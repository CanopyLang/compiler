{-# LANGUAGE OverloadedStrings #-}

-- | Module discovery and transitive dependency resolution.
--
-- Provides functions for finding Canopy source files on disk,
-- parsing them to extract import lists, and recursively discovering
-- all transitive dependencies needed for compilation.
--
-- The discovery algorithm uses parallel BFS traversal: each frontier
-- of newly-discovered imports is resolved and parsed concurrently
-- using bounded parallelism ('QSem'). A concurrent 'PathCache'
-- eliminates redundant filesystem lookups when multiple modules
-- import the same dependency.
--
-- @since 0.19.1
module Compiler.Discovery
  ( -- * Transitive Discovery
    discoverTransitiveDeps,

    -- * Error Types
    DiscoveryError (..),

    -- * Import Extraction
    extractImports,

    -- * Path Resolution
    findModulePath,
    findModuleInDirs,
    discoverModulePaths,
    moduleNameToBasePath,

    -- * Source Reading
    readSourceWithLimit,

    -- * Utilities
    splitOn,
  )
where

import qualified AST.Source as Src
import Compiler.Types (SrcDir (..), srcDirToString)
import qualified Canopy.Interface as Interface
import qualified Canopy.Limits as Limits
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Data.Name as Name
import qualified Control.Concurrent.Async as Async
import qualified Control.Concurrent.QSem as QSem
import qualified Control.Exception as Exception
import qualified Control.Monad as Monad
import qualified Data.ByteString as BS
import qualified Data.Either as Either
import Data.IORef (IORef)
import qualified Data.IORef as IORef
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified GHC.Conc as Conc
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as Ann
import qualified System.Directory as Dir
import System.FilePath ((</>), normalise)

-- | Errors that can occur during module discovery.
--
-- These represent user-facing errors (e.g., syntax errors in imported files)
-- rather than internal compiler bugs. Discovery propagates them as 'Left'
-- values so callers can report them with source location context.
--
-- @since 0.19.2
data DiscoveryError
  = -- | A source file failed to parse during import discovery.
    -- Contains the file path and a textual description of the parse error.
    DiscoveryParseError !FilePath !Text.Text
  deriving (Eq, Show)

-- CONCURRENT PATH CACHE

-- | Thread-safe cache for module path resolution.
--
-- Prevents duplicate filesystem lookups when multiple modules import
-- the same dependency. Uses 'atomicModifyIORef'' for safe concurrent
-- access from parallel discovery workers.
--
-- @since 0.19.2
type PathCache = IORef (Map.Map ModuleName.Raw (Maybe FilePath))

-- | Look up a module path, consulting the cache first.
--
-- If the module is not yet cached, performs the filesystem lookup
-- and atomically stores the result. Concurrent lookups for the same
-- module may both perform the filesystem check, but the cache will
-- converge to the same value, so this is safe without locking.
--
-- @since 0.19.2
lookupCachedPath ::
  PathCache ->
  FilePath ->
  [SrcDir] ->
  ModuleName.Raw ->
  IO (Maybe FilePath)
lookupCachedPath cache root srcDirs modName = do
  cached <- Map.lookup modName <$> IORef.readIORef cache
  maybe performLookup pure cached
  where
    performLookup = do
      result <- findModulePath root srcDirs modName
      IORef.atomicModifyIORef' cache (\m -> (Map.insert modName result m, ()))
      pure result

-- TRANSITIVE DISCOVERY

-- | Discover transitive dependencies using parallel BFS.
--
-- Parses the initial entry-point files, then iteratively discovers
-- imported modules in parallel batches. Each BFS level is processed
-- concurrently, with bounded parallelism controlled by a semaphore
-- sized to the number of runtime capabilities.
--
-- Returns a map from module name to (file path, import list) for
-- every discovered module. This avoids a redundant re-parse when
-- building the dependency graph for parallel compilation.
--
-- @since 0.19.1
discoverTransitiveDeps ::
  FilePath ->
  [SrcDir] ->
  [FilePath] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Parse.ProjectType ->
  IO (Either DiscoveryError (Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw])))
discoverTransitiveDeps root srcDirs initialPaths depInterfaces projectType = do
  Log.logEvent (BuildStarted (Text.pack ("discoverTransitiveDeps: " ++ root)))
  numCaps <- Conc.getNumCapabilities
  sem <- QSem.newQSem (max 1 numCaps)
  pathCache <- IORef.newIORef Map.empty
  initialResults <- Async.mapConcurrently (withSemaphore sem . parseModuleFile projectType) initialPaths
  case Either.partitionEithers initialResults of
    (err : _, _) -> return (Left err)
    ([], initialModules) -> do
      Log.logEvent (BuildModuleQueued (Text.pack ("parsed " ++ show (length initialModules) ++ " initial modules")))
      let initialMap = buildInitialMap initialModules initialPaths
          frontier = collectFrontier initialMap depInterfaces initialModules
      result <- discoverBfsParallel sem pathCache root srcDirs initialMap depInterfaces projectType frontier
      logDiscoveryResult result
      return result

-- | Build the initial module map from parsed modules and their file paths.
--
-- @since 0.19.2
buildInitialMap ::
  [Src.Module] ->
  [FilePath] ->
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw])
buildInitialMap modules paths =
  Map.fromList [(Src.getName m, (p, extractImports m)) | (m, p) <- zip modules paths]

-- | Collect the initial frontier of undiscovered imports.
--
-- Gathers all imports from the initial modules that are not already
-- in the found map or the dependency interfaces, deduplicating them
-- into a 'Set'.
--
-- @since 0.19.2
collectFrontier ::
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  Map.Map ModuleName.Raw Interface.Interface ->
  [Src.Module] ->
  Set.Set ModuleName.Raw
collectFrontier found depInterfaces modules =
  Set.fromList (filter isNew allImports)
  where
    allImports = concatMap extractImports modules
    isNew imp = not (Map.member imp found) && not (Map.member imp depInterfaces)

-- | Log the final discovery result.
--
-- @since 0.19.2
logDiscoveryResult ::
  Either DiscoveryError (Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw])) ->
  IO ()
logDiscoveryResult (Left _) = pure ()
logDiscoveryResult (Right allModules) =
  Log.logEvent (BuildModuleQueued (Text.pack ("discovered " ++ show (Map.size allModules) ++ " modules total")))

-- PARALLEL BFS DISCOVERY

-- | Parallel BFS loop for module discovery.
--
-- Each iteration processes the current frontier of undiscovered modules
-- in parallel. For each module, the path is resolved (with caching),
-- the file is parsed, and imports are extracted. New imports that have
-- not been seen before form the next frontier.
--
-- Terminates when the frontier is empty (all transitive dependencies
-- discovered) or when any module fails to parse.
--
-- @since 0.19.2
discoverBfsParallel ::
  QSem.QSem ->
  PathCache ->
  FilePath ->
  [SrcDir] ->
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Parse.ProjectType ->
  Set.Set ModuleName.Raw ->
  IO (Either DiscoveryError (Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw])))
discoverBfsParallel _ _ _ _ found _ _ frontier
  | Set.null frontier = return (Right found)
discoverBfsParallel sem pathCache root srcDirs found depInterfaces projectType frontier = do
  let frontierList = Set.toList frontier
  Log.logEvent (BuildModuleQueued (Text.pack ("BFS level: " ++ show (length frontierList) ++ " modules")))
  results <- Async.mapConcurrently (withSemaphore sem . discoverOneParallel pathCache root srcDirs projectType) frontierList
  case Either.partitionEithers results of
    (err : _, _) -> return (Left err)
    ([], discoveries) -> do
      let newFound = foldr insertDiscovery found discoveries
          newFrontier = collectNewFrontier newFound depInterfaces discoveries
      discoverBfsParallel sem pathCache root srcDirs newFound depInterfaces projectType newFrontier

-- | Discover a single module during parallel BFS.
--
-- Resolves the file path using the shared cache, reads and parses
-- the source file, and extracts its import list. Returns 'Nothing'
-- for the path if the module cannot be found on disk (silently
-- skipped -- it may be a kernel or dependency module).
--
-- @since 0.19.2
discoverOneParallel ::
  PathCache ->
  FilePath ->
  [SrcDir] ->
  Parse.ProjectType ->
  ModuleName.Raw ->
  IO (Either DiscoveryError (ModuleName.Raw, Maybe (FilePath, [ModuleName.Raw])))
discoverOneParallel pathCache root srcDirs projectType modName = do
  maybePath <- lookupCachedPath pathCache root srcDirs modName
  maybe (pure (Right (modName, Nothing))) (resolveAndParse modName projectType) maybePath

-- | Resolve a module path and parse its source to extract imports.
--
-- @since 0.19.2
resolveAndParse ::
  ModuleName.Raw ->
  Parse.ProjectType ->
  FilePath ->
  IO (Either DiscoveryError (ModuleName.Raw, Maybe (FilePath, [ModuleName.Raw])))
resolveAndParse modName projectType path = do
  content <- readSourceWithLimit path
  pure (either
    (Left . mkParseError path)
    (\m -> Right (modName, Just (path, extractImports m)))
    (Parse.fromByteString projectType content))

-- | Insert a discovery result into the found map.
--
-- Modules that were not found on disk (Nothing) are silently skipped.
--
-- @since 0.19.2
insertDiscovery ::
  (ModuleName.Raw, Maybe (FilePath, [ModuleName.Raw])) ->
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw])
insertDiscovery (_, Nothing) acc = acc
insertDiscovery (modName, Just entry) acc = Map.insert modName entry acc

-- | Collect the next BFS frontier from discovery results.
--
-- Gathers all imports from newly-discovered modules that are not
-- yet in the found map, not in dependency interfaces, and not
-- modules that failed to resolve (which are tracked as visited).
--
-- @since 0.19.2
collectNewFrontier ::
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  Map.Map ModuleName.Raw Interface.Interface ->
  [(ModuleName.Raw, Maybe (FilePath, [ModuleName.Raw]))] ->
  Set.Set ModuleName.Raw
collectNewFrontier found depInterfaces discoveries =
  Set.fromList (filter isNew allNewImports)
  where
    allNewImports = concatMap importsFromDiscovery discoveries
    visitedNotFound = Set.fromList [n | (n, Nothing) <- discoveries]
    isNew imp =
      not (Map.member imp found)
        && not (Map.member imp depInterfaces)
        && not (Set.member imp visitedNotFound)
    importsFromDiscovery (_, Nothing) = []
    importsFromDiscovery (_, Just (_, imports)) = imports

-- | Parse a single source file for discovery purposes.
--
-- Returns 'Left' with a structured error on parse failure instead of
-- crashing via 'InternalError.report'. This allows the build pipeline
-- to surface user-friendly parse errors with source locations.
--
-- @since 0.19.2
parseModuleFile :: Parse.ProjectType -> FilePath -> IO (Either DiscoveryError Src.Module)
parseModuleFile projType path = do
  content <- readSourceWithLimit path
  pure (either (Left . mkParseError path) Right (Parse.fromByteString projType content))

-- | Construct a 'DiscoveryParseError' from a file path and parse error.
mkParseError :: (Show e) => FilePath -> e -> DiscoveryError
mkParseError path err = DiscoveryParseError path (Text.pack (show err))

-- IMPORT EXTRACTION

-- | Extract import names from a parsed module.
--
-- Returns the raw module names of all imports declared in the module
-- header. These are used to build the dependency graph for parallel
-- compilation ordering.
extractImports :: Src.Module -> [ModuleName.Raw]
extractImports modul =
  [Ann.toValue (Src._importName imp) | imp <- Src._imports modul]

-- SOURCE READING

-- | Read a source file with a size limit check.
--
-- Checks the file size on disk against 'Limits.maxSourceFileBytes'
-- before reading. This prevents out-of-memory conditions when
-- encountering accidentally-huge or malicious source files.
--
-- @since 0.19.2
readSourceWithLimit :: FilePath -> IO BS.ByteString
readSourceWithLimit path = do
  size <- Dir.getFileSize path
  enforceSourceLimit path (fromIntegral size)
  BS.readFile path

-- | Enforce the source file size limit.
--
-- @since 0.19.2
enforceSourceLimit :: FilePath -> Int -> IO ()
enforceSourceLimit path size =
  case Limits.checkFileSize path size Limits.maxSourceFileBytes of
    Nothing -> pure ()
    Just (Limits.FileSizeError fp actual limit) ->
      ioError (userError (fileTooLargeMessage fp actual limit))

-- | Format a file-too-large error message for source files.
--
-- @since 0.19.2
fileTooLargeMessage :: FilePath -> Int -> Int -> String
fileTooLargeMessage path actual limit =
  "FILE TOO LARGE -- " ++ path ++ "\n\n"
    ++ "    This source file is " ++ showMB actual
    ++ ", which exceeds the " ++ showMB limit ++ " limit.\n\n"
    ++ "    Consider splitting it into smaller modules.\n"
  where
    showMB bytes = show (bytes `div` (1024 * 1024)) ++ " MB"

-- PATH RESOLUTION

-- | Find the file path for a module given search directories.
--
-- Searches each source directory for files with @.can@ or @.elm@
-- extension matching the module name. Returns the first match found.
findModulePath :: FilePath -> [SrcDir] -> ModuleName.Raw -> IO (Maybe FilePath)
findModulePath root srcDirs modName = do
  paths <- findModuleInDirs root srcDirs modName
  pure (case paths of
          [] -> Nothing
          (p:_) -> Just p)

-- | Find all file paths for a module across all source directories.
--
-- Returns all matching paths (both @.can@ and @.elm@ extensions)
-- across all configured source directories.
findModuleInDirs :: FilePath -> [SrcDir] -> ModuleName.Raw -> IO [FilePath]
findModuleInDirs root srcDirs moduleName = do
  let basePath = moduleNameToBasePath moduleName
      candidates = concatMap (buildCandidates root basePath) srcDirs
  Monad.filterM Dir.doesFileExist candidates
  where
    buildCandidates :: FilePath -> FilePath -> SrcDir -> [FilePath]
    buildCandidates projectRoot base srcDir =
      let dirPath = normalise (projectRoot </> srcDirToString srcDir)
       in [ dirPath </> base ++ ".can"
          , dirPath </> base ++ ".elm"
          ]

-- | Discover file paths for a list of module names.
--
-- Searches all source directories for each module, returning
-- all found paths concatenated.
discoverModulePaths :: FilePath -> [SrcDir] -> [ModuleName.Raw] -> IO [FilePath]
discoverModulePaths root srcDirs moduleNames =
  concat <$> mapM (findModuleInDirs root srcDirs) moduleNames

-- | Convert a dotted module name to a file system base path.
--
-- For example, @"Data.List"@ becomes @"Data/List"@ (without extension).
moduleNameToBasePath :: ModuleName.Raw -> FilePath
moduleNameToBasePath moduleName =
  let nameStr = Name.toChars moduleName
      parts = splitOn '.' nameStr
   in foldr1 (</>) parts

-- CONCURRENCY HELPERS

-- | Bound an IO action with a semaphore for concurrency control.
--
-- Acquires the semaphore before running the action and releases it
-- afterward, even if the action throws an exception.
--
-- @since 0.19.2
withSemaphore :: QSem.QSem -> IO a -> IO a
withSemaphore sem = Exception.bracket_ (QSem.waitQSem sem) (QSem.signalQSem sem)

-- UTILITIES

-- | Split a string on a delimiter character.
--
-- @splitOn '.' "Data.List.Extra"@ returns @["Data", "List", "Extra"]@.
splitOn :: Char -> String -> [String]
splitOn _ "" = []
splitOn c s =
  let (chunk, rest) = break (== c) s
   in chunk : case rest of
        [] -> []
        (_:rest') -> splitOn c rest'

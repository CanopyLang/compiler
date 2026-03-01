{-# LANGUAGE OverloadedStrings #-}

-- | Module discovery and transitive dependency resolution.
--
-- Provides functions for finding Canopy source files on disk,
-- parsing them to extract import lists, and recursively discovering
-- all transitive dependencies needed for compilation.
--
-- The discovery algorithm uses DFS traversal (prepend new modules)
-- instead of BFS (append) to avoid O(N) list append per step.
-- Already-resolved paths are reused to eliminate redundant file
-- system lookups.
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
import Control.Monad (filterM)
import qualified Data.ByteString as BS
import Data.Either (partitionEithers)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
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

-- TRANSITIVE DISCOVERY

-- | Discover transitive dependencies, returning both file paths and
-- pre-computed import lists.
--
-- This avoids a redundant re-parse when building the dependency
-- graph for parallel compilation. Starting from the given initial
-- file paths, recursively discovers all imported modules.
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
  initialResults <- mapM (parseModuleFile projectType) initialPaths
  case partitionEithers initialResults of
    (err : _, _) -> return (Left err)
    ([], initialModules) -> do
      Log.logEvent (BuildModuleQueued (Text.pack ("parsed " ++ show (length initialModules) ++ " initial modules")))
      let initialMap = Map.fromList [(Src.getName m, (p, extractImports m)) | (m, p) <- zip initialModules initialPaths]
      result <- discoverImports root srcDirs initialMap Set.empty initialModules depInterfaces projectType
      case result of
        Left err -> return (Left err)
        Right allModules -> do
          Log.logEvent (BuildModuleQueued (Text.pack ("discovered " ++ show (Map.size allModules) ++ " modules total")))
          return (Right allModules)

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

-- RECURSIVE IMPORT DISCOVERY

-- | Recursively discover imports using DFS traversal.
--
-- Uses DFS order (prepend new modules) instead of BFS (append) to avoid
-- O(N) list append per step. Also reuses already-resolved paths to
-- eliminate redundant file system lookups. Returns 'Left' on the first
-- parse error encountered.
--
-- @since 0.19.2
discoverImports ::
  FilePath ->
  [SrcDir] ->
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  Set.Set ModuleName.Raw ->
  [Src.Module] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Parse.ProjectType ->
  IO (Either DiscoveryError (Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw])))
discoverImports root srcDirs found visited modules depInterfaces projectType =
  case modules of
    [] -> do
      Log.logEvent (BuildModuleQueued (Text.pack ("discoverImports complete: " ++ show (Map.size found) ++ " modules")))
      return (Right found)
    (modul : rest) ->
      discoverOneModule root srcDirs found visited modul rest depInterfaces projectType

-- | Process a single module during DFS import discovery.
--
-- @since 0.19.2
discoverOneModule ::
  FilePath ->
  [SrcDir] ->
  Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]) ->
  Set.Set ModuleName.Raw ->
  Src.Module ->
  [Src.Module] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Parse.ProjectType ->
  IO (Either DiscoveryError (Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw])))
discoverOneModule root srcDirs found visited modul rest depInterfaces projectType
  | Set.member modName visited || Map.member modName depInterfaces =
      discoverImports root srcDirs found (Set.insert modName visited) rest depInterfaces projectType
  | otherwise = do
      let imports = extractImports modul
          newImports = filter (\imp -> not (Map.member imp found) && not (Map.member imp depInterfaces)) imports
      newPaths <- mapM (findModulePath root srcDirs) newImports
      let validPairs = [(imp, path) | (Just path, imp) <- zip newPaths newImports]
          newFound = foldr (\(imp, path) m -> Map.insert imp (path, []) m) found validPairs
      newResults <- mapM (parseModuleAtPath projectType) validPairs
      case partitionEithers newResults of
        (err : _, _) -> return (Left err)
        ([], newModules) -> do
          let newFoundWithImports = foldr backfillImports newFound newModules
          discoverImports root srcDirs newFoundWithImports (Set.insert modName visited) (newModules ++ rest) depInterfaces projectType
  where
    modName = Src.getName modul
    backfillImports nm acc = Map.adjust (\(p, _) -> (p, extractImports nm)) (Src.getName nm) acc

-- | Parse a module at a known file path.
--
-- Unlike 'findModulePath' + parse, this skips path resolution since the
-- caller already resolved the path during import discovery. Returns
-- 'Left' on parse failure for graceful error propagation.
--
-- @since 0.19.2
parseModuleAtPath :: Parse.ProjectType -> (ModuleName.Raw, FilePath) -> IO (Either DiscoveryError Src.Module)
parseModuleAtPath projectType (_modName, path) = do
  content <- readSourceWithLimit path
  pure (either (Left . mkParseError path) Right (Parse.fromByteString projectType content))

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
  return (case paths of
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
  filterM Dir.doesFileExist candidates
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

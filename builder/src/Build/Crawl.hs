{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module crawling functionality for the Build system.
--
-- This module handles the crawling and discovery of modules, decomposing
-- the complex crawlModule function into focused components that comply
-- with CLAUDE.md standards.
module Build.Crawl
  ( -- * Main Functions
    crawlModule
  , crawlFile
  , crawlDeps
  , crawlRoot
  
  -- * File Discovery
  , findModuleFile
    
  -- * Helper Functions
  , processModulePaths
  , processForeignModule
  , processKernelModule
  , validateModuleName
  , createSinglePathConfig
  , createLocalPathConfig
  , createValidationConfig
  , fork
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (MVar, takeMVar, putMVar, newEmptyMVar, readMVar)
import Control.Lens ((^.), makeLenses)
import Control.Monad (filterM)
import Data.Foldable (traverse_)
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString as B
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Name as Name
import qualified File
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Import as Import
import qualified Reporting.Error.Syntax as Syntax
import qualified Reporting.Error as Error
import System.FilePath ((<.>), (</>))
import qualified System.FilePath as FP

import Build.Config (CrawlConfig (..), crawlEnv, crawlMVar, crawlDocsNeed)
import Build.Types
  ( Env (..)
  , AbsoluteSrcDir (..)
  , Status (..)
  , StatusDict
  , DocsNeed (..)
  , RootLocation (..)
  , RootStatus (..)
  )

-- | Configuration for processing module paths.
data ProcessPathConfig = ProcessPathConfig
  { _pathConfigEnv :: !Env
  , _pathConfigMVar :: !(MVar StatusDict)
  , _pathConfigDocsNeed :: !DocsNeed
  , _pathConfigName :: !ModuleName.Raw
  , _pathConfigPaths :: ![FilePath]
  , _pathConfigRoot :: !FilePath
  , _pathConfigProjectType :: !Parse.ProjectType
  , _pathConfigBuildID :: !Details.BuildID
  , _pathConfigLocals :: !(Map ModuleName.Raw Details.Local)
  , _pathConfigForeigns :: !(Map ModuleName.Raw Details.Foreign)
  }

-- | Configuration for single path processing.
data SinglePathConfig = SinglePathConfig
  { _singlePathEnv :: !Env
  , _singlePathMVar :: !(MVar StatusDict)
  , _singlePathDocsNeed :: !DocsNeed
  , _singlePathName :: !ModuleName.Raw
  , _singlePathPath :: !FilePath
  , _singlePathBuildID :: !Details.BuildID
  , _singlePathLocals :: !(Map ModuleName.Raw Details.Local)
  , _singlePathForeigns :: !(Map ModuleName.Raw Details.Foreign)
  }

-- | Configuration for local path processing.
data LocalPathConfig = LocalPathConfig
  { _localPathEnv :: !Env
  , _localPathMVar :: !(MVar StatusDict)
  , _localPathDocsNeed :: !DocsNeed
  , _localPathName :: !ModuleName.Raw
  , _localPathPath :: !FilePath
  , _localPathBuildID :: !Details.BuildID
  , _localPathLocals :: !(Map ModuleName.Raw Details.Local)
  }

-- | Configuration for parsing and validation.
data ParseConfig = ParseConfig
  { _parseConfigEnv :: !Env
  , _parseConfigMVar :: !(MVar StatusDict)
  , _parseConfigDocsNeed :: !DocsNeed
  , _parseConfigExpectedName :: !ModuleName.Raw
  , _parseConfigPath :: !FilePath
  , _parseConfigTime :: !File.Time
  , _parseConfigSource :: !B.ByteString
  , _parseConfigProjectType :: !Parse.ProjectType
  , _parseConfigBuildID :: !Details.BuildID
  , _parseConfigLastChange :: !Details.BuildID
  }

-- | Configuration for module validation.
data ValidationConfig = ValidationConfig
  { _validationConfigEnv :: !Env
  , _validationConfigMVar :: !(MVar StatusDict)
  , _validationConfigDocsNeed :: !DocsNeed
  , _validationConfigExpectedName :: !ModuleName.Raw
  , _validationConfigActualName :: !ModuleName.Raw
  , _validationConfigPath :: !FilePath
  , _validationConfigTime :: !File.Time
  , _validationConfigSource :: !B.ByteString
  , _validationConfigImports :: ![Src.Import]
  , _validationConfigValues :: ![A.Located Src.Value]
  , _validationConfigBuildID :: !Details.BuildID
  , _validationConfigLastChange :: !Details.BuildID
  , _validationConfigName :: !(A.Located ModuleName.Raw)
  }

-- Generate lenses for configuration records
makeLenses ''ProcessPathConfig
makeLenses ''SinglePathConfig  
makeLenses ''LocalPathConfig
makeLenses ''ParseConfig
makeLenses ''ValidationConfig

-- | Crawl a module using configuration record.
crawlModule :: CrawlConfig -> ModuleName.Raw -> IO Status
crawlModule config name = do
  let env = config ^. crawlEnv
  let mvar = config ^. crawlMVar
  let docsNeed = config ^. crawlDocsNeed
  processModuleDiscovery env mvar docsNeed name

-- | Process module discovery with path resolution.
processModuleDiscovery :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> IO Status
processModuleDiscovery env@(Env _ root projectType srcDirs buildID locals foreigns) mvar docsNeed name = do
  let baseName = ModuleName.toFilePath name
  paths <- findModuleFile srcDirs baseName
  let config = ProcessPathConfig env mvar docsNeed name paths root projectType buildID locals foreigns
  processModulePaths config

-- | Create single path configuration from process path configuration.
createSinglePathConfig :: ProcessPathConfig -> FilePath -> SinglePathConfig
createSinglePathConfig cfg path = SinglePathConfig
  { _singlePathEnv = cfg ^. pathConfigEnv
  , _singlePathMVar = cfg ^. pathConfigMVar
  , _singlePathDocsNeed = cfg ^. pathConfigDocsNeed
  , _singlePathName = cfg ^. pathConfigName
  , _singlePathPath = path
  , _singlePathBuildID = cfg ^. pathConfigBuildID
  , _singlePathLocals = cfg ^. pathConfigLocals
  , _singlePathForeigns = cfg ^. pathConfigForeigns
  }

-- | Process discovered module paths.
processModulePaths :: ProcessPathConfig -> IO Status
processModulePaths config =
  case config ^. pathConfigPaths of
    [path] -> processSinglePath (createSinglePathConfig config path)
    p1 : p2 : ps -> processAmbiguousPaths (config ^. pathConfigRoot) p1 p2 ps
    [] -> processNoPath (config ^. pathConfigName) (config ^. pathConfigProjectType) (config ^. pathConfigForeigns)

-- | Create local path configuration from single path configuration.
createLocalPathConfig :: SinglePathConfig -> LocalPathConfig
createLocalPathConfig cfg = LocalPathConfig
  { _localPathEnv = cfg ^. singlePathEnv
  , _localPathMVar = cfg ^. singlePathMVar
  , _localPathDocsNeed = cfg ^. singlePathDocsNeed
  , _localPathName = cfg ^. singlePathName
  , _localPathPath = cfg ^. singlePathPath
  , _localPathBuildID = cfg ^. singlePathBuildID
  , _localPathLocals = cfg ^. singlePathLocals
  }

-- | Process single discovered path.
processSinglePath :: SinglePathConfig -> IO Status
processSinglePath config =
  case Map.lookup (config ^. singlePathName) (config ^. singlePathForeigns) of
    Just (Details.Foreign dep deps) -> pure . SBadImport $ Import.Ambiguous (config ^. singlePathPath) [] dep deps
    Nothing -> processLocalPath (createLocalPathConfig config)

-- | Process local module path.
processLocalPath :: LocalPathConfig -> IO Status
processLocalPath config = do
  newTime <- File.getTime (config ^. localPathPath)
  case Map.lookup (config ^. localPathName) (config ^. localPathLocals) of
    Nothing -> crawlFile (config ^. localPathEnv) (config ^. localPathMVar) (config ^. localPathDocsNeed) (config ^. localPathName) (config ^. localPathPath) newTime (config ^. localPathBuildID)
    Just local -> processExistingLocal (config ^. localPathEnv) (config ^. localPathMVar) (config ^. localPathDocsNeed) (config ^. localPathName) (config ^. localPathPath) newTime local

-- | Process existing local module.
processExistingLocal :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> FilePath -> File.Time -> Details.Local -> IO Status
processExistingLocal env mvar docsNeed name path newTime local@(Details.Local oldPath oldTime deps _ lastChange _) =
  if shouldRecrawl path newTime oldPath oldTime docsNeed
    then crawlFile env mvar docsNeed name path newTime lastChange
    else crawlDeps env mvar deps (SCached local)

-- | Check if module should be recrawled.
shouldRecrawl :: FilePath -> File.Time -> FilePath -> File.Time -> DocsNeed -> Bool
shouldRecrawl path newTime oldPath oldTime docsNeed =
  path /= oldPath || oldTime /= newTime || needsDocs docsNeed

-- | Process ambiguous module paths.
processAmbiguousPaths :: FilePath -> FilePath -> FilePath -> [FilePath] -> IO Status
processAmbiguousPaths root p1 p2 ps =
  pure . SBadImport $ Import.AmbiguousLocal 
    (FP.makeRelative root p1) 
    (FP.makeRelative root p2) 
    (fmap (FP.makeRelative root) ps)

-- | Process case where no module path found.
processNoPath :: ModuleName.Raw -> Parse.ProjectType -> Map ModuleName.Raw Details.Foreign -> IO Status
processNoPath name projectType foreigns =
  case Map.lookup name foreigns of
    Just (Details.Foreign dep deps) -> processForeignModule dep deps
    Nothing -> processKernelModule name projectType

-- | Process foreign module dependency.
processForeignModule :: Pkg.Name -> [Pkg.Name] -> IO Status
processForeignModule dep deps =
  case deps of
    [] -> pure $ SForeign dep
    d : ds -> pure . SBadImport $ Import.AmbiguousForeign dep d ds

-- | Process potential kernel module.
processKernelModule :: ModuleName.Raw -> Parse.ProjectType -> IO Status
processKernelModule name projectType =
  if Name.isKernel name && Parse.isKernel projectType
    then checkKernelExists name
    else pure $ SBadImport Import.NotFound

-- | Check if kernel module exists.
checkKernelExists :: ModuleName.Raw -> IO Status
checkKernelExists name = do
  exists <- File.exists ("src" </> ModuleName.toFilePath name <.> "js")
  pure $ if exists then SKernel else SBadImport Import.NotFound

-- | Find module file with extension priority.
findModuleFile :: [AbsoluteSrcDir] -> FilePath -> IO [FilePath]
findModuleFile srcDirs baseName = do
  canPaths <- findFilesWithExtension srcDirs baseName "can"
  case canPaths of
    [] -> findCanopyOrElm srcDirs baseName
    _ -> pure canPaths

-- | Find .canopy or .elm files.
findCanopyOrElm :: [AbsoluteSrcDir] -> FilePath -> IO [FilePath]
findCanopyOrElm srcDirs baseName = do
  canopyPaths <- findFilesWithExtension srcDirs baseName "canopy"
  case canopyPaths of
    [] -> findFilesWithExtension srcDirs baseName "elm"
    _ -> pure canopyPaths

-- | Find files with specific extension.
findFilesWithExtension :: [AbsoluteSrcDir] -> FilePath -> String -> IO [FilePath]
findFilesWithExtension srcDirs baseName ext =
  filterM File.exists (fmap (`addRelative` (baseName <.> ext)) srcDirs)

-- | Add relative path to source directory.
addRelative :: AbsoluteSrcDir -> FilePath -> FilePath
addRelative (AbsoluteSrcDir srcDir) path = srcDir </> path

-- | Crawl dependencies for a module.
crawlDeps :: Env -> MVar StatusDict -> [ModuleName.Raw] -> a -> IO a
crawlDeps env mvar deps blockedValue = do
  statusDict <- takeMVar mvar
  let depsDict = Map.fromSet (const ()) (Set.fromList deps)
  let newsDict = Map.difference depsDict statusDict
  statuses <- Map.traverseWithKey (crawlNewDep env mvar) newsDict
  putMVar mvar (Map.union statuses statusDict)
  traverse_ readMVar statuses
  pure blockedValue

-- | Crawl a new dependency.
crawlNewDep :: Env -> MVar StatusDict -> ModuleName.Raw -> () -> IO (MVar Status)
crawlNewDep env mvar name () = fork (crawlModule (CrawlConfig env mvar (DocsNeed False)) name)

-- | Crawl file with validation.
crawlFile :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> FilePath -> File.Time -> Details.BuildID -> IO Status
crawlFile env@(Env _ root projectType _ buildID _ _) mvar docsNeed expectedName path time lastChange = do
  source <- File.readUtf8 (root </> path)
  let config = ParseConfig env mvar docsNeed expectedName path time source projectType buildID lastChange
  parseAndValidate config

-- | Parse and validate module source.
parseAndValidate :: ParseConfig -> IO Status
parseAndValidate config =
  case Parse.fromByteString (config ^. parseConfigProjectType) (config ^. parseConfigSource) of
    Left err -> pure $ SBadSyntax (config ^. parseConfigPath) (config ^. parseConfigTime) (config ^. parseConfigSource) err
    Right modul -> validateAndProcess config modul

-- | Create validation configuration from parse configuration.
createValidationConfig :: ParseConfig -> ModuleName.Raw -> [Src.Import] -> [A.Located Src.Value] -> A.Located ModuleName.Raw -> ValidationConfig
createValidationConfig cfg actualName imports values name = ValidationConfig
  { _validationConfigEnv = cfg ^. parseConfigEnv
  , _validationConfigMVar = cfg ^. parseConfigMVar
  , _validationConfigDocsNeed = cfg ^. parseConfigDocsNeed
  , _validationConfigExpectedName = cfg ^. parseConfigExpectedName
  , _validationConfigActualName = actualName
  , _validationConfigPath = cfg ^. parseConfigPath
  , _validationConfigTime = cfg ^. parseConfigTime
  , _validationConfigSource = cfg ^. parseConfigSource
  , _validationConfigImports = imports
  , _validationConfigValues = values
  , _validationConfigBuildID = cfg ^. parseConfigBuildID
  , _validationConfigLastChange = cfg ^. parseConfigLastChange
  , _validationConfigName = name
  }

-- | Validate module name and process.
validateAndProcess :: ParseConfig -> Src.Module -> IO Status
validateAndProcess config (Src.Module maybeActualName _ _ imports values _ _ _ _) =
  case maybeActualName of
    Nothing -> pure $ SBadSyntax (config ^. parseConfigPath) (config ^. parseConfigTime) (config ^. parseConfigSource) (Syntax.ModuleNameUnspecified (config ^. parseConfigExpectedName))
    Just name@(A.At _ actualName) -> validateModuleName (createValidationConfig config actualName imports values name)

-- | Validate module name matches expected.
validateModuleName :: ValidationConfig -> IO Status
validateModuleName config =
  if config ^. validationConfigExpectedName == config ^. validationConfigActualName
    then processValidModule config
    else pure $ SBadSyntax (config ^. validationConfigPath) (config ^. validationConfigTime) (config ^. validationConfigSource) (Syntax.ModuleNameMismatch (config ^. validationConfigExpectedName) (config ^. validationConfigName))

-- | Process valid module.
processValidModule :: ValidationConfig -> IO Status
processValidModule config = do
  let deps = fmap Src.getImportName (config ^. validationConfigImports)
  let local = Details.Local (config ^. validationConfigPath) (config ^. validationConfigTime) deps (any isMain (config ^. validationConfigValues)) (config ^. validationConfigLastChange) (config ^. validationConfigBuildID)
  crawlDeps (config ^. validationConfigEnv) (config ^. validationConfigMVar) deps (SChanged local (config ^. validationConfigSource) undefined (config ^. validationConfigDocsNeed))

-- | Check if value is main function.
isMain :: A.Located Src.Value -> Bool
isMain (A.At _ (Src.Value (A.At _ name) _ _ _)) = name == Name._main

-- | Crawl root module.
crawlRoot :: Env -> MVar StatusDict -> RootLocation -> IO RootStatus
crawlRoot env@(Env _ _ projectType _ buildID _ _) mvar root =
  case root of
    LInside name -> crawlInsideRoot env mvar name
    LOutside path -> crawlOutsideRoot env mvar projectType path buildID

-- | Crawl inside root module.
crawlInsideRoot :: Env -> MVar StatusDict -> ModuleName.Raw -> IO RootStatus
crawlInsideRoot env mvar name = do
  statusMVar <- newEmptyMVar
  statusDict <- takeMVar mvar
  putMVar mvar (Map.insert name statusMVar statusDict)
  crawlModule (CrawlConfig env mvar (DocsNeed False)) name >>= putMVar statusMVar
  pure (SInside name)

-- | Crawl outside root module.
crawlOutsideRoot :: Env -> MVar StatusDict -> Parse.ProjectType -> FilePath -> Details.BuildID -> IO RootStatus
crawlOutsideRoot env mvar projectType path buildID = do
  time <- File.getTime path
  source <- File.readUtf8 path
  parseRootModule env mvar projectType path time source buildID

-- | Parse root module source.
parseRootModule :: Env -> MVar StatusDict -> Parse.ProjectType -> FilePath -> File.Time -> B.ByteString -> Details.BuildID -> IO RootStatus
parseRootModule env mvar projectType path time source buildID =
  case Parse.fromByteString projectType source of
    Right modul@(Src.Module _ _ _ imports values _ _ _ _) -> processRootModule env mvar path time source imports values buildID modul
    Left syntaxError -> pure . SOutsideErr $ Error.Module "???" path time source (Error.BadSyntax syntaxError)
  where
    processRootModule e m p t s imports values bID modul = do
      let deps = fmap Src.getImportName imports
      let local = Details.Local p t deps (any isMain values) bID bID
      crawlDeps e m deps (SOutsideOk local s modul)

-- | Fork an IO operation.
fork :: IO a -> IO (MVar a)
fork work = do
  mvar <- newEmptyMVar
  _ <- forkIO $ work >>= putMVar mvar
  pure mvar
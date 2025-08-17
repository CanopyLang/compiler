{-# LANGUAGE OverloadedStrings #-}
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
  , fork
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (MVar, takeMVar, putMVar, newEmptyMVar, readMVar)
import Control.Lens ((^.))
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
  processModulePaths env mvar docsNeed name paths root projectType buildID locals foreigns

-- | Process discovered module paths.
processModulePaths :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> [FilePath] -> FilePath -> Parse.ProjectType -> Details.BuildID -> Map ModuleName.Raw Details.Local -> Map ModuleName.Raw Details.Foreign -> IO Status
processModulePaths env mvar docsNeed name paths root projectType buildID locals foreigns =
  case paths of
    [path] -> processSinglePath env mvar docsNeed name path root buildID locals foreigns
    p1 : p2 : ps -> processAmbiguousPaths root p1 p2 ps
    [] -> processNoPath name projectType foreigns

-- | Process single discovered path.
processSinglePath :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> FilePath -> FilePath -> Details.BuildID -> Map ModuleName.Raw Details.Local -> Map ModuleName.Raw Details.Foreign -> IO Status
processSinglePath env mvar docsNeed name path root buildID locals foreigns =
  case Map.lookup name foreigns of
    Just (Details.Foreign dep deps) -> pure . SBadImport $ Import.Ambiguous path [] dep deps
    Nothing -> processLocalPath env mvar docsNeed name path root buildID locals

-- | Process local module path.
processLocalPath :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> FilePath -> FilePath -> Details.BuildID -> Map ModuleName.Raw Details.Local -> IO Status
processLocalPath env mvar docsNeed name path _root buildID locals = do
  newTime <- File.getTime path
  case Map.lookup name locals of
    Nothing -> crawlFile env mvar docsNeed name path newTime buildID
    Just local -> processExistingLocal env mvar docsNeed name path newTime local

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
  parseAndValidate env mvar docsNeed expectedName path time source projectType buildID lastChange

-- | Parse and validate module source.
parseAndValidate :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> FilePath -> File.Time -> B.ByteString -> Parse.ProjectType -> Details.BuildID -> Details.BuildID -> IO Status
parseAndValidate env mvar docsNeed expectedName path time source projectType buildID lastChange =
  case Parse.fromByteString projectType source of
    Left err -> pure $ SBadSyntax path time source err
    Right modul -> validateAndProcess env mvar docsNeed expectedName path time source modul buildID lastChange

-- | Validate module name and process.
validateAndProcess :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> FilePath -> File.Time -> B.ByteString -> Src.Module -> Details.BuildID -> Details.BuildID -> IO Status
validateAndProcess env mvar docsNeed expectedName path time source (Src.Module maybeActualName _ _ imports values _ _ _ _) buildID lastChange =
  case maybeActualName of
    Nothing -> pure $ SBadSyntax path time source (Syntax.ModuleNameUnspecified expectedName)
    Just name@(A.At _ actualName) -> validateModuleName env mvar docsNeed expectedName actualName path time source imports values buildID lastChange name

-- | Validate module name matches expected.
validateModuleName :: Env -> MVar StatusDict -> DocsNeed -> ModuleName.Raw -> ModuleName.Raw -> FilePath -> File.Time -> B.ByteString -> [Src.Import] -> [A.Located Src.Value] -> Details.BuildID -> Details.BuildID -> A.Located ModuleName.Raw -> IO Status
validateModuleName env mvar docsNeed expectedName actualName path time source imports values buildID lastChange name =
  if expectedName == actualName
    then processValidModule env mvar docsNeed path time source imports values buildID lastChange
    else pure $ SBadSyntax path time source (Syntax.ModuleNameMismatch expectedName name)

-- | Process valid module.
processValidModule :: Env -> MVar StatusDict -> DocsNeed -> FilePath -> File.Time -> B.ByteString -> [Src.Import] -> [A.Located Src.Value] -> Details.BuildID -> Details.BuildID -> IO Status
processValidModule env mvar docsNeed path time source imports values buildID lastChange = do
  let deps = fmap Src.getImportName imports
  let local = Details.Local path time deps (any isMain values) lastChange buildID
  crawlDeps env mvar deps (SChanged local source undefined docsNeed)

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
    Right modul@(Src.Module _ _ _ imports values _ _ _ _) -> do
      let deps = fmap Src.getImportName imports
      let local = Details.Local path time deps (any isMain values) buildID buildID
      crawlDeps env mvar deps (SOutsideOk local source modul)
    Left syntaxError ->
      pure . SOutsideErr $ Error.Module "???" path time source (Error.BadSyntax syntaxError)

-- | Fork an IO operation.
fork :: IO a -> IO (MVar a)
fork work = do
  mvar <- newEmptyMVar
  _ <- forkIO $ work >>= putMVar mvar
  pure mvar
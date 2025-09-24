{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Path-based build functionality for the Build system.
--
-- This module handles building from file paths, decomposing the complex
-- fromPaths function into focused components that comply with CLAUDE.md standards.
module Build.Paths
  ( -- * Main Functions
    fromPaths
  , toArtifacts
  
  -- * Root Processing
  , findRoots
  , crawlRoots
  , checkRoot
  
  -- * Compilation Pipeline
  , runCrawlPhase
  , runCompilePhase
  
  -- * Helper Functions
  , makeEnv
  , writeDetails
  , forkWithKey
  ) where

import Control.Concurrent.MVar (MVar, newEmptyMVar, newMVar, readMVar, putMVar)
import Control.Lens ((^.))
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import Logging.Logger (printLog)
import qualified Parse.Module as Parse
import qualified Reporting
import qualified Reporting.Error as Error
import qualified Reporting.Exit as Exit
import System.FilePath (isAbsolute, (</>))
import qualified AST.Source as Src
import qualified Canopy.Outline as Outline
import qualified File
import qualified Stuff
import qualified Compile
import qualified Canopy.Interface as I
import qualified Reporting.Error.Import as Import
import qualified Reporting.Annotation as A
import qualified Data.Set as Set
import qualified Data.ByteString as B

import Build.Config (CheckConfig (..), DepsConfig (..))
import Build.Crawl (crawlRoot)
import Build.Crawl.Core (fork)
import Build.Dependencies (checkDeps, loadInterfaces)
import Build.Module.Check (checkModule)
import qualified Build.Validation as Validation
import Build.Types
  ( Env (..)
  , Dependencies
  , Artifacts (..)
  , Module (..)
  , Root (..)
  , RootLocation (..)
  , RootResult (..)
  , RootStatus (..)
  , StatusDict
  , ResultDict
  , Status
  , Result (..)
  , AbsoluteSrcDir (..)
  , DepsStatus (..)
  , envForeigns
  )

-- | Build artifacts from file paths.
fromPaths :: Reporting.Style -> FilePath -> Details.Details -> List FilePath -> IO (Either Exit.BuildProblem Artifacts)
fromPaths style root details paths =
  Reporting.trackBuild style $ \key -> do
    env <- makeEnv key root details
    processPathsBuild env paths root details

-- | Process the complete paths build pipeline.
processPathsBuild :: Env -> List FilePath -> FilePath -> Details.Details -> IO (Either Exit.BuildProblem Artifacts)
processPathsBuild env paths root details = do
  logEnvironmentInfo env details
  elroots <- findRoots env paths
  case elroots of
    Left problem -> pure (Left (Exit.BuildProjectProblem problem))
    Right lroots -> runBuildPipeline env root details lroots

-- | Log environment information for debugging.
logEnvironmentInfo :: Env -> Details.Details -> IO ()
logEnvironmentInfo env details = do
  _ <- printLog ("foreigns env: " <> show (env ^. envForeigns))
  _ <- printLog ("details foreigns: " <> show (details ^. Details.foreigns))
  _ <- printLog ("extras" <> show (details ^. Details.extras))
  pure ()

-- | Run the complete build pipeline.
runBuildPipeline :: Env -> FilePath -> Details.Details -> List RootLocation -> IO (Either Exit.BuildProblem Artifacts)
runBuildPipeline env root details lroots = do
  dmvar <- Details.loadInterfaces root details
  crawlResult <- runCrawlPhase env lroots dmvar
  case crawlResult of
    Left problem -> pure (Left (Exit.BuildProjectProblem problem))
    Right (sroots, statuses, foreigns) -> runCompilePipeline env root details sroots statuses foreigns

-- | Run crawl phase of build pipeline.
runCrawlPhase :: Env -> List RootLocation -> MVar (Maybe Dependencies) -> IO (Either Exit.BuildProjectProblem (List RootStatus, Map ModuleName.Raw Status, Dependencies))
runCrawlPhase env lroots dmvar = do
  dmvarContents <- readMVar dmvar
  _ <- printLog ("dmvarContents: " <> show (fmap Map.keys dmvarContents))
  smvar <- newMVar Map.empty
  (sroots, statuses) <- crawlRoots env smvar lroots
  midpoint <- checkMidpointAndRoots dmvar statuses sroots
  case midpoint of
    Left problem -> pure (Left problem)
    Right foreigns -> pure (Right (sroots, statuses, foreigns))

-- | Crawl all root modules.
crawlRoots :: Env -> MVar StatusDict -> List RootLocation -> IO (List RootStatus, Map ModuleName.Raw Status)
crawlRoots env smvar lroots = do
  srootMVars <- traverse (fork . crawlRoot env smvar) lroots
  sroots <- traverse readMVar srootMVars
  statuses <- readMVar smvar >>= traverse readMVar
  pure (sroots, statuses)

-- | Run compile phase of build pipeline.
runCompilePipeline :: Env -> FilePath -> Details.Details -> List RootStatus -> Map ModuleName.Raw Status -> Dependencies -> IO (Either Exit.BuildProblem Artifacts)
runCompilePipeline env root details sroots statuses foreigns = do
  rmvar <- newEmptyMVar
  (results, rrootResults) <- runCompilePhase env foreigns rmvar statuses sroots
  writeDetails root details results
  pure (toArtifacts env foreigns results rrootResults)

-- | Run compilation phase.
runCompilePhase :: Env -> Dependencies -> MVar ResultDict -> Map ModuleName.Raw Status -> List RootStatus -> IO (Map ModuleName.Raw Result, List RootResult)
runCompilePhase env foreigns rmvar statuses sroots = do
  let checkConfig = CheckConfig env foreigns rmvar
  resultsMVars <- forkWithKey (checkModule checkConfig) statuses
  putMVar rmvar resultsMVars
  rrootMVars <- traverse (fork . checkRoot env resultsMVars) sroots
  results <- traverse readMVar resultsMVars
  rrootResults <- traverse readMVar rrootMVars
  pure (results, rrootResults)

-- | Convert build results to artifacts.
toArtifacts :: Env -> Dependencies -> Map ModuleName.Raw Result -> List RootResult -> Either Exit.BuildProblem Artifacts
toArtifacts env@(Env _ root _projectType _ _ _ _) foreigns results rootResults =
  case gatherProblemsOrMains results rootResults of
    Left (NE.List e es) -> Left (Exit.BuildBadModules root e es)
    Right roots -> createArtifacts env foreigns results rootResults roots

-- | Create artifacts from successful build.
createArtifacts :: Env -> Dependencies -> Map ModuleName.Raw Result -> List RootResult -> List Root -> Either Exit.BuildProblem Artifacts
createArtifacts (Env _ _ projectType _ _ _ _) foreigns results rootResults roots =
  let modules = Map.foldrWithKey (addInsideSafe rootResults) (foldr (addOutside results) [] rootResults) results
      ffiInfo = Map.empty  -- TODO: Collect FFI info from modules
  in Right $ Artifacts (projectTypeToPkg projectType) foreigns roots modules ffiInfo

-- | Gather problems or main modules from results.
gatherProblemsOrMains :: Map ModuleName.Raw Result -> List RootResult -> Either (List Error.Module) (List Root)
gatherProblemsOrMains results (NE.List rootResult rootResults) =
  let addResult result (es, roots) =
        case result of
          RInside n -> (es, Inside n : roots)
          ROutsideOk n i o -> (es, Outside n i o : roots)
          ROutsideErr e -> (e : es, roots)
          ROutsideBlocked -> (es, roots)
      errors = Map.foldr addErrors [] results
   in processRootResult rootResult (foldr addResult (errors, []) rootResults)

-- | Process root result to determine final outcome.
processRootResult :: RootResult -> ([Error.Module], [Root]) -> Either (List Error.Module) (List Root)
processRootResult rootResult (errors, modules) =
  case (rootResult, errors) of
    (RInside n, []) -> Right (NE.List (Inside n) modules)
    (RInside _, e : es) -> Left (NE.List e es)
    (ROutsideOk n i o, []) -> Right (NE.List (Outside n i o) modules)
    (ROutsideOk {}, e : es) -> Left (NE.List e es)
    (ROutsideErr e, es) -> Left (NE.List e es)
    (ROutsideBlocked, []) -> error "seems like canopy-stuff/ is corrupted"
    (ROutsideBlocked, e : es) -> Left (NE.List e es)

-- Helper functions that would be imported or defined elsewhere
addInsideSafe :: List RootResult -> ModuleName.Raw -> Result -> [Module] -> [Module]
addInsideSafe rootResults name result modules =
  if isRootName name rootResults
    then modules
    else addInside name result modules

addOutside :: Map ModuleName.Raw Result -> RootResult -> [Module] -> [Module]
addOutside _results rootResult modules =
  case rootResult of
    RInside _ -> modules
    ROutsideOk name iface objs -> Fresh name iface objs : modules
    ROutsideErr _ -> modules
    ROutsideBlocked -> modules

addErrors :: Result -> [Error.Module] -> [Error.Module]
addErrors result errors =
  case result of
    RProblem e -> e : errors
    _ -> errors

projectTypeToPkg :: Parse.ProjectType -> Pkg.Name
projectTypeToPkg projectType =
  case projectType of
    Parse.Package pkg -> pkg
    Parse.Application -> Pkg.dummyName

makeEnv :: Reporting.BKey -> FilePath -> Details.Details -> IO Env
makeEnv key root details = do
  let srcDirs = getSrcDirs (details ^. Details.outline)
  let locals = details ^. Details.locals
  let foreigns = details ^. Details.foreigns
  let buildID = details ^. Details.buildID
  let projectType = outlineToProjectType (details ^. Details.outline)
  pure (Env key root projectType srcDirs buildID locals foreigns)

getSrcDirs :: Details.ValidOutline -> [AbsoluteSrcDir]
getSrcDirs outline =
  case outline of
    Details.ValidApp srcDirs -> fmap srcDirToAbsolute (NE.toList srcDirs)
    Details.ValidPkg _ _ _ -> [AbsoluteSrcDir "src"]

srcDirToAbsolute :: Outline.SrcDir -> AbsoluteSrcDir
srcDirToAbsolute srcDir =
  case srcDir of
    Outline.AbsoluteSrcDir dir -> AbsoluteSrcDir dir
    Outline.RelativeSrcDir dir -> AbsoluteSrcDir dir

outlineToProjectType :: Details.ValidOutline -> Parse.ProjectType
outlineToProjectType outline =
  case outline of
    Details.ValidApp _ -> Parse.Application
    Details.ValidPkg pkg _ _ -> Parse.Package pkg

writeDetails :: FilePath -> Details.Details -> Map ModuleName.Raw Result -> IO ()
writeDetails root (Details.Details time outline buildID locals foreigns extras) results =
  File.writeBinary (Stuff.details root) $
    Details.Details time outline buildID (Map.foldrWithKey addNewLocal locals results) foreigns extras

addNewLocal :: ModuleName.Raw -> Result -> Map ModuleName.Raw Details.Local -> Map ModuleName.Raw Details.Local
addNewLocal name result locals =
  case result of
    RNew local _ _ _ -> Map.insert name local locals
    RSame local _ _ _ -> Map.insert name local locals
    RCached {} -> locals
    RNotFound _ -> locals
    RProblem _ -> locals
    RBlocked -> locals
    RForeign _ -> locals
    RKernel -> locals

forkWithKey :: (ModuleName.Raw -> a -> IO b) -> Map ModuleName.Raw a -> IO (Map ModuleName.Raw (MVar b))
forkWithKey function dictionary =
  Map.traverseWithKey (\key value -> fork (function key value)) dictionary

checkRoot :: Env -> Map ModuleName.Raw (MVar Result) -> RootStatus -> IO RootResult
checkRoot env@(Env _ root _ _ _ _ _) results rootStatus =
  case rootStatus of
    SInside name -> pure (RInside name)
    SOutsideErr err -> pure (ROutsideErr err)
    SOutsideOk local source modul@(Src.Module _ _ _ imports _ _ _ _ _ _) -> do
      let localDeps = local ^. Details.deps
      let localLastCompile = local ^. Details.lastCompile  
      depsStatus <- checkDeps (DepsConfig root results localDeps localLastCompile)
      case depsStatus of
        DepsChange ifaces ->
          compileOutside env local source ifaces modul
        DepsSame same cached -> do
          maybeLoaded <- loadInterfaces root same cached
          case maybeLoaded of
            Nothing -> pure ROutsideBlocked
            Just ifaces -> compileOutside env local source ifaces modul
        DepsBlock ->
          pure ROutsideBlocked
        DepsNotFound problems ->
          (pure . ROutsideErr) . Error.Module (Src.getName modul) (local ^. Details.path) (local ^. Details.time) source $ Error.BadImports (toImportErrors env results imports problems)

findRoots :: Env -> List FilePath -> IO (Either Exit.BuildProjectProblem (List RootLocation))
findRoots env paths = do
  locations <- traverse (processPath env) paths
  case NE.toList locations of
    (x:xs) -> pure (Right (NE.List x xs))
    [] -> pure (Right (NE.List (LOutside "") []))

processPath :: Env -> FilePath -> IO RootLocation
processPath (Env _ root _ _ _ _ _) path =
  if isAbsolute path
    then pure (LOutside path)
    else pure (LOutside (root </> path))

checkMidpointAndRoots :: MVar (Maybe Dependencies) -> Map ModuleName.Raw Status -> List RootStatus -> IO (Either Exit.BuildProjectProblem Dependencies)
checkMidpointAndRoots dmvar statuses sroots = do
  case Validation.checkForCycles statuses of
    Nothing ->
      case Validation.checkUniqueRoots statuses sroots of
        Nothing -> do
          maybeForeigns <- readMVar dmvar
          case maybeForeigns of
            Nothing -> pure (Left Exit.BP_CannotLoadDependencies)
            Just fs -> pure (Right fs)
        Just problem -> do
          _ <- readMVar dmvar
          pure (Left problem)
    Just cycles -> do
      _ <- readMVar dmvar
      case cycles of
        NE.List name names -> pure (Left (Exit.BP_Cycle name names))

-- Helper functions for implementation
isRootName :: ModuleName.Raw -> List RootResult -> Bool
isRootName name rootResults =
  any checkResult (NE.toList rootResults)
  where
    checkResult rootResult =
      case rootResult of
        RInside n -> n == name
        ROutsideOk n _ _ -> n == name
        ROutsideErr _ -> False
        ROutsideBlocked -> False

addInside :: ModuleName.Raw -> Result -> [Module] -> [Module]
addInside name result modules =
  case result of
    RNew _ iface objs _ ->
      Fresh name iface objs : modules
    RSame _ iface objs _ ->
      Fresh name iface objs : modules
    RCached main _buildID mvar ->
      Cached name main mvar : modules
    _ -> modules


compileOutside :: Env -> Details.Local -> B.ByteString -> Map ModuleName.Raw I.Interface -> Src.Module -> IO RootResult
compileOutside (Env key _ projectType _ _ _ _) local source ifaces modul = do
  let pkg = projectTypeToPkg projectType
      name = Src.getName modul
  compileResult <- Compile.compile pkg ifaces modul
  case compileResult of
        Right (Compile.Artifacts canonical annotations objects _ffiInfo) -> do
          Reporting.report key Reporting.BDone
          pure $ ROutsideOk name (I.fromModule pkg canonical annotations) objects
        Left errors ->
          pure . ROutsideErr $ Error.Module name (local ^. Details.path) (local ^. Details.time) source errors

toImportErrors :: Env -> Map ModuleName.Raw (MVar Result) -> [Src.Import] -> NE.List (ModuleName.Raw, Import.Problem) -> NE.List Import.Error
toImportErrors (Env _ _ _ _ _ locals foreigns) results imports problems =
  let knownModules =
        Set.unions
          [ Map.keysSet foreigns,
            Map.keysSet locals,
            Map.keysSet results
          ]

      unimportedModules =
        Set.difference knownModules (Set.fromList (fmap Src.getImportName imports))

      regionDict =
        Map.fromList (fmap (\(Src.Import (A.At region name) _ _) -> (name, region)) imports)

      toError (name, problem) =
        case Map.lookup name regionDict of
          Just region -> Import.Error region name unimportedModules problem
          Nothing -> Import.Error A.one name unimportedModules problem  -- Use default region if not found
   in fmap toError problems


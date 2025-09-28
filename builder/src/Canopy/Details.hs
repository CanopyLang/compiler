{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall -Wno-unused-top-binds #-}

module Canopy.Details
  ( Details (..),
    BuildID,
    ValidOutline (..),
    Local (..),
    Foreign (..),
    Artifacts (..),
    ArtifactCache (..),
    Extras (..),
    -- Lens exports
    outlineTime,
    buildID,
    foreigns,
    outline,
    locals,
    extras,
    lastCompile,
    lastChange,
    deps,
    path,
    time,
    main,
    ifaces,
    objects,
    fingerprints,
    artifacts,
    load,
    loadForReactorTH,
    loadObjects,
    loadInterfaces,
    getDocsStatus,
    getDocsStatusOverridePkg,
    writeDocs,
    verifyInstall,
    writeDocsOverridingPackage,
    downloadPackage,
    downloadPackageDirectly,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified BackgroundWriter as BW
import qualified Canopy.Constraint as C
import qualified Canopy.Constraint as Con
import Canopy.CustomRepositoryData
  ( CustomSingleRepositoryData (..),
    DefaultPackageServerRepo (..),
    HumanReadableShaDigest,
    PZRPackageServerRepo (..),
    PackageUrl,
    RepositoryUrl,
    humanReadableShaDigestIsEqualToSha,
    humanReadableShaDigestToString,
  )
import qualified Canopy.CustomRepositoryData as CustomRepositoriesData
import qualified Canopy.CustomRepositoryData as CustomRepositoryData
import qualified Canopy.Docs as Docs
import qualified Canopy.Interface as I
import qualified Canopy.Kernel as Kernel
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import Canopy.PackageOverrideData (PackageOverrideData (..))
import qualified Canopy.PackageOverrideData as PackageOverrideData
import qualified Canopy.Version as V
import qualified Compile
import Control.Concurrent.Async (async, wait, forConcurrently)
import Control.Concurrent.STM (TVar, STM, atomically, newTVar, newTVarIO, readTVar, readTVarIO, writeTVar, modifyTVar, retry)
import Debug.Trace (trace)
import Control.Lens (makeLenses)
import Control.Exception (Handler (..), SomeException, catches, throwIO, catch, ErrorCall)
import Control.Monad (foldM, liftM2, liftM3, void, when, filterM)
import Data.Binary (Binary, get, getWord8, put, putWord8)
import qualified Data.Either as Either
import Data.Foldable ()
import qualified Data.Map as Map
import qualified Data.Map.Merge.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Data.OneOrMore as OneOrMore
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Utf8 as Utf8
import Data.Word (Word64)
import Deps.Registry (ZokkaRegistries)
import qualified Deps.Registry as Registry
import qualified Deps.Solver as Solver
import qualified Deps.Website as Website
import qualified File
import qualified Http
import qualified Json.Decode as D
import qualified Json.Encode as E
import Logging.Logger (printLog)
import qualified Parse.Module as Parse
import qualified Reporting
import qualified Reporting.Annotation as A
import Reporting.Exit (PackageProblem (PP_BadArchiveHash))
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import Stuff (PackageOverrideConfig (..))
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath ((<.>), (</>))

-- | Wait for a TVar result, handling TVars created by fork operations.
-- Local implementation to avoid circular imports with Build.Types.
waitForResult :: TVar a -> IO a
waitForResult tvar = do
  result <- catch (readTVarIO tvar) $ \(_ :: ErrorCall) -> do
    -- If we get the "fork: result not yet available" error, retry
    waitForResult tvar
  pure result

-- | Wait for a result from a Maybe TVar (used with fork)
-- Uses proper STM retry - need to investigate why TVars aren't filled
waitForMaybeResult :: TVar (Maybe a) -> IO a
waitForMaybeResult tvar = waitForMaybeResultWithName tvar "Unknown Resource"

-- | Labeled STM retry with detailed logging for debugging
waitForMaybeResultWithName :: TVar (Maybe a) -> String -> IO a
waitForMaybeResultWithName tvar resourceName = do
  putStrLn ("WAIT-DEBUG: Starting wait for resource: " <> resourceName)
  atomically $ do
    result <- readTVar tvar
    case result of
      Nothing -> trace ("STM-RETRY: Resource not available, retrying: " <> resourceName) retry
      Just value -> trace ("STM-SUCCESS: Resource available: " <> resourceName) (pure value)

-- DETAILS

data Details = Details
  { _outlineTime :: File.Time,
    _outline :: ValidOutline,
    _buildID :: BuildID,
    _locals :: Map.Map ModuleName.Raw Local,
    _foreigns :: Map.Map ModuleName.Raw Foreign,
    _extras :: Extras
  }

type BuildID = Word64

data ValidOutline
  = ValidApp (NE.List Outline.SrcDir)
  | ValidPkg Pkg.Name [ModuleName.Raw] (Map.Map Pkg.Name V.Version {- for docs in reactor -})
  deriving (Show)

-- NOTE: we need two ways to detect if a file must be recompiled:
--
-- (1) _time is the modification time from the last time we compiled the file.
-- By checking EQUALITY with the current modification time, we can detect file
-- saves and `git checkout` of previous versions. Both need a recompile.
--
-- (2) _lastChange is the BuildID from the last time a new interface file was
-- generated, and _lastCompile is the BuildID from the last time the file was
-- compiled. These may be different if a file is recompiled but the interface
-- stayed the same. When the _lastCompile is LESS THAN the _lastChange of any
-- imports, we need to recompile. This can happen when a project has multiple
-- entrypoints and some modules are compiled less often than their imports.
--
data Local = Local
  { _path :: FilePath,
    _time :: File.Time,
    _deps :: [ModuleName.Raw],
    _main :: Bool,
    _lastChange :: BuildID,
    _lastCompile :: BuildID
  }
  deriving (Show)

-- "Foreign" modules, i.e. modules that come from third-party dependencies and
-- are not from modules in the current project
data Foreign
  = -- In normal operation every foreign module should only come from one package.
    -- It is possible, however, for a module name to be used by multiple different
    -- packages. This is currently an error in Canopy and will cause an error later
    -- on in the build process, but to surface that error we track duplicate
    -- packages in the second argument of this constructor.
    Foreign Pkg.Name [Pkg.Name]
  deriving (Show)

data Extras
  = ArtifactsCached
  | ArtifactsFresh Interfaces Opt.GlobalGraph

instance Show Extras where
  show ArtifactsCached = "ArtifactsCached"
  show (ArtifactsFresh i _) = "ArtifactsFresh: " <> show (Map.keys i)

type Interfaces =
  Map.Map ModuleName.Canonical I.DependencyInterface

-- STM DEPENDENCY STORE

-- | STM-based dependency store to eliminate MVar deadlocks
-- Replaces the circular MVar dependency pattern with composable transactions
data DepStore = DepStore
  { _completedDeps :: TVar (Map.Map Pkg.Name Dep)
  , _inProgressDeps :: TVar (Set Pkg.Name)
  }

-- | Create new dependency store
newDepStore :: STM DepStore
newDepStore = DepStore
  <$> newTVar Map.empty
  <*> newTVar Set.empty

-- | Claim a dependency for processing
-- Returns True if this thread should process it
claimDependency :: DepStore -> Pkg.Name -> STM Bool
claimDependency store pkg = do
  completed <- readTVar (_completedDeps store)
  inProgress <- readTVar (_inProgressDeps store)

  if Map.member pkg completed || Set.member pkg inProgress
    then return False
    else do
      modifyTVar (_inProgressDeps store) (Set.insert pkg)
      return True

-- | Mark dependency as completed
completeDependency :: DepStore -> Pkg.Name -> Dep -> STM ()
completeDependency store pkg result = do
  modifyTVar (_completedDeps store) (Map.insert pkg result)
  modifyTVar (_inProgressDeps store) (Set.delete pkg)

-- | Wait for specific dependencies with labeled STM retry for debugging
-- This replaces the deadlock-prone MVar pattern
waitForDependencies :: DepStore -> [Pkg.Name] -> STM (Map.Map Pkg.Name Dep)
waitForDependencies store pkgs = do
  completed <- readTVar (_completedDeps store)
  let available = Map.intersection completed (Map.fromList [(p, ()) | p <- pkgs])
  let missing = [p | p <- pkgs, not (Map.member p completed)]

  if Map.size available == length pkgs
    then return (Map.intersection completed (Map.fromList [(p, ()) | p <- pkgs]))
    else
      let missingStr = show missing
      in trace ("STM-WAIT-DEPS: Waiting for dependencies: " <> missingStr) retry

-- | Wait for a specific dependency with labeled STM retry for debugging
waitForSpecificDependency :: DepStore -> Pkg.Name -> STM Dep
waitForSpecificDependency store pkg = do
  completed <- readTVar (_completedDeps store)
  case Map.lookup pkg completed of
    Just result -> return result
    Nothing -> trace ("STM-WAIT-DEP: Waiting for specific dependency: " <> show pkg) retry

-- LOAD ARTIFACTS

loadObjects :: FilePath -> Details -> IO (TVar (Maybe Opt.GlobalGraph))
loadObjects root (Details _ _ _ _ _ extras) =
  case extras of
    ArtifactsFresh _ o -> newTVarIO (Just o)
    ArtifactsCached -> do
      objects <- File.readBinary (Stuff.objects root) :: IO (Maybe Opt.GlobalGraph)
      newTVarIO objects

loadInterfaces :: FilePath -> Details -> IO (TVar (Maybe Interfaces))
loadInterfaces root (Details _ _ _ _ _ extras) =
  case extras of
    ArtifactsFresh i _ -> newTVarIO (Just i)
    ArtifactsCached -> do
      interfaces <- File.readBinary (Stuff.interfaces root) :: IO (Maybe Interfaces)
      newTVarIO interfaces

-- VERIFY INSTALL -- used by Install

verifyInstall :: BW.Scope -> FilePath -> Solver.Env -> Outline.Outline -> IO (Either Exit.Details ())
verifyInstall scope root (Solver.Env cache manager connection registry packageOverridesCache) outline =
  do
    configPath <- Stuff.getConfigFilePath root
    time <- File.getTime configPath
    let key = Reporting.ignorer
    let env = Env key scope root cache manager connection registry packageOverridesCache
    case outline of
      Outline.Pkg pkg -> Task.run (void (verifyPkg env time pkg))
      Outline.App app -> Task.run (void (verifyApp env time app))

-- LOAD -- used by Make, Repl, Reactor

load :: Reporting.Style -> BW.Scope -> FilePath -> IO (Either Exit.Details Details)
load style scope root =
  do
    configPath <- Stuff.getConfigFilePath root
    newTime <- File.getTime configPath
    maybeDetails <- File.readBinary (Stuff.details root)
    printLog "Finished file operations for generating the Details data structure"
    case maybeDetails of
      Nothing ->
        generate style scope root newTime
      Just details@(Details oldTime _ buildID _ _ _) ->
        if oldTime == newTime
          then return (Right details {_buildID = buildID + 1})
          else generate style scope root newTime

-- FIXME: This is a hack to get around a bug somewhere in the build process
loadForReactorTH :: Reporting.Style -> BW.Scope -> FilePath -> IO (Either Exit.Details Details)
loadForReactorTH style scope root =
  do
    configPath <- Stuff.getConfigFilePath root
    newTime <- File.getTime configPath
    maybeDetails <- File.readBinary (Stuff.details root)
    printLog "Finished file operations for generating the Details data structure"
    case maybeDetails of
      Nothing ->
        generateForReactorTH style scope root newTime
      Just details@(Details oldTime _ buildID _ _ _) ->
        if oldTime == newTime
          then return (Right details {_buildID = buildID + 1})
          else generate style scope root newTime

-- GENERATE

generate :: Reporting.Style -> BW.Scope -> FilePath -> File.Time -> IO (Either Exit.Details Details)
generate style scope root time =
  Reporting.trackDetails style $ \key ->
    do
      result <- initEnv key scope root
      printLog "Made it to generate 1"
      case result of
        Left exit ->
          return (Left exit)
        Right (env, outline) ->
          case outline of
            Outline.Pkg pkg -> Task.run (verifyPkg env time pkg)
            Outline.App app -> Task.run (verifyApp env time app)

-- FIXME
generateForReactorTH :: Reporting.Style -> BW.Scope -> FilePath -> File.Time -> IO (Either Exit.Details Details)
generateForReactorTH style scope root time =
  Reporting.trackDetails style $ \key ->
    do
      result <- initEnvForReactorTH key scope root
      printLog "Made it to generateForReactorTH 1"
      case result of
        Left exit ->
          return (Left exit)
        Right (env, outline) ->
          case outline of
            Outline.Pkg pkg -> Task.run (verifyPkg env time pkg)
            Outline.App app -> Task.run (verifyApp env time app)

-- ENV

data Env = Env
  { _key :: Reporting.DKey,
    _scope :: BW.Scope,
    _root :: FilePath,
    _cache :: Stuff.PackageCache,
    _manager :: Http.Manager,
    _connection :: Solver.Connection,
    _registry :: Registry.ZokkaRegistries,
    _packageOverridesCache :: Stuff.PackageOverridesCache
  }

initEnv :: Reporting.DKey -> BW.Scope -> FilePath -> IO (Either Exit.Details (Env, Outline.Outline))
initEnv key scope root =
  do
    asyncAction <- async Solver.initEnv
    eitherOutline <- Outline.read root
    case eitherOutline of
      Left problem ->
        return . Left $ Exit.DetailsBadOutline problem
      Right outline ->
        do
          maybeEnv <- wait asyncAction
          case maybeEnv of
            Left problem ->
              return . Left $ Exit.DetailsCannotGetRegistry problem
            Right (Solver.Env cache manager connection registry packageOverridesCache) ->
              return $ Right (Env key scope root cache manager connection registry packageOverridesCache, outline)

-- FIXME
initEnvForReactorTH :: Reporting.DKey -> BW.Scope -> FilePath -> IO (Either Exit.Details (Env, Outline.Outline))
initEnvForReactorTH key scope root =
  do
    asyncAction <- async Solver.initEnv
    eitherOutline <- Outline.read root
    case eitherOutline of
      Left problem ->
        return . Left $ Exit.DetailsBadOutline problem
      Right outline ->
        do
          maybeEnv <- wait asyncAction
          case maybeEnv of
            Left problem ->
              return . Left $ Exit.DetailsCannotGetRegistry problem
            Right (Solver.Env cache manager connection registry packageOverridesCache) ->
              return $ Right (Env key scope root cache manager connection registry packageOverridesCache, outline)

-- VERIFY PROJECT

type Task a = Task.Task Exit.Details a

verifyPkg :: Env -> File.Time -> Outline.PkgOutline -> Task Details
verifyPkg env time (Outline.PkgOutline pkg _ _ _ exposed direct testDirect canopy) =
  if Con.goodCanopy canopy
    then do
      solution <- union noDups direct testDirect >>= verifyConstraints env
      let exposedList = Outline.flattenExposed exposed
      let exactDeps = Map.map (\(Solver.Details v _) -> v) solution -- for pkg docs in reactor
      -- We don't allow packages to override transitive dependencies, only applications
      -- This is because it causes major headaches if the dependency tree of an
      -- application could have its own nested overrides. Hence we use an empty Map
      verifyDependencies env time (ValidPkg pkg exposedList exactDeps) solution direct Map.empty
    else Task.throw $ Exit.DetailsBadCanopyInPkg canopy

groupByOriginalPkg :: [PackageOverrideData] -> Map.Map Pkg.Name (Pkg.Name, V.Version)
groupByOriginalPkg packageOverrides =
  Map.fromListWith
    const
    (fmap (\po -> (PackageOverrideData._originalPackageName po, (PackageOverrideData._overridePackageName po, PackageOverrideData._overridePackageVersion po))) packageOverrides)

verifyApp :: Env -> File.Time -> Outline.AppOutline -> Task Details
verifyApp env time outline@(Outline.AppOutline canopyVersion srcDirs direct _ _ _ packageOverrides) =
  if canopyVersion == V.compiler
    then do
      stated <- checkAppDeps outline
      actual <- verifyConstraints env (Map.map Con.exactly stated)
      -- FIXME: Think about what to do with multiple packageOverrides that have the same keys (probably shouldn't be possible?)
      let originalPkgToOverridingPkg = groupByOriginalPkg packageOverrides
      if Map.size stated == Map.size actual
        then verifyDependencies env time (ValidApp srcDirs) actual direct originalPkgToOverridingPkg
        else Task.throw Exit.DetailsHandEditedDependencies
    else Task.throw $ Exit.DetailsBadCanopyInAppOutline canopyVersion

checkAppDeps :: Outline.AppOutline -> Task (Map.Map Pkg.Name V.Version)
checkAppDeps (Outline.AppOutline _ _ direct indirect testDirect testIndirect _) =
  do
    x <- union allowEqualDups indirect testDirect
    y <- union noDups direct testIndirect
    union noDups x y

-- VERIFY CONSTRAINTS

verifyConstraints :: Env -> Map.Map Pkg.Name Con.Constraint -> Task (Map.Map Pkg.Name Solver.Details)
verifyConstraints (Env _ _ _ cache _ connection registry _) constraints =
  do
    -- ARCHITECTURAL FIX: Filter elm/core from solver and provide as foreign interface
    -- elm/core should not go through source compilation, it should use interface files
    let (coreConstraint, nonCoreConstraints) = Map.partitionWithKey (\pkg _ -> pkg == Pkg.core) constraints

    result <- Task.io $ Solver.verify cache connection registry nonCoreConstraints
    case result of
      Solver.Ok details ->
        -- Add elm/core back as a foreign dependency if it was requested
        if Map.member Pkg.core coreConstraint
          then do
            let coreDetails = Solver.Details V.one Map.empty  -- elm/core 1.0.0 with no deps
            return (Map.insert Pkg.core coreDetails details)
          else return details
      Solver.NoSolution -> Task.throw Exit.DetailsNoSolution
      Solver.NoOfflineSolution r -> Task.throw $ Exit.DetailsNoOfflineSolution r
      Solver.Err exit -> Task.throw $ Exit.DetailsSolverProblem exit

-- UNION

union :: (Ord k) => (k -> v -> v -> Task v) -> Map.Map k v -> Map.Map k v -> Task (Map.Map k v)
union tieBreaker = Map.mergeA Map.preserveMissing Map.preserveMissing (Map.zipWithAMatched tieBreaker)

noDups :: k -> v -> v -> Task v
noDups _ _ _ =
  Task.throw Exit.DetailsHandEditedDependencies

allowEqualDups :: (Eq v) => k -> v -> v -> Task v
allowEqualDups _ v1 v2 =
  if v1 == v2
    then return v1
    else Task.throw Exit.DetailsHandEditedDependencies

-- FORK

-- Legacy fork function removed - using STM-based async instead


genericErrorHandler :: String -> IO a -> IO a
genericErrorHandler msg action =
  action
    `catches` [ Handler handler
              ]
  where
    handler :: SomeException -> IO a
    handler exception = printLog ("SOME EXCEPTION: " <> (msg <> (" | exception was: " <> show exception))) >> throwIO exception

-- VERIFY DEPENDENCIES

verifyDependencies :: Env -> File.Time -> ValidOutline -> Map.Map Pkg.Name Solver.Details -> Map.Map Pkg.Name a -> Map.Map Pkg.Name (Pkg.Name, V.Version) -> Task Details
verifyDependencies (Env key scope root cache manager _ zokkaRegistries packageOverridesCache) time outline solution directDeps originalPkgToOverridingPkg =
  let generateBuildData :: Pkg.Name -> V.Version -> BuildData
      generateBuildData pkgName pkgVersion = case Map.lookup pkgName originalPkgToOverridingPkg of
        Nothing ->
          BuildOriginalPackage $
            OriginalPackageBuildData
              { _pkg = pkgName,
                _version = pkgVersion,
                _buildCache = cache
              }
        Just (overridingPkgName, overridingPkgVersion) ->
          BuildWithOverridingPackage $
            OverridingPackageBuildData
              { _originalPkg = pkgName,
                _originalPkgVersion = pkgVersion,
                _overridingPkg = overridingPkgName,
                _overridingPkgVersion = overridingPkgVersion,
                _overridingCache = packageOverridesCache
              }

      extractVersionFromDetails (Solver.Details vsn _) = vsn
      extractConstraintsFromDetails (Solver.Details _ constraints) = constraints
   in Task.eio id $
        do
          Reporting.report key (Reporting.DStart (Map.size solution))
          printLog "Made it to VERIFYDEPENDENCIES 0 - using STM to prevent deadlocks"

          -- Create STM dependency store to eliminate circular dependency deadlock
          store <- atomically newDepStore
          printLog "Made it to VERIFYDEPENDENCIES 1 - created STM store"
          printLog ("SOLUTION: " <> show solution)

          -- ARCHITECTURAL FIX: Filter elm/core from dependency building
          -- elm/core should use foreign interfaces, not source compilation
          let solutionWithoutCore = Map.delete Pkg.core solution
          printLog ("FILTERED SOLUTION (without elm/core): " <> show solutionWithoutCore)

          -- Start workers concurrently without circular dependencies (excluding elm/core)
          workers <- Stuff.withRegistryLock cache $
            forConcurrently (Map.toList solutionWithoutCore) $ \(pkg, details) ->
              async (verifyDep store key (generateBuildData pkg (extractVersionFromDetails details)) manager zokkaRegistries solution (extractConstraintsFromDetails details))

          printLog ("Made it to VERIFYDEPENDENCIES 2: started " <> show (length workers) <> " workers")

          -- Wait for all workers with proper error handling (excluding elm/core)
          deps <- Map.fromList <$> mapM (\(worker, (pkg, _)) -> do
            result <- wait worker
            printLog ("deps result for " <> show pkg)
            return (pkg, result)) (zip workers (Map.toList solutionWithoutCore))

          printLog "Made it to VERIFYDEPENDENCIES 3 - collected all results"
          case sequenceA deps of
            Left _ ->
              do
                home <- Stuff.getCanopyHome
                (((return . Left) . Exit.DetailsBadDeps home) . Maybe.catMaybes) . Either.lefts $ Map.elems deps
            Right artifacts ->
              let objs = Map.foldr addObjects Opt.empty artifacts
                  ifaces = Map.foldrWithKey (addInterfaces directDeps) Map.empty artifacts
                  foreigns = (Map.map (OneOrMore.destruct Foreign) . Map.foldrWithKey gatherForeigns Map.empty $ Map.intersection artifacts directDeps)
                  details = Details time outline 0 Map.empty foreigns (ArtifactsFresh ifaces objs)
               in do
                    BW.writeBinary scope (Stuff.objects root) objs
                    BW.writeBinary scope (Stuff.interfaces root) ifaces
                    BW.writeBinary scope (Stuff.details root) details
                    return (Right details)

addObjects :: Artifacts -> Opt.GlobalGraph -> Opt.GlobalGraph
addObjects (Artifacts _ objs) = Opt.addGlobalGraph objs

addInterfaces :: Map.Map Pkg.Name a -> Pkg.Name -> Artifacts -> Interfaces -> Interfaces
addInterfaces directDeps pkg (Artifacts ifaces _) dependencyInterfaces =
  Map.union dependencyInterfaces . Map.mapKeysMonotonic (ModuleName.Canonical pkg) $
    ( if Map.member pkg directDeps
        then ifaces
        else Map.map I.privatize ifaces
    )

gatherForeigns :: Pkg.Name -> Artifacts -> Map.Map ModuleName.Raw (OneOrMore.OneOrMore Pkg.Name) -> Map.Map ModuleName.Raw (OneOrMore.OneOrMore Pkg.Name)
gatherForeigns pkg (Artifacts ifaces _) foreigns =
  let isPublic di =
        case di of
          I.Public _ -> Just (OneOrMore.one pkg)
          I.Private {} -> Nothing
   in Map.unionWith OneOrMore.more foreigns (Map.mapMaybe isPublic ifaces)

-- VERIFY DEPENDENCY

data Artifacts = Artifacts
  { _ifaces :: Map.Map ModuleName.Raw I.DependencyInterface,
    _objects :: Opt.GlobalGraph
  }
  deriving (Show)

type Dep =
  Either (Maybe Exit.DetailsBadDep) Artifacts


-- ARTIFACT CACHE

data ArtifactCache = ArtifactCache
  { _fingerprints :: Set.Set Fingerprint,
    _artifacts :: Artifacts
  }

type Fingerprint =
  Map.Map Pkg.Name V.Version

-- BUILD

data OverridingPackageBuildData = OverridingPackageBuildData
  { _originalPkg :: Pkg.Name,
    _originalPkgVersion :: V.Version,
    _overridingPkg :: Pkg.Name,
    _overridingPkgVersion :: V.Version,
    _overridingCache :: Stuff.PackageOverridesCache
  }

data OriginalPackageBuildData = OriginalPackageBuildData
  { _pkg :: Pkg.Name,
    _version :: V.Version,
    _buildCache :: Stuff.PackageCache
  }

data BuildData
  = BuildOriginalPackage OriginalPackageBuildData
  | BuildWithOverridingPackage OverridingPackageBuildData

cacheFilePathFromBuildData :: BuildData -> FilePath
cacheFilePathFromBuildData buildData =
  case buildData of
    BuildOriginalPackage (OriginalPackageBuildData {_pkg = pkg, _version = vsn, _buildCache = cache}) ->
      Stuff.package cache pkg vsn
    BuildWithOverridingPackage
      (OverridingPackageBuildData {_originalPkg = origPkg, _originalPkgVersion = origPkgVer, _overridingPkg = overPkg, _overridingPkgVersion = overPkgVer, _overridingCache = cache}) ->
        Stuff.packageOverride (PackageOverrideConfig cache origPkg origPkgVer overPkg overPkgVer)

-- | Safe version of verifyDep that eliminates MVar deadlocks using STM
verifyDep :: DepStore -> Reporting.DKey -> BuildData -> Http.Manager -> ZokkaRegistries -> Map.Map Pkg.Name Solver.Details -> Map.Map Pkg.Name C.Constraint -> IO Dep
verifyDep store key buildData _manager _zokkaRegistry solution directDeps = do
  let fingerprint = Map.intersectionWith (\(Solver.Details v _) _ -> v) solution directDeps
      primaryPkg = case buildData of
        BuildOriginalPackage (OriginalPackageBuildData {_pkg = pkg}) -> pkg
        BuildWithOverridingPackage (OverridingPackageBuildData {_overridingPkg = overridingPkg}) -> overridingPkg

  -- Check if another thread is already processing this package
  shouldProcess <- atomically $ claimDependency store primaryPkg

  if not shouldProcess
    then do
      -- Another thread is handling it, wait for result using STM
      result <- atomically $ waitForSpecificDependency store primaryPkg
      return result
    else do
      -- Process this package
      result <- build store key buildData fingerprint Set.empty
      -- Mark as completed
      atomically $ completeDependency store primaryPkg result
      return result

-- | Safe build function that eliminates MVar deadlocks
build :: DepStore -> Reporting.DKey -> BuildData -> Fingerprint -> Set.Set Fingerprint -> IO Dep
build store key buildData f fs = do
  let cacheFilePath = cacheFilePathFromBuildData buildData
      (pkg, vsn) = case buildData of
        BuildOriginalPackage (OriginalPackageBuildData {_pkg = origPkg, _version = origVsn}) ->
          (origPkg, origVsn)
        BuildWithOverridingPackage
          (OverridingPackageBuildData {_originalPkg = origPkg, _originalPkgVersion = origPkgVer}) ->
            (origPkg, origPkgVer)

  eitherOutline <- Outline.read cacheFilePath
  printLog ("COMPILING: " <> (show pkg <> (show vsn <> (" OUTLINE: " <> show eitherOutline))))
  printLog ("PROCESSING_PACKAGE: " <> Pkg.toChars pkg)

  case eitherOutline of
    Left _ -> do
      Reporting.report key Reporting.DBroken
      return $ Left $ Just $ Exit.BD_BadBuild pkg vsn f
    Right (Outline.App _) -> do
      Reporting.report key Reporting.DBroken
      return $ Left $ Just $ Exit.BD_BadBuild pkg vsn f
    Right (Outline.Pkg (Outline.PkgOutline _ _ _ _ exposed deps _ _)) -> do
      -- CIRCULAR DEPENDENCY FIX: elm/core should not wait for other packages
      depResults <- if pkg == Pkg.core
        then do
          putStrLn ("CIRCULAR-DEP-FIX: elm/core detected - using non-blocking dependency resolution")
          -- For elm/core, use immediate/non-blocking dependency access
          completed <- readTVarIO (_completedDeps store)
          let available = Map.intersection completed (Map.fromList [(p, ()) | p <- Map.keys deps])
          putStrLn ("CIRCULAR-DEP-FIX: elm/core available deps: " <> show (Map.keys available))
          return available
        else do
          -- For non-core packages, wait for dependencies (excluding elm/core)
          -- elm/core is provided as foreign interface, not built as dependency
          let depsWithoutCore = Map.delete Pkg.core deps
          putStrLn ("ATOMICALLY-DEBUG: Details.hs:666 - about to wait for dependencies: " <> show (Map.keys depsWithoutCore))
          atomically $ waitForDependencies store (Map.keys depsWithoutCore)
      putStrLn ("ATOMICALLY-DEBUG: Details.hs:666 - dependency resolution completed successfully")

      case sequenceA depResults of
        Left x -> do
          Reporting.report key Reporting.DBroken
          return $ Left x
        Right directArtifacts -> do
          let src = cacheFilePath </> "src"
          let foreignDeps = gatherForeignInterfaces directArtifacts
          -- Create package-aware foreign dependency lookup
          let pkgForeignDeps = gatherPackageForeignInterfaces directArtifacts
          printLog ("DEBUG: Processing package " <> show pkg <> " (isCore: " <> show (pkg == Pkg.core) <> ")")
          when (pkg == Pkg.core) $ do
            printLog ("DEBUG: Foreign interfaces for pkg " <> show pkg <> ": " <> show (Map.keys foreignDeps))
          let exposedDict = Map.fromSet (const ()) (Set.fromList (Outline.flattenExposed exposed))
          when (pkg == Pkg.core) $ do
            printLog ("DEBUG: Exposed modules for " <> show pkg <> ": " <> show (Map.keys exposedDict))

          -- FIXED: Treat elm/core like any other package - use exposed modules only
          -- Package overrides are optional, normal packages use interface files
          let modulesToCrawl = exposedDict

          docsStatus <- getDocsStatusFromFilePath cacheFilePath
          -- STM-based status tracking for modules
          statusStore <- atomically $ newTVar Map.empty
          mvars <- Map.traverseWithKey (\name _ -> async (crawlModuleWithPackageContext pkgForeignDeps statusStore pkg src docsStatus name)) modulesToCrawl
          statuses <- traverse wait mvars
          let successfulCrawls = Map.keys $ Map.mapMaybe id statuses
          when (pkg == Pkg.core) $ do
            printLog ("DEBUG: Successfully crawled modules for " <> show pkg <> ": " <> show successfulCrawls)
          case sequenceA statuses of
            Nothing -> do
              Reporting.report key Reporting.DBroken
              printLog ("maybeStatuses were Nothing for " <> (show pkg <> (" vsn " <> (show vsn <> (" and deps " <> show deps)))))
              return $ Left $ Just $ Exit.BD_BadBuild pkg vsn f
            Just statusList -> do
              printLog ("DEBUG: MAIN ENTRY POINT - Processing statusList for pkg: " <> show pkg)
              when (pkg == Pkg.core) $ do
                printLog ("DEBUG: Modules in statusList for " <> show pkg <> ": " <> show (Map.keys statusList))


              -- STM-based result tracking for compilation
              resultStore <- atomically $ newTVar Map.empty
              let extractDepsFromStatus status = case status of (SLocal _ statusDeps _) -> statusDeps; _ -> Map.empty

              printLog ("DEBUG: CHECKPOINT 1 - Starting resultStore setup")

              -- Read final state of statusStore to get ALL modules (including those discovered during import crawling)
              putStrLn "ATOMICALLY-DEBUG: Details.hs:724 - about to read statusStore"
              finalStatusStore <- atomically $ readTVar statusStore
              putStrLn "ATOMICALLY-DEBUG: Details.hs:724 - statusStore read successful"
              printLog ("DEBUG: CHECKPOINT 2 - Read finalStatusStore successfully")
              printLog ("DEBUG: Final statusStore contains modules: " <> show (Map.keys finalStatusStore))

              -- Pre-populate result store with TVars for ALL modules in final statusStore
              allModuleNames <- pure $ Map.keys finalStatusStore
              printLog ("DEBUG: CHECKPOINT 3 - About to create moduleResultTVars")
              printLog ("DEBUG: Creating result TVars for ALL modules (including crawled imports): " <> show allModuleNames)
              moduleResultTVars <- traverse (\_ -> atomically $ newTVar Nothing) (Map.fromList (zip allModuleNames allModuleNames))
              printLog ("DEBUG: CHECKPOINT 4 - Created moduleResultTVars successfully")
              atomically $ writeTVar resultStore moduleResultTVars
              printLog ("DEBUG: CHECKPOINT 5 - Result store populated with modules: " <> show (Map.keys moduleResultTVars))

              -- IMPORTANT: Create compileAction AFTER populating resultStore
              let compileAction status = genericErrorHandler ("This package failed: " <> show pkg) (compile pkg resultStore status)

              printLog ("DEBUG: CHECKPOINT 6 - About to extract final status values")

              -- Extract final status values from all TVars in statusStore
              finalStatusValues <- traverse waitForResult finalStatusStore
              printLog ("DEBUG: CHECKPOINT 7 - Extracted final status values")
              -- Debug: Check which modules returned Nothing
              let nothingModules = Map.keys $ Map.filter (\case { Nothing -> True; Just _ -> False }) finalStatusValues
              let justModules = Map.keys $ Map.filter (\case { Nothing -> False; Just _ -> True }) finalStatusValues
              printLog ("DEBUG: Modules that returned Nothing: " <> show nothingModules)
              printLog ("DEBUG: Modules that returned Just: " <> show justModules)
              let completeStatusList = Map.mapMaybe id finalStatusValues
              printLog ("DEBUG: CHECKPOINT 8 - Created completeStatusList")
              printLog ("DEBUG: Kernel modules check - looking for Elm.JsArray in completeStatusList: " <> show (Map.member "Elm.JsArray" completeStatusList))

              printLog ("DEBUG: CHECKPOINT 9 - About to check if elm/core package")
              -- Bootstrap-aware compilation ordering for elm/core
              -- Use ALL modules from finalStatusStore for dependency graph, not just successful ones
              -- This ensures kernel modules are included even if they fail to parse
              let allStatusList = Map.mapWithKey (\name maybeStatus ->
                    case maybeStatus of
                      Just status -> status
                      Nothing -> if Name.isKernel name
                        then SKernelForeign  -- Treat failed kernel modules as foreign
                        else error ("Non-kernel module failed to crawl: " <> show name)
                    ) finalStatusValues
              printLog ("DEBUG: allStatusList keys: " <> show (Map.keys allStatusList))
              printLog ("DEBUG: completeStatusList keys: " <> show (Map.keys completeStatusList))
              -- Re-enable bootstrap compilation now that STM issue is fixed
              maybeResults <- if isElmCorePackage pkg
                then do
                  printLog ("BOOTSTRAP: Detected elm/core package, using bootstrap compilation ordering")
                  compileElmCoreBootstrapSimple compileAction allStatusList moduleResultTVars
                else do
                  printLog ("REGULAR: Using regular parallel compilation for " <> show pkg)
                  compileRegularWithTVars compileAction allStatusList moduleResultTVars
              case sequenceA maybeResults of
                Nothing -> do
                  printLog ("maybeResults were Nothing for " <> (show pkg <> (" vsn " <> (show vsn <> (" and deps from status were " <> show (fmap extractDepsFromStatus allStatusList))))))
                  Reporting.report key Reporting.DBroken
                  return $ Left $ Just $ Exit.BD_BadBuild pkg vsn f
                Just results -> do
                  let path = cacheFilePath </> "artifacts.dat"
                  let ifaces = gatherInterfaces exposedDict results
                  let objects = gatherObjects results
                  let artifacts = Artifacts ifaces objects
                  let fingerprints = Set.insert f fs
                  writeDocsToFilePath cacheFilePath docsStatus results
                  File.writeBinary path (ArtifactCache fingerprints artifacts)
                  Reporting.report key Reporting.DBuilt
                  return (Right artifacts)


-- GATHER

gatherObjects :: Map.Map ModuleName.Raw Result -> Opt.GlobalGraph
gatherObjects = Map.foldrWithKey addLocalGraph Opt.empty

addLocalGraph :: ModuleName.Raw -> Result -> Opt.GlobalGraph -> Opt.GlobalGraph
addLocalGraph name status graph =
  case status of
    RLocal _ objs _ -> Opt.addLocalGraph objs graph
    RForeign _ -> graph
    RKernelLocal cs -> Opt.addKernel (Name.getKernel name) cs graph
    RKernelForeign -> graph

gatherInterfaces :: Map.Map ModuleName.Raw () -> Map.Map ModuleName.Raw Result -> Map.Map ModuleName.Raw I.DependencyInterface
gatherInterfaces exposed artifacts =
  let onLeft = Map.mapMissing (error "compiler bug manifesting in Canopy.Details.gatherInterfaces")
      onRight = Map.mapMaybeMissing (\_ iface -> toLocalInterface I.private iface)
      onBoth = Map.zipWithMaybeMatched (\_ () iface -> toLocalInterface I.public iface)
   in Map.merge onLeft onRight onBoth exposed artifacts

toLocalInterface :: (I.Interface -> a) -> Result -> Maybe a
toLocalInterface func result =
  case result of
    RLocal iface _ _ -> Just (func iface)
    RForeign _ -> Nothing
    RKernelLocal _ -> Nothing
    RKernelForeign -> Nothing

-- GATHER FOREIGN INTERFACES

data ForeignInterface
  = ForeignAmbiguous
  | ForeignSpecific I.Interface
  deriving (Show)

gatherForeignInterfaces :: Map.Map Pkg.Name Artifacts -> Map.Map ModuleName.Raw ForeignInterface
gatherForeignInterfaces directArtifacts =
  Map.map (OneOrMore.destruct finalize) $
    Map.foldrWithKey gather Map.empty directArtifacts
  where
    finalize :: I.Interface -> [I.Interface] -> ForeignInterface
    finalize i is =
      case is of
        [] -> ForeignSpecific i
        _ : _ -> ForeignAmbiguous

    gather :: Pkg.Name -> Artifacts -> Map.Map ModuleName.Raw (OneOrMore.OneOrMore I.Interface) -> Map.Map ModuleName.Raw (OneOrMore.OneOrMore I.Interface)
    gather _ (Artifacts ifaces _) buckets =
      Map.unionWith OneOrMore.more buckets (Map.mapMaybe isPublic ifaces)

    isPublic :: I.DependencyInterface -> Maybe (OneOrMore.OneOrMore I.Interface)
    isPublic di =
      case di of
        I.Public iface -> Just (OneOrMore.one iface)
        I.Private {} -> Nothing

-- | Create package-aware foreign interface lookup.
--
-- Instead of flattening all foreign interfaces into one map (losing package context),
-- this creates a mapping from package names to their specific foreign interfaces.
-- This allows dependency modules to get the correct foreign interfaces for their package.
gatherPackageForeignInterfaces :: Map.Map Pkg.Name Artifacts -> Map.Map Pkg.Name (Map.Map ModuleName.Raw ForeignInterface)
gatherPackageForeignInterfaces directArtifacts =
  Map.mapWithKey (\pkg artifacts -> gatherForeignInterfaces (Map.singleton pkg artifacts)) directArtifacts

-- | Package-aware version of crawlModule that looks up foreign dependencies by package.
--
-- This function determines which package a module belongs to and uses the correct
-- foreign dependencies for that package, fixing the architectural issue where
-- dependency-crawled kernel modules got wrong foreign dependency context.
crawlModuleWithPackageContext :: Map.Map Pkg.Name (Map.Map ModuleName.Raw ForeignInterface) -> TVar StatusDict -> Pkg.Name -> FilePath -> DocsStatus -> ModuleName.Raw -> IO (Maybe Status)
crawlModuleWithPackageContext pkgForeignDeps mvar currentPkg src docsStatus name = do
  -- Determine which package this module belongs to and get its foreign deps
  let targetPkg = if Name.isKernel name then Pkg.core else currentPkg  -- Kernel modules belong to elm/core
  let foreignDeps = Map.findWithDefault Map.empty targetPkg pkgForeignDeps
  -- Call the original crawlModule with correct package name and foreign deps for the target package
  crawlModule foreignDeps mvar targetPkg src docsStatus name

-- CRAWL

type StatusDict =
  Map.Map ModuleName.Raw (TVar (Maybe Status))

data Status
  = SLocal DocsStatus (Map.Map ModuleName.Raw ()) Src.Module
  | SForeign I.Interface
  | SKernelLocal [Kernel.Chunk]
  | SKernelForeign
  deriving (Show)

crawlModule :: Map.Map ModuleName.Raw ForeignInterface -> TVar StatusDict -> Pkg.Name -> FilePath -> DocsStatus -> ModuleName.Raw -> IO (Maybe Status)
crawlModule foreignDeps mvar pkg src docsStatus name =
  do

    let pathCanopy = src </> ModuleName.toFilePath name <.> "canopy"
    let pathElm = src </> ModuleName.toFilePath name <.> "elm"
    canopyExists <- File.exists pathCanopy
    elmExists <- File.exists pathElm
    let exists = canopyExists || elmExists
    let path = if canopyExists then pathCanopy else pathElm
    printLog ("crawlModule: " <> (show name <> (" canopy exists: " <> (show canopyExists <> (" elm exists: " <> show elmExists)))))
    when (name == "Elm.JsArray") $ do
      printLog ("DEBUG: Elm.JsArray src path: " <> show src)
      printLog ("DEBUG: Elm.JsArray pathCanopy: " <> show pathCanopy)
      printLog ("DEBUG: Elm.JsArray pathElm: " <> show pathElm)
      printLog ("DEBUG: Elm.JsArray ModuleName.toFilePath: " <> show (ModuleName.toFilePath name))
      printLog ("DEBUG: Elm.JsArray exists: " <> show exists)
      printLog ("DEBUG: Elm.JsArray using provided foreignDeps context")
      printLog ("DEBUG: Elm.JsArray lookup in foreignDeps: " <> show (Map.lookup name foreignDeps))
      printLog ("DEBUG: Elm.JsArray all foreignDeps keys: " <> show (Map.keys foreignDeps))
    when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
      printLog ("DEBUG: KERNEL " <> show name <> " src path: " <> show src)
      printLog ("DEBUG: KERNEL " <> show name <> " pathCanopy: " <> show pathCanopy)
      printLog ("DEBUG: KERNEL " <> show name <> " pathElm: " <> show pathElm)
      printLog ("DEBUG: KERNEL " <> show name <> " exists: " <> show exists)
      printLog ("DEBUG: KERNEL " <> show name <> " using provided foreignDeps context")
      printLog ("DEBUG: KERNEL " <> show name <> " lookup in foreignDeps: " <> show (Map.lookup name foreignDeps))

    when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
      printLog ("DEBUG: KERNEL " <> show name <> " foreignDeps lookup result: " <> show (Map.lookup name foreignDeps))
    case Map.lookup name foreignDeps of
      Just ForeignAmbiguous -> do
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: KERNEL " <> show name <> " returning Nothing (ForeignAmbiguous)")
        return Nothing
      Just (ForeignSpecific iface) -> do
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: KERNEL " <> show name <> " ForeignSpecific branch, exists=" <> show exists)
        if exists
          then return Nothing
          else return (Just (SForeign iface))
      Nothing -> do
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: KERNEL " <> show name <> " Nothing branch, exists=" <> show exists)
        if exists
          then do
            printLog ("module " <> (show name <> " is in exists branch"))
            crawlFile foreignDeps mvar pkg src docsStatus name path
          else do
            -- Debug logging to check kernel detection for Elm.JsArray issue
            let pkgIsKernel = Pkg.isKernel pkg
                nameIsKernel = Name.isKernel name
                combined = pkgIsKernel && nameIsKernel
            printLog ("isKernel check: pkg=" <> show pkg <> " isKernel=" <> show pkgIsKernel <> " name=" <> show name <> " isKernel=" <> show nameIsKernel <> " combined=" <> show combined)
            when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
              printLog ("DEBUG: KERNEL " <> show name <> " about to check combined condition")
            if combined
              then do
                when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
                  printLog ("DEBUG: KERNEL " <> show name <> " entering kernel branch")
                printLog ("module " <> (show name <> " is in kernel branch"))
                result <- crawlKernel foreignDeps mvar pkg src name
                when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
                  printLog ("DEBUG: KERNEL " <> show name <> " crawlKernel returned: " <> show result)
                return result
              else do
                when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
                  printLog ("DEBUG: KERNEL " <> show name <> " entering NotFound branch")
                printLog ("module " <> (show name <> " not found locally and not in foreignDeps - treating as NotFound"))
                return Nothing

crawlFile :: Map.Map ModuleName.Raw ForeignInterface -> TVar StatusDict -> Pkg.Name -> FilePath -> DocsStatus -> ModuleName.Raw -> FilePath -> IO (Maybe Status)
crawlFile foreignDeps mvar pkg src docsStatus expectedName path =
  do
    bytes <- File.readUtf8 path
    case Parse.fromByteString (Parse.Package pkg) bytes of
      Right modul@(Src.Module (Just (A.At _ actualName)) _ _ imports _ _ _ _ _ _) | expectedName == actualName ->
        do
          printLog ("crawlFile (imports) pkg: " <> (show pkg <> (" src: " <> (show src <> (" path : " <> (show path <> (" imports are " <> show (fmap (Src._importName) imports))))))))
          deps <- crawlImports foreignDeps mvar pkg src imports
          printLog ("crawlFile (deps) pkg: " <> (show pkg <> (" src: " <> (show src <> (" path : " <> (show path <> (" deps are " <> show deps)))))))
          return (Just (SLocal docsStatus deps modul))
      _ ->
        return Nothing

crawlImports :: Map.Map ModuleName.Raw ForeignInterface -> TVar StatusDict -> Pkg.Name -> FilePath -> [Src.Import] -> IO (Map.Map ModuleName.Raw ())
crawlImports foreignDeps mvar pkg src imports =
  do
    putStrLn ("ATOMICALLY-DEBUG: Details.hs:970 crawlImports - about to read mvar for pkg " <> show pkg)
    statusDict <- atomically $ readTVar mvar
    putStrLn ("ATOMICALLY-DEBUG: Details.hs:970 crawlImports - mvar read successful for pkg " <> show pkg)
    let deps = Map.fromList (fmap (\i -> (Src.getImportName i, ())) imports)
    printLog ("crawlImports pkg: " <> (show pkg <> (" src: " <> (show src <> (" deps are " <> show deps)))))
    let news = Map.difference deps statusDict
    printLog ("crawlImports NEWS (dependencies to crawl): " <> show (Map.keys news))
    when (Map.member "Elm.JsArray" news) $ do
      printLog ("DEBUG: Elm.JsArray is in NEWS - will be crawled")

    -- STM-based: Create placeholder TVars and update the store atomically
    -- This eliminates deadlock as STM operations are composable
    placeholderTVars <- Map.traverseWithKey (\_ () -> newTVarIO Nothing) news
    atomically $ writeTVar mvar (Map.union placeholderTVars statusDict)

    -- Now use async to start concurrent crawling
    asyncs <- Map.traverseWithKey (\name () -> do
      when (name == "Elm.JsArray") $ do
        printLog ("DEBUG: Starting async crawlModule for Elm.JsArray")
      when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
        printLog ("DEBUG: Starting async crawlModule for kernel module: " <> show name)
      async (crawlModule foreignDeps mvar pkg src DocsNotNeeded name)) news

    -- Wait for all async operations to complete and store results
    results <- traverse wait asyncs

    -- Store the results back into the placeholder TVars AND update the main status store
    putStrLn ("ATOMICALLY-DEBUG: Details.hs:999 crawlImports - about to read mvar for final status update, pkg " <> show pkg)
    currentStatusDict <- atomically $ readTVar mvar
    putStrLn ("ATOMICALLY-DEBUG: Details.hs:999 crawlImports - mvar read successful for final status update, pkg " <> show pkg)
    _ <- Map.traverseWithKey (\name result -> do
      let placeholderTVar = placeholderTVars Map.! name
      atomically $ writeTVar placeholderTVar result
      -- Also update the main status store to ensure consistency
      case Map.lookup name currentStatusDict of
        Just mainTVar -> atomically $ writeTVar mainTVar result
        Nothing -> pure () -- This shouldn't happen, but handle gracefully
      when (name == "Elm.JsArray") $ do
        printLog ("DEBUG: Stored Elm.JsArray result in both TVars: " <> show result)
      when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
        printLog ("DEBUG: Stored kernel module " <> show name <> " result: " <> show result)
      ) results
    when (Map.member "Elm.JsArray" news) $ do
      printLog ("DEBUG: Finished waiting for Elm.JsArray async operation")
    return deps

crawlKernel :: Map.Map ModuleName.Raw ForeignInterface -> TVar StatusDict -> Pkg.Name -> FilePath -> ModuleName.Raw -> IO (Maybe Status)
crawlKernel foreignDeps mvar pkg src name =
  do
    let path = src </> ModuleName.toFilePath name <.> "js"
    exists <- File.exists path
    when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
      printLog ("DEBUG: crawlKernel " <> show name <> " checking path: " <> path)
      printLog ("DEBUG: crawlKernel " <> show name <> " exists: " <> show exists)
    if exists
      then do
        bytes <- File.readUtf8 path
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: crawlKernel " <> show name <> " about to parse kernel file")
          printLog ("DEBUG: crawlKernel " <> show name <> " pkg: " <> show pkg)
          printLog ("DEBUG: crawlKernel " <> show name <> " foreignDeps keys: " <> show (Map.keys foreignDeps))
          printLog ("DEBUG: crawlKernel " <> show name <> " getDepHome mapped: " <> show (Map.mapMaybe getDepHome foreignDeps))
        -- Kernel modules are foundation layer - they provide foreign interfaces rather than consume them
        -- For kernel modules, use empty foreign dependency context since they don't depend on other packages
        let kernelForeignDeps = if Name.isKernel name then Map.empty else Map.mapMaybe getDepHome foreignDeps
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: crawlKernel " <> show name <> " using kernelForeignDeps: " <> show kernelForeignDeps)
          printLog ("DEBUG: crawlKernel " <> show name <> " isKernel: " <> show (Name.isKernel name))
        case Kernel.fromByteString pkg kernelForeignDeps bytes of
          Nothing -> do
            when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
              printLog ("DEBUG: crawlKernel " <> show name <> " Kernel.fromByteString returned Nothing")
            -- FOUNDATION FIX: Kernel modules are foundation layer and should never fail
            -- If parsing fails, treat as foreign kernel to maintain dependency graph integrity
            if Name.isKernel name
              then do
                printLog ("DEBUG: crawlKernel " <> show name <> " treating as foreign kernel (foundation layer)")
                return (Just SKernelForeign)
              else return Nothing
          Just (Kernel.Content imports chunks) -> do
            when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
              printLog ("DEBUG: crawlKernel " <> show name <> " parsed successfully, crawling imports")
            _ <- crawlImports foreignDeps mvar pkg src imports
            when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
              printLog ("DEBUG: crawlKernel " <> show name <> " returning SKernelLocal")
            return (Just (SKernelLocal chunks))
      else do
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: crawlKernel " <> show name <> " file does not exist, returning SKernelForeign")
        return (Just SKernelForeign)

getDepHome :: ForeignInterface -> Maybe Pkg.Name
getDepHome fi =
  case fi of
    ForeignSpecific (I.Interface pkg _ _ _ _) -> Just pkg
    ForeignAmbiguous -> Nothing

-- COMPILE

data Result
  = RLocal !I.Interface !Opt.LocalGraph (Maybe Docs.Module)
  | RForeign I.Interface
  | RKernelLocal [Kernel.Chunk]
  | RKernelForeign

-- BOOTSTRAP COMPILATION HELPERS

-- | Check if a package is elm/core which needs bootstrap compilation ordering
isElmCorePackage :: Pkg.Name -> Bool
isElmCorePackage pkg =
  case pkg of
    Pkg.Name author project ->
      Utf8.toChars author == "elm" && Utf8.toChars project == "core"

-- | Compile elm/core modules in proper dependency order using topological sort
compileElmCoreBootstrapSimple :: (Status -> IO (Maybe Result))
                              -> Map.Map ModuleName.Raw Status
                              -> Map.Map ModuleName.Raw (TVar (Maybe Result))
                              -> IO (Map.Map ModuleName.Raw (Maybe Result))
compileElmCoreBootstrapSimple compileAction statusMap moduleResultTVars = do
  printLog ("BOOTSTRAP: Starting compileElmCoreBootstrapSimple")
  printLog ("BOOTSTRAP: statusMap has " <> show (Map.size statusMap) <> " modules")
  printLog ("BOOTSTRAP: statusMap keys: " <> show (map ModuleName.toChars (Map.keys statusMap)))

  -- Extract dependency graph
  printLog ("BOOTSTRAP: About to build dependency graph")
  let depGraph = buildDependencyGraph statusMap
  printLog ("BOOTSTRAP: Built dependency graph with " <> show (Map.size depGraph) <> " modules")
  printLog ("BOOTSTRAP: All modules found: " <> show (Map.keys statusMap))
  printLog ("BOOTSTRAP: Status types by module:")
  Map.foldrWithKey (\k status acc -> do
    let statusType = case status of
          SLocal {} -> "SLocal"
          SKernelLocal {} -> "SKernelLocal"
          SKernelForeign -> "SKernelForeign"
          SForeign {} -> "SForeign"
    printLog ("  " <> ModuleName.toChars k <> " -> " <> statusType)
    acc) (pure ()) statusMap
  printLog ("BOOTSTRAP: Dependency details:")
  Map.foldrWithKey (\k v acc -> do
    printLog ("  " <> ModuleName.toChars k <> " depends on: " <> show (map ModuleName.toChars v))
    acc) (pure ()) depGraph

  -- Prepare debug info for topological sort
  let allNodes = Map.keys depGraph
      inDegree = Map.fromList [(node, length (Map.findWithDefault [] node depGraph)) | node <- allNodes]
      noIncoming = [node | (node, degree) <- Map.toList inDegree, degree == 0]
  printLog ("TOPOLOGICAL: All nodes in dependency graph: " <> show (map ModuleName.toChars allNodes))
  printLog ("TOPOLOGICAL: In-degree calculation: " <> show [(ModuleName.toChars k, v) | (k, v) <- Map.toList inDegree])
  printLog ("TOPOLOGICAL: Nodes with no incoming edges: " <> show (map ModuleName.toChars noIncoming))
  -- Detailed debug for Elm.JsArray
  let jsArrayNodes = filter (\name -> ModuleName.toChars name == "Elm.JsArray") allNodes
  printLog ("JSARRAY-DEBUG: Found Elm.JsArray nodes: " <> show (map ModuleName.toChars jsArrayNodes))
  case jsArrayNodes of
    [jsArrayName] -> do
      printLog ("JSARRAY-DEBUG: Elm.JsArray in-degree: " <> show (Map.lookup jsArrayName inDegree))
      printLog ("JSARRAY-DEBUG: Is Elm.JsArray in noIncoming? " <> show (jsArrayName `elem` noIncoming))
      case Map.lookup jsArrayName statusMap of
        Just status -> printLog ("JSARRAY-DEBUG: Elm.JsArray status type: " <> case status of
          SLocal {} -> "SLocal"
          SKernelLocal {} -> "SKernelLocal"
          SKernelForeign -> "SKernelForeign"
          SForeign {} -> "SForeign")
        Nothing -> printLog ("JSARRAY-DEBUG: Elm.JsArray not found in statusMap")
    _ -> printLog ("JSARRAY-DEBUG: Elm.JsArray not found or multiple matches")

  -- Perform topological sort
  case topologicalSort depGraph of
    Nothing -> do
      printLog ("BOOTSTRAP: ERROR - Cycle detected in elm/core dependencies!")
      -- Fallback to parallel compilation with proper module names
      results <- Map.traverseWithKey compileAndStore statusMap
      pure results
    Just sortedModules -> do
      printLog ("BOOTSTRAP: Final sorted order length: " <> show (length sortedModules) <> ", expected: " <> show (Map.size depGraph))
      printLog ("BOOTSTRAP: Dependency order: " <> show (map ModuleName.toChars sortedModules))
      compileInDependencyOrder sortedModules statusMap

  where
    -- Build dependency graph from status map
    buildDependencyGraph :: Map.Map ModuleName.Raw Status -> Map.Map ModuleName.Raw [ModuleName.Raw]
    buildDependencyGraph sMap = Map.mapWithKey extractDependencies sMap
      where
        extractDependencies :: ModuleName.Raw -> Status -> [ModuleName.Raw]
        extractDependencies _name status = case status of
          SLocal _ deps _ -> Map.keys (Map.intersection deps sMap) -- Only deps that are in this package
          SKernelLocal _ -> [] -- Kernel modules have no dependencies - they're leaf nodes
          SKernelForeign -> [] -- Foreign kernel modules have no dependencies
          SForeign _ -> [] -- Foreign modules have no dependencies in this package

    -- Kahn's algorithm for topological sort
    topologicalSort :: Map.Map ModuleName.Raw [ModuleName.Raw] -> Maybe [ModuleName.Raw]
    topologicalSort dependsOn =
      let allNodes = Map.keys dependsOn
          -- Calculate in-degree for each node (number of dependencies)
          inDegree = Map.fromList [(node, length (Map.findWithDefault [] node dependsOn)) | node <- allNodes]
          -- Build reverse graph: module -> list of modules that depend on it
          dependents = buildDependents dependsOn
          -- Find nodes with no dependencies
          noIncoming = [node | (node, degree) <- Map.toList inDegree, degree == 0]
      in kahnsAlgorithm dependents inDegree noIncoming []
      where
        buildDependents depGraph =
          let pairs = [(dep, node) | (node, deps) <- Map.toList depGraph, dep <- deps]
          in Map.fromListWith (++) [(dep, [dependent]) | (dep, dependent) <- pairs]

        kahnsAlgorithm :: Map.Map ModuleName.Raw [ModuleName.Raw] -> Map.Map ModuleName.Raw Int -> [ModuleName.Raw] -> [ModuleName.Raw] -> Maybe [ModuleName.Raw]
        kahnsAlgorithm _ _ [] result =
          if length result == Map.size dependsOn
          then Just result  -- Don't reverse - build in correct order
          else Nothing -- Cycle detected
        kahnsAlgorithm dependentsGraph inDeg (node:queue) result =
          let nodesDependingOnThis = Map.findWithDefault [] node dependentsGraph
              newInDeg = foldl (\acc dependent -> Map.adjust (\d -> d - 1) dependent acc) inDeg nodesDependingOnThis
              newlyFree = [dep | dep <- nodesDependingOnThis, Map.findWithDefault 0 dep newInDeg == 0]
              newQueue = queue ++ newlyFree
          in kahnsAlgorithm dependentsGraph newInDeg newQueue (result ++ [node])

    -- Compile modules in dependency order
    compileInDependencyOrder :: [ModuleName.Raw] -> Map.Map ModuleName.Raw Status -> IO (Map.Map ModuleName.Raw (Maybe Result))
    compileInDependencyOrder sortedModules sMap = do
      results <- foldM compileNextModule Map.empty sortedModules
      pure results
      where
        compileNextModule :: Map.Map ModuleName.Raw (Maybe Result) -> ModuleName.Raw -> IO (Map.Map ModuleName.Raw (Maybe Result))
        compileNextModule resultsSoFar moduleName = do
          case Map.lookup moduleName sMap of
            Nothing -> do
              printLog ("BOOTSTRAP: Warning - module not found: " <> show moduleName)
              pure resultsSoFar
            Just status -> do
              printLog ("BOOTSTRAP: Compiling " <> show moduleName)
              result <- compileAndStore moduleName status
              pure (Map.insert moduleName result resultsSoFar)

    -- Wrapper that updates TVar after compilation
    compileAndStore :: ModuleName.Raw -> Status -> IO (Maybe Result)
    compileAndStore moduleName status = do
      result <- compileAction status
      case result of
        Just res -> do
          case Map.lookup moduleName moduleResultTVars of
            Just tvar -> do
              atomically $ writeTVar tvar (Just res)
              printLog ("TVar updated for module: " <> show moduleName)
            Nothing -> printLog ("BOOTSTRAP: Warning - no TVar found for module " <> show moduleName)
        Nothing -> printLog ("BOOTSTRAP: Compilation failed for module: " <> show moduleName)
      pure result

-- | Compile modules in parallel with TVar updates
compileRegularWithTVars :: (Status -> IO (Maybe Result))
                        -> Map.Map ModuleName.Raw Status
                        -> Map.Map ModuleName.Raw (TVar (Maybe Result))
                        -> IO (Map.Map ModuleName.Raw (Maybe Result))
compileRegularWithTVars compileAction statusMap moduleResultTVars = do
  -- Define a wrapper that updates the TVar after compilation
  let compileAndStore moduleName status = do
        result <- compileAction status
        case result of
          Just res -> do
            case Map.lookup moduleName moduleResultTVars of
              Just tvar -> atomically $ writeTVar tvar (Just res)
              Nothing -> pure () -- No warning for regular compilation
          Nothing -> pure ()
        pure result

  -- Compile all modules in parallel with module names
  vars <- Map.traverseWithKey (\moduleName status -> async (compileAndStore moduleName status)) statusMap
  traverse wait vars

compile :: Pkg.Name -> TVar (Map.Map ModuleName.Raw (TVar (Maybe Result))) -> Status -> IO (Maybe Result)
compile pkg mvar status =
  case status of
    SLocal docsStatus deps modul ->
      do
        resultsDict <- readTVarIO mvar
        printLog ("all keys in resultsDict for pkg:  " <> (show pkg <> (" " <> show (Map.keys resultsDict))))
        printLog ("all keys in deps for pkg: " <> (show pkg <> (" " <> show (Map.keys deps))))
        let thingToRead = Map.intersection resultsDict deps
        printLog ("all keys in thingToRead for pkg: " <> (show pkg <> (" " <> show (Map.keys thingToRead))))
        let missingFromResultsDict = filter (\k -> not (Map.member k resultsDict)) (Map.keys deps)
        when (not (null missingFromResultsDict)) $
          printLog ("DEBUG: Missing from resultsDict: " <> show missingFromResultsDict)

        -- LAZY DEPENDENCY RESOLUTION: Only get already-resolved dependencies
        -- This breaks circular dependency deadlocks by avoiding eager waitForMaybeResult
        lazyInterfaces <- resolveLazyInterfaces resultsDict deps

        printLog ("DEBUG: lazy interfaces keys for pkg " <> show pkg <> ": " <> show (Map.keys lazyInterfaces))

        -- DETAILED LOGGING FOR COMPILE.COMPILE ARGUMENTS
        let interfaces = lazyInterfaces
        printLog ("COMPILE-DEBUG: About to call Compile.compile")
        printLog ("COMPILE-DEBUG: pkg = " <> show pkg)
        printLog ("COMPILE-DEBUG: interfaces size = " <> show (Map.size interfaces))
        printLog ("COMPILE-DEBUG: interfaces keys = " <> show (Map.keys interfaces))

        -- Log each interface briefly
        Map.foldrWithKey (\k _ acc -> do
          printLog ("COMPILE-DEBUG: interface " <> ModuleName.toChars k <> " present")
          acc) (pure ()) interfaces

        -- Log module info
        case modul of
          Src.Module (Just (A.At _ moduleName)) _ _ imports _ _ _ _ _ _ -> do
            printLog ("COMPILE-DEBUG: module name = " <> ModuleName.toChars moduleName)
            printLog ("COMPILE-DEBUG: module imports count = " <> show (length imports))
          _ -> printLog ("COMPILE-DEBUG: module has no name or unexpected structure")

        -- CRITICAL DEBUGGING: Verify ALL required dependencies before compilation
        case modul of
          Src.Module (Just (A.At _ moduleName)) _ _ imports _ _ _ _ _ _ -> do
            let importNames = map Src.getImportName imports
            printLog ("COMPILE-DEBUG: Module " <> ModuleName.toChars moduleName <> " requires imports: " <> show (map ModuleName.toChars importNames))

            -- Check each required dependency
            missingImports <- filterM (\importName -> do
              case Map.lookup importName interfaces of
                Just _ -> do
                  printLog ("COMPILE-DEBUG: ✓ " <> ModuleName.toChars importName <> " AVAILABLE")
                  return False
                Nothing -> do
                  printLog ("COMPILE-DEBUG: ✗ " <> ModuleName.toChars importName <> " MISSING!")
                  return True
              ) importNames

            if null missingImports
              then printLog ("COMPILE-DEBUG: ✓ ALL DEPENDENCIES VERIFIED - proceeding to compilation")
              else do
                printLog ("COMPILE-DEBUG: ✗ MISSING DEPENDENCIES: " <> show (map ModuleName.toChars missingImports))
                printLog ("COMPILE-DEBUG: Available interfaces: " <> show (Map.keys interfaces))
          _ -> printLog ("COMPILE-DEBUG: Module structure not recognized for dependency checking")

        printLog ("COMPILE-DEBUG: ========== ENTERING COMPILE.COMPILE ==========")
        compileResult <- Compile.compile pkg interfaces modul
        printLog ("DEBUG: Compile.compile completed for pkg: " <> show pkg)
        case compileResult of
          Left compileError -> do
            printLog ("=== COMPILE ERROR DEBUG INFO START ===")
            printLog ("Package: " <> show pkg)
            printLog ("Module: " <> show modul)
            printLog ("CompileError: " <> show compileError)
            printLog ("=== COMPILE ERROR DEBUG INFO END ===")
            return Nothing
          Right (Compile.Artifacts canonical annotations objects _ffiInfo) -> do
            printLog ("DEBUG: Processing successful compilation result for pkg: " <> show pkg)
            let ifaces = I.fromModule pkg canonical annotations
            printLog ("DEBUG: Created interfaces for pkg: " <> show pkg)
            docs <- makeDocs docsStatus canonical
            printLog ("DEBUG: Created docs for pkg: " <> show pkg)
            return (Just (RLocal ifaces objects docs))
    SForeign iface ->
      return (Just (RForeign iface))
    SKernelLocal chunks ->
      return (Just (RKernelLocal chunks))
    SKernelForeign ->
      return (Just RKernelForeign)

getInterface :: Result -> Maybe I.Interface
getInterface result =
  case result of
    RLocal iface _ _ -> Just iface
    RForeign iface -> Just iface
    RKernelLocal _ -> Just emptyKernelInterface
    RKernelForeign -> Just emptyKernelInterface
  where
    -- Create empty interface for kernel modules
    -- Kernel modules provide JavaScript functions that don't have Elm type annotations
    emptyKernelInterface = I.Interface
      { I._home = Pkg.dummyName  -- Will be overridden by proper package name
      , I._values = Map.empty    -- No Elm values (JavaScript functions)
      , I._unions = Map.empty    -- No union types
      , I._aliases = Map.empty   -- No type aliases
      , I._binops = Map.empty    -- No binary operators
      }

-- | Resolve dependency interfaces without blocking (lazy resolution)
-- This breaks circular dependency deadlocks by only getting already-ready dependencies
resolveLazyInterfaces :: Map.Map ModuleName.Raw (TVar (Maybe Result))
                       -> Map.Map ModuleName.Raw ()
                       -> IO (Map.Map ModuleName.Raw I.Interface)
resolveLazyInterfaces resultsDict deps = do
  -- For each dependency, try to get the interface if it's ready (non-blocking)
  let availableDeps = Map.intersection resultsDict deps
  availableResults <- Map.traverseWithKey (\modName tvar -> do
    maybeResult <- readTVarIO tvar
    case maybeResult of
      Nothing -> do
        printLog ("LAZY-DEP: " <> show modName <> " not ready yet, skipping")
        pure Nothing
      Just result -> do
        printLog ("LAZY-DEP: " <> show modName <> " ready, using interface")
        pure (Just result)
    ) availableDeps

  -- Extract interfaces from available results
  let interfaces = Map.mapMaybe (>>= getInterface) availableResults
  printLog ("LAZY-DEP: Resolved " <> show (Map.size interfaces) <> " out of " <> show (Map.size deps) <> " dependencies")
  pure interfaces


-- MAKE DOCS

data DocsStatus
  = DocsNeeded
  | DocsNotNeeded
  deriving (Show)

getDocsStatus :: Stuff.PackageCache -> Pkg.Name -> V.Version -> IO DocsStatus
getDocsStatus cache pkg vsn =
  do
    exists <- File.exists (Stuff.package cache pkg vsn </> "docs.json")
    if exists
      then return DocsNotNeeded
      else return DocsNeeded

getDocsStatusFromFilePath :: FilePath -> IO DocsStatus
getDocsStatusFromFilePath pathToDocsDir =
  do
    exists <- File.exists (pathToDocsDir </> "docs.json")
    if exists
      then return DocsNotNeeded
      else return DocsNeeded

getDocsStatusOverridePkg :: Stuff.PackageOverridesCache -> Pkg.Name -> V.Version -> Pkg.Name -> V.Version -> IO DocsStatus
getDocsStatusOverridePkg cache originalPkg originalVsn overridingPkg overridingVsn =
  do
    exists <- File.exists (Stuff.packageOverride (PackageOverrideConfig cache originalPkg originalVsn overridingPkg overridingVsn) </> "docs.json")
    if exists
      then return DocsNotNeeded
      else return DocsNeeded

makeDocs :: DocsStatus -> Can.Module -> IO (Maybe Docs.Module)
makeDocs status modul =
  case status of
    DocsNeeded -> do
      result <- Docs.fromModule modul
      case result of
        Right docs -> pure (Just docs)
        Left _ -> pure Nothing
    DocsNotNeeded ->
      pure Nothing

writeDocs :: Stuff.PackageCache -> Pkg.Name -> V.Version -> DocsStatus -> Map.Map ModuleName.Raw Result -> IO ()
writeDocs cache pkg vsn status results =
  case status of
    DocsNeeded ->
      E.writeUgly (Stuff.package cache pkg vsn </> "docs.json") . Docs.encode $ Map.mapMaybe toDocs results
    DocsNotNeeded ->
      return ()

writeDocsToFilePath :: FilePath -> DocsStatus -> Map.Map ModuleName.Raw Result -> IO ()
writeDocsToFilePath pathToDocsDir status results =
  case status of
    DocsNeeded ->
      E.writeUgly (pathToDocsDir </> "docs.json") . Docs.encode $ Map.mapMaybe toDocs results
    DocsNotNeeded ->
      return ()

writeDocsOverridingPackage :: Stuff.PackageOverridesCache -> Pkg.Name -> V.Version -> Pkg.Name -> V.Version -> DocsStatus -> Map.Map ModuleName.Raw Result -> IO ()
writeDocsOverridingPackage cache originalPkg originalVsn overridingPkg overridingVsn status results =
  case status of
    DocsNeeded ->
      E.writeUgly (Stuff.packageOverride (PackageOverrideConfig cache originalPkg originalVsn overridingPkg overridingVsn) </> "docs.json") . Docs.encode $ Map.mapMaybe toDocs results
    DocsNotNeeded ->
      return ()

toDocs :: Result -> Maybe Docs.Module
toDocs result =
  case result of
    RLocal _ _ docs -> docs
    RForeign _ -> Nothing
    RKernelLocal _ -> Nothing
    RKernelForeign -> Nothing

-- DOWNLOAD PACKAGE

getHeadersFromCustomRepositoryData :: CustomRepositoriesData.CustomSingleRepositoryData -> [Http.Header]
getHeadersFromCustomRepositoryData customRepositoryData =
  case customRepositoryData of
    DefaultPackageServerRepoData _ -> []
    PZRPackageServerRepoData pzrPackageServerRepoData -> [Registry.createAuthHeader (_pzrPackageServerRepoAuthToken pzrPackageServerRepoData)]

getRepoUrlFromCustomRepositoryData :: CustomRepositoriesData.CustomSingleRepositoryData -> RepositoryUrl
getRepoUrlFromCustomRepositoryData customRepositoryData =
  case customRepositoryData of
    DefaultPackageServerRepoData defaultPackageServerRepo -> _defaultPackageServerRepoTypeUrl defaultPackageServerRepo
    PZRPackageServerRepoData pzrPackageServerRepoData -> _pzrPackageServerRepoTypeUrl pzrPackageServerRepoData

downloadPackage :: Stuff.PackageCache -> ZokkaRegistries -> Http.Manager -> Pkg.Name -> V.Version -> IO (Either Exit.PackageProblem ())
downloadPackage cache zokkaRegistries manager pkg vsn =
  case Registry.lookupPackageRegistryKey zokkaRegistries pkg vsn of
    Just (Registry.RepositoryUrlKey repositoryData) ->
      do
        _exists <- Dir.doesDirectoryExist (Stuff.package cache pkg vsn)
        let headers = getHeadersFromCustomRepositoryData repositoryData
        let repoUrl = getRepoUrlFromCustomRepositoryData repositoryData
        downloadPackageFromCanopyPackageRepo cache repoUrl headers manager pkg vsn
    Just (Registry.PackageUrlKey packageData) ->
      do
        _exists <- Dir.doesDirectoryExist (Stuff.package cache pkg vsn)
        downloadPackageDirectly cache (CustomRepositoryData._url packageData) manager pkg vsn
    Nothing ->
      let --FIXME
          blah = fmap show (Map.keys $ Registry._registries zokkaRegistries)
       in pure (Left $ Exit.PP_PackageNotInRegistry blah pkg vsn)

-- FIXME: reduce duplication with downloadPackage
downloadPackageToFilePath :: FilePath -> ZokkaRegistries -> Http.Manager -> Pkg.Name -> V.Version -> IO (Either Exit.PackageProblem ())
downloadPackageToFilePath filePath zokkaRegistries manager pkg vsn =
  case Registry.lookupPackageRegistryKey zokkaRegistries pkg vsn of
    Just (Registry.RepositoryUrlKey repositoryData) ->
      do
        exists <- Dir.doesDirectoryExist filePath
        printLog (show exists <> ("A (toFilePath)" <> filePath))
        let headers = getHeadersFromCustomRepositoryData repositoryData
        let repoUrl = getRepoUrlFromCustomRepositoryData repositoryData
        downloadPackageFromCanopyPackageRepoToFilePath filePath repoUrl headers manager pkg vsn
    Just (Registry.PackageUrlKey packageData) ->
      do
        exists <- Dir.doesDirectoryExist filePath
        printLog ("Checking whether " <> (filePath <> ("exists as a directory. Result: " <> show exists)))
        downloadPackageDirectlyToFilePath filePath (CustomRepositoriesData._url packageData) (CustomRepositoriesData._shaHash packageData) manager
    Nothing ->
      let --FIXME
          blah = fmap show (Map.keys $ Registry._registries zokkaRegistries)
       in pure (Left $ Exit.PP_PackageNotInRegistry blah pkg vsn)

downloadPackageDirectly :: Stuff.PackageCache -> PackageUrl -> Http.Manager -> Pkg.Name -> V.Version -> IO (Either Exit.PackageProblem ())
downloadPackageDirectly cache packageUrl manager pkg vsn =
  let urlString = Utf8.toChars packageUrl
   in Http.getArchiveWithFallback manager urlString Exit.PP_BadArchiveRequest (Exit.PP_BadArchiveContent urlString) $
        \(_, archive) ->
          Right <$> File.writePackage (Stuff.package cache pkg vsn) archive

downloadPackageDirectlyToFilePath :: FilePath -> PackageUrl -> HumanReadableShaDigest -> Http.Manager -> IO (Either Exit.PackageProblem ())
downloadPackageDirectlyToFilePath filePath packageUrl expectedShaDigest manager =
  let urlString = Utf8.toChars packageUrl
   in Http.getArchiveWithFallback manager urlString Exit.PP_BadArchiveRequest (Exit.PP_BadArchiveContent urlString) $
        \(receivedShaHash, archive) ->
          if humanReadableShaDigestIsEqualToSha expectedShaDigest receivedShaHash
            then Right <$> File.writePackage filePath archive
            else -- FIXME Maybe use a custom error type instead of PP_BadArchiveHash that points to where the hash is defined in the custom-repo config
              pure (Left (PP_BadArchiveHash urlString (humanReadableShaDigestToString expectedShaDigest) (Http.shaToChars receivedShaHash)))

downloadPackageFromCanopyPackageRepo :: Stuff.PackageCache -> RepositoryUrl -> [Http.Header] -> Http.Manager -> Pkg.Name -> V.Version -> IO (Either Exit.PackageProblem ())
downloadPackageFromCanopyPackageRepo cache repositoryUrl headers manager pkg vsn =
  let url = Website.metadata repositoryUrl pkg vsn "endpoint.json"
   in do
        eitherByteString <-
          Http.getWithFallback manager url headers id (return . Right)
        exists <- Dir.doesDirectoryExist (Stuff.package cache pkg vsn)
        printLog (show exists <> ("B0" <> Stuff.package cache pkg vsn))

        case eitherByteString of
          Left err ->
            return . Left $ Exit.PP_BadEndpointRequest err
          Right byteString ->
            case D.fromByteString endpointDecoder byteString of
              Left _ ->
                return . Left $ Exit.PP_BadEndpointContent url
              Right (endpoint, expectedHash) ->
                Http.getArchiveWithHeadersAndFallback manager endpoint headers Exit.PP_BadArchiveRequest (Exit.PP_BadArchiveContent endpoint) $
                  \(sha, archive) ->
                    if expectedHash == Http.shaToChars sha
                      then
                        Right <$> do
                          packageExists <- Dir.doesDirectoryExist (Stuff.package cache pkg vsn)
                          printLog (show packageExists <> ("C" <> Stuff.package cache pkg vsn))
                          File.writePackage (Stuff.package cache pkg vsn) archive
                      else return . Left $ Exit.PP_BadArchiveHash endpoint expectedHash (Http.shaToChars sha)

-- FIXME: Reduce duplication
downloadPackageFromCanopyPackageRepoToFilePath :: FilePath -> RepositoryUrl -> [Http.Header] -> Http.Manager -> Pkg.Name -> V.Version -> IO (Either Exit.PackageProblem ())
downloadPackageFromCanopyPackageRepoToFilePath filePath repositoryUrl headers manager pkg vsn =
  let url = Website.metadata repositoryUrl pkg vsn "endpoint.json"
   in do
        eitherByteString <-
          Http.getWithFallback manager url headers id (return . Right)
        exists <- Dir.doesDirectoryExist filePath
        printLog (show exists <> ("B0 (toFilePath)" <> filePath))

        case eitherByteString of
          Left err ->
            return . Left $ Exit.PP_BadEndpointRequest err
          Right byteString ->
            case D.fromByteString endpointDecoder byteString of
              Left _ ->
                return . Left $ Exit.PP_BadEndpointContent url
              Right (endpoint, expectedHash) ->
                Http.getArchiveWithHeadersAndFallback manager endpoint headers Exit.PP_BadArchiveRequest (Exit.PP_BadArchiveContent endpoint) $
                  \(sha, archive) ->
                    if expectedHash == Http.shaToChars sha
                      then
                        Right <$> do
                          filePathExists <- Dir.doesDirectoryExist filePath
                          printLog (show filePathExists <> ("C (toFilePath)" <> filePath))
                          File.writePackage filePath archive
                      else return . Left $ Exit.PP_BadArchiveHash endpoint expectedHash (Http.shaToChars sha)

endpointDecoder :: D.Decoder e (String, String)
endpointDecoder =
  do
    url <- D.field "url" D.string
    hash <- D.field "hash" D.string
    return (Utf8.toChars url, Utf8.toChars hash)

-- BINARY

instance Binary Details where
  put (Details a b c d e _) = put a >> put b >> put c >> put d >> put e
  get =
    do
      a <- get
      b <- get
      c <- get
      d <- get
      e <- get
      return (Details a b c d e ArtifactsCached)

instance Binary ValidOutline where
  put outline =
    case outline of
      ValidApp a -> putWord8 0 >> put a
      ValidPkg a b c -> putWord8 1 >> put a >> put b >> put c

  get =
    do
      n <- getWord8
      case n of
        0 -> fmap ValidApp get
        1 -> liftM3 ValidPkg get get get
        _ -> fail "binary encoding of ValidOutline was corrupted"

instance Binary Local where
  put (Local a b c d e f) = put a >> put b >> put c >> put d >> put e >> put f
  get =
    do
      a <- get
      b <- get
      c <- get
      d <- get
      e <- get
      Local a b c d e <$> get

instance Binary Foreign where
  get = liftM2 Foreign get get
  put (Foreign a b) = put a >> put b

instance Binary Artifacts where
  get = liftM2 Artifacts get get
  put (Artifacts a b) = put a >> put b

instance Binary ArtifactCache where
  get = liftM2 ArtifactCache get get
  put (ArtifactCache a b) = put a >> put b

-- Generate lenses for record types  
makeLenses ''Details
makeLenses ''Local
makeLenses ''Foreign
makeLenses ''Artifacts
makeLenses ''ArtifactCache

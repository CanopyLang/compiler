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
import Debug.Trace (trace)
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
import Control.Lens (makeLenses)
import Control.Exception (Handler (..), SomeException, catches, throwIO, catch, ErrorCall)
import Control.Monad (liftM2, liftM3, void, when, filterM)
import System.IO.Unsafe (unsafePerformIO)
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
loadInterfaces root (Details _ _ _ _ _ extras) = do
  case extras of
    ArtifactsFresh i _ -> do
      newTVarIO (Just i)
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
    -- FOUNDATION LAYER: elm/core will be processed FIRST, then other packages
    -- elm/core is included in dependency resolution but prioritized
    let nonCoreConstraints = constraints  -- Don't filter elm/core anymore

    result <- Task.io $ Solver.verify cache connection registry nonCoreConstraints
    case result of
      Solver.Ok details -> return details
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

          -- Start workers concurrently for all dependencies using STM
          workers <- Stuff.withRegistryLock cache $
            forConcurrently (Map.toList solution) $ \(pkg, details) ->
              async (verifyDep store key (generateBuildData pkg (extractVersionFromDetails details)) manager zokkaRegistries solution (extractConstraintsFromDetails details))

          printLog ("Made it to VERIFYDEPENDENCIES 2: started " <> show (length workers) <> " workers")

          -- Wait for all workers with proper error handling
          deps <- Map.fromList <$> mapM (\(worker, (pkg, _)) -> do
            result <- wait worker
            printLog ("deps result for " <> show pkg)
            return (pkg, result)) (zip workers (Map.toList solution))

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

verifyDep :: DepStore -> Reporting.DKey -> BuildData -> Http.Manager -> ZokkaRegistries -> Map.Map Pkg.Name Solver.Details -> Map.Map Pkg.Name C.Constraint -> IO Dep
verifyDep store key buildData manager zokkaRegistry solution directDeps = do
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
      result <- build store key buildData fingerprint Set.empty manager zokkaRegistry
      -- Mark as completed
      atomically $ completeDependency store primaryPkg result
      return result

build :: DepStore -> Reporting.DKey -> BuildData -> Fingerprint -> Set.Set Fingerprint -> Http.Manager -> ZokkaRegistries -> IO Dep
build store key buildData f fs manager zokkaRegistry = do
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

  -- ELM-CSV DEBUG: Specific logging for BrianHicks/elm-csv
  when (Pkg.toChars pkg == "BrianHicks/elm-csv") $ do
    putStrLn "ELM-CSV-DEBUG: *** STARTING COMPILATION OF BrianHicks/elm-csv ***"
    putStrLn ("ELM-CSV-DEBUG: Version: " <> V.toChars vsn)
    putStrLn ("ELM-CSV-DEBUG: Cache path: " <> cacheFilePath)
    putStrLn ("ELM-CSV-DEBUG: Outline result: " <> show eitherOutline)

  case eitherOutline of
    Left _ -> do
      Reporting.report key Reporting.DBroken
      return $ Left $ Just $ Exit.BD_BadBuild pkg vsn f
    Right (Outline.App _) -> do
      Reporting.report key Reporting.DBroken
      return $ Left $ Just $ Exit.BD_BadBuild pkg vsn f
    Right (Outline.Pkg (Outline.PkgOutline _ _ _ _ exposed deps _ _)) -> do
      putStrLn ("ATOMICALLY-DEBUG: Details.hs:666 - about to wait for dependencies: " <> show (Map.keys deps))

      -- ELM-CSV DEBUG: Log dependency resolution for elm-csv
      when (Pkg.toChars pkg == "BrianHicks/elm-csv") $ do
        putStrLn "ELM-CSV-DEBUG: *** STARTING DEPENDENCY RESOLUTION ***"
        putStrLn ("ELM-CSV-DEBUG: Dependencies required: " <> show (Map.keys deps))
        Map.foldrWithKey (\dep constraint acc -> do
          putStrLn ("ELM-CSV-DEBUG: Dependency " <> Pkg.toChars dep <> " -> " <> show constraint)
          acc) (pure ()) deps

      depResults <- atomically $ waitForDependencies store (Map.keys deps)
      putStrLn ("ATOMICALLY-DEBUG: Details.hs:666 - dependency resolution completed successfully")

      -- ELM-CSV DEBUG: Log dependency resolution results
      when (Pkg.toChars pkg == "BrianHicks/elm-csv") $ do
        putStrLn "ELM-CSV-DEBUG: *** DEPENDENCY RESOLUTION RESULTS ***"
        putStrLn ("ELM-CSV-DEBUG: Number of depResults: " <> show (Map.size depResults))
        Map.foldrWithKey (\depPkg result acc -> do
          case result of
            Left err -> putStrLn ("ELM-CSV-DEBUG: ✗ " <> Pkg.toChars depPkg <> " FAILED: " <> show err)
            Right _ -> putStrLn ("ELM-CSV-DEBUG: ✓ " <> Pkg.toChars depPkg <> " SUCCESS")
          acc) (pure ()) depResults

      case sequenceA depResults of
        Left x -> do
          Reporting.report key Reporting.DBroken
          return $ Left x
        Right directArtifacts -> do
          -- CRITICAL DEBUG: Log directArtifacts content to understand cross-package interface issue
          printLog ("CROSS-PACKAGE-DEBUG: Package " <> show pkg <> " received directArtifacts from packages: " <> show (Map.keys directArtifacts))
          when (pkg == Pkg.json) $ do
            putStrLn ("ELM-JSON-DEBUG: *** elm/json directArtifacts keys: " ++ show (Map.keys directArtifacts))
            putStrLn ("ELM-JSON-DEBUG: *** elm/json expected elm/core in directArtifacts")
            case Map.lookup Pkg.core directArtifacts of
              Nothing -> putStrLn ("ELM-JSON-DEBUG: *** elm/core NOT FOUND in directArtifacts!")
              Just artifacts -> do
                putStrLn ("ELM-JSON-DEBUG: *** elm/core FOUND in directArtifacts")
                let (Artifacts ifaces _) = artifacts
                putStrLn ("ELM-JSON-DEBUG: *** elm/core provides interfaces: " ++ show (Map.keys ifaces))
                putStrLn ("ELM-JSON-DEBUG: *** elm/core total interfaces count: " ++ show (Map.size ifaces))
                -- Debug individual interface types
                let publicCount = length [() | I.Public _ <- Map.elems ifaces]
                let privateCount = length [() | I.Private _ _ _ <- Map.elems ifaces]
                putStrLn ("ELM-JSON-DEBUG: *** elm/core public interfaces: " ++ show (publicCount :: Int))
                putStrLn ("ELM-JSON-DEBUG: *** elm/core private interfaces: " ++ show (privateCount :: Int))
          let src = cacheFilePath </> "src"

          -- Check if source files exist, download if missing
          srcExists <- File.exists src
          when (not srcExists) $ do
            putStrLn ("DOWNLOAD_DEBUG: Source directory missing for " <> show pkg <> ", downloading package...")
            case buildData of
              BuildOriginalPackage (OriginalPackageBuildData {_buildCache = cache}) -> do
                downloadResult <- downloadPackage cache zokkaRegistry manager pkg vsn
                case downloadResult of
                  Left err -> putStrLn ("DOWNLOAD_ERROR: " <> show err)
                  Right () -> putStrLn ("DOWNLOAD_SUCCESS: Downloaded " <> show pkg)
              BuildWithOverridingPackage _ ->
                putStrLn ("DOWNLOAD_SKIP: Package override detected for " <> show pkg)

          -- Create package-aware foreign dependency lookup
          let pkgForeignDeps = gatherPackageForeignInterfaces directArtifacts
          printLog ("DEBUG: Processing package " <> show pkg)
          -- DEBUG: Log foreign interface gathering results
          when (pkg == Pkg.json) $ do
            putStrLn ("ELM-JSON-DEBUG: *** pkgForeignDeps after gathering: " ++ show (Map.keys pkgForeignDeps))
            case Map.lookup Pkg.core pkgForeignDeps of
              Nothing -> putStrLn ("ELM-JSON-DEBUG: *** elm/core foreign interfaces NOT FOUND!")
              Just coreInterfaces -> do
                putStrLn ("ELM-JSON-DEBUG: *** elm/core foreign interfaces FOUND: " ++ show (Map.keys coreInterfaces))
                putStrLn ("ELM-JSON-DEBUG: *** Total elm/core interfaces available: " ++ show (Map.size coreInterfaces))
          let exposedDict = Map.fromSet (const ()) (Set.fromList (Outline.flattenExposed exposed))

          -- Package overrides are optional, normal packages use interface files
          let modulesToCrawl = exposedDict

          docsStatus <- getDocsStatusFromFilePath cacheFilePath
          -- STM-based status tracking for modules
          statusStore <- atomically $ newTVar Map.empty
          mvars <- Map.traverseWithKey (\name _ -> async (crawlModuleWithPackageContext pkgForeignDeps statusStore pkg src docsStatus name)) modulesToCrawl
          statuses <- traverse wait mvars
          case sequenceA statuses of
            Nothing -> do
              Reporting.report key Reporting.DBroken
              printLog ("maybeStatuses were Nothing for " <> (show pkg <> (" vsn " <> (show vsn <> (" and deps " <> show deps)))))
              return $ Left $ Just $ Exit.BD_BadBuild pkg vsn f
            Just _ -> do
              printLog ("DEBUG: MAIN ENTRY POINT - Processing for pkg: " <> show pkg)


              -- STM-based result tracking for compilation
              resultStore <- atomically $ newTVar Map.empty
              let extractDepsFromStatus status = case status of (SLocal _ statusDeps _ _) -> statusDeps; _ -> Map.empty

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

              -- Use ALL modules from finalStatusStore for dependency graph, not just successful ones
              -- This ensures kernel modules are included even if they fail to parse
              let allStatusList = Map.mapWithKey (\name maybeStatus ->
                    case maybeStatus of
                      Just status -> status
                      Nothing -> if Name.isKernel name
                        then SKernelForeign  -- Treat failed kernel modules as foreign
                        else SNotFound ("Module failed to crawl: " <> show name)  -- NEW: Don't throw error, create SNotFound status
                    ) finalStatusValues
              printLog ("DEBUG: allStatusList keys: " <> show (Map.keys allStatusList))
              printLog ("DEBUG: completeStatusList keys: " <> show (Map.keys completeStatusList))
              -- elm/core excluded from pipeline - use regular parallel compilation for all packages
              printLog ("REGULAR: Using regular parallel compilation for " <> show pkg)
              -- ELM-CSV DEBUG: Log before compilation
              when (Pkg.toChars pkg == "BrianHicks/elm-csv") $ do
                putStrLn "ELM-CSV-DEBUG: *** STARTING MODULE COMPILATION ***"
                putStrLn ("ELM-CSV-DEBUG: Number of modules to compile: " <> show (Map.size allStatusList))
                putStrLn ("ELM-CSV-DEBUG: Module names: " <> show (Map.keys allStatusList))

              maybeResults <- compileRegularWithTVars compileAction allStatusList moduleResultTVars

              -- ELM-CSV DEBUG: Log compilation results
              when (Pkg.toChars pkg == "BrianHicks/elm-csv") $ do
                putStrLn "ELM-CSV-DEBUG: *** MODULE COMPILATION COMPLETED ***"
                let successCount = length [() | Just _ <- Map.elems maybeResults]
                let failureCount = length [() | Nothing <- Map.elems maybeResults]
                putStrLn ("ELM-CSV-DEBUG: Successful modules: " <> show successCount)
                putStrLn ("ELM-CSV-DEBUG: Failed modules: " <> show failureCount)
                when (failureCount > 0) $ do
                  let failedModules = Map.keys (Map.filter (\case Nothing -> True; Just _ -> False) maybeResults)
                  putStrLn ("ELM-CSV-DEBUG: Failed module names: " <> show failedModules)

              case sequenceA maybeResults of
                Nothing -> do
                  when (Pkg.toChars pkg == "BrianHicks/elm-csv") $ do
                    putStrLn "ELM-CSV-DEBUG: *** COMPILATION FAILED - sequenceA returned Nothing ***"
                  printLog ("maybeResults were Nothing for " <> (show pkg <> (" vsn " <> (show vsn <> (" and deps from status were " <> show (fmap extractDepsFromStatus allStatusList))))))
                  Reporting.report key Reporting.DBroken
                  return $ Left $ Just $ Exit.BD_BadBuild pkg vsn f
                Just results -> do
                  let path = cacheFilePath </> "artifacts.dat"
                  putStrLn $ "LIST_DEBUG: About to gatherInterfaces for pkg: " ++ show pkg
                  putStrLn $ "LIST_DEBUG: exposedDict keys: " ++ show (Map.keys exposedDict)
                  putStrLn $ "LIST_DEBUG: results keys: " ++ show (Map.keys results)
                  when (Map.member "List" results) $ do
                    putStrLn $ "LIST_DEBUG: *** List is in results map ***"
                  when (Map.member "Tuple" results) $ do
                    putStrLn $ "TUPLE_DEBUG: *** Tuple is in results map ***"
                  when (Map.member "String" results) $ do
                    putStrLn $ "STRING_DEBUG: *** String is in results map ***"
                  let ifaces = gatherInterfaces pkg exposedDict results
                  putStrLn $ "LIST_DEBUG: After gatherInterfaces, ifaces keys: " ++ show (Map.keys ifaces)
                  when (Map.member "List" ifaces) $ do
                    putStrLn $ "LIST_DEBUG: *** List is in ifaces map ***"
                  if Map.member "Tuple" ifaces
                    then putStrLn $ "TUPLE_DEBUG: *** Tuple is in ifaces map ***"
                    else putStrLn $ "TUPLE_DEBUG: *** Tuple is MISSING from ifaces map ***"
                  if Map.member "String" ifaces
                    then putStrLn $ "STRING_DEBUG: *** String is in ifaces map ***"
                    else putStrLn $ "STRING_DEBUG: *** String is MISSING from ifaces map ***"
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
    RNotFound _ -> graph  -- No objects to add for not found modules

-- Check if a module is from elm/core and should always be public
isElmCoreModule :: ModuleName.Raw -> Bool
isElmCoreModule moduleName =
  let name = ModuleName.toChars moduleName
  in name `elem` ["Array", "Basics", "Bitwise", "Char", "Debug", "Dict", "List", "Maybe", "Platform", "Platform.Cmd", "Platform.Sub", "Process", "Result", "Set", "String", "Task", "Tuple"]

gatherInterfaces :: Pkg.Name -> Map.Map ModuleName.Raw () -> Map.Map ModuleName.Raw Result -> Map.Map ModuleName.Raw I.DependencyInterface
gatherInterfaces _pkg exposed artifacts =
  let -- Handle exposed modules that are missing from artifacts
      onLeft = Map.mapMissing (\key _ ->
        let moduleName = ModuleName.toChars key
        in trace ("GATHER_INTERFACES_WARNING: Module '" ++ moduleName ++ "' is exposed but missing from compilation artifacts. This indicates the module failed to crawl or compile properly.") $
           error ("GATHER_INTERFACES_ERROR: Module '" ++ moduleName ++ "' is exposed but missing from compilation artifacts."))

      -- Handle modules in artifacts but not exposed
      -- CRITICAL FIX: elm/core modules should always be public, not private
      onRight = Map.mapMaybeMissing (\key iface ->
        case iface of
          RNotFound reason -> trace ("GATHER_INTERFACES_INFO: Module '" ++ ModuleName.toChars key ++ "' not found: " ++ reason) Nothing
          _ -> if isElmCoreModule key
            then if ModuleName.toChars key == "List"
              then trace "LIST_DEBUG: *** List found in artifacts (elm/core module - making public) ***" (toLocalInterface I.public iface)
              else if ModuleName.toChars key == "Tuple"
                then trace "TUPLE_DEBUG: *** Tuple found in artifacts (elm/core module - making public) ***" (toLocalInterface I.public iface)
                else if ModuleName.toChars key == "String"
                  then trace "STRING_DEBUG: *** String found in artifacts (elm/core module - making public) ***" (toLocalInterface I.public iface)
                  else toLocalInterface I.public iface  -- All elm/core modules are public
            else if ModuleName.toChars key == "List"
              then trace "LIST_DEBUG: *** List found in artifacts but not exposed (private) ***" (toLocalInterface I.private iface)
              else if ModuleName.toChars key == "Tuple"
                then trace "TUPLE_DEBUG: *** Tuple found in artifacts but not exposed (private) ***" (toLocalInterface I.private iface)
                else if ModuleName.toChars key == "String"
                  then trace "STRING_DEBUG: *** String found in artifacts but not exposed (private) ***" (toLocalInterface I.private iface)
                  else toLocalInterface I.private iface)

      -- Handle modules that are both exposed and in artifacts
      onBoth = Map.zipWithMaybeMatched (\key () iface ->
        case iface of
          RNotFound reason -> trace ("GATHER_INTERFACES_SKIP: Exposed module '" ++ ModuleName.toChars key ++ "' not found: " ++ reason) Nothing
          _ -> if ModuleName.toChars key == "List"
            then trace "LIST_DEBUG: *** List found in both exposed and artifacts (public) ***" (toLocalInterface I.public iface)
            else if ModuleName.toChars key == "Tuple"
              then trace "TUPLE_DEBUG: *** Tuple found in both exposed and artifacts (public) ***" (toLocalInterface I.public iface)
              else if ModuleName.toChars key == "String"
                then trace "STRING_DEBUG: *** String found in both exposed and artifacts (public) ***" (toLocalInterface I.public iface)
                else toLocalInterface I.public iface)

      result = Map.merge onLeft onRight onBoth exposed artifacts
   in result

toLocalInterface :: (I.Interface -> a) -> Result -> Maybe a
toLocalInterface func result =
  case result of
    RLocal iface _ _ -> Just (func iface)
    RForeign iface -> Just (func iface)  -- Support foreign interfaces too
    RKernelLocal _ -> Nothing
    RKernelForeign -> Nothing
    RNotFound _ -> Nothing  -- No interface for not found modules

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
  Map.mapWithKey processPackage directArtifacts
  where
    processPackage pkg artifacts =
      let singletonMap = Map.singleton pkg artifacts
          foreignIfaces = gatherForeignInterfaces singletonMap
      in
      -- Debug the foreign interface gathering process for elm/core
      if pkg == Pkg.core then
        let _ = unsafePerformIO $ do
              putStrLn ("GATHER-DEBUG: *** Processing elm/core in gatherPackageForeignInterfaces")
              let (Artifacts ifaces _) = artifacts
              putStrLn ("GATHER-DEBUG: *** elm/core has " ++ show (Map.size ifaces) ++ " interfaces in artifacts")
              putStrLn ("GATHER-DEBUG: *** gatherForeignInterfaces returned " ++ show (Map.size foreignIfaces) ++ " foreign interfaces")
              putStrLn ("GATHER-DEBUG: *** foreign interface keys: " ++ show (Map.keys foreignIfaces))
        in foreignIfaces
      else foreignIfaces

-- | Package-aware version of crawlModule that looks up foreign dependencies by package.
--
-- This function determines which package a module belongs to and uses the correct
-- foreign dependencies for that package, fixing the architectural issue where
-- dependency-crawled kernel modules got wrong foreign dependency context.
crawlModuleWithPackageContext :: Map.Map Pkg.Name (Map.Map ModuleName.Raw ForeignInterface) -> TVar StatusDict -> Pkg.Name -> FilePath -> DocsStatus -> ModuleName.Raw -> IO (Maybe Status)
crawlModuleWithPackageContext pkgForeignDeps mvar currentPkg src docsStatus name = do
  -- Determine which package this module belongs to
  let targetPkg = if Name.isKernel name then Pkg.core else currentPkg  -- Kernel modules belong to elm/core

  -- CRITICAL FIX: Aggregate foreign interfaces from ALL dependency packages, not just the current package
  -- The current package needs interfaces from its dependencies, not from itself
  let foreignDeps = Map.unions (Map.elems pkgForeignDeps)

  -- Debug for elm/json
  when (currentPkg == Pkg.json) $ do
    putStrLn ("CRAWL-DEBUG: *** Module " ++ show name ++ " in package " ++ show currentPkg)
    putStrLn ("CRAWL-DEBUG: *** Available dependency packages: " ++ show (Map.keys pkgForeignDeps))
    putStrLn ("CRAWL-DEBUG: *** Total foreign interfaces after union: " ++ show (Map.size foreignDeps))
    putStrLn ("CRAWL-DEBUG: *** Foreign interface keys: " ++ show (Map.keys foreignDeps))

  -- Call the original crawlModule with correct package name and foreign deps for the target package
  crawlModule foreignDeps mvar targetPkg src docsStatus name

-- CRAWL

type StatusDict =
  Map.Map ModuleName.Raw (TVar (Maybe Status))

data Status
  = SLocal DocsStatus (Map.Map ModuleName.Raw ()) Src.Module (Map.Map ModuleName.Raw ForeignInterface)
  | SForeign I.Interface
  | SKernelLocal [Kernel.Chunk]
  | SKernelForeign
  | SNotFound String  -- New: Module failed to crawl with reason
  deriving (Show)

crawlModule :: Map.Map ModuleName.Raw ForeignInterface -> TVar StatusDict -> Pkg.Name -> FilePath -> DocsStatus -> ModuleName.Raw -> IO (Maybe Status)
crawlModule foreignDeps mvar pkg src docsStatus name =
  do

    let pathCanopy = src </> ModuleName.toFilePath name <.> "canopy"
    let pathElm = src </> ModuleName.toFilePath name <.> "elm"
    let pathCan = src </> ModuleName.toFilePath name <.> "can"
    canopyExists <- File.exists pathCanopy
    elmExists <- File.exists pathElm
    canExists <- File.exists pathCan
    let exists = canopyExists || elmExists || canExists
    let path = if canopyExists then pathCanopy
               else if canExists then pathCan
               else pathElm
    printLog ("crawlModule: " <> (show name <> (" canopy exists: " <> (show canopyExists <> (" elm exists: " <> (show elmExists <> (" can exists: " <> show canExists)))))))
    when (name == "Basics") $ do
      printLog ("BASICS_DEBUG: src path: " <> show src)
      printLog ("BASICS_DEBUG: pathCanopy: " <> show pathCanopy)
      printLog ("BASICS_DEBUG: pathElm: " <> show pathElm)
      printLog ("BASICS_DEBUG: pathCan: " <> show pathCan)
      printLog ("BASICS_DEBUG: canopyExists: " <> show canopyExists)
      printLog ("BASICS_DEBUG: elmExists: " <> show elmExists)
      printLog ("BASICS_DEBUG: canExists: " <> show canExists)
      printLog ("BASICS_DEBUG: exists: " <> show exists)
      printLog ("BASICS_DEBUG: selected path: " <> show path)
    when (name == "Char") $ do
      printLog ("CHAR_DEBUG: src path: " <> show src)
      printLog ("CHAR_DEBUG: pathCanopy: " <> show pathCanopy)
      printLog ("CHAR_DEBUG: pathElm: " <> show pathElm)
      printLog ("CHAR_DEBUG: pathCan: " <> show pathCan)
      printLog ("CHAR_DEBUG: canopyExists: " <> show canopyExists)
      printLog ("CHAR_DEBUG: elmExists: " <> show elmExists)
      printLog ("CHAR_DEBUG: canExists: " <> show canExists)
      printLog ("CHAR_DEBUG: exists: " <> show exists)
      printLog ("CHAR_DEBUG: selected path: " <> show path)
      printLog ("CHAR_DEBUG: foreignDeps lookup: " <> show (Map.lookup name foreignDeps))
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
    when (show name == "\"Basics\"") $ do
      putStrLn $ "BASICS_DEBUG: *** FOREIGN LOOKUP *** " ++ show (Map.lookup name foreignDeps)
      putStrLn $ "BASICS_DEBUG: *** EXISTS *** " ++ show exists
    case Map.lookup name foreignDeps of
      Just ForeignAmbiguous -> do
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: KERNEL " <> show name <> " returning Nothing (ForeignAmbiguous)")
        when (show name == "\"Basics\"") $ do
          putStrLn $ "BASICS_DEBUG: *** TAKING ForeignAmbiguous BRANCH ***"
        return Nothing
      Just (ForeignSpecific iface) -> do
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: KERNEL " <> show name <> " ForeignSpecific branch, exists=" <> show exists)
        when (show name == "\"Basics\"") $ do
          putStrLn $ "BASICS_DEBUG: *** TAKING ForeignSpecific BRANCH *** exists=" ++ show exists
        if exists
          then do
            -- FIXED: When both foreign interface and local source exist, compile the local version
            -- This is critical for elm/core modules which have both foreign interfaces from dependencies
            -- and local source files that should be compiled
            printLog ("module " <> (show name <> " has both foreign interface and local source - compiling local version"))
            crawlFile foreignDeps mvar pkg src docsStatus name path
          else return (Just (SForeign iface))
      Nothing -> do
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: KERNEL " <> show name <> " Nothing branch, exists=" <> show exists)
        when (show name == "\"Basics\"") $ do
          putStrLn $ "BASICS_DEBUG: *** TAKING Nothing BRANCH *** exists=" ++ show exists
        if exists
          then do
            when (show name == "\"Basics\"") $ do
              putStrLn $ "BASICS_DEBUG: *** CALLING crawlFile ***"
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
    putStrLn $ "CRAWLFILE_DEBUG: Parsing " ++ show expectedName ++ " from " ++ path
    case Parse.fromByteString (Parse.Package pkg) bytes of
      Left err ->
        do
          putStrLn $ "CRAWLFILE_DEBUG: Parse FAILED for " ++ show expectedName ++ ": " ++ show err
          return Nothing
      Right modul@(Src.Module (Just (A.At _ actualName)) _ _ imports _ _ _ _ _ _) | expectedName == actualName ->
        do
          putStrLn $ "CRAWLFILE_DEBUG: Parse SUCCESS for " ++ show expectedName
          putStrLn $ "CRAWLFILE_DEBUG: Actual module name: " ++ show actualName
          putStrLn $ "CRAWLFILE_DEBUG: Name comparison: expectedName == actualName = " ++ show (expectedName == actualName)
          putStrLn $ "CRAWLFILE_DEBUG: Module imports: " ++ show (fmap (Src._importName) imports)
          printLog ("crawlFile (imports) pkg: " <> (show pkg <> (" src: " <> (show src <> (" path : " <> (show path <> (" imports are " <> show (fmap (Src._importName) imports))))))))
          deps <- crawlImports foreignDeps mvar pkg src imports
          printLog ("crawlFile (deps) pkg: " <> (show pkg <> (" src: " <> (show src <> (" path : " <> (show path <> (" deps are " <> show deps)))))))
          let status = SLocal docsStatus deps modul foreignDeps
          putStrLn $ "CRAWLFILE_DEBUG: Created status for " ++ show expectedName ++ ": SLocal"
          -- CRITICAL FIX: Add the module itself to statusStore (not just its dependencies)
          -- This ensures exposed modules that are crawled directly get added to statusStore
          putStrLn $ "CRAWLFILE_DEBUG: Adding " ++ show expectedName ++ " to statusStore"
          statusTVar <- newTVarIO (Just status)
          atomically $ do
            statusDict <- readTVar mvar
            writeTVar mvar (Map.insert expectedName statusTVar statusDict)
          putStrLn $ "CRAWLFILE_DEBUG: Successfully added " ++ show expectedName ++ " to statusStore"
          return (Just status)
      Right (Src.Module (Just (A.At _ actualName)) _ _ _ _ _ _ _ _ _) ->
        do
          putStrLn $ "CRAWLFILE_DEBUG: Parse SUCCESS but name mismatch for " ++ show expectedName
          putStrLn $ "CRAWLFILE_DEBUG: Expected: " ++ show expectedName ++ ", Actual: " ++ show actualName
          putStrLn $ "CRAWLFILE_DEBUG: Name comparison check: " ++ show (expectedName == actualName)
          return Nothing
      Right (Src.Module Nothing _ _ _ _ _ _ _ _ _) ->
        do
          putStrLn $ "CRAWLFILE_DEBUG: Parse SUCCESS but no module name for " ++ show expectedName
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
    putStrLn $ "CRAWLRESULT_DEBUG: currentStatusDict contains modules: " ++ show (Map.keys currentStatusDict)
    _ <- Map.traverseWithKey (\name result -> do
      putStrLn $ "CRAWLRESULT_DEBUG: Storing result for " ++ show name ++ ": " ++ show (Maybe.isJust result)
      let placeholderTVar = placeholderTVars Map.! name
      atomically $ writeTVar placeholderTVar result
      -- Also update the main status store to ensure consistency
      case Map.lookup name currentStatusDict of
        Just mainTVar -> do
          atomically $ writeTVar mainTVar result
          putStrLn $ "CRAWLRESULT_DEBUG: Updated main TVar for " ++ show name
        Nothing -> do
          putStrLn $ "CRAWLRESULT_DEBUG: WARNING - No main TVar found for " ++ show name
      when (name == "Elm.JsArray") $ do
        printLog ("DEBUG: Stored Elm.JsArray result in both TVars: " <> show result)
      when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
        printLog ("DEBUG: Stored kernel module " <> show name <> " result: " <> show result)
      when (show name == "\"Basics\"") $ do
        putStrLn $ "CRAWLRESULT_DEBUG: *** BASICS MODULE *** result: " ++ show (Maybe.isJust result)
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
        -- For kernel modules, use empty foreign dependency context since they don't depend on other packages
        let kernelForeignDeps = if Name.isKernel name then Map.empty else Map.mapMaybe getDepHome foreignDeps
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
          printLog ("DEBUG: crawlKernel " <> show name <> " using kernelForeignDeps: " <> show kernelForeignDeps)
          printLog ("DEBUG: crawlKernel " <> show name <> " isKernel: " <> show (Name.isKernel name))
        case Kernel.fromByteString pkg kernelForeignDeps bytes of
            Nothing -> do
              when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray"]) $ do
                printLog ("DEBUG: crawlKernel " <> show name <> " Kernel.fromByteString returned Nothing")
              -- Fallback: treat failed kernels as foreign
              if Name.isKernel name
                then do
                  printLog ("DEBUG: crawlKernel " <> show name <> " treating as foreign kernel (fallback)")
                  return (Just SKernelForeign)
                else return Nothing
            Just (Kernel.Content imports chunks) -> do
              when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray", "Elm.Kernel.List"]) $ do
                printLog ("DEBUG: crawlKernel " <> show name <> " parsed successfully, crawling imports")
              _ <- crawlImports foreignDeps mvar pkg src imports
              when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray", "Elm.Kernel.List"]) $ do
                printLog ("DEBUG: crawlKernel " <> show name <> " returning SKernelLocal")
              return (Just (SKernelLocal chunks))
      else do
        when (ModuleName.toChars name `elem` ["Elm.Kernel.Basics", "Elm.Kernel.JsArray", "Elm.Kernel.List"]) $ do
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
  | RNotFound String  -- New: Module not found with reason


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
compile pkg mvar status = do
  case status of
    SLocal docsStatus deps modul foreignInterfaces -> do
      -- ELM-CSV DEBUG: Log individual module compilation for elm-csv
      when (Pkg.toChars pkg == "BrianHicks/elm-csv") $ do
        case modul of
          Src.Module (Just (A.At _ moduleName)) _ _ _ _ _ _ _ _ _ -> do
            putStrLn ("ELM-CSV-DEBUG: *** Compiling module: " <> ModuleName.toChars moduleName <> " ***")
          _ -> putStrLn "ELM-CSV-DEBUG: *** Compiling module with unknown name ***"
      do
        resultsDict <- readTVarIO mvar
        printLog ("all keys in resultsDict for pkg:  " <> (show pkg <> (" " <> show (Map.keys resultsDict))))
        printLog ("all keys in deps for pkg: " <> (show pkg <> (" " <> show (Map.keys deps))))
        let thingToRead = Map.intersection resultsDict deps
        printLog ("all keys in thingToRead for pkg: " <> (show pkg <> (" " <> show (Map.keys thingToRead))))
        let missingFromResultsDict = filter (\k -> not (Map.member k resultsDict)) (Map.keys deps)
        when (not (null missingFromResultsDict)) $
          printLog ("DEBUG: Missing from resultsDict: " <> show missingFromResultsDict)

        -- DEPENDENCY RESOLUTION: Use eager resolution for elm/core, lazy for others
        -- elm/core needs complete dependencies to compile properly
        interfaces <- if pkg == Pkg.core
          then do
            printLog ("EAGER-DEP: Using eager dependency resolution for elm/core")
            resolveEagerInterfaces resultsDict deps foreignInterfaces
          else do
            printLog ("LAZY-DEP: Using lazy dependency resolution for non-core package")
            resolveLazyInterfaces resultsDict deps foreignInterfaces

        printLog ("DEBUG: resolved interfaces keys for pkg " <> show pkg <> ": " <> show (Map.keys interfaces))

        -- DETAILED LOGGING FOR COMPILE.COMPILE ARGUMENTS
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
        ioCompileResult <- Compile.compile pkg interfaces modul
        printLog ("DEBUG: Compile.compile IO action completed for pkg: " <> show pkg)
        case ioCompileResult of
          Left compileError -> do
            printLog ("=== COMPILE ERROR DEBUG INFO START ===")
            printLog ("Package: " <> show pkg)
            case modul of
              Src.Module (Just (A.At _ moduleName)) _ _ _ _ _ _ _ _ _ -> do
                printLog ("Module Name: " <> ModuleName.toChars moduleName)
                when (ModuleName.toChars moduleName `elem` ["Set", "Array", "Debug", "Char", "String"]) $ do
                  putStrLn $ "MISSING_MODULE_DEBUG: *** " ++ ModuleName.toChars moduleName ++ " FAILED TO COMPILE ***"
                  putStrLn $ "MISSING_MODULE_DEBUG: Error: " ++ show compileError
                -- ELM-CSV DEBUG: Enhanced error logging for elm-csv
                when (Pkg.toChars pkg == "BrianHicks/elm-csv") $ do
                  putStrLn ("ELM-CSV-DEBUG: *** MODULE COMPILATION FAILED ***")
                  putStrLn ("ELM-CSV-DEBUG: Module: " <> ModuleName.toChars moduleName)
                  putStrLn ("ELM-CSV-DEBUG: Error details: " <> show compileError)
                  putStrLn ("ELM-CSV-DEBUG: Available interfaces: " <> show (Map.keys interfaces))
              _ -> printLog ("Module: " <> show modul)
            printLog ("CompileError: " <> show compileError)
            printLog ("=== COMPILE ERROR DEBUG INFO END ===")
            return Nothing
          Right (Compile.Artifacts canonical annotations objects _ffiInfo) -> do
            printLog ("DEBUG: Processing successful compilation result for pkg: " <> show pkg)
            let ifaces = I.fromModule pkg canonical annotations
            let moduleName = Can._name canonical
            let moduleNameRaw = ModuleName._module moduleName
            when (ModuleName.toChars moduleNameRaw == "List") $ do
              putStrLn $ "LIST_DEBUG: *** LIST MODULE COMPILED SUCCESSFULLY ***"
              putStrLn $ "LIST_DEBUG: Interface created for List module: " ++ ModuleName.toChars moduleNameRaw
            when (ModuleName.toChars moduleNameRaw == "Tuple") $ do
              putStrLn $ "TUPLE_DEBUG: *** TUPLE MODULE COMPILED SUCCESSFULLY ***"
              putStrLn $ "TUPLE_DEBUG: Interface created for Tuple module: " ++ ModuleName.toChars moduleNameRaw
            when (ModuleName.toChars moduleNameRaw == "String") $ do
              putStrLn $ "STRING_DEBUG: *** STRING MODULE COMPILED SUCCESSFULLY ***"
              putStrLn $ "STRING_DEBUG: Interface created for String module: " ++ ModuleName.toChars moduleNameRaw
            when (ModuleName.toChars moduleNameRaw `elem` ["Set", "Array", "Debug", "Char", "Process"]) $ do
              putStrLn $ "MISSING_MODULE_DEBUG: *** " ++ ModuleName.toChars moduleNameRaw ++ " COMPILED SUCCESSFULLY ***"
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
    SNotFound reason -> do
      printLog ("DEBUG: Module not found during compilation: " <> reason)
      return (Just (RNotFound reason))

getInterface :: Result -> Maybe I.Interface
getInterface result =
  case result of
    RLocal iface _ _ -> Just iface
    RForeign iface -> Just iface
    RKernelLocal _ -> Just emptyKernelInterface
    RKernelForeign -> Just emptyKernelInterface
    RNotFound _ -> Nothing  -- No interface available for not found modules
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
                       -> Map.Map ModuleName.Raw ForeignInterface
                       -> IO (Map.Map ModuleName.Raw I.Interface)
resolveLazyInterfaces resultsDict deps foreignInterfaces = do
  -- For each dependency, check if it's an intra-package dependency (in resultsDict)
  -- If so, wait for it to be ready (blocking). Otherwise, try non-blocking read.
  let availableDeps = Map.intersection resultsDict deps
  availableResults <- Map.traverseWithKey (\modName tvar -> do
    -- If the dependency is in resultsDict, it's an intra-package dependency
    -- and we should wait for it to complete
    if Map.member modName resultsDict
      then do
        printLog ("LAZY-DEP: " <> show modName <> " is intra-package, waiting for it to be ready...")
        maybeResult <- waitForMaybeResultWithName tvar ("Intra-package module " <> show modName)
        printLog ("LAZY-DEP: " <> show modName <> " ready, using interface")
        pure (Just maybeResult)
      else do
        -- Foreign dependency, use non-blocking read
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
  let localInterfaces = Map.mapMaybe (>>= getInterface) availableResults

  -- Add foreign interfaces for dependencies not available locally
  let missingDeps = Map.difference deps (Map.mapMaybe id availableResults)
  let foreignIfacesForMissing = Map.intersection foreignInterfaces missingDeps
  let combinedForeignInterfaces = Map.mapMaybe (\case
        ForeignSpecific iface -> Just iface
        ForeignAmbiguous -> Nothing) foreignIfacesForMissing

  -- Combine local and foreign interfaces
  let allInterfaces = Map.union localInterfaces combinedForeignInterfaces

  printLog ("LAZY-DEP: Resolved " <> show (Map.size localInterfaces) <> " local + " <> show (Map.size combinedForeignInterfaces) <> " foreign = " <> show (Map.size allInterfaces) <> " out of " <> show (Map.size deps) <> " dependencies")
  printLog ("LAZY-DEP: Foreign interfaces used: " <> show (Map.keys combinedForeignInterfaces))
  pure allInterfaces

-- | Resolve dependency interfaces with blocking (eager resolution)
-- This ensures all required dependencies are available for foundational packages like elm/core
resolveEagerInterfaces :: Map.Map ModuleName.Raw (TVar (Maybe Result))
                        -> Map.Map ModuleName.Raw ()
                        -> Map.Map ModuleName.Raw ForeignInterface
                        -> IO (Map.Map ModuleName.Raw I.Interface)
resolveEagerInterfaces resultsDict deps foreignInterfaces = do
  -- For each dependency, wait for the interface to be ready (blocking)
  let availableDeps = Map.intersection resultsDict deps
  availableResults <- Map.traverseWithKey (\modName tvar -> do
    printLog ("EAGER-DEP: Waiting for " <> show modName <> " to be ready...")
    maybeResult <- waitForMaybeResultWithName tvar ("Module " <> show modName)
    printLog ("EAGER-DEP: " <> show modName <> " ready, using interface")
    pure (Just maybeResult)
    ) availableDeps

  -- Extract interfaces from all results (should all be available now)
  let localInterfaces = Map.mapMaybe (>>= getInterface) availableResults

  -- Add foreign interfaces for dependencies not available locally
  let missingDeps = Map.difference deps (Map.mapMaybe id availableResults)
  let foreignIfacesForMissing = Map.intersection foreignInterfaces missingDeps
  let combinedForeignInterfaces = Map.mapMaybe (\case
        ForeignSpecific iface -> Just iface
        ForeignAmbiguous -> Nothing) foreignIfacesForMissing

  -- Combine local and foreign interfaces
  let allInterfaces = Map.union localInterfaces combinedForeignInterfaces

  printLog ("EAGER-DEP: Resolved " <> show (Map.size localInterfaces) <> " local + " <> show (Map.size combinedForeignInterfaces) <> " foreign = " <> show (Map.size allInterfaces) <> " out of " <> show (Map.size deps) <> " dependencies")
  printLog ("EAGER-DEP: Foreign interfaces used: " <> show (Map.keys combinedForeignInterfaces))
  pure allInterfaces


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
    RNotFound _ -> Nothing  -- No docs for not found modules

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

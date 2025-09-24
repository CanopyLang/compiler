{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

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
import Control.Concurrent (forkIO)
import Control.Lens (makeLenses)
import Control.Concurrent.MVar (MVar, newEmptyMVar, newMVar, putMVar, readMVar, takeMVar)
import Control.Exception (BlockedIndefinitelyOnMVar, Handler (..), SomeException, catches, throwIO)
import Control.Monad (liftM2, liftM3, void)
import Data.Binary (Binary, get, getWord8, put, putWord8)
import qualified Data.Either as Either
import Data.Foldable (traverse_)
import qualified Data.Map as Map
import qualified Data.Map.Merge.Strict as Map
import qualified Data.Map.Utils as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Data.OneOrMore as OneOrMore
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

-- LOAD ARTIFACTS

loadObjects :: FilePath -> Details -> IO (MVar (Maybe Opt.GlobalGraph))
loadObjects root (Details _ _ _ _ _ extras) =
  case extras of
    ArtifactsFresh _ o -> newMVar (Just o)
    ArtifactsCached -> fork (File.readBinary (Stuff.objects root))

loadInterfaces :: FilePath -> Details -> IO (MVar (Maybe Interfaces))
loadInterfaces root (Details _ _ _ _ _ extras) =
  case extras of
    ArtifactsFresh i _ -> newMVar (Just i)
    ArtifactsCached -> fork (File.readBinary (Stuff.interfaces root))

-- VERIFY INSTALL -- used by Install

verifyInstall :: BW.Scope -> FilePath -> Solver.Env -> Outline.Outline -> IO (Either Exit.Details ())
verifyInstall scope root (Solver.Env cache manager connection registry packageOverridesCache) outline =
  do
    time <- File.getTime (root </> "canopy.json")
    let key = Reporting.ignorer
    let env = Env key scope root cache manager connection registry packageOverridesCache
    case outline of
      Outline.Pkg pkg -> Task.run (void (verifyPkg env time pkg))
      Outline.App app -> Task.run (void (verifyApp env time app))

-- LOAD -- used by Make, Repl, Reactor

load :: Reporting.Style -> BW.Scope -> FilePath -> IO (Either Exit.Details Details)
load style scope root =
  do
    newTime <- File.getTime (root </> "canopy.json")
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
    newTime <- File.getTime (root </> "canopy.json")
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
    mvar <- fork Solver.initEnv
    eitherOutline <- Outline.read root
    case eitherOutline of
      Left problem ->
        return . Left $ Exit.DetailsBadOutline problem
      Right outline ->
        do
          maybeEnv <- readMVar mvar
          case maybeEnv of
            Left problem ->
              return . Left $ Exit.DetailsCannotGetRegistry problem
            Right (Solver.Env cache manager connection registry packageOverridesCache) ->
              return $ Right (Env key scope root cache manager connection registry packageOverridesCache, outline)

-- FIXME
initEnvForReactorTH :: Reporting.DKey -> BW.Scope -> FilePath -> IO (Either Exit.Details (Env, Outline.Outline))
initEnvForReactorTH key scope root =
  do
    mvar <- fork Solver.initEnv
    eitherOutline <- Outline.read root
    case eitherOutline of
      Left problem ->
        return . Left $ Exit.DetailsBadOutline problem
      Right outline ->
        do
          maybeEnv <- readMVar mvar
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
    result <- Task.io $ Solver.verify cache connection registry constraints
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

fork :: IO a -> IO (MVar a)
fork work =
  do
    mvar <- newEmptyMVar
    _ <- forkIO (work >>= putMVar mvar)
    return mvar

hasLocked :: String -> IO a -> IO a
hasLocked msg action =
  action
    `catches` [ Handler handler
              ]
  where
    handler :: BlockedIndefinitelyOnMVar -> IO a
    handler exception = printLog ("MVAR: " <> msg) >> throwIO exception

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
          printLog "Made it to VERIFYDEPENDENCIES 0"
          mvar <- newEmptyMVar
          printLog "Made it to VERIFYDEPENDENCIES 1"
          printLog ("SOLUTION: " <> show solution)
          mvars <-
            Stuff.withRegistryLock cache $
              Map.traverseWithKey (\k details -> fork (verifyDep key (generateBuildData k (extractVersionFromDetails details)) manager zokkaRegistries mvar solution (extractConstraintsFromDetails details))) solution
          printLog ("Made it to VERIFYDEPENDENCIES 2: " <> show (Map.keys mvars))
          putMVar mvar mvars
          printLog "Made it to VERIFYDEPENDENCIES 3"
          deps <- Map.traverseWithKey (\n m -> hasLocked (show n) (do r <- readMVar m; printLog ("deps result for " <> show n); pure r)) mvars
          printLog "Made it to VERIFYDEPENDENCIES 4"
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

verifyDep :: Reporting.DKey -> BuildData -> Http.Manager -> ZokkaRegistries -> MVar (Map.Map Pkg.Name (MVar Dep)) -> Map.Map Pkg.Name Solver.Details -> Map.Map Pkg.Name C.Constraint -> IO Dep
verifyDep key buildData manager zokkaRegistry depsMVar solution directDeps =
  let fingerprint = Map.intersectionWith (\(Solver.Details v _) _ -> v) solution directDeps
      cacheFilePath = cacheFilePathFromBuildData buildData
      -- These are the pkg names and versions that we actually perform downloading and error reporting on
      (primaryPkg, primaryPkgVersion) =
        case buildData of
          BuildOriginalPackage (OriginalPackageBuildData {_pkg = pkg, _version = vsn}) ->
            (pkg, vsn)
          BuildWithOverridingPackage
            (OverridingPackageBuildData {_overridingPkg = overridingPkg, _overridingPkgVersion = overridingPkgVer}) ->
              (overridingPkg, overridingPkgVer)
      downloadPackageAction = downloadPackageToFilePath cacheFilePath zokkaRegistry manager primaryPkg primaryPkgVersion
   in do
        exists <- Dir.doesDirectoryExist cacheFilePath
        printLog (show exists <> ("A0" <> cacheFilePath))
        srcExists <- Dir.doesDirectoryExist (cacheFilePath </> "src")
        if srcExists
          then do
            Reporting.report key Reporting.DCached
            maybeCache <- File.readBinary (cacheFilePath </> "artifacts.dat")
            case maybeCache of
              Nothing ->
                build key buildData depsMVar fingerprint Set.empty
              Just (ArtifactCache fingerprints artifacts) ->
                if Set.member fingerprint fingerprints
                  then Reporting.report key Reporting.DBuilt >> return (Right artifacts)
                  else build key buildData depsMVar fingerprint fingerprints
          else do
            Reporting.report key Reporting.DRequested
            -- Normally we don't need to create the directory because it's created during the
            -- constraint solving process (to put an canopy.json there), but in Zokka's case we
            -- might be looking at a dependency that showed up after the constraint solving
            -- process was completed via an override, so the directory might not actually exist,
            -- so we better create it here just in case.
            --
            -- Note that the ...IfMissing part is used because this directory might actually
            -- exist (if it wasn't used as an override), just without a src directory.
            --
            -- Also the reason we don't shift overrides to happen during constraint solving is
            -- that we want to eventually in the future download both the original package
            -- and the package that is being used to override the original, both to help with
            -- Canopy IDE integrations (which may be unaware of Zokka and so we still want to
            -- support click-to-definition, which is usually based on the cache, even if the
            -- integration is unaware of Zokka overrides) and to help with error messages, where
            -- we can rigorously check that the APIs of the original package and the override
            -- match. So we want to make sure that we keep the information about what original
            -- package was used around and we want that to drive the constraint process in
            -- the bad case that the override package is malformed and doesn't follow the
            -- same dependencies as the original package.
            Dir.createDirectoryIfMissing True cacheFilePath
            result <- downloadPackageAction
            case result of
              Left problem ->
                do
                  Reporting.report key (Reporting.DFailed primaryPkg primaryPkgVersion)
                  (return . Left) . Just $ Exit.BD_BadDownload primaryPkg primaryPkgVersion problem
              Right () ->
                do
                  Reporting.report key (Reporting.DReceived primaryPkg primaryPkgVersion)
                  build key buildData depsMVar fingerprint Set.empty

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

build :: Reporting.DKey -> BuildData -> MVar (Map.Map Pkg.Name (MVar Dep)) -> Fingerprint -> Set.Set Fingerprint -> IO Dep
build key buildData depsMVar f fs =
  let cacheFilePath = cacheFilePathFromBuildData buildData
      (pkg, vsn) = case buildData of
        BuildOriginalPackage (OriginalPackageBuildData {_pkg = origPkg, _version = origVsn}) ->
          (origPkg, origVsn)
        BuildWithOverridingPackage
          (OverridingPackageBuildData {_originalPkg = origPkg, _originalPkgVersion = origPkgVer}) ->
            (origPkg, origPkgVer)
   in do
        eitherOutline <- Outline.read cacheFilePath
        printLog ("COMPILING: " <> (show pkg <> (show vsn <> (" OUTLINE: " <> show eitherOutline))))
        case eitherOutline of
          Left _ ->
            do
              Reporting.report key Reporting.DBroken
              (return . Left) . Just $ Exit.BD_BadBuild pkg vsn f
          Right (Outline.App _) ->
            do
              Reporting.report key Reporting.DBroken
              (return . Left) . Just $ Exit.BD_BadBuild pkg vsn f
          Right (Outline.Pkg (Outline.PkgOutline _ _ _ _ exposed deps _ _)) ->
            do
              allDeps <- readMVar depsMVar
              directDeps <- traverse readMVar (Map.intersection allDeps deps)
              case sequenceA directDeps of
                Left x ->
                  do
                    Reporting.report key Reporting.DBroken
                    printLog ("bad dep! while building: " <> (show pkg <> ("|" <> show x)))
                    return . Left $ Nothing
                Right directArtifacts ->
                  do
                    let src = cacheFilePath </> "src"
                    let foreignDeps = gatherForeignInterfaces directArtifacts
                    let exposedDict = Map.fromKeys (const ()) (Outline.flattenExposed exposed)
                    docsStatus <- getDocsStatusFromFilePath cacheFilePath
                    mvar <- newEmptyMVar
                    mvars <- Map.traverseWithKey (const . fork . crawlModule foreignDeps mvar pkg src docsStatus) exposedDict
                    putMVar mvar mvars
                    traverse_ readMVar mvars
                    maybeStatuses <- readMVar mvar >>= traverse readMVar
                    case sequenceA maybeStatuses of
                      Nothing ->
                        do
                          Reporting.report key Reporting.DBroken
                          printLog ("maybeStatuses were Nothing for " <> (show pkg <> (" vsn " <> (show vsn <> (" and deps " <> show deps)))))
                          (return . Left) . Just $ Exit.BD_BadBuild pkg vsn f
                      Just statuses ->
                        do
                          rmvar <- newEmptyMVar
                          let extractDepsFromStatus status = case status of (SLocal _ statusDeps _) -> statusDeps; _ -> Map.empty
                          let compileAction status = genericErrorHandler ("This package failed: " <> show pkg) (compile pkg rmvar status)
                          rmvars <- traverse (fork . compileAction) statuses
                          putMVar rmvar rmvars
                          maybeResults <- traverse readMVar rmvars
                          case sequenceA maybeResults of
                            Nothing ->
                              do
                                printLog ("maybeResults were Nothing for " <> (show pkg <> (" vsn " <> (show vsn <> (" and deps from status were " <> show (fmap extractDepsFromStatus statuses))))))
                                Reporting.report key Reporting.DBroken
                                (return . Left) . Just $ Exit.BD_BadBuild pkg vsn f
                            Just results ->
                              let path = cacheFilePath </> "artifacts.dat"
                                  ifaces = gatherInterfaces exposedDict results
                                  objects = gatherObjects results
                                  artifacts = Artifacts ifaces objects
                                  fingerprints = Set.insert f fs
                               in do
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

-- CRAWL

type StatusDict =
  Map.Map ModuleName.Raw (MVar (Maybe Status))

data Status
  = SLocal DocsStatus (Map.Map ModuleName.Raw ()) Src.Module
  | SForeign I.Interface
  | SKernelLocal [Kernel.Chunk]
  | SKernelForeign
  deriving (Show)

crawlModule :: Map.Map ModuleName.Raw ForeignInterface -> MVar StatusDict -> Pkg.Name -> FilePath -> DocsStatus -> ModuleName.Raw -> IO (Maybe Status)
crawlModule foreignDeps mvar pkg src docsStatus name =
  do
    let pathCanopy = src </> ModuleName.toFilePath name <.> "canopy"
    let pathElm = src </> ModuleName.toFilePath name <.> "elm"
    canopyExists <- File.exists pathCanopy
    elmExists <- File.exists pathElm
    let exists = canopyExists || elmExists
    let path = if canopyExists then pathCanopy else pathElm
    printLog ("crawlModule: " <> (show name <> (" canopy exists: " <> (show canopyExists <> (" elm exists: " <> show elmExists)))))
    case Map.lookup name foreignDeps of
      Just ForeignAmbiguous ->
        return Nothing
      Just (ForeignSpecific iface) ->
        if exists
          then return Nothing
          else return (Just (SForeign iface))
      Nothing ->
        if exists
          then do
            printLog ("module " <> (show name <> " is in exists branch"))
            crawlFile foreignDeps mvar pkg src docsStatus name path
          else
            if Pkg.isKernel pkg && Name.isKernel name
              then do
                printLog ("module " <> (show name <> " is in kernel branch"))
                crawlKernel foreignDeps mvar pkg src name
              else do
                printLog ("module " <> (show name <> (" returning Nothing: Pkg.isKernel=" <> (show (Pkg.isKernel pkg) <> (" Name.isKernel=" <> show (Name.isKernel name))))))
                return Nothing

crawlFile :: Map.Map ModuleName.Raw ForeignInterface -> MVar StatusDict -> Pkg.Name -> FilePath -> DocsStatus -> ModuleName.Raw -> FilePath -> IO (Maybe Status)
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

crawlImports :: Map.Map ModuleName.Raw ForeignInterface -> MVar StatusDict -> Pkg.Name -> FilePath -> [Src.Import] -> IO (Map.Map ModuleName.Raw ())
crawlImports foreignDeps mvar pkg src imports =
  do
    statusDict <- takeMVar mvar
    let deps = Map.fromList (fmap (\i -> (Src.getImportName i, ())) imports)
    printLog ("crawlImports pkg: " <> (show pkg <> (" src: " <> (show src <> (" deps are " <> show deps)))))
    let news = Map.difference deps statusDict

    -- CRITICAL FIX: Create placeholder MVars and put back the MVar BEFORE forking
    -- This prevents deadlock where forked threads wait for the MVar that's held by this thread
    placeholderMVars <- Map.traverseWithKey (\_ () -> newEmptyMVar) news
    putMVar mvar (Map.union placeholderMVars statusDict)

    -- Now fork the threads and populate the placeholder MVars
    mvars <- Map.traverseWithKey (\name () -> do
      result <- fork (crawlModule foreignDeps mvar pkg src DocsNotNeeded name)
      return result) news

    traverse_ readMVar mvars
    return deps

crawlKernel :: Map.Map ModuleName.Raw ForeignInterface -> MVar StatusDict -> Pkg.Name -> FilePath -> ModuleName.Raw -> IO (Maybe Status)
crawlKernel foreignDeps mvar pkg src name =
  do
    let path = src </> ModuleName.toFilePath name <.> "js"
    exists <- File.exists path
    if exists
      then do
        bytes <- File.readUtf8 path
        case Kernel.fromByteString pkg (Map.mapMaybe getDepHome foreignDeps) bytes of
          Nothing ->
            return Nothing
          Just (Kernel.Content imports chunks) ->
            do
              _ <- crawlImports foreignDeps mvar pkg src imports
              return (Just (SKernelLocal chunks))
      else return (Just SKernelForeign)

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

compile :: Pkg.Name -> MVar (Map.Map ModuleName.Raw (MVar (Maybe Result))) -> Status -> IO (Maybe Result)
compile pkg mvar status =
  case status of
    SLocal docsStatus deps modul ->
      do
        resultsDict <- readMVar mvar
        printLog ("all keys in resultsDict for pkg:  " <> (show pkg <> (" " <> show (Map.keys resultsDict))))
        printLog ("all keys in deps for pkg: " <> (show pkg <> (" " <> show (Map.keys deps))))
        let thingToRead = Map.intersection resultsDict deps
        printLog ("all keys in thingToRead for pkg: " <> (show pkg <> (" " <> show (Map.keys thingToRead))))
        maybeResults <- Map.traverseWithKey (\k v -> hasLocked ("compiling this pkg: " <> (show pkg <> ("reading this module: " <> show k))) (readMVar v)) (Map.intersection resultsDict deps)
        case sequenceA maybeResults of
          Nothing -> do
            printLog ("nothing branch of sequence maybeResults for pkg: " <> show pkg)
            return Nothing
          Just results -> do
            compileResult <- Compile.compile pkg (Map.mapMaybe getInterface results) modul
            case compileResult of
              Left compileError ->
                do
                  printLog ("=== COMPILE ERROR DEBUG INFO START ===")
                  printLog ("Package: " <> show pkg)
                  printLog ("Module: " <> show modul)
                  printLog ("CompileError: " <> show compileError)
                  printLog ("=== COMPILE ERROR DEBUG INFO END ===")
                  return Nothing
              Right (Compile.Artifacts canonical annotations objects _ffiInfo) -> do
                let ifaces = I.fromModule pkg canonical annotations
                docs <- makeDocs docsStatus canonical
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
    RKernelLocal _ -> Nothing
    RKernelForeign -> Nothing

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

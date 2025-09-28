{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}

module Deps.Solver
  ( Solver,
    Result (..),
    Connection (..),
    --
    Details (..),
    verify,
    --
    AppSolution (..),
    addToApp,
    --
    Env (..),
    initEnv,
    initEnvForReactorTH,
  )
where

import Canopy.Constraint (Constraint)
import qualified Canopy.Constraint as C
import Canopy.CustomRepositoryData (CustomSingleRepositoryData (..), DefaultPackageServerRepo (_defaultPackageServerRepoTypeUrl), PZRPackageServerRepo (_pzrPackageServerRepoAuthToken, _pzrPackageServerRepoTypeUrl), SinglePackageLocationData (..))
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import Canopy.Version (Version)
import qualified Canopy.Version as V
import Control.Concurrent.STM (newTVarIO, readTVarIO)
import Control.Monad (foldM)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Utf8 as Utf8
import Deps.CustomRepositoryDataIO (loadCustomRepositoriesData, loadCustomRepositoriesDataForReactorTH)
import Deps.Registry (ZokkaRegistries (..))
import qualified Deps.Registry as Registry
import qualified Deps.Website as Website
import File (getTime)
import qualified File
import qualified Http
import qualified Json.Decode as D
import Logging.Logger (printLog)
import Reporting.Exit (RegistryProblem (..))
import qualified Reporting.Exit as Exit
import Stuff (ZokkaCustomRepositoryConfigFilePath (unZokkaCustomRepositoryConfigFilePath))
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.FilePath as FP

-- SOLVER

newtype Solver a
  = Solver
      ( forall b.
        State ->
        (State -> a -> (State -> IO b) -> IO b) ->
        (State -> IO b) ->
        (Exit.Solver -> IO b) ->
        IO b
      )

data State = State
  { _cache :: Stuff.PackageCache,
    _connection :: Connection,
    _registry :: Registry.ZokkaRegistries,
    _constraints :: Map (Pkg.Name, Version) Constraints
  }

data Constraints = Constraints
  { _canopy :: Constraint,
    _deps :: Map Pkg.Name Constraint
  }

data Connection
  = Online Http.Manager
  | Offline RegistryProblem -- The thing that made us think that we were offline

-- RESULT

data Result a
  = Ok a
  | NoSolution
  | NoOfflineSolution RegistryProblem
  | Err Exit.Solver

-- VERIFY -- used by Canopy.Details

data Details
  = Details Version (Map Pkg.Name Constraint) -- First argument is the version, second is the set of dependencies that the package depends on
  deriving (Show)

verify :: Stuff.PackageCache -> Connection -> Registry.ZokkaRegistries -> Map Pkg.Name Constraint -> IO (Result (Map Pkg.Name Details))
verify cache connection registry constraints =
  Stuff.withRegistryLock cache $
    case try constraints of
      Solver solver ->
        solver
          (State cache connection registry Map.empty)
          (\s a _ -> return $ Ok (Map.mapWithKey (addDeps s) a))
          (\_ -> return $ noSolution connection)
          (return . Err)

addDeps :: State -> Pkg.Name -> Version -> Details
addDeps (State _ _ _ constraints) name vsn =
  case Map.lookup (name, vsn) constraints of
    Just (Constraints _ deps) -> Details vsn deps
    Nothing -> error "compiler bug manifesting in Deps.Solver.addDeps"

noSolution :: Connection -> Result a
noSolution connection =
  case connection of
    Online _ -> NoSolution
    Offline registryError -> NoOfflineSolution registryError

-- ADD TO APP - used in Install

data AppSolution = AppSolution
  { _old :: Map Pkg.Name Version,
    _new :: Map Pkg.Name Version,
    _app :: Outline.AppOutline
  }

addToApp :: Stuff.PackageCache -> Connection -> Registry.ZokkaRegistries -> Pkg.Name -> Outline.AppOutline -> IO (Result AppSolution)
addToApp cache connection registry pkg outline@(Outline.AppOutline _ _ direct indirect testDirect testIndirect _) =
  Stuff.withRegistryLock cache $
    let allIndirects = Map.union indirect testIndirect
        allDirects = Map.union direct testDirect
        allDeps = Map.union allDirects allIndirects

        attempt toConstraint deps =
          try (Map.insert pkg C.anything (Map.map toConstraint deps))
     in case oneOf
          (attempt C.exactly allDeps)
          [ attempt C.exactly allDirects,
            attempt C.untilNextMinor allDirects,
            attempt C.untilNextMajor allDirects,
            attempt (const C.anything) allDirects
          ] of
          Solver solver ->
            solver
              (State cache connection registry Map.empty)
              (\s a _ -> return $ Ok (toApp s pkg outline allDeps a))
              (\_ -> return $ noSolution connection)
              (return . Err)

toApp :: State -> Pkg.Name -> Outline.AppOutline -> Map Pkg.Name Version -> Map Pkg.Name Version -> AppSolution
toApp (State _ _ _ constraints) pkg (Outline.AppOutline canopy srcDirs direct _ testDirect _ pkgOverrides) old new =
  let d = Map.intersection new (Map.insert pkg V.one direct)
      i = Map.difference (getTransitive constraints new (Map.toList d) Map.empty) d
      td = Map.intersection new (Map.delete pkg testDirect)
      ti = Map.difference new (Map.unions [d, i, td])
   in AppSolution old new (Outline.AppOutline canopy srcDirs d i td ti pkgOverrides)

getTransitive :: Map (Pkg.Name, Version) Constraints -> Map Pkg.Name Version -> [(Pkg.Name, Version)] -> Map Pkg.Name Version -> Map Pkg.Name Version
getTransitive constraints solution unvisited visited =
  case unvisited of
    [] ->
      visited
    info@(pkg, vsn) : infos ->
      if Map.member pkg visited
        then getTransitive constraints solution infos visited
        else
          case Map.lookup info constraints of
            Nothing ->
              -- FIXED: Handle missing constraint to prevent Map.! error
              getTransitive constraints solution infos visited  -- Skip this dependency
            Just constraint ->
              let newDeps = _deps constraint
                  newUnvisited = Map.toList (Map.intersection solution (Map.difference newDeps visited))
                  newVisited = Map.insert pkg vsn visited
              in getTransitive constraints solution infos $
                   getTransitive constraints solution newUnvisited newVisited

-- TRY

try :: Map Pkg.Name Constraint -> Solver (Map Pkg.Name Version)
try constraints =
  exploreGoals (Goals constraints Map.empty)

-- EXPLORE GOALS

data Goals = Goals
  { _pending :: Map Pkg.Name Constraint,
    _solved :: Map Pkg.Name Version
  }

exploreGoals :: Goals -> Solver (Map Pkg.Name Version)
exploreGoals (Goals pending solved) =
  case Map.minViewWithKey pending of
    Nothing ->
      return solved
    Just ((name, constraint), otherPending) ->
      do
        let goals1 = Goals otherPending solved
        let addVsn = addVersion goals1 name
        (v, vs) <- getRelevantVersions name constraint
        goals2 <- oneOf (addVsn v) (fmap addVsn vs)
        exploreGoals goals2

addVersion :: Goals -> Pkg.Name -> Version -> Solver Goals
addVersion (Goals pending solved) name version =
  do
    (Constraints canopy deps) <- getConstraints name version
    if C.goodCanopy canopy
      then do
        newPending <- foldM (addConstraint solved) pending (Map.toList deps)
        return (Goals newPending (Map.insert name version solved))
      else backtrack

addConstraint :: Map Pkg.Name Version -> Map Pkg.Name Constraint -> (Pkg.Name, Constraint) -> Solver (Map Pkg.Name Constraint)
addConstraint solved unsolved (name, newConstraint) =
  case Map.lookup name solved of
    Just version ->
      if C.satisfies newConstraint version
        then return unsolved
        else backtrack
    Nothing ->
      case Map.lookup name unsolved of
        Nothing ->
          return $ Map.insert name newConstraint unsolved
        Just oldConstraint ->
          case C.intersect oldConstraint newConstraint of
            Nothing ->
              backtrack
            Just mergedConstraint ->
              if oldConstraint == mergedConstraint
                then return unsolved
                else return (Map.insert name mergedConstraint unsolved)

-- GET RELEVANT VERSIONS

getRelevantVersions :: Pkg.Name -> Constraint -> Solver (Version, [Version])
getRelevantVersions name constraint =
  Solver $ \state@(State _ _ registry _) ok back _ ->
    case Registry.getVersions name registry of
      Just (Registry.KnownVersions newest previous) ->
        case filter (C.satisfies constraint) (newest : previous) of
          [] -> back state
          v : vs -> ok state (v, vs) back
      Nothing ->
        back state

-- GET CONSTRAINTS

getFromCustomSingleRepositoryData ::
  CustomSingleRepositoryData ->
  Pkg.Name ->
  Version ->
  Stuff.PackageCache ->
  (Constraints -> State) ->
  Http.Manager ->
  (State -> Constraints -> (State -> IO b) -> IO b) ->
  (State -> IO b) ->
  (Exit.Solver -> IO b) ->
  IO b
getFromCustomSingleRepositoryData customSingleRepositoryData pkg vsn cache toNewState manager ok back err =
  -- FIXME: Reduce duplication
  case customSingleRepositoryData of
    DefaultPackageServerRepoData defaultPackageServerRepo ->
      let repositoryUrl = _defaultPackageServerRepoTypeUrl defaultPackageServerRepo
          home = Stuff.package cache pkg vsn
       in do
            result <- fetchPackageMetadataWithFallback manager [] (Utf8.toChars repositoryUrl) pkg vsn
            case result of
              Left httpProblem ->
                err (Exit.SolverBadHttp pkg vsn httpProblem)
              Right (body, filename) ->
                let path = home </> filename
                    decoder = if filename == "elm.json" then elmConstraintsDecoder else constraintsDecoder
                    url = Website.metadata repositoryUrl pkg vsn filename
                 in case D.fromByteString decoder body of
                      Right cs ->
                        do
                          Dir.createDirectoryIfMissing True home
                          File.writeUtf8Atomic path body
                          ok (toNewState cs) cs back
                      Left _ ->
                        err (Exit.SolverBadHttpData pkg vsn url)
    PZRPackageServerRepoData pzrPackageServerRepo ->
      let repositoryUrl = _pzrPackageServerRepoTypeUrl pzrPackageServerRepo
          repositoryAuthToken = _pzrPackageServerRepoAuthToken pzrPackageServerRepo
          home = Stuff.package cache pkg vsn
       in do
            result <- fetchPackageMetadataWithFallback manager [Registry.createAuthHeader repositoryAuthToken] (Utf8.toChars repositoryUrl) pkg vsn
            case result of
              Left httpProblem ->
                err (Exit.SolverBadHttp pkg vsn httpProblem)
              Right (body, filename) ->
                let path = home </> filename
                    decoder = if filename == "elm.json" then elmConstraintsDecoder else constraintsDecoder
                    url = Website.metadata repositoryUrl pkg vsn filename
                 in case D.fromByteString decoder body of
                      Right cs ->
                        do
                          Dir.createDirectoryIfMissing True home
                          File.writeUtf8Atomic path body
                          ok (toNewState cs) cs back
                      Left _ ->
                        err (Exit.SolverBadHttpData pkg vsn url)

getConstraints :: Pkg.Name -> Version -> Solver Constraints
getConstraints pkg vsn =
  Solver $ \state@(State cache connection registry cDict) ok back err ->
    do
      let key = (pkg, vsn)
      case Map.lookup key cDict of
        Just cs ->
          ok state cs back
        Nothing ->
          do
            let toNewState cs = State cache connection registry (Map.insert key cs cDict)
            let home = Stuff.package cache pkg vsn
            path <- Stuff.getConfigFilePath home
            outlineExists <- File.exists path
            if outlineExists
              then do
                bytes <- File.readUtf8 path
                -- Log detailed parsing attempt
                printLog ("PARSE_ATTEMPT: Reading " <> path <> " for " <> Pkg.toChars pkg <> " " <> V.toChars vsn)
                printLog ("PARSE_SIZE: " <> show (BS.length bytes) <> " bytes")
                -- Log first 200 chars for debugging
                let preview = BS.take 200 bytes
                    previewText = show preview
                printLog ("PARSE_PREVIEW: " <> previewText)
                -- Choose decoder based on filename (elm.json vs canopy.json)
                let filename = FP.takeFileName path
                    decoder = if filename == "elm.json" then elmConstraintsDecoder else constraintsDecoder
                printLog ("DECODER_CHOICE: Using " <> (if filename == "elm.json" then "elmConstraintsDecoder" else "constraintsDecoder") <> " for " <> filename)
                case D.fromByteString decoder bytes of
                  Right cs ->
                    do
                      printLog ("PARSE_SUCCESS: " <> path <> " for " <> Pkg.toChars pkg <> " " <> V.toChars vsn)
                      case connection of
                        Online _ ->
                          ok (toNewState cs) cs back
                        Offline _ ->
                          do
                            srcExists <- Dir.doesDirectoryExist (Stuff.package cache pkg vsn </> "src")
                            if srcExists
                              then ok (toNewState cs) cs back
                              else back state
                  Left parseError ->
                    do
                      printLog ("PARSE_FAILURE: " <> path <> " for " <> Pkg.toChars pkg <> " " <> V.toChars vsn)
                      printLog ("PARSE_ERROR: " <> show parseError)
                      printLog ("CORRUPT_CONTENT_FULL: " <> show bytes)
                      File.remove path
                      err (Exit.SolverBadCacheData pkg vsn)
              else case connection of
                Offline _ ->
                  back state
                Online manager ->
                  do
                    let registryKeyMaybe = Registry.lookupPackageRegistryKey registry pkg vsn
                    -- FIXME: I feel like this entire case should be nicer
                    case registryKeyMaybe of
                      Just (Registry.RepositoryUrlKey repositoryData) ->
                        getFromCustomSingleRepositoryData repositoryData pkg vsn cache toNewState manager ok back err
                      Just (Registry.PackageUrlKey singlePackageData) ->
                        do
                          let packageUrl = _url singlePackageData
                          let url = Utf8.toChars packageUrl
                          printLog ("DOWNLOAD_START: " <> Pkg.toChars pkg <> " " <> V.toChars vsn <> " from " <> url)
                          result <-
                            -- FIXME: Use custom error instead of SolverBadHttpData for bad ZIP data
                            Http.getArchiveWithFallback manager url (Exit.SolverBadHttp pkg vsn) (Exit.SolverBadHttpData pkg vsn url) $
                              -- FIXME: Deal with the SHA hash instead of ignoring it
                              \(_, archive) ->
                                -- FIXME: Do I need to do this createDirectoryIfMissing?
                                Right <$> do
                                  printLog ("EXTRACT_START: " <> Pkg.toChars pkg <> " " <> V.toChars vsn <> " to " <> home)
                                  Dir.createDirectoryIfMissing True home
                                  File.writePackageReturnCanopyJson (Stuff.package cache pkg vsn) archive
                          case result of
                            -- In this case we should've successfully written canopy.json to our cache so let's take a look
                            -- FIXME: I don't like this implicit dependence
                            Right (Just body) ->
                              do
                                printLog ("EXTRACT_SUCCESS: " <> Pkg.toChars pkg <> " " <> V.toChars vsn <> " extracted canopy.json (" <> show (BS.length body) <> " bytes)")
                                -- Log preview of extracted content
                                let preview = BS.take 200 body
                                    previewText = show preview
                                printLog ("EXTRACT_PREVIEW: " <> previewText)
                                -- Try canopy.json format first, then fallback to elm.json format
                                case D.fromByteString constraintsDecoder body of
                                  Right cs ->
                                    do
                                      printLog ("EXTRACT_PARSE_SUCCESS: " <> Pkg.toChars pkg <> " " <> V.toChars vsn <> " (canopy.json format)")
                                      Dir.createDirectoryIfMissing True home
                                      printLog ("CACHE_WRITE_START: Writing to cache " <> path)
                                      File.writeUtf8Atomic path body
                                      printLog ("CACHE_WRITE_COMPLETE: " <> path)

                                      -- Verify cache write integrity
                                      printLog ("CACHE_INTEGRITY_CHECK: Verifying " <> path)
                                      cachedContent <- File.readUtf8 path
                                      if cachedContent == body
                                        then do
                                          printLog ("CACHE_INTEGRITY_SUCCESS: " <> path <> " matches written content")
                                          ok (toNewState cs) cs back
                                        else do
                                          printLog ("CACHE_INTEGRITY_FAILURE: " <> path <> " does not match written content!")
                                          printLog ("CACHE_WRITTEN_SIZE: " <> show (BS.length cachedContent) <> " bytes")
                                          printLog ("CACHE_EXPECTED_SIZE: " <> show (BS.length body) <> " bytes")
                                          printLog ("CACHE_WRITTEN_PREVIEW: " <> show (BS.take 100 cachedContent))
                                          printLog ("CACHE_EXPECTED_PREVIEW: " <> show (BS.take 100 body))
                                          -- Still proceed but log the issue
                                          ok (toNewState cs) cs back
                                  Left canopyParseError ->
                                    do
                                      printLog ("EXTRACT_CANOPY_PARSE_FAILURE: " <> Pkg.toChars pkg <> " " <> V.toChars vsn <> ", trying elm.json format")
                                      printLog ("EXTRACT_CANOPY_ERROR: " <> show canopyParseError)
                                      -- Try elm.json format as fallback
                                      case D.fromByteString elmConstraintsDecoder body of
                                        Right cs ->
                                          do
                                            printLog ("EXTRACT_PARSE_SUCCESS: " <> Pkg.toChars pkg <> " " <> V.toChars vsn <> " (elm.json format)")
                                            Dir.createDirectoryIfMissing True home
                                            printLog ("CACHE_WRITE_START: Writing to cache " <> path)
                                            File.writeUtf8Atomic path body
                                            printLog ("CACHE_WRITE_COMPLETE: " <> path)

                                            -- Verify cache write integrity
                                            printLog ("CACHE_INTEGRITY_CHECK: Verifying " <> path)
                                            cachedContent <- File.readUtf8 path
                                            if cachedContent == body
                                              then do
                                                printLog ("CACHE_INTEGRITY_SUCCESS: " <> path <> " matches written content")
                                                ok (toNewState cs) cs back
                                              else do
                                                printLog ("CACHE_INTEGRITY_FAILURE: " <> path <> " does not match written content!")
                                                printLog ("CACHE_WRITTEN_SIZE: " <> show (BS.length cachedContent) <> " bytes")
                                                printLog ("CACHE_EXPECTED_SIZE: " <> show (BS.length body) <> " bytes")
                                                printLog ("CACHE_WRITTEN_PREVIEW: " <> show (BS.take 100 cachedContent))
                                                printLog ("CACHE_EXPECTED_PREVIEW: " <> show (BS.take 100 body))
                                                -- Still proceed but log the issue
                                                ok (toNewState cs) cs back
                                        Left elmParseError ->
                                          do
                                            printLog ("EXTRACT_ELM_PARSE_FAILURE: " <> Pkg.toChars pkg <> " " <> V.toChars vsn)
                                            printLog ("EXTRACT_CANOPY_ERROR: " <> show canopyParseError)
                                            printLog ("EXTRACT_ELM_ERROR: " <> show elmParseError)
                                            printLog ("EXTRACT_CORRUPT_CONTENT: " <> show body)
                                            err (Exit.SolverBadHttpData pkg vsn url)
                            Right Nothing ->
                              -- FIXME: Maybe want a custom error for this?
                              err (Exit.SolverBadHttpData pkg vsn url)
                            Left archiveErr ->
                              err archiveErr
                      Nothing ->
                        -- FIXME: I'm only ~70% sure you can actually hit this error case... should verify
                        -- I think you hit this if we have a transitive dependency on a package that doesn't exist?
                        err (Exit.SolverNonexistentPackage pkg vsn)

constraintsDecoder :: D.Decoder () Constraints
constraintsDecoder =
  do
    outline <- D.mapError (const ()) Outline.decoder
    case outline of
      Outline.Pkg (Outline.PkgOutline _ _ _ _ _ deps _ canopyConstraint) ->
        return (Constraints canopyConstraint deps)
      Outline.App _ ->
        D.failure ()

-- ENVIRONMENT

data Env
  = Env Stuff.PackageCache Http.Manager Connection Registry.ZokkaRegistries Stuff.PackageOverridesCache

initEnv :: IO (Either Exit.RegistryProblem Env)
initEnv =
  do
    manager <- Http.getManager
    tvar <- newTVarIO (Just manager)
    cache <- Stuff.getPackageCache
    packageOverridesCache <- Stuff.getPackageOverridesCache
    zokkaCache <- Stuff.getZokkaCache
    customRepositoriesConfigLocation <- Stuff.getOrCreateZokkaCustomRepositoryConfig
    customRepositoriesDataOrErr <- loadCustomRepositoriesData customRepositoriesConfigLocation
    case customRepositoriesDataOrErr of
      Left err -> pure $ Left (RP_BadCustomReposData err (unZokkaCustomRepositoryConfigFilePath customRepositoriesConfigLocation))
      Right customRepositoriesData ->
        Stuff.withRegistryLock cache $
          do
            maybeRegistry <- Registry.read zokkaCache
            maybeManager <- readTVarIO tvar
            case maybeManager of
              Nothing -> error "HTTP manager not initialized"
              Just httpManager -> do
                modifiedTimeOfCustomRepositoriesData <- getTime (unZokkaCustomRepositoryConfigFilePath customRepositoriesConfigLocation)

                case maybeRegistry of
                  Nothing ->
                    do
                      eitherRegistry <- Registry.fetch httpManager zokkaCache customRepositoriesData modifiedTimeOfCustomRepositoriesData
                      case eitherRegistry of
                        Right latestRegistry ->
                          return . Right $ Env cache httpManager (Online httpManager) latestRegistry packageOverridesCache
                        Left problem ->
                          return . Left $ problem
                  Just cachedRegistry@ZokkaRegistries {_lastModificationTimeOfCustomRepoConfig = customRepoConfigUpdateTime} ->
                    do
                      -- FIXME: Think about whether I need a lock on the custom repository JSON file as well
                      eitherRegistry <-
                        if customRepoConfigUpdateTime == modifiedTimeOfCustomRepositoriesData
                          then Registry.update httpManager zokkaCache cachedRegistry modifiedTimeOfCustomRepositoriesData
                          else Registry.fetch httpManager zokkaCache customRepositoriesData modifiedTimeOfCustomRepositoriesData
                      case eitherRegistry of
                        Right latestRegistry ->
                          return . Right $ Env cache httpManager (Online httpManager) latestRegistry packageOverridesCache
                        Left registryProblem ->
                          return . Right $ Env cache httpManager (Offline registryProblem) cachedRegistry packageOverridesCache

initEnvForReactorTH :: IO (Either Exit.RegistryProblem Env)
initEnvForReactorTH =
  do
    manager <- Http.getManager
    tvar <- newTVarIO (Just manager)
    cache <- Stuff.getPackageCache
    packageOverridesCache <- Stuff.getPackageOverridesCache
    zokkaCache <- Stuff.getZokkaCache
    customRepositoriesConfigLocation <- Stuff.getOrCreateZokkaCustomRepositoryConfig
    customRepositoriesDataOrErr <- loadCustomRepositoriesDataForReactorTH customRepositoriesConfigLocation
    case customRepositoriesDataOrErr of
      Left err -> pure $ Left (RP_BadCustomReposData err (unZokkaCustomRepositoryConfigFilePath customRepositoriesConfigLocation))
      Right customRepositoriesData ->
        Stuff.withRegistryLock cache $
          do
            maybeRegistry <- Registry.read zokkaCache
            maybeManager <- readTVarIO tvar
            case maybeManager of
              Nothing -> error "HTTP manager not initialized"
              Just httpManager -> do
                modifiedTimeOfCustomRepositoriesData <- getTime (unZokkaCustomRepositoryConfigFilePath customRepositoriesConfigLocation)

                case maybeRegistry of
                  Nothing ->
                    do
                      eitherRegistry <- Registry.fetch httpManager zokkaCache customRepositoriesData modifiedTimeOfCustomRepositoriesData
                      case eitherRegistry of
                        Right latestRegistry ->
                          return . Right $ Env cache httpManager (Online httpManager) latestRegistry packageOverridesCache
                        Left problem ->
                          return . Left $ problem
                  Just cachedRegistry ->
                    do
                      eitherRegistry <- Registry.update manager zokkaCache cachedRegistry modifiedTimeOfCustomRepositoriesData
                      case eitherRegistry of
                        Right latestRegistry ->
                          return . Right $ Env cache httpManager (Online httpManager) latestRegistry packageOverridesCache
                        Left registryProblem ->
                          return . Right $ Env cache httpManager (Offline registryProblem) cachedRegistry packageOverridesCache

-- INSTANCES

instance Functor Solver where
  fmap func (Solver solver) =
    Solver $ \state ok back err ->
      let okA stateA arg = ok stateA (func arg)
       in solver state okA back err

instance Applicative Solver where
  pure a =
    Solver $ \state ok back _ -> ok state a back

  (<*>) (Solver solverFunc) (Solver solverArg) =
    Solver $ \state ok back err ->
      let okF stateF func backF =
            let okA stateA arg = ok stateA (func arg)
             in solverArg stateF okA backF err
       in solverFunc state okF back err

instance Monad Solver where
  (>>=) (Solver solverA) callback =
    Solver $ \state ok back err ->
      let okA stateA a backA =
            case callback a of
              Solver solverB -> solverB stateA ok backA err
       in solverA state okA back err

oneOf :: Solver a -> [Solver a] -> Solver a
oneOf solver@(Solver solverHead) solvers =
  case solvers of
    [] ->
      solver
    s : ss ->
      Solver $ \state0 ok back err ->
        let tryTail state1 =
              let (Solver solverTail) = oneOf s ss
               in solverTail state1 ok back err
         in solverHead state0 ok tryTail err

backtrack :: Solver a
backtrack =
  Solver $ \state _ back _ -> back state

-- FETCH PACKAGE METADATA WITH ELM.JSON FALLBACK

fetchPackageMetadata :: Http.Manager -> [Http.Header] -> String -> Pkg.Name -> Version -> String -> IO (Either Http.Error ByteString)
fetchPackageMetadata manager headers repositoryUrl pkg vsn filename =
  do
    let url = Website.metadata (Utf8.fromChars repositoryUrl) pkg vsn filename
    Http.getWithFallback manager url headers id (return . Right)

fetchPackageMetadataWithFallback :: Http.Manager -> [Http.Header] -> String -> Pkg.Name -> Version -> IO (Either Http.Error (ByteString, String))
fetchPackageMetadataWithFallback manager headers repositoryUrl pkg vsn =
  do
    canopyResult <- fetchPackageMetadata manager headers repositoryUrl pkg vsn "canopy.json"
    case canopyResult of
      Right body -> return $ Right (body, "canopy.json")
      Left _ -> do
        elmResult <- fetchPackageMetadata manager headers repositoryUrl pkg vsn "elm.json"
        case elmResult of
          Right body -> return $ Right (body, "elm.json")
          Left err -> return $ Left err

elmConstraintsDecoder :: D.Decoder () Constraints
elmConstraintsDecoder =
  do
    outline <- D.mapError (const ()) Outline.elmDecoder
    case outline of
      Outline.App (Outline.AppOutline canopyVersion _ deps _ _ _ _) ->
        return (Constraints (C.exactly canopyVersion) (Map.map C.exactly deps))
      Outline.Pkg (Outline.PkgOutline _ _ _ _ _ deps _ canopyConstraint) ->
        return (Constraints canopyConstraint deps)

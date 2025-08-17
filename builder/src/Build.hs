{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-unused-do-bind #-}

-- | Build system for the Canopy compiler.
--
-- This module provides the main build functionality for compiling Canopy modules
-- and applications. It has been refactored to comply with CLAUDE.md standards
-- by decomposing large functions into focused sub-modules.
module Build
  ( -- * Main Build Functions
    fromExposed
  , fromPaths  
  , fromRepl
  
  -- * Types (re-exported from Build.Types)
  , Artifacts (..)
  , Root (..)
  , Module (..)
  , CachedInterface (..)
  , ReplArtifacts (..)
  , DocsGoal (..)
  
  -- * Utility Functions
  , getRootNames
  
  -- * Environment Functions
  , makeEnv
  , toAbsoluteSrcDir
  , addRelative
    
  -- * Fork Utilities
  , fork
  , forkWithKey
  ) where

-- Core AST and compilation imports
import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Compile

-- Canopy-specific imports
import qualified Canopy.Details as Details
import qualified Canopy.Docs as Docs
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg

-- Build system modules (refactored)
import Build.Config
  ( CheckConfig (..)
  , CrawlConfig (..) 
  , DepsConfig (..)
  )
import Build.Crawl (crawlModule, crawlDeps)
import Build.Dependencies (checkDeps, loadInterfaces)
import Build.Module.Check (checkModule)
import Build.Paths (fromPaths)
import Build.Types
  ( Env (..)
  , AbsoluteSrcDir (..)
  , Status (..)
  , DocsNeed (..)
  , Result (..)
  , ResultDict
  , CachedInterface (..)
  , Dependencies
  , DepsStatus (..)
  , RootLocation (..)
  , RootInfo (..)
  , RootStatus (..)
  , RootResult (..)
  , Root (..)
  , Artifacts (..)
  , Module (..)
  , ReplArtifacts (..)
  , DocsGoal (..)
  , rootInfoRelative
  , rootInfoLocation
  )

-- Standard library imports
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar
  ( MVar
  , newEmptyMVar
  , newMVar
  , putMVar
  , readMVar
  )
import Control.Lens ((^.))
import Control.Monad (filterM)
import qualified Data.ByteString as B
import qualified Data.Char as Char
import Data.Foldable (sequenceA_, traverse_)
import qualified Data.Graph as Graph
import qualified Data.List as List
import Data.Map.Strict (Map, (!))
import qualified Data.Map.Strict as Map
import qualified Data.Map.Utils as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import qualified Data.OneOrMore as OneOrMore
import qualified Data.Set as Set
import Debug.Trace (trace)
import qualified File
import qualified Json.Encode as E
import qualified Parse.Module as Parse
import qualified Reporting
import qualified Reporting.Annotation as A
import qualified Reporting.Error as Error
import qualified Reporting.Error.Docs as EDocs
import qualified Reporting.Error.Import as Import
import qualified Reporting.Exit as Exit
import qualified Reporting.Render.Type.Localizer as L
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath ((<.>), (</>))
import qualified System.FilePath as FP

-- ENVIRONMENT

-- NOTE: Env type is now defined in Build.Types and imported

makeEnv :: Reporting.BKey -> FilePath -> Details.Details -> IO Env
makeEnv key root (Details.Details _ validOutline buildID locals foreigns _) =
  case validOutline of
    Details.ValidApp givenSrcDirs -> do
      srcDirs <- traverse (toAbsoluteSrcDir root) (NE.toList givenSrcDirs)
      pure $ Env key root Parse.Application srcDirs buildID locals foreigns
    Details.ValidPkg pkg _ _ -> do
      srcDir <- toAbsoluteSrcDir root (Outline.RelativeSrcDir "src")
      pure $ Env key root (Parse.Package pkg) [srcDir] buildID locals foreigns

-- SOURCE DIRECTORY

-- NOTE: AbsoluteSrcDir type is now defined in Build.Types and imported

toAbsoluteSrcDir :: FilePath -> Outline.SrcDir -> IO AbsoluteSrcDir
toAbsoluteSrcDir root srcDir =
  AbsoluteSrcDir
    <$> Dir.canonicalizePath
      ( case srcDir of
          Outline.AbsoluteSrcDir dir -> dir
          Outline.RelativeSrcDir dir -> root </> dir
      )

addRelative :: AbsoluteSrcDir -> FilePath -> FilePath
addRelative (AbsoluteSrcDir srcDir) path =
  srcDir </> path

-- FORK

-- PERF try using IORef semephore on file crawl phase?
-- described in Chapter 13 of Parallel and Concurrent Programming in Haskell by Simon Marlow
-- https://www.oreilly.com/library/view/parallel-and-concurrent/9781449335939/ch13.html#sec_conc-par-overhead
--
fork :: IO a -> IO (MVar a)
fork work =
  do
    mvar <- newEmptyMVar
    _ <- forkIO $ work >>= putMVar mvar
    return mvar

{-# INLINE forkWithKey #-}
forkWithKey :: (k -> a -> IO b) -> Map k a -> IO (Map k (MVar b))
forkWithKey func =
  Map.traverseWithKey (\k v -> fork (func k v))

-- FROM EXPOSED

fromExposed :: Reporting.Style -> FilePath -> Details.Details -> DocsGoal docs -> List ModuleName.Raw -> IO (Either Exit.BuildProblem docs)
fromExposed style root details docsGoal exposed@(NE.List e es) =
  Reporting.trackBuild style $ \key ->
    do
      env <- makeEnv key root details
      dmvar <- Details.loadInterfaces root details

      -- crawl
      mvar <- newEmptyMVar
      let docsNeed = toDocsNeed docsGoal
      roots <- Map.fromKeysA (fork . crawlModule (CrawlConfig env mvar docsNeed)) (e : es)
      putMVar mvar roots
      traverse_ readMVar roots
      statuses <- readMVar mvar >>= traverse readMVar

      -- compile
      midpoint <- checkMidpoint dmvar statuses
      case midpoint of
        Left problem ->
          return (Left (Exit.BuildProjectProblem problem))
        Right foreigns ->
          do
            rmvar <- newEmptyMVar
            resultMVars <- forkWithKey (checkModule (CheckConfig env foreigns rmvar)) statuses
            putMVar rmvar resultMVars
            results <- traverse readMVar resultMVars
            writeDetails root details results
            finalizeExposed root docsGoal exposed results

-- FROM PATHS

-- NOTE: Artifacts, Module, and Dependencies types are now defined in Build.Types and imported
-- NOTE: fromPaths function is now implemented in Build.Paths module

-- Re-export fromPaths from Build.Paths (this is already imported above)

-- GET ROOT NAMES

getRootNames :: Artifacts -> NE.List ModuleName.Raw
getRootNames (Artifacts _ _ roots _) =
  fmap getRootName roots

getRootName :: Root -> ModuleName.Raw
getRootName root =
  case root of
    Inside name -> name
    Outside name _ _ -> name

-- CRAWL




-- NOTE: crawlModule function is now implemented in Build.Crawl module
-- Using configuration-based approach to reduce parameter count

-- NOTE: crawlModule function is now implemented in Build.Crawl module

-- NOTE: crawlFile function is now implemented in Build.Crawl module

-- NOTE: isMain function is now implemented in Build.Crawl module

-- CHECK MODULE



-- NOTE: checkModule function is now implemented in Build.Module.Check module
-- Using configuration-based approach to reduce parameter count

-- NOTE: checkModule function is now imported from Build.Module.Check

-- CHECK DEPS

-- NOTE: DepsStatus, Dep, CDep types are now defined in Build.Types and imported
-- NOTE: checkDeps and checkDepsHelp functions are now implemented in Build.Dependencies module

-- NOTE: checkDeps function is now imported from Build.Dependencies

-- TO IMPORT ERROR

toImportErrors :: Env -> ResultDict -> [Src.Import] -> NE.List (ModuleName.Raw, Import.Problem) -> NE.List Import.Error
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
        Import.Error (regionDict ! name) name unimportedModules problem
   in fmap toError problems

-- LOAD CACHED INTERFACES


-- CHECK PROJECT

checkMidpoint :: MVar (Maybe Dependencies) -> Map.Map ModuleName.Raw Status -> IO (Either Exit.BuildProjectProblem Dependencies)
checkMidpoint dmvar statuses =
  case checkForCycles statuses of
    Nothing ->
      do
        maybeForeigns <- readMVar dmvar
        case maybeForeigns of
          Nothing -> return (Left Exit.BP_CannotLoadDependencies)
          Just fs -> return (Right fs)
    Just (NE.List name names) ->
      do
        _ <- readMVar dmvar
        return (Left (Exit.BP_Cycle name names))

checkMidpointAndRoots :: MVar (Maybe Dependencies) -> Map.Map ModuleName.Raw Status -> NE.List RootStatus -> IO (Either Exit.BuildProjectProblem Dependencies)
checkMidpointAndRoots dmvar statuses sroots =
  case checkForCycles statuses of
    Nothing ->
      case checkUniqueRoots statuses sroots of
        Nothing ->
          do
            maybeForeigns <- readMVar dmvar
            case maybeForeigns of
              Nothing -> return (Left Exit.BP_CannotLoadDependencies)
              Just fs -> return (Right fs)
        Just problem ->
          do
            _ <- readMVar dmvar
            return (Left problem)
    Just (NE.List name names) ->
      do
        _ <- readMVar dmvar
        return (Left (Exit.BP_Cycle name names))

-- CHECK FOR CYCLES

checkForCycles :: Map.Map ModuleName.Raw Status -> Maybe (NE.List ModuleName.Raw)
checkForCycles modules =
  let !graph = Map.foldrWithKey addToGraph [] modules
      !sccs = Graph.stronglyConnComp graph
   in checkForCyclesHelp sccs

checkForCyclesHelp :: [Graph.SCC ModuleName.Raw] -> Maybe (NE.List ModuleName.Raw)
checkForCyclesHelp sccs =
  case sccs of
    [] ->
      Nothing
    scc : otherSccs ->
      case scc of
        Graph.AcyclicSCC _ -> checkForCyclesHelp otherSccs
        Graph.CyclicSCC [] -> checkForCyclesHelp otherSccs
        Graph.CyclicSCC (m : ms) -> Just (NE.List m ms)

type Node =
  (ModuleName.Raw, ModuleName.Raw, [ModuleName.Raw])

addToGraph :: ModuleName.Raw -> Status -> [Node] -> [Node]
addToGraph name status graph =
  let dependencies =
        case status of
          SCached (Details.Local _ _ deps _ _ _) -> deps
          SChanged (Details.Local _ _ deps _ _ _) _ _ _ -> deps
          SBadImport _ -> []
          SBadSyntax {} -> []
          SForeign _ -> []
          SKernel -> []
   in (name, name, dependencies) : graph

-- CHECK UNIQUE ROOTS

checkUniqueRoots :: Map.Map ModuleName.Raw Status -> NE.List RootStatus -> Maybe Exit.BuildProjectProblem
checkUniqueRoots insides sroots =
  let outsidesDict =
        Map.fromListWith OneOrMore.more (Maybe.mapMaybe rootStatusToNamePathPair (NE.toList sroots))
   in case Map.traverseWithKey checkOutside outsidesDict of
        Left problem ->
          Just problem
        Right outsides ->
          case sequenceA_ (Map.intersectionWithKey checkInside outsides insides) of
            Right () -> Nothing
            Left problem -> Just problem

rootStatusToNamePathPair :: RootStatus -> Maybe (ModuleName.Raw, OneOrMore.OneOrMore FilePath)
rootStatusToNamePathPair sroot =
  case sroot of
    SInside _ -> Nothing
    SOutsideOk (Details.Local path _ _ _ _ _) _ modul -> Just (Src.getName modul, OneOrMore.one path)
    SOutsideErr _ -> Nothing

checkOutside :: ModuleName.Raw -> OneOrMore.OneOrMore FilePath -> Either Exit.BuildProjectProblem FilePath
checkOutside name paths =
  case OneOrMore.destruct NE.List paths of
    NE.List p [] -> Right p
    NE.List p1 (p2 : _) -> Left (Exit.BP_RootNameDuplicate name p1 p2)

checkInside :: ModuleName.Raw -> FilePath -> Status -> Either Exit.BuildProjectProblem ()
checkInside name p1 status =
  case status of
    SCached (Details.Local p2 _ _ _ _ _) -> Left (Exit.BP_RootNameDuplicate name p1 p2)
    SChanged (Details.Local p2 _ _ _ _ _) _ _ _ -> Left (Exit.BP_RootNameDuplicate name p1 p2)
    SBadImport _ -> Right ()
    SBadSyntax {} -> Right ()
    SForeign _ -> Right ()
    SKernel -> Right ()

-- COMPILE MODULE

compile :: Env -> DocsNeed -> Details.Local -> B.ByteString -> Map.Map ModuleName.Raw I.Interface -> Src.Module -> IO Result
compile (Env key root projectType _ buildID _ _) docsNeed (Details.Local path time deps main lastChange _) source ifaces modul =
  let pkg = projectTypeToPkg projectType
   in case Compile.compile pkg ifaces modul of
        Right (Compile.Artifacts canonical annotations objects) ->
          case makeDocs docsNeed canonical of
            Left err ->
              return . RProblem $ Error.Module (Src.getName modul) path time source (Error.BadDocs err)
            Right docs ->
              do
                let name = Src.getName modul
                let iface = I.fromModule pkg canonical annotations
                File.writeBinary (Stuff.canopyo root name) objects
                maybeOldi <- File.readBinary (Stuff.canopyi root name)
                case maybeOldi of
                  Just oldi | oldi == iface ->
                    do
                      -- iface should be fully forced by equality check
                      Reporting.report key Reporting.BDone
                      let local = Details.Local path time deps main lastChange buildID
                      return (RSame local iface objects docs)
                  _ ->
                    do
                      -- iface may be lazy still
                      File.writeBinary (Stuff.canopyi root name) iface
                      Reporting.report key Reporting.BDone
                      let local = Details.Local path time deps main buildID buildID
                      return (RNew local iface objects docs)
        Left err ->
          return . RProblem $ Error.Module (Src.getName modul) path time source err

projectTypeToPkg :: Parse.ProjectType -> Pkg.Name
projectTypeToPkg projectType =
  case projectType of
    Parse.Package pkg -> pkg
    Parse.Application -> Pkg.dummyName

-- WRITE DETAILS

writeDetails :: FilePath -> Details.Details -> Map.Map ModuleName.Raw Result -> IO ()
writeDetails root (Details.Details time outline buildID locals foreigns extras) results =
  File.writeBinary (Stuff.details root) $
    Details.Details time outline buildID (Map.foldrWithKey addNewLocal locals results) foreigns extras

addNewLocal :: ModuleName.Raw -> Result -> Map.Map ModuleName.Raw Details.Local -> Map.Map ModuleName.Raw Details.Local
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

-- FINALIZE EXPOSED

finalizeExposed :: FilePath -> DocsGoal docs -> NE.List ModuleName.Raw -> Map.Map ModuleName.Raw Result -> IO (Either Exit.BuildProblem docs)
finalizeExposed root docsGoal exposed results =
  case foldr (addImportProblems results) [] (NE.toList exposed) of
    p : ps ->
      return . Left $ Exit.BuildProjectProblem (Exit.BP_MissingExposed (NE.List p ps))
    [] ->
      case Map.foldr addErrors [] results of
        [] -> Right <$> finalizeDocs docsGoal results
        e : es -> return . Left $ Exit.BuildBadModules root e es

addErrors :: Result -> [Error.Module] -> [Error.Module]
addErrors result errors =
  case result of
    RNew {} -> errors
    RSame {} -> errors
    RCached {} -> errors
    RNotFound _ -> errors
    RProblem e -> e : errors
    RBlocked -> errors
    RForeign _ -> errors
    RKernel -> errors

addImportProblems :: Map.Map ModuleName.Raw Result -> ModuleName.Raw -> [(ModuleName.Raw, Import.Problem)] -> [(ModuleName.Raw, Import.Problem)]
addImportProblems results name problems =
  case results ! name of
    RNew {} -> problems
    RSame {} -> problems
    RCached {} -> problems
    RNotFound p -> (name, p) : problems
    RProblem _ -> problems
    RBlocked -> problems
    RForeign _ -> problems
    RKernel -> problems

-- DOCS

-- NOTE: DocsGoal and DocsNeed types are now defined in Build.Types and imported

toDocsNeed :: DocsGoal a -> DocsNeed
toDocsNeed goal =
  case goal of
    IgnoreDocs -> DocsNeed False
    WriteDocs _ -> DocsNeed True
    KeepDocs -> DocsNeed True

makeDocs :: DocsNeed -> Can.Module -> Either EDocs.Error (Maybe Docs.Module)
makeDocs (DocsNeed isNeeded) modul =
  if isNeeded
    then case Docs.fromModule modul of
      Right docs -> Right (Just docs)
      Left err -> Left err
    else Right Nothing

finalizeDocs :: DocsGoal docs -> Map.Map ModuleName.Raw Result -> IO docs
finalizeDocs goal results =
  case goal of
    KeepDocs ->
      return $ Map.mapMaybe toDocs results
    WriteDocs path ->
      E.writeUgly path . Docs.encode $ Map.mapMaybe toDocs results
    IgnoreDocs ->
      return ()

toDocs :: Result -> Maybe Docs.Module
toDocs result =
  case result of
    RNew _ _ _ d -> d
    RSame _ _ _ d -> d
    RCached {} -> Nothing
    RNotFound _ -> Nothing
    RProblem _ -> Nothing
    RBlocked -> Nothing
    RForeign _ -> Nothing
    RKernel -> Nothing

--------------------------------------------------------------------------------
------ NOW FOR SOME REPL STUFF -------------------------------------------------
--------------------------------------------------------------------------------

-- FROM REPL


fromRepl :: FilePath -> Details.Details -> B.ByteString -> IO (Either Exit.Repl ReplArtifacts)
fromRepl root details source =
  do
    env@(Env _ _ projectType _ _ _ _) <- makeEnv Reporting.ignorer root details
    case Parse.fromByteString projectType source of
      Left syntaxError ->
        (return . Left) . Exit.ReplBadInput source $ Error.BadSyntax syntaxError
      Right modul@(Src.Module _ _ _ imports _ _ _ _ _) ->
        do
          dmvar <- Details.loadInterfaces root details

          let deps = fmap Src.getImportName imports
          mvar <- newMVar Map.empty
          crawlDeps env mvar deps ()

          statuses <- readMVar mvar >>= traverse readMVar
          midpoint <- checkMidpoint dmvar statuses

          case midpoint of
            Left problem ->
              return . Left $ Exit.ReplProjectProblem problem
            Right foreigns ->
              do
                rmvar <- newEmptyMVar
                resultMVars <- forkWithKey (checkModule (CheckConfig env foreigns rmvar)) statuses
                putMVar rmvar resultMVars
                results <- traverse readMVar resultMVars
                writeDetails root details results
                depsStatus <- checkDeps (DepsConfig root resultMVars deps 0)
                finalizeReplArtifacts env source modul depsStatus resultMVars results

finalizeReplArtifacts :: Env -> B.ByteString -> Src.Module -> DepsStatus -> ResultDict -> Map.Map ModuleName.Raw Result -> IO (Either Exit.Repl ReplArtifacts)
finalizeReplArtifacts env@(Env _ root projectType _ _ _ _) source modul@(Src.Module _ _ _ imports _ _ _ _ _) depsStatus resultMVars results =
  let pkg =
        projectTypeToPkg projectType

      compileInput ifaces =
        case Compile.compile pkg ifaces modul of
          Right (Compile.Artifacts canonical annotations objects) ->
            let h = Can._name canonical
                m = Fresh (Src.getName modul) (I.fromModule pkg canonical annotations) objects
                ms = Map.foldrWithKey addInside [] results
             in (return . Right $ ReplArtifacts h (m : ms) (L.fromModule modul) annotations)
          Left errors ->
            return . Left $ Exit.ReplBadInput source errors
   in case depsStatus of
        DepsChange ifaces ->
          compileInput ifaces
        DepsSame same cached ->
          do
            maybeLoaded <- loadInterfaces root same cached
            case maybeLoaded of
              Just ifaces -> compileInput ifaces
              Nothing -> return . Left $ Exit.ReplBadCache
        DepsBlock ->
          case Map.foldr addErrors [] results of
            [] -> return . Left $ Exit.ReplBlocked
            e : es -> return . Left $ Exit.ReplBadLocalDeps root e es
        DepsNotFound problems ->
          ((return . Left) . Exit.ReplBadInput source) . Error.BadImports $ toImportErrors env resultMVars imports problems

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
------ AFTER THIS, EVERYTHING IS ABOUT HANDLING MODULES GIVEN BY FILEPATH ------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- FIND ROOT


findRoots :: Env -> NE.List FilePath -> IO (Either Exit.BuildProjectProblem (NE.List RootLocation))
findRoots env paths =
  do
    mvars <- traverse (fork . getRootInfo env) paths
    einfos <- traverse readMVar mvars
    return (sequenceA einfos >>= checkRoots)

checkRoots :: NE.List RootInfo -> Either Exit.BuildProjectProblem (NE.List RootLocation)
checkRoots infos =
  let toOneOrMore loc@(RootInfo absolute _ _) =
        (absolute, OneOrMore.one loc)

      fromOneOrMore loc locs =
        case locs of
          [] -> Right ()
          loc2 : _ -> Left (Exit.BP_MainPathDuplicate (loc ^. rootInfoRelative) (loc2 ^. rootInfoRelative))
   in ((fmap (\_ -> fmap (^. rootInfoLocation) infos) . traverse (OneOrMore.destruct fromOneOrMore)) . Map.fromListWith OneOrMore.more $ fmap toOneOrMore (NE.toList infos))

-- ROOT INFO


getRootInfo :: Env -> FilePath -> IO (Either Exit.BuildProjectProblem RootInfo)
getRootInfo env path =
  do
    exists <- File.exists path
    if exists
      then Dir.canonicalizePath path >>= getRootInfoHelp env path
      else return (Left (Exit.BP_PathUnknown path))

getRootInfoHelp :: Env -> FilePath -> FilePath -> IO (Either Exit.BuildProjectProblem RootInfo)
getRootInfoHelp (Env _ _ _ srcDirs _ _ _) path absolutePath =
  let (dirs, file) = FP.splitFileName absolutePath
      (final, ext) = FP.splitExtension file
   in if not (ext == ".can" || ext == ".canopy" || ext == ".elm")
        then return . Left $ Exit.BP_WithBadExtension path
        else
          let absoluteSegments = (FP.splitDirectories dirs <> [final])
           in case Maybe.mapMaybe (isInsideSrcDirByPath absoluteSegments) srcDirs of
                [] ->
                  return . Right $ RootInfo absolutePath path (LOutside path)
                [(_, Right names)] ->
                  do
                    let name = Name.fromChars (List.intercalate "." names)
                    matchingDirs <- filterM (isInsideSrcDirByName names) srcDirs
                    case matchingDirs of
                      d1 : d2 : _ ->
                        do
                          let p1 = addRelative d1 (FP.joinPath names <.> "can")
                          let p2 = addRelative d2 (FP.joinPath names <.> "can")
                          return . Left $ Exit.BP_RootNameDuplicate name p1 p2
                      _ ->
                        return . Right $ RootInfo absolutePath path (LInside name)
                [(s, Left names)] ->
                  return . Left $ Exit.BP_RootNameInvalid path s names
                (s1, _) : (s2, _) : _ ->
                  return . Left $ Exit.BP_WithAmbiguousSrcDir path s1 s2

isInsideSrcDirByName :: [String] -> AbsoluteSrcDir -> IO Bool
isInsideSrcDirByName names srcDir =
  do
    let base = FP.joinPath names
    existsCan <- File.exists (addRelative srcDir (base <.> "can"))
    if existsCan
      then return True
      else do
        existsCanopy <- File.exists (addRelative srcDir (base <.> "canopy"))
        if existsCanopy then return True else File.exists (addRelative srcDir (base <.> "elm"))

isInsideSrcDirByPath :: [String] -> AbsoluteSrcDir -> Maybe (FilePath, Either [String] [String])
isInsideSrcDirByPath segments (AbsoluteSrcDir srcDir) =
  case dropPrefix (FP.splitDirectories srcDir) segments of
    Nothing ->
      Nothing
    Just names ->
      if all isGoodName names
        then Just (srcDir, Right names)
        else Just (srcDir, Left names)

isGoodName :: String -> Bool
isGoodName name =
  case name of
    [] ->
      False
    char : chars ->
      Char.isUpper char && all (\c -> Char.isAlphaNum c || c == '_') chars

-- INVARIANT: Dir.canonicalizePath has been run on both inputs
--
dropPrefix :: [FilePath] -> [FilePath] -> Maybe [FilePath]
dropPrefix roots paths =
  case roots of
    [] ->
      Just paths
    r : rs ->
      case paths of
        [] -> Nothing
        p : ps -> if r == p then dropPrefix rs ps else Nothing

-- CRAWL ROOTS


-- NOTE: crawlRoot function is now imported from Build.Crawl

-- CHECK ROOTS


checkRoot :: Env -> ResultDict -> RootStatus -> IO RootResult
checkRoot env@(Env _ root _ _ _ _ _) results rootStatus =
  case rootStatus of
    SInside name ->
      return (RInside name)
    SOutsideErr err ->
      return (ROutsideErr err)
    SOutsideOk local@(Details.Local path time deps _ _ lastCompile) source modul@(Src.Module _ _ _ imports _ _ _ _ _) ->
      do
        depsStatus <- checkDeps (DepsConfig root results deps lastCompile)
        case depsStatus of
          DepsChange ifaces ->
            compileOutside env local source ifaces modul
          DepsSame same cached ->
            do
              maybeLoaded <- loadInterfaces root same cached
              case maybeLoaded of
                Nothing -> return ROutsideBlocked
                Just ifaces -> compileOutside env local source ifaces modul
          DepsBlock ->
            return ROutsideBlocked
          DepsNotFound problems ->
            (return . ROutsideErr) . Error.Module (Src.getName modul) path time source $ Error.BadImports (toImportErrors env results imports problems)

compileOutside :: Env -> Details.Local -> B.ByteString -> Map.Map ModuleName.Raw I.Interface -> Src.Module -> IO RootResult
compileOutside (Env key _ projectType _ _ _ _) (Details.Local path time _ _ _ _) source ifaces modul =
  let pkg = projectTypeToPkg projectType
      name = Src.getName modul
   in case Compile.compile pkg ifaces modul of
        Right (Compile.Artifacts canonical annotations objects) ->
          do
            Reporting.report key Reporting.BDone
            return $ ROutsideOk name (I.fromModule pkg canonical annotations) objects
        Left errors ->
          return . ROutsideErr $ Error.Module name path time source errors

-- TO ARTIFACTS


toArtifacts :: Env -> Dependencies -> Map.Map ModuleName.Raw Result -> NE.List RootResult -> Either Exit.BuildProblem Artifacts
toArtifacts (Env _ root projectType _ _ _ _) foreigns results rootResults =
  case gatherProblemsOrMains results rootResults of
    Left (NE.List e es) ->
      Left (Exit.BuildBadModules root e es)
    Right roots ->
      Right . Artifacts (projectTypeToPkg projectType) foreigns roots $ Map.foldrWithKey (addInsideSafe rootResults) (foldr (addOutside results) [] rootResults) results

gatherProblemsOrMains :: Map.Map ModuleName.Raw Result -> NE.List RootResult -> Either (NE.List Error.Module) (NE.List Root)
gatherProblemsOrMains results (NE.List rootResult rootResults) =
  let addResult result (es, roots) =
        case result of
          RInside n -> (es, Inside n : roots)
          ROutsideOk n i o -> (es, Outside n i o : roots)
          ROutsideErr e -> (e : es, roots)
          ROutsideBlocked -> (es, roots)

      errors = Map.foldr addErrors [] results
   in case (rootResult, foldr addResult (errors, []) rootResults) of
        (RInside n, ([], ms)) -> Right (NE.List (Inside n) ms)
        (RInside _, (e : es, _)) -> Left (NE.List e es)
        (ROutsideOk n i o, ([], ms)) -> Right (NE.List (Outside n i o) ms)
        (ROutsideOk {}, (e : es, _)) -> Left (NE.List e es)
        (ROutsideErr e, (es, _)) -> Left (NE.List e es)
        (ROutsideBlocked, ([], _)) -> error "seems like canopy-stuff/ is corrupted"
        (ROutsideBlocked, (e : es, _)) -> Left (NE.List e es)

addInside :: ModuleName.Raw -> Result -> [Module] -> [Module]
addInside name result modules =
  case result of
    RNew _ iface objs _ -> Fresh name iface objs : modules
    RSame _ iface objs _ -> Fresh name iface objs : modules
    RCached main _ mvar -> Cached name main mvar : modules
    RNotFound _ -> error (badInside name)
    RProblem _ -> error (badInside name)
    RBlocked -> error (badInside name)
    RForeign _ -> modules
    RKernel -> modules

addInsideSafe :: List RootResult -> ModuleName.Raw -> Result -> [Module] -> [Module]
addInsideSafe rootResults name result modules =
  -- Root modules should never be processed by addInside since they're handled by addOutside
  if isRootModule rootResults name
    then modules -- Skip root modules entirely
    else case result of
      RNew _ iface objs _ -> Fresh name iface objs : modules
      RSame _ iface objs _ -> Fresh name iface objs : modules
      RCached main _ mvar -> Cached name main mvar : modules
      RNotFound _ -> modules -- Ignore problematic dependencies
      RProblem _ -> modules -- Ignore problematic dependencies
      RBlocked -> modules -- Ignore problematic dependencies
      RForeign _ -> modules
      RKernel -> modules

isRootModule :: List RootResult -> ModuleName.Raw -> Bool
isRootModule rootResults name =
  any (matchesRootName name) (NE.toList rootResults)

matchesRootName :: ModuleName.Raw -> RootResult -> Bool
matchesRootName name rootResult =
  case rootResult of
    RInside n -> n == name
    ROutsideOk n _ _ -> n == name
    ROutsideErr _ -> False
    ROutsideBlocked -> False

badInside :: ModuleName.Raw -> String
badInside name =
  "Error from `" <> (Name.toChars name <> "` should have been reported already.")

addOutside :: Map ModuleName.Raw Result -> RootResult -> [Module] -> [Module]
addOutside results root modules =
  case root of
    RInside name -> do
      -- Look up the result for this root module and handle it
      case Map.lookup name results of
        Just (RNew _ iface objs _) -> Fresh name iface objs : modules
        Just (RSame _ iface objs _) -> Fresh name iface objs : modules
        Just (RCached main _ mvar) -> Cached name main mvar : modules
        Just (RNotFound prob) ->
          -- Log the specific problem to understand why Main is failing
          trace ("WARNING: Main module has RNotFound status: " <> show prob) modules
        Just (RProblem _) -> modules -- Root module has compilation errors, skip
        Just (RBlocked) -> modules -- Root module is blocked, skip
        Just (RForeign _) -> modules -- Shouldn't happen for root modules
        Just (RKernel) -> modules -- Shouldn't happen for root modules
        Nothing -> modules -- Result not found, skip
    ROutsideOk name iface objs -> Fresh name iface objs : modules
    ROutsideErr _ -> modules
    ROutsideBlocked -> modules

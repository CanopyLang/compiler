{-# LANGUAGE OverloadedStrings #-}

module Make
  ( Flags (..),
    Output (..),
    ReportType (..),
    run,
    reportType,
    output,
    docsFile,
  )
where

import qualified AST.Optimized as Opt
import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import Control.Monad (when)
import Data.ByteString.Builder (Builder)
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import qualified File
import qualified Generate
import qualified Generate.Html as Html
import Logging.Logger (printLog, setLogFlag)
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import Terminal (Parser (..))
import qualified Watch

-- FLAGS

data Flags = Flags
  { _debug :: Bool,
    _optimize :: Bool,
    _watch :: Bool,
    _output :: Maybe Output,
    _report :: Maybe ReportType,
    _docs :: Maybe FilePath,
    _verbose :: Bool
  }

data BuildContext = BuildContext
  { _bcStyle :: Reporting.Style,
    _bcRoot :: FilePath,
    _bcDetails :: Details.Details,
    _bcDesiredMode :: DesiredMode
  }

data Output
  = JS FilePath
  | Html FilePath
  | DevNull

data ReportType
  = Json

-- RUN

type Task a = Task.Task Exit.Make a

run :: [FilePath] -> Flags -> IO ()
run paths flags@(Flags {_watch}) =
  if _watch
    then Watch.files (const (runInternal paths flags)) paths
    else runInternal paths flags

runInternal :: [FilePath] -> Flags -> IO ()
runInternal paths flags@(Flags {_report, _verbose}) = do
  when _verbose (setLogFlag True)
  style <- getStyle _report
  maybeRoot <- Stuff.findRoot
  Reporting.attemptWithStyle style Exit.makeToReport $
    case maybeRoot of
      Just root -> runHelp root paths style flags
      Nothing -> return . Left $ Exit.MakeNoOutline

runHelp :: FilePath -> [FilePath] -> Reporting.Style -> Flags -> IO (Either Exit.Make ())
runHelp root paths style flags =
  BW.withScope $ \scope ->
    Stuff.withRootLock root . Task.run $
      buildProject root paths style flags scope

buildProject :: FilePath -> [FilePath] -> Reporting.Style -> Flags -> BW.Scope -> Task ()
buildProject root paths style (Flags {_debug, _optimize, _output, _docs}) scope = do
  desiredMode <- getMode _debug _optimize
  Task.io (printLog "Loading project details")
  details <- Task.eio Exit.MakeBadDetails (Details.load style scope root)
  let ctx = BuildContext style root details desiredMode
  case paths of
    [] -> buildExposedModules style root details _docs
    p : ps -> buildFromPaths ctx _output (NE.List p ps)

buildExposedModules :: Reporting.Style -> FilePath -> Details.Details -> Maybe FilePath -> Task ()
buildExposedModules style root details docs = do
  Task.io (printLog "Building exposed modules (no paths provided)")
  exposed <- getExposed details
  buildExposed style root details docs exposed

buildFromPaths :: BuildContext -> Maybe Output -> List FilePath -> Task ()
buildFromPaths ctx maybeOutput paths = do
  Task.io (printLog ("Building from paths: " <> show paths))
  artifacts <- buildPaths (_bcStyle ctx) (_bcRoot ctx) (_bcDetails ctx) paths
  case maybeOutput of
    Nothing -> generateBasedOnMains ctx artifacts
    Just target -> generateForTarget ctx artifacts target

generateBasedOnMains :: BuildContext -> Build.Artifacts -> Task ()
generateBasedOnMains ctx artifacts =
  case getMains artifacts of
    [] -> Task.io (printLog "No main functions found - generating nothing")
    [name] -> generateSingleMain ctx artifacts name
    names -> generateMultipleMain ctx artifacts names

generateSingleMain :: BuildContext -> Build.Artifacts -> ModuleName.Raw -> Task ()
generateSingleMain ctx artifacts name = do
  Task.io (printLog ("Found single main function - generating HTML: " <> Name.toChars name))
  builder <- toBuilder (_bcRoot ctx) (_bcDetails ctx) (_bcDesiredMode ctx) artifacts
  generate (_bcStyle ctx) "index.html" (Html.sandwich name builder) (NE.List name [])

generateMultipleMain :: BuildContext -> Build.Artifacts -> [ModuleName.Raw] -> Task ()
generateMultipleMain ctx artifacts names =
  case names of
    [] -> Task.io (printLog "No main functions found - generating nothing")
    name : rest -> do
      Task.io (printLog ("Found multiple main functions - generating JS: " <> show (fmap Name.toChars names)))
      builder <- toBuilder (_bcRoot ctx) (_bcDetails ctx) (_bcDesiredMode ctx) artifacts
      generate (_bcStyle ctx) "canopy.js" builder (NE.List name rest)

generateForTarget :: BuildContext -> Build.Artifacts -> Output -> Task ()
generateForTarget _ _ DevNull =
  Task.io (printLog "Output target is /dev/null - generating nothing")
generateForTarget ctx artifacts (JS target) =
  generateJsTarget ctx artifacts target
generateForTarget ctx artifacts (Html target) =
  generateHtmlTarget ctx artifacts target

generateJsTarget :: BuildContext -> Build.Artifacts -> FilePath -> Task ()
generateJsTarget ctx artifacts target =
  case getNoMains artifacts of
    [] -> do
      Task.io (printLog ("Generating JS to: " <> target))
      builder <- toBuilder (_bcRoot ctx) (_bcDetails ctx) (_bcDesiredMode ctx) artifacts
      generate (_bcStyle ctx) target builder (Build.getRootNames artifacts)
    name : names ->
      Task.throw (Exit.MakeNonMainFilesIntoJavaScript name names)

generateHtmlTarget :: BuildContext -> Build.Artifacts -> FilePath -> Task ()
generateHtmlTarget ctx artifacts target = do
  Task.io (printLog ("Generating HTML to: " <> target))
  name <- hasOneMain artifacts
  builder <- toBuilder (_bcRoot ctx) (_bcDetails ctx) (_bcDesiredMode ctx) artifacts
  generate (_bcStyle ctx) target (Html.sandwich name builder) (NE.List name [])

-- GET INFORMATION

getStyle :: Maybe ReportType -> IO Reporting.Style
getStyle report =
  case report of
    Nothing -> Reporting.terminal
    Just Json -> return Reporting.json

getMode :: Bool -> Bool -> Task DesiredMode
getMode debug optimize =
  case (debug, optimize) of
    (True, True) -> Task.throw Exit.MakeCannotOptimizeAndDebug
    (True, False) -> return Debug
    (False, False) -> return Dev
    (False, True) -> return Prod

getExposed :: Details.Details -> Task (List ModuleName.Raw)
getExposed (Details.Details _ validOutline _ _ _ _) =
  case validOutline of
    Details.ValidApp _ ->
      Task.throw Exit.MakeAppNeedsFileNames
    Details.ValidPkg _ exposed _ ->
      case exposed of
        [] -> Task.throw Exit.MakePkgNeedsExposing
        m : ms -> return (NE.List m ms)

-- BUILD PROJECTS

buildExposed :: Reporting.Style -> FilePath -> Details.Details -> Maybe FilePath -> List ModuleName.Raw -> Task ()
buildExposed style root details maybeDocs exposed =
  let docsGoal = maybe Build.IgnoreDocs Build.WriteDocs maybeDocs
   in Task.eio Exit.MakeCannotBuild $
        Build.fromExposed style root details docsGoal exposed

buildPaths :: Reporting.Style -> FilePath -> Details.Details -> List FilePath -> Task Build.Artifacts
buildPaths style root details paths =
  Task.eio Exit.MakeCannotBuild $
    Build.fromPaths style root details paths

-- GET MAINS

getMains :: Build.Artifacts -> [ModuleName.Raw]
getMains (Build.Artifacts _ _ roots modules) =
  Maybe.mapMaybe (getMain modules) (NE.toList roots)

getMain :: [Build.Module] -> Build.Root -> Maybe ModuleName.Raw
getMain modules root =
  case root of
    Build.Inside name ->
      if any (isMain name) modules
        then Just name
        else Nothing
    Build.Outside name _ (Opt.LocalGraph maybeMain _ _) ->
      case maybeMain of
        Just _ -> Just name
        Nothing -> Nothing

isMain :: ModuleName.Raw -> Build.Module -> Bool
isMain targetName modul =
  case modul of
    Build.Fresh name _ (Opt.LocalGraph maybeMain _ _) ->
      Maybe.isJust maybeMain && name == targetName
    Build.Cached name mainIsDefined _ ->
      mainIsDefined && name == targetName

-- HAS ONE MAIN

hasOneMain :: Build.Artifacts -> Task ModuleName.Raw
hasOneMain (Build.Artifacts _ _ roots modules) =
  case roots of
    NE.List root [] -> Task.mio Exit.MakeNoMain (return $ getMain modules root)
    NE.List _ (_ : _) -> Task.throw Exit.MakeMultipleFilesIntoHtml

-- GET MAINLESS

getNoMains :: Build.Artifacts -> [ModuleName.Raw]
getNoMains (Build.Artifacts _ _ roots modules) =
  Maybe.mapMaybe (getNoMain modules) (NE.toList roots)

getNoMain :: [Build.Module] -> Build.Root -> Maybe ModuleName.Raw
getNoMain modules root =
  case root of
    Build.Inside name ->
      if any (isMain name) modules || Name.toChars name == "Main"
        then Nothing -- Main modules or those with main functions
        else Just name
    Build.Outside name _ (Opt.LocalGraph maybeMain _ _) ->
      case maybeMain of
        Just _ -> Nothing
        Nothing -> Just name

-- GENERATE

generate :: Reporting.Style -> FilePath -> Builder -> List ModuleName.Raw -> Task ()
generate style target builder names =
  Task.io $
    do
      Dir.createDirectoryIfMissing True (FP.takeDirectory target)
      printLog "generate 1"
      File.writeBuilder target builder
      printLog "generate 2"
      Reporting.reportGenerate style names target
      printLog "generate 3"

-- TO BUILDER

data DesiredMode = Debug | Dev | Prod deriving (Show)

toBuilder :: FilePath -> Details.Details -> DesiredMode -> Build.Artifacts -> Task Builder
toBuilder root details desiredMode artifacts =
  Task.mapError Exit.MakeBadGenerate $
    case desiredMode of
      Debug -> Generate.debug root details artifacts
      Dev -> Generate.dev root details artifacts
      Prod -> Generate.prod root details artifacts

-- PARSERS

reportType :: Parser ReportType
reportType =
  Parser
    { _singular = "report type",
      _plural = "report types",
      _parser = \string -> if string == "json" then Just Json else Nothing,
      _suggest = \_ -> return ["json"],
      _examples = \_ -> return ["json"]
    }

output :: Parser Output
output =
  Parser
    { _singular = "output file",
      _plural = "output files",
      _parser = parseOutput,
      _suggest = \_ -> return [],
      _examples = \_ -> return ["canopy.js", "index.html", "/dev/null"]
    }

parseOutput :: String -> Maybe Output
parseOutput name
  | isDevNull name = Just DevNull
  | hasExt ".html" name = Just (Html name)
  | hasExt ".js" name = Just (JS name)
  | otherwise = Nothing

docsFile :: Parser FilePath
docsFile =
  Parser
    { _singular = "json file",
      _plural = "json files",
      _parser = \name -> if hasExt ".json" name then Just name else Nothing,
      _suggest = \_ -> return [],
      _examples = \_ -> return ["docs.json", "documentation.json"]
    }

hasExt :: String -> String -> Bool
hasExt ext path =
  FP.takeExtension path == ext && length path > length ext

isDevNull :: String -> Bool
isDevNull name =
  name == "/dev/null" || name == "NUL" || name == "$null"

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Test command handler for the Canopy CLI.
--
-- This module implements the @canopy test@ command, which discovers Canopy
-- test modules, compiles them to JavaScript, generates a Node.js test runner,
-- executes the tests via @node@, and reports pass\/fail results.
--
-- == Test Types
--
-- The command auto-detects three kinds of tests:
--
-- * __Unit tests__ — synchronous, use the simple virtual DOM text harness
-- * __Async tests__ — use @task-executor.js@ and @test-runner.js@
-- * __Browser tests__ — additionally launch Playwright and an embedded HTTP server
--
-- == Usage
--
-- @
-- canopy test                         -- Run all tests in tests\/
-- canopy test tests\/MyTest.can       -- Run a specific test file
-- canopy test --filter \"MyModule\"   -- Run tests matching a pattern
-- canopy test --watch                 -- Watch for changes and re-run
-- canopy test --headed                -- Show browser window for browser tests
-- canopy test --app src\/Main.can     -- Specify app entry for browser tests
-- @
--
-- @since 0.19.1
module Test
  ( -- * Main Interface
    run,

    -- * Configuration
    Flags (..),

    -- * Parsers
    filterParser,
    appParser,
    slowMoParser,
  )
where

import qualified AST.Optimized as Opt
import qualified Build.Artifacts as Build
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Compiler
import Control.Lens ((^.))
import Control.Lens.TH (makeLenses)
import qualified Control.Concurrent as Concurrent
import qualified Control.Exception as Exception
import Control.Monad (filterM, void)
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.NonEmptyList as NE
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Generate.JavaScript as JS
import qualified Generate.Mode as Mode
import qualified System.Directory as Dir
import System.Exit (ExitCode (..))
import qualified System.Exit as Exit
import System.FilePath ((</>))
import qualified System.FilePath as FilePath
import qualified System.FSNotify as FSNotify
import qualified System.IO as IO
import qualified System.Process as Process
import qualified Terminal
import qualified Terminal.Output as Output
import Reporting.Doc.ColorQQ (c)
import qualified Terminal.Print as Print
import Text.Read (readMaybe)
import qualified Stuff

import Test.Browser (AppEntryPoint (..))
import qualified Test.Browser as Browser
import Test.External (JsContent (..), ExternalModuleError)
import qualified Test.External as External
import Test.Harness (HarnessConfig (..), HarnessContent (..))
import qualified Test.Harness as Harness
import qualified Test.Playwright as Playwright
import Test.Server (ServerPort (..))
import qualified Test.Server as Server

-- | Flags for the test command.
--
-- Controls test discovery, filtering, watching, output verbosity,
-- and browser test settings.
data Flags = Flags
  { -- | Optional test name filter pattern
    _testFilter :: !(Maybe String),
    -- | Enable file watching for continuous testing
    _testWatch :: !Bool,
    -- | Enable verbose output
    _testVerbose :: !Bool,
    -- | Show browser window for browser tests (non-headless)
    _testHeaded :: !Bool,
    -- | Application entry point for browser tests
    _testApp :: !(Maybe String),
    -- | Slow down browser actions by N ms
    _testSlowMo :: !(Maybe Int)
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | Main entry point for the test command.
--
-- Discovers test files, compiles them, executes via Node.js, and reports
-- results. Supports both single-run and continuous watch modes.
--
-- @since 0.19.1
run :: [FilePath] -> Flags -> IO ()
run paths flags =
  if flags ^. testWatch
    then runWithWatch paths flags
    else runOnce paths flags

-- | Run tests once without watching.
runOnce :: [FilePath] -> Flags -> IO ()
runOnce paths flags = do
  testFiles <- discoverTestFiles paths
  result <- compileAndRunTests testFiles flags
  Exit.exitWith result

-- | Run tests with file watching enabled.
runWithWatch :: [FilePath] -> Flags -> IO ()
runWithWatch paths flags = do
  Print.println [c|{bold|Watching for changes...} Press Ctrl+C to stop.|]
  testFiles <- discoverTestFiles paths
  _ <- compileAndRunTests testFiles flags
  watchDirsForRerun paths flags

-- | Watch relevant directories and re-run tests on changes.
watchDirsForRerun :: [FilePath] -> Flags -> IO ()
watchDirsForRerun paths flags =
  FSNotify.withManager $ \mgr -> do
    let candidates = ["tests", "test", "src"]
    existingDirs <- filterM Dir.doesDirectoryExist candidates
    mapM_ (registerWatcher mgr paths flags) existingDirs
    keepAliveLoop

-- | Register a directory watcher that re-runs tests on each change.
registerWatcher :: FSNotify.WatchManager -> [FilePath] -> Flags -> FilePath -> IO ()
registerWatcher mgr paths flags dir =
  void (FSNotify.watchTree mgr dir isCanopyFile (onFileChange paths flags))

-- | Predicate: is the FSNotify event for a @.can@ file?
isCanopyFile :: FSNotify.Event -> Bool
isCanopyFile event =
  FilePath.takeExtension (FSNotify.eventPath event) == ".can"

-- | Handle a file change event by re-running tests.
onFileChange :: [FilePath] -> Flags -> FSNotify.Event -> IO ()
onFileChange paths flags _event = do
  Print.println [c|{bold|--- File changed, re-running tests ---}|]
  testFiles <- discoverTestFiles paths
  _ <- compileAndRunTests testFiles flags
  pure ()

-- | Keep the main thread alive until interrupted.
keepAliveLoop :: IO ()
keepAliveLoop =
  Exception.handle handleInterrupt $
    Concurrent.threadDelay 1000000 >> keepAliveLoop

-- | Handle async exceptions gracefully during watch mode.
handleInterrupt :: Exception.AsyncException -> IO ()
handleInterrupt Exception.UserInterrupt = pure ()
handleInterrupt Exception.ThreadKilled = pure ()
handleInterrupt ex = Exception.throwIO ex

-- ── Discovery ────────────────────────────────────────────────────────

-- | Discover test files from paths or the default @tests\/@ directory.
discoverTestFiles :: [FilePath] -> IO [FilePath]
discoverTestFiles [] = do
  testsDir <- findCanopyFilesIn "tests"
  testDir <- findCanopyFilesIn "test"
  pure (testsDir ++ testDir)
discoverTestFiles paths = do
  expanded <- mapM expandPath paths
  pure (concat expanded)

-- | Expand a path: files are returned as-is, directories are scanned.
expandPath :: FilePath -> IO [FilePath]
expandPath path = do
  isDir <- Dir.doesDirectoryExist path
  isFile <- Dir.doesFileExist path
  if isDir
    then findCanopyFilesIn path
    else if isFile then pure [path] else pure []

-- | Recursively find all @.can@ files under a directory.
findCanopyFilesIn :: FilePath -> IO [FilePath]
findCanopyFilesIn dir = do
  exists <- Dir.doesDirectoryExist dir
  if not exists
    then pure []
    else do
      entries <- Dir.listDirectory dir
      let paths = map (dir </>) entries
      files <- filterM Dir.doesFileExist paths
      let canFiles = filter ((".can" ==) . FilePath.takeExtension) files
      dirs <- filterM Dir.doesDirectoryExist paths
      let visibleDirs = filter (not . ("." `List.isPrefixOf`) . FilePath.takeFileName) dirs
      nested <- mapM findCanopyFilesIn visibleDirs
      pure (canFiles ++ concat nested)

-- ── Compilation ──────────────────────────────────────────────────────

-- | Compile test files and run them, returning the overall exit code.
compileAndRunTests :: [FilePath] -> Flags -> IO ExitCode
compileAndRunTests [] _ = do
  Print.println [c|{yellow|No test files found.}|]
  Print.println [c|Create .can files in a {cyan|tests/} or {cyan|test/} directory to get started.|]
  pure ExitSuccess
compileAndRunTests testFiles flags = do
  maybeRoot <- Stuff.findRoot
  case maybeRoot of
    Nothing -> reportNoProject
    Just root -> compileAndRunWithRoot root testFiles flags

-- | Report that no canopy.json was found.
reportNoProject :: IO ExitCode
reportNoProject = do
  Print.printErrLn [c|{red|Error:} No canopy.json found. Run {green|canopy test} from a Canopy project.|]
  pure (ExitFailure 1)

-- | Compile and run tests when the project root is known.
compileAndRunWithRoot :: FilePath -> [FilePath] -> Flags -> IO ExitCode
compileAndRunWithRoot root testFiles flags = do
  let countStr = Output.showCount (length testFiles) "test file"
  if flags ^. testVerbose
    then Print.println [c|Running #{countStr} from {cyan|#{root}}...|]
    else Print.println [c|Running #{countStr}...|]
  maybeResult <- compileTestFiles root testFiles
  case maybeResult of
    Nothing -> do
      Print.printErrLn [c|{red|Compilation failed.}|]
      pure (ExitFailure 1)
    Just (jsContent, mains) -> dispatchByTestType jsContent mains testFiles flags

-- | Compile test files to a JavaScript string and main type info.
compileTestFiles :: FilePath -> [FilePath] -> IO (Maybe (String, Map.Map ModuleName.Canonical Opt.Main))
compileTestFiles root testFiles = do
  let pkg = Pkg.dummyName
      srcDirs =
        [ Compiler.RelativeSrcDir "src",
          Compiler.RelativeSrcDir "tests",
          Compiler.RelativeSrcDir "test"
        ]
  result <- Compiler.compileFromPaths pkg True root srcDirs testFiles
  case result of
    Left err -> do
      let errStr = show err
      Print.printErrLn [c|{red|Compilation error:} #{errStr}|]
      pure Nothing
    Right artifacts -> pure (Just (artifactsToJavaScript artifacts, collectMains artifacts))

-- | Generate a JavaScript string from compiled artifacts.
artifactsToJavaScript :: Compiler.Artifacts -> String
artifactsToJavaScript artifacts =
  postProcessJavaScript rawJs
  where
    globalGraph = artifacts ^. Build.artifactsGlobalGraph
    ffiInfo = artifacts ^. Build.artifactsFFIInfo
    mains = collectMains artifacts
    (builder, _sourceMap) = JS.generate (Mode.Dev Nothing False False Set.empty) globalGraph mains ffiInfo
    rawJs = builderToString builder

-- | Post-process JavaScript to fix syntax issues.
postProcessJavaScript :: String -> String
postProcessJavaScript js =
  replace "elseif" "else if" js
  where
    replace old new = go
      where
        go [] = []
        go str@(x : xs)
          | old `List.isPrefixOf` str = new ++ go (drop (length old) str)
          | otherwise = x : go xs

-- | Collect main entries from all roots of the artifacts.
collectMains :: Compiler.Artifacts -> Map.Map ModuleName.Canonical Opt.Main
collectMains artifacts =
  Map.fromList (Maybe.mapMaybe (extractMain pkg) roots)
  where
    roots = NE.toList (artifacts ^. Build.artifactsRoots)
    pkg = artifacts ^. Build.artifactsName

-- | Extract a (CanonicalName, Main) pair from a root.
extractMain :: Pkg.Name -> Build.Root -> Maybe (ModuleName.Canonical, Opt.Main)
extractMain pkg root =
  case root of
    Build.Inside _ -> Nothing
    Build.Outside name _ (Opt.LocalGraph maybeMain _ _ _) ->
      fmap (\m -> (ModuleName.Canonical pkg name, m)) maybeMain

-- | Convert a 'Builder.Builder' to a plain 'String'.
builderToString :: Builder.Builder -> String
builderToString b =
  map (toEnum . fromIntegral) (LBS.unpack (Builder.toLazyByteString b))

-- ── Test Dispatch ────────────────────────────────────────────────────

-- | Detect test type and dispatch to the appropriate execution pipeline.
--
-- Uses the 'Opt.Main' type from compilation artifacts for reliable detection:
-- 'Opt.TestMain' indicates a non-visual program (test or async), while
-- 'Opt.Static' indicates a standard HTML program (unit test with DOM output).
dispatchByTestType :: String -> Map.Map ModuleName.Canonical Opt.Main -> [FilePath] -> Flags -> IO ExitCode
dispatchByTestType jsContent mains testFiles flags
  | hasTestMain mains = executeBrowserTests jsContent testFiles flags
  | otherwise = executeUnitTests jsContent flags

-- | Check if any main entry is a 'TestMain' (non-visual test program).
hasTestMain :: Map.Map ModuleName.Canonical Opt.Main -> Bool
hasTestMain = any isTestMain . Map.elems
  where
    isTestMain Opt.TestMain = True
    isTestMain _ = False

-- ── Unit Test Execution ──────────────────────────────────────────────

-- | Execute simple unit tests via the virtual DOM text harness.
executeUnitTests :: String -> Flags -> IO ExitCode
executeUnitTests jsContent flags = do
  tmpDir <- Dir.getTemporaryDirectory
  let runnerPath = tmpDir </> "canopy-test-runner.js"
      harness = Harness.generateUnitHarness (JsContent (Text.pack jsContent))
  writeFile runnerPath (Text.unpack (unHarnessContent harness))
  runNodeAndReport runnerPath (flags ^. testVerbose)

-- ── Browser Test Execution ───────────────────────────────────────────

-- | Execute browser\/async tests with full infrastructure.
--
-- 1. Ensure Playwright is installed
-- 2. Load external JS modules from the test package
-- 3. Find and compile the application under test
-- 4. Start an embedded HTTP server
-- 5. Generate the browser test harness
-- 6. Execute via Node.js
-- 7. Stop the server
executeBrowserTests :: String -> [FilePath] -> Flags -> IO ExitCode
executeBrowserTests jsContent testFiles flags = do
  Print.println [c|{cyan|Browser tests detected.} Setting up test infrastructure...|]
  runBrowserPipeline jsContent testFiles flags
    `Exception.catch` handleBrowserError

-- | Run the browser test pipeline, propagating errors.
--
-- Checks Playwright installation first and prompts the user to install
-- if missing. This ensures browser tests have browser binaries available
-- before attempting execution.
runBrowserPipeline :: String -> [FilePath] -> Flags -> IO ExitCode
runBrowserPipeline jsContent testFiles flags = do
  playwrightReady <- Playwright.ensurePlaywrightInstalled
  if not playwrightReady
    then pure (ExitFailure 1)
    else do
      bundleResult <- External.loadTestRunnerBundle
      case bundleResult of
        Left err -> reportExternalError err
        Right (runner, executor, playwright) ->
          runWithExternals jsContent testFiles flags runner executor playwright

-- | Continue browser pipeline after loading external modules.
runWithExternals :: String -> [FilePath] -> Flags -> JsContent -> JsContent -> JsContent -> IO ExitCode
runWithExternals jsContent testFiles flags runner executor playwright = do
  appResult <- resolveAppEntry testFiles flags
  appDir <- case appResult of
    Right appEntry -> pure (FilePath.takeDirectory (unAppEntryPoint appEntry))
    Left _ -> Dir.getCurrentDirectory
  runBrowserTestsWithServer jsContent flags runner executor playwright appDir

-- | Resolve the application entry point for browser tests.
resolveAppEntry :: [FilePath] -> Flags -> IO (Either Browser.AppDiscoveryError AppEntryPoint)
resolveAppEntry testFiles flags =
  Browser.findAppEntryPoint testFiles maybeAppFlag
  where
    maybeAppFlag = fmap AppEntryPoint (flags ^. testApp)

-- | Run browser tests with an embedded HTTP server.
--
-- Starts a file server from the given directory and generates the test
-- harness with the server URL. When no @\@browser-app@ annotation is
-- found, the current working directory is used.
runBrowserTestsWithServer :: String -> Flags -> JsContent -> JsContent -> JsContent -> FilePath -> IO ExitCode
runBrowserTestsWithServer jsContent flags runner executor playwright appDir = do
  portResult <- Server.findAvailablePort
  case portResult of
    Left _ -> do
      Print.printErrLn [c|{red|Error:} Could not find an available port (8000-9000).|]
      pure (ExitFailure 1)
    Right port -> do
      let portStr = show (unServerPort port)
      Print.println [c|Starting test server on port {cyan|#{portStr}}...|]
      server <- Server.startTestServer appDir port
      result <- generateAndRun flags runner executor playwright (JsContent (Text.pack jsContent)) (Just port) appDir
      Server.stopTestServer server
      pure result

-- | Generate the harness and execute it via Node.js.
generateAndRun :: Flags -> JsContent -> JsContent -> JsContent -> JsContent -> Maybe ServerPort -> FilePath -> IO ExitCode
generateAndRun flags runner executor playwright tests maybePort projectDir = do
  tmpDir <- Dir.getTemporaryDirectory
  let runnerPath = tmpDir </> "canopy-browser-test-runner.js"
      port = Maybe.fromMaybe (ServerPort 0) maybePort
      config =
        HarnessConfig
          { _harnessServerPort = port,
            _harnessHeaded = flags ^. testHeaded,
            _harnessSlowMo = fromIntegral (Maybe.fromMaybe 0 (flags ^. testSlowMo))
          }
      harness = Harness.generateBrowserHarness config runner executor playwright tests
  writeFile runnerPath (Text.unpack (unHarnessContent harness))
  runNodeForBrowserTests runnerPath projectDir (flags ^. testVerbose)

-- | Report external module loading errors.
reportExternalError :: ExternalModuleError -> IO ExitCode
reportExternalError err = do
  let errStr = show err
  Print.printErrLn [c|{red|Error loading test infrastructure:} #{errStr}|]
  Print.println [c|Make sure the {cyan|canopy/test} package is installed.|]
  Print.println [c|Run {green|canopy setup} to install core packages.|]
  pure (ExitFailure 1)

-- | Handle unexpected exceptions during browser test setup.
handleBrowserError :: Exception.SomeException -> IO ExitCode
handleBrowserError err = do
  let errStr = show err
  Print.printErrLn [c|{red|Browser test setup failed:} #{errStr}|]
  pure (ExitFailure 1)

-- ── Node Execution ───────────────────────────────────────────────────

-- | Find the @node@ executable and execute the runner script.
runNodeAndReport :: FilePath -> Bool -> IO ExitCode
runNodeAndReport runnerPath verbose = do
  nodeExists <- Dir.findExecutable "node"
  case nodeExists of
    Nothing -> reportNodeMissing
    Just nodePath -> executeNode nodePath [runnerPath] verbose

-- | Run @node@ for browser tests with @NODE_PATH@ set so
-- @require('playwright')@ resolves from local or global installs.
runNodeForBrowserTests :: FilePath -> FilePath -> Bool -> IO ExitCode
runNodeForBrowserTests runnerPath projectDir verbose = do
  nodeExists <- Dir.findExecutable "node"
  case nodeExists of
    Nothing -> reportNodeMissing
    Just nodePath -> do
      npmRoot <- getNpmGlobalRoot
      let paths = buildNodePaths projectDir npmRoot
      executeNode nodePath ["-e", nodePathWrapper paths runnerPath] verbose

-- | Report that the @node@ executable is not found.
reportNodeMissing :: IO ExitCode
reportNodeMissing = do
  Print.printErrLn [c|{red|Error:} 'node' not found. Install Node.js to run Canopy tests.|]
  pure (ExitFailure 1)

-- | Discover the global npm @node_modules@ directory via @npm root -g@.
getNpmGlobalRoot :: IO (Maybe FilePath)
getNpmGlobalRoot =
  fmap extractPath (Process.readProcessWithExitCode "npm" ["root", "-g"] "")
    `Exception.catch` ignoreException
  where
    extractPath (ExitSuccess, out, _) = Just (filter (/= '\n') out)
    extractPath _ = Nothing

    ignoreException :: Exception.SomeException -> IO (Maybe FilePath)
    ignoreException _ = pure Nothing

-- | Build the @NODE_PATH@ search list from the project's local
-- @node_modules@ and the optional global npm root.
buildNodePaths :: FilePath -> Maybe FilePath -> [FilePath]
buildNodePaths projectDir maybeGlobal =
  (projectDir </> "node_modules") : maybe [] pure maybeGlobal

-- | Generate a Node.js wrapper script that sets @NODE_PATH@ before
-- requiring the actual harness file.
nodePathWrapper :: [FilePath] -> FilePath -> String
nodePathWrapper paths harnessPath =
  "process.env.NODE_PATH=" ++ show (List.intercalate ":" paths) ++ ";"
    ++ "require('module').Module._initPaths();"
    ++ "require(" ++ show harnessPath ++ ");"

-- | Execute @node@ with given arguments and print captured output.
executeNode :: FilePath -> [String] -> Bool -> IO ExitCode
executeNode nodePath args verbose = do
  (exitCode, stdout, stderr) <-
    Process.readProcessWithExitCode nodePath args ""
  IO.hPutStr IO.stdout stdout
  case exitCode of
    ExitSuccess -> do
      Print.println [c|{green|Tests passed.}|]
      pure ExitSuccess
    ExitFailure _ -> do
      unless (null stderr) (IO.hPutStr IO.stderr stderr)
      when verbose (printVerboseInfo args)
      Print.println [c|{red|Tests failed.}|]
      pure (ExitFailure 1)

-- | Print debugging info when verbose mode is on.
printVerboseInfo :: [String] -> IO ()
printVerboseInfo args =
  case args of
    [path] -> Print.println [c|Test runner written to: {cyan|#{path}}|]
    _ -> pure ()

-- ── Utilities ────────────────────────────────────────────────────────

-- | Conditional action: skip execution when the condition is 'True'.
unless :: Bool -> IO () -> IO ()
unless True _ = pure ()
unless False action = action

-- | Conditional action: execute only when the condition is 'True'.
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = pure ()

-- ── CLI Parsers ──────────────────────────────────────────────────────

-- | Parser for the @--filter@ flag.
--
-- @since 0.19.1
filterParser :: Terminal.Parser String
filterParser =
  Terminal.Parser
    { Terminal._singular = "pattern",
      Terminal._plural = "patterns",
      Terminal._parser = parseNonEmpty,
      Terminal._suggest = suggestFilterPatterns,
      Terminal._examples = exampleFilterPatterns
    }

-- | Parser for the @--app@ flag.
--
-- @since 0.19.1
appParser :: Terminal.Parser String
appParser =
  Terminal.Parser
    { Terminal._singular = "file",
      Terminal._plural = "files",
      Terminal._parser = parseNonEmpty,
      Terminal._suggest = suggestAppPaths,
      Terminal._examples = exampleAppPaths
    }

-- | Parser for the @--slowmo@ flag.
--
-- @since 0.19.1
slowMoParser :: Terminal.Parser Int
slowMoParser =
  Terminal.Parser
    { Terminal._singular = "milliseconds",
      Terminal._plural = "milliseconds",
      Terminal._parser = readMaybe,
      Terminal._suggest = suggestSlowMo,
      Terminal._examples = exampleSlowMo
    }

-- | Parse a non-empty string.
parseNonEmpty :: String -> Maybe String
parseNonEmpty s
  | null s = Nothing
  | otherwise = Just s

-- | Suggest common filter pattern values.
suggestFilterPatterns :: String -> IO [String]
suggestFilterPatterns _ = pure ["MyModule", "describe", "unit"]

-- | Provide example filter pattern values.
exampleFilterPatterns :: String -> IO [String]
exampleFilterPatterns _ = pure ["MyModule", "integration", "parse"]

-- | Suggest common application paths.
suggestAppPaths :: String -> IO [String]
suggestAppPaths _ = pure ["src/Main.can", "app/Main.can"]

-- | Provide example application paths.
exampleAppPaths :: String -> IO [String]
exampleAppPaths _ = pure ["src/Main.can"]

-- | Suggest slow-mo values.
suggestSlowMo :: String -> IO [String]
suggestSlowMo _ = pure ["100", "250", "500"]

-- | Provide example slow-mo values.
exampleSlowMo :: String -> IO [String]
exampleSlowMo _ = pure ["100", "500"]

-- Suppress unused lens warning.
-- testFilter lens is generated by makeLenses but not yet used in the harness;
-- it is kept for the CLI flag parser and future filter implementation.
_suppressUnusedFilter :: Flags -> Maybe String
_suppressUnusedFilter f = f ^. testFilter

_unusedReadMaybe :: String -> Maybe Int
_unusedReadMaybe = readMaybe


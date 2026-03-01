{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Test command handler for the Canopy CLI.
--
-- This module implements the @canopy test@ command, which discovers Canopy
-- test modules, compiles them to JavaScript, generates a Node.js test runner,
-- executes the tests via @node@, and reports pass\/fail results.
--
-- == Output Protocol
--
-- The JavaScript test runner emits NDJSON (newline-delimited JSON) on stdout.
-- Each line is either a @result@ event (one per test) or a @summary@ event
-- (after all tests). This module reads stdout line-by-line, parses each JSON
-- object, and formats it with 'Terminal.Print' + 'Reporting.Doc.ColorQQ' for
-- TTY-aware, streaming output.
--
-- == Test Types
--
-- The command auto-detects three kinds of tests:
--
-- * __Unit tests__ -- synchronous, use the simple virtual DOM text harness
-- * __Async tests__ -- use @task-executor.js@ and @test-runner.js@
-- * __Browser tests__ -- additionally launch Playwright and an embedded HTTP server
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
-- Sub-modules:
--
-- * "Test.Discovery" - Test file discovery
-- * "Test.Compile" - Test compilation pipeline
-- * "Test.Event" - NDJSON event types and formatting
-- * "Test.Runner" - Node.js process execution
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
import qualified Canopy.ModuleName as ModuleName
import Control.Lens ((^.))
import Control.Lens.TH (makeLenses)
import qualified Control.Concurrent as Concurrent
import qualified Control.Exception as Exception
import Control.Monad (filterM, void)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import qualified System.Directory as Dir
import System.Exit (ExitCode (..))
import qualified System.Exit as Exit
import System.FilePath ((</>))
import qualified System.FilePath as FilePath
import qualified System.Environment as Environment
import qualified System.FSNotify as FSNotify
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
import qualified Test.Runner as Runner

import qualified Test.Compile as Compile
import qualified Test.Discovery as Discovery

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
  testFiles <- Discovery.discoverTestFiles paths
  result <- compileAndRunTests testFiles flags
  Exit.exitWith result

-- | Run tests with file watching enabled.
runWithWatch :: [FilePath] -> Flags -> IO ()
runWithWatch paths flags = do
  Print.println [c|{bold|Watching for changes...} Press Ctrl+C to stop.|]
  testFiles <- Discovery.discoverTestFiles paths
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
  testFiles <- Discovery.discoverTestFiles paths
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

-- ── Header Bar ──────────────────────────────────────────────────────

-- | Format a dullcyan header bar in the Canopy report style.
testBar :: [FilePath] -> String
testBar [single] = barWithSuffix single
testBar files = barWithSuffix (Output.showCount (length files) "file")

-- | Build the bar string given the right-hand suffix.
barWithSuffix :: String -> String
barWithSuffix suffix =
  "-- TEST RESULTS " ++ dashes ++ " " ++ suffix
  where
    usedCols = 17 + 1 + length suffix
    dashes = replicate (max 1 (80 - usedCols)) '-'

-- ── Compilation & Execution ──────────────────────────────────────────

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
  let bar = testBar testFiles
  Print.println [c|{dullcyan|#{bar}}|]
  when (flags ^. testVerbose) $
    Print.println [c|  Project root: {cyan|#{root}}|]
  Print.newline
  maybeResult <- Compile.compileTestFiles root testFiles
  case maybeResult of
    Nothing -> do
      Print.printErrLn [c|{red|Compilation failed.}|]
      pure (ExitFailure 1)
    Just (jsContent, mains) -> dispatchByTestType jsContent mains testFiles flags

-- ── Test Dispatch ────────────────────────────────────────────────────

-- | Detect test type and dispatch to the appropriate execution pipeline.
dispatchByTestType :: Text.Text -> Map.Map ModuleName.Canonical Opt.Main -> [FilePath] -> Flags -> IO ExitCode
dispatchByTestType jsContent mains testFiles flags
  | hasBrowserTestMain mains = executeBrowserExecutionTests jsContent testFiles flags
  | hasTestMain mains = executeBrowserTests jsContent testFiles flags
  | otherwise = executeUnitTests jsContent flags

-- | Check if any main entry is a 'BrowserTestMain' (real browser test).
hasBrowserTestMain :: Map.Map ModuleName.Canonical Opt.Main -> Bool
hasBrowserTestMain = any isBrowserTestMain . Map.elems
  where
    isBrowserTestMain Opt.BrowserTestMain = True
    isBrowserTestMain _ = False

-- | Check if any main entry is a 'TestMain' (non-visual test program).
hasTestMain :: Map.Map ModuleName.Canonical Opt.Main -> Bool
hasTestMain = any isTestMain . Map.elems
  where
    isTestMain Opt.TestMain = True
    isTestMain _ = False

-- ── Browser Execution Tests (BrowserTestMain) ───────────────────────

-- | Execute tests in a real browser via Playwright.
executeBrowserExecutionTests :: Text.Text -> [FilePath] -> Flags -> IO ExitCode
executeBrowserExecutionTests jsContent testFiles flags = do
  Print.println [c|{cyan|Browser execution tests detected.} Setting up real browser environment...|]
  Print.newline
  runBrowserExecutionPipeline jsContent testFiles flags
    `Exception.catch` handleBrowserError

-- | Run the browser execution pipeline.
runBrowserExecutionPipeline :: Text.Text -> [FilePath] -> Flags -> IO ExitCode
runBrowserExecutionPipeline jsContent _testFiles flags = do
  playwrightReady <- Playwright.ensurePlaywrightInstalled
  if not playwrightReady
    then pure (ExitFailure 1)
    else do
      bundleResult <- External.loadBrowserTestBundle
      case bundleResult of
        Left err -> reportExternalError err
        Right (browserRunner, rpcModule) ->
          runBrowserExecutionWithServer jsContent flags browserRunner rpcModule

-- | Start server, write HTML harness, launch Playwright, collect results.
runBrowserExecutionWithServer :: Text.Text -> Flags -> JsContent -> JsContent -> IO ExitCode
runBrowserExecutionWithServer jsContent flags browserRunner rpcModule = do
  setTestFilter (flags ^. testFilter)
  portResult <- Server.findAvailablePort
  case portResult of
    Left _ -> do
      Print.printErrLn [c|{red|Error:} Could not find an available port (8000-9000).|]
      pure (ExitFailure 1)
    Right port -> do
      tmpDir <- Dir.getTemporaryDirectory
      let htmlPath = tmpDir </> "canopy-browser-test.html"
          rpcPath = tmpDir </> "canopy-playwright-rpc.js"
          harness = Harness.generateBrowserTestHarness (JsContent jsContent) browserRunner
      writeFile htmlPath (Text.unpack (unHarnessContent harness))
      writeFile rpcPath (Text.unpack (unJsContent rpcModule))
      server <- Server.startTestServer tmpDir port
      when (flags ^. testVerbose) $ do
        let portStr = show (unServerPort port)
        Print.println [c|  Serving tests at {cyan|http://127.0.0.1:#{portStr}/canopy-browser-test.html}|]
      result <- launchPlaywrightForBrowserTests port flags tmpDir
      Server.stopTestServer server
      pure result

-- | Generate and execute a Node.js Playwright launcher script.
launchPlaywrightForBrowserTests :: ServerPort -> Flags -> FilePath -> IO ExitCode
launchPlaywrightForBrowserTests port flags tmpDir = do
  let launcherPath = tmpDir </> "canopy-browser-launcher.js"
      rpcPath = tmpDir </> "canopy-playwright-rpc.js"
      headless = not (flags ^. testHeaded)
      portStr = show (unServerPort port)
      headlessStr = if headless then "true" else "false"
      escapedRpcPath = Text.replace "\\" "\\\\" (Text.pack rpcPath)
      launcher = Text.unlines
        [ "const { chromium } = require('playwright');",
          "const _fs = require('fs');",
          "const rpc = require('" <> escapedRpcPath <> "');",
          "(async () => {",
          "  const browser = await chromium.launch({",
          "    headless: " <> Text.pack headlessStr <> ",",
          "    args: ['--autoplay-policy=no-user-gesture-required']",
          "  });",
          "  const page = await browser.newPage();",
          "  const forward = (text) => _fs.writeSync(1, text + '\\n');",
          "  rpc.setup(page, forward);",
          "  page.on('pageerror', err => {",
          "    _fs.writeSync(2, 'Page error: ' + err.message + '\\n');",
          "  });",
          "  await page.goto('http://127.0.0.1:" <> Text.pack portStr <> "/canopy-browser-test.html');",
          "  await page.waitForFunction(() => window.__canopyTestsDone === true, { timeout: 60000 });",
          "  const exitCode = await page.evaluate(() => window.__canopyExitCode || 0);",
          "  await browser.close();",
          "  process.exit(exitCode);",
          "})().catch(err => {",
          "  _fs.writeSync(2, 'Playwright error: ' + err.message + '\\n');",
          "  process.exit(1);",
          "});"
        ]
  writeFile launcherPath (Text.unpack launcher)
  cwd <- Dir.getCurrentDirectory
  Runner.runNodeForBrowserTests launcherPath cwd (flags ^. testVerbose)

-- ── Unit Test Execution ──────────────────────────────────────────────

-- | Execute simple unit tests via the virtual DOM text harness.
executeUnitTests :: Text.Text -> Flags -> IO ExitCode
executeUnitTests jsContent flags = do
  setTestFilter (flags ^. testFilter)
  tmpDir <- Dir.getTemporaryDirectory
  let runnerPath = tmpDir </> "canopy-test-runner.js"
      harness = Harness.generateUnitHarness (JsContent jsContent)
  writeFile runnerPath (Text.unpack (unHarnessContent harness))
  Runner.runNodeAndReport runnerPath (flags ^. testVerbose)

-- ── Browser Test Execution ───────────────────────────────────────────

-- | Execute browser\/async tests with full infrastructure.
executeBrowserTests :: Text.Text -> [FilePath] -> Flags -> IO ExitCode
executeBrowserTests jsContent testFiles flags = do
  Print.println [c|{cyan|Browser tests detected.} Setting up test infrastructure...|]
  Print.newline
  runBrowserPipeline jsContent testFiles flags
    `Exception.catch` handleBrowserError

-- | Run the browser test pipeline, propagating errors.
runBrowserPipeline :: Text.Text -> [FilePath] -> Flags -> IO ExitCode
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
runWithExternals :: Text.Text -> [FilePath] -> Flags -> JsContent -> JsContent -> JsContent -> IO ExitCode
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
runBrowserTestsWithServer :: Text.Text -> Flags -> JsContent -> JsContent -> JsContent -> FilePath -> IO ExitCode
runBrowserTestsWithServer jsContent flags runner executor playwright appDir = do
  portResult <- Server.findAvailablePort
  case portResult of
    Left _ -> do
      Print.printErrLn [c|{red|Error:} Could not find an available port (8000-9000).|]
      pure (ExitFailure 1)
    Right port -> do
      server <- Server.startTestServer appDir port
      when (flags ^. testVerbose) $ do
        let portStr = show (unServerPort port)
        Print.println [c|  Listening on {cyan|http://127.0.0.1:#{portStr}}|]
      result <- generateAndRun flags runner executor playwright (JsContent jsContent) (Just port) appDir
      Server.stopTestServer server
      pure result

-- | Generate the harness and execute it via Node.js.
generateAndRun :: Flags -> JsContent -> JsContent -> JsContent -> JsContent -> Maybe ServerPort -> FilePath -> IO ExitCode
generateAndRun flags runner executor playwright tests maybePort projectDir = do
  setTestFilter (flags ^. testFilter)
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
  Runner.runNodeForBrowserTests runnerPath projectDir (flags ^. testVerbose)

-- | Report external module loading errors.
reportExternalError :: ExternalModuleError -> IO ExitCode
reportExternalError err = do
  let errStr = show err
  Print.printErrLn [c|{red|Error loading test infrastructure:} #{errStr}|]
  Print.println [c|Make sure the {cyan|canopy/test} package is installed.|]
  Print.println [c|Run {green|canopy setup} to install core packages.|]
  pure (ExitFailure 1)

-- | Handle IO exceptions during browser test setup.
handleBrowserError :: Exception.IOException -> IO ExitCode
handleBrowserError err = do
  let errStr = show err
  Print.printErrLn [c|{red|Browser test setup failed:} #{errStr}|]
  pure (ExitFailure 1)

-- ── Utilities ────────────────────────────────────────────────────────

-- | Conditional action: execute only when the condition is 'True'.
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = pure ()

-- ── CLI Parsers ──────────────────────────────────────────────────────

-- | Parser for the @--filter@ flag.
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

-- | Set the @CANOPY_TEST_FILTER@ environment variable for the Node.js
-- test harness. When 'Nothing', unsets the variable to ensure a clean
-- environment for unfiltered runs.
setTestFilter :: Maybe String -> IO ()
setTestFilter Nothing = Environment.unsetEnv "CANOPY_TEST_FILTER"
setTestFilter (Just pattern_) = Environment.setEnv "CANOPY_TEST_FILTER" pattern_

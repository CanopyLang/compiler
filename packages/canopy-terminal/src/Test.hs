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
    coverageFormatParser,
    coverageOutputParser,
    minCoverageParser,
    includeDepsParser,

    -- * Coverage
    Coverage.CoverageScope (..),
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens ((^.))
import Control.Lens.TH (makeLenses)
import qualified Control.Concurrent as Concurrent
import qualified Control.Exception as Exception
import qualified Control.Monad as Monad
import Data.Aeson (Value)
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
import qualified Test.Coverage as Coverage
import qualified Data.Text.IO as TextIO
import qualified Generate.JavaScript.Coverage as CoverageMap
import Test.Harness (JsContent (..), HarnessConfig (..), HarnessContent (..))
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
    _testSlowMo :: !(Maybe Int),
    -- | Instrument code and show coverage report after tests
    _testCoverage :: !Bool,
    -- | Coverage output format: istanbul, lcov, or html
    _testCoverageFormat :: !(Maybe String),
    -- | Write coverage report to this file path
    _testCoverageOutput :: !(Maybe String),
    -- | Minimum coverage percentage required (fail if below)
    _testMinCoverage :: !(Maybe Int),
    -- | Include dependency packages in coverage analysis
    _testIncludeDeps :: !(Maybe String),
    -- | Show uncovered source locations after report
    _testShowUncovered :: !Bool
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
    existingDirs <- Monad.filterM Dir.doesDirectoryExist candidates
    mapM_ (registerWatcher mgr paths flags) existingDirs
    keepAliveLoop

-- | Register a directory watcher that re-runs tests on each change.
registerWatcher :: FSNotify.WatchManager -> [FilePath] -> Flags -> FilePath -> IO ()
registerWatcher mgr paths flags dir =
  Monad.void (FSNotify.watchTree mgr dir isCanopyFile (onFileChange paths flags))

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
  maybeResult <- Compile.compileTestFiles root testFiles (flags ^. testCoverage)
  case maybeResult of
    Nothing -> do
      Print.printErrLn [c|{red|Compilation failed.}|]
      pure (ExitFailure 1)
    Just (jsContent, mains, maybeCovMap, staleFFI, pkgName) -> do
      (exitCode, maybeCovData) <- dispatchByTestType jsContent mains testFiles flags
      let scope = parseCoverageScope (flags ^. testIncludeDeps)
      thresholdPassed <- handleCoverageOutput flags scope (Just pkgName) maybeCovMap maybeCovData
      renderUncoveredIfEnabled flags scope (Just pkgName) maybeCovMap maybeCovData
      reportStaleFFI staleFFI
      pure (if exitCode == ExitSuccess && not thresholdPassed then ExitFailure 1 else exitCode)

-- ── Test Dispatch ────────────────────────────────────────────────────

-- | Detect test type and dispatch to the appropriate execution pipeline.
--
-- Returns the exit code and any coverage data captured from the NDJSON stream.
dispatchByTestType :: Text.Text -> Map.Map ModuleName.Canonical Opt.Main -> [FilePath] -> Flags -> IO (ExitCode, Maybe Value)
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
executeBrowserExecutionTests :: Text.Text -> [FilePath] -> Flags -> IO (ExitCode, Maybe Value)
executeBrowserExecutionTests jsContent testFiles flags = do
  Print.println [c|{cyan|Browser execution tests detected.} Setting up real browser environment...|]
  Print.newline
  runBrowserExecutionPipeline jsContent testFiles flags
    `Exception.catch` handleBrowserErrorWithCov

-- | Run the browser execution pipeline.
--
-- Loads browser-test-runner.js from the package cache and injects it
-- into the HTML harness.  Also loads playwright-rpc.js (a standalone
-- Node.js launcher, not callable from Canopy).
runBrowserExecutionPipeline :: Text.Text -> [FilePath] -> Flags -> IO (ExitCode, Maybe Value)
runBrowserExecutionPipeline jsContent _testFiles flags = do
  playwrightReady <- Playwright.ensurePlaywrightInstalled
  if not playwrightReady
    then pure (ExitFailure 1, Nothing)
    else do
      rpcResult <- loadFileFromPackage "canopy" "test" ("external" </> "playwright-rpc.js")
      browserRunnerResult <- loadFileFromPackage "canopy" "test" ("external" </> "browser-test-runner.js")
      let maybeBrowserRunner = case browserRunnerResult of
            Right content -> Just (JsContent content)
            Left _ -> Nothing
      case rpcResult of
        Left err -> do
          Print.printErrLn [c|{red|Error loading playwright-rpc.js:} #{err}|]
          pure (ExitFailure 1, Nothing)
        Right rpcContent ->
          runBrowserExecutionWithServer jsContent flags (JsContent rpcContent) maybeBrowserRunner

-- | Start server, write HTML harness, launch Playwright, collect results.
runBrowserExecutionWithServer :: Text.Text -> Flags -> JsContent -> Maybe JsContent -> IO (ExitCode, Maybe Value)
runBrowserExecutionWithServer jsContent flags rpcModule maybeBrowserRunner = do
  setTestFilter (flags ^. testFilter)
  portResult <- Server.findAvailablePort
  case portResult of
    Left _ -> do
      Print.printErrLn [c|{red|Error:} Could not find an available port (8000-9000).|]
      pure (ExitFailure 1, Nothing)
    Right port -> do
      tmpDir <- Dir.getTemporaryDirectory
      let htmlPath = tmpDir </> "canopy-browser-test.html"
          rpcPath = tmpDir </> "canopy-playwright-rpc.js"
          harness = Harness.generateBrowserTestHarness (JsContent jsContent) maybeBrowserRunner
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
launchPlaywrightForBrowserTests :: ServerPort -> Flags -> FilePath -> IO (ExitCode, Maybe Value)
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
executeUnitTests :: Text.Text -> Flags -> IO (ExitCode, Maybe Value)
executeUnitTests jsContent flags = do
  setTestFilter (flags ^. testFilter)
  tmpDir <- Dir.getTemporaryDirectory
  let runnerPath = tmpDir </> "canopy-test-runner.js"
      harness = Harness.generateUnitHarness (JsContent jsContent)
  writeFile runnerPath (Text.unpack (unHarnessContent harness))
  Runner.runNodeAndReport runnerPath (flags ^. testVerbose)

-- ── Browser Test Execution ───────────────────────────────────────────

-- | Execute browser\/async tests with full infrastructure.
executeBrowserTests :: Text.Text -> [FilePath] -> Flags -> IO (ExitCode, Maybe Value)
executeBrowserTests jsContent testFiles flags = do
  Print.println [c|{cyan|Browser tests detected.} Setting up test infrastructure...|]
  Print.newline
  runBrowserPipeline jsContent testFiles flags
    `Exception.catch` handleBrowserErrorWithCov

-- | Run the browser test pipeline, propagating errors.
--
-- The compiled output already includes test-runner.js, task-executor.js,
-- and playwright.js via FFI imports. No external module loading needed.
runBrowserPipeline :: Text.Text -> [FilePath] -> Flags -> IO (ExitCode, Maybe Value)
runBrowserPipeline jsContent testFiles flags = do
  playwrightReady <- Playwright.ensurePlaywrightInstalled
  if not playwrightReady
    then pure (ExitFailure 1, Nothing)
    else do
      appResult <- resolveAppEntry testFiles flags
      appDir <- case appResult of
        Right appEntry -> pure (FilePath.takeDirectory (unAppEntryPoint appEntry))
        Left _ -> Dir.getCurrentDirectory
      runBrowserTestsWithServer jsContent flags appDir

-- | Resolve the application entry point for browser tests.
resolveAppEntry :: [FilePath] -> Flags -> IO (Either Browser.AppDiscoveryError AppEntryPoint)
resolveAppEntry testFiles flags =
  Browser.findAppEntryPoint testFiles maybeAppFlag
  where
    maybeAppFlag = fmap AppEntryPoint (flags ^. testApp)

-- | Run browser tests with an embedded HTTP server.
runBrowserTestsWithServer :: Text.Text -> Flags -> FilePath -> IO (ExitCode, Maybe Value)
runBrowserTestsWithServer jsContent flags appDir = do
  portResult <- Server.findAvailablePort
  case portResult of
    Left _ -> do
      Print.printErrLn [c|{red|Error:} Could not find an available port (8000-9000).|]
      pure (ExitFailure 1, Nothing)
    Right port -> do
      server <- Server.startTestServer appDir port
      when (flags ^. testVerbose) $ do
        let portStr = show (unServerPort port)
        Print.println [c|  Listening on {cyan|http://127.0.0.1:#{portStr}}|]
      result <- generateAndRun flags (JsContent jsContent) (Just port) appDir
      Server.stopTestServer server
      pure result

-- | Generate the harness and execute it via Node.js.
--
-- Loads @test-runner.js@ and @task-executor.js@ from the @canopy/test@
-- package cache and injects them into the harness. The test runner provides
-- @runAndReport@ (the main test execution function), and the task executor
-- provides async task execution for @asyncTest@ nodes.
generateAndRun :: Flags -> JsContent -> Maybe ServerPort -> FilePath -> IO (ExitCode, Maybe Value)
generateAndRun flags tests maybePort projectDir = do
  setTestFilter (flags ^. testFilter)
  tmpDir <- Dir.getTemporaryDirectory
  let runnerPath = tmpDir </> "canopy-browser-test-runner.js"
      taskExecPath = tmpDir </> "task-executor.js"
      port = Maybe.fromMaybe (ServerPort 0) maybePort
      config =
        HarnessConfig
          { _harnessServerPort = port,
            _harnessHeaded = flags ^. testHeaded,
            _harnessSlowMo = fromIntegral (Maybe.fromMaybe 0 (flags ^. testSlowMo))
          }
  testRunnerResult <- loadFileFromPackage "canopy" "test" ("external" </> "test-runner.js")
  let maybeRunner = case testRunnerResult of
        Right content -> Just (JsContent content)
        Left _ -> Nothing
      harness = Harness.generateBrowserHarness config tests maybeRunner
  writeFile runnerPath (Text.unpack (unHarnessContent harness))
  taskExecResult <- loadFileFromPackage "canopy" "test" ("external" </> "task-executor.js")
  case taskExecResult of
    Right content -> writeFile taskExecPath (Text.unpack content)
    Left _ -> pure ()
  Runner.runNodeForBrowserTests runnerPath projectDir (flags ^. testVerbose)

-- | Load a file from an installed package in the Canopy package cache.
--
-- Resolves the package directory via 'Stuff.getPackageCache', finds
-- the latest installed version, and reads the file. Used for loading
-- standalone JS files (like playwright-rpc.js) that cannot go through
-- the FFI import pipeline.
loadFileFromPackage :: String -> String -> FilePath -> IO (Either String Text.Text)
loadFileFromPackage author project relPath = do
  cacheDir <- Stuff.getPackageCache
  let pkgDir = cacheDir </> author </> project
  pkgExists <- Dir.doesDirectoryExist pkgDir
  if not pkgExists
    then tryElmFallback author project relPath
    else loadFromPkgDir pkgDir relPath

-- | Find the latest version directory and read the file.
loadFromPkgDir :: FilePath -> FilePath -> IO (Either String Text.Text)
loadFromPkgDir pkgDir relPath = do
  entries <- Dir.listDirectory pkgDir
  dirs <- Monad.filterM (Dir.doesDirectoryExist . (pkgDir </>)) entries
  let sorted = reverse (filter (not . ("." `isPrefixOfStr`)) dirs)
  case sorted of
    [] -> pure (Left "Package not installed")
    (latest : _) -> readFileFromDir (pkgDir </> latest </> relPath)
  where
    isPrefixOfStr prefix str = take (length prefix) str == prefix

-- | Read a single file, returning Left on missing file.
readFileFromDir :: FilePath -> IO (Either String Text.Text)
readFileFromDir path = do
  exists <- Dir.doesFileExist path
  if exists
    then fmap Right (TextIO.readFile path)
    else pure (Left ("File not found: " ++ path))

-- | Fallback to the Elm package cache.
tryElmFallback :: String -> String -> FilePath -> IO (Either String Text.Text)
tryElmFallback author project relPath = do
  homeDir <- Dir.getHomeDirectory
  let elmDir = homeDir </> ".elm" </> "0.19.1" </> "packages" </> author </> project
  elmExists <- Dir.doesDirectoryExist elmDir
  if elmExists
    then loadFromPkgDir elmDir relPath
    else pure (Left "Package not installed (checked Canopy and Elm caches)")

-- | Handle IO exceptions during browser test setup.
handleBrowserError :: Exception.IOException -> IO ExitCode
handleBrowserError err = do
  let errStr = show err
  Print.printErrLn [c|{red|Browser test setup failed:} #{errStr}|]
  pure (ExitFailure 1)

-- | Handle IO exceptions during browser test setup (with coverage data).
handleBrowserErrorWithCov :: Exception.IOException -> IO (ExitCode, Maybe Value)
handleBrowserErrorWithCov err =
  fmap (\ec -> (ec, Nothing)) (handleBrowserError err)

-- ── Utilities ────────────────────────────────────────────────────────

-- | Conditional action: execute only when the condition is 'True'.
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = pure ()

-- ── Coverage Scope Parsing ──────────────────────────────────────────

-- | Parse the @--include-deps@ flag value into a 'CoverageScope'.
--
-- * 'Nothing' -> 'CurrentOnly'
-- * @Just \"all\"@ -> 'WithAllDeps'
-- * @Just \"author\/pkg1,author\/pkg2\"@ -> 'WithSpecific [...]'
--
-- @since 0.19.2
parseCoverageScope :: Maybe String -> Coverage.CoverageScope
parseCoverageScope Nothing = Coverage.CurrentOnly
parseCoverageScope (Just "all") = Coverage.WithAllDeps
parseCoverageScope (Just s) =
  Coverage.WithSpecific (Maybe.mapMaybe parsePkgName (splitOn ',' s))

-- | Parse an @author\/project@ string into a 'Pkg.Name'.
parsePkgName :: String -> Maybe Pkg.Name
parsePkgName s =
  case break (== '/') s of
    (author, '/' : project)
      | not (null author) && not (null project) ->
          Just (Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project))
    _ -> Nothing

-- | Split a string on a delimiter character.
splitOn :: Char -> String -> [String]
splitOn _ [] = []
splitOn delim s =
  case break (== delim) s of
    (chunk, []) -> [chunk]
    (chunk, _ : rest) -> chunk : splitOn delim rest

-- ── Coverage Output ─────────────────────────────────────────────────

-- | Render and\/or write coverage reports after tests complete.
--
-- When the coverage flag is set and both a 'CoverageMap' and runtime
-- hit data are available, prints a terminal summary and optionally
-- writes an Istanbul JSON, LCOV, or HTML file.
--
-- @since 0.19.2
handleCoverageOutput :: Flags -> Coverage.CoverageScope -> Maybe Pkg.Name -> Maybe CoverageMap.CoverageMap -> Maybe Value -> IO Bool
handleCoverageOutput flags scope maybePkg maybeCovMap maybeCovData =
  case (flags ^. testCoverage, maybeCovMap, maybeCovData) of
    (True, Just covMap, Just covData) -> do
      let hits = Coverage.parseCoverageHits covData
      Coverage.renderTerminalReport scope maybePkg covMap hits
      writeCoverageFile flags covMap hits
      checkMinCoverage flags scope maybePkg covMap hits
    (True, _, Nothing) -> do
      Print.println [c|{yellow|Warning:} Coverage enabled but no coverage data received from test runner.|]
      pure True
    _ -> pure True

-- | Render uncovered locations if the @--show-uncovered@ flag is set.
--
-- @since 0.19.2
renderUncoveredIfEnabled :: Flags -> Coverage.CoverageScope -> Maybe Pkg.Name -> Maybe CoverageMap.CoverageMap -> Maybe Value -> IO ()
renderUncoveredIfEnabled flags scope maybePkg maybeCovMap maybeCovData =
  case (flags ^. testCoverage, flags ^. testShowUncovered, maybeCovMap, maybeCovData) of
    (True, True, Just covMap, Just covData) -> do
      let hits = Coverage.parseCoverageHits covData
          scopedMap = Coverage.applyCoverageScope scope maybePkg covMap
      Coverage.renderUncoveredLocations scopedMap hits
    _ -> pure ()

-- | Write a coverage report file if @--coverage-format@ and @--coverage-output@ are set.
--
-- @since 0.19.2
writeCoverageFile :: Flags -> CoverageMap.CoverageMap -> Map.Map Int Int -> IO ()
writeCoverageFile flags covMap hits =
  case (flags ^. testCoverageFormat, flags ^. testCoverageOutput) of
    (Just fmt, Just path) ->
      case parseCoverageFormatString fmt of
        Just coverageFormat -> Coverage.writeReport coverageFormat path covMap hits
        Nothing -> do
          let fmtStr = fmt
          Print.printErrLn [c|{red|Error:} Unknown coverage format: #{fmtStr}. Use 'istanbul', 'lcov', or 'html'.|]
    (Just _, Nothing) ->
      Print.printErrLn [c|{yellow|Warning:} --coverage-format requires --coverage-output.|]
    _ -> pure ()

-- | Parse a coverage format string into a 'CoverageFormat'.
--
-- @since 0.19.2
parseCoverageFormatString :: String -> Maybe Coverage.CoverageFormat
parseCoverageFormatString "istanbul" = Just Coverage.Istanbul
parseCoverageFormatString "lcov" = Just Coverage.LCOV
parseCoverageFormatString "html" = Just Coverage.Html
parseCoverageFormatString _ = Nothing

-- | Check the @--min-coverage@ threshold and report pass/fail.
--
-- Returns 'True' if the threshold is met or not set.
--
-- @since 0.19.2
checkMinCoverage :: Flags -> Coverage.CoverageScope -> Maybe Pkg.Name -> CoverageMap.CoverageMap -> Map.Map Int Int -> IO Bool
checkMinCoverage flags scope maybePkg covMap hits =
  case flags ^. testMinCoverage of
    Nothing -> pure True
    Just threshold ->
      if Coverage.checkThreshold threshold scope maybePkg covMap hits
        then pure True
        else do
          let thresholdStr = show threshold
          Print.printErrLn [c|{red|Error:} Coverage #{thresholdStr}% threshold not met.|]
          pure False

-- | Print warnings for FFI functions that are defined but never referenced.
--
-- @since 0.19.2
reportStaleFFI :: [(String, FilePath)] -> IO ()
reportStaleFFI [] = pure ()
reportStaleFFI stale = do
  Print.newline
  let countStr = show (length stale)
  Print.println [c|  {yellow|Warning:} #{countStr} FFI functions defined but never called:|]
  mapM_ reportOne stale
  Print.newline
  where
    reportOne (name, path) =
      Print.println [c|    #{name}  ({dullcyan|#{path}})|]

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

-- | Parser for the @--coverage-format@ flag.
--
-- @since 0.19.2
coverageFormatParser :: Terminal.Parser String
coverageFormatParser =
  Terminal.Parser
    { Terminal._singular = "format",
      Terminal._plural = "formats",
      Terminal._parser = parseCoverageFormatArg,
      Terminal._suggest = suggestCoverageFormats,
      Terminal._examples = exampleCoverageFormats
    }

-- | Parse a coverage format argument.
parseCoverageFormatArg :: String -> Maybe String
parseCoverageFormatArg "istanbul" = Just "istanbul"
parseCoverageFormatArg "lcov" = Just "lcov"
parseCoverageFormatArg "html" = Just "html"
parseCoverageFormatArg _ = Nothing

-- | Suggest coverage format values.
suggestCoverageFormats :: String -> IO [String]
suggestCoverageFormats _ = pure ["istanbul", "lcov", "html"]

-- | Provide example coverage format values.
exampleCoverageFormats :: String -> IO [String]
exampleCoverageFormats _ = pure ["istanbul", "lcov", "html"]

-- | Parser for the @--coverage-output@ flag.
--
-- @since 0.19.2
coverageOutputParser :: Terminal.Parser String
coverageOutputParser =
  Terminal.Parser
    { Terminal._singular = "file",
      Terminal._plural = "files",
      Terminal._parser = parseNonEmpty,
      Terminal._suggest = suggestCoverageOutput,
      Terminal._examples = exampleCoverageOutput
    }

-- | Suggest coverage output file paths.
suggestCoverageOutput :: String -> IO [String]
suggestCoverageOutput _ = pure ["coverage.json", "coverage.lcov"]

-- | Provide example coverage output paths.
exampleCoverageOutput :: String -> IO [String]
exampleCoverageOutput _ = pure ["coverage.json", "coverage.lcov"]

-- | Parser for the @--min-coverage@ flag.
--
-- @since 0.19.2
minCoverageParser :: Terminal.Parser Int
minCoverageParser =
  Terminal.Parser
    { Terminal._singular = "percentage",
      Terminal._plural = "percentages",
      Terminal._parser = parseMinCoverage,
      Terminal._suggest = suggestMinCoverage,
      Terminal._examples = exampleMinCoverage
    }

-- | Parse a min-coverage percentage (0-100).
parseMinCoverage :: String -> Maybe Int
parseMinCoverage s =
  case readMaybe s of
    Just n | n >= 0 && n <= 100 -> Just n
    _ -> Nothing

-- | Suggest min-coverage values.
suggestMinCoverage :: String -> IO [String]
suggestMinCoverage _ = pure ["80", "90", "100"]

-- | Provide example min-coverage values.
exampleMinCoverage :: String -> IO [String]
exampleMinCoverage _ = pure ["80", "90"]

-- | Parser for the @--include-deps@ flag.
--
-- Accepts @\"all\"@ or a comma-separated list of @author\/project@ names.
--
-- @since 0.19.2
includeDepsParser :: Terminal.Parser String
includeDepsParser =
  Terminal.Parser
    { Terminal._singular = "scope",
      Terminal._plural = "scopes",
      Terminal._parser = parseNonEmpty,
      Terminal._suggest = suggestIncludeDeps,
      Terminal._examples = exampleIncludeDeps
    }

-- | Suggest include-deps values.
suggestIncludeDeps :: String -> IO [String]
suggestIncludeDeps _ = pure ["all", "canopy/core", "canopy/json"]

-- | Provide example include-deps values.
exampleIncludeDeps :: String -> IO [String]
exampleIncludeDeps _ = pure ["all", "canopy/core,canopy/json"]

-- | Set the @CANOPY_TEST_FILTER@ environment variable for the Node.js
-- test harness. When 'Nothing', unsets the variable to ensure a clean
-- environment for unfiltered runs.
setTestFilter :: Maybe String -> IO ()
setTestFilter Nothing = Environment.unsetEnv "CANOPY_TEST_FILTER"
setTestFilter (Just pattern_) = Environment.setEnv "CANOPY_TEST_FILTER" pattern_

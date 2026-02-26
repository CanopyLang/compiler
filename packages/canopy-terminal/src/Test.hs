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
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Constraint as C
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import qualified Compiler
import Control.Lens ((^.))
import Control.Lens.TH (makeLenses)
import qualified Control.Concurrent as Concurrent
import qualified Control.Exception as Exception
import Control.Monad (filterM, void)
import qualified Data.Utf8 as Utf8
import qualified Data.Aeson as Aeson
import Data.Aeson (Object)
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.NonEmptyList as NE
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
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
import qualified PackageCache
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

-- ── Header Bar ──────────────────────────────────────────────────────

-- | Format a dullcyan header bar in the Elm report style.
--
-- Single file:    @-- TEST RESULTS ---------- test\/PlaywrightTest.can@
-- Multiple files: @-- TEST RESULTS ----------------------- 3 files@
--
-- Follows the pattern from 'Reporting.Exit.Help.formatReportBar'.
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
  let bar = testBar testFiles
  Print.println [c|{dullcyan|#{bar}}|]
  when (flags ^. testVerbose) $
    Print.println [c|  Project root: {cyan|#{root}}|]
  Print.newline
  maybeResult <- compileTestFiles root testFiles
  case maybeResult of
    Nothing -> do
      Print.printErrLn [c|{red|Compilation failed.}|]
      pure (ExitFailure 1)
    Just (jsContent, mains) -> dispatchByTestType jsContent mains testFiles flags

-- | Compile test files to a JavaScript string and main type info.
--
-- Before compiling user test files, ensures that all test-dependency
-- packages have @artifacts.dat@.  Packages with source but no artifacts
-- (e.g. locally symlinked @canopy\/test@ during development) are compiled
-- just-in-time so they receive their correct package identity in the
-- optimizer.  This is critical for type-based dispatch (e.g.
-- @BrowserTestMain@ detection requires the @Test@ module to be
-- canonicalised under @Pkg.test@, not @Pkg.dummyName@).
--
-- @since 0.19.1
compileTestFiles :: FilePath -> [FilePath] -> IO (Maybe (String, Map.Map ModuleName.Canonical Opt.Main))
compileTestFiles root testFiles = do
  ensureTestDepArtifacts root
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

-- | Ensure all test-dependency packages have compiled artifacts.
--
-- Reads the project outline, extracts test dependencies, and for each
-- package that has source files but no @artifacts.dat@, compiles the
-- package from source with its real package identity and writes the
-- artifacts to the cache.  Subsequent compilation then loads them via
-- the normal @PackageCache@ pipeline with correct canonical names.
--
-- @since 0.19.1
ensureTestDepArtifacts :: FilePath -> IO ()
ensureTestDepArtifacts root = do
  maybeOutline <- Outline.read root
  case maybeOutline of
    Nothing -> pure ()
    Just outline -> do
      cacheDir <- Stuff.getPackageCache
      mapM_ (ensureOneTestDep cacheDir) (extractTestDeps outline)

-- | Extract test-dependency (name, version) pairs from an outline.
extractTestDeps :: Outline.Outline -> [(Pkg.Name, V.Version)]
extractTestDeps (Outline.App o) = Map.toList (Outline._appTestDepsDirect o)
extractTestDeps (Outline.Pkg o) =
  Map.toList (Map.map C.lowerBound (Outline._pkgTestDeps o))

-- | Compile a single test-dependency package if it lacks artifacts.
--
-- When @artifacts.dat@ exists, this is a no-op.  Otherwise, reads the
-- package's @canopy.json@, compiles all exposed modules with the real
-- package identity, and writes @artifacts.dat@ to the cache.
--
-- Compiles from the package's own directory so that
-- @loadDependencyArtifacts@ reads the package's @canopy.json@ and
-- resolves its dependencies independently.
--
-- @since 0.19.1
ensureOneTestDep :: FilePath -> (Pkg.Name, V.Version) -> IO ()
ensureOneTestDep cacheDir (pkgName, version) = do
  let pkgDir = testDepDir cacheDir pkgName version
      artifactsPath = pkgDir </> "artifacts.dat"
  hasArtifacts <- Dir.doesFileExist artifactsPath
  if hasArtifacts
    then pure ()
    else compileTestDepFromSource pkgName version pkgDir

-- | Compile a test-dependency package from source and write artifacts.
--
-- @since 0.19.1
compileTestDepFromSource :: Pkg.Name -> V.Version -> FilePath -> IO ()
compileTestDepFromSource pkgName version pkgDir = do
  let srcPath = pkgDir </> "src"
  hasSrc <- Dir.doesDirectoryExist srcPath
  if not hasSrc
    then pure ()
    else do
      maybeOutline <- Outline.read pkgDir
      maybe (pure ()) (compileTestDepOutline pkgName version pkgDir srcPath) maybeOutline

-- | Compile a test-dependency package given its parsed outline.
--
-- Uses @withCurrentDirectory@ to set the working directory to the
-- package root so that FFI kernel paths resolve correctly.
--
-- @since 0.19.1
compileTestDepOutline :: Pkg.Name -> V.Version -> FilePath -> FilePath -> Outline.Outline -> IO ()
compileTestDepOutline _ _ _ _ (Outline.App _) = pure ()
compileTestDepOutline pkgName version pkgDir srcPath (Outline.Pkg pkgOutline) =
  case flattenExposedToNonEmpty (Outline._pkgExposed pkgOutline) of
    Nothing -> pure ()
    Just exposedModules -> do
      compileResult <- Dir.withCurrentDirectory pkgDir
        (Compiler.compileFromExposed pkgName False pkgDir [Compiler.AbsoluteSrcDir srcPath] exposedModules)
      either reportTestDepError (writeTestDepArtifacts pkgName version) compileResult
  where
    reportTestDepError err = do
      let errStr = show err
      Print.printErrLn [c|{yellow|Warning:} Could not compile test dependency: #{errStr}|]

-- | Write compiled artifacts for a test-dependency package.
--
-- @since 0.19.1
writeTestDepArtifacts :: Pkg.Name -> V.Version -> Compiler.Artifacts -> IO ()
writeTestDepArtifacts (Pkg.Name author project) version artifacts =
  PackageCache.writePackageArtifacts
    (Utf8.toChars author)
    (Utf8.toChars project)
    (V.toChars version)
    interfaces
    globalGraph
    ffiInfo
  where
    interfaces = buildArtifactsToInterfaces artifacts
    globalGraph = artifacts ^. Build.artifactsGlobalGraph
    ffiInfo = artifacts ^. Build.artifactsFFIInfo

-- | Convert compiled artifacts to package interface map.
--
-- @since 0.19.1
buildArtifactsToInterfaces :: Compiler.Artifacts -> PackageCache.PackageInterfaces
buildArtifactsToInterfaces artifacts =
  Map.fromList
    [ (name, I.Public iface)
    | Build.Fresh name iface _ <- Build._artifactsModules artifacts
    ]

-- | Flatten exposed modules to a non-empty list.
--
-- @since 0.19.1
flattenExposedToNonEmpty :: Outline.Exposed -> Maybe (NE.List ModuleName.Raw)
flattenExposedToNonEmpty exposed =
  case Outline.flattenExposed exposed of
    [] -> Nothing
    (x : xs) -> Just (NE.List x xs)

-- | Build the package directory path inside the cache.
testDepDir :: FilePath -> Pkg.Name -> V.Version -> FilePath
testDepDir cacheDir (Pkg.Name author project) version =
  cacheDir </> Utf8.toChars author </> Utf8.toChars project </> V.toChars version

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
-- 'Opt.BrowserTestMain' runs tests in a real browser via Playwright.
-- 'Opt.TestMain' indicates a non-visual program (test or async).
-- 'Opt.Static' indicates a standard HTML program (unit test with DOM output).
dispatchByTestType :: String -> Map.Map ModuleName.Canonical Opt.Main -> [FilePath] -> Flags -> IO ExitCode
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
--
-- For @main : BrowserTest@ programs. Generates an HTML page with the
-- compiled tests and browser-test-runner.js, serves it via an embedded
-- HTTP server, launches Playwright to navigate to the page, and collects
-- NDJSON results from console.log events.
--
-- @since 0.19.1
executeBrowserExecutionTests :: String -> [FilePath] -> Flags -> IO ExitCode
executeBrowserExecutionTests jsContent testFiles flags = do
  Print.println [c|{cyan|Browser execution tests detected.} Setting up real browser environment...|]
  Print.newline
  runBrowserExecutionPipeline jsContent testFiles flags
    `Exception.catch` handleBrowserError

-- | Run the browser execution pipeline.
runBrowserExecutionPipeline :: String -> [FilePath] -> Flags -> IO ExitCode
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
runBrowserExecutionWithServer :: String -> Flags -> JsContent -> JsContent -> IO ExitCode
runBrowserExecutionWithServer jsContent flags browserRunner rpcModule = do
  portResult <- Server.findAvailablePort
  case portResult of
    Left _ -> do
      Print.printErrLn [c|{red|Error:} Could not find an available port (8000-9000).|]
      pure (ExitFailure 1)
    Right port -> do
      tmpDir <- Dir.getTemporaryDirectory
      let htmlPath = tmpDir </> "canopy-browser-test.html"
          rpcPath = tmpDir </> "canopy-playwright-rpc.js"
          harness = Harness.generateBrowserTestHarness (JsContent (Text.pack jsContent)) browserRunner
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
--
-- The launcher loads @playwright-rpc.js@, sets up the RPC bridge,
-- navigates to the HTML harness, intercepts console.log events
-- (forwarding NDJSON and handling RPC requests), and waits for
-- @window.__canopyTestsDone@.
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
  runNodeForBrowserTests launcherPath cwd (flags ^. testVerbose)

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
  Print.newline
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
      server <- Server.startTestServer appDir port
      when (flags ^. testVerbose) $ do
        let portStr = show (unServerPort port)
        Print.println [c|  Listening on {cyan|http://127.0.0.1:#{portStr}}|]
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

-- | Execute @node@ with streaming NDJSON output.
--
-- Launches the node process with piped stdout\/stderr. Reads stdout
-- line-by-line, parsing each line as an NDJSON test event and formatting
-- it with 'Terminal.Print' + 'Reporting.Doc.ColorQQ'. Non-JSON lines are
-- passed through as-is. Stderr is drained in a background thread and
-- printed on failure.
executeNode :: FilePath -> [String] -> Bool -> IO ExitCode
executeNode nodePath args verbose =
  Process.withCreateProcess procSpec handleStreams
  where
    procSpec =
      (Process.proc nodePath args)
        { Process.std_out = Process.CreatePipe,
          Process.std_err = Process.CreatePipe
        }
    handleStreams _stdin mStdout mStderr procHandle =
      case (mStdout, mStderr) of
        (Just hOut, Just hErr) -> do
          IO.hSetBinaryMode hOut True
          IO.hSetBinaryMode hErr True
          stderrVar <- Concurrent.newMVar []
          _ <- Concurrent.forkIO (drainStderr hErr stderrVar)
          sawSummary <- streamStdout hOut
          exitCode <- Process.waitForProcess procHandle
          when (not sawSummary) $
            Print.printErrLn [c|{yellow|Warning: test process exited without summary.}|]
          reportExitCode exitCode stderrVar verbose args
        _ -> do
          exitCode <- Process.waitForProcess procHandle
          pure exitCode

-- | Read stderr lines into a MVar for later display.
drainStderr :: IO.Handle -> Concurrent.MVar [String] -> IO ()
drainStderr hErr var = go
  where
    go = do
      eof <- IO.hIsEOF hErr
      if eof
        then pure ()
        else do
          line <- IO.hGetLine hErr
          Concurrent.modifyMVar_ var (\ls -> pure (ls ++ [line]))
          go

-- | Read stdout line-by-line, parsing NDJSON events and formatting them.
--
-- Returns 'True' if a summary event was received, 'False' otherwise.
-- The caller uses this to detect when the JS process crashed or was
-- killed before emitting its summary.
streamStdout :: IO.Handle -> IO Bool
streamStdout hOut = go False
  where
    go sawSummary = do
      eof <- IO.hIsEOF hOut
      if eof
        then pure sawSummary
        else do
          line <- BS.hGetLine hOut
          isSummary <- handleOutputLine line
          go (sawSummary || isSummary)

-- | Parse a single stdout line as NDJSON or pass through as plain text.
--
-- Returns 'True' when the line was a summary event, 'False' otherwise.
-- Non-JSON lines are written to stderr so they do not corrupt formatted
-- test output on stdout. Flushes after each line so results appear
-- immediately, even when stdout is a pipe.
handleOutputLine :: BS.ByteString -> IO Bool
handleOutputLine line =
  case Aeson.decodeStrict' line of
    Just event -> do
      formatTestEvent event
      IO.hFlush IO.stdout
      pure (isSummaryEvent event)
    Nothing -> do
      IO.hPutStrLn IO.stderr (Text.unpack (TextEnc.decodeUtf8 line))
      IO.hFlush IO.stderr
      pure False

-- | Check if a 'TestEvent' is a summary event.
isSummaryEvent :: TestEvent -> Bool
isSummaryEvent (SummaryEvent {}) = True
isSummaryEvent _ = False

-- | Report exit status, printing stderr and verbose info on failure.
reportExitCode :: ExitCode -> Concurrent.MVar [String] -> Bool -> [String] -> IO ExitCode
reportExitCode ExitSuccess _ _ _ = do
  Print.newline
  Print.println [c|{green|Tests passed.}|]
  pure ExitSuccess
reportExitCode (ExitFailure _) stderrVar verbose args = do
  stderrLines <- Concurrent.readMVar stderrVar
  mapM_ (IO.hPutStrLn IO.stderr) stderrLines
  when verbose (printVerboseInfo args)
  Print.newline
  Print.println [c|{red|Tests failed.}|]
  pure (ExitFailure 1)

-- | Print debugging info when verbose mode is on.
printVerboseInfo :: [String] -> IO ()
printVerboseInfo args =
  case args of
    [path] -> Print.println [c|Test runner written to: {cyan|#{path}}|]
    _ -> pure ()

-- ── NDJSON Event Types ──────────────────────────────────────────────

-- | A test event emitted by the JavaScript test runner as NDJSON.
data TestEvent
  = ResultEvent !ResultStatus !Text.Text !Double !(Maybe Text.Text)
  | SummaryEvent !Int !Int !Int !Int !Int !Double
  deriving (Eq, Show)

-- | Status of a single test result.
data ResultStatus = Passed | Failed | Skipped | Todo
  deriving (Eq, Show)

instance Aeson.FromJSON TestEvent where
  parseJSON = Aeson.withObject "TestEvent" $ \obj -> do
    eventType <- obj Aeson..: "event"
    case (eventType :: Text.Text) of
      "result" -> parseResultEvent obj
      "summary" -> parseSummaryEvent obj
      _ -> fail ("Unknown event type: " ++ Text.unpack eventType)

-- | Parse a result event from a JSON object.
parseResultEvent :: Object -> AesonTypes.Parser TestEvent
parseResultEvent obj = do
  statusStr <- obj Aeson..: "status"
  name <- obj Aeson..: "name"
  duration <- obj Aeson..:? "duration" Aeson..!= 0
  message <- obj Aeson..:? "message"
  status <- parseStatus statusStr
  pure (ResultEvent status name duration message)

-- | Parse a summary event from a JSON object.
parseSummaryEvent :: Object -> AesonTypes.Parser TestEvent
parseSummaryEvent obj =
  SummaryEvent
    <$> obj Aeson..: "passed"
    <*> obj Aeson..: "failed"
    <*> obj Aeson..: "skipped"
    <*> obj Aeson..: "todo"
    <*> obj Aeson..: "total"
    <*> obj Aeson..: "duration"

-- | Parse a status string into a 'ResultStatus'.
parseStatus :: Text.Text -> AesonTypes.Parser ResultStatus
parseStatus "passed" = pure Passed
parseStatus "failed" = pure Failed
parseStatus "skipped" = pure Skipped
parseStatus "todo" = pure Todo
parseStatus other = fail ("Unknown status: " ++ Text.unpack other)

-- ── NDJSON Formatting ───────────────────────────────────────────────

-- | Format and print a test event using ColorQQ.
formatTestEvent :: TestEvent -> IO ()
formatTestEvent (ResultEvent status name duration message) =
  formatResult status name duration message
formatTestEvent (SummaryEvent passed failed skipped todo total duration) =
  formatSummary passed failed skipped todo total duration

-- | Format a single test result line.
formatResult :: ResultStatus -> Text.Text -> Double -> Maybe Text.Text -> IO ()
formatResult Passed name duration _ =
  Print.println [c|  {green|✓} #{nameStr} {dullcyan|#{durationStr}}|]
  where
    nameStr = Text.unpack name
    durationStr = formatDuration duration
formatResult Failed name duration message = do
  Print.println [c|  {red|✗} #{nameStr} {dullcyan|#{durationStr}}|]
  maybe (pure ()) printFailureMessage message
  where
    nameStr = Text.unpack name
    durationStr = formatDuration duration
formatResult Skipped name _ _ =
  Print.println [c|  {yellow|○} #{nameStr} {dullcyan|(skipped)}|]
  where
    nameStr = Text.unpack name
formatResult Todo name _ _ =
  Print.println [c|  {cyan|◌} #{nameStr} {dullcyan|(todo)}|]
  where
    nameStr = Text.unpack name

-- | Print a failure message indented under the test name.
printFailureMessage :: Text.Text -> IO ()
printFailureMessage msg =
  mapM_ printIndentedLine (Text.lines msg)
  where
    printIndentedLine line =
      Print.println [c|    {red|#{lineStr}}|]
      where
        lineStr = Text.unpack line

-- | Format the test suite summary line.
formatSummary :: Int -> Int -> Int -> Int -> Int -> Double -> IO ()
formatSummary passed failed skipped todo total duration = do
  Print.newline
  Print.println [c|  {green|#{passedStr} passed}, {red|#{failedStr} failed}#{extraStr} (#{totalStr} total)|]
  Print.println [c|  Duration: #{durationStr}|]
  where
    passedStr = show passed
    failedStr = show failed
    totalStr = show total
    durationStr = formatDuration duration
    skippedPart = if skipped > 0 then ", " ++ show skipped ++ " skipped" else ""
    todoPart = if todo > 0 then ", " ++ show todo ++ " todo" else ""
    extraStr = skippedPart ++ todoPart

-- | Format a duration in milliseconds for display.
formatDuration :: Double -> String
formatDuration ms
  | ms < 1000 = show (round ms :: Int) ++ "ms"
  | otherwise = show (fromIntegral (round (ms / 100) :: Int) / 10 :: Double) ++ "s"

-- ── Utilities ────────────────────────────────────────────────────────

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


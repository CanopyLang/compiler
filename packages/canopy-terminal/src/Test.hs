{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Test command handler for the Canopy CLI.
--
-- This module implements the @canopy test@ command, which discovers Canopy
-- test modules, compiles them to JavaScript, generates a Node.js test runner,
-- executes the tests via @node@, and reports pass\/fail results.
--
-- == Usage
--
-- @
-- canopy test                         -- Run all tests in tests\/
-- canopy test tests\/MyTest.can       -- Run a specific test file
-- canopy test --filter \"MyModule\"   -- Run tests matching a pattern
-- canopy test --watch                 -- Watch for changes and re-run
-- @
--
-- == Test Module Convention
--
-- Test modules are @.can@ files in the @tests\/@ directory that expose
-- a @suite@ value of type @Test@:
--
-- @
-- module MyTest exposing (..)
--
-- import Test exposing (Test, describe, test)
-- import Expect
--
-- suite : Test
-- suite = describe \"MyModule\" [ test \"works\" (\\_ -> Expect.equal 1 1) ]
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
import Text.Read (readMaybe)
import qualified Stuff

-- | Flags for the test command.
--
-- Controls test discovery, filtering, watching, and output verbosity.
data Flags = Flags
  { -- | Optional test name filter pattern
    _testFilter :: !(Maybe String),
    -- | Enable file watching for continuous testing
    _testWatch :: !Bool,
    -- | Enable verbose output
    _testVerbose :: !Bool
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
--
-- Performs discovery, compilation, execution, and reporting in a single pass.
-- Exits with code 0 on all tests passing, 1 on any failure.
runOnce :: [FilePath] -> Flags -> IO ()
runOnce paths flags = do
  testFiles <- discoverTestFiles paths
  result <- compileAndRunTests testFiles flags
  Exit.exitWith result

-- | Run tests with file watching enabled.
--
-- Performs an initial test run, then watches @tests\/@ and @src\/@ for
-- @.can@ file changes. Re-runs tests on each detected change.
-- Blocks until interrupted with Ctrl+C.
runWithWatch :: [FilePath] -> Flags -> IO ()
runWithWatch paths flags = do
  putStrLn "Watching for changes... Press Ctrl+C to stop."
  testFiles <- discoverTestFiles paths
  _ <- compileAndRunTests testFiles flags
  watchDirsForRerun paths flags

-- | Watch relevant directories and re-run tests on changes.
--
-- Uses FSNotify to monitor @tests\/@ and @src\/@ for @.can@ files.
-- Blocks indefinitely until the thread is killed.
watchDirsForRerun :: [FilePath] -> Flags -> IO ()
watchDirsForRerun paths flags =
  FSNotify.withManager $ \mgr -> do
    let candidates = ["tests", "src"]
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
  putStrLn "\n--- File changed, re-running tests ---"
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

-- | Discover test files from paths or the default @tests\/@ directory.
--
-- If no paths are given, scans @tests\/@ for @.can@ files.
-- Otherwise, expands the explicitly specified paths (files and\/or dirs).
discoverTestFiles :: [FilePath] -> IO [FilePath]
discoverTestFiles [] = findCanopyFilesIn "tests"
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

-- | Compile test files and run them, returning the overall exit code.
--
-- Locates the project root, compiles discovered test files to JavaScript,
-- wraps them in a test harness, executes via @node@, and reports results.
compileAndRunTests :: [FilePath] -> Flags -> IO ExitCode
compileAndRunTests [] _ = do
  putStrLn "No test files found."
  putStrLn "Create .can files in a tests/ directory to get started."
  pure ExitSuccess
compileAndRunTests testFiles flags = do
  maybeRoot <- Stuff.findRoot
  case maybeRoot of
    Nothing -> reportNoProject
    Just root -> compileAndRunWithRoot root testFiles flags

-- | Report that no canopy.json was found in the current directory tree.
reportNoProject :: IO ExitCode
reportNoProject = do
  putStrLn "Error: No canopy.json found. Run canopy test from a Canopy project."
  pure (ExitFailure 1)

-- | Compile and run tests when the project root is known.
compileAndRunWithRoot :: FilePath -> [FilePath] -> Flags -> IO ExitCode
compileAndRunWithRoot root testFiles flags = do
  if flags ^. testVerbose
    then putStrLn ("Running " ++ show (length testFiles) ++ " test file(s) from " ++ root ++ "...")
    else putStrLn ("Running " ++ show (length testFiles) ++ " test file(s)...")
  maybeJs <- compileTestFiles root testFiles
  case maybeJs of
    Nothing -> do
      putStrLn "Compilation failed."
      pure (ExitFailure 1)
    Just jsContent -> executeTestRunner jsContent flags

-- | Compile test files to a JavaScript string using the Canopy compiler.
--
-- Invokes 'Compiler.compileFromPaths' with @src@ and @tests@ as source
-- directories.  On success, generates JavaScript in development mode.
-- Returns 'Nothing' when compilation fails (the error is printed).
compileTestFiles :: FilePath -> [FilePath] -> IO (Maybe String)
compileTestFiles root testFiles = do
  let pkg = Pkg.dummyName
      srcDirs = [Compiler.RelativeSrcDir "src", Compiler.RelativeSrcDir "tests"]
  result <- Compiler.compileFromPaths pkg True root srcDirs testFiles
  case result of
    Left err -> do
      putStrLn ("Compilation error: " ++ show err)
      pure Nothing
    Right artifacts -> pure (Just (artifactsToJavaScript artifacts))

-- | Generate a JavaScript string from compiled artifacts.
--
-- Extracts the global graph, mains map, and FFI info from artifacts,
-- then invokes 'JS.generate' in development mode (no optimisations).
artifactsToJavaScript :: Compiler.Artifacts -> String
artifactsToJavaScript artifacts =
  let globalGraph = artifacts ^. Build.artifactsGlobalGraph
      ffiInfo = artifacts ^. Build.artifactsFFIInfo
      mains = collectMains artifacts
      builder = JS.generate (Mode.Dev Nothing False) globalGraph mains ffiInfo
  in builderToString builder

-- | Collect main entries from all roots of the artifacts.
--
-- Produces the map from canonical module name to @Main@ value that
-- 'JS.generate' needs to emit the module initialisation code.
collectMains :: Compiler.Artifacts -> Map.Map ModuleName.Canonical Opt.Main
collectMains artifacts =
  let roots = NE.toList (artifacts ^. Build.artifactsRoots)
      pkg = artifacts ^. Build.artifactsName
  in Map.fromList (Maybe.mapMaybe (extractMain pkg) roots)

-- | Extract a (CanonicalName, Main) pair from a root, if it has a main.
extractMain :: Pkg.Name -> Build.Root -> Maybe (ModuleName.Canonical, Opt.Main)
extractMain pkg root =
  case root of
    Build.Inside _ -> Nothing
    Build.Outside name _ (Opt.LocalGraph maybeMain _ _) ->
      fmap (\m -> (ModuleName.Canonical pkg name, m)) maybeMain

-- | Convert a 'Builder.Builder' to a plain 'String'.
--
-- Materialises the lazy 'ByteString' then converts each byte to a 'Char'.
-- This is safe for the ASCII-heavy JavaScript output produced by the compiler.
builderToString :: Builder.Builder -> String
builderToString b =
  map (toEnum . fromIntegral) (LBS.unpack (Builder.toLazyByteString b))

-- | Write the JS harness to a temp file and execute it with node.
--
-- Wraps compiled JS with the test harness bootstrap, writes to a temporary
-- file, then runs @node@ on it and captures stdout\/stderr.
executeTestRunner :: String -> Flags -> IO ExitCode
executeTestRunner jsContent flags = do
  tmpDir <- Dir.getTemporaryDirectory
  let runnerPath = tmpDir </> "canopy-test-runner.js"
  writeFile runnerPath (wrapWithTestHarness jsContent (flags ^. testFilter))
  runNodeAndReport runnerPath

-- | Wrap compiled JavaScript with the test harness bootstrap.
--
-- Appends a Node.js snippet that discovers compiled test suite objects,
-- runs each suite through the harness, and exits with 0 or 1.
wrapWithTestHarness :: String -> Maybe String -> String
wrapWithTestHarness jsContent maybeFilter =
  unlines [jsContent, "", generateTestHarness maybeFilter]

-- | Generate the Node.js test harness snippet.
--
-- Produces code that collects test suites from compiled module globals,
-- runs each suite, prints a summary, and exits with the appropriate code.
generateTestHarness :: Maybe String -> String
generateTestHarness maybeFilter =
  unlines
    [ "// Canopy test harness - auto-generated by canopy test",
      "var passed = 0;",
      "var failed = 0;",
      "var total = 0;",
      filterVarCode maybeFilter,
      "",
      "function runSuite(suite) {",
      "  var results = (suite && suite.run) ? suite.run() : [];",
      "  results.forEach(function(r) {",
      "    if (testFilter && r.name.indexOf(testFilter) === -1) { return; }",
      "    total++;",
      "    if (r.passed) {",
      "      passed++;",
      "      console.log('  PASS  ' + r.name);",
      "    } else {",
      "      failed++;",
      "      console.log('  FAIL  ' + r.name);",
      "      if (r.reason) { console.log('        ' + r.reason); }",
      "    }",
      "  });",
      "}",
      "",
      "var scope = (typeof module !== 'undefined' && module.exports) || this || {};",
      "Object.keys(scope).forEach(function(k) {",
      "  var v = scope[k];",
      "  if (v && typeof v === 'object' && typeof v.run === 'function') {",
      "    runSuite(v);",
      "  }",
      "});",
      "",
      "console.log('');",
      "console.log(total + ' test(s) total, ' + passed + ' passed, ' + failed + ' failed.');",
      "process.exit(failed > 0 ? 1 : 0);"
    ]

-- | Generate the JavaScript @testFilter@ variable declaration.
filterVarCode :: Maybe String -> String
filterVarCode Nothing = "var testFilter = null;"
filterVarCode (Just f) = "var testFilter = " ++ show f ++ ";"

-- | Find the @node@ executable and execute the runner script.
runNodeAndReport :: FilePath -> IO ExitCode
runNodeAndReport runnerPath = do
  nodeExists <- Dir.findExecutable "node"
  case nodeExists of
    Nothing -> do
      putStrLn "Error: 'node' not found. Install Node.js to run Canopy tests."
      pure (ExitFailure 1)
    Just nodePath -> executeNode nodePath runnerPath

-- | Execute @node@ on the runner path and print captured output.
executeNode :: FilePath -> FilePath -> IO ExitCode
executeNode nodePath runnerPath = do
  (exitCode, stdout, stderr) <-
    Process.readProcessWithExitCode nodePath [runnerPath] ""
  IO.hPutStr IO.stdout stdout
  case exitCode of
    ExitSuccess -> do
      putStrLn "Tests passed."
      pure ExitSuccess
    ExitFailure _ -> do
      unless (null stderr) (IO.hPutStr IO.stderr stderr)
      putStrLn "Tests failed."
      pure (ExitFailure 1)

-- | Conditional action: skip execution when the condition is 'True'.
unless :: Bool -> IO () -> IO ()
unless True _ = pure ()
unless False action = action

-- | Parser for the @--filter@ flag.
--
-- Accepts any non-empty string as a test name filter pattern.
-- Tests whose names do not contain the pattern are skipped.
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

-- | Parse a non-empty string; returns 'Nothing' for empty input.
parseNonEmpty :: String -> Maybe String
parseNonEmpty s
  | null s = Nothing
  | otherwise = Just s

-- | Suggest common filter pattern values.
suggestFilterPatterns :: String -> IO [String]
suggestFilterPatterns _ = pure ["MyModule", "describe", "unit"]

-- | Provide example filter pattern values for help text.
exampleFilterPatterns :: String -> IO [String]
exampleFilterPatterns _ = pure ["MyModule", "integration", "parse"]

-- Suppress the unused-import warning for readMaybe; it is used by callers.
_unusedReadMaybe :: String -> Maybe Int
_unusedReadMaybe = readMaybe

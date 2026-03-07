{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Node.js test runner execution for the Canopy test runner.
--
-- This module handles finding and executing the @node@ executable to run
-- compiled Canopy test scripts. It supports both simple unit test execution
-- and browser test execution with @NODE_PATH@ setup for Playwright.
--
-- Output is read line-by-line from stdout, parsed as NDJSON test events,
-- and formatted with 'Terminal.Print' for streaming display.
--
-- @since 0.19.1
module Test.Runner
  ( runNodeAndReport,
    runNodeForBrowserTests,
    reportNodeMissing,
    getNpmGlobalRoot,
    buildNodePaths,
    nodePathWrapper,
    executeNode,
    drainStderr,
    streamStdout,
    handleOutputLine,
    reportExitCode,
    printVerboseInfo,
  )
where

import qualified Control.Concurrent as Concurrent
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import Data.Aeson (Value)
import qualified Data.ByteString.Char8 as BS
import qualified Data.List as List
import Reporting.Doc.ColorQQ (c)
import System.Exit (ExitCode (..))
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.IO as IO
import qualified System.Process as Process
import qualified Terminal.Print as Print
import Test.Event (TestEvent (..), formatTestEvent, isSummaryEvent)

-- | Find the @node@ executable and execute the runner script.
--
-- Reports an error if @node@ is not found on @PATH@.
-- Returns the exit code and any coverage data collected during the run.
--
-- @since 0.19.1
runNodeAndReport :: FilePath -> Bool -> IO (ExitCode, Maybe Value)
runNodeAndReport runnerPath verbose = do
  nodeExists <- Dir.findExecutable "node"
  case nodeExists of
    Nothing -> fmap (\ec -> (ec, Nothing)) reportNodeMissing
    Just nodePath -> executeNode nodePath [runnerPath] verbose

-- | Run @node@ for browser tests with @NODE_PATH@ set so
-- @require('playwright')@ resolves from local or global installs.
--
-- Returns the exit code and any coverage data collected during the run.
--
-- @since 0.19.1
runNodeForBrowserTests :: FilePath -> FilePath -> Bool -> IO (ExitCode, Maybe Value)
runNodeForBrowserTests runnerPath projectDir verbose = do
  nodeExists <- Dir.findExecutable "node"
  case nodeExists of
    Nothing -> fmap (\ec -> (ec, Nothing)) reportNodeMissing
    Just nodePath -> do
      npmRoot <- getNpmGlobalRoot
      let paths = buildNodePaths projectDir npmRoot
      executeNode nodePath ["-e", nodePathWrapper paths runnerPath] verbose

-- | Report that the @node@ executable is not found.
--
-- @since 0.19.1
reportNodeMissing :: IO ExitCode
reportNodeMissing = do
  Print.printErrLn [c|{red|Error:} 'node' not found. Install Node.js to run Canopy tests.|]
  pure (ExitFailure 1)

-- | Discover the global npm @node_modules@ directory via @npm root -g@.
--
-- @since 0.19.1
getNpmGlobalRoot :: IO (Maybe FilePath)
getNpmGlobalRoot =
  fmap extractPath (Process.readProcessWithExitCode "npm" ["root", "-g"] "")
    `Exception.catch` handleIOError
  where
    extractPath (ExitSuccess, out, _) = Just (filter (/= '\n') out)
    extractPath _ = Nothing

    handleIOError :: Exception.IOException -> IO (Maybe FilePath)
    handleIOError _ = pure Nothing

-- | Build the @NODE_PATH@ search list from the project's local
-- @node_modules@ and the optional global npm root.
--
-- @since 0.19.1
buildNodePaths :: FilePath -> Maybe FilePath -> [FilePath]
buildNodePaths projectDir maybeGlobal =
  (projectDir </> "node_modules") : maybe [] pure maybeGlobal

-- | Generate a Node.js wrapper script that sets @NODE_PATH@ before
-- requiring the actual harness file.
--
-- @since 0.19.1
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
--
-- Returns the exit code and any coverage data captured from the NDJSON stream.
--
-- @since 0.19.1
executeNode :: FilePath -> [String] -> Bool -> IO (ExitCode, Maybe Value)
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
          (sawSummary, covData) <- streamStdout hOut
          exitCode <- Process.waitForProcess procHandle
          when (not sawSummary) $
            Print.printErrLn [c|{yellow|Warning: test process exited without summary.}|]
          finalCode <- reportExitCode exitCode stderrVar verbose args
          pure (finalCode, covData)
        _ -> do
          exitCode <- Process.waitForProcess procHandle
          pure (exitCode, Nothing)

-- | Read stderr lines into a MVar for later display.
--
-- @since 0.19.1
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
-- Returns @(sawSummary, maybeCoverageData)@. The first element is 'True'
-- if a summary event was received. The second is the JSON coverage data
-- from a @CoverageEvent@, if one was emitted.
--
-- @since 0.19.1
streamStdout :: IO.Handle -> IO (Bool, Maybe Value)
streamStdout hOut = go False Nothing
  where
    go sawSummary covData = do
      eof <- IO.hIsEOF hOut
      if eof
        then pure (sawSummary, covData)
        else do
          line <- BS.hGetLine hOut
          (isSummary, maybeCov) <- handleOutputLine line
          go (sawSummary || isSummary) (maybeCov `orElse` covData)

    orElse (Just x) _ = Just x
    orElse Nothing  y = y

-- | Parse a single stdout line as NDJSON or pass through as plain text.
--
-- Returns @(isSummary, maybeCoverageData)@. The first element is 'True'
-- when the line was a summary event. The second is 'Just' the coverage
-- JSON payload when the line was a coverage event.
--
-- Non-JSON lines are written to stderr so they do not corrupt formatted
-- test output on stdout. Flushes after each line so results appear
-- immediately, even when stdout is a pipe.
--
-- @since 0.19.1
handleOutputLine :: BS.ByteString -> IO (Bool, Maybe Value)
handleOutputLine line =
  case Aeson.decodeStrict' line of
    Just event -> do
      formatTestEvent event
      IO.hFlush IO.stdout
      pure (isSummaryEvent event, extractCoverageData event)
    Nothing -> do
      IO.hPutStrLn IO.stderr (BS.unpack line)
      IO.hFlush IO.stderr
      pure (False, Nothing)

-- | Extract coverage data from a 'CoverageEvent', if present.
--
-- @since 0.19.2
extractCoverageData :: TestEvent -> Maybe Value
extractCoverageData (CoverageEvent v) = Just v
extractCoverageData _ = Nothing

-- | Report exit status, printing stderr and verbose info on failure.
--
-- @since 0.19.1
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
--
-- @since 0.19.1
printVerboseInfo :: [String] -> IO ()
printVerboseInfo args =
  case args of
    [path] -> Print.println [c|Test runner written to: {cyan|#{path}}|]
    _ -> pure ()

-- LOCAL HELPERS

-- | Conditional action: execute only when the condition is 'True'.
--
-- @since 0.19.1
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = pure ()

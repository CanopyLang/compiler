{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Tests for logging output sinks.
--
-- Verifies CLI and JSON sink output formatting.
--
-- @since 0.19.1
module Unit.Logging.SinkTest (tests) where

import qualified Data.IORef as IORef
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Logging.Event
import qualified Logging.Sink as Sink
import System.Directory (doesFileExist)
import qualified System.IO as IO
import System.IO.Temp (withSystemTempDirectory, withSystemTempFile)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Logging.Sink Tests"
    [ nullSinkTests,
      combineSinkTests,
      cliSinkTests,
      jsonSinkTests,
      fileSinkTests
    ]

nullSinkTests :: TestTree
nullSinkTests =
  testGroup
    "null sink"
    [ testCase "null sink does not crash" $ do
        Sink.runSink Sink.nullSink (BuildStarted "test")
    ]

combineSinkTests :: TestTree
combineSinkTests =
  testGroup
    "combine sinks"
    [ testCase "combined sink calls all children" $ do
        counter <- IORef.newIORef (0 :: Int)
        let countSink = Sink.Sink (\_ -> IORef.modifyIORef' counter (+ 1))
        let combined = Sink.combineSinks [countSink, countSink, countSink]
        Sink.runSink combined (BuildStarted "test")
        count <- IORef.readIORef counter
        count @?= 3
    ]

cliSinkTests :: TestTree
cliSinkTests =
  testGroup
    "CLI sink output"
    [ testCase "CLI output contains level" $
        withCapturedOutput $ \output -> do
          let sink = Sink.cliSink output
          Sink.runSink sink (BuildStarted "test-label")
          IO.hSeek output IO.AbsoluteSeek 0
          content <- TextIO.hGetContents output
          assertBool "contains INFO" (Text.isInfixOf "INFO" content),
      testCase "CLI output contains phase" $
        withCapturedOutput $ \output -> do
          let sink = Sink.cliSink output
          Sink.runSink sink (ParseStarted "/tmp/test.can" 100)
          IO.hSeek output IO.AbsoluteSeek 0
          content <- TextIO.hGetContents output
          assertBool "contains PARSE" (Text.isInfixOf "PARSE" content),
      testCase "CLI output contains message" $
        withCapturedOutput $ \output -> do
          let sink = Sink.cliSink output
          Sink.runSink sink (BuildStarted "my-unique-label")
          IO.hSeek output IO.AbsoluteSeek 0
          content <- TextIO.hGetContents output
          assertBool "contains label" (Text.isInfixOf "my-unique-label" content)
    ]

jsonSinkTests :: TestTree
jsonSinkTests =
  testGroup
    "JSON sink output"
    [ testCase "JSON output is valid JSON-like structure" $
        withCapturedOutput $ \output -> do
          let sink = Sink.jsonSink output
          Sink.runSink sink (BuildStarted "json-test")
          IO.hSeek output IO.AbsoluteSeek 0
          content <- TextIO.hGetContents output
          assertBool "starts with {" (Text.isPrefixOf "{" (Text.stripStart content))
          assertBool "contains closing }" (Text.isInfixOf "}" content),
      testCase "JSON output contains event type" $
        withCapturedOutput $ \output -> do
          let sink = Sink.jsonSink output
          Sink.runSink sink (BuildStarted "json-test")
          IO.hSeek output IO.AbsoluteSeek 0
          content <- TextIO.hGetContents output
          assertBool "contains event key" (Text.isInfixOf "\"event\"" content)
          assertBool "contains event value" (Text.isInfixOf "build_started" content),
      testCase "JSON output contains level" $
        withCapturedOutput $ \output -> do
          let sink = Sink.jsonSink output
          Sink.runSink sink (ParseFailed "/tmp" "error")
          IO.hSeek output IO.AbsoluteSeek 0
          content <- TextIO.hGetContents output
          assertBool "contains ERROR" (Text.isInfixOf "ERROR" content),
      testCase "JSON output contains phase" $
        withCapturedOutput $ \output -> do
          let sink = Sink.jsonSink output
          Sink.runSink sink (TypeSolveStarted "Main" 5)
          IO.hSeek output IO.AbsoluteSeek 0
          content <- TextIO.hGetContents output
          assertBool "contains TYPE" (Text.isInfixOf "TYPE" content)
    ]

fileSinkTests :: TestTree
fileSinkTests =
  testGroup
    "file sink"
    [ testCase "file sink creates without error" $
        withSystemTempDirectory "sink-test" $ \dir -> do
          let path = dir ++ "/test.log"
          sink <- Sink.fileSink path
          Sink.runSink sink (BuildStarted "file-test")
          -- Verify the file was created (the handle keeps it open, so
          -- we just check creation succeeded without exception)
          exists <- doesFileExist path
          assertBool "file exists" exists
    ]

-- | Create a temporary file handle for capturing sink output.
withCapturedOutput :: (IO.Handle -> IO ()) -> IO ()
withCapturedOutput action =
  withSystemTempFile "sink-capture.txt" $ \_ handle -> action handle

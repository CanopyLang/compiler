{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | NDJSON test event types and formatting for the Canopy test runner.
--
-- This module defines the 'TestEvent' data type that represents test events
-- emitted by the JavaScript test runner as newline-delimited JSON (NDJSON).
-- It also provides Aeson 'FromJSON' instances and formatting functions for
-- displaying test results to the terminal.
--
-- @since 0.19.1
module Test.Event
  ( TestEvent (..),
    ResultStatus (..),
    isSummaryEvent,
    isCoverageEvent,
    formatTestEvent,
    formatResult,
    formatSummary,
    formatDuration,
  )
where

import qualified Data.Aeson as Aeson
import Data.Aeson (Object, Value)
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Text as Text
import Reporting.Doc.ColorQQ (c)
import qualified Terminal.Print as Print

-- | A test event emitted by the JavaScript test runner as NDJSON.
--
-- @since 0.19.1
data TestEvent
  = ResultEvent !ResultStatus !Text.Text !Double !(Maybe Text.Text)
  | SummaryEvent !Int !Int !Int !Int !Int !Double
  | CoverageEvent !Value
  deriving (Eq, Show)

-- | Status of a single test result.
--
-- @since 0.19.1
data ResultStatus = Passed | Failed | Skipped | Todo
  deriving (Eq, Show)

instance Aeson.FromJSON TestEvent where
  parseJSON = Aeson.withObject "TestEvent" $ \obj -> do
    eventType <- obj Aeson..: "event"
    case (eventType :: Text.Text) of
      "result" -> parseResultEvent obj
      "summary" -> parseSummaryEvent obj
      "coverage" -> parseCoverageEvent obj
      _ -> fail ("Unknown event type: " ++ Text.unpack eventType)

-- | Parse a result event from a JSON object.
--
-- @since 0.19.1
parseResultEvent :: Object -> AesonTypes.Parser TestEvent
parseResultEvent obj = do
  statusStr <- obj Aeson..: "status"
  name <- obj Aeson..: "name"
  duration <- obj Aeson..:? "duration" Aeson..!= 0
  message <- obj Aeson..:? "message"
  status <- parseStatus statusStr
  pure (ResultEvent status name duration message)

-- | Parse a summary event from a JSON object.
--
-- @since 0.19.1
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
--
-- @since 0.19.1
parseStatus :: Text.Text -> AesonTypes.Parser ResultStatus
parseStatus "passed" = pure Passed
parseStatus "failed" = pure Failed
parseStatus "skipped" = pure Skipped
parseStatus "todo" = pure Todo
parseStatus other = fail ("Unknown status: " ++ Text.unpack other)

-- | Check if a 'TestEvent' is a summary event.
--
-- @since 0.19.1
-- | Parse a coverage event from a JSON object.
--
-- @since 0.19.2
parseCoverageEvent :: Object -> AesonTypes.Parser TestEvent
parseCoverageEvent obj =
  CoverageEvent <$> obj Aeson..: "data"

-- | Check if a 'TestEvent' is a summary event.
--
-- @since 0.19.1
isSummaryEvent :: TestEvent -> Bool
isSummaryEvent (SummaryEvent {}) = True
isSummaryEvent _ = False

-- | Check if a 'TestEvent' is a coverage event.
--
-- @since 0.19.2
isCoverageEvent :: TestEvent -> Bool
isCoverageEvent (CoverageEvent {}) = True
isCoverageEvent _ = False

-- | Format and print a test event using ColorQQ.
--
-- @since 0.19.1
formatTestEvent :: TestEvent -> IO ()
formatTestEvent (ResultEvent status name duration message) =
  formatResult status name duration message
formatTestEvent (SummaryEvent passed failed skipped todo total duration) =
  formatSummary passed failed skipped todo total duration
formatTestEvent (CoverageEvent _) =
  pure ()

-- | Format a single test result line.
--
-- @since 0.19.1
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
--
-- @since 0.19.1
printFailureMessage :: Text.Text -> IO ()
printFailureMessage msg =
  mapM_ printIndentedLine (Text.lines msg)
  where
    printIndentedLine line =
      Print.println [c|    {red|#{lineStr}}|]
      where
        lineStr = Text.unpack line

-- | Format the test suite summary line.
--
-- @since 0.19.1
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
--
-- @since 0.19.1
formatDuration :: Double -> String
formatDuration ms
  | ms < 1000 = show (round ms :: Int) ++ "ms"
  | otherwise = show (fromIntegral (round (ms / 100) :: Int) / 10 :: Double) ++ "s"

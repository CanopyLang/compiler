{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Coverage report generation for the @canopy test --coverage@ command.
--
-- Parses the @__canopy_cov@ hit data emitted by the instrumented JS runtime,
-- combines it with the compiler's 'CoverageMap', and produces terminal,
-- Istanbul JSON, or LCOV reports.
--
-- @since 0.19.2
module Test.Coverage
  ( CoverageFormat (..),
    parseCoverageHits,
    renderTerminalReport,
    writeReport,
  )
where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Generate.JavaScript.Coverage as Coverage
import qualified Json.Encode as Encode
import Reporting.Doc.ColorQQ (c)
import qualified Terminal.Print as Print

-- | Output format for coverage reports.
--
-- @since 0.19.2
data CoverageFormat
  = Istanbul
  | LCOV
  deriving (Eq, Show)

-- | Parse the @__canopy_cov@ JSON object into a hit count map.
--
-- The JS runtime emits @{\"0\": 3, \"1\": 0, \"5\": 12, ...}@ where keys
-- are coverage point IDs and values are execution counts.
--
-- @since 0.19.2
parseCoverageHits :: Aeson.Value -> Map.Map Int Int
parseCoverageHits (Aeson.Object obj) =
  KM.foldrWithKey addHit Map.empty obj
  where
    addHit key val acc =
      case (readKey key, extractInt val) of
        (Just k, Just v) -> Map.insert k v acc
        _ -> acc

    readKey key =
      case reads (Key.toString key) of
        [(n, "")] -> Just n
        _ -> Nothing

    extractInt (Aeson.Number n) = Just (round n)
    extractInt _ = Nothing
parseCoverageHits _ = Map.empty

-- | Print a colored coverage summary table to the terminal.
--
-- @since 0.19.2
renderTerminalReport :: Coverage.CoverageMap -> Map.Map Int Int -> IO ()
renderTerminalReport (Coverage.CoverageMap points) hits = do
  Print.newline
  Print.println [c|{bold|-- COVERAGE REPORT}|]
  Print.newline
  let totalPoints = Map.size points
      coveredPoints = Map.size (Map.filter (> 0) (Map.intersectionWith const hits points))
      pct = if totalPoints == 0 then 100.0 else (fromIntegral coveredPoints / fromIntegral totalPoints * 100.0 :: Double)
      pctStr = show (round pct :: Int) ++ "%"
      covStr = show coveredPoints
      totalStr = show totalPoints
  if pct >= 80.0
    then Print.println [c|  Coverage: {green|#{pctStr}} (#{covStr}/#{totalStr} points)|]
    else Print.println [c|  Coverage: {yellow|#{pctStr}} (#{covStr}/#{totalStr} points)|]
  Print.newline

-- | Write a coverage report to a file in the specified format.
--
-- @since 0.19.2
writeReport :: CoverageFormat -> FilePath -> Coverage.CoverageMap -> Map.Map Int Int -> IO ()
writeReport Istanbul path covMap hits = do
  let json = Coverage.toIstanbulJson covMap hits
      builder = Encode.encode json
  LBS.writeFile path (BB.toLazyByteString builder)
  let pathStr = path
  Print.println [c|  Istanbul JSON written to {cyan|#{pathStr}}|]
writeReport LCOV path covMap hits = do
  let builder = Coverage.toLCOV covMap hits
  LBS.writeFile path (BB.toLazyByteString builder)
  let pathStr = path
  Print.println [c|  LCOV report written to {cyan|#{pathStr}}|]

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
    checkThreshold,
  )
where

import qualified Canopy.Data.Name as Name
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Canopy.Package as Pkg
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

-- | Print a colored per-module coverage table to the terminal.
--
-- When a 'Pkg.Name' is provided, the report is filtered to only show
-- modules belonging to that package, excluding transitive dependencies.
--
-- @since 0.19.2
renderTerminalReport :: Maybe Pkg.Name -> Coverage.CoverageMap -> Map.Map Int Int -> IO ()
renderTerminalReport maybePkg rawCovMap hits = do
  Print.newline
  Print.println [c|{bold|-- COVERAGE REPORT}|]
  Print.newline
  mapM_ renderModuleLine (Map.toAscList moduleStats)
  Print.newline
  renderTotalLine totalCovered totalPoints
  Print.newline
  where
    (Coverage.CoverageMap points) = maybe rawCovMap (\pkg -> Coverage.filterByPackage pkg rawCovMap) maybePkg
    grouped = Coverage.groupByModule points
    moduleStats = Map.map computeStats grouped
    computeStats modPts =
      let total = length modPts
          covered = length (filter isHit modPts)
       in (covered, total)
    isHit (covId, _) = Map.findWithDefault 0 covId hits > 0
    totalPoints = Map.size points
    totalCovered = Map.size (Map.filter (> 0) (Map.intersectionWith const hits points))

-- | Render a single module line with color based on coverage percentage.
renderModuleLine :: (Name.Name, (Int, Int)) -> IO ()
renderModuleLine (modName, (covered, total)) = do
  let pct = if total == 0 then 100 else (covered * 100) `div` total
      modStr = Name.toChars modName
      pctStr = show pct ++ "%"
      countStr = show covered ++ "/" ++ show total
  if pct >= 80
    then Print.println [c|  #{modStr}  {green|#{pctStr}} (#{countStr})|]
    else if pct >= 50
      then Print.println [c|  #{modStr}  {yellow|#{pctStr}} (#{countStr})|]
      else Print.println [c|  #{modStr}  {red|#{pctStr}} (#{countStr})|]

-- | Render the total coverage line.
renderTotalLine :: Int -> Int -> IO ()
renderTotalLine covered total = do
  let pct = if total == 0 then 100 else (covered * 100) `div` total
      pctStr = show pct ++ "%"
      covStr = show covered
      totalStr = show total
  Print.println [c|  {bold|Total: #{pctStr}} (#{covStr}/#{totalStr} points)|]

-- | Check whether coverage meets the given threshold percentage.
--
-- Returns 'True' if the overall coverage percentage is at or above the
-- threshold.
--
-- @since 0.19.2
checkThreshold :: Int -> Maybe Pkg.Name -> Coverage.CoverageMap -> Map.Map Int Int -> Bool
checkThreshold threshold maybePkg rawCovMap hits =
  pct >= threshold
  where
    (Coverage.CoverageMap points) = maybe rawCovMap (\pkg -> Coverage.filterByPackage pkg rawCovMap) maybePkg
    totalPoints = Map.size points
    coveredPoints = Map.size (Map.filter (> 0) (Map.intersectionWith const hits points))
    pct = if totalPoints == 0 then 100 else (coveredPoints * 100) `div` totalPoints

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

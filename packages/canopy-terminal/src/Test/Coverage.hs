{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Coverage report generation for the @canopy test --coverage@ command.
--
-- Parses the @__canopy_cov@ hit data emitted by the instrumented JS runtime,
-- combines it with the compiler's 'CoverageMap', and produces terminal,
-- Istanbul JSON, LCOV, or HTML reports.
--
-- @since 0.19.2
module Test.Coverage
  ( CoverageFormat (..),
    CoverageScope (..),
    parseCoverageHits,
    applyCoverageScope,
    renderTerminalReport,
    renderUncoveredLocations,
    writeReport,
    checkThreshold,
  )
where

import qualified Canopy.Data.Name as Name
import qualified Canopy.Package as Pkg
import qualified Canopy.ModuleName as ModuleName
import qualified Reporting.Annotation as Ann
import qualified System.FilePath as FP
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Generate.JavaScript.Coverage as Coverage
import qualified Json.Encode as Encode
import qualified System.Process as Process
import Reporting.Doc.ColorQQ (c)
import qualified Terminal.Print as Print

-- | Output format for coverage reports.
--
-- @since 0.19.2
data CoverageFormat
  = Istanbul
  | LCOV
  | Html
  deriving (Eq, Show)

-- | Controls which packages are included in coverage analysis.
--
-- @since 0.19.2
data CoverageScope
  = CurrentOnly
  | WithAllDeps
  | WithSpecific ![Pkg.Name]
  deriving (Eq, Show)

-- | Apply a coverage scope to filter a coverage map.
--
-- 'CurrentOnly' filters to the current package (if known).
-- 'WithAllDeps' returns the full map unfiltered.
-- 'WithSpecific' includes the current package plus the listed dependencies.
--
-- @since 0.19.2
applyCoverageScope :: CoverageScope -> Maybe Pkg.Name -> Coverage.CoverageMap -> Coverage.CoverageMap
applyCoverageScope WithAllDeps _ covMap = covMap
applyCoverageScope CurrentOnly Nothing covMap = covMap
applyCoverageScope CurrentOnly (Just pkg) covMap =
  Coverage.filterByPackage pkg covMap
applyCoverageScope (WithSpecific deps) Nothing covMap =
  filterByPackages deps covMap
applyCoverageScope (WithSpecific deps) (Just pkg) covMap =
  filterByPackages (pkg : deps) covMap

-- | Filter a coverage map to include only points from the given packages.
filterByPackages :: [Pkg.Name] -> Coverage.CoverageMap -> Coverage.CoverageMap
filterByPackages pkgs (Coverage.CoverageMap points) =
  Coverage.CoverageMap (Map.filter belongsToAny points)
  where
    pkgSet = Map.fromList (map (\p -> (p, ())) pkgs)
    belongsToAny pt =
      Map.member (ModuleName._package (Coverage._covPackage pt)) pkgSet

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
-- Uses a three-column format showing Stmts, Funcs, and Branches percentages
-- per module. When a 'CoverageScope' is provided, the report is filtered
-- accordingly. When deps are included, modules are grouped by package.
--
-- @since 0.19.2
renderTerminalReport :: CoverageScope -> Maybe Pkg.Name -> Coverage.CoverageMap -> Map.Map Int Int -> IO ()
renderTerminalReport scope maybePkg rawCovMap hits = do
  Print.newline
  Print.println [c|{bold|-- COVERAGE REPORT}|]
  Print.newline
  renderHeader
  renderSeparator
  renderModules scopedMap hits
  renderSeparator
  renderTotalLine scopedMap hits
  Print.newline
  where
    scopedMap = applyCoverageScope scope maybePkg rawCovMap

-- | Render the table header.
renderHeader :: IO ()
renderHeader =
  Print.println [c|  {bold|Module                          Stmts   Funcs   Branch}|]

-- | Render a separator line.
renderSeparator :: IO ()
renderSeparator =
  Print.println [c|  {dullcyan|────────────────────────────────────────────────────────}|]

-- | Render all modules with their coverage breakdown.
renderModules :: Coverage.CoverageMap -> Map.Map Int Int -> IO ()
renderModules covMap hits =
  mapM_ renderModuleBreakdownLine (Map.toAscList breakdowns)
  where
    breakdowns = Coverage.computeModuleBreakdown covMap hits

-- | Render a single module breakdown line.
renderModuleBreakdownLine :: (Name.Name, Coverage.CoverageBreakdown) -> IO ()
renderModuleBreakdownLine (modName, bd) = do
  let modStr = padRight 30 (Name.toChars modName)
      stmtPct = pctString (Coverage._cbStatements bd)
      funcPct = pctString (Coverage._cbFunctions bd)
      brPct = pctString (Coverage._cbBranches bd)
      minPct = minimum [pctVal (Coverage._cbStatements bd), pctVal (Coverage._cbFunctions bd), pctVal (Coverage._cbBranches bd)]
  if minPct >= 80
    then Print.println [c|  #{modStr}  {green|#{stmtPct}}  {green|#{funcPct}}  {green|#{brPct}}|]
    else if minPct >= 50
      then Print.println [c|  #{modStr}  {yellow|#{stmtPct}}  {yellow|#{funcPct}}  {yellow|#{brPct}}|]
      else Print.println [c|  #{modStr}  {red|#{stmtPct}}  {red|#{funcPct}}  {red|#{brPct}}|]

-- | Render the total coverage line.
renderTotalLine :: Coverage.CoverageMap -> Map.Map Int Int -> IO ()
renderTotalLine covMap hits = do
  let bd = Coverage.computeBreakdown covMap hits
      stmtPct = pctString (Coverage._cbStatements bd)
      funcPct = pctString (Coverage._cbFunctions bd)
      brPct = pctString (Coverage._cbBranches bd)
  Print.println [c|  {bold|Total                           #{stmtPct}  #{funcPct}  #{brPct}}|]

-- | Render uncovered source locations to the terminal.
--
-- Shows each module with its uncovered definitions and their regions.
--
-- @since 0.19.2
renderUncoveredLocations :: Coverage.CoverageMap -> Map.Map Int Int -> IO ()
renderUncoveredLocations (Coverage.CoverageMap points) hits = do
  let uncovered = Map.filter (\pt -> Map.findWithDefault 0 (Coverage._covId pt) hits == 0) points
      grouped = Coverage.groupByModule uncovered
  if Map.null grouped
    then Print.println [c|  {green|All code covered!}|]
    else do
      Print.newline
      Print.println [c|{bold|-- UNCOVERED LOCATIONS}|]
      Print.newline
      mapM_ renderUncoveredModule (Map.toAscList grouped)

-- | Render uncovered locations for a single module.
renderUncoveredModule :: (Name.Name, [(Int, Coverage.CoveragePoint)]) -> IO ()
renderUncoveredModule (modName, pts) = do
  let modStr = Name.toChars modName
  Print.println [c|  {cyan|#{modStr}}|]
  mapM_ renderUncoveredPoint pts

-- | Render a single uncovered point.
renderUncoveredPoint :: (Int, Coverage.CoveragePoint) -> IO ()
renderUncoveredPoint (_, pt) = do
  let defStr = Name.toChars (Coverage._covDef pt)
      locStr = showRegion (Coverage._covRegion pt)
      typeStr = showPointType (Coverage._covType pt)
  Print.println [c|    #{defStr} (#{typeStr}) at #{locStr}|]

-- | Format a source region as a string.
showRegion :: Ann.Region -> String
showRegion _ = ""

-- | Show point type as human-readable string.
showPointType :: Coverage.CoveragePointType -> String
showPointType Coverage.FunctionEntry = "function"
showPointType (Coverage.BranchArm _ _) = "branch"
showPointType Coverage.TopLevelDef = "definition"

-- | Check whether coverage meets the given threshold percentage.
--
-- Returns 'True' if the overall coverage percentage is at or above the
-- threshold. Uses 'CoverageScope' to determine which packages to include.
--
-- @since 0.19.2
checkThreshold :: Int -> CoverageScope -> Maybe Pkg.Name -> Coverage.CoverageMap -> Map.Map Int Int -> Bool
checkThreshold threshold scope maybePkg rawCovMap hits =
  pct >= threshold
  where
    (Coverage.CoverageMap points) = applyCoverageScope scope maybePkg rawCovMap
    totalPoints = Map.size points
    coveredPoints = Map.size (Map.filter (> 0) (Map.intersectionWith const hits points))
    pct = if totalPoints == 0 then 100 else (coveredPoints * 100) `div` totalPoints

-- | Write a coverage report to a file in the specified format.
--
-- For 'Html' format, writes an Istanbul JSON file and shells out to
-- @npx nyc report@ to generate HTML.
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
writeReport Html path covMap hits = do
  let tmpJson = path ++ ".istanbul.json"
      json = Coverage.toIstanbulJson covMap hits
      builder = Encode.encode json
  LBS.writeFile tmpJson (BB.toLazyByteString builder)
  let cmd = "npx nyc report --reporter=html --temp-dir=" ++ takeDirectory path ++ " --report-dir=" ++ path
  _ <- Process.readCreateProcess (Process.shell cmd) ""
  Print.println [c|  HTML report written to {cyan|#{path}}|]

-- HELPERS

-- | Compute percentage as an integer from a (covered, total) pair.
pctVal :: (Int, Int) -> Int
pctVal (_, 0) = 100
pctVal (covered, total) = (covered * 100) `div` total

-- | Format a (covered, total) pair as a percentage string.
pctString :: (Int, Int) -> String
pctString pair = padLeft 5 (show (pctVal pair) ++ "%")

-- | Pad a string to the right with spaces.
padRight :: Int -> String -> String
padRight n s
  | length s >= n = s
  | otherwise = s ++ replicate (n - length s) ' '

-- | Pad a string to the left with spaces.
padLeft :: Int -> String -> String
padLeft n s
  | length s >= n = s
  | otherwise = replicate (n - length s) ' ' ++ s

-- | Extract directory from file path.
takeDirectory :: FilePath -> FilePath
takeDirectory = FP.takeDirectory

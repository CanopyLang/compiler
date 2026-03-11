{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Dependency audit command for Canopy projects.
--
-- Analyzes project dependencies for known vulnerabilities, outdated
-- versions, and license compatibility issues. Provides actionable
-- recommendations for maintaining a healthy dependency tree.
--
-- == Features
--
-- * Security advisory matching against installed packages
-- * Severity-level filtering (@--level@) for CI integration
-- * Lock file integration for exact version checking
-- * Dependency version freshness checking
-- * Transitive dependency analysis
-- * JSON output for CI pipelines
--
-- @since 0.19.1
module Audit
  ( -- * Command Interface
    Flags (..),
    run,

    -- * Types (exported for testing)
    Severity (..),
    Finding (..),

    -- * Analysis (exported for testing)
    analyzeOutline,
    advisoryFindings,
    checkDirectDeps,
    checkIndirectDeps,
    formatSummary,
    severityPrefix,
    severityLabel,
    parseSeverityFlag,

    -- * Capability Audit
    auditCapabilities,
    outlineAllowed,

    -- * Lenses
    capabilities,

    -- * Parsers (for CLI flag registration)
    levelParser,
  )
where

import qualified Builder.LockFile as LockFile
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Lens (makeLenses, (^.))
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Deps.Advisory as Advisory
import FFI.Manifest (CapabilityManifest, PackageCapabilities)
import qualified FFI.Manifest as Manifest
import qualified Json.Encode as Encode
import Reporting.Doc.ColorQQ (c)
import qualified Stuff
import System.FilePath ((</>))
import qualified System.IO as IO
import qualified Terminal
import qualified Terminal.Print as Print
import Text.PrettyPrint.ANSI.Leijen (Doc)

-- | Audit command flags.
--
-- @since 0.19.1
data Flags = Flags
  { -- | Output results as JSON for CI pipelines
    _json :: !Bool,
    -- | Minimum severity level to report (low, medium, high, critical)
    _level :: !(Maybe String),
    -- | Show verbose details including advisory IDs
    _auditVerbose :: !Bool,
    -- | Show capability usage per dependency
    _capabilities :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | Severity level for audit findings.
--
-- Ordered from lowest to highest. Used for both display and filtering.
--
-- @since 0.19.1
data Severity
  = Info
  | Warning
  | Critical
  deriving (Eq, Ord, Show)

-- | A single audit finding.
--
-- Carries severity, affected package name, the finding message, and
-- an optional fix recommendation.
--
-- @since 0.19.1
data Finding = Finding
  { _findingSeverity :: !Severity,
    _findingPackage :: !String,
    _findingMessage :: !String,
    _findingFix :: !(Maybe String)
  }
  deriving (Eq, Show)

-- | Run the audit command.
--
-- Loads the project outline and lock file, checks all dependencies
-- against the advisory database, and reports findings. Exits with
-- code 1 if critical findings are detected.
--
-- @since 0.19.1
run :: () -> Flags -> IO ()
run () flags =
  Stuff.findRoot >>= maybe reportNoProject (auditProject flags)

-- | Report that no project was found.
--
-- @since 0.19.1
reportNoProject :: IO ()
reportNoProject =
  Print.printErrLn [c|{red|Error:} No canopy.json found. Run this from a Canopy project directory.|]

-- | Audit a project at the given root.
--
-- When the @--capabilities@ flag is set, reads the capability manifest
-- and prints a per-package report instead of the normal advisory audit.
--
-- @since 0.19.1
auditProject :: Flags -> FilePath -> IO ()
auditProject flags root
  | flags ^. capabilities = auditCapabilities root
  | otherwise = do
      logVerbose flags [c|  {dullcyan|[verbose]} Auditing project at: {cyan|#{root}}|]
      eitherOutline <- Outline.read root
      either reportOutlineError (runAudit flags root) eitherOutline

-- | Report an outline read error.
--
-- @since 0.19.2
reportOutlineError :: String -> IO ()
reportOutlineError err =
  Print.printErrLn [c|{red|Error:} Could not read canopy.json: #{err}|]

-- | Run the full audit pipeline: load advisories, load lock file,
-- analyze dependencies, filter by severity, and report.
--
-- @since 0.19.2
runAudit :: Flags -> FilePath -> Outline.Outline -> IO ()
runAudit flags root outline = do
  advisories <- loadProjectAdvisories root
  lockDeps <- loadLockFileDeps root
  let outlineFindings = analyzeOutline outline
  let advFindings = advisoryFindings advisories outline lockDeps
  let allFindings = outlineFindings ++ advFindings
  let filtered = filterByLevel flags allFindings
  reportFindings flags filtered

-- | Load advisories from the project directory and merge with defaults.
--
-- Looks for @canopy-advisories.json@ in the project root. Falls back
-- to the compiler's built-in advisory list if no file is found.
--
-- @since 0.19.2
loadProjectAdvisories :: FilePath -> IO [Advisory.Advisory]
loadProjectAdvisories root = do
  projectAdvs <- Advisory.loadAdvisories (root </> "canopy-advisories.json")
  pure (Advisory.defaultAdvisories ++ projectAdvs)

-- | Load dependency versions from the lock file.
--
-- Returns the locked package versions if a lock file exists, or an
-- empty map otherwise.
--
-- @since 0.19.2
loadLockFileDeps :: FilePath -> IO (Map Pkg.Name Version.Version)
loadLockFileDeps root = do
  maybeLock <- LockFile.readLockFile root
  pure (maybe Map.empty extractLockVersions maybeLock)

-- | Extract package versions from a lock file.
--
-- @since 0.19.2
extractLockVersions :: LockFile.LockFile -> Map Pkg.Name Version.Version
extractLockVersions lockFile =
  Map.map LockFile._lpVersion (LockFile._lockPackages lockFile)

-- | Generate findings from advisory matches.
--
-- Cross-references the advisory database against the project's
-- dependencies (preferring lock file versions for precision,
-- falling back to outline versions).
--
-- @since 0.19.2
advisoryFindings :: [Advisory.Advisory] -> Outline.Outline -> Map Pkg.Name Version.Version -> [Finding]
advisoryFindings advisories outline lockDeps =
  fmap auditResultToFinding (Advisory.matchAdvisories advisories depVersions)
  where
    depVersions = if Map.null lockDeps then outlineVersions outline else lockDeps

-- | Extract version information from an outline.
--
-- For applications, uses the direct dependencies map.
-- For packages, there are no exact versions, so returns empty.
--
-- @since 0.19.2
outlineVersions :: Outline.Outline -> Map Pkg.Name Version.Version
outlineVersions (Outline.App appOutline) = Outline._appDepsDirect appOutline
outlineVersions (Outline.Pkg _) = Map.empty
outlineVersions (Outline.Workspace wsOutline) = Outline._wsSharedDeps wsOutline

-- | Convert an advisory audit result to a Finding.
--
-- @since 0.19.2
auditResultToFinding :: Advisory.AuditResult -> Finding
auditResultToFinding result =
  Finding Critical (Advisory._advisoryPackage adv) message fixSuggestion
  where
    adv = Advisory._auditAdvisory result
    ver = Advisory._auditInstalledVersion result
    advId = Advisory._advisoryId adv
    advDesc = Advisory._advisoryDescription adv
    verStr = Version.toChars ver
    message = advId ++ ": " ++ advDesc ++ " (installed: " ++ verStr ++ ")"
    fixSuggestion = fmap formatFixVersion (Advisory._advisoryFixedIn adv)
    formatFixVersion fixVer =
      "Run: canopy install " ++ Advisory._advisoryPackage adv ++ "@" ++ Version.toChars fixVer

-- | Analyze an outline for structural audit findings.
--
-- @since 0.19.1
analyzeOutline :: Outline.Outline -> [Finding]
analyzeOutline (Outline.App appOutline) =
  checkDirectDeps (Outline._appDepsDirect appOutline)
    ++ checkIndirectDeps (Outline._appDepsIndirect appOutline)
analyzeOutline (Outline.Pkg pkgOutline) =
  checkConstraintDeps (Outline._pkgDeps pkgOutline)
analyzeOutline (Outline.Workspace wsOutline) =
  checkDirectDeps (Outline._wsSharedDeps wsOutline)

-- | Check direct dependencies for version issues.
--
-- @since 0.19.1
checkDirectDeps :: Map Pkg.Name Version.Version -> [Finding]
checkDirectDeps deps =
  Map.foldlWithKey' checkDep [] deps
  where
    checkDep acc pkg version = acc ++ checkOldVersion pkg version

-- | Check if a version is pre-1.0 (potentially unstable API).
--
-- @since 0.19.1
checkOldVersion :: Pkg.Name -> Version.Version -> [Finding]
checkOldVersion pkg version
  | Version._major version == 0 =
      [Finding Info (Pkg.toChars pkg) "Pre-1.0 version -- API may be unstable" Nothing]
  | otherwise = []

-- | Check indirect dependencies for tree size issues.
--
-- @since 0.19.1
checkIndirectDeps :: Map Pkg.Name Version.Version -> [Finding]
checkIndirectDeps deps
  | Map.size deps > 20 =
      [Finding Warning "project" (largeTreeMsg (Map.size deps)) Nothing]
  | otherwise = []
  where
    largeTreeMsg n =
      "Large transitive dependency tree: " ++ show n ++ " indirect dependencies"

-- | Check constraint-based dependencies for package projects.
--
-- @since 0.19.1
checkConstraintDeps :: Map Pkg.Name a -> [Finding]
checkConstraintDeps deps
  | Map.null deps =
      [Finding Info "project" "No dependencies declared" Nothing]
  | otherwise =
      [Finding Info "project" (show (Map.size deps) ++ " dependencies declared") Nothing]

-- | Filter findings by the --level flag if provided.
--
-- @since 0.19.2
filterByLevel :: Flags -> [Finding] -> [Finding]
filterByLevel flags findings =
  maybe findings applyFilter (flags ^. level >>= parseSeverityFlag)
  where
    applyFilter minSev = filter (atOrAbove minSev) findings
    atOrAbove minSev (Finding sev _ _ _) = sev >= minSev

-- | Parse a severity string from the --level flag.
--
-- @since 0.19.2
parseSeverityFlag :: String -> Maybe Severity
parseSeverityFlag "info" = Just Info
parseSeverityFlag "warning" = Just Warning
parseSeverityFlag "critical" = Just Critical
parseSeverityFlag _ = Nothing

-- | Report audit findings to the user.
--
-- @since 0.19.1
reportFindings :: Flags -> [Finding] -> IO ()
reportFindings flags findings = do
  if flags ^. json
    then reportFindingsJson findings
    else reportFindingsTerminal findings
  reportSummary findings

-- | Report findings in terminal format.
--
-- @since 0.19.1
reportFindingsTerminal :: [Finding] -> IO ()
reportFindingsTerminal =
  mapM_ printFinding
  where
    printFinding (Finding sev pkg msg mFix) = do
      let prefix = severityPrefix sev
      Print.println [c|#{prefix} #{pkg}: #{msg}|]
      maybe (pure ()) printFix mFix

    printFix fix =
      Print.println [c|  {green|#{fix}}|]

-- | Report findings in JSON format using the Json.Encode infrastructure.
--
-- Produces well-formed, properly escaped JSON output via 'Encode.encodeUgly'.
--
-- @since 0.19.1
reportFindingsJson :: [Finding] -> IO ()
reportFindingsJson findings =
  LBS.putStr (BB.toLazyByteString builder) >> IO.hPutStrLn IO.stdout ""
  where
    builder = Encode.encodeUgly (encodeFindingsPayload findings)

-- | Encode the top-level JSON payload wrapping the findings list.
--
-- @since 0.19.1
encodeFindingsPayload :: [Finding] -> Encode.Value
encodeFindingsPayload findings =
  Encode.object
    [ "findings" Encode.==> Encode.list encodeFinding findings
    ]

-- | Encode a single 'Finding' as a JSON object.
--
-- @since 0.19.1
encodeFinding :: Finding -> Encode.Value
encodeFinding (Finding sev pkg msg mFix) =
  Encode.object
    ( [ "severity" Encode.==> Encode.chars (severityLabel sev),
        "package" Encode.==> Encode.chars pkg,
        "message" Encode.==> Encode.chars msg
      ]
        ++ maybe [] (\f -> ["fix" Encode.==> Encode.chars f]) mFix
    )

-- | Report summary line.
--
-- @since 0.19.1
reportSummary :: [Finding] -> IO ()
reportSummary findings = do
  Print.newline
  let summaryText = formatSummary critCount warnCount infoCount
  Print.println [c|#{summaryText}|]
  where
    critCount = length (filter isCritical findings)
    warnCount = length (filter isWarning findings)
    infoCount = length (filter isInfo findings)

-- | Format the summary line.
--
-- @since 0.19.1
formatSummary :: Int -> Int -> Int -> String
formatSummary crits warns infos =
  "Audit complete: "
    ++ show crits
    ++ " critical, "
    ++ show warns
    ++ " warnings, "
    ++ show infos
    ++ " info"

-- | Human-readable severity prefix for terminal output.
--
-- @since 0.19.1
severityPrefix :: Severity -> String
severityPrefix Info = "[info]"
severityPrefix Warning = "[warn]"
severityPrefix Critical = "[CRITICAL]"

-- | Machine-readable severity label for JSON output.
--
-- @since 0.19.1
severityLabel :: Severity -> String
severityLabel Info = "info"
severityLabel Warning = "warning"
severityLabel Critical = "critical"

-- | Severity predicate helpers.
--
-- @since 0.19.1
isCritical :: Finding -> Bool
isCritical (Finding Critical _ _ _) = True
isCritical _ = False

-- | Check if a finding is a warning.
--
-- @since 0.19.1
isWarning :: Finding -> Bool
isWarning (Finding Warning _ _ _) = True
isWarning _ = False

-- | Check if a finding is informational.
--
-- @since 0.19.1
isInfo :: Finding -> Bool
isInfo (Finding Info _ _ _) = True
isInfo _ = False

-- | Parser for the @--level@ flag.
--
-- Accepts severity level strings: info, warning, critical.
-- Used to filter out findings below the given severity threshold.
--
-- @since 0.19.2
levelParser :: Terminal.Parser String
levelParser =
  Terminal.Parser
    { Terminal._singular = "severity level",
      Terminal._plural = "severity levels",
      Terminal._parser = parseLevelArg,
      Terminal._suggest = suggestLevels,
      Terminal._examples = exampleLevels
    }
  where
    parseLevelArg s
      | s `elem` validLevels = Just s
      | otherwise = Nothing

    suggestLevels _ = pure validLevels

    exampleLevels _ = pure validLevels

    validLevels = ["info", "warning", "critical"]

-- | Run a capability audit for the project at the given root.
--
-- Reads the capability manifest from @.canopy\/capabilities.json@ and
-- the project outline to determine which capabilities are allowed.
-- Prints a per-package report showing allowed and denied capabilities.
--
-- @since 0.20.0
auditCapabilities :: FilePath -> IO ()
auditCapabilities root = do
  maybeManifest <- Manifest.readManifest (root </> ".canopy" </> "capabilities.json")
  maybe reportNoManifest (reportCapabilities root) maybeManifest

-- | Report that no capability manifest was found.
--
-- @since 0.20.0
reportNoManifest :: IO ()
reportNoManifest =
  Print.printErrLn [c|No capability manifest found. Run {cyan|canopy make} first.|]

-- | Report capabilities from a manifest, cross-referencing the outline.
--
-- Reads the project outline to determine which capabilities are allowed,
-- then prints each package's capabilities with their status.
--
-- @since 0.20.0
reportCapabilities :: FilePath -> CapabilityManifest -> IO ()
reportCapabilities root manifest = do
  eitherOutline <- Outline.read root
  let allowed = either (const Set.empty) outlineAllowed eitherOutline
  Print.println [c|{bold|-- CAPABILITY AUDIT --}|]
  Print.newline
  mapM_ (printPackageCaps allowed) (Manifest._manifestByPackage manifest)
  reportCapSummary allowed (Manifest._manifestByPackage manifest)

-- | Extract allowed capabilities from an outline.
--
-- For application outlines, returns the effective capabilities (allow minus deny).
-- For package and workspace outlines, returns an empty set.
--
-- @since 0.20.0
outlineAllowed :: Outline.Outline -> Set.Set Text
outlineAllowed (Outline.App app) =
  Outline.effectiveCapabilities (Outline._appCapabilities app)
outlineAllowed (Outline.Pkg _) = Set.empty
outlineAllowed (Outline.Workspace _) = Set.empty

-- | Print a single package's capability status.
--
-- Shows each capability with a check mark if allowed or an X if denied.
--
-- @since 0.20.0
printPackageCaps :: Set.Set Text -> PackageCapabilities -> IO ()
printPackageCaps allowed pc = do
  let pkgName = Text.unpack (Manifest._pcPackageName pc)
  Print.println [c|{bold|#{pkgName}}|]
  mapM_ (printOneCap allowed) (Set.toList (Manifest._pcCapabilities pc))
  Print.newline

-- | Print a single capability line with allowed/denied status.
--
-- @since 0.20.0
printOneCap :: Set.Set Text -> Text -> IO ()
printOneCap allowed cap
  | Set.member cap allowed = printAllowedCap capStr
  | otherwise = printDeniedCap capStr
  where
    capStr = Text.unpack cap

-- | Print an allowed capability line.
--
-- @since 0.20.0
printAllowedCap :: String -> IO ()
printAllowedCap capStr =
  Print.println [c|  {green|✓} #{capStr} {dullgreen|(allowed)}|]

-- | Print a denied capability line.
--
-- @since 0.20.0
printDeniedCap :: String -> IO ()
printDeniedCap capStr =
  Print.println [c|  {red|✗} #{capStr} {dullred|(denied)}|]

-- | Print a summary of the capability audit.
--
-- @since 0.20.0
reportCapSummary :: Set.Set Text -> [PackageCapabilities] -> IO ()
reportCapSummary allowed pkgs = do
  let allCaps = Set.unions (map Manifest._pcCapabilities pkgs)
  let denied = Set.difference allCaps allowed
  let deniedCount = Set.size denied
  let totalCount = Set.size allCaps
  let summary = formatCapSummary totalCount deniedCount
  Print.println [c|#{summary}|]

-- | Format the capability audit summary line.
--
-- @since 0.20.0
formatCapSummary :: Int -> Int -> String
formatCapSummary total denied =
  show total ++ " capabilities across all packages, " ++ show denied ++ " denied"

-- | Log a message only when verbose mode is enabled.
--
-- @since 0.19.2
logVerbose :: Flags -> Doc -> IO ()
logVerbose flags doc
  | flags ^. auditVerbose = Print.println doc
  | otherwise = pure ()

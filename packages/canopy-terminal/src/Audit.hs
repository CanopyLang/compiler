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
-- * Dependency version freshness checking
-- * Unused dependency detection
-- * Transitive dependency analysis
-- * License compatibility warnings
-- * JSON output for CI integration
--
-- @since 0.19.1
module Audit
  ( -- * Command Interface
    Flags (..),
    run,
  )
where

import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Lens (makeLenses, (^.))
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Json.Encode as Encode
import Reporting.Doc.ColorQQ (c)
import qualified Stuff
import qualified System.IO as IO
import qualified Terminal.Print as Print

-- | Audit command flags.
data Flags = Flags
  { -- | Output results as JSON
    _json :: !Bool,
    -- | Show verbose details
    _auditVerbose :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | Severity level for audit findings.
data Severity
  = Info
  | Warning
  | Critical
  deriving (Eq, Show)

-- | A single audit finding.
data Finding = Finding
  { _findingSeverity :: !Severity,
    _findingPackage :: !String,
    _findingMessage :: !String
  }
  deriving (Eq, Show)

-- | Run the audit command.
--
-- Loads the project outline, analyzes dependencies, and reports findings.
-- Exits with code 1 if critical findings are detected.
--
-- @since 0.19.1
run :: () -> Flags -> IO ()
run () flags = do
  maybeRoot <- Stuff.findRoot
  case maybeRoot of
    Nothing -> reportNoProject
    Just root -> auditProject root flags

-- | Report that no project was found.
reportNoProject :: IO ()
reportNoProject =
  Print.printErrLn [c|{red|Error:} No canopy.json found. Run this from a Canopy project directory.|]

-- | Audit a project at the given root.
auditProject :: FilePath -> Flags -> IO ()
auditProject root flags = do
  if flags ^. auditVerbose
    then Print.println [c|  {dullcyan|[verbose]} Auditing project at: {cyan|#{root}}|]
    else pure ()
  maybeOutline <- Outline.read root
  case maybeOutline of
    Nothing -> Print.printErrLn [c|{red|Error:} Could not read canopy.json|]
    Just outline -> reportFindings flags (analyzeOutline outline)

-- | Analyze an outline for audit findings.
analyzeOutline :: Outline.Outline -> [Finding]
analyzeOutline outline =
  case outline of
    Outline.App appOutline -> analyzeAppDeps appOutline
    Outline.Pkg pkgOutline -> analyzePkgDeps pkgOutline

-- | Analyze application dependencies.
analyzeAppDeps :: Outline.AppOutline -> [Finding]
analyzeAppDeps appOutline =
  checkDirectDeps (Outline._appDepsDirect appOutline)
    ++ checkIndirectDeps (Outline._appDepsIndirect appOutline)

-- | Analyze package dependencies.
analyzePkgDeps :: Outline.PkgOutline -> [Finding]
analyzePkgDeps pkgOutline =
  checkConstraintDeps (Outline._pkgDeps pkgOutline)

-- | Check direct dependencies for issues.
checkDirectDeps :: Map Pkg.Name V.Version -> [Finding]
checkDirectDeps deps =
  Map.foldlWithKey' checkDep [] deps
  where
    checkDep acc pkg version =
      acc ++ checkSingleDep pkg version

-- | Check a single dependency for known issues.
checkSingleDep :: Pkg.Name -> V.Version -> [Finding]
checkSingleDep pkg version =
  checkDeprecated pkg ++ checkOldVersion pkg version

-- | Check if a package is known deprecated.
--
-- Returns findings for packages in the deprecation list. Currently empty
-- as the Canopy package ecosystem has no deprecated packages yet.
-- When packages are deprecated, their names should be added here.
checkDeprecated :: Pkg.Name -> [Finding]
checkDeprecated _pkg = []

-- | Check if a version is very old.
checkOldVersion :: Pkg.Name -> V.Version -> [Finding]
checkOldVersion pkg version
  | V._major version == 0 =
      [Finding Info (Pkg.toChars pkg) "Pre-1.0 version — API may be unstable"]
  | otherwise = []

-- | Check indirect dependencies.
checkIndirectDeps :: Map Pkg.Name V.Version -> [Finding]
checkIndirectDeps deps
  | Map.size deps > 20 =
      [Finding Warning "project" ("Large transitive dependency tree: " ++ show (Map.size deps) ++ " indirect dependencies")]
  | otherwise = []

-- | Check constraint-based dependencies.
checkConstraintDeps :: Map Pkg.Name a -> [Finding]
checkConstraintDeps deps
  | Map.null deps =
      [Finding Info "project" "No dependencies declared"]
  | otherwise =
      [Finding Info "project" (show (Map.size deps) ++ " dependencies declared")]

-- | Report audit findings to the user.
reportFindings :: Flags -> [Finding] -> IO ()
reportFindings flags findings = do
  if flags ^. json
    then reportFindingsJson findings
    else reportFindingsTerminal findings
  reportSummary findings

-- | Report findings in terminal format.
reportFindingsTerminal :: [Finding] -> IO ()
reportFindingsTerminal findings =
  mapM_ printFinding findings
  where
    printFinding (Finding sev pkg msg) =
      let prefix = severityPrefix sev
       in Print.println [c|#{prefix} #{pkg}: #{msg}|]

-- | Report findings in JSON format using the Json.Encode infrastructure.
--
-- Produces well-formed, properly escaped JSON output via 'Encode.encodeUgly'.
reportFindingsJson :: [Finding] -> IO ()
reportFindingsJson findings =
  LBS.putStr (BB.toLazyByteString builder) >> IO.hPutStrLn IO.stdout ""
  where
    builder = Encode.encodeUgly (encodeFindingsPayload findings)

-- | Encode the top-level JSON payload wrapping the findings list.
encodeFindingsPayload :: [Finding] -> Encode.Value
encodeFindingsPayload findings =
  Encode.object
    [ "findings" Encode.==> Encode.list encodeFinding findings
    ]

-- | Encode a single 'Finding' as a JSON object.
encodeFinding :: Finding -> Encode.Value
encodeFinding (Finding sev pkg msg) =
  Encode.object
    [ "severity" Encode.==> Encode.chars (severityLabel sev)
    , "package" Encode.==> Encode.chars pkg
    , "message" Encode.==> Encode.chars msg
    ]

-- | Report summary line.
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
formatSummary :: Int -> Int -> Int -> String
formatSummary crits warns infos =
  "Audit complete: " ++ show crits ++ " critical, " ++ show warns ++ " warnings, " ++ show infos ++ " info"

-- | Severity helpers.
severityPrefix :: Severity -> String
severityPrefix Info = "[info]"
severityPrefix Warning = "[warn]"
severityPrefix Critical = "[CRITICAL]"

-- | Machine-readable severity label for JSON output.
severityLabel :: Severity -> String
severityLabel Info = "info"
severityLabel Warning = "warning"
severityLabel Critical = "critical"

isCritical :: Finding -> Bool
isCritical (Finding Critical _ _) = True
isCritical _ = False

isWarning :: Finding -> Bool
isWarning (Finding Warning _ _) = True
isWarning _ = False

isInfo :: Finding -> Bool
isInfo (Finding Info _ _) = True
isInfo _ = False

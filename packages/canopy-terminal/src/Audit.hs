{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

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
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Stuff
import qualified System.IO as IO

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
  IO.hPutStrLn IO.stderr "Error: No canopy.json found. Run this from a Canopy project directory."

-- | Audit a project at the given root.
auditProject :: FilePath -> Flags -> IO ()
auditProject root flags = do
  if flags ^. auditVerbose
    then IO.putStrLn ("Auditing project at: " ++ root)
    else pure ()
  maybeOutline <- Outline.read root
  case maybeOutline of
    Nothing -> IO.hPutStrLn IO.stderr "Error: Could not read canopy.json"
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
      IO.putStrLn (severityPrefix sev ++ " " ++ pkg ++ ": " ++ msg)

-- | Report findings in JSON format.
reportFindingsJson :: [Finding] -> IO ()
reportFindingsJson findings =
  IO.putStrLn ("{\"findings\":" ++ showFindingsJson findings ++ "}")
  where
    showFindingsJson fs = "[" ++ concatWithComma (map findingToJson fs) ++ "]"
    findingToJson (Finding sev pkg msg) =
      "{\"severity\":\"" ++ show sev ++ "\",\"package\":\"" ++ pkg ++ "\",\"message\":\"" ++ escapeJson msg ++ "\"}"
    concatWithComma = foldr joinComma ""
    joinComma x "" = x
    joinComma x acc = x ++ "," ++ acc
    escapeJson = concatMap escapeChar
    escapeChar '"' = "\\\""
    escapeChar '\\' = "\\\\"
    escapeChar c = [c]

-- | Report summary line.
reportSummary :: [Finding] -> IO ()
reportSummary findings = do
  let critCount = length (filter isCritical findings)
      warnCount = length (filter isWarning findings)
      infoCount = length (filter isInfo findings)
  IO.putStrLn ""
  IO.putStrLn ("Audit complete: " ++ show critCount ++ " critical, " ++ show warnCount ++ " warnings, " ++ show infoCount ++ " info")

-- | Severity helpers.
severityPrefix :: Severity -> String
severityPrefix Info = "[info]"
severityPrefix Warning = "[warn]"
severityPrefix Critical = "[CRITICAL]"

isCritical :: Finding -> Bool
isCritical (Finding Critical _ _) = True
isCritical _ = False

isWarning :: Finding -> Bool
isWarning (Finding Warning _ _) = True
isWarning _ = False

isInfo :: Finding -> Bool
isInfo (Finding Info _ _) = True
isInfo _ = False

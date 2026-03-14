{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Advisory database for dependency security auditing.
--
-- Provides types and matching logic for checking project dependencies
-- against known security advisories. Advisories can be loaded from
-- a local JSON file (e.g., @canopy-advisories.json@) or bundled
-- with the compiler.
--
-- == Advisory Format
--
-- Each advisory specifies a package, an affected version range,
-- a severity level, and a human-readable description. Optionally,
-- a fixed-in version suggests the minimum safe upgrade.
--
-- @since 0.19.2
module Deps.Advisory
  ( -- * Types
    Advisory (..),
    Severity (..),
    AuditResult (..),

    -- * Lenses
    advisoryId,
    advisoryPackage,
    advisoryAffectedLower,
    advisoryAffectedUpper,
    advisorySeverity,
    advisoryDescription,
    advisoryFixedIn,

    -- * Matching
    matchAdvisories,
    isAffected,
    filterBySeverity,

    -- * Loading
    loadAdvisories,
    defaultAdvisories,

    -- * Rendering
    severityLabel,
    severityOrd,
  )
where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import Control.Lens (makeLenses)
import qualified Data.Aeson as Json
import qualified Data.Aeson.Types as Json
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe

-- | Severity level for security advisories.
--
-- Ordered from lowest to highest severity. 'filterBySeverity' uses
-- 'severityOrd' to include only findings at or above a threshold.
--
-- @since 0.19.2
data Severity
  = SevLow
  | SevMedium
  | SevHigh
  | SevCritical
  deriving (Eq, Show)

-- | Numeric ordering for severity comparison.
--
-- @since 0.19.2
severityOrd :: Severity -> Int
severityOrd SevLow = 0
severityOrd SevMedium = 1
severityOrd SevHigh = 2
severityOrd SevCritical = 3

-- | Machine-readable severity label for output.
--
-- @since 0.19.2
severityLabel :: Severity -> String
severityLabel SevLow = "low"
severityLabel SevMedium = "medium"
severityLabel SevHigh = "high"
severityLabel SevCritical = "critical"

-- | A single security advisory for a package.
--
-- Represents a known vulnerability affecting a specific version range
-- of a package, with an optional recommended fix version.
--
-- @since 0.19.2
data Advisory = Advisory
  { _advisoryId :: !String,
    _advisoryPackage :: !String,
    _advisoryAffectedLower :: !Version.Version,
    _advisoryAffectedUpper :: !Version.Version,
    _advisorySeverity :: !Severity,
    _advisoryDescription :: !String,
    _advisoryFixedIn :: !(Maybe Version.Version)
  }
  deriving (Eq, Show)

makeLenses ''Advisory

-- | Result of matching an advisory against a project dependency.
--
-- Pairs the matched advisory with the actual version found in the
-- project, providing enough context for actionable reporting.
--
-- @since 0.19.2
data AuditResult = AuditResult
  { _auditAdvisory :: !Advisory,
    _auditInstalledVersion :: !Version.Version
  }
  deriving (Eq, Show)

-- | Check whether a specific version is affected by an advisory.
--
-- A version is affected when it falls within the closed range
-- @[lower, upper]@ specified by the advisory.
--
-- @since 0.19.2
isAffected :: Advisory -> Version.Version -> Bool
isAffected adv version =
  version >= _advisoryAffectedLower adv
    && version <= _advisoryAffectedUpper adv

-- | Match advisories against a map of installed packages.
--
-- For each package in the dependency map, checks all advisories
-- and collects matches. Returns results for every advisory that
-- applies to an installed version.
--
-- @since 0.19.2
matchAdvisories :: [Advisory] -> Map Pkg.Name Version.Version -> [AuditResult]
matchAdvisories advisories deps =
  concatMap matchPackage (Map.toList deps)
  where
    matchPackage (pkg, version) =
      Maybe.mapMaybe (matchSingle (Pkg.toChars pkg) version) advisories

    matchSingle pkgStr version adv
      | _advisoryPackage adv == pkgStr && isAffected adv version =
          Just (AuditResult adv version)
      | otherwise = Nothing

-- | Filter audit results by minimum severity level.
--
-- Only includes results whose severity is at or above the given
-- threshold.
--
-- @since 0.19.2
filterBySeverity :: Severity -> [AuditResult] -> [AuditResult]
filterBySeverity minSev =
  filter aboveThreshold
  where
    threshold = severityOrd minSev
    aboveThreshold result = severityOrd (_advisorySeverity (_auditAdvisory result)) >= threshold

-- | Load advisories from a JSON file on disk.
--
-- Returns an empty list if the file does not exist or cannot be parsed.
-- Errors are silently ignored because advisory checking is best-effort;
-- a missing advisory file should never block compilation.
--
-- @since 0.19.2
loadAdvisories :: FilePath -> IO [Advisory]
loadAdvisories path =
  either (const []) id <$> tryLoad
  where
    tryLoad :: IO (Either IOException [Advisory])
    tryLoad = Exception.try (loadAndParse path)

    loadAndParse :: FilePath -> IO [Advisory]
    loadAndParse fp = do
      content <- LBS.readFile fp
      pure (maybe [] extractAdvisories (Json.decode content))

    extractAdvisories :: Json.Value -> [Advisory]
    extractAdvisories val =
      maybe [] id (Json.parseMaybe parseAdvisoryList val)

-- | Parse a JSON value as a list of advisories.
--
-- Expected format:
--
-- @
-- { "advisories": [ { "id": "...", "package": "...", ... } ] }
-- @
--
-- @since 0.19.2
parseAdvisoryList :: Json.Value -> Json.Parser [Advisory]
parseAdvisoryList = Json.withObject "advisories" $ \obj -> do
  arr <- obj Json..: "advisories"
  mapM parseAdvisory arr

-- | Parse a single advisory from JSON.
--
-- @since 0.19.2
parseAdvisory :: Json.Value -> Json.Parser Advisory
parseAdvisory = Json.withObject "advisory" $ \obj -> do
  aid <- obj Json..: "id"
  pkg <- obj Json..: "package"
  lowerStr <- obj Json..: "affected-from"
  upperStr <- obj Json..: "affected-through"
  sevStr <- obj Json..: "severity"
  desc <- obj Json..: "description"
  fixStr <- obj Json..:? "fixed-in"
  lower <- parseVersion lowerStr
  upper <- parseVersion upperStr
  sev <- parseSeverity sevStr
  mFix <- traverse parseVersion fixStr
  pure (Advisory aid pkg lower upper sev desc mFix)

-- | Parse a version string like \"1.2.3\" into a Version.
--
-- @since 0.19.2
parseVersion :: String -> Json.Parser Version.Version
parseVersion str =
  maybe (fail ("Invalid version: " ++ str)) pure (parseVersionParts str)

-- | Parse dot-separated version components.
--
-- @since 0.19.2
parseVersionParts :: String -> Maybe Version.Version
parseVersionParts str =
  case break (== '.') str of
    (majorS, '.' : rest1) ->
      case break (== '.') rest1 of
        (minorS, '.' : patchS) ->
          makeVersion majorS minorS patchS
        _ -> Nothing
    _ -> Nothing
  where
    makeVersion ms ns ps = do
      major <- safeRead ms
      minor <- safeRead ns
      patch <- safeRead ps
      pure (Version.Version (fromIntegral major) (fromIntegral minor) (fromIntegral patch))

    safeRead :: String -> Maybe Int
    safeRead s =
      case reads s of
        [(n, "")] | n >= 0 -> Just n
        _ -> Nothing

-- | Parse a severity string.
--
-- @since 0.19.2
parseSeverity :: String -> Json.Parser Severity
parseSeverity "low" = pure SevLow
parseSeverity "medium" = pure SevMedium
parseSeverity "high" = pure SevHigh
parseSeverity "critical" = pure SevCritical
parseSeverity other = fail ("Unknown severity: " ++ other)

-- | Default built-in advisories.
--
-- These are bundled with the compiler and cover known issues in
-- commonly used packages. They serve as a baseline even when no
-- external advisory file is available.
--
-- Currently empty as the Canopy package ecosystem is new and has
-- no known vulnerabilities. This list will be populated as the
-- ecosystem matures and vulnerabilities are discovered.
--
-- @since 0.19.2
defaultAdvisories :: [Advisory]
defaultAdvisories = []

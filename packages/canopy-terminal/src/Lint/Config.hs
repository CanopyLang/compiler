{-# LANGUAGE OverloadedStrings #-}

-- | Lint configuration loading from canopy.json.
--
-- Reads the optional @\"lints\"@ key from a project's @canopy.json@ and
-- merges it with the default configuration. Each rule can be configured
-- as a simple severity string or as an object with a @\"level\"@ key:
--
-- @
-- {
--   "lints": {
--     "unused-import": "error",
--     "magic-number": "off",
--     "long-function": { "level": "warn" }
--   }
-- }
-- @
--
-- Rules not mentioned in the config retain their default severity.
--
-- @since 0.19.2
module Lint.Config
  ( -- * Config Loading
    loadLintConfig,

    -- * Parsing
    parseLintOverrides,
  )
where

import qualified Data.Aeson as Json
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Text as Text
import Lint.Types
  ( LintConfig (..),
    LintRule,
    RuleConfig (..),
    Severity,
    ruleFromString,
    severityFromString,
  )
import qualified System.Directory as Dir

-- | Load lint configuration from the project's @canopy.json@.
--
-- Reads the file at @{root}\/canopy.json@, extracts the optional
-- @\"lints\"@ object, and merges any overrides with the provided
-- default configuration. If the file does not exist, cannot be
-- parsed, or has no @\"lints\"@ key, returns the defaults unchanged.
--
-- @since 0.19.2
loadLintConfig :: LintConfig -> FilePath -> IO LintConfig
loadLintConfig defaults root = do
  let path = root ++ "/canopy.json"
  exists <- Dir.doesFileExist path
  if not exists
    then pure defaults
    else do
      content <- LBS.readFile path
      pure (applyOverrides defaults content)

-- | Apply lint overrides from raw JSON bytes to a default config.
applyOverrides :: LintConfig -> LBS.ByteString -> LintConfig
applyOverrides defaults content =
  case Json.decode content of
    Nothing -> defaults
    Just jsonValue -> applyFromJson defaults jsonValue

-- | Extract lint overrides from a parsed JSON value and apply them.
applyFromJson :: LintConfig -> Json.Value -> LintConfig
applyFromJson defaults (Json.Object obj) =
  case KeyMap.lookup "lints" obj of
    Just (Json.Object lintsObj) ->
      let overrides = parseLintOverrides lintsObj
       in mergeLintConfig defaults overrides
    _ -> defaults
applyFromJson defaults _ = defaults

-- | Parse the @\"lints\"@ JSON object into a list of rule overrides.
--
-- Each key is a rule identifier (kebab-case) and the value is either:
--
-- * A string severity: @\"error\"@, @\"warn\"@, @\"info\"@, @\"off\"@
-- * An object with a @\"level\"@ key: @{ \"level\": \"warn\" }@
--
-- @since 0.19.2
parseLintOverrides :: KeyMap.KeyMap Json.Value -> [(LintRule, Severity)]
parseLintOverrides = mapMaybe parseEntry . KeyMap.toList
  where
    parseEntry :: (Key.Key, Json.Value) -> Maybe (LintRule, Severity)
    parseEntry (key, value) = do
      rule <- ruleFromString (Text.unpack (Key.toText key))
      sev <- parseSeverityValue value
      Just (rule, sev)

-- | Parse a severity from a JSON value (string or object with "level" key).
parseSeverityValue :: Json.Value -> Maybe Severity
parseSeverityValue (Json.String s) = severityFromString (Text.unpack s)
parseSeverityValue (Json.Object obj) =
  case KeyMap.lookup "level" obj of
    Just (Json.String s) -> severityFromString (Text.unpack s)
    _ -> Nothing
parseSeverityValue _ = Nothing

-- | Merge lint overrides into a default config.
--
-- Each override replaces the severity for its rule. Rules not
-- mentioned in the overrides retain their default severity.
mergeLintConfig :: LintConfig -> [(LintRule, Severity)] -> LintConfig
mergeLintConfig (LintConfig defaults) overrides =
  LintConfig (foldr applyOne defaults overrides)
  where
    applyOne (rule, sev) m = Map.insert rule (RuleConfig sev) m

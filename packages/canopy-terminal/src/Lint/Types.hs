{-# LANGUAGE OverloadedStrings #-}

-- | Core types for the Canopy lint system.
--
-- This module defines all data types shared across the lint sub-modules:
-- warnings, rules, fixes, severity levels, configuration, and CLI flags.
-- Separating them here avoids circular imports between 'Lint.Rules',
-- 'Lint.Report', and 'Lint.Fix'.
--
-- @since 0.19.1
module Lint.Types
  ( -- * CLI Flags
    Flags (..),

    -- * Warnings
    LintWarning (..),

    -- * Rules
    LintRule (..),
    ruleToString,
    ruleFromString,

    -- * Fixes
    LintFix (..),

    -- * Severity
    Severity (..),
    severityFromString,

    -- * Configuration
    RuleConfig (..),
    LintConfig (..),

    -- * Output Format
    ReportFormat (..),
  )
where

import Data.Map.Strict (Map)
import qualified Reporting.Annotation as Ann

-- | Command-line flags for the lint command.
--
-- Controls which files are analysed, whether auto-fixes are applied,
-- and the output format for the results.
--
-- @since 0.19.1
data Flags = Flags
  { _fix :: !Bool,
    _reportFormat :: !(Maybe ReportFormat)
  }
  deriving (Eq, Show)

-- | Severity level for lint rules.
--
-- Controls how a lint rule violation is reported and whether it blocks
-- the build.  'Off' disables the rule entirely, 'SevInfo' and 'SevWarning'
-- are non-blocking, and 'SevError' is treated as a build failure.
--
-- @since 0.19.1
data Severity = Off | SevInfo | SevWarning | SevError
  deriving (Eq, Ord, Show)

-- | Per-rule configuration specifying the severity at which to report.
--
-- @since 0.19.1
data RuleConfig = RuleConfig
  { _rcSeverity :: !Severity
  }
  deriving (Eq, Show)

-- | Complete lint configuration mapping each rule to its severity.
--
-- Rules absent from the map are treated as disabled.
--
-- @since 0.19.1
data LintConfig = LintConfig
  { _lcRules :: !(Map LintRule RuleConfig)
  }
  deriving (Eq, Show)

-- | Output format for lint results.
--
-- @since 0.19.1
data ReportFormat
  = TerminalFormat
  | JsonFormat
  deriving (Eq, Show)

-- | A single lint warning produced by a rule.
--
-- Carries the location, rule name, human-readable message, and an optional
-- description of a text substitution that fixes the issue automatically.
--
-- @since 0.19.1
data LintWarning = LintWarning
  { _warnRegion :: !Ann.Region,
    _warnRule :: !LintRule,
    _warnSeverity :: !Severity,
    _warnMessage :: !String,
    _warnFix :: !(Maybe LintFix)
  }
  deriving (Eq, Show)

-- | Identifier for a lint rule.
--
-- @since 0.19.1
data LintRule
  = UnusedImport
  | BooleanCase
  | UnnecessaryParens
  | DropConcatOfLists
  | UseConsOverConcat
  | MissingTypeAnnotation
  | ShadowedVariable
  | UnusedLetVariable
  | PartialFunction
  | UnsafeCoerce
  | ListAppendInLoop
  | UnnecessaryLazyPattern
  | StringConcatInLoop
  | TooManyArguments
  | LongFunction
  | MagicNumber
  | InconsistentNaming
  | SketchyMaybeCheck
  | RedundantMaybeWrap
  | UnnecessaryPatternMatch
  | SilentFallback
  | AlwaysFalseComparison
  | UnreachableCode
  deriving (Eq, Ord, Show)

-- | Description of an auto-fix action.
--
-- Two modes are supported:
--
-- * 'TextReplace' -- search-and-replace a literal string with a replacement.
-- * 'RemoveLines' -- delete a contiguous range of lines (1-indexed, inclusive).
--
-- The terminal @--fix@ flag applies all fixes whose warnings have
-- a populated 'LintFix'.
--
-- @since 0.19.1
data LintFix
  = TextReplace
      { _fixOriginal :: !String,
        _fixReplacement :: !String
      }
  | RemoveLines
      { _fixStartLine :: !Int,
        _fixEndLine :: !Int
      }
  deriving (Eq, Show)

-- | Convert a 'LintRule' to its kebab-case string identifier.
--
-- These identifiers are used in canopy.json lint configuration
-- and in the @--rule@ CLI flag.
--
-- @since 0.19.2
ruleToString :: LintRule -> String
ruleToString UnusedImport = "unused-import"
ruleToString BooleanCase = "boolean-case"
ruleToString UnnecessaryParens = "unnecessary-parens"
ruleToString DropConcatOfLists = "drop-concat-of-lists"
ruleToString UseConsOverConcat = "use-cons-over-concat"
ruleToString MissingTypeAnnotation = "missing-type-annotation"
ruleToString ShadowedVariable = "shadowed-variable"
ruleToString UnusedLetVariable = "unused-let-variable"
ruleToString PartialFunction = "partial-function"
ruleToString UnsafeCoerce = "unsafe-coerce"
ruleToString ListAppendInLoop = "list-append-in-loop"
ruleToString UnnecessaryLazyPattern = "unnecessary-lazy-pattern"
ruleToString StringConcatInLoop = "string-concat-in-loop"
ruleToString TooManyArguments = "too-many-arguments"
ruleToString LongFunction = "long-function"
ruleToString MagicNumber = "magic-number"
ruleToString InconsistentNaming = "inconsistent-naming"
ruleToString SketchyMaybeCheck = "sketchy-maybe"
ruleToString RedundantMaybeWrap = "redundant-maybe-wrap"
ruleToString UnnecessaryPatternMatch = "unnecessary-pattern-match"
ruleToString SilentFallback = "silent-fallback"
ruleToString AlwaysFalseComparison = "always-false-comparison"
ruleToString UnreachableCode = "unreachable-code"

-- | Parse a kebab-case string into a 'LintRule'.
--
-- Returns 'Nothing' if the string does not match any known rule.
--
-- @since 0.19.2
ruleFromString :: String -> Maybe LintRule
ruleFromString "unused-import" = Just UnusedImport
ruleFromString "boolean-case" = Just BooleanCase
ruleFromString "unnecessary-parens" = Just UnnecessaryParens
ruleFromString "drop-concat-of-lists" = Just DropConcatOfLists
ruleFromString "use-cons-over-concat" = Just UseConsOverConcat
ruleFromString "missing-type-annotation" = Just MissingTypeAnnotation
ruleFromString "shadowed-variable" = Just ShadowedVariable
ruleFromString "unused-let-variable" = Just UnusedLetVariable
ruleFromString "partial-function" = Just PartialFunction
ruleFromString "unsafe-coerce" = Just UnsafeCoerce
ruleFromString "list-append-in-loop" = Just ListAppendInLoop
ruleFromString "unnecessary-lazy-pattern" = Just UnnecessaryLazyPattern
ruleFromString "string-concat-in-loop" = Just StringConcatInLoop
ruleFromString "too-many-arguments" = Just TooManyArguments
ruleFromString "long-function" = Just LongFunction
ruleFromString "magic-number" = Just MagicNumber
ruleFromString "inconsistent-naming" = Just InconsistentNaming
ruleFromString "sketchy-maybe" = Just SketchyMaybeCheck
ruleFromString "redundant-maybe-wrap" = Just RedundantMaybeWrap
ruleFromString "unnecessary-pattern-match" = Just UnnecessaryPatternMatch
ruleFromString "silent-fallback" = Just SilentFallback
ruleFromString "always-false-comparison" = Just AlwaysFalseComparison
ruleFromString "unreachable-code" = Just UnreachableCode
ruleFromString _ = Nothing

-- | Parse a severity level from a string.
--
-- Accepts @"off"@, @"info"@, @"warn"\/"warning"@, and @"error"@.
--
-- @since 0.19.2
severityFromString :: String -> Maybe Severity
severityFromString "off" = Just Off
severityFromString "info" = Just SevInfo
severityFromString "warn" = Just SevWarning
severityFromString "warning" = Just SevWarning
severityFromString "error" = Just SevError
severityFromString _ = Nothing

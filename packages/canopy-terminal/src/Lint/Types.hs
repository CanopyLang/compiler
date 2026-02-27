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

    -- * Fixes
    LintFix (..),

    -- * Severity
    Severity (..),

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

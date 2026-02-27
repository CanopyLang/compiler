{-# LANGUAGE OverloadedStrings #-}

-- | Static analysis (lint) command for Canopy source files.
--
-- This module implements the @canopy lint@ command, which performs static
-- analysis on @.can@ source files and reports style issues, potential bugs,
-- and code quality improvements.
--
-- == Available Rules
--
-- * 'checkUnusedImport' - Imports that are never referenced in the module body
-- * 'checkBooleanCase' - @case x of True -> a; False -> b@ that should be @if@
-- * 'checkUnnecessaryParens' - Extra parentheses around simple expressions
-- * 'checkDropConcatOfLists' - @[a] ++ [b]@ that should be @[a, b]@
-- * 'checkUseConsOverConcat' - @[a] ++ list@ that should be @a :: list@
-- * 'checkMissingTypeAnnotation' - Top-level function without a type signature
--
-- == Usage
--
-- @
-- canopy lint                  -- Lint all .can files in src/
-- canopy lint src/Main.can     -- Lint a specific file
-- canopy lint --fix            -- Auto-fix simple issues
-- canopy lint --report=json    -- Output results as JSON
-- @
--
-- == Architecture
--
-- Each lint rule is a pure function @'AST.Source.Module' -> ['LintWarning']@.
-- The engine collects results from all rules and reports them together.
-- Auto-fixable warnings carry a 'LintFix' describing the substitution to apply.
--
-- Rule implementations live in "Lint.Rules", reporting in "Lint.Report",
-- auto-fix logic in "Lint.Fix", and shared types in "Lint.Types".
--
-- @since 0.19.1
module Lint
  ( -- * Entry Point
    run,

    -- * Types (re-exported from Lint.Types)
    Flags (..),
    LintWarning (..),
    LintRule (..),
    LintFix (..),
    ReportFormat (..),
    Severity (..),
    RuleConfig (..),
    LintConfig (..),

    -- * Configuration
    defaultLintConfig,

    -- * Parsers
    reportFormatParser,
  )
where

import qualified AST.Source as Src
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Lint.Fix as Fix
import qualified Lint.Report as Report
import qualified Lint.Rules as Rules
import Lint.Types
  ( Flags (..),
    LintConfig (..),
    LintFix (..),
    LintRule (..),
    LintWarning (..),
    ReportFormat (..),
    RuleConfig (..),
    Severity (..),
  )
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as Ann
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import Terminal (Parser (..))

-- CONFIGURATION

-- | The default lint configuration with all built-in rules enabled.
--
-- Style-oriented rules ('UnnecessaryParens', 'UseConsOverConcat') default
-- to 'SevInfo'; all others default to 'SevWarning'.
--
-- @since 0.19.1
defaultLintConfig :: LintConfig
defaultLintConfig = LintConfig
  { _lcRules = Map.fromList
      [ (UnusedImport, RuleConfig SevWarning)
      , (BooleanCase, RuleConfig SevWarning)
      , (UnnecessaryParens, RuleConfig SevInfo)
      , (DropConcatOfLists, RuleConfig SevWarning)
      , (UseConsOverConcat, RuleConfig SevInfo)
      , (MissingTypeAnnotation, RuleConfig SevWarning)
      ]
  }

-- ENTRY POINT

-- | Main entry point for the lint command.
--
-- Resolves the list of files to analyse (either the user-supplied paths or
-- all @.can@ files under @src/@), parses each file, runs all lint rules, and
-- reports the results.  When @--fix@ is set, fixable warnings are applied
-- in-place before reporting.
--
-- @since 0.19.1
run :: [FilePath] -> Flags -> IO ()
run paths flags = do
  files <- resolveTargetFiles paths
  let config = defaultLintConfig
  results <- mapM (lintFile config flags) files
  let allWarnings = concat results
  case _reportFormat flags of
    Just JsonFormat -> Report.reportJson allWarnings
    _ -> Report.reportTerminal allWarnings
  Report.reportExitSummary allWarnings

-- FILE RESOLUTION

-- | Resolve the list of files to lint.
--
-- When no paths are given, recursively discovers all @.can@ files under
-- @src/@.  Otherwise uses the supplied paths directly.
resolveTargetFiles :: [FilePath] -> IO [FilePath]
resolveTargetFiles [] = discoverCanopyFiles "src"
resolveTargetFiles paths = pure paths

-- | Recursively find all @.can@ files under a directory.
--
-- Silently returns an empty list if the directory does not exist so that
-- running @canopy lint@ in a project with no @src/@ directory does not crash.
discoverCanopyFiles :: FilePath -> IO [FilePath]
discoverCanopyFiles dir = do
  exists <- Dir.doesDirectoryExist dir
  if exists
    then do
      entries <- Dir.listDirectory dir
      let fullPaths = map (dir FilePath.</>) entries
      files <- filterM Dir.doesFileExist fullPaths
      subdirs <- filterM Dir.doesDirectoryExist fullPaths
      nested <- mapM discoverCanopyFiles subdirs
      pure (filter isCanopyFile files ++ concat nested)
    else pure []

-- | Check whether a file path has a @.can@ or @.canopy@ extension.
isCanopyFile :: FilePath -> Bool
isCanopyFile p =
  FilePath.takeExtension p `elem` [".can", ".canopy"]

-- LINT ENGINE

-- | Parse and lint a single file, returning all warnings.
--
-- Parse errors are reported as a single synthesised warning so that
-- the linter can continue processing other files.
lintFile :: LintConfig -> Flags -> FilePath -> IO [LintWarning]
lintFile config flags path = do
  source <- BS.readFile path
  case Parse.fromByteString Parse.Application source of
    Left _parseErr ->
      pure [parseErrorWarning path]
    Right modul ->
      Fix.applyFixesIfRequested flags path (lintModule config modul)

-- | Synthesise a warning for an unparseable file.
parseErrorWarning :: FilePath -> LintWarning
parseErrorWarning path =
  LintWarning
    { _warnRegion = Ann.zero,
      _warnRule = MissingTypeAnnotation,
      _warnSeverity = SevWarning,
      _warnMessage = "Could not parse file: " ++ path,
      _warnFix = Nothing
    }

-- | Run all enabled lint rules over a parsed module.
--
-- Each rule is independent; results are concatenated in rule order.
-- The 'LintConfig' controls which rules are active and at what severity.
--
-- @since 0.19.1
lintModule :: LintConfig -> Src.Module -> [LintWarning]
lintModule config modul =
  concatMap (runRule modul) (enabledRules config)

-- | Execute a single lint rule at the given severity, stamping each
-- resulting warning with that severity.
runRule :: Src.Module -> (Severity, Src.Module -> [LintWarning]) -> [LintWarning]
runRule modul (sev, check) = map (setSeverity sev) (check modul)

-- | Override the severity field of a warning.
setSeverity :: Severity -> LintWarning -> LintWarning
setSeverity sev w = w {_warnSeverity = sev}

-- | Registry mapping each rule identifier to its check function.
--
-- New rules are registered here to be picked up by the config-driven engine.
ruleRegistry :: [(LintRule, Src.Module -> [LintWarning])]
ruleRegistry =
  [ (UnusedImport, Rules.checkUnusedImport),
    (BooleanCase, Rules.checkBooleanCase),
    (UnnecessaryParens, Rules.checkUnnecessaryParens),
    (DropConcatOfLists, Rules.checkDropConcatOfLists),
    (UseConsOverConcat, Rules.checkUseConsOverConcat),
    (MissingTypeAnnotation, Rules.checkMissingTypeAnnotation)
  ]

-- | Filter the rule registry to only those rules that are enabled
-- (severity greater than 'Off') in the given config.
enabledRules :: LintConfig -> [(Severity, Src.Module -> [LintWarning])]
enabledRules config =
  mapMaybe lookupEnabled ruleRegistry
  where
    lookupEnabled (rule, check) =
      case Map.lookup rule (_lcRules config) of
        Just (RuleConfig sev) | sev > Off -> Just (sev, check)
        _ -> Nothing

-- PARSER

-- | CLI parser for the @--report@ flag.
--
-- Accepts @"json"@ to select machine-readable output.
--
-- @since 0.19.1
reportFormatParser :: Parser ReportFormat
reportFormatParser =
  Parser
    { _singular = "report format",
      _plural = "report formats",
      _parser = parseReportFormat,
      _suggest = suggestReportFormats,
      _examples = exampleReportFormats
    }

-- | Parse a report format string.
parseReportFormat :: String -> Maybe ReportFormat
parseReportFormat "json" = Just JsonFormat
parseReportFormat _ = Nothing

-- | Suggest valid report format values for shell completion.
suggestReportFormats :: String -> IO [String]
suggestReportFormats _ = pure ["json"]

-- | Provide example report format values for help text.
exampleReportFormats :: String -> IO [String]
exampleReportFormats _ = pure ["json"]

-- | Filter a list using a monadic predicate.
filterM :: (Monad m) => (a -> m Bool) -> [a] -> m [a]
filterM _ [] = pure []
filterM predicate (x : xs) = do
  keep <- predicate x
  rest <- filterM predicate xs
  pure (if keep then x : rest else rest)

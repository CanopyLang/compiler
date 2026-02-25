{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -Wall #-}

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
-- @since 0.19.1
module Lint
  ( -- * Entry Point
    run,

    -- * Types
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
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Name as Name
import Data.Ord (Down (..))
import qualified Data.Set as Set
import qualified Data.Word as Word
import qualified Json.Encode as Encode
import qualified Json.String as JsonString
import qualified Parse.Module as Parse
import qualified Reporting.Annotation as A
import Reporting.Doc.ColorQQ (c)
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import qualified System.IO as IO
import Terminal (Parser (..))
import qualified Terminal.Print as Print

-- TYPES

-- | Command-line flags for the lint command.
--
-- Controls which files are analysed, whether auto-fixes are applied,
-- and the output format for the results.
--
-- @since 0.19.1
data Flags = Flags
  { -- | Apply auto-fixes for fixable warnings.
    _fix :: !Bool,
    -- | Output format: terminal (default) or JSON.
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
  } deriving (Eq, Show)

-- | Complete lint configuration mapping each rule to its severity.
--
-- Rules absent from the map are treated as disabled.
--
-- @since 0.19.1
data LintConfig = LintConfig
  { _lcRules :: !(Map LintRule RuleConfig)
  } deriving (Eq, Show)

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

-- | Output format for lint results.
--
-- @since 0.19.1
data ReportFormat
  = -- | Human-readable terminal output (default).
    TerminalFormat
  | -- | Machine-readable JSON output.
    JsonFormat
  deriving (Eq, Show)

-- | A single lint warning produced by a rule.
--
-- Carries the location, rule name, human-readable message, and an optional
-- description of a text substitution that fixes the issue automatically.
--
-- @since 0.19.1
data LintWarning = LintWarning
  { -- | Source region where the issue was detected.
    _warnRegion :: !A.Region,
    -- | Short identifier for the rule (e.g. \"UnusedImport\").
    _warnRule :: !LintRule,
    -- | Severity at which this warning was reported.
    _warnSeverity :: !Severity,
    -- | Human-readable description of the issue.
    _warnMessage :: !String,
    -- | Optional auto-fix description.
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
-- * 'TextReplace' — search-and-replace a literal string with a replacement.
-- * 'RemoveLines' — delete a contiguous range of lines (1-indexed, inclusive).
--
-- The terminal @--fix@ flag applies all fixes whose warnings have
-- a populated 'LintFix'.
--
-- @since 0.19.1
data LintFix
  = -- | Replace the first occurrence of @_fixOriginal@ with @_fixReplacement@.
    TextReplace
      { _fixOriginal :: !String,
        _fixReplacement :: !String
      }
  | -- | Remove lines from @_fixStartLine@ to @_fixEndLine@ (inclusive, 1-indexed).
    RemoveLines
      { _fixStartLine :: !Int,
        _fixEndLine :: !Int
      }
  deriving (Eq, Show)

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
    Just JsonFormat -> reportJson allWarnings
    _ -> reportTerminal allWarnings
  reportExitSummary allWarnings

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
      applyFixesIfRequested flags path (lintModule config modul)

-- | Synthesise a warning for an unparseable file.
parseErrorWarning :: FilePath -> LintWarning
parseErrorWarning path =
  LintWarning
    { _warnRegion = A.zero,
      _warnRule = MissingTypeAnnotation,
      _warnSeverity = SevWarning,
      _warnMessage = "Could not parse file: " ++ path,
      _warnFix = Nothing
    }

-- | Apply auto-fixes to a file when the @--fix@ flag is active.
--
-- Rewrites the file in-place for each fixable warning, then returns the
-- (now-stale but still informative) original warning list.
applyFixesIfRequested :: Flags -> FilePath -> [LintWarning] -> IO [LintWarning]
applyFixesIfRequested flags path warnings
  | _fix flags = applyFixes path warnings >> pure warnings
  | otherwise = pure warnings

-- | Apply all auto-fixable warnings to a file.
--
-- Line removals are applied bottom-to-top (descending line order) so that
-- earlier line numbers remain valid.  Text replacements are applied
-- afterwards since they operate on string content rather than line indices.
-- After writing the fixed file, the result is re-parsed to verify validity.
applyFixes :: FilePath -> [LintWarning] -> IO ()
applyFixes path warnings = do
  source <- readFile path
  let (lineRemoves, textReplaces) = partitionFixes (mapMaybe _warnFix warnings)
      sortedRemoves = List.sortOn (Down . _fixStartLine) lineRemoves
      afterRemoves = foldl applyOneFix source sortedRemoves
      fixed = foldl applyOneFix afterRemoves textReplaces
  writeFile path fixed
  validateFixedFile path source

-- | Partition fixes into line removals and text replacements.
--
-- Line removals must be applied in reverse order to preserve line indices;
-- text replacements are order-independent.
partitionFixes :: [LintFix] -> ([LintFix], [LintFix])
partitionFixes = foldr classify ([], [])
  where
    classify fix@(RemoveLines _ _) (removes, replaces) = (fix : removes, replaces)
    classify fix@(TextReplace _ _) (removes, replaces) = (removes, fix : replaces)

-- | Re-parse the fixed file to verify it is still valid.
--
-- If the fixed file fails to parse, the original content is restored
-- and a message is printed to stderr.
validateFixedFile :: FilePath -> String -> IO ()
validateFixedFile path originalSource = do
  fixedBytes <- BS.readFile path
  case Parse.fromByteString Parse.Application fixedBytes of
    Left _ -> do
      writeFile path originalSource
      Print.println [c|{yellow|Warning:} auto-fix produced invalid syntax in {cyan|#{path}}; reverted.|]
    Right _ -> pure ()

-- | Apply a single fix to source text.
applyOneFix :: String -> LintFix -> String
applyOneFix source (TextReplace original replacement) =
  replaceFirst original replacement source
applyOneFix source (RemoveLines startLine endLine) =
  unlines kept
  where
    allLines = lines source
    kept = removeRange startLine endLine allLines

-- | Remove lines in a 1-indexed inclusive range from a list of lines.
removeRange :: Int -> Int -> [String] -> [String]
removeRange start end lns =
  zipWith keepLine [1 ..] lns >>= id
  where
    keepLine i l
      | i >= start && i <= end = []
      | otherwise = [l]

-- | Replace the first occurrence of @needle@ with @replacement@ in @haystack@.
replaceFirst :: String -> String -> String -> String
replaceFirst needle replacement haystack =
  case List.stripPrefix needle haystack of
    Just rest -> replacement ++ rest
    Nothing -> replaceFirstStep needle replacement haystack

-- | Advance one character and retry the replacement.
replaceFirstStep :: String -> String -> String -> String
replaceFirstStep _ _ [] = []
replaceFirstStep needle replacement (ch : rest) =
  ch : replaceFirst needle replacement rest

-- LINT ENGINE

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
  [ (UnusedImport, checkUnusedImport),
    (BooleanCase, checkBooleanCase),
    (UnnecessaryParens, checkUnnecessaryParens),
    (DropConcatOfLists, checkDropConcatOfLists),
    (UseConsOverConcat, checkUseConsOverConcat),
    (MissingTypeAnnotation, checkMissingTypeAnnotation)
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

-- LINT RULES

-- | Rule: detect imports that are never used in the module body.
--
-- An import is considered used when its qualified name (or alias) or any
-- of its explicitly exposed names appear somewhere in the module's value,
-- type, or union declarations.
--
-- @since 0.19.1
checkUnusedImport :: Src.Module -> [LintWarning]
checkUnusedImport modul =
  mapMaybe (checkOneImport usedNames) (Src._imports modul)
  where
    usedNames = collectUsedNames modul

-- | Produce a warning for an import if none of its exposed names are used.
checkOneImport :: Set.Set String -> Src.Import -> Maybe LintWarning
checkOneImport usedNames imp
  | isImportUsed usedNames imp = Nothing
  | otherwise = Just (unusedImportWarning imp)

-- | Check whether at least one name from the import appears in the module.
isImportUsed :: Set.Set String -> Src.Import -> Bool
isImportUsed usedNames (Src.Import (A.At _ modName) alias exposing _isLazy) =
  qualifierUsed || exposedNamesUsed
  where
    qualifier = maybe (Name.toChars modName) Name.toChars alias
    qualifierUsed = Set.member qualifier usedNames
    exposedNamesUsed = any (flip Set.member usedNames) (exposedNames exposing)

-- | Extract the list of explicitly exposed names from an exposing clause.
exposedNames :: Src.Exposing -> [String]
exposedNames Src.Open = []
exposedNames (Src.Explicit items) = mapMaybe exposedItemName items

-- | Extract the string representation of a single exposed item.
exposedItemName :: Src.Exposed -> Maybe String
exposedItemName (Src.Lower (A.At _ n)) = Just (Name.toChars n)
exposedItemName (Src.Upper (A.At _ n) _) = Just (Name.toChars n)
exposedItemName (Src.Operator _ n) = Just (Name.toChars n)

-- | Build the set of all name tokens that appear in the module body.
collectUsedNames :: Src.Module -> Set.Set String
collectUsedNames modul =
  Set.fromList $
    concatMap collectNamesInValue (map A.toValue (Src._values modul))
      ++ concatMap collectNamesInUnion (map A.toValue (Src._unions modul))
      ++ concatMap collectNamesInAlias (map A.toValue (Src._aliases modul))

-- | Collect all name tokens from a value definition.
collectNamesInValue :: Src.Value -> [String]
collectNamesInValue (Src.Value _ _ expr _) =
  collectNamesInExpr (A.toValue expr)

-- | Collect all name tokens from a union type definition.
collectNamesInUnion :: Src.Union -> [String]
collectNamesInUnion (Src.Union _ _ ctors) =
  concatMap collectNamesInCtor ctors

-- | Collect names from a constructor definition.
collectNamesInCtor :: (A.Located Name.Name, [Src.Type]) -> [String]
collectNamesInCtor (_, types) =
  concatMap collectNamesInType (map A.toValue types)

-- | Collect names from a type alias definition.
collectNamesInAlias :: Src.Alias -> [String]
collectNamesInAlias (Src.Alias _ _ t) =
  collectNamesInType (A.toValue t)

-- | Collect all identifier tokens used in an expression.
collectNamesInExpr :: Src.Expr_ -> [String]
collectNamesInExpr expr =
  case expr of
    Src.Var _ n -> [Name.toChars n]
    Src.VarQual _ modN n -> [Name.toChars modN, Name.toChars n]
    Src.Call f args ->
      collectNamesInExpr (A.toValue f)
        ++ concatMap (collectNamesInExpr . A.toValue) args
    Src.If branches elseBranch ->
      concatMap collectBranchNames branches
        ++ collectNamesInExpr (A.toValue elseBranch)
    Src.Let defs body ->
      concatMap (collectNamesInDef . A.toValue) defs
        ++ collectNamesInExpr (A.toValue body)
    Src.Case scrutinee branches ->
      collectNamesInExpr (A.toValue scrutinee)
        ++ concatMap (collectNamesInExpr . A.toValue . snd) branches
    Src.Lambda _ body -> collectNamesInExpr (A.toValue body)
    Src.List items -> concatMap (collectNamesInExpr . A.toValue) items
    Src.Binops pairs last_ ->
      concatMap (collectNamesInExpr . A.toValue . fst) pairs
        ++ collectNamesInExpr (A.toValue last_)
    Src.Negate e -> collectNamesInExpr (A.toValue e)
    Src.Access e _ -> collectNamesInExpr (A.toValue e)
    Src.Update (A.At _ n) fields ->
      Name.toChars n : concatMap (collectNamesInExpr . A.toValue . snd) fields
    Src.Record fields ->
      concatMap (collectNamesInExpr . A.toValue . snd) fields
    Src.Tuple e1 e2 rest ->
      collectNamesInExpr (A.toValue e1)
        ++ collectNamesInExpr (A.toValue e2)
        ++ concatMap (collectNamesInExpr . A.toValue) rest
    _ -> []

-- | Collect names from a branch pair.
collectBranchNames :: (Src.Expr, Src.Expr) -> [String]
collectBranchNames (cond, body) =
  collectNamesInExpr (A.toValue cond)
    ++ collectNamesInExpr (A.toValue body)

-- | Collect names in a local definition.
collectNamesInDef :: Src.Def -> [String]
collectNamesInDef (Src.Define _ _ body _) = collectNamesInExpr (A.toValue body)
collectNamesInDef (Src.Destruct _ body) = collectNamesInExpr (A.toValue body)

-- | Collect names referenced in a type expression.
collectNamesInType :: Src.Type_ -> [String]
collectNamesInType t =
  case t of
    Src.TType _ n args ->
      Name.toChars n : concatMap (collectNamesInType . A.toValue) args
    Src.TTypeQual _ modN n args ->
      Name.toChars modN : Name.toChars n : concatMap (collectNamesInType . A.toValue) args
    Src.TLambda a b ->
      collectNamesInType (A.toValue a) ++ collectNamesInType (A.toValue b)
    Src.TRecord fields _ ->
      concatMap (collectNamesInType . A.toValue . snd) fields
    Src.TTuple a b rest ->
      collectNamesInType (A.toValue a)
        ++ collectNamesInType (A.toValue b)
        ++ concatMap (collectNamesInType . A.toValue) rest
    _ -> []

-- | Build the unused-import warning for an import statement.
--
-- The auto-fix removes the entire import line range based on the AST region.
unusedImportWarning :: Src.Import -> LintWarning
unusedImportWarning (Src.Import (A.At region modName) _ _ _) =
  LintWarning
    { _warnRegion = region,
      _warnRule = UnusedImport,
      _warnSeverity = SevWarning,
      _warnMessage =
        "Import of `" ++ Name.toChars modName ++ "` is never used.",
      _warnFix = Just (RemoveLines startLine endLine)
    }
  where
    (startLine, endLine) = regionLineRange region

-- | Extract the 1-indexed start and end lines from a region.
regionLineRange :: A.Region -> (Int, Int)
regionLineRange (A.Region (A.Position startRow _) (A.Position endRow _)) =
  (fromIntegral startRow, fromIntegral endRow)

-- | Rule: detect @case x of True -> a; False -> b@ patterns.
--
-- A case expression with exactly two branches matching the constructors
-- @True@ and @False@ (in either order) should be written as @if x then a else b@.
--
-- @since 0.19.1
checkBooleanCase :: Src.Module -> [LintWarning]
checkBooleanCase modul =
  concatMap (checkBooleanCaseInValue . A.toValue) (Src._values modul)

-- | Search a value definition for boolean case expressions.
checkBooleanCaseInValue :: Src.Value -> [LintWarning]
checkBooleanCaseInValue (Src.Value _ _ expr _) =
  checkBooleanCaseInExpr expr

-- | Walk an expression tree looking for boolean case expressions.
checkBooleanCaseInExpr :: Src.Expr -> [LintWarning]
checkBooleanCaseInExpr (A.At region expr_) =
  caseWarning ++ subWarnings
  where
    caseWarning = maybe [] pure (isBooleanCase region expr_)
    subWarnings = concatMap checkBooleanCaseInExpr (childExprs expr_)

-- | Determine whether an expression is a boolean case; produce a warning if so.
isBooleanCase :: A.Region -> Src.Expr_ -> Maybe LintWarning
isBooleanCase region (Src.Case _ branches)
  | isBooleanBranches branches =
      Just
        LintWarning
          { _warnRegion = region,
            _warnRule = BooleanCase,
            _warnSeverity = SevWarning,
            _warnMessage =
              "This `case` on a Bool can be rewritten as an `if` expression.",
            _warnFix = Nothing
          }
isBooleanCase _ _ = Nothing

-- | Check whether the branches of a case match exactly the Bool constructors.
isBooleanBranches :: [(Src.Pattern, Src.Expr)] -> Bool
isBooleanBranches branches =
  length branches == 2
    && all (isBoolPattern . A.toValue . fst) branches
    && Set.fromList (map (patternCtorName . A.toValue . fst) branches)
      == Set.fromList ["True", "False"]

-- | Check if a pattern is a bare @True@ or @False@ constructor.
isBoolPattern :: Src.Pattern_ -> Bool
isBoolPattern (Src.PCtor _ n []) = Name.toChars n `elem` ["True", "False"]
isBoolPattern _ = False

-- | Extract the constructor name from a pattern (used for set membership).
patternCtorName :: Src.Pattern_ -> String
patternCtorName (Src.PCtor _ n _) = Name.toChars n
patternCtorName _ = ""

-- | Collect direct child expressions of an expression node.
childExprs :: Src.Expr_ -> [Src.Expr]
childExprs expr =
  case expr of
    Src.Call f args -> f : args
    Src.If branches elseBranch ->
      concatMap (\(cond, body) -> [cond, body]) branches ++ [elseBranch]
    Src.Let defs body ->
      concatMap defExprs (map A.toValue defs) ++ [body]
    Src.Case scrutinee branches ->
      scrutinee : map snd branches
    Src.Lambda _ body -> [body]
    Src.List items -> items
    Src.Binops pairs last_ ->
      map fst pairs ++ [last_]
    Src.Negate e -> [e]
    Src.Access e _ -> [e]
    Src.Update _ fields -> map snd fields
    Src.Record fields -> map snd fields
    Src.Tuple e1 e2 rest -> e1 : e2 : rest
    _ -> []

-- | Extract child expressions from a local definition.
defExprs :: Src.Def -> [Src.Expr]
defExprs (Src.Define _ _ body _) = [body]
defExprs (Src.Destruct _ body) = [body]

-- | Rule: detect unnecessary parentheses around already-atomic expressions.
--
-- Parentheses around literals, variables, and simple qualified names add
-- visual noise without aiding readability.
--
-- @since 0.19.1
checkUnnecessaryParens :: Src.Module -> [LintWarning]
checkUnnecessaryParens modul =
  concatMap (checkParensInValue . A.toValue) (Src._values modul)

-- | Search a value definition for unnecessary parentheses.
checkParensInValue :: Src.Value -> [LintWarning]
checkParensInValue (Src.Value _ _ expr _) =
  checkParensInExpr expr

-- | Walk an expression looking for parenthesised atomic sub-expressions.
checkParensInExpr :: Src.Expr -> [LintWarning]
checkParensInExpr located@(A.At region expr_) =
  parenWarnings ++ subWarnings
  where
    parenWarnings = maybe [] pure (unnecessaryParenWarning region located expr_)
    subWarnings = concatMap checkParensInExpr (childExprs expr_)

-- | Produce a warning when a Call with a single argument is wrapping an atomic.
--
-- In practice the Canopy source AST does not represent parentheses as a
-- distinct node.  The closest observable pattern is a 'Tuple' with a single
-- element – but the parser prevents that.  We therefore detect the most common
-- hand-written pattern: @(variable)@ represented as a @Call@ on nothing with
-- an atomic argument.
unnecessaryParenWarning :: A.Region -> Src.Expr -> Src.Expr_ -> Maybe LintWarning
unnecessaryParenWarning region _ (Src.Tuple e1 _ [])
  | isAtomic (A.toValue e1) =
      Just
        LintWarning
          { _warnRegion = region,
            _warnRule = UnnecessaryParens,
            _warnSeverity = SevInfo,
            _warnMessage = "Unnecessary parentheses around a simple expression.",
            _warnFix = Nothing
          }
unnecessaryParenWarning _ _ _ = Nothing

-- | Check whether an expression is atomic (needs no grouping parentheses).
isAtomic :: Src.Expr_ -> Bool
isAtomic (Src.Var _ _) = True
isAtomic (Src.VarQual _ _ _) = True
isAtomic (Src.Int _) = True
isAtomic (Src.Float _) = True
isAtomic (Src.Str _) = True
isAtomic (Src.Chr _) = True
isAtomic Src.Unit = True
isAtomic _ = False

-- | Rule: @[a] ++ [b]@ should be written @[a, b]@.
--
-- Concatenating two list literals produces an unnecessary intermediate
-- allocation.  The fix is to merge both literals into one.
--
-- @since 0.19.1
checkDropConcatOfLists :: Src.Module -> [LintWarning]
checkDropConcatOfLists modul =
  concatMap (checkConcatInValue . A.toValue) (Src._values modul)

-- | Search a value definition for @[x] ++ [y]@ patterns.
checkConcatInValue :: Src.Value -> [LintWarning]
checkConcatInValue (Src.Value _ _ expr _) =
  checkConcatInExpr expr

-- | Walk an expression looking for @[a] ++ [b]@ binop chains.
checkConcatInExpr :: Src.Expr -> [LintWarning]
checkConcatInExpr (A.At region expr_) =
  concatWarnings ++ subWarnings
  where
    concatWarnings = maybe [] pure (dropConcatWarning region expr_)
    subWarnings = concatMap checkConcatInExpr (childExprs expr_)

-- | Detect @[a] ++ [b]@ and produce a warning.
dropConcatWarning :: A.Region -> Src.Expr_ -> Maybe LintWarning
dropConcatWarning region (Src.Binops pairs _)
  | any isListConcatPair pairs =
      Just
        LintWarning
          { _warnRegion = region,
            _warnRule = DropConcatOfLists,
            _warnSeverity = SevWarning,
            _warnMessage =
              "`[a] ++ [b]` can be simplified to `[a, b]`.",
            _warnFix = Nothing
          }
dropConcatWarning _ _ = Nothing

-- | Check whether a binop pair is a @++ [...]@ applied to a @[...]@ left-hand side.
isListConcatPair :: (Src.Expr, A.Located Name.Name) -> Bool
isListConcatPair (lhs, A.At _ op) =
  Name.toChars op == "++" && isList (A.toValue lhs)

-- | Check whether an expression is a list literal.
isList :: Src.Expr_ -> Bool
isList (Src.List _) = True
isList _ = False

-- | Rule: @[a] ++ list@ should be written @a :: list@.
--
-- Prepending a single-element list literal via @++@ creates an unnecessary
-- allocation.  Using @::@ (cons) is more idiomatic and more efficient.
--
-- @since 0.19.1
checkUseConsOverConcat :: Src.Module -> [LintWarning]
checkUseConsOverConcat modul =
  concatMap (checkConsInValue . A.toValue) (Src._values modul)

-- | Search a value definition for @[a] ++ list@ patterns.
checkConsInValue :: Src.Value -> [LintWarning]
checkConsInValue (Src.Value _ _ expr _) =
  checkConsInExpr expr

-- | Walk an expression looking for @[a] ++ list@ binop chains.
checkConsInExpr :: Src.Expr -> [LintWarning]
checkConsInExpr (A.At region expr_) =
  consWarnings ++ subWarnings
  where
    consWarnings = maybe [] pure (useConsWarning region expr_)
    subWarnings = concatMap checkConsInExpr (childExprs expr_)

-- | Detect @[a] ++ list@ where the right-hand side is not a literal.
useConsWarning :: A.Region -> Src.Expr_ -> Maybe LintWarning
useConsWarning region (Src.Binops pairs rhs)
  | any isSingletonConcatPair pairs
      && not (isList (A.toValue rhs)) =
      Just
        LintWarning
          { _warnRegion = region,
            _warnRule = UseConsOverConcat,
            _warnSeverity = SevInfo,
            _warnMessage =
              "`[a] ++ list` can be simplified to `a :: list`.",
            _warnFix = Nothing
          }
useConsWarning _ _ = Nothing

-- | Check whether the left-hand side of a @++@ is a single-element list literal.
isSingletonConcatPair :: (Src.Expr, A.Located Name.Name) -> Bool
isSingletonConcatPair (lhs, A.At _ op) =
  Name.toChars op == "++" && isSingleton (A.toValue lhs)

-- | Check whether an expression is a list literal with exactly one element.
isSingleton :: Src.Expr_ -> Bool
isSingleton (Src.List [_]) = True
isSingleton _ = False

-- | Rule: top-level value definitions without a type annotation.
--
-- Type annotations on top-level definitions improve readability and help
-- the compiler produce better error messages.  Definitions with parameters
-- are also checked since they are function definitions.
--
-- @since 0.19.1
checkMissingTypeAnnotation :: Src.Module -> [LintWarning]
checkMissingTypeAnnotation modul =
  mapMaybe (checkAnnotation . A.toValue) (Src._values modul)

-- | Produce a warning for a value without a type annotation.
checkAnnotation :: Src.Value -> Maybe LintWarning
checkAnnotation (Src.Value (A.At region name_) _patterns _body Nothing) =
  Just
    LintWarning
      { _warnRegion = region,
        _warnRule = MissingTypeAnnotation,
        _warnSeverity = SevWarning,
        _warnMessage =
          "Top-level definition `"
            ++ Name.toChars name_
            ++ "` is missing a type annotation.",
        _warnFix = Nothing
      }
checkAnnotation _ = Nothing

-- REPORTING

-- | Print all warnings to the terminal in human-readable form.
--
-- Warnings are grouped by rule and printed with their source region and
-- message.  An empty list produces no output (silent success).
reportTerminal :: [LintWarning] -> IO ()
reportTerminal [] = Print.println [c|{green|No lint warnings found.}|]
reportTerminal warnings = mapM_ printWarning warnings

-- | Print a single warning in terminal format, including its severity.
printWarning :: LintWarning -> IO ()
printWarning w = do
  let region = renderRegion (_warnRegion w)
      severity = severityName (_warnSeverity w)
      rule = ruleName (_warnRule w)
      msg = _warnMessage w
      sevColor = case _warnSeverity w of
        SevError -> [c|{red|#{severity}}|]
        SevWarning -> [c|{yellow|#{severity}}|]
        _ -> [c|{cyan|#{severity}}|]
  Print.print [c|{cyan|#{region}} [|]
  Print.print sevColor
  Print.println [c|] [#{rule}]|]
  Print.println [c|  #{msg}|]
  maybe (pure ()) printFix (_warnFix w)

-- | Print the auto-fix hint for a warning.
printFix :: LintFix -> IO ()
printFix (TextReplace orig repl) =
  Print.println [c|  {green|Fix:} replace `#{orig}` with `#{repl}`|]
printFix (RemoveLines start end)
  | start == end = Print.println [c|  {green|Fix:} remove line #{startStr}|]
  | otherwise = Print.println [c|  {green|Fix:} remove lines #{startStr}-#{endStr}|]
  where
    startStr = show start
    endStr = show end

-- | Render a source region as a human-readable @line:col-line:col@ string.
renderRegion :: A.Region -> String
renderRegion (A.Region (A.Position startLine startCol) (A.Position endLine endCol)) =
  showWord16 startLine ++ ":" ++ showWord16 startCol
    ++ "-"
    ++ showWord16 endLine ++ ":" ++ showWord16 endCol

-- | Convert a 'Word.Word16' to a decimal string.
showWord16 :: Word.Word16 -> String
showWord16 = show

-- | Output all warnings as a JSON array.
reportJson :: [LintWarning] -> IO ()
reportJson warnings =
  LBS.putStr (BB.toLazyByteString (Encode.encode (Encode.list encodeWarning warnings)))
    >> IO.hPutStrLn IO.stdout ""

-- | Encode a single warning as a JSON object, including its severity.
encodeWarning :: LintWarning -> Encode.Value
encodeWarning w =
  Encode.object
    [ (JsonString.fromChars "rule", Encode.string (JsonString.fromChars (ruleName (_warnRule w)))),
      (JsonString.fromChars "severity", Encode.string (JsonString.fromChars (severityName (_warnSeverity w)))),
      (JsonString.fromChars "message", Encode.string (JsonString.fromChars (_warnMessage w))),
      (JsonString.fromChars "region", encodeRegion (_warnRegion w))
    ]

-- | Encode a source region as a JSON object.
encodeRegion :: A.Region -> Encode.Value
encodeRegion (A.Region (A.Position sl sc) (A.Position el ec)) =
  Encode.object
    [ (JsonString.fromChars "start", encodePosition sl sc),
      (JsonString.fromChars "end", encodePosition el ec)
    ]

-- | Encode a source position as a JSON object.
encodePosition :: Word.Word16 -> Word.Word16 -> Encode.Value
encodePosition line col =
  Encode.object
    [ (JsonString.fromChars "line", Encode.int (fromIntegral line)),
      (JsonString.fromChars "column", Encode.int (fromIntegral col))
    ]

-- | Print a summary line.
--
-- Only warnings at 'SevError' severity are considered blocking.
-- Info and warning-level issues are reported but do not cause a
-- non-zero exit summary.
reportExitSummary :: [LintWarning] -> IO ()
reportExitSummary [] = pure ()
reportExitSummary warnings =
  Print.println [c|#{summaryText}|]
  where
    total = length warnings
    errors = length (filter (\w -> _warnSeverity w == SevError) warnings)
    summaryText = summaryLine ++ errorSuffix
    summaryLine =
      show total
        ++ " issue"
        ++ (if total == 1 then "" else "s")
        ++ " found"
    errorSuffix
      | errors > 0 =
          " (" ++ show errors ++ " error"
            ++ (if errors == 1 then "" else "s")
            ++ ")."
      | otherwise = "."

-- | Return the canonical string name for a lint rule.
ruleName :: LintRule -> String
ruleName UnusedImport = "UnusedImport"
ruleName BooleanCase = "BooleanCase"
ruleName UnnecessaryParens = "UnnecessaryParens"
ruleName DropConcatOfLists = "DropConcatOfLists"
ruleName UseConsOverConcat = "UseConsOverConcat"
ruleName MissingTypeAnnotation = "MissingTypeAnnotation"

-- | Return the human-readable name for a severity level.
severityName :: Severity -> String
severityName Off = "off"
severityName SevInfo = "info"
severityName SevWarning = "warning"
severityName SevError = "error"

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

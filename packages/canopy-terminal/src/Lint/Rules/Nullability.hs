{-# LANGUAGE OverloadedStrings #-}

-- | Lint rules for sketchy nullability and unsafe operations.
--
-- Detects common patterns that are technically valid but likely indicate
-- bugs or code quality issues related to Maybe handling, silent error
-- fallbacks, and unnecessary pattern matching.
--
-- == Rules
--
-- * 'checkSketchyMaybe' - Case on Maybe where inner type has a meaningful
--   zero value (Int 0, String "", List [])
-- * 'checkRedundantMaybeWrap' - Function that always returns Just, never Nothing
-- * 'checkUnnecessaryPatternMatch' - Case on unit or single-constructor type
-- * 'checkSilentFallback' - Case on parsing result that silently returns a default
-- * 'checkAlwaysFalseComparison' - Equality comparison of constructors from different types
-- * 'checkUnreachableCode' - Let bindings after expressions that cannot continue
--
-- @since 0.19.2
module Lint.Rules.Nullability
  ( checkSketchyMaybe,
    checkRedundantMaybeWrap,
    checkUnnecessaryPatternMatch,
    checkSilentFallback,
    checkAlwaysFalseComparison,
    checkUnreachableCode,
  )
where

import qualified AST.Source as Src
import qualified Canopy.Data.Name as Name
import Lint.Rules.Helpers (childExprs)
import Lint.Types
  ( LintRule (..),
    LintWarning (..),
    Severity (..),
  )
import qualified Reporting.Annotation as Ann

-- SKETCHY MAYBE CHECK

-- | Rule: detect case-on-Maybe where the Just branch checks for a
-- \"zero\" value (like @n /= 0@ or @n > 0@), suggesting the author
-- may be conflating Nothing with a meaningful zero.
--
-- Triggers on patterns like:
--
-- @
-- case maybeCount of
--   Just n -> n /= 0
--   Nothing -> False
-- @
--
-- The value @0@ is valid for @Int@ but would behave the same as
-- @Nothing@ in the above check, which is almost certainly a bug.
--
-- @since 0.19.2
checkSketchyMaybe :: Src.Module -> [LintWarning]
checkSketchyMaybe modul =
  concatMap (checkSketchyInValue . Ann.toValue) (Src._values modul)

-- | Check a value definition for sketchy Maybe patterns.
checkSketchyInValue :: Src.Value -> [LintWarning]
checkSketchyInValue (Src.Value _ _ expr _ _) =
  checkSketchyInExpr expr

-- | Walk the expression tree for sketchy Maybe case patterns.
checkSketchyInExpr :: Src.Expr -> [LintWarning]
checkSketchyInExpr (Ann.At region expr_) =
  localWarnings ++ subWarnings
  where
    localWarnings = sketchyCaseWarning region expr_
    subWarnings = concatMap checkSketchyInExpr (childExprs expr_)

-- | Detect a case with Just/Nothing branches where the Just branch
-- contains a zero-comparison on the bound variable.
sketchyCaseWarning :: Ann.Region -> Src.Expr_ -> [LintWarning]
sketchyCaseWarning region (Src.Case _ branches)
  | isMaybeCase branches && hasZeroCheckInJustBranch branches =
      [sketchyMaybeWarn region]
sketchyCaseWarning _ _ = []

-- | Check whether branches match the Just/Nothing pattern.
isMaybeCase :: [(Src.Pattern, Src.Expr)] -> Bool
isMaybeCase branches =
  length branches == 2
    && any (isJustPattern . Ann.toValue . fst) branches
    && any (isNothingPattern . Ann.toValue . fst) branches

-- | Check if a pattern is @Just x@.
isJustPattern :: Src.Pattern_ -> Bool
isJustPattern (Src.PCtor _ name [_]) = Name.toChars name == "Just"
isJustPattern (Src.PCtorQual _ _ name [_]) = Name.toChars name == "Just"
isJustPattern _ = False

-- | Check if a pattern is @Nothing@.
isNothingPattern :: Src.Pattern_ -> Bool
isNothingPattern (Src.PCtor _ name []) = Name.toChars name == "Nothing"
isNothingPattern (Src.PCtorQual _ _ name []) = Name.toChars name == "Nothing"
isNothingPattern _ = False

-- | Check whether the Just branch contains a comparison against zero.
hasZeroCheckInJustBranch :: [(Src.Pattern, Src.Expr)] -> Bool
hasZeroCheckInJustBranch = any checkBranch
  where
    checkBranch (Ann.At _ pat_, body) =
      isJustPattern pat_ && containsZeroComparison body

-- | Check whether an expression contains a comparison with zero
-- (like @n /= 0@, @n > 0@, @n == 0@).
containsZeroComparison :: Src.Expr -> Bool
containsZeroComparison (Ann.At _ (Src.Binops pairs lastExpr)) =
  hasZeroOperand (map fst pairs ++ [lastExpr])
containsZeroComparison (Ann.At _ expr_) =
  any containsZeroComparison (childExprs expr_)

-- | Check if any operand in a binop chain is the integer literal 0.
hasZeroOperand :: [Src.Expr] -> Bool
hasZeroOperand = any isZeroLiteral

-- | Check if an expression is the integer literal 0.
isZeroLiteral :: Src.Expr -> Bool
isZeroLiteral (Ann.At _ (Src.Int 0)) = True
isZeroLiteral _ = False

-- | Build a sketchy Maybe warning.
sketchyMaybeWarn :: Ann.Region -> LintWarning
sketchyMaybeWarn region =
  LintWarning
    { _warnRegion = region,
      _warnRule = SketchyMaybeCheck,
      _warnSeverity = SevWarning,
      _warnMessage =
        "Case on Maybe with a zero-comparison in the Just branch. "
          ++ "The value 0 may be valid but is treated like Nothing. "
          ++ "Consider explicit threshold checks.",
      _warnFix = Nothing
    }

-- REDUNDANT MAYBE WRAP

-- | Rule: detect functions whose body is always @Just expr@.
--
-- A function that always returns @Just@ and never returns @Nothing@
-- adds no information with the Maybe wrapper. Either the return type
-- should be the unwrapped type, or there is a missing Nothing path.
--
-- @since 0.19.2
checkRedundantMaybeWrap :: Src.Module -> [LintWarning]
checkRedundantMaybeWrap modul =
  concatMap (checkRedundantInValue . Ann.toValue) (Src._values modul)

-- | Check a value for redundant Maybe wrapping.
checkRedundantInValue :: Src.Value -> [LintWarning]
checkRedundantInValue (Src.Value (Ann.At region name_) _ body _ _)
  | isAlwaysJust (Ann.toValue body) =
      [redundantMaybeWarn region (Name.toChars name_)]
checkRedundantInValue _ = []

-- | Check if an expression is a direct @Just expr@ call.
isAlwaysJust :: Src.Expr_ -> Bool
isAlwaysJust (Src.Call (Ann.At _ (Src.Var Src.CapVar name)) [_]) =
  Name.toChars name == "Just"
isAlwaysJust _ = False

-- | Build a redundant Maybe wrapping warning.
redundantMaybeWarn :: Ann.Region -> String -> LintWarning
redundantMaybeWarn region funcName =
  LintWarning
    { _warnRegion = region,
      _warnRule = RedundantMaybeWrap,
      _warnSeverity = SevWarning,
      _warnMessage =
        "`" ++ funcName ++ "` always returns Just and never Nothing. "
          ++ "Consider removing the Maybe wrapper or adding a Nothing path.",
      _warnFix = Nothing
    }

-- UNNECESSARY PATTERN MATCH

-- | Rule: detect case expressions on unit @()@ which can never fail.
--
-- Matching on a single-constructor type adds complexity without value.
-- Replace with a direct expression.
--
-- @since 0.19.2
checkUnnecessaryPatternMatch :: Src.Module -> [LintWarning]
checkUnnecessaryPatternMatch modul =
  concatMap (checkUnnecessaryInValue . Ann.toValue) (Src._values modul)

-- | Check a value for unnecessary pattern matches.
checkUnnecessaryInValue :: Src.Value -> [LintWarning]
checkUnnecessaryInValue (Src.Value _ _ expr _ _) =
  checkUnnecessaryInExpr expr

-- | Walk the expression tree for unnecessary case expressions.
checkUnnecessaryInExpr :: Src.Expr -> [LintWarning]
checkUnnecessaryInExpr (Ann.At region expr_) =
  localWarnings ++ subWarnings
  where
    localWarnings = unnecessaryCaseWarning region expr_
    subWarnings = concatMap checkUnnecessaryInExpr (childExprs expr_)

-- | Detect case on unit (single constructor, never fails).
unnecessaryCaseWarning :: Ann.Region -> Src.Expr_ -> [LintWarning]
unnecessaryCaseWarning region (Src.Case _ [(Ann.At _ Src.PUnit, _)]) =
  [unnecessaryMatchWarn region]
unnecessaryCaseWarning _ _ = []

-- | Build an unnecessary pattern match warning.
unnecessaryMatchWarn :: Ann.Region -> LintWarning
unnecessaryMatchWarn region =
  LintWarning
    { _warnRegion = region,
      _warnRule = UnnecessaryPatternMatch,
      _warnSeverity = SevWarning,
      _warnMessage =
        "Case on unit `()` can never fail. "
          ++ "Remove the case and use the body expression directly.",
      _warnFix = Nothing
    }

-- SILENT FALLBACK

-- | Rule: detect case on a parsing result where the error branch
-- silently returns a default literal value.
--
-- Patterns like:
--
-- @
-- case String.toInt input of
--   Just n -> n
--   Nothing -> 0
-- @
--
-- The silent fallback to @0@ hides parse failures. Consider propagating
-- the error with @Maybe@ or @Result@.
--
-- @since 0.19.2
checkSilentFallback :: Src.Module -> [LintWarning]
checkSilentFallback modul =
  concatMap (checkFallbackInValue . Ann.toValue) (Src._values modul)

-- | Check a value for silent fallback patterns.
checkFallbackInValue :: Src.Value -> [LintWarning]
checkFallbackInValue (Src.Value _ _ expr _ _) =
  checkFallbackInExpr expr

-- | Walk expression tree for silent fallback case patterns.
checkFallbackInExpr :: Src.Expr -> [LintWarning]
checkFallbackInExpr (Ann.At region expr_) =
  localWarnings ++ subWarnings
  where
    localWarnings = silentFallbackWarning region expr_
    subWarnings = concatMap checkFallbackInExpr (childExprs expr_)

-- | Detect a Maybe case where Nothing branch returns a literal default.
silentFallbackWarning :: Ann.Region -> Src.Expr_ -> [LintWarning]
silentFallbackWarning region (Src.Case _ branches)
  | isMaybeCase branches && hasLiteralNothingBranch branches =
      [silentFallbackWarn region]
silentFallbackWarning _ _ = []

-- | Check whether the Nothing branch returns a literal value.
hasLiteralNothingBranch :: [(Src.Pattern, Src.Expr)] -> Bool
hasLiteralNothingBranch = any checkBranch
  where
    checkBranch (Ann.At _ pat_, body) =
      isNothingPattern pat_ && isLiteral (Ann.toValue body)

-- | Check if an expression is a simple literal (Int, Float, String, Char).
isLiteral :: Src.Expr_ -> Bool
isLiteral (Src.Int _) = True
isLiteral (Src.Float _) = True
isLiteral (Src.Str _) = True
isLiteral (Src.Chr _) = True
isLiteral (Src.List []) = True
isLiteral _ = False

-- | Build a silent fallback warning.
silentFallbackWarn :: Ann.Region -> LintWarning
silentFallbackWarn region =
  LintWarning
    { _warnRegion = region,
      _warnRule = SilentFallback,
      _warnSeverity = SevWarning,
      _warnMessage =
        "Nothing branch returns a literal default, silently hiding failures. "
          ++ "Consider propagating the error with Maybe or Result.",
      _warnFix = Nothing
    }

-- ALWAYS FALSE COMPARISON

-- | Rule: detect equality comparisons between constructors of
-- different custom types.
--
-- Comparing constructors from different union types (e.g., @Red == Small@)
-- will always be False. This usually indicates a logic error.
--
-- @since 0.19.2
checkAlwaysFalseComparison :: Src.Module -> [LintWarning]
checkAlwaysFalseComparison modul =
  concatMap (checkComparisonInValue . Ann.toValue) (Src._values modul)

-- | Check a value for always-false comparisons.
checkComparisonInValue :: Src.Value -> [LintWarning]
checkComparisonInValue (Src.Value _ _ expr _ _) =
  checkComparisonInExpr expr

-- | Walk expression tree for always-false equality comparisons.
checkComparisonInExpr :: Src.Expr -> [LintWarning]
checkComparisonInExpr (Ann.At region expr_) =
  localWarnings ++ subWarnings
  where
    localWarnings = alwaysFalseWarning region expr_
    subWarnings = concatMap checkComparisonInExpr (childExprs expr_)

-- | Detect binop equality between two uppercase constructors
-- that appear to be from different types.
alwaysFalseWarning :: Ann.Region -> Src.Expr_ -> [LintWarning]
alwaysFalseWarning region (Src.Binops [(left, Ann.At _ opName)] right)
  | isEqualityOp opName
      && isConstructorExpr (Ann.toValue left)
      && isConstructorExpr (Ann.toValue right)
      && differentConstructors (Ann.toValue left) (Ann.toValue right) =
      [alwaysFalseWarn region (ctorName (Ann.toValue left)) (ctorName (Ann.toValue right))]
alwaysFalseWarning _ _ = []

-- | Check if an operator is == or /=.
isEqualityOp :: Name.Name -> Bool
isEqualityOp name =
  Name.toChars name `elem` ["==", "/="]

-- | Check if an expression is an uppercase constructor reference.
isConstructorExpr :: Src.Expr_ -> Bool
isConstructorExpr (Src.Var Src.CapVar _) = True
isConstructorExpr _ = False

-- | Check if two constructors have different names (heuristic for
-- different types at the source level).
differentConstructors :: Src.Expr_ -> Src.Expr_ -> Bool
differentConstructors (Src.Var Src.CapVar a) (Src.Var Src.CapVar b) =
  Name.toChars a /= Name.toChars b
differentConstructors _ _ = False

-- | Extract the constructor name from an expression.
ctorName :: Src.Expr_ -> String
ctorName (Src.Var Src.CapVar name) = Name.toChars name
ctorName _ = "<unknown>"

-- | Build an always-false comparison warning.
alwaysFalseWarn :: Ann.Region -> String -> String -> LintWarning
alwaysFalseWarn region left right =
  LintWarning
    { _warnRegion = region,
      _warnRule = AlwaysFalseComparison,
      _warnSeverity = SevError,
      _warnMessage =
        "Comparing `" ++ left ++ "` with `" ++ right
          ++ "` will always be False because they are constructors "
          ++ "of different types.",
      _warnFix = Nothing
    }

-- UNREACHABLE CODE

-- | Rule: detect let bindings whose body references definitions
-- that appear after a case expression where all branches return
-- a value (suggesting the code after the case is unreachable).
--
-- This is a simplified heuristic that detects the pattern of a
-- let binding whose sole definition is a case expression, followed
-- by additional code that is never reached.
--
-- @since 0.19.2
checkUnreachableCode :: Src.Module -> [LintWarning]
checkUnreachableCode modul =
  concatMap (checkUnreachableInValue . Ann.toValue) (Src._values modul)

-- | Check a value for unreachable code patterns.
checkUnreachableInValue :: Src.Value -> [LintWarning]
checkUnreachableInValue (Src.Value _ _ expr _ _) =
  checkUnreachableInExpr expr

-- | Walk expression tree for unreachable code patterns.
checkUnreachableInExpr :: Src.Expr -> [LintWarning]
checkUnreachableInExpr (Ann.At region expr_) =
  localWarnings ++ subWarnings
  where
    localWarnings = unreachableWarning region expr_
    subWarnings = concatMap checkUnreachableInExpr (childExprs expr_)

-- | Detect let expressions with definitions after an exhaustive case
-- where all branches are simple return values (not bindings).
unreachableWarning :: Ann.Region -> Src.Expr_ -> [LintWarning]
unreachableWarning _ (Src.Let defs body)
  | hasDefsAfterExhaustiveCase defs body = [unreachableWarn (Ann.toRegion body)]
unreachableWarning _ _ = []

-- | Check if any definition in a let block is preceded by a case
-- expression that exhaustively returns in all branches, making
-- subsequent definitions unreachable.
hasDefsAfterExhaustiveCase :: [Ann.Located Src.Def] -> Src.Expr -> Bool
hasDefsAfterExhaustiveCase defs _body =
  any isExhaustiveCaseDef (initSafe defs)

-- | Safe init that returns empty for empty lists.
initSafe :: [a] -> [a]
initSafe [] = []
initSafe xs = init xs

-- | Check if a definition body is an exhaustive case (has both
-- Just and Nothing, or multiple branches all returning literals).
isExhaustiveCaseDef :: Ann.Located Src.Def -> Bool
isExhaustiveCaseDef (Ann.At _ (Src.Define _ _ body _)) =
  isExhaustiveCase (Ann.toValue body)
isExhaustiveCaseDef (Ann.At _ (Src.Destruct _ body)) =
  isExhaustiveCase (Ann.toValue body)

-- | Check if an expression is an exhaustive case where all branches
-- return simple values (not bindings or further computation).
isExhaustiveCase :: Src.Expr_ -> Bool
isExhaustiveCase (Src.Case _ branches) =
  length branches >= 2 && all (isSimpleReturn . Ann.toValue . snd) branches
isExhaustiveCase _ = False

-- | Check if an expression is a simple return value (literal or variable).
isSimpleReturn :: Src.Expr_ -> Bool
isSimpleReturn (Src.Int _) = True
isSimpleReturn (Src.Float _) = True
isSimpleReturn (Src.Str _) = True
isSimpleReturn (Src.Chr _) = True
isSimpleReturn (Src.Var _ _) = True
isSimpleReturn (Src.VarQual _ _ _) = True
isSimpleReturn Src.Unit = True
isSimpleReturn _ = False

-- | Build an unreachable code warning.
unreachableWarn :: Ann.Region -> LintWarning
unreachableWarn region =
  LintWarning
    { _warnRegion = region,
      _warnRule = UnreachableCode,
      _warnSeverity = SevError,
      _warnMessage =
        "Code after an exhaustive case expression is unreachable. "
          ++ "All branches return a value, so this code can never execute.",
      _warnFix = Nothing
    }

{-# LANGUAGE OverloadedStrings #-}

-- | Lint rules for code style and readability.
--
-- Includes rules for boolean case expressions, unnecessary parentheses,
-- missing type annotations, and inconsistent naming conventions.
--
-- @since 0.19.1
module Lint.Rules.Style
  ( checkBooleanCase,
    checkUnnecessaryParens,
    checkMissingTypeAnnotation,
    checkInconsistentNaming,
  )
where

import qualified AST.Source as Src
import Data.Char (isUpper)
import Data.Maybe (mapMaybe)
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import Lint.Rules.Helpers (childExprs)
import Lint.Types
  ( LintRule (..),
    LintWarning (..),
    Severity (..),
  )
import qualified Reporting.Annotation as Ann

-- BOOLEAN CASE

-- | Rule: detect @case x of True -> a; False -> b@ patterns.
--
-- A case expression with exactly two branches matching the constructors
-- @True@ and @False@ (in either order) should be written as @if x then a else b@.
--
-- @since 0.19.1
checkBooleanCase :: Src.Module -> [LintWarning]
checkBooleanCase modul =
  concatMap (checkBooleanCaseInValue . Ann.toValue) (Src._values modul)

-- | Search a value definition for boolean case expressions.
checkBooleanCaseInValue :: Src.Value -> [LintWarning]
checkBooleanCaseInValue (Src.Value _ _ expr _) =
  checkBooleanCaseInExpr expr

-- | Walk an expression tree looking for boolean case expressions.
checkBooleanCaseInExpr :: Src.Expr -> [LintWarning]
checkBooleanCaseInExpr (Ann.At region expr_) =
  caseWarning ++ subWarnings
  where
    caseWarning = maybe [] pure (isBooleanCase region expr_)
    subWarnings = concatMap checkBooleanCaseInExpr (childExprs expr_)

-- | Determine whether an expression is a boolean case; produce a warning if so.
isBooleanCase :: Ann.Region -> Src.Expr_ -> Maybe LintWarning
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
    && all (isBoolPattern . Ann.toValue . fst) branches
    && Set.fromList (map (patternCtorName . Ann.toValue . fst) branches)
      == Set.fromList ["True", "False"]

-- | Check if a pattern matches a boolean constructor.
isBoolPattern :: Src.Pattern_ -> Bool
isBoolPattern (Src.PCtor _ n []) = Name.toChars n `elem` ["True", "False"]
isBoolPattern _ = False

-- | Extract the constructor name from a pattern.
patternCtorName :: Src.Pattern_ -> String
patternCtorName (Src.PCtor _ n _) = Name.toChars n
patternCtorName _ = ""

-- UNNECESSARY PARENS

-- | Rule: detect unnecessary parentheses around already-atomic expressions.
--
-- Parentheses around literals, variables, and simple qualified names add
-- visual noise without aiding readability.
--
-- @since 0.19.1
checkUnnecessaryParens :: Src.Module -> [LintWarning]
checkUnnecessaryParens modul =
  concatMap (checkParensInValue . Ann.toValue) (Src._values modul)

-- | Search a value definition for unnecessary parentheses.
checkParensInValue :: Src.Value -> [LintWarning]
checkParensInValue (Src.Value _ _ expr _) =
  checkParensInExpr expr

-- | Walk an expression looking for parenthesised atomic sub-expressions.
checkParensInExpr :: Src.Expr -> [LintWarning]
checkParensInExpr located@(Ann.At region expr_) =
  parenWarnings ++ subWarnings
  where
    parenWarnings = maybe [] pure (unnecessaryParenWarning region located expr_)
    subWarnings = concatMap checkParensInExpr (childExprs expr_)

-- | Produce a warning when a Tuple with a single element wraps an atomic.
unnecessaryParenWarning :: Ann.Region -> Src.Expr -> Src.Expr_ -> Maybe LintWarning
unnecessaryParenWarning region _ (Src.Tuple e1 _ [])
  | isAtomic (Ann.toValue e1) =
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

-- MISSING TYPE ANNOTATION

-- | Rule: top-level value definitions without a type annotation.
--
-- Type annotations on top-level definitions improve readability and help
-- the compiler produce better error messages.
--
-- @since 0.19.1
checkMissingTypeAnnotation :: Src.Module -> [LintWarning]
checkMissingTypeAnnotation modul =
  mapMaybe (checkAnnotation . Ann.toValue) (Src._values modul)

-- | Produce a warning for a value without a type annotation.
checkAnnotation :: Src.Value -> Maybe LintWarning
checkAnnotation (Src.Value (Ann.At region name_) _patterns _body Nothing) =
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

-- INCONSISTENT NAMING

-- | Rule: detect camelCase\/snake_case mixing in a module.
--
-- All top-level names in a module should follow the same convention.
-- This rule flags names that contain underscores when the majority
-- use camelCase, and vice versa.
--
-- @since 0.19.2
checkInconsistentNaming :: Src.Module -> [LintWarning]
checkInconsistentNaming modul =
  flagMinorityConvention allNames
  where
    allNames = map extractNameInfo (Src._values modul)

-- | Extract the name string and region from a value definition.
extractNameInfo :: Ann.Located Src.Value -> (Ann.Region, String)
extractNameInfo (Ann.At _ (Src.Value (Ann.At region name_) _ _ _)) =
  (region, Name.toChars name_)

-- | Classify name convention.
data NamingConvention = CamelCase | SnakeCase | OtherConvention
  deriving (Eq)

-- | Determine the naming convention of a string.
classifyName :: String -> NamingConvention
classifyName name_
  | '_' `elem` name_ = SnakeCase
  | hasInternalUpper name_ = CamelCase
  | otherwise = OtherConvention

-- | Check whether a name has internal uppercase letters (camelCase).
hasInternalUpper :: String -> Bool
hasInternalUpper (_ : rest) = any isUpper rest
hasInternalUpper _ = False

-- | Flag names that do not match the majority convention.
flagMinorityConvention :: [(Ann.Region, String)] -> [LintWarning]
flagMinorityConvention names
  | camelCount >= snakeCount = mapMaybe (flagIfSnake) names
  | otherwise = mapMaybe (flagIfCamel) names
  where
    conventions = map (classifyName . snd) names
    camelCount = length (filter (== CamelCase) conventions)
    snakeCount = length (filter (== SnakeCase) conventions)

-- | Flag a name if it uses snake_case.
flagIfSnake :: (Ann.Region, String) -> Maybe LintWarning
flagIfSnake (region, name_)
  | classifyName name_ == SnakeCase = Just (namingWarn region name_ "snake_case" "camelCase")
  | otherwise = Nothing

-- | Flag a name if it uses camelCase.
flagIfCamel :: (Ann.Region, String) -> Maybe LintWarning
flagIfCamel (region, name_)
  | classifyName name_ == CamelCase = Just (namingWarn region name_ "camelCase" "snake_case")
  | otherwise = Nothing

-- | Build a naming inconsistency warning.
namingWarn :: Ann.Region -> String -> String -> String -> LintWarning
namingWarn region name_ usedStyle majorStyle =
  LintWarning
    { _warnRegion = region,
      _warnRule = InconsistentNaming,
      _warnSeverity = SevInfo,
      _warnMessage =
        "`" ++ name_ ++ "` uses " ++ usedStyle
          ++ " but most names use "
          ++ majorStyle
          ++ ".",
      _warnFix = Nothing
    }

{-# LANGUAGE OverloadedStrings #-}

-- | Lint rules for code complexity and size.
--
-- Includes rules for detecting functions with too many arguments,
-- overly long function bodies, magic numbers, and string concatenation
-- inside loops.
--
-- @since 0.19.2
module Lint.Rules.Complexity
  ( checkTooManyArguments,
    checkLongFunction,
    checkMagicNumber,
    checkStringConcatInLoop,
  )
where

import qualified AST.Source as Src
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

-- TOO MANY ARGUMENTS

-- | Rule: warn on functions with more than 4 arguments.
--
-- Functions with many parameters are hard to call correctly.  Group
-- related parameters into a record type or split the function.
--
-- @since 0.19.2
checkTooManyArguments :: Src.Module -> [LintWarning]
checkTooManyArguments modul =
  mapMaybe (checkArgCount . Ann.toValue) (Src._values modul)

-- | Maximum number of arguments before a warning is emitted.
maxArguments :: Int
maxArguments = 4

-- | Check the argument count of a single value definition.
checkArgCount :: Src.Value -> Maybe LintWarning
checkArgCount (Src.Value (Ann.At region name_) _ _ (Just annot) _)
  | countTypeArgs annot > maxArguments =
      Just (tooManyArgsWarn region (Name.toChars name_))
checkArgCount (Src.Value _ args _ _ _)
  | length args > maxArguments =
      Just (tooManyArgsWarnNoRegion args)
checkArgCount _ = Nothing

-- | Count the number of arrow types in a type annotation.
countTypeArgs :: Src.Type -> Int
countTypeArgs (Ann.At _ (Src.TLambda _ rest)) =
  1 + countTypeArgs rest
countTypeArgs _ = 0

-- | Build a too-many-arguments warning from a named region.
tooManyArgsWarn :: Ann.Region -> String -> LintWarning
tooManyArgsWarn region funcName =
  LintWarning
    { _warnRegion = region,
      _warnRule = TooManyArguments,
      _warnSeverity = SevWarning,
      _warnMessage =
        "`" ++ funcName ++ "` has more than "
          ++ show maxArguments
          ++ " arguments. Consider grouping into a record.",
      _warnFix = Nothing
    }

-- | Build a too-many-arguments warning from pattern list.
tooManyArgsWarnNoRegion :: [Src.Pattern] -> LintWarning
tooManyArgsWarnNoRegion pats =
  LintWarning
    { _warnRegion = regionFromPats pats,
      _warnRule = TooManyArguments,
      _warnSeverity = SevWarning,
      _warnMessage =
        "Function has more than "
          ++ show maxArguments
          ++ " arguments. Consider grouping into a record.",
      _warnFix = Nothing
    }

-- | Extract a region spanning all patterns.
regionFromPats :: [Src.Pattern] -> Ann.Region
regionFromPats [] =
  Ann.Region (Ann.Position 1 1) (Ann.Position 1 1)
regionFromPats (p : ps) =
  Ann.mergeRegions (Ann.toRegion p) (Ann.toRegion (lastPat ps))
  where
    lastPat [] = p
    lastPat [x] = x
    lastPat (_ : xs) = lastPat xs

-- LONG FUNCTION

-- | Rule: warn on function bodies that span too many lines.
--
-- Long functions are harder to understand, test, and maintain.
-- Extract helper functions to keep each definition focused.
--
-- @since 0.19.2
checkLongFunction :: Src.Module -> [LintWarning]
checkLongFunction modul =
  mapMaybe (checkFuncLength . Ann.toValue) (Src._values modul)

-- | Maximum number of lines a function body may span.
maxFunctionLines :: Int
maxFunctionLines = 15

-- | Check whether a function body exceeds the line limit.
checkFuncLength :: Src.Value -> Maybe LintWarning
checkFuncLength (Src.Value (Ann.At nameRegion name_) _ body _ _) =
  longFuncWarning nameRegion (Name.toChars name_) bodyRegion
  where
    bodyRegion = Ann.toRegion body

-- | Emit a warning if the body spans too many lines.
longFuncWarning :: Ann.Region -> String -> Ann.Region -> Maybe LintWarning
longFuncWarning nameRegion funcName (Ann.Region (Ann.Position startLine _) (Ann.Position endLine _))
  | lineSpan > fromIntegral maxFunctionLines =
      Just
        LintWarning
          { _warnRegion = nameRegion,
            _warnRule = LongFunction,
            _warnSeverity = SevWarning,
            _warnMessage =
              "`" ++ funcName ++ "` spans " ++ show lineSpan
                ++ " lines (limit: "
                ++ show maxFunctionLines
                ++ "). Extract helpers to reduce size.",
            _warnFix = Nothing
          }
  | otherwise = Nothing
  where
    lineSpan = endLine - startLine + 1

-- MAGIC NUMBER

-- | Rule: detect literal numbers (other than 0, 1, 2) in expressions.
--
-- Magic numbers make code hard to understand.  Bind them to named
-- constants with descriptive names.
--
-- @since 0.19.2
checkMagicNumber :: Src.Module -> [LintWarning]
checkMagicNumber modul =
  concatMap (checkMagicInValue . Ann.toValue) (Src._values modul)

-- | Check a value for magic number literals.
checkMagicInValue :: Src.Value -> [LintWarning]
checkMagicInValue (Src.Value _ _ expr _ _) =
  checkMagicInExpr expr

-- | Small integers that are not considered magic.
allowedInts :: Set.Set Int
allowedInts = Set.fromList [0, 1, 2, -1]

-- | Walk expression tree for magic number literals.
checkMagicInExpr :: Src.Expr -> [LintWarning]
checkMagicInExpr (Ann.At region (Src.Int n))
  | not (Set.member n allowedInts) = [magicNumWarn region n]
checkMagicInExpr (Ann.At _ expr_) =
  concatMap checkMagicInExpr (childExprs expr_)

-- | Build a magic number warning.
magicNumWarn :: Ann.Region -> Int -> LintWarning
magicNumWarn region n =
  LintWarning
    { _warnRegion = region,
      _warnRule = MagicNumber,
      _warnSeverity = SevInfo,
      _warnMessage =
        "Magic number " ++ show n
          ++ " should be a named constant.",
      _warnFix = Nothing
    }

-- STRING CONCAT IN LOOP

-- | Rule: detect repeated string concatenation inside folds or recursion.
--
-- Repeated @String.append@ inside loops creates intermediate allocations.
-- Use @String.join@ or a builder pattern.
--
-- @since 0.19.2
checkStringConcatInLoop :: Src.Module -> [LintWarning]
checkStringConcatInLoop modul =
  concatMap (checkStrConcatInValue . Ann.toValue) (Src._values modul)

-- | Check a value for string concat in loop patterns.
checkStrConcatInValue :: Src.Value -> [LintWarning]
checkStrConcatInValue (Src.Value _ _ expr _ _) =
  checkStrConcatInExpr expr

-- | Walk lambda bodies for String.append or String.concat calls.
checkStrConcatInExpr :: Src.Expr -> [LintWarning]
checkStrConcatInExpr (Ann.At _ (Src.Lambda _ body)) =
  checkStrConcatBody body
checkStrConcatInExpr (Ann.At _ expr_) =
  concatMap checkStrConcatInExpr (childExprs expr_)

-- | Check a lambda body for String.append calls.
checkStrConcatBody :: Src.Expr -> [LintWarning]
checkStrConcatBody (Ann.At region (Src.VarQual _ modName funcName))
  | Name.toChars modName == "String"
      && Name.toChars funcName == "append" =
      [strConcatWarn region]
checkStrConcatBody (Ann.At _ expr_) =
  concatMap checkStrConcatBody (childExprs expr_)

-- | Build a string concat warning.
strConcatWarn :: Ann.Region -> LintWarning
strConcatWarn region =
  LintWarning
    { _warnRegion = region,
      _warnRule = StringConcatInLoop,
      _warnSeverity = SevWarning,
      _warnMessage =
        "`String.append` inside a lambda may create excess allocations. "
          ++ "Consider `String.join` or accumulate in a list.",
      _warnFix = Nothing
    }

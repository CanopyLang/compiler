{-# LANGUAGE OverloadedStrings #-}

-- | Lint rules for list operations.
--
-- Includes rules for detecting list literal concatenation that should be
-- merged, single-element prepend that should use cons, and list append
-- inside lambdas that may cause O(n^2) behavior.
--
-- @since 0.19.1
module Lint.Rules.Lists
  ( checkDropConcatOfLists,
    checkUseConsOverConcat,
    checkListAppendInLoop,
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

-- DROP CONCAT OF LISTS

-- | Rule: @[a] ++ [b]@ should be written @[a, b]@.
--
-- Concatenating two list literals produces an unnecessary intermediate
-- allocation.  The fix is to merge both literals into one.
--
-- @since 0.19.1
checkDropConcatOfLists :: Src.Module -> [LintWarning]
checkDropConcatOfLists modul =
  concatMap (checkConcatInValue . Ann.toValue) (Src._values modul)

-- | Search a value definition for @[x] ++ [y]@ patterns.
checkConcatInValue :: Src.Value -> [LintWarning]
checkConcatInValue (Src.Value _ _ expr _ _) =
  checkConcatInExpr expr

-- | Walk an expression looking for @[a] ++ [b]@ binop chains.
checkConcatInExpr :: Src.Expr -> [LintWarning]
checkConcatInExpr (Ann.At region expr_) =
  concatWarnings ++ subWarnings
  where
    concatWarnings = maybe [] pure (dropConcatWarning region expr_)
    subWarnings = concatMap checkConcatInExpr (childExprs expr_)

-- | Detect @[a] ++ [b]@ and produce a warning.
dropConcatWarning :: Ann.Region -> Src.Expr_ -> Maybe LintWarning
dropConcatWarning region (Src.Binops pairs _)
  | any isListConcatPair pairs =
      Just
        LintWarning
          { _warnRegion = region,
            _warnRule = DropConcatOfLists,
            _warnSeverity = SevWarning,
            _warnMessage =
              "Concatenation of two list literals can be merged into one.",
            _warnFix = Nothing
          }
dropConcatWarning _ _ = Nothing

-- | Check whether a binop pair is @list ++ list@.
isListConcatPair :: (Src.Expr, Ann.Located Name.Name) -> Bool
isListConcatPair (lhs, Ann.At _ op) =
  Name.toChars op == "++" && isList (Ann.toValue lhs)

-- | Check whether an expression is a list literal.
isList :: Src.Expr_ -> Bool
isList (Src.List _) = True
isList _ = False

-- USE CONS OVER CONCAT

-- | Rule: @[a] ++ list@ should be written @a :: list@.
--
-- Prepending a single-element list literal via @++@ creates an unnecessary
-- allocation.  Using @::@ (cons) is more idiomatic and more efficient.
--
-- @since 0.19.1
checkUseConsOverConcat :: Src.Module -> [LintWarning]
checkUseConsOverConcat modul =
  concatMap (checkConsInValue . Ann.toValue) (Src._values modul)

-- | Search a value definition for @[a] ++ list@ patterns.
checkConsInValue :: Src.Value -> [LintWarning]
checkConsInValue (Src.Value _ _ expr _ _) =
  checkConsInExpr expr

-- | Walk an expression looking for @[a] ++ list@ binop chains.
checkConsInExpr :: Src.Expr -> [LintWarning]
checkConsInExpr (Ann.At region expr_) =
  consWarnings ++ subWarnings
  where
    consWarnings = maybe [] pure (useConsWarning region expr_)
    subWarnings = concatMap checkConsInExpr (childExprs expr_)

-- | Detect @[a] ++ list@ where the right-hand side is not a literal.
useConsWarning :: Ann.Region -> Src.Expr_ -> Maybe LintWarning
useConsWarning region (Src.Binops pairs rhs)
  | any isSingletonConcatPair pairs
      && not (isList (Ann.toValue rhs)) =
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
isSingletonConcatPair :: (Src.Expr, Ann.Located Name.Name) -> Bool
isSingletonConcatPair (lhs, Ann.At _ op) =
  Name.toChars op == "++" && isSingleton (Ann.toValue lhs)

-- | Check whether an expression is a list literal with exactly one element.
isSingleton :: Src.Expr_ -> Bool
isSingleton (Src.List [_]) = True
isSingleton _ = False

-- LIST APPEND IN LOOP

-- | Rule: detect @++ [x]@ patterns inside fold-like expressions.
--
-- Appending to the end of a list with @++@ is O(n) per call and O(n^2)
-- overall when done inside a fold.  Use @x :: acc@ and reverse at the
-- end, or accumulate in a different data structure.
--
-- @since 0.19.2
checkListAppendInLoop :: Src.Module -> [LintWarning]
checkListAppendInLoop modul =
  concatMap (checkAppendInValue . Ann.toValue) (Src._values modul)

-- | Check a value for list append in fold patterns.
checkAppendInValue :: Src.Value -> [LintWarning]
checkAppendInValue (Src.Value _ _ expr _ _) =
  checkAppendInExpr expr

-- | Walk expression tree for @++@ inside lambda (fold callback).
checkAppendInExpr :: Src.Expr -> [LintWarning]
checkAppendInExpr (Ann.At _ (Src.Lambda _ body)) =
  checkAppendInBody body
checkAppendInExpr (Ann.At _ expr_) =
  concatMap checkAppendInExpr (childExprs expr_)

-- | Check a lambda body for list append operations.
checkAppendInBody :: Src.Expr -> [LintWarning]
checkAppendInBody (Ann.At region (Src.Binops pairs _))
  | any isAppendOp pairs = [appendWarn region]
  where
    isAppendOp (_, Ann.At _ op) = Name.toChars op == "++"
checkAppendInBody (Ann.At _ expr_) =
  concatMap checkAppendInBody (childExprs expr_)

-- | Build a list append warning.
appendWarn :: Ann.Region -> LintWarning
appendWarn region =
  LintWarning
    { _warnRegion = region,
      _warnRule = ListAppendInLoop,
      _warnSeverity = SevWarning,
      _warnMessage =
        "List append (++) inside a lambda may indicate O(n^2) behavior. "
          ++ "Consider using cons (::) and reversing.",
      _warnFix = Nothing
    }

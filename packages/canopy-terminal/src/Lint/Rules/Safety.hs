{-# LANGUAGE OverloadedStrings #-}

-- | Lint rules for code safety.
--
-- Includes rules for detecting partial function usage, Debug.todo as a value,
-- and unnecessary lazy patterns.
--
-- @since 0.19.2
module Lint.Rules.Safety
  ( checkPartialFunction,
    checkUnsafeCoerce,
    checkUnnecessaryLazyPattern,
  )
where

import qualified AST.Source as Src
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import Lint.Rules.Helpers (childExprs)
import Lint.Types
  ( LintRule (..),
    LintWarning (..),
    Severity (..),
  )
import qualified Reporting.Annotation as Ann

-- PARTIAL FUNCTION

-- | Rule: detect usage of partial functions like @List.head@ and @List.tail@.
--
-- These functions fail on empty lists. Safe alternatives include
-- pattern matching or explicit empty-list handling.
--
-- @since 0.19.2
checkPartialFunction :: Src.Module -> [LintWarning]
checkPartialFunction modul =
  concatMap (checkPartialInValue . Ann.toValue) (Src._values modul)

-- | Check a value for partial function calls.
checkPartialInValue :: Src.Value -> [LintWarning]
checkPartialInValue (Src.Value _ _ expr _ _) =
  checkPartialInExpr expr

-- | Walk an expression tree searching for partial function references.
checkPartialInExpr :: Src.Expr -> [LintWarning]
checkPartialInExpr (Ann.At region expr_) =
  localWarnings ++ subWarnings
  where
    localWarnings = checkPartialRef region expr_
    subWarnings = concatMap checkPartialInExpr (childExprs expr_)

-- | Known partial function names to flag.
partialFunctions :: Set.Set String
partialFunctions =
  Set.fromList ["head", "tail", "fromJust", "minimum", "maximum"]

-- | Check whether an expression references a partial function.
checkPartialRef :: Ann.Region -> Src.Expr_ -> [LintWarning]
checkPartialRef region (Src.VarQual _ _ name_)
  | Set.member (Name.toChars name_) partialFunctions =
      [partialWarn region (Name.toChars name_)]
checkPartialRef _ _ = []

-- | Build a partial function warning.
partialWarn :: Ann.Region -> String -> LintWarning
partialWarn region funcName =
  LintWarning
    { _warnRegion = region,
      _warnRule = PartialFunction,
      _warnSeverity = SevWarning,
      _warnMessage =
        "`" ++ funcName ++ "` is partial and will crash on empty input. "
          ++ "Use pattern matching or a safe alternative.",
      _warnFix = Nothing
    }

-- UNSAFE COERCE

-- | Rule: detect @Debug.todo@ used as a value (unsafe coercion).
--
-- @Debug.todo@ with a string argument is sometimes used to stub out
-- type-incompatible code paths.  This rule flags any reference to
-- @Debug.todo@ in non-top-level position.
--
-- @since 0.19.2
checkUnsafeCoerce :: Src.Module -> [LintWarning]
checkUnsafeCoerce modul =
  concatMap (checkUnsafeInValue . Ann.toValue) (Src._values modul)

-- | Check a value for Debug.todo references.
checkUnsafeInValue :: Src.Value -> [LintWarning]
checkUnsafeInValue (Src.Value _ _ expr _ _) =
  checkUnsafeInExpr expr

-- | Walk expression tree for Debug.todo usage.
checkUnsafeInExpr :: Src.Expr -> [LintWarning]
checkUnsafeInExpr (Ann.At region expr_) =
  localWarnings ++ subWarnings
  where
    localWarnings = checkDebugTodo region expr_
    subWarnings = concatMap checkUnsafeInExpr (childExprs expr_)

-- | Check if an expression is Debug.todo.
checkDebugTodo :: Ann.Region -> Src.Expr_ -> [LintWarning]
checkDebugTodo region (Src.VarQual _ modName funcName)
  | Name.toChars modName == "Debug" && Name.toChars funcName == "todo" =
      [unsafeCoerceWarn region]
checkDebugTodo _ _ = []

-- | Build an unsafe coerce warning.
unsafeCoerceWarn :: Ann.Region -> LintWarning
unsafeCoerceWarn region =
  LintWarning
    { _warnRegion = region,
      _warnRule = UnsafeCoerce,
      _warnSeverity = SevError,
      _warnMessage =
        "`Debug.todo` used as a value. Replace with proper error handling.",
      _warnFix = Nothing
    }

-- UNNECESSARY LAZY PATTERN

-- | Rule: detect tilde (@~@) lazy patterns in strict contexts.
--
-- Canopy (like Elm) is strict by default, so lazy patterns are not
-- part of the language syntax.  This rule is a no-op placeholder
-- that exists for completeness.
--
-- @since 0.19.2
checkUnnecessaryLazyPattern :: Src.Module -> [LintWarning]
checkUnnecessaryLazyPattern _modul =
  []

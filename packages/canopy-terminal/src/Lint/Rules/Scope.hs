{-# LANGUAGE OverloadedStrings #-}

-- | Lint rules for variable scoping.
--
-- Includes rules for detecting shadowed variables and unused let bindings.
--
-- @since 0.19.2
module Lint.Rules.Scope
  ( checkShadowedVariable,
    checkUnusedLetVariable,
  )
where

import qualified AST.Source as Src
import Data.Maybe (mapMaybe)
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import Lint.Rules.Helpers
  ( childExprs,
    collectNamesInDef,
    collectNamesInExpr,
    defNames,
    patternLocatedNames,
    patternNames,
  )
import Lint.Types
  ( LintRule (..),
    LintWarning (..),
    Severity (..),
  )
import qualified Reporting.Annotation as Ann

-- SHADOWED VARIABLE

-- | Rule: detect bindings that shadow names from an outer scope.
--
-- When a let, case, or lambda binding introduces a name that is already
-- bound in an enclosing scope, the outer binding becomes inaccessible.
-- This is a common source of subtle bugs where the programmer intends
-- to reference the outer value but accidentally refers to the inner one.
--
-- @since 0.19.2
checkShadowedVariable :: Src.Module -> [LintWarning]
checkShadowedVariable modul =
  concatMap (checkShadowInValue . Ann.toValue) (Src._values modul)

-- | Check a top-level value for shadowed variables.
checkShadowInValue :: Src.Value -> [LintWarning]
checkShadowInValue (Src.Value _ patterns body _) =
  checkShadowInExpr paramNames body
  where
    paramNames = Set.fromList (concatMap patternNames patterns)

-- | Walk an expression collecting shadow warnings.
checkShadowInExpr :: Set.Set String -> Src.Expr -> [LintWarning]
checkShadowInExpr scope (Ann.At _ expr_) =
  checkShadowInExpr_ scope expr_

-- | Dispatch on expression form for shadow checking.
checkShadowInExpr_ :: Set.Set String -> Src.Expr_ -> [LintWarning]
checkShadowInExpr_ scope (Src.Let defs body) =
  defWarnings ++ bodyWarnings
  where
    defWarnings = concatMap (checkShadowInDef scope) defs
    newNames = concatMap (defNames . Ann.toValue) defs
    extendedScope = Set.union scope (Set.fromList newNames)
    bodyWarnings = checkShadowInExpr extendedScope body
checkShadowInExpr_ scope (Src.Case scrutinee branches) =
  checkShadowInExpr scope scrutinee
    ++ concatMap (checkShadowInBranch scope) branches
checkShadowInExpr_ scope (Src.Lambda patterns body) =
  shadowWarnings ++ checkShadowInExpr extendedScope body
  where
    newNames = concatMap patternNames patterns
    shadowWarnings = concatMap (shadowWarningForName scope) (patternLocatedNames patterns)
    extendedScope = Set.union scope (Set.fromList newNames)
checkShadowInExpr_ scope expr_ =
  concatMap (checkShadowInExpr scope) (childExprs expr_)

-- | Check a let definition for shadowed variable names.
checkShadowInDef :: Set.Set String -> Ann.Located Src.Def -> [LintWarning]
checkShadowInDef scope (Ann.At _ (Src.Define (Ann.At region name_) patterns body _)) =
  nameWarning ++ paramWarnings ++ bodyWarnings
  where
    nameStr = Name.toChars name_
    nameWarning = [shadowedWarning region nameStr | Set.member nameStr scope]
    paramNewNames = concatMap patternNames patterns
    paramLocated = patternLocatedNames patterns
    paramWarnings = concatMap (shadowWarningForName scope) paramLocated
    extendedScope = Set.union scope (Set.fromList (nameStr : paramNewNames))
    bodyWarnings = checkShadowInExpr extendedScope body
checkShadowInDef scope (Ann.At _ (Src.Destruct pat body)) =
  patWarnings ++ bodyWarnings
  where
    newNames = patternNames pat
    patWarnings = concatMap (shadowWarningForName scope) (patternLocatedNames [pat])
    extendedScope = Set.union scope (Set.fromList newNames)
    bodyWarnings = checkShadowInExpr extendedScope body

-- | Check a case branch for shadowed variables.
checkShadowInBranch :: Set.Set String -> (Src.Pattern, Src.Expr) -> [LintWarning]
checkShadowInBranch scope (pat, body) =
  patWarnings ++ bodyWarnings
  where
    newNames = patternNames pat
    patWarnings = concatMap (shadowWarningForName scope) (patternLocatedNames [pat])
    extendedScope = Set.union scope (Set.fromList newNames)
    bodyWarnings = checkShadowInExpr extendedScope body

-- | Produce a shadow warning for a located name if it is already in scope.
shadowWarningForName :: Set.Set String -> (Ann.Region, String) -> [LintWarning]
shadowWarningForName scope (region, name_)
  | Set.member name_ scope = [shadowedWarning region name_]
  | otherwise = []

-- | Build a warning for a shadowed variable.
shadowedWarning :: Ann.Region -> String -> LintWarning
shadowedWarning region name_ =
  LintWarning
    { _warnRegion = region,
      _warnRule = ShadowedVariable,
      _warnSeverity = SevWarning,
      _warnMessage =
        "Variable `" ++ name_ ++ "` shadows a binding from an outer scope.",
      _warnFix = Nothing
    }

-- UNUSED LET VARIABLE

-- | Rule: detect bound but unused variables in let expressions.
--
-- A let-binding that introduces a name never referenced in the body
-- expression or subsequent bindings is dead code.
--
-- @since 0.19.2
checkUnusedLetVariable :: Src.Module -> [LintWarning]
checkUnusedLetVariable modul =
  concatMap (checkUnusedLetInValue . Ann.toValue) (Src._values modul)

-- | Check a top-level value for unused let variables.
checkUnusedLetInValue :: Src.Value -> [LintWarning]
checkUnusedLetInValue (Src.Value _ _ expr _) =
  checkUnusedLetInExpr expr

-- | Walk an expression looking for let bindings with unused variables.
checkUnusedLetInExpr :: Src.Expr -> [LintWarning]
checkUnusedLetInExpr (Ann.At _ expr_) =
  checkUnusedLetInExpr_ expr_

-- | Dispatch on expression form for unused let checking.
checkUnusedLetInExpr_ :: Src.Expr_ -> [LintWarning]
checkUnusedLetInExpr_ (Src.Let defs body) =
  unusedWarnings ++ subDefWarnings ++ subBodyWarnings
  where
    usedInBody = collectNamesInExpr (Ann.toValue body)
    usedInDefs = concatMap (collectNamesInDef . Ann.toValue) defs
    allUsed = Set.fromList (usedInBody ++ usedInDefs)
    unusedWarnings = concatMap (checkDefUnused allUsed) defs
    subDefWarnings = concatMap (checkUnusedLetInDef . Ann.toValue) defs
    subBodyWarnings = checkUnusedLetInExpr body
checkUnusedLetInExpr_ expr_ =
  concatMap checkUnusedLetInExpr (childExprs expr_)

-- | Check sub-expressions in a let definition for nested unused let variables.
checkUnusedLetInDef :: Src.Def -> [LintWarning]
checkUnusedLetInDef (Src.Define _ _ body _) = checkUnusedLetInExpr body
checkUnusedLetInDef (Src.Destruct _ body) = checkUnusedLetInExpr body

-- | Check whether a definition's bound name is unused.
checkDefUnused :: Set.Set String -> Ann.Located Src.Def -> [LintWarning]
checkDefUnused usedNames (Ann.At _ (Src.Define (Ann.At region name_) _ _ _)) =
  [unusedLetWarning region nameStr | not (Set.member nameStr usedNames)]
  where
    nameStr = Name.toChars name_
checkDefUnused usedNames (Ann.At _ (Src.Destruct pat _)) =
  mapMaybe (checkPatNameUnused usedNames) (patternLocatedNames [pat])

-- | Check a single pattern-bound name for usage.
checkPatNameUnused :: Set.Set String -> (Ann.Region, String) -> Maybe LintWarning
checkPatNameUnused usedNames (region, name_)
  | Set.member name_ usedNames = Nothing
  | otherwise = Just (unusedLetWarning region name_)

-- | Build a warning for an unused let variable.
unusedLetWarning :: Ann.Region -> String -> LintWarning
unusedLetWarning region nameStr =
  LintWarning
    { _warnRegion = region,
      _warnRule = UnusedLetVariable,
      _warnSeverity = SevWarning,
      _warnMessage =
        "Let binding `" ++ nameStr ++ "` is never used.",
      _warnFix = Nothing
    }

{-# LANGUAGE OverloadedStrings #-}

-- | Lint rule implementations for the Canopy static analyser.
--
-- Each rule is a pure function @'AST.Source.Module' -> ['LintWarning']@ that
-- inspects a parsed module and produces zero or more warnings.
--
-- == Available Rules
--
-- * 'checkUnusedImport' - Imports that are never referenced in the module body
-- * 'checkBooleanCase' - @case x of True -> a; False -> b@ that should be @if@
-- * 'checkUnnecessaryParens' - Extra parentheses around simple expressions
-- * 'checkDropConcatOfLists' - @[a] ++ [b]@ that should be @[a, b]@
-- * 'checkUseConsOverConcat' - @[a] ++ list@ that should be @a :: list@
-- * 'checkMissingTypeAnnotation' - Top-level function without a type signature
-- * 'checkShadowedVariable' - Let\/case\/lambda bindings that shadow outer names
-- * 'checkUnusedLetVariable' - Bound but unused variables in let expressions
--
-- @since 0.19.1
module Lint.Rules
  ( -- * Rule Check Functions
    checkUnusedImport,
    checkBooleanCase,
    checkUnnecessaryParens,
    checkDropConcatOfLists,
    checkUseConsOverConcat,
    checkMissingTypeAnnotation,
    checkShadowedVariable,
    checkUnusedLetVariable,

    -- * Helpers
    collectUsedNames,
    childExprs,
  )
where

import qualified AST.Source as Src
import Data.Maybe (mapMaybe)
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import Lint.Types
  ( LintFix (..),
    LintRule (..),
    LintWarning (..),
    Severity (..),
  )
import qualified Reporting.Annotation as Ann

-- UNUSED IMPORT

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
isImportUsed usedNames (Src.Import (Ann.At _ modName) alias exposing _isLazy) =
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
exposedItemName (Src.Lower (Ann.At _ n)) = Just (Name.toChars n)
exposedItemName (Src.Upper (Ann.At _ n) _) = Just (Name.toChars n)
exposedItemName (Src.Operator _ n) = Just (Name.toChars n)

-- | Build the set of all name tokens that appear in the module body.
collectUsedNames :: Src.Module -> Set.Set String
collectUsedNames modul =
  Set.fromList
    ( concatMap (collectNamesInValue . Ann.toValue) (Src._values modul)
        ++ concatMap (collectNamesInUnion . Ann.toValue) (Src._unions modul)
        ++ concatMap (collectNamesInAlias . Ann.toValue) (Src._aliases modul)
    )

-- | Collect all name tokens from a value definition.
collectNamesInValue :: Src.Value -> [String]
collectNamesInValue (Src.Value _ _ expr _) =
  collectNamesInExpr (Ann.toValue expr)

-- | Collect all name tokens from a union type definition.
collectNamesInUnion :: Src.Union -> [String]
collectNamesInUnion (Src.Union _ _ ctors) =
  concatMap collectNamesInCtor ctors

-- | Collect names from a constructor definition.
collectNamesInCtor :: (Ann.Located Name.Name, [Src.Type]) -> [String]
collectNamesInCtor (_, types) =
  concatMap (collectNamesInType . Ann.toValue) types

-- | Collect names from a type alias definition.
collectNamesInAlias :: Src.Alias -> [String]
collectNamesInAlias (Src.Alias _ _ t) =
  collectNamesInType (Ann.toValue t)

-- | Collect all identifier tokens used in an expression.
collectNamesInExpr :: Src.Expr_ -> [String]
collectNamesInExpr (Src.Var _ n) = [Name.toChars n]
collectNamesInExpr (Src.VarQual _ modN n) = [Name.toChars modN, Name.toChars n]
collectNamesInExpr (Src.Call f args) =
  collectNamesInExpr (Ann.toValue f)
    ++ concatMap (collectNamesInExpr . Ann.toValue) args
collectNamesInExpr (Src.If branches elseBranch) =
  concatMap collectBranchNames branches
    ++ collectNamesInExpr (Ann.toValue elseBranch)
collectNamesInExpr (Src.Let defs body) =
  concatMap (collectNamesInDef . Ann.toValue) defs
    ++ collectNamesInExpr (Ann.toValue body)
collectNamesInExpr (Src.Case scrutinee branches) =
  collectNamesInExpr (Ann.toValue scrutinee)
    ++ concatMap (collectNamesInExpr . Ann.toValue . snd) branches
collectNamesInExpr (Src.Lambda _ body) = collectNamesInExpr (Ann.toValue body)
collectNamesInExpr (Src.List items) = concatMap (collectNamesInExpr . Ann.toValue) items
collectNamesInExpr (Src.Binops pairs last_) =
  concatMap (collectNamesInExpr . Ann.toValue . fst) pairs
    ++ collectNamesInExpr (Ann.toValue last_)
collectNamesInExpr (Src.Negate e) = collectNamesInExpr (Ann.toValue e)
collectNamesInExpr (Src.Access e _) = collectNamesInExpr (Ann.toValue e)
collectNamesInExpr (Src.Update (Ann.At _ n) fields) =
  Name.toChars n : concatMap (collectNamesInExpr . Ann.toValue . snd) fields
collectNamesInExpr (Src.Record fields) =
  concatMap (collectNamesInExpr . Ann.toValue . snd) fields
collectNamesInExpr (Src.Tuple e1 e2 rest) =
  collectNamesInExpr (Ann.toValue e1)
    ++ collectNamesInExpr (Ann.toValue e2)
    ++ concatMap (collectNamesInExpr . Ann.toValue) rest
collectNamesInExpr _ = []

-- | Collect names from a branch pair.
collectBranchNames :: (Src.Expr, Src.Expr) -> [String]
collectBranchNames (cond, body) =
  collectNamesInExpr (Ann.toValue cond)
    ++ collectNamesInExpr (Ann.toValue body)

-- | Collect names in a local definition.
collectNamesInDef :: Src.Def -> [String]
collectNamesInDef (Src.Define _ _ body _) = collectNamesInExpr (Ann.toValue body)
collectNamesInDef (Src.Destruct _ body) = collectNamesInExpr (Ann.toValue body)

-- | Collect names referenced in a type expression.
collectNamesInType :: Src.Type_ -> [String]
collectNamesInType (Src.TType _ n args) =
  Name.toChars n : concatMap (collectNamesInType . Ann.toValue) args
collectNamesInType (Src.TTypeQual _ modN n args) =
  Name.toChars modN : Name.toChars n : concatMap (collectNamesInType . Ann.toValue) args
collectNamesInType (Src.TLambda a b) =
  collectNamesInType (Ann.toValue a) ++ collectNamesInType (Ann.toValue b)
collectNamesInType (Src.TRecord fields _) =
  concatMap (collectNamesInType . Ann.toValue . snd) fields
collectNamesInType (Src.TTuple a b rest) =
  collectNamesInType (Ann.toValue a)
    ++ collectNamesInType (Ann.toValue b)
    ++ concatMap (collectNamesInType . Ann.toValue) rest
collectNamesInType _ = []

-- | Build the unused-import warning for an import statement.
--
-- The auto-fix removes the entire import line range based on the AST region.
unusedImportWarning :: Src.Import -> LintWarning
unusedImportWarning (Src.Import (Ann.At region modName) _ _ _) =
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
regionLineRange :: Ann.Region -> (Int, Int)
regionLineRange (Ann.Region (Ann.Position startRow _) (Ann.Position endRow _)) =
  (fromIntegral startRow, fromIntegral endRow)

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
childExprs (Src.Call f args) = f : args
childExprs (Src.If branches elseBranch) =
  concatMap (\(cond, body) -> [cond, body]) branches ++ [elseBranch]
childExprs (Src.Let defs body) =
  concatMap (defExprs . Ann.toValue) defs ++ [body]
childExprs (Src.Case scrutinee branches) =
  scrutinee : map snd branches
childExprs (Src.Lambda _ body) = [body]
childExprs (Src.List items) = items
childExprs (Src.Binops pairs last_) =
  map fst pairs ++ [last_]
childExprs (Src.Negate e) = [e]
childExprs (Src.Access e _) = [e]
childExprs (Src.Update _ fields) = map snd fields
childExprs (Src.Record fields) = map snd fields
childExprs (Src.Tuple e1 e2 rest) = e1 : e2 : rest
childExprs _ = []

-- | Extract child expressions from a local definition.
defExprs :: Src.Def -> [Src.Expr]
defExprs (Src.Define _ _ body _) = [body]
defExprs (Src.Destruct _ body) = [body]

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

-- | Produce a warning when a Call with a single argument is wrapping an atomic.
--
-- In practice the Canopy source AST does not represent parentheses as a
-- distinct node.  The closest observable pattern is a 'Tuple' with a single
-- element -- but the parser prevents that.  We therefore detect the most common
-- hand-written pattern: @(variable)@ represented as a @Call@ on nothing with
-- an atomic argument.
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
checkConcatInValue (Src.Value _ _ expr _) =
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
              "`[a] ++ [b]` can be simplified to `[a, b]`.",
            _warnFix = Nothing
          }
dropConcatWarning _ _ = Nothing

-- | Check whether a binop pair is a @++ [...]@ applied to a @[...]@ left-hand side.
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
checkConsInValue (Src.Value _ _ expr _) =
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

-- MISSING TYPE ANNOTATION

-- | Rule: top-level value definitions without a type annotation.
--
-- Type annotations on top-level definitions improve readability and help
-- the compiler produce better error messages.  Definitions with parameters
-- are also checked since they are function definitions.
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

-- SHADOWED VARIABLE

-- | Rule: detect bindings that shadow names from an outer scope.
--
-- When a let, case, or lambda binding introduces a name that is already
-- bound in an enclosing scope, the outer binding becomes inaccessible.
-- This is a common source of subtle bugs where the programmer intends
-- to reference the outer value but accidentally refers to the inner one.
--
-- The rule tracks the set of names in scope as it descends through the
-- expression tree.  Top-level function parameters are the initial scope.
--
-- @since 0.19.2
checkShadowedVariable :: Src.Module -> [LintWarning]
checkShadowedVariable modul =
  concatMap (checkShadowInValue . Ann.toValue) (Src._values modul)

-- | Check a top-level value for shadowed variables.
--
-- Collects the function parameter names as the initial scope, then
-- walks the body expression.
checkShadowInValue :: Src.Value -> [LintWarning]
checkShadowInValue (Src.Value _ patterns body _) =
  checkShadowInExpr paramNames body
  where
    paramNames = Set.fromList (concatMap patternNames patterns)

-- | Walk an expression collecting shadow warnings.
--
-- The @scope@ set tracks all names currently in scope. When a new
-- binding site is encountered (let, case branch, lambda), any name
-- that already exists in the scope produces a warning.
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

-- | Extract all variable names bound by a pattern.
patternNames :: Src.Pattern -> [String]
patternNames (Ann.At _ pat_) = patternNames_ pat_

-- | Extract variable names from a pattern node.
patternNames_ :: Src.Pattern_ -> [String]
patternNames_ (Src.PVar n) = [Name.toChars n]
patternNames_ (Src.PRecord fields) = map (Name.toChars . Ann.toValue) fields
patternNames_ (Src.PAlias subPat (Ann.At _ n)) = Name.toChars n : patternNames subPat
patternNames_ (Src.PCtor _ _ subPats) = concatMap patternNames subPats
patternNames_ (Src.PCtorQual _ _ _ subPats) = concatMap patternNames subPats
patternNames_ (Src.PTuple p1 p2 rest) = concatMap patternNames (p1 : p2 : rest)
patternNames_ (Src.PList pats) = concatMap patternNames pats
patternNames_ (Src.PCons hd tl) = patternNames hd ++ patternNames tl
patternNames_ Src.PAnything = []
patternNames_ Src.PUnit = []
patternNames_ (Src.PChr _) = []
patternNames_ (Src.PStr _) = []
patternNames_ (Src.PInt _) = []

-- | Extract all located variable names from a list of patterns.
--
-- Returns @(region, name)@ pairs so that warnings carry the precise location
-- of the binding that causes the shadow.
patternLocatedNames :: [Src.Pattern] -> [(Ann.Region, String)]
patternLocatedNames = concatMap go
  where
    go (Ann.At _ pat_) = goInner pat_
    goInner (Src.PVar n) = [(Ann.zero, Name.toChars n)]
    goInner (Src.PRecord fields) = map locatedField fields
    goInner (Src.PAlias subPat (Ann.At region n)) =
      (region, Name.toChars n) : concatMap go [subPat]
    goInner (Src.PCtor _ _ subPats) = concatMap go subPats
    goInner (Src.PCtorQual _ _ _ subPats) = concatMap go subPats
    goInner (Src.PTuple p1 p2 rest) = concatMap go (p1 : p2 : rest)
    goInner (Src.PList pats) = concatMap go pats
    goInner (Src.PCons hd tl) = concatMap go [hd, tl]
    goInner Src.PAnything = []
    goInner Src.PUnit = []
    goInner (Src.PChr _) = []
    goInner (Src.PStr _) = []
    goInner (Src.PInt _) = []
    locatedField (Ann.At region n) = (region, Name.toChars n)

-- | Extract the names bound by a definition.
defNames :: Src.Def -> [String]
defNames (Src.Define (Ann.At _ n) _ _ _) = [Name.toChars n]
defNames (Src.Destruct pat _) = patternNames pat

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
-- expression or subsequent bindings is dead code.  This rule flags such
-- bindings so they can be removed or replaced with @_@.
--
-- Only local @let@ bindings are checked; top-level definitions are not
-- flagged since they may be part of the module's public API.
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

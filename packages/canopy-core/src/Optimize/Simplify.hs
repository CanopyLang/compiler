{-# LANGUAGE OverloadedStrings #-}

-- | Post-optimization simplification passes for the Canopy compiler.
--
-- This module provides expression-level simplification passes that run
-- after the main optimization phase. These passes operate on the
-- 'Opt.Expr' AST and apply algebraic simplifications that the main
-- optimizer does not handle.
--
-- == Simplification Passes
--
-- * **Boolean simplification** - Evaluates @if True@ / @if False@ statically,
--   simplifies @True && x@ to @x@, @False || x@ to @x@, etc.
-- * **Identity elimination** - Removes @identity x@ calls, eliminates
--   @not (not x)@ double negation.
-- * **String folding** - Concatenates adjacent string literals at compile time.
-- * **Dead binding elimination** - Removes unused pure let-bindings.
--
-- == Integration
--
-- The 'simplify' function is called from "Optimize.Module" after the main
-- optimization pass produces an 'Opt.Expr'. Simplification is applied
-- bottom-up so that inner subexpressions are simplified before outer ones.
--
-- @since 0.19.2
module Optimize.Simplify
  ( simplify,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map

-- | Simplify an optimized expression by applying algebraic rewrites.
--
-- Walks the expression tree bottom-up, applying simplification rules at
-- each node. The pass is applied once (not iterated to fixpoint) since
-- the rules are designed to compose cleanly in a single traversal.
--
-- ==== Simplification Rules
--
-- * @if True then a else b@ becomes @a@
-- * @if False then a else b@ becomes @b@
-- * @if c then True else False@ becomes @c@
-- * @if c then False else True@ becomes @not c@
-- * @identity x@ becomes @x@
-- * @not (not x)@ becomes @x@
-- * @True && x@ becomes @x@, @x && True@ becomes @x@
-- * @False && x@ becomes @False@
-- * @True || x@ becomes @True@
-- * @False || x@ becomes @x@, @x || False@ becomes @x@
-- * @"a" ++ "b"@ becomes @"ab"@
-- * @x ++ ""@ becomes @x@, @"" ++ x@ becomes @x@
-- * @let v = pure in body@ (where @v@ is unused in @body@) becomes @body@
--
-- @since 0.19.2
simplify :: Opt.Expr -> Opt.Expr
simplify expr =
  simplifyExpr (walkChildren expr)

-- | Recursively simplify all child expressions before simplifying the parent.
--
-- @since 0.19.2
walkChildren :: Opt.Expr -> Opt.Expr
walkChildren expr =
  case expr of
    Opt.Call fn args ->
      Opt.Call (simplify fn) (fmap simplify args)
    Opt.If branches elseExpr ->
      Opt.If (fmap simplifyBranchPair branches) (simplify elseExpr)
    Opt.Let def body ->
      Opt.Let (simplifyDef def) (simplify body)
    Opt.Destruct destructor body ->
      Opt.Destruct destructor (simplify body)
    Opt.Case a b decider jumps ->
      Opt.Case a b (simplifyDecider decider) (fmap simplifyJump jumps)
    Opt.Function names body ->
      Opt.Function names (simplify body)
    Opt.TailCall name pairs ->
      Opt.TailCall name (fmap simplifyTailPair pairs)
    Opt.List items ->
      Opt.List (fmap simplify items)
    Opt.Tuple a b mc ->
      Opt.Tuple (simplify a) (simplify b) (fmap simplify mc)
    Opt.Access record field ->
      Opt.Access (simplify record) field
    Opt.Update record fields ->
      Opt.Update (simplify record) (fmap simplify fields)
    Opt.Record fields ->
      Opt.Record (fmap simplify fields)
    Opt.ArithBinop op l r ->
      Opt.ArithBinop op (simplify l) (simplify r)
    -- Leaves: no children to walk
    _ -> expr

-- | Simplify a single expression node after its children have been simplified.
--
-- @since 0.19.2
simplifyExpr :: Opt.Expr -> Opt.Expr
simplifyExpr expr =
  case expr of
    Opt.If branches elseExpr ->
      simplifyIf branches elseExpr
    Opt.Call fn args ->
      simplifyCall fn args
    Opt.Let def body ->
      simplifyLet def body
    _ -> expr

-- BOOLEAN SIMPLIFICATION

-- | Simplify conditional expressions with known boolean conditions.
--
-- @since 0.19.2
simplifyIf :: [(Opt.Expr, Opt.Expr)] -> Opt.Expr -> Opt.Expr
simplifyIf branches elseExpr =
  case branches of
    -- if True then a else b  =>  a
    [(Opt.Bool True, thenBranch)] ->
      thenBranch
    -- if False then a else b  =>  b
    [(Opt.Bool False, _)] ->
      elseExpr
    -- if c then True else False  =>  c
    [(cond, Opt.Bool True)]
      | isBoolFalse elseExpr ->
          cond
    -- if c then False else True  =>  not c
    [(cond, Opt.Bool False)]
      | isBoolTrue elseExpr ->
          mkNotCall cond
    -- No simplification applies
    _ ->
      Opt.If branches elseExpr

-- CALL SIMPLIFICATION

-- | Simplify function calls to known Basics functions.
--
-- @since 0.19.2
simplifyCall :: Opt.Expr -> [Opt.Expr] -> Opt.Expr
simplifyCall fn args =
  case (fn, args) of
    -- identity x  =>  x
    (Opt.VarGlobal global, [x])
      | isBasicsGlobal Name.identity global ->
          x
    -- not (not x)  =>  x
    (Opt.VarGlobal global, [Opt.Call innerFn [innerArg]])
      | isBasicsGlobal Name.not_ global
      , isNotCall innerFn ->
          innerArg
    -- True && x  =>  x
    (Opt.VarGlobal global, [Opt.Bool True, x])
      | isBasicsGlobal Name.and_ global ->
          x
    -- x && True  =>  x
    (Opt.VarGlobal global, [x, Opt.Bool True])
      | isBasicsGlobal Name.and_ global ->
          x
    -- False && _  =>  False
    (Opt.VarGlobal global, [Opt.Bool False, _])
      | isBasicsGlobal Name.and_ global ->
          Opt.Bool False
    -- _ && False  =>  False
    (Opt.VarGlobal global, [_, Opt.Bool False])
      | isBasicsGlobal Name.and_ global ->
          Opt.Bool False
    -- True || _  =>  True
    (Opt.VarGlobal global, [Opt.Bool True, _])
      | isBasicsGlobal Name.or_ global ->
          Opt.Bool True
    -- _ || True  =>  True
    (Opt.VarGlobal global, [_, Opt.Bool True])
      | isBasicsGlobal Name.or_ global ->
          Opt.Bool True
    -- False || x  =>  x
    (Opt.VarGlobal global, [Opt.Bool False, x])
      | isBasicsGlobal Name.or_ global ->
          x
    -- x || False  =>  x
    (Opt.VarGlobal global, [x, Opt.Bool False])
      | isBasicsGlobal Name.or_ global ->
          x
    -- "a" ++ "b"  =>  "ab"
    (Opt.VarGlobal global, [Opt.Str a, Opt.Str b])
      | isBasicsGlobal Name.append global ->
          Opt.Str (concatUtf8 a b)
    -- "" ++ x  =>  x
    (Opt.VarGlobal global, [Opt.Str s, x])
      | isBasicsGlobal Name.append global
      , Utf8.isEmpty s ->
          x
    -- x ++ ""  =>  x
    (Opt.VarGlobal global, [x, Opt.Str s])
      | isBasicsGlobal Name.append global
      , Utf8.isEmpty s ->
          x
    -- No simplification applies
    _ ->
      Opt.Call fn args

-- DEAD BINDING ELIMINATION

-- | Eliminate unused pure let-bindings.
--
-- If a let-binding defines a name that is never referenced in the body,
-- and the bound expression is pure (no side effects), the binding is
-- removed entirely.
--
-- @since 0.19.2
simplifyLet :: Opt.Def -> Opt.Expr -> Opt.Expr
simplifyLet def body =
  case def of
    Opt.Def name boundExpr
      | isPure boundExpr && not (nameUsedIn name body) ->
          body
    _ ->
      Opt.Let def body

-- HELPERS

-- | Check whether a 'Global' refers to a specific function in the Basics module.
--
-- @since 0.19.2
isBasicsGlobal :: Name.Name -> Opt.Global -> Bool
isBasicsGlobal name (Opt.Global home funcName) =
  home == ModuleName.basics && funcName == name

-- | Check whether an expression is a call to @Basics.not@.
--
-- @since 0.19.2
isNotCall :: Opt.Expr -> Bool
isNotCall (Opt.VarGlobal global) = isBasicsGlobal Name.not_ global
isNotCall _ = False

-- | Build a @Basics.not@ call expression.
--
-- @since 0.19.2
mkNotCall :: Opt.Expr -> Opt.Expr
mkNotCall arg =
  Opt.Call (Opt.VarGlobal (Opt.Global ModuleName.basics Name.not_)) [arg]

-- | Check whether an expression is the boolean literal @True@.
--
-- @since 0.19.2
isBoolTrue :: Opt.Expr -> Bool
isBoolTrue (Opt.Bool True) = True
isBoolTrue _ = False

-- | Check whether an expression is the boolean literal @False@.
--
-- @since 0.19.2
isBoolFalse :: Opt.Expr -> Bool
isBoolFalse (Opt.Bool False) = True
isBoolFalse _ = False

-- | Concatenate two UTF-8 strings by converting to [Char] and back.
--
-- @since 0.19.2
concatUtf8 :: Utf8.Utf8 t -> Utf8.Utf8 t -> Utf8.Utf8 t
concatUtf8 a b =
  Utf8.fromChars (Utf8.toChars a ++ Utf8.toChars b)

-- | Check whether an expression is pure (has no observable side effects).
--
-- Pure expressions can be safely eliminated if their result is unused.
-- Only a conservative subset of expressions is considered pure to avoid
-- incorrectly eliminating effectful code.
--
-- @since 0.19.2
isPure :: Opt.Expr -> Bool
isPure expr =
  case expr of
    Opt.Bool _ -> True
    Opt.Chr _ -> True
    Opt.Str _ -> True
    Opt.Int _ -> True
    Opt.Float _ -> True
    Opt.VarLocal _ -> True
    Opt.VarGlobal _ -> True
    Opt.VarEnum _ _ -> True
    Opt.VarBox _ -> True
    Opt.VarKernel _ _ -> True
    Opt.Unit -> True
    Opt.Tuple a b mc ->
      isPure a && isPure b && maybe True isPure mc
    Opt.List items ->
      all isPure items
    Opt.Record fields ->
      all isPure (Map.elems fields)
    Opt.Function _ _ -> True
    _ -> False

-- | Check whether a name is referenced within an expression.
--
-- Performs a conservative traversal: if the name appears anywhere in the
-- expression tree, it is considered used. This avoids false positives from
-- shadowing but may miss some dead bindings (conservative is correct).
--
-- @since 0.19.2
nameUsedIn :: Name.Name -> Opt.Expr -> Bool
nameUsedIn name = go
  where
    go expr =
      case expr of
        Opt.VarLocal n -> n == name
        Opt.Call fn args -> go fn || any go args
        Opt.If branches elseExpr ->
          any (\(c, b) -> go c || go b) branches || go elseExpr
        Opt.Let def body -> goInDef def || go body
        Opt.Destruct _ body -> go body
        Opt.Case _ _ decider jumps ->
          nameInDecider name decider || any (go . snd) jumps
        Opt.Function _ body -> go body
        Opt.TailCall _ pairs -> any (go . snd) pairs
        Opt.List items -> any go items
        Opt.Tuple a b mc -> go a || go b || maybe False go mc
        Opt.Access record _ -> go record
        Opt.Update record fields -> go record || any go (Map.elems fields)
        Opt.Record fields -> any go (Map.elems fields)
        Opt.ArithBinop _ l r -> go l || go r
        _ -> False

    goInDef (Opt.Def _ e) = go e
    goInDef (Opt.TailDef _ _ e) = go e

-- | Check whether a name appears in a decision tree.
--
-- @since 0.19.2
nameInDecider :: Name.Name -> Opt.Decider Opt.Choice -> Bool
nameInDecider name = go
  where
    go decider =
      case decider of
        Opt.Leaf choice -> nameInChoice name choice
        Opt.Chain _ success failure -> go success || go failure
        Opt.FanOut _ tests fallback ->
          go fallback || any (go . snd) tests

-- | Check whether a name appears in a choice.
--
-- @since 0.19.2
nameInChoice :: Name.Name -> Opt.Choice -> Bool
nameInChoice name choice =
  case choice of
    Opt.Inline expr -> nameUsedIn name expr
    Opt.Jump _ -> False

-- RECURSIVE HELPERS

-- | Simplify a branch pair in an If expression.
--
-- @since 0.19.2
simplifyBranchPair :: (Opt.Expr, Opt.Expr) -> (Opt.Expr, Opt.Expr)
simplifyBranchPair (cond, branch) = (simplify cond, simplify branch)

-- | Simplify a definition.
--
-- @since 0.19.2
simplifyDef :: Opt.Def -> Opt.Def
simplifyDef def =
  case def of
    Opt.Def n e -> Opt.Def n (simplify e)
    Opt.TailDef n ns e -> Opt.TailDef n ns (simplify e)

-- | Simplify a jump table entry.
--
-- @since 0.19.2
simplifyJump :: (Int, Opt.Expr) -> (Int, Opt.Expr)
simplifyJump (idx, e) = (idx, simplify e)

-- | Simplify a tail call argument pair.
--
-- @since 0.19.2
simplifyTailPair :: (Name.Name, Opt.Expr) -> (Name.Name, Opt.Expr)
simplifyTailPair (n, e) = (n, simplify e)

-- | Simplify expressions within a decision tree.
--
-- @since 0.19.2
simplifyDecider :: Opt.Decider Opt.Choice -> Opt.Decider Opt.Choice
simplifyDecider decider =
  case decider of
    Opt.Leaf choice -> Opt.Leaf (simplifyChoice choice)
    Opt.Chain tests success failure ->
      Opt.Chain tests (simplifyDecider success) (simplifyDecider failure)
    Opt.FanOut path tests fallback ->
      Opt.FanOut path (fmap simplifyTest tests) (simplifyDecider fallback)

-- | Simplify a choice expression.
--
-- @since 0.19.2
simplifyChoice :: Opt.Choice -> Opt.Choice
simplifyChoice choice =
  case choice of
    Opt.Inline expr -> Opt.Inline (simplify expr)
    Opt.Jump idx -> Opt.Jump idx

-- | Simplify a test branch in a FanOut.
--
-- @since 0.19.2
simplifyTest :: (a, Opt.Decider Opt.Choice) -> (a, Opt.Decider Opt.Choice)
simplifyTest (test, dec) = (test, simplifyDecider dec)

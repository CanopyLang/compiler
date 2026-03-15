{-# LANGUAGE OverloadedStrings #-}

-- | Post-optimization warning detection for the Canopy compiler.
--
-- Walks the optimized AST to detect patterns that indicate potential
-- runtime issues which cannot be caught by the type system:
--
-- * Integer overflow beyond JavaScript's @MAX_SAFE_INTEGER@ (2^53 - 1)
-- * Division by constant zero producing @NaN@ or @Infinity@
-- * Unreachable branches from constant boolean conditions
--
-- This pass runs AFTER constant folding and BEFORE simplification,
-- so it can detect both folded results and about-to-be-eliminated branches.
--
-- @since 0.20.1
module Optimize.Warnings
  ( collectPreSimplifyWarnings,
    collectPostFoldWarnings,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Reporting.Warning as Warning

-- | JavaScript's MAX_SAFE_INTEGER (2^53 - 1).
maxSafeInteger :: Int
maxSafeInteger = 9007199254740991

-- | Collect warnings from an optimized expression BEFORE simplification.
--
-- Detects unreachable branches that simplification will eliminate:
--
-- * @if True then a else b@ — the else branch is dead
-- * @if False then a else b@ — the then branch is dead
--
-- @since 0.20.1
collectPreSimplifyWarnings :: Opt.Expr -> [Warning.Warning]
collectPreSimplifyWarnings = go
  where
    go expr = case expr of
      Opt.If branches elseExpr ->
        detectDeadBranches branches ++ concatMap goBranch branches ++ go elseExpr
      Opt.Call fn args ->
        go fn ++ concatMap go args
      Opt.Let def body ->
        goDef def ++ go body
      Opt.Destruct _ body -> go body
      Opt.Case _ _ decider jumps ->
        goDecider decider ++ concatMap (go . snd) jumps
      Opt.Function _ body -> go body
      Opt.TailCall _ pairs -> concatMap (go . snd) pairs
      Opt.List items -> concatMap go items
      Opt.Tuple a b mc ->
        go a ++ go b ++ maybe [] go mc
      Opt.Access record _ -> go record
      Opt.Update record fields ->
        go record ++ concatMap go (fmap id fields)
      Opt.Record fields -> concatMap go (fmap id fields)
      Opt.ArithBinop _ l r -> go l ++ go r
      _ -> []

    goBranch (c, b) = go c ++ go b

    goDef (Opt.Def _ e) = go e
    goDef (Opt.TailDef _ _ e) = go e

    goDecider (Opt.Leaf choice) = goChoice choice
    goDecider (Opt.Chain _ s f) = goDecider s ++ goDecider f
    goDecider (Opt.FanOut _ tests fallback) =
      goDecider fallback ++ concatMap (goDecider . snd) tests

    goChoice (Opt.Inline e) = go e
    goChoice (Opt.Jump _) = []

-- | Detect dead branches in an If expression.
detectDeadBranches :: [(Opt.Expr, Opt.Expr)] -> [Warning.Warning]
detectDeadBranches [(Opt.Bool True, _)] =
  [Warning.UnreachableBranch 0 "else branch is unreachable (condition is always True)"]
detectDeadBranches [(Opt.Bool False, _)] =
  [Warning.UnreachableBranch 0 "then branch is unreachable (condition is always False)"]
detectDeadBranches _ = []

-- | Collect warnings from an optimized expression AFTER constant folding.
--
-- Detects:
--
-- * Integer literals that exceed JavaScript's safe integer range
-- * Division by constant zero
--
-- @since 0.20.1
collectPostFoldWarnings :: Opt.Expr -> [Warning.Warning]
collectPostFoldWarnings = go
  where
    go expr = case expr of
      Opt.Int n
        | abs n > maxSafeInteger ->
            [Warning.IntegerOverflow 0 n]
      Opt.ArithBinop Can.Div _ (Opt.Int 0) ->
        [Warning.DivisionByZero 0]
      Opt.Call fn args ->
        go fn ++ concatMap go args
      Opt.If branches elseExpr ->
        concatMap goBranch branches ++ go elseExpr
      Opt.Let def body ->
        goDef def ++ go body
      Opt.Destruct _ body -> go body
      Opt.Case _ _ decider jumps ->
        goDecider decider ++ concatMap (go . snd) jumps
      Opt.Function _ body -> go body
      Opt.TailCall _ pairs -> concatMap (go . snd) pairs
      Opt.List items -> concatMap go items
      Opt.Tuple a b mc ->
        go a ++ go b ++ maybe [] go mc
      Opt.Access record _ -> go record
      Opt.Update record fields ->
        go record ++ concatMap go (fmap id fields)
      Opt.Record fields -> concatMap go (fmap id fields)
      Opt.ArithBinop _ l r -> go l ++ go r
      _ -> []

    goBranch (c, b) = go c ++ go b

    goDef (Opt.Def _ e) = go e
    goDef (Opt.TailDef _ _ e) = go e

    goDecider (Opt.Leaf choice) = goChoice choice
    goDecider (Opt.Chain _ s f) = goDecider s ++ goDecider f
    goDecider (Opt.FanOut _ tests fallback) =
      goDecider fallback ++ concatMap (goDecider . snd) tests

    goChoice (Opt.Inline e) = go e
    goChoice (Opt.Jump _) = []

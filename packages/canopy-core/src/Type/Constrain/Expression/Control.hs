-- | Control flow constraint generation.
--
-- This module generates type constraints for control flow expressions:
-- @if@/@then@/@else@ branches and @case@ pattern matching. Both constructs
-- require all branches to produce the same type, enforced through constraint
-- generation.
--
-- For @if@ expressions, conditions are constrained to @Bool@ and all branches
-- (including the @else@) must unify. For @case@ expressions, the scrutinee
-- is constrained against the pattern types, and all branch bodies must unify.
module Type.Constrain.Expression.Control
  ( constrainIf,
    constrainCase,
    constrainCaseBranch,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Index as Index
import Reporting.Annotation (Region)
import Reporting.Error.Type (Category (..), Context (..), Expected (..), PContext (..), PExpected (..), SubContext (..))
import qualified Type.Constrain.Pattern as Pattern
import Type.Type as Type hiding (Descriptor (..))

-- | Constrain function type, passed in to avoid circular module dependencies.
type Constrain = Can.Expr -> Expected Type -> IO Constraint

-- | Generate type constraints for an @if@/@then@/@else@ expression.
--
-- All conditions are constrained to @Bool@. When the expected type comes
-- from a type annotation, each branch is constrained against that annotation.
-- Otherwise a fresh type variable is introduced that all branches must unify with.
constrainIf :: Constrain -> Region -> [(Can.Expr, Can.Expr)] -> Can.Expr -> Expected Type -> IO Constraint
constrainIf doConstrain region branches final expected =
  do
    let boolExpect = FromContext region IfCondition Type.bool
    let (conditions, exprs) = foldr (\(c, e) (cs, es) -> (c : cs, e : es)) ([], [final]) branches

    condCons <-
      traverse (\c -> doConstrain c boolExpect) conditions

    case expected of
      FromAnnotation name arity _ tipe ->
        do
          branchCons <- Index.indexedForA exprs $ \index expr ->
            doConstrain expr (FromAnnotation name arity (TypedIfBranch index) tipe)
          return $
            CAnd
              [ CAnd condCons,
                CAnd branchCons
              ]
      _ ->
        do
          branchVar <- mkFlexVar
          let branchType = VarN branchVar

          branchCons <- Index.indexedForA exprs $ \index expr ->
            doConstrain expr (FromContext region (IfBranch index) branchType)

          return $
            exists [branchVar] $
              CAnd
                [ CAnd condCons,
                  CAnd branchCons,
                  CEqual region If branchType expected
                ]

-- | Generate type constraints for a @case@ expression.
--
-- The scrutinee expression is constrained to a fresh type variable that
-- each pattern must match. When the expected type comes from an annotation,
-- branch bodies are constrained against that annotation; otherwise a fresh
-- variable is introduced for branch unification.
constrainCase :: Constrain -> Region -> Can.Expr -> [Can.CaseBranch] -> Expected Type -> IO Constraint
constrainCase doConstrain region expr branches expected =
  do
    ptrnVar <- mkFlexVar
    let ptrnType = VarN ptrnVar
    exprCon <- doConstrain expr (NoExpectation ptrnType)

    case expected of
      FromAnnotation name arity _ tipe ->
        do
          branchCons <- Index.indexedForA branches $ \index branch ->
            constrainCaseBranch
              doConstrain
              branch
              (PFromContext region (PCaseMatch index) ptrnType)
              (FromAnnotation name arity (TypedCaseBranch index) tipe)

          return $ exists [ptrnVar] $ CAnd [exprCon, CCaseBranchesIsolated branchCons]
      _ ->
        do
          branchVar <- mkFlexVar
          let branchType = VarN branchVar

          branchCons <- Index.indexedForA branches $ \index branch ->
            constrainCaseBranch
              doConstrain
              branch
              (PFromContext region (PCaseMatch index) ptrnType)
              (FromContext region (CaseBranch index) branchType)

          return $
            exists [ptrnVar, branchVar] $
              CAnd
                [ exprCon,
                  CCaseBranchesIsolated branchCons,
                  CEqual region Case branchType expected
                ]

-- | Generate type constraints for a single @case@ branch.
--
-- The pattern is added to the constraint state, and the branch body
-- is constrained with the resulting header bindings in scope.
constrainCaseBranch :: Constrain -> Can.CaseBranch -> PExpected Type -> Expected Type -> IO Constraint
constrainCaseBranch doConstrain (Can.CaseBranch pattern expr) pExpect bExpect =
  do
    (Pattern.State headers pvars revCons) <-
      Pattern.add pattern pExpect Pattern.emptyState

    CLet [] pvars headers (CAnd (reverse revCons))
      <$> doConstrain expr bExpect
      <*> pure Nothing

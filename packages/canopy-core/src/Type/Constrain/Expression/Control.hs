-- | Control flow constraint generation with type guard narrowing.
--
-- This module generates type constraints for control flow expressions:
-- @if@/@then@/@else@ branches and @case@ pattern matching. Both constructs
-- require all branches to produce the same type, enforced through constraint
-- generation.
--
-- For @if@ expressions, when a condition is a call to a guard function,
-- the then-branch constrains the guarded variable to the guard's declared
-- narrow type. This enables type narrowing based on predicate functions.
--
-- For @case@ expressions, the scrutinee is constrained against the pattern
-- types, and all branch bodies must unify.
--
-- @since 0.19.1
module Type.Constrain.Expression.Control
  ( constrainIf,
    constrainCase,
    constrainCaseBranch,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import Data.List (foldl')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Reporting.Annotation as Ann
import Reporting.Annotation (Region)
import Reporting.Error.Type (Category (..), Context (..), Expected (..), PContext (..), PExpected (..), SubContext (..))
import qualified Type.Constrain.Pattern as Pattern
import qualified Type.Instantiate as Instantiate
import Type.Type as Type hiding (Descriptor (..))

-- | Constrain function type, passed in to avoid circular module dependencies.
type Constrain = Can.Expr -> Expected Type -> IO Constraint

-- GUARD CALL DETECTION

-- | Information about a detected guard function call in an if-condition.
--
-- When a condition expression is @guardFn argExpr@, and @guardFn@ has a
-- guard annotation, this record captures the narrowing information needed
-- to constrain the then-branch.
--
-- @since 0.20.0
data GuardCallInfo = GuardCallInfo
  { _gciArgName :: !Name.Name,
    _gciNarrowType :: !Can.Type
  }

-- | Detect a guard function call in a condition expression.
--
-- A guard call is a @Can.Call@ where the function is a local or top-level
-- variable that appears in the guard map. Returns 'Nothing' when the
-- condition is not a guard call.
--
-- @since 0.20.0
extractGuardCall :: Map Name.Name Can.GuardInfo -> Can.Expr -> Maybe GuardCallInfo
extractGuardCall guardMap (Ann.At _ (Can.Call func args)) =
  guardCallFromFunc guardMap func args
extractGuardCall _ _ = Nothing

-- | Extract guard info from a function call's function and arguments.
--
-- @since 0.20.0
guardCallFromFunc :: Map Name.Name Can.GuardInfo -> Can.Expr -> [Can.Expr] -> Maybe GuardCallInfo
guardCallFromFunc guardMap func args = do
  name <- extractVarName func
  lookupGuardCall guardMap name args

-- | Extract the variable name from a local or top-level variable expression.
--
-- @since 0.20.0
extractVarName :: Can.Expr -> Maybe Name.Name
extractVarName (Ann.At _ (Can.VarLocal name)) = Just name
extractVarName (Ann.At _ (Can.VarTopLevel _ name)) = Just name
extractVarName _ = Nothing

-- | Look up a function name in the guard map and extract guard call info.
--
-- Uses the guard's @_giArgIndex@ to find the argument expression, then
-- extracts its variable name. Returns 'Nothing' if the function is not
-- a guard, the argument index is out of bounds, or the argument is not
-- a simple variable.
--
-- @since 0.20.0
lookupGuardCall :: Map Name.Name Can.GuardInfo -> Name.Name -> [Can.Expr] -> Maybe GuardCallInfo
lookupGuardCall guardMap name args = do
  guardInfo <- Map.lookup name guardMap
  argExpr <- safeIndex args (Can._giArgIndex guardInfo)
  argName <- extractVarName argExpr
  pure (GuardCallInfo argName (Can._giNarrowType guardInfo))

-- | Create a zero-based index from an integer count.
--
-- Equivalent to calling 'Index.next' @n@ times starting from 'Index.first'.
--
-- @since 0.20.0
indexFromLength :: Int -> Index.ZeroBased
indexFromLength n = foldl' (\acc _ -> Index.next acc) Index.first [1 .. n]

-- | Safe list index that returns 'Nothing' for out-of-bounds access.
--
-- @since 0.20.0
safeIndex :: [a] -> Int -> Maybe a
safeIndex (x : _) 0 = Just x
safeIndex (_ : xs) n
  | n > 0 = safeIndex xs (n - 1)
safeIndex _ _ = Nothing

-- TYPE NARROWING

-- | Collect all free type variable names from a canonical type.
--
-- @since 0.20.0
collectFreeVars :: Can.Type -> Set Name.Name
collectFreeVars (Can.TVar name) = Set.singleton name
collectFreeVars (Can.TLambda a b) = Set.union (collectFreeVars a) (collectFreeVars b)
collectFreeVars (Can.TType _ _ args) = Set.unions (fmap collectFreeVars args)
collectFreeVars (Can.TTuple a b mc) =
  Set.unions (collectFreeVars a : collectFreeVars b : maybe [] (pure . collectFreeVars) mc)
collectFreeVars (Can.TRecord fields _) =
  Set.unions (fmap collectCanFieldType (Map.elems fields))
collectFreeVars (Can.TAlias _ _ args _) =
  Set.unions (fmap (collectFreeVars . snd) args)
collectFreeVars Can.TUnit = Set.empty

-- | Collect free vars from a canonical field type.
--
-- @since 0.20.0
collectCanFieldType :: Can.FieldType -> Set Name.Name
collectCanFieldType (Can.FieldType _ t) = collectFreeVars t

-- | Constrain a branch expression, optionally applying guard narrowing.
--
-- When no guard is detected, delegates directly to the constrainer.
-- When a guard is detected, wraps the constraint in a 'CLet' that
-- provides the narrow type for the guarded variable.
--
-- @since 0.20.0
constrainOneGuardedBranch :: Maybe GuardCallInfo -> Constrain -> Can.Expr -> Expected Type -> IO Constraint
constrainOneGuardedBranch Nothing doConstrain expr expected =
  doConstrain expr expected
constrainOneGuardedBranch (Just guardCall) doConstrain expr expected = do
  innerCon <- doConstrain expr expected
  wrapWithNarrowing guardCall innerCon

-- | Wrap a constraint with a CLet that narrows a variable to the guard's type.
--
-- Creates fresh flex variables for free type variables in the narrow type,
-- instantiates the narrow type, and wraps the inner constraint in a CLet
-- that shadows the guarded variable with the narrowed type.
--
-- @since 0.20.0
wrapWithNarrowing :: GuardCallInfo -> Constraint -> IO Constraint
wrapWithNarrowing (GuardCallInfo argName narrowCanType) innerCon = do
  let freeVarNames = Set.toList (collectFreeVars narrowCanType)
  freshVars <- traverse (const mkFlexVar) freeVarNames
  let varMap = Map.fromList (zip freeVarNames (fmap VarN freshVars))
  narrowType <- Instantiate.fromSrcType varMap narrowCanType
  let header = Map.singleton argName (Ann.At Ann.zero narrowType)
  pure (CLet [] freshVars header CTrue innerCon Nothing)

-- IF EXPRESSIONS

-- | Generate type constraints for an @if@/@then@/@else@ expression.
--
-- All conditions are constrained to @Bool@. When a condition is a call
-- to a guard function, the corresponding then-branch sees the guarded
-- variable with the narrowed type. When the expected type comes from a
-- type annotation, each branch is constrained against that annotation.
-- Otherwise a fresh type variable is introduced that all branches must
-- unify with.
--
-- @since 0.19.1
constrainIf :: Map Name.Name Can.GuardInfo -> Constrain -> Region -> [(Can.Expr, Can.Expr)] -> Can.Expr -> Expected Type -> IO Constraint
constrainIf guardMap doConstrain region branches final expected =
  do
    let boolExpect = FromContext region IfCondition Type.bool
    let conditions = fmap fst branches
    let thenExprs = fmap snd branches
    let guardCalls = fmap (extractGuardCall guardMap) conditions

    condCons <- traverse (\c -> doConstrain c boolExpect) conditions

    case expected of
      FromAnnotation name arity _ tipe ->
        constrainIfAnnotated guardCalls doConstrain thenExprs final name arity tipe condCons
      _ ->
        constrainIfInferred guardCalls doConstrain region thenExprs final expected condCons

-- | Constrain if-branches when an annotation provides the expected type.
--
-- @since 0.20.0
constrainIfAnnotated :: [Maybe GuardCallInfo] -> Constrain -> [Can.Expr] -> Can.Expr -> Name.Name -> Int -> Type -> [Constraint] -> IO Constraint
constrainIfAnnotated guardCalls doConstrain thenExprs final name arity tipe condCons =
  do
    thenCons <- traverseGuarded guardCalls thenExprs $ \index mGuard expr ->
      constrainOneGuardedBranch mGuard doConstrain expr
        (FromAnnotation name arity (TypedIfBranch index) tipe)

    let finalIndex = indexFromLength (length thenExprs)
    finalCon <- doConstrain final
      (FromAnnotation name arity (TypedIfBranch finalIndex) tipe)

    pure (CAnd [CAnd condCons, CAnd thenCons, finalCon])

-- | Constrain if-branches when the expected type is inferred.
--
-- @since 0.20.0
constrainIfInferred :: [Maybe GuardCallInfo] -> Constrain -> Region -> [Can.Expr] -> Can.Expr -> Expected Type -> [Constraint] -> IO Constraint
constrainIfInferred guardCalls doConstrain region thenExprs final expected condCons =
  do
    branchVar <- mkFlexVar
    let branchType = VarN branchVar

    thenCons <- traverseGuarded guardCalls thenExprs $ \index mGuard expr ->
      constrainOneGuardedBranch mGuard doConstrain expr
        (FromContext region (IfBranch index) branchType)

    let finalIndex = indexFromLength (length thenExprs)
    finalCon <- doConstrain final
      (FromContext region (IfBranch finalIndex) branchType)

    pure $
      exists [branchVar] $
        CAnd
          [ CAnd condCons,
            CAnd thenCons,
            finalCon,
            CEqual region If branchType expected
          ]

-- | Traverse expressions paired with optional guard info, indexed from 0.
--
-- Each expression is visited with its corresponding guard info (or 'Nothing'
-- if the guard list is shorter than the expression list).
--
-- @since 0.20.0
traverseGuarded :: [Maybe GuardCallInfo] -> [Can.Expr] -> (Index.ZeroBased -> Maybe GuardCallInfo -> Can.Expr -> IO Constraint) -> IO [Constraint]
traverseGuarded guardCalls exprs f =
  go Index.first guardCalls exprs
  where
    go _ _ [] = pure []
    go idx (g : gs) (e : es) = (:) <$> f idx g e <*> go (Index.next idx) gs es
    go idx [] (e : es) = (:) <$> f idx Nothing e <*> go (Index.next idx) [] es

-- CASE EXPRESSIONS

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

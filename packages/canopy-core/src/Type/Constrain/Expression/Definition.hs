-- | Definition constraint generation.
--
-- This module handles type constraint generation for value definitions,
-- recursive definition groups, destructuring let-bindings, and function
-- argument patterns. Definitions introduce type bindings into scope through
-- @CLet@ constraints, supporting both annotated and unannotated forms.
--
-- Recursive definitions are handled specially: typed (annotated) definitions
-- produce rigid type variables, while untyped definitions produce flexible
-- variables that can unify freely.
module Type.Constrain.Expression.Definition
  ( constrainDef,
    constrainRecursiveDefs,
    recDefsHelp,
    constrainDestruct,
    Args (..),
    constrainArgs,
    argsHelp,
    TypedArgs (..),
    constrainTypedArgs,
    typedArgsHelp,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Reporting.Annotation as Ann
import Reporting.Annotation (Region)
import Reporting.Error.Type (Context (..), Expected (..), PContext (..), PExpected (..), SubContext (..))
import qualified Type.Constrain.Pattern as Pattern
import qualified Type.Instantiate as Instantiate
import Type.Type as Type hiding (Descriptor (..))

-- | Constrain function type, passed in to avoid circular module dependencies.
type Constrain = Can.Expr -> Expected Type -> IO Constraint

-- | Generate type constraints for a value definition.
--
-- For unannotated definitions, all type variables are flexible and the
-- definition's type is inferred. For annotated definitions, free type
-- variables from the annotation become rigid, preventing unification
-- with incompatible types.
constrainDef :: Constrain -> Map Name.Name Type -> Can.Def -> Constraint -> Expected Type -> IO Constraint
constrainDef doConstrain rtv def bodyCon expected = do
  let (_defName, _defType) = case def of
        Can.Def (Ann.At _ n) _ _ -> (n, "Def" :: String)
        Can.TypedDef (Ann.At _ n) _ _ _ _ -> (n, "TypedDef" :: String)
      expectedType = case expected of
        NoExpectation t -> Just t
        FromContext _ _ t -> Just t
        FromAnnotation _ _ _ t -> Just t
  case def of
    Can.Def (Ann.At region name) args expr ->
      constrainUnannotatedDef doConstrain rtv region name args expr bodyCon expectedType
    Can.TypedDef (Ann.At region name) freeVars typedArgs expr srcResultType ->
      constrainAnnotatedDef doConstrain rtv region name freeVars typedArgs expr srcResultType bodyCon expectedType

-- | Constrain an unannotated definition.
constrainUnannotatedDef :: Constrain -> Map Name.Name Type -> Region -> Name.Name -> [Can.Pattern] -> Can.Expr -> Constraint -> Maybe Type -> IO Constraint
constrainUnannotatedDef doConstrain rtv region name args expr bodyCon expectedType =
  do
    (Args vars tipe resultType (Pattern.State headers pvars revCons)) <-
      constrainArgs args

    exprCon <-
      doConstrain expr (NoExpectation resultType)

    return $
      CLet
        { _rigidVars = [],
          _flexVars = vars,
          _header = Map.singleton name (Ann.At region tipe),
          _headerCon =
            CLet
              { _rigidVars = [],
                _flexVars = pvars,
                _header = headers,
                _headerCon = CAnd (reverse revCons),
                _bodyCon = exprCon,
                _expectedType = Nothing
              },
          _bodyCon = bodyCon,
          _expectedType = expectedType
        }

-- | Constrain an annotated definition with rigid type variables.
constrainAnnotatedDef :: Constrain -> Map Name.Name Type -> Region -> Name.Name -> Map Name.Name () -> [(Can.Pattern, Can.Type)] -> Can.Expr -> Can.Type -> Constraint -> Maybe Type -> IO Constraint
constrainAnnotatedDef doConstrain rtv region name freeVars typedArgs expr srcResultType bodyCon expectedType =
  do
    let newNames = Map.difference freeVars rtv
    newRigids <- Map.traverseWithKey (\n _ -> nameToRigid n) newNames
    let newRtv = Map.union rtv (Map.map VarN newRigids)

    let existingRigids = [var | (n, VarN var) <- Map.toList rtv, Map.member n freeVars]
    let allRigids = existingRigids <> Map.elems newRigids

    (TypedArgs tipe resultType (Pattern.State headers pvars revCons)) <-
      constrainTypedArgs newRtv name typedArgs srcResultType

    let exprExpected = FromAnnotation name (length typedArgs) TypedBody resultType
    exprCon <-
      doConstrain expr exprExpected

    return $
      CLet
        { _rigidVars = allRigids,
          _flexVars = [],
          _header = Map.singleton name (Ann.At region tipe),
          _headerCon =
            CLet
              { _rigidVars = [],
                _flexVars = pvars,
                _header = headers,
                _headerCon = CAnd (reverse revCons),
                _bodyCon = exprCon,
                _expectedType = Nothing
              },
          _bodyCon = bodyCon,
          _expectedType = expectedType
        }

-- CONSTRAIN RECURSIVE DEFS

-- | Accumulator for recursive definition constraint collection.
data Info = Info
  { _vars :: [Variable],
    _cons :: [Constraint],
    _headers :: Map Name.Name (Ann.Located Type)
  }

{-# NOINLINE emptyInfo #-}
emptyInfo :: Info
emptyInfo =
  Info [] [] Map.empty

-- | Generate type constraints for a mutually recursive definition group.
--
-- Typed and untyped definitions are collected separately: typed definitions
-- produce rigid variables (preventing unification with incompatible types),
-- while untyped definitions produce flexible variables. The final constraint
-- nests both groups appropriately.
constrainRecursiveDefs :: Constrain -> Map Name.Name Type -> [Can.Def] -> Constraint -> IO Constraint
constrainRecursiveDefs doConstrain rtv defs bodyCon =
  recDefsHelp doConstrain rtv defs bodyCon emptyInfo emptyInfo

-- | Worker for recursive definition constraint generation.
--
-- Processes each definition in turn, accumulating rigid and flexible
-- constraint information separately, then combines them into a final
-- nested @CLet@ constraint.
recDefsHelp :: Constrain -> Map Name.Name Type -> [Can.Def] -> Constraint -> Info -> Info -> IO Constraint
recDefsHelp doConstrain rtv defs bodyCon rigidInfo flexInfo =
  case defs of
    [] ->
      do
        let (Info rigidVars rigidCons rigidHeaders) = rigidInfo
        let (Info flexVars flexCons flexHeaders) = flexInfo
        return $
          CLet rigidVars [] rigidHeaders CTrue
            (CLet [] flexVars flexHeaders
              (CLet [] [] flexHeaders CTrue (CAnd flexCons) Nothing)
              (CAnd [CAnd rigidCons, bodyCon])
              Nothing)
            Nothing
    def : otherDefs ->
      case def of
        Can.Def (Ann.At region name) args expr ->
          recDefsHelpUntyped doConstrain rtv otherDefs bodyCon rigidInfo flexInfo region name args expr
        Can.TypedDef (Ann.At region name) freeVars typedArgs expr srcResultType ->
          recDefsHelpTyped doConstrain rtv otherDefs bodyCon rigidInfo flexInfo region name freeVars typedArgs expr srcResultType

-- | Process an untyped definition in a recursive group.
recDefsHelpUntyped :: Constrain -> Map Name.Name Type -> [Can.Def] -> Constraint -> Info -> Info -> Region -> Name.Name -> [Can.Pattern] -> Can.Expr -> IO Constraint
recDefsHelpUntyped doConstrain rtv otherDefs bodyCon rigidInfo flexInfo region name args expr =
  do
    let (Info flexVars flexCons flexHeaders) = flexInfo

    (Args newFlexVars tipe resultType (Pattern.State headers pvars revCons)) <-
      argsHelp args (Pattern.State Map.empty flexVars [])

    exprCon <-
      doConstrain expr (NoExpectation resultType)

    let defCon =
          CLet
            { _rigidVars = [],
              _flexVars = pvars,
              _header = headers,
              _headerCon = CAnd (reverse revCons),
              _bodyCon = exprCon,
              _expectedType = Nothing
            }

    recDefsHelp doConstrain rtv otherDefs bodyCon rigidInfo $
      Info
        { _vars = newFlexVars,
          _cons = defCon : flexCons,
          _headers = Map.insert name (Ann.At region tipe) flexHeaders
        }

-- | Process a typed definition in a recursive group.
recDefsHelpTyped :: Constrain -> Map Name.Name Type -> [Can.Def] -> Constraint -> Info -> Info -> Region -> Name.Name -> Map Name.Name () -> [(Can.Pattern, Can.Type)] -> Can.Expr -> Can.Type -> IO Constraint
recDefsHelpTyped doConstrain rtv otherDefs bodyCon rigidInfo flexInfo region name freeVars typedArgs expr srcResultType =
  do
    let newNames = Map.difference freeVars rtv
    newRigids <- Map.traverseWithKey (\n _ -> nameToRigid n) newNames
    let newRtv = Map.union rtv (Map.map VarN newRigids)

    let existingRigids = [var | (n, VarN var) <- Map.toList rtv, Map.member n freeVars]
    let allRigids = existingRigids <> Map.elems newRigids

    (TypedArgs tipe resultType (Pattern.State headers pvars revCons)) <-
      constrainTypedArgs newRtv name typedArgs srcResultType

    exprCon <-
      doConstrain expr $
        FromAnnotation name (length typedArgs) TypedBody resultType

    let defCon =
          CLet
            { _rigidVars = [],
              _flexVars = pvars,
              _header = headers,
              _headerCon = CAnd (reverse revCons),
              _bodyCon = exprCon,
              _expectedType = Nothing
            }

    let (Info rigidVars rigidCons rigidHeaders) = rigidInfo
    recDefsHelp
      doConstrain
      rtv
      otherDefs
      bodyCon
      ( Info
          { _vars = foldr (:) rigidVars allRigids,
            _cons = CLet allRigids [] Map.empty defCon CTrue Nothing : rigidCons,
            _headers = Map.insert name (Ann.At region tipe) rigidHeaders
          }
      )
      flexInfo

-- CONSTRAIN DESTRUCTURES

-- | Generate type constraints for a destructuring let-binding.
--
-- The pattern is matched against the expression type, and any bindings
-- introduced by the pattern are made available in the body constraint.
constrainDestruct :: Constrain -> Map Name.Name Type -> Region -> Can.Pattern -> Can.Expr -> Constraint -> IO Constraint
constrainDestruct doConstrain rtv region pattern expr bodyCon =
  do
    patternVar <- mkFlexVar
    let patternType = VarN patternVar

    (Pattern.State headers pvars revCons) <-
      Pattern.add pattern (PNoExpectation patternType) Pattern.emptyState

    exprCon <-
      doConstrain expr (FromContext region Destructure patternType)

    return $ CLet [] (patternVar : pvars) headers (CAnd (reverse (exprCon : revCons))) bodyCon Nothing

-- CONSTRAIN ARGS

-- | Result of constraining a list of function argument patterns.
data Args = Args
  { _a_vars :: [Variable],
    _a_type :: Type,
    _a_result :: Type,
    _a_state :: Pattern.State
  }

-- | Constrain function argument patterns, starting from empty state.
constrainArgs :: [Can.Pattern] -> IO Args
constrainArgs args =
  argsHelp args Pattern.emptyState

-- | Worker for argument pattern constraint generation.
--
-- Processes argument patterns right-to-left, building up a function
-- type from the argument types and accumulating pattern constraints.
argsHelp :: [Can.Pattern] -> Pattern.State -> IO Args
argsHelp args state =
  case args of
    [] ->
      do
        resultVar <- mkFlexVar
        let resultType = VarN resultVar
        return $ Args [resultVar] resultType resultType state
    pattern : otherArgs ->
      do
        argVar <- mkFlexVar
        let argType = VarN argVar

        (Args vars tipe result newState) <-
          argsHelp otherArgs
            =<< Pattern.add pattern (PNoExpectation argType) state

        return (Args (argVar : vars) (FunN argType tipe) result newState)

-- CONSTRAIN TYPED ARGS

-- | Result of constraining annotated function argument patterns.
data TypedArgs = TypedArgs
  { _t_type :: Type,
    _t_result :: Type,
    _t_state :: Pattern.State
  }

-- | Constrain annotated function arguments against their declared types.
constrainTypedArgs :: Map Name.Name Type -> Name.Name -> [(Can.Pattern, Can.Type)] -> Can.Type -> IO TypedArgs
constrainTypedArgs rtv name args srcResultType =
  typedArgsHelp rtv name Index.first args srcResultType Pattern.emptyState

-- | Worker for annotated argument constraint generation.
--
-- Each argument pattern is constrained against its declared source type,
-- instantiated into the internal type representation. Builds up the
-- function type from annotated argument types.
typedArgsHelp :: Map Name.Name Type -> Name.Name -> Index.ZeroBased -> [(Can.Pattern, Can.Type)] -> Can.Type -> Pattern.State -> IO TypedArgs
typedArgsHelp rtv name index args srcResultType state =
  case args of
    [] ->
      do
        resultType <- Instantiate.fromSrcType rtv srcResultType
        return $ TypedArgs resultType resultType state
    (pattern@(Ann.At region _), srcType) : otherArgs ->
      do
        argType <- Instantiate.fromSrcType rtv srcType
        let expected = PFromContext region (PTypedArg name index) argType

        (TypedArgs tipe resultType newState) <-
          typedArgsHelp rtv name (Index.next index) otherArgs srcResultType
            =<< Pattern.add pattern expected state

        return (TypedArgs (FunN argType tipe) resultType newState)

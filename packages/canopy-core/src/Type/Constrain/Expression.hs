-- | Expression constraint generation.
--
-- This is the top-level entry point for generating type constraints from
-- Canopy expressions. The main 'constrain' function dispatches to
-- specialized constraint generators based on the expression form.
--
-- Sub-modules handle specific expression categories:
--
-- * "Type.Constrain.Expression.Operator" - Binary operator constraints
-- * "Type.Constrain.Expression.Control" - If/case control flow constraints
-- * "Type.Constrain.Expression.Record" - Record, tuple, and shader constraints
-- * "Type.Constrain.Expression.Definition" - Definition and argument constraints
module Type.Constrain.Expression
  ( constrain,
    constrainDef,
    constrainRecursiveDefs,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Reporting.Annotation as Ann
import Reporting.Error.Type (Category (..), Context (..), Expected (..), MaybeName (..))
import qualified Reporting.Error.Type as TypeError
import qualified Type.Constrain.Expression.Control as Control
import qualified Type.Constrain.Expression.Definition as Def
import qualified Type.Constrain.Expression.Operator as Operator
import qualified Type.Constrain.Expression.Record as Record
import qualified Type.Constrain.Pattern as Pattern
import Type.Type as Type hiding (Descriptor (..))

-- | Rigid type variable mapping.
--
-- As we step past type annotations, the free type variables are added to
-- the "rigid type variables" dict. Allowing sharing of rigid variables
-- between nested type annotations.
--
-- So if you have a top-level type annotation like @(func : a -> b)@ the RTV
-- dictionary will hold variables for @a@ and @b@.
type RTV =
  Map Name.Name Type

-- | Generate type constraints for an expression.
--
-- This is the main dispatch function for expression constraint generation.
-- It pattern matches on the expression form and delegates to the appropriate
-- specialized constraint generator, either locally or in a sub-module.
constrain :: RTV -> Can.Expr -> Expected Type -> IO Constraint
constrain rtv (Ann.At region expression) expected =
  case expression of
    Can.VarLocal name ->
      return (CLocal region name expected)
    Can.VarTopLevel _ name ->
      return (CLocal region name expected)
    Can.VarKernel _ _ ->
      return CTrue
    Can.VarForeign _ name annotation ->
      return $ CForeign region name annotation expected
    Can.VarCtor _ _ name _ annotation ->
      return $ CForeign region name annotation expected
    Can.VarDebug _ name annotation ->
      return $ CForeign region name annotation expected
    Can.VarOperator op _ _ annotation ->
      return $ CForeign region op annotation expected
    Can.Str _ ->
      return $ CEqual region String Type.string expected
    Can.Chr _ ->
      return $ CEqual region Char Type.char expected
    Can.Int _ ->
      do
        var <- mkFlexNumber
        return $ exists [var] $ CEqual region TypeError.Number (VarN var) expected
    Can.Float _ ->
      return $ CEqual region Float Type.float expected
    Can.List elements ->
      constrainList rtv region elements expected
    Can.Negate expr ->
      do
        numberVar <- mkFlexNumber
        let numberType = VarN numberVar
        numberCon <- constrain rtv expr (FromContext region Negate numberType)
        let negateCon = CEqual region TypeError.Number numberType expected
        return $ exists [numberVar] $ CAnd [numberCon, negateCon]
    Can.BinopOp kind annotation leftExpr rightExpr ->
      Operator.constrainBinopOp (constrain rtv) region kind annotation leftExpr rightExpr expected
    Can.Lambda args body ->
      constrainLambda rtv region args body expected
    Can.Call func args ->
      constrainCall rtv region func args expected
    Can.If branches finally ->
      Control.constrainIf (constrain rtv) region branches finally expected
    Can.Case expr branches ->
      Control.constrainCase (constrain rtv) region expr branches expected
    Can.Let def body ->
      constrain rtv body expected >>= \bodyCon ->
        constrainDef rtv def bodyCon expected
    Can.LetRec defs body ->
      constrainRecursiveDefs rtv defs
        =<< constrain rtv body expected
    Can.LetDestruct pattern expr body ->
      Def.constrainDestruct (constrain rtv) rtv region pattern expr
        =<< constrain rtv body expected
    Can.Accessor field ->
      do
        extVar <- mkFlexVar
        fieldVar <- mkFlexVar
        let extType = VarN extVar
        let fieldType = VarN fieldVar
        let recordType = RecordN (Map.singleton field fieldType) extType
        return $
          exists [fieldVar, extVar] $
            CEqual region (Accessor field) (FunN recordType fieldType) expected
    Can.Access expr (Ann.At accessRegion field) ->
      do
        extVar <- mkFlexVar
        fieldVar <- mkFlexVar
        let extType = VarN extVar
        let fieldType = VarN fieldVar
        let recordType = RecordN (Map.singleton field fieldType) extType

        let context = RecordAccess (Ann.toRegion expr) (getAccessName expr) accessRegion field
        recordCon <- constrain rtv expr (FromContext region context recordType)

        return $
          exists [fieldVar, extVar] $
            CAnd
              [ recordCon,
                CEqual region (Access field) fieldType expected
              ]
    Can.Update name expr fields ->
      Record.constrainUpdate (constrain rtv) region name expr fields expected
    Can.Record fields ->
      Record.constrainRecord (constrain rtv) region fields expected
    Can.Unit ->
      return $ CEqual region Unit UnitN expected
    Can.Tuple a b maybeC ->
      Record.constrainTuple (constrain rtv) region a b maybeC expected
    Can.Shader _src types ->
      Record.constrainShader region types expected
    Can.StringConcat parts ->
      constrainStringConcat rtv region parts expected

-- CONSTRAIN LAMBDA

constrainLambda :: RTV -> Ann.Region -> [Can.Pattern] -> Can.Expr -> Expected Type -> IO Constraint
constrainLambda rtv region args body expected =
  do
    (Def.Args vars tipe resultType (Pattern.State headers pvars revCons)) <-
      Def.constrainArgs args

    bodyCon <-
      constrain rtv body (NoExpectation resultType)

    return $
      exists vars $
        CAnd
          [ CLet
              { _rigidVars = [],
                _flexVars = pvars,
                _header = headers,
                _headerCon = CAnd (reverse revCons),
                _bodyCon = bodyCon,
                _expectedType = Nothing
              },
            CEqual region Lambda tipe expected
          ]

-- CONSTRAIN CALL

constrainCall :: RTV -> Ann.Region -> Can.Expr -> [Can.Expr] -> Expected Type -> IO Constraint
constrainCall rtv region func@(Ann.At funcRegion _) args expected =
  do
    let maybeName = getName func

    funcVar <- mkFlexVar
    resultVar <- mkFlexVar
    let funcType = VarN funcVar
    let resultType = VarN resultVar

    funcCon <- constrain rtv func (NoExpectation funcType)

    (argVars, argTypes, argCons) <-
      unzip3 <$> Index.indexedTraverse (constrainArg rtv region maybeName) args

    let arityType = foldr FunN resultType argTypes
    let category = CallResult maybeName

    return $
      exists (funcVar : resultVar : argVars) $
        CAnd
          [ funcCon,
            CEqual funcRegion category funcType (FromContext region (CallArity maybeName (length args)) arityType),
            CAnd argCons,
            CEqual region category resultType expected
          ]

constrainArg :: RTV -> Ann.Region -> MaybeName -> Index.ZeroBased -> Can.Expr -> IO (Variable, Type, Constraint)
constrainArg rtv region maybeName index arg =
  do
    argVar <- mkFlexVar
    let argType = VarN argVar
    argCon <- constrain rtv arg (FromContext region (CallArg maybeName index) argType)
    return (argVar, argType, argCon)

getName :: Can.Expr -> MaybeName
getName (Ann.At _ expr) =
  case expr of
    Can.VarLocal name -> FuncName name
    Can.VarTopLevel _ name -> FuncName name
    Can.VarForeign _ name _ -> FuncName name
    Can.VarCtor _ _ name _ _ -> CtorName name
    Can.VarOperator op _ _ _ -> OpName op
    Can.VarKernel _ name -> FuncName name
    _ -> NoName

getAccessName :: Can.Expr -> Maybe Name.Name
getAccessName (Ann.At _ expr) =
  case expr of
    Can.VarLocal name -> Just name
    Can.VarTopLevel _ name -> Just name
    Can.VarForeign _ name _ -> Just name
    _ -> Nothing

-- CONSTRAIN LISTS

constrainList :: RTV -> Ann.Region -> [Can.Expr] -> Expected Type -> IO Constraint
constrainList rtv region entries expected =
  do
    entryVar <- mkFlexVar
    let entryType = VarN entryVar
    let listType = AppN ModuleName.list Name.list [entryType]

    entryCons <-
      Index.indexedTraverse (constrainListEntry rtv region entryType) entries

    return $
      exists [entryVar] $
        CAnd
          [ CAnd entryCons,
            CEqual region List listType expected
          ]

constrainListEntry :: RTV -> Ann.Region -> Type -> Index.ZeroBased -> Can.Expr -> IO Constraint
constrainListEntry rtv region tipe index expr =
  constrain rtv expr (FromContext region (ListEntry index) tipe)

-- CONSTRAIN STRING CONCAT

constrainStringConcat :: RTV -> Ann.Region -> [Can.Expr] -> Expected Type -> IO Constraint
constrainStringConcat rtv region parts expected =
  do
    partCons <-
      Index.indexedTraverse (constrainStringPart rtv region) parts
    return $
      CAnd
        [ CAnd partCons,
          CEqual region String Type.string expected
        ]

constrainStringPart :: RTV -> Ann.Region -> Index.ZeroBased -> Can.Expr -> IO Constraint
constrainStringPart rtv region index expr =
  constrain rtv expr (FromContext region (Interpolation index) Type.string)

-- CONSTRAIN DEF (public API delegates to Definition sub-module)

-- | Generate type constraints for a value definition.
constrainDef :: RTV -> Can.Def -> Constraint -> Expected Type -> IO Constraint
constrainDef rtv def bodyCon expected =
  Def.constrainDef (constrain rtv) rtv def bodyCon expected

-- CONSTRAIN RECURSIVE DEFS (public API delegates to Definition sub-module)

-- | Generate type constraints for a mutually recursive definition group.
constrainRecursiveDefs :: RTV -> [Can.Def] -> Constraint -> IO Constraint
constrainRecursiveDefs rtv defs bodyCon =
  Def.constrainRecursiveDefs (constrain rtv) rtv defs bodyCon

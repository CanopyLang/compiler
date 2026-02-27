-- | Record, tuple, and shader constraint generation.
--
-- This module handles type constraint generation for record construction,
-- record field access, record updates, tuple construction, and WebGL
-- shader types. These constructs all involve structured types with
-- named or positional fields.
--
-- Record types use row polymorphism via an extension type variable,
-- allowing open record types in field access and update operations.
-- Shader types map GLSL types to their Canopy equivalents.
module Type.Constrain.Expression.Record
  ( constrainRecord,
    constrainField,
    constrainUpdate,
    constrainUpdateField,
    constrainTuple,
    constrainShader,
    toShaderRecord,
    glToType,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Utils.Shader as Shader
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Reporting.Annotation (Region)
import Reporting.Error.Type (Category (..), Context (..), Expected (..))
import Type.Type as Type hiding (Descriptor (..))

-- | Constrain function type, passed in to avoid circular module dependencies.
type Constrain = Can.Expr -> Expected Type -> IO Constraint

-- | Generate type constraints for record construction.
--
-- Each field expression is constrained to a fresh type variable, and
-- the overall record type is constructed from the field types with
-- an empty extension (closed record).
constrainRecord :: Constrain -> Region -> Map Name.Name Can.Expr -> Expected Type -> IO Constraint
constrainRecord doConstrain region fields expected =
  do
    dict <- traverse (constrainField doConstrain) fields

    let getType (_, t, _) = t
    let recordType = RecordN (Map.map getType dict) EmptyRecordN
    let recordCon = CEqual region Record recordType expected

    let vars = Map.foldr (\(v, _, _) vs -> v : vs) [] dict
    let cons = Map.foldr (\(_, _, c) cs -> c : cs) [recordCon] dict

    return $ exists vars (CAnd cons)

-- | Constrain a single record field expression to a fresh type variable.
constrainField :: Constrain -> Can.Expr -> IO (Variable, Type, Constraint)
constrainField doConstrain expr =
  do
    var <- mkFlexVar
    let tipe = VarN var
    con <- doConstrain expr (NoExpectation tipe)
    return (var, tipe, con)

-- | Generate type constraints for record update expressions.
--
-- The original record expression is constrained to a record type containing
-- all updated fields. Each updated field value is constrained independently.
-- The result type matches the original record type.
constrainUpdate :: Constrain -> Region -> Name.Name -> Can.Expr -> Map Name.Name Can.FieldUpdate -> Expected Type -> IO Constraint
constrainUpdate doConstrain region name expr fields expected =
  do
    extVar <- mkFlexVar
    fieldDict <- Map.traverseWithKey (constrainUpdateField doConstrain region) fields

    recordVar <- mkFlexVar
    let recordType = VarN recordVar
    let fieldsType = RecordN (Map.map (\(_, t, _) -> t) fieldDict) (VarN extVar)

    let fieldsCon = CEqual region Record recordType (NoExpectation fieldsType)
    let recordCon = CEqual region Record recordType expected

    let vars = Map.foldr (\(v, _, _) vs -> v : vs) [recordVar, extVar] fieldDict
    let cons = Map.foldr (\(_, _, c) cs -> c : cs) [recordCon] fieldDict

    con <- doConstrain expr (FromContext region (RecordUpdateKeys name fields) recordType)

    return $ exists vars $ CAnd (fieldsCon : con : cons)

-- | Constrain a single record update field value.
constrainUpdateField :: Constrain -> Region -> Name.Name -> Can.FieldUpdate -> IO (Variable, Type, Constraint)
constrainUpdateField doConstrain region field (Can.FieldUpdate _ expr) =
  do
    var <- mkFlexVar
    let tipe = VarN var
    con <- doConstrain expr (FromContext region (RecordUpdateValue field) tipe)
    return (var, tipe, con)

-- | Generate type constraints for tuple construction.
--
-- Two-element and three-element tuples are supported. Each element
-- is constrained to a fresh type variable, and the overall tuple type
-- is constructed from those variables.
constrainTuple :: Constrain -> Region -> Can.Expr -> Can.Expr -> Maybe Can.Expr -> Expected Type -> IO Constraint
constrainTuple doConstrain region a b maybeC expected =
  do
    aVar <- mkFlexVar
    bVar <- mkFlexVar
    let aType = VarN aVar
    let bType = VarN bVar

    aCon <- doConstrain a (NoExpectation aType)
    bCon <- doConstrain b (NoExpectation bType)

    case maybeC of
      Nothing ->
        do
          let tupleType = TupleN aType bType Nothing
          let tupleCon = CEqual region Tuple tupleType expected
          return $ exists [aVar, bVar] $ CAnd [aCon, bCon, tupleCon]
      Just c ->
        do
          cVar <- mkFlexVar
          let cType = VarN cVar

          cCon <- doConstrain c (NoExpectation cType)

          let tupleType = TupleN aType bType (Just cType)
          let tupleCon = CEqual region Tuple tupleType expected

          return $ exists [aVar, bVar, cVar] $ CAnd [aCon, bCon, cCon, tupleCon]

-- | Generate type constraints for a WebGL shader expression.
--
-- Maps GLSL attribute, uniform, and varying types to their Canopy
-- equivalents and constructs the @Shader@ type with three record
-- type parameters.
constrainShader :: Region -> Shader.Types -> Expected Type -> IO Constraint
constrainShader region (Shader.Types attributes uniforms varyings) expected =
  do
    attrVar <- mkFlexVar
    unifVar <- mkFlexVar
    let attrType = VarN attrVar
    let unifType = VarN unifVar

    let shaderType =
          AppN
            ModuleName.webgl
            Name.shader
            [ toShaderRecord attributes attrType,
              toShaderRecord uniforms unifType,
              toShaderRecord varyings EmptyRecordN
            ]

    return $
      exists [attrVar, unifVar] $
        CEqual region Shader shaderType expected

-- | Build a record type from a map of GLSL typed fields.
--
-- If the field map is empty, returns the base record type unchanged.
-- Otherwise wraps the fields in a 'RecordN' with the given extension.
toShaderRecord :: Map Name.Name Shader.Type -> Type -> Type
toShaderRecord types baseRecType =
  if Map.null types
    then baseRecType
    else RecordN (Map.map glToType types) baseRecType

-- | Convert a GLSL type to its corresponding Canopy type.
glToType :: Shader.Type -> Type
glToType glType =
  case glType of
    Shader.V2 -> Type.vec2
    Shader.V3 -> Type.vec3
    Shader.V4 -> Type.vec4
    Shader.M4 -> Type.mat4
    Shader.Int -> Type.int
    Shader.Float -> Type.float
    Shader.Texture -> Type.texture

{-# LANGUAGE OverloadedStrings #-}

module Canonicalize.Effects
  ( canonicalize,
    checkPayload,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified AST.Utils.Type as Type
import qualified Canonicalize.Environment as Env
import qualified Canonicalize.Type as Type
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Foldable as Foldable
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result

-- RESULT

type Result i w a =
  Result.Result i w Error.Error a

-- CANONICALIZE

canonicalize ::
  Env.Env ->
  [Ann.Located Src.Value] ->
  Map Name.Name union ->
  Src.Effects ->
  Result i w Can.Effects
canonicalize env values unions effects =
  case effects of
    Src.NoEffects ->
      Result.ok Can.NoEffects
    Src.Ports ports ->
      do
        pairs <- traverse (canonicalizePort env) ports
        return $ Can.Ports (Map.fromList pairs)
    Src.FFI _ ->
      Result.ok Can.FFI
    Src.Manager region manager ->
      let dict = Map.fromList (fmap toNameRegion values)
       in Can.Manager
            <$> verifyManager region dict "init"
            <*> verifyManager region dict "onEffects"
            <*> verifyManager region dict "onSelfMsg"
            <*> case manager of
              Src.Cmd cmdType ->
                Can.Cmd
                  <$> verifyEffectType cmdType unions
                  <* verifyManager region dict "cmdMap"
              Src.Sub subType ->
                Can.SubManager
                  <$> verifyEffectType subType unions
                  <* verifyManager region dict "subMap"
              Src.Fx cmdType subType ->
                Can.Fx
                  <$> verifyEffectType cmdType unions
                  <*> verifyEffectType subType unions
                  <* verifyManager region dict "cmdMap"
                  <* verifyManager region dict "subMap"

-- CANONICALIZE PORT

canonicalizePort :: Env.Env -> Src.Port -> Result i w (Name.Name, Can.Port)
canonicalizePort env (Src.Port (Ann.At region portName) tipe) =
  do
    (Can.Forall freeVars ctipe) <- Type.toAnnotation env tipe
    case reverse (Type.delambda (Type.deepDealias ctipe)) of
      Can.TType home name [msg] : revArgs
        | home == ModuleName.cmd && name == Name.cmd ->
          canonicalizeCmdPort region portName freeVars ctipe msg revArgs
        | home == ModuleName.sub && name == Name.sub ->
          canonicalizeSubPort region portName freeVars ctipe msg revArgs
      _ ->
        Result.throw (Error.PortTypeInvalid region portName Error.NotCmdOrSub)

-- | Canonicalize an outgoing command port.
--
-- Validates that the command port has exactly one argument, the message
-- type is a type variable, and the payload type is valid for port
-- communication.
--
-- @since 0.19.2
canonicalizeCmdPort ::
  Ann.Region ->
  Name.Name ->
  Map Name.Name () ->
  Can.Type ->
  Can.Type ->
  [Can.Type] ->
  Result i w (Name.Name, Can.Port)
canonicalizeCmdPort region portName freeVars ctipe msg revArgs =
  case revArgs of
    [] ->
      Result.throw (Error.PortTypeInvalid region portName Error.CmdNoArg)
    [outgoingType] ->
      validateCmdPayload region portName freeVars ctipe msg outgoingType
    _ ->
      Result.throw (Error.PortTypeInvalid region portName (Error.CmdExtraArgs (length revArgs)))

-- | Validate the payload of a command port.
--
-- @since 0.19.2
validateCmdPayload ::
  Ann.Region ->
  Name.Name ->
  Map Name.Name () ->
  Can.Type ->
  Can.Type ->
  Can.Type ->
  Result i w (Name.Name, Can.Port)
validateCmdPayload region portName freeVars ctipe msg outgoingType =
  case msg of
    Can.TVar _ ->
      either
        (\(badType, err) -> Result.throw (Error.PortPayloadInvalid region portName badType err))
        (\() -> Result.ok (portName, Can.Outgoing freeVars outgoingType ctipe))
        (checkPayload outgoingType)
    _ ->
      Result.throw (Error.PortTypeInvalid region portName Error.CmdBadMsg)

-- | Canonicalize an incoming subscription port.
--
-- Validates that the subscription port has the correct shape
-- @(payload -> msg) -> Sub msg@ and the payload type is valid
-- for port communication.
--
-- @since 0.19.2
canonicalizeSubPort ::
  Ann.Region ->
  Name.Name ->
  Map Name.Name () ->
  Can.Type ->
  Can.Type ->
  [Can.Type] ->
  Result i w (Name.Name, Can.Port)
canonicalizeSubPort region portName freeVars _ctipe msg revArgs =
  case revArgs of
    [Can.TLambda incomingType (Can.TVar msg1)] ->
      validateSubPayload region portName freeVars incomingType _ctipe msg msg1
    _ ->
      Result.throw (Error.PortTypeInvalid region portName Error.SubBad)

-- | Validate the payload of a subscription port.
--
-- @since 0.19.2
validateSubPayload ::
  Ann.Region ->
  Name.Name ->
  Map Name.Name () ->
  Can.Type ->
  Can.Type ->
  Can.Type ->
  Name.Name ->
  Result i w (Name.Name, Can.Port)
validateSubPayload region portName freeVars incomingType ctipe msg msg1 =
  case msg of
    Can.TVar msg2 | msg1 == msg2 ->
      either
        (\(badType, err) -> Result.throw (Error.PortPayloadInvalid region portName badType err))
        (\() -> Result.ok (portName, Can.Incoming freeVars incomingType ctipe))
        (checkPayload incomingType)
    _ ->
      Result.throw (Error.PortTypeInvalid region portName Error.SubBad)

-- VERIFY MANAGER

verifyEffectType :: Ann.Located Name.Name -> Map Name.Name a -> Result i w Name.Name
verifyEffectType (Ann.At region name) unions =
  if Map.member name unions
    then Result.ok name
    else Result.throw (Error.EffectNotFound region name)

toNameRegion :: Ann.Located Src.Value -> (Name.Name, Ann.Region)
toNameRegion (Ann.At _ (Src.Value (Ann.At region name) _ _ _)) =
  (name, region)

verifyManager :: Ann.Region -> Map Name.Name Ann.Region -> Name.Name -> Result i w Ann.Region
verifyManager tagRegion values name =
  case Map.lookup name values of
    Just region ->
      Result.ok region
    Nothing ->
      Result.throw (Error.EffectFunctionNotFound tagRegion name)

-- CHECK PAYLOAD TYPES

checkPayload :: Can.Type -> Either (Can.Type, Error.InvalidPayload) ()
checkPayload tipe =
  case tipe of
    Can.TAlias _ _ args aliasedType ->
      checkPayload (Type.dealias args aliasedType)
    Can.TType home name args ->
      case args of
        []
          | isJson home name -> Right ()
          | isString home name -> Right ()
          | isIntFloatBool home name -> Right ()
        [arg]
          | isList home name -> checkPayload arg
          | isMaybe home name -> checkPayload arg
          | isArray home name -> checkPayload arg
        _ ->
          Left (tipe, Error.UnsupportedType name)
    Can.TUnit ->
      Right ()
    Can.TTuple a b maybeC ->
      do
        checkPayload a
        checkPayload b
        case maybeC of
          Nothing ->
            Right ()
          Just c ->
            checkPayload c
    Can.TVar name ->
      Left (tipe, Error.TypeVariable name)
    Can.TLambda _ _ ->
      Left (tipe, Error.Function)
    Can.TRecord _ (Just _) ->
      Left (tipe, Error.ExtendedRecord)
    Can.TRecord fields Nothing ->
      Foldable.traverse_ checkFieldPayload fields

checkFieldPayload :: Can.FieldType -> Either (Can.Type, Error.InvalidPayload) ()
checkFieldPayload (Can.FieldType _ tipe) =
  checkPayload tipe

isIntFloatBool :: ModuleName.Canonical -> Name.Name -> Bool
isIntFloatBool home name =
  home == ModuleName.basics
    && (name == Name.int || name == Name.float || name == Name.bool)

isString :: ModuleName.Canonical -> Name.Name -> Bool
isString home name =
  home == ModuleName.string
    && name == Name.string

isJson :: ModuleName.Canonical -> Name.Name -> Bool
isJson home name =
  home == ModuleName.jsonEncode
    && name == Name.value

isList :: ModuleName.Canonical -> Name.Name -> Bool
isList home name =
  home == ModuleName.list
    && name == Name.list

isMaybe :: ModuleName.Canonical -> Name.Name -> Bool
isMaybe home name =
  home == ModuleName.maybe
    && name == Name.maybe

isArray :: ModuleName.Canonical -> Name.Name -> Bool
isArray home name =
  home == ModuleName.array
    && name == Name.array

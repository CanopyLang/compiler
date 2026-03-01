{-# LANGUAGE OverloadedStrings #-}

module Type.Instantiate
  ( FreeVars,
    fromSrcType,
  )
where

import qualified AST.Canonical as Can
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Data.Text as Text
import qualified Reporting.InternalError as InternalError
import Type.Type

-- FREE VARS

type FreeVars =
  Map Name.Name Type

-- FROM SOURCE TYPE

fromSrcType :: Map Name.Name Type -> Can.Type -> IO Type
fromSrcType freeVars sourceType =
  case sourceType of
    Can.TLambda arg result ->
      FunN
        <$> fromSrcType freeVars arg
        <*> fromSrcType freeVars result
    Can.TVar name ->
      maybe
        (InternalError.report "Type.Instantiate.fromSrcType" ("Free type variable not found: " <> Text.pack (show name)) "All type variables referenced in a type must be bound in the freeVars map at the point of instantiation.")
        return
        (Map.lookup name freeVars)
    Can.TType home name args ->
      AppN home name <$> traverse (fromSrcType freeVars) args
    Can.TAlias home name args aliasedType ->
      do
        targs <- traverse (traverse (fromSrcType freeVars)) args
        AliasN home name targs
          <$> case aliasedType of
            Can.Filled realType ->
              fromSrcType freeVars realType
            Can.Holey realType ->
              fromSrcType (Map.fromList targs) realType
    Can.TTuple a b maybeC ->
      TupleN
        <$> fromSrcType freeVars a
        <*> fromSrcType freeVars b
        <*> traverse (fromSrcType freeVars) maybeC
    Can.TUnit ->
      return UnitN
    Can.TRecord fields maybeExt ->
      RecordN
        <$> traverse (fromSrcFieldType freeVars) fields
        <*> case maybeExt of
          Nothing ->
            return EmptyRecordN
          Just ext ->
            maybe
              (InternalError.report "Type.Instantiate.fromSrcType" ("Extension variable not found: " <> Text.pack (show ext)) "All record extension variables must be bound in the freeVars map at the point of instantiation.")
              return
              (Map.lookup ext freeVars)

fromSrcFieldType :: Map.Map Name.Name Type -> Can.FieldType -> IO Type
fromSrcFieldType freeVars (Can.FieldType _ tipe) =
  fromSrcType freeVars tipe

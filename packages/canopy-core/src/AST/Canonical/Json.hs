{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | AST.Canonical.Json - Aeson JSON instances for Canonical AST types
--
-- This module provides 'ToJSON' and 'FromJSON' instances for Canonical AST
-- types that require JSON serialization. These instances are used for the
-- compiler's JSON-based diagnostic output, language server protocol
-- communication, and debugging tools.
--
-- The JSON encoding uses descriptive tag-based object representations
-- for readability and forward compatibility.
--
-- This module is imported by "AST.Canonical" to ensure instances are always
-- available. External code should not need to import this module directly.
--
-- @since 0.19.1
module AST.Canonical.Json () where

import AST.Canonical.Types
  ( Alias (..),
    AliasType (..),
    Annotation (..),
    Ctor (..),
    CtorOpts (..),
    FieldType (..),
    GuardInfo (..),
    SupertypeBound (..),
    Type (..),
    Union (..),
  )
import qualified Data.Aeson as Aeson
import Data.Aeson.Types (Parser)

instance Aeson.ToJSON CtorOpts where
  toJSON opts = Aeson.String $
    case opts of
      Normal -> "normal"
      Enum -> "enum"
      Unbox -> "unbox"

instance Aeson.FromJSON CtorOpts where
  parseJSON = Aeson.withText "CtorOpts" $ \txt ->
    case txt of
      "normal" -> pure Normal
      "enum" -> pure Enum
      "unbox" -> pure Unbox
      _ -> fail ("Unknown CtorOpts: " ++ show txt)

instance Aeson.ToJSON Ctor where
  toJSON (Ctor name idx numArgs types) =
    Aeson.object
      [ "name" Aeson..= name,
        "index" Aeson..= idx,
        "numArgs" Aeson..= numArgs,
        "types" Aeson..= types
      ]

instance Aeson.FromJSON Ctor where
  parseJSON = Aeson.withObject "Ctor" $ \o ->
    Ctor
      <$> o Aeson..: "name"
      <*> o Aeson..: "index"
      <*> o Aeson..: "numArgs"
      <*> o Aeson..: "types"

instance Aeson.ToJSON SupertypeBound where
  toJSON bound = Aeson.String $ case bound of
    ComparableBound -> "comparable"
    AppendableBound -> "appendable"
    NumberBound -> "number"
    CompAppendBound -> "compappend"

instance Aeson.FromJSON SupertypeBound where
  parseJSON = Aeson.withText "SupertypeBound" $ \txt ->
    case txt of
      "comparable" -> pure ComparableBound
      "appendable" -> pure AppendableBound
      "number" -> pure NumberBound
      "compappend" -> pure CompAppendBound
      _ -> fail ("Unknown SupertypeBound: " ++ show txt)

instance Aeson.ToJSON Alias where
  toJSON (Alias vars tipe bound) =
    Aeson.object
      [ "vars" Aeson..= vars,
        "type" Aeson..= tipe,
        "bound" Aeson..= bound
      ]

instance Aeson.FromJSON Alias where
  parseJSON = Aeson.withObject "Alias" $ \o ->
    Alias
      <$> o Aeson..: "vars"
      <*> o Aeson..: "type"
      <*> o Aeson..:? "bound"

instance Aeson.ToJSON Union where
  toJSON (Union vars alts numAlts opts) =
    Aeson.object
      [ "vars" Aeson..= vars,
        "alts" Aeson..= alts,
        "numAlts" Aeson..= numAlts,
        "opts" Aeson..= opts
      ]

instance Aeson.FromJSON Union where
  parseJSON = Aeson.withObject "Union" $ \o ->
    Union
      <$> o Aeson..: "vars"
      <*> o Aeson..: "alts"
      <*> o Aeson..: "numAlts"
      <*> o Aeson..: "opts"

instance Aeson.ToJSON Annotation where
  toJSON (Forall freeVars tipe) =
    Aeson.object
      [ "freeVars" Aeson..= freeVars,
        "type" Aeson..= tipe
      ]

instance Aeson.FromJSON Annotation where
  parseJSON = Aeson.withObject "Annotation" $ \o ->
    Forall
      <$> o Aeson..: "freeVars"
      <*> o Aeson..: "type"

instance Aeson.ToJSON AliasType where
  toJSON aliasType = case aliasType of
    Holey tipe ->
      Aeson.object
        [ "tag" Aeson..= ("holey" :: String),
          "type" Aeson..= tipe
        ]
    Filled tipe ->
      Aeson.object
        [ "tag" Aeson..= ("filled" :: String),
          "type" Aeson..= tipe
        ]

instance Aeson.FromJSON AliasType where
  parseJSON = Aeson.withObject "AliasType" $ \o -> do
    tag <- o Aeson..: "tag" :: Parser String
    tipe <- o Aeson..: "type"
    case tag of
      "holey" -> pure (Holey tipe)
      "filled" -> pure (Filled tipe)
      _ -> fail ("Unknown AliasType tag: " ++ tag)

instance Aeson.ToJSON FieldType where
  toJSON (FieldType idx tipe) =
    Aeson.object
      [ "index" Aeson..= idx,
        "type" Aeson..= tipe
      ]

instance Aeson.FromJSON FieldType where
  parseJSON = Aeson.withObject "FieldType" $ \o ->
    FieldType
      <$> o Aeson..: "index"
      <*> o Aeson..: "type"

instance Aeson.ToJSON Type where
  toJSON tipe = case tipe of
    TLambda a b ->
      Aeson.object
        [ "tag" Aeson..= ("lambda" :: String),
          "arg" Aeson..= a,
          "result" Aeson..= b
        ]
    TVar name ->
      Aeson.object
        [ "tag" Aeson..= ("var" :: String),
          "name" Aeson..= name
        ]
    TType moduleName typeName args ->
      Aeson.object
        [ "tag" Aeson..= ("type" :: String),
          "module" Aeson..= moduleName,
          "name" Aeson..= typeName,
          "args" Aeson..= args
        ]
    TRecord fields ext ->
      Aeson.object
        [ "tag" Aeson..= ("record" :: String),
          "fields" Aeson..= fields,
          "extension" Aeson..= ext
        ]
    TUnit ->
      Aeson.object
        [ "tag" Aeson..= ("unit" :: String)
        ]
    TTuple a b c ->
      Aeson.object
        [ "tag" Aeson..= ("tuple" :: String),
          "first" Aeson..= a,
          "second" Aeson..= b,
          "third" Aeson..= c
        ]
    TAlias moduleName typeName args aliasType ->
      Aeson.object
        [ "tag" Aeson..= ("alias" :: String),
          "module" Aeson..= moduleName,
          "name" Aeson..= typeName,
          "args" Aeson..= args,
          "aliasType" Aeson..= aliasType
        ]

instance Aeson.FromJSON Type where
  parseJSON = Aeson.withObject "Type" $ \o -> do
    tag <- o Aeson..: "tag" :: Parser String
    case tag of
      "lambda" ->
        TLambda
          <$> o Aeson..: "arg"
          <*> o Aeson..: "result"
      "var" ->
        TVar <$> o Aeson..: "name"
      "type" ->
        TType
          <$> o Aeson..: "module"
          <*> o Aeson..: "name"
          <*> o Aeson..: "args"
      "record" ->
        TRecord
          <$> o Aeson..: "fields"
          <*> o Aeson..: "extension"
      "unit" ->
        pure TUnit
      "tuple" ->
        TTuple
          <$> o Aeson..: "first"
          <*> o Aeson..: "second"
          <*> o Aeson..: "third"
      "alias" ->
        TAlias
          <$> o Aeson..: "module"
          <*> o Aeson..: "name"
          <*> o Aeson..: "args"
          <*> o Aeson..: "aliasType"
      _ -> fail ("Unknown Type tag: " ++ tag)

instance Aeson.ToJSON GuardInfo where
  toJSON (GuardInfo argIndex narrowType) =
    Aeson.object
      [ "argIndex" Aeson..= argIndex,
        "narrowType" Aeson..= narrowType
      ]

instance Aeson.FromJSON GuardInfo where
  parseJSON = Aeson.withObject "GuardInfo" $ \o ->
    GuardInfo
      <$> o Aeson..: "argIndex"
      <*> o Aeson..: "narrowType"

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | AST.Canonical.Binary - Binary serialization instances for Canonical AST types
--
-- This module provides 'Binary' instances for all Canonical AST types that
-- require serialization. These instances are used for writing and reading
-- module interface files (.elci) and compilation caches (.elco).
--
-- The serialization format uses compact tag-based encoding with optimizations
-- for common cases (e.g., small type argument lists in 'TType').
--
-- This module is imported by "AST.Canonical" to ensure instances are always
-- available. External code should not need to import this module directly.
--
-- @since 0.19.1
module AST.Canonical.Binary () where

import AST.Canonical.Types
  ( Alias (..),
    AliasType (..),
    Annotation (..),
    ArithOp (..),
    BinopKind (..),
    Ctor (..),
    CtorOpts (..),
    FieldType (..),
    GuardInfo (..),
    SupertypeBound (..),
    Type (..),
    Union (..),
    Variance (..),
  )
import Canopy.Data.Name (Name)
import qualified Canopy.ModuleName as ModuleName
import qualified Control.Monad as Monad
import qualified Data.Binary as Binary
import qualified Data.Foldable as Foldable
import Data.Word (Word8)
import qualified Reporting.InternalError as InternalError

instance Binary.Binary SupertypeBound where
  put bound =
    Binary.putWord8 $ case bound of
      ComparableBound -> 0
      AppendableBound -> 1
      NumberBound -> 2
      CompAppendBound -> 3
  get = do
    tag <- Binary.getWord8
    case tag of
      0 -> pure ComparableBound
      1 -> pure AppendableBound
      2 -> pure NumberBound
      3 -> pure CompAppendBound
      _ -> fail ("SupertypeBound: unexpected tag " ++ show tag ++ " (expected 0-3). Delete canopy-stuff/ to rebuild.")

instance Binary.Binary Variance where
  put variance =
    Binary.putWord8 $ case variance of
      Covariant -> 0
      Contravariant -> 1
      Invariant -> 2
  get = do
    tag <- Binary.getWord8
    case tag of
      0 -> pure Covariant
      1 -> pure Contravariant
      2 -> pure Invariant
      _ -> fail ("Variance: unexpected tag " ++ show tag ++ " (expected 0-2). Delete canopy-stuff/ to rebuild.")

instance Binary.Binary Alias where
  get = Monad.liftM4 Alias Binary.get Binary.get Binary.get Binary.get
  put (Alias a b c d) = Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d

instance Binary.Binary Union where
  put (Union a b c d e) = Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d >> Binary.put e
  get = Monad.liftM5 Union Binary.get Binary.get Binary.get Binary.get Binary.get

instance Binary.Binary Ctor where
  get = Monad.liftM4 Ctor Binary.get Binary.get Binary.get Binary.get
  put (Ctor a b c d) = Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d

instance Binary.Binary CtorOpts where
  put opts =
    case opts of
      Normal -> Binary.putWord8 0
      Enum -> Binary.putWord8 1
      Unbox -> Binary.putWord8 2

  get =
    do
      n <- Binary.getWord8
      case n of
        0 -> return Normal
        1 -> return Enum
        2 -> return Unbox
        _ -> fail ("CtorOpts: unexpected tag " ++ show n ++ " (expected 0-2). Delete canopy-stuff/ to rebuild.")

instance Binary.Binary Annotation where
  get = Monad.liftM2 Forall Binary.get Binary.get
  put (Forall a b) = Binary.put a >> Binary.put b

instance Binary.Binary GuardInfo where
  get = Monad.liftM2 GuardInfo Binary.get Binary.get
  put (GuardInfo a b) = Binary.put a >> Binary.put b

instance Binary.Binary Type where
  put = putType
  get = getType

-- | Serialize a type to binary format.
--
-- Efficiently serializes canonical types to binary representation for
-- module interface files and compilation caching.
--
-- @since 0.19.1
putType :: Type -> Binary.Put
putType tipe = case tipe of
  TLambda a b -> Binary.putWord8 0 >> Binary.put a >> Binary.put b
  TVar a -> Binary.putWord8 1 >> Binary.put a
  TRecord a b -> Binary.putWord8 2 >> Binary.put a >> Binary.put b
  TUnit -> Binary.putWord8 3
  _ -> putTypeComplex tipe

-- | Serialize complex types to binary format.
--
-- Handles serialization of complex type constructs like tuples,
-- aliases, and parameterized types.
--
-- @since 0.19.1
putTypeComplex :: Type -> Binary.Put
putTypeComplex tipe = case tipe of
  TTuple a b c -> Binary.putWord8 4 >> Binary.put a >> Binary.put b >> Binary.put c
  TAlias a b c d -> Binary.putWord8 5 >> Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d
  TType home name ts -> putTType home name ts
  _ -> InternalError.report
    "AST.Canonical.Binary.putTypeComplex"
    "unexpected type in putTypeComplex"
    "putTypeComplex only handles TTuple, TAlias, and TType. Other type constructors (TLambda, TVar, TRecord, TUnit) must be serialized by their own Binary.put paths."

-- | Serialize TType with optimization for small type lists.
--
-- Uses an optimization for type applications with few arguments
-- to reduce serialization overhead in common cases.
--
-- @since 0.19.1
putTType :: ModuleName.Canonical -> Name -> [Type] -> Binary.Put
putTType home name ts =
  if potentialWord <= fromIntegral (maxBound :: Word8)
    then do
      Binary.putWord8 (fromIntegral potentialWord)
      Binary.put home
      Binary.put name
      Foldable.traverse_ Binary.put ts
    else Binary.putWord8 6 >> Binary.put home >> Binary.put name >> Binary.put ts
  where
    potentialWord = length ts + 7

-- | Deserialize a type from binary format.
--
-- Efficiently deserializes canonical types from binary representation
-- with proper error handling for corrupted data.
--
-- @since 0.19.1
getType :: Binary.Get Type
getType = do
  word <- Binary.getWord8
  case word of
    n | n <= 5 -> getTypeSimple n
    6 -> Monad.liftM3 TType Binary.get Binary.get Binary.get
    n -> getTTypeOptimized n

-- | Deserialize simple types.
--
-- Handles deserialization of basic type constructs like functions,
-- variables, records, and units.
--
-- @since 0.19.1
getTypeSimple :: Word8 -> Binary.Get Type
getTypeSimple word = case word of
  0 -> Monad.liftM2 TLambda Binary.get Binary.get
  1 -> fmap TVar Binary.get
  2 -> Monad.liftM2 TRecord Binary.get Binary.get
  3 -> return TUnit
  4 -> Monad.liftM3 TTuple Binary.get Binary.get Binary.get
  5 -> Monad.liftM4 TAlias Binary.get Binary.get Binary.get Binary.get
  _ -> fail ("Can.Type: unexpected tag " ++ show word ++ " (expected 0-5). Delete canopy-stuff/ to rebuild.")

-- | Deserialize TType with optimized length encoding.
--
-- Handles the optimized encoding for type applications with
-- length information encoded in the tag byte.
--
-- @since 0.19.1
getTTypeOptimized :: Word8 -> Binary.Get Type
getTTypeOptimized n =
  Monad.liftM3 TType Binary.get Binary.get (Monad.replicateM (fromIntegral (n - 7)) Binary.get)

instance Binary.Binary AliasType where
  put aliasType =
    case aliasType of
      Holey tipe -> Binary.putWord8 0 >> Binary.put tipe
      Filled tipe -> Binary.putWord8 1 >> Binary.put tipe

  get =
    do
      n <- Binary.getWord8
      case n of
        0 -> fmap Holey Binary.get
        1 -> fmap Filled Binary.get
        _ -> fail ("AliasType: unexpected tag " ++ show n ++ " (expected 0-1). Delete canopy-stuff/ to rebuild.")

instance Binary.Binary FieldType where
  get = Monad.liftM2 FieldType Binary.get Binary.get
  put (FieldType a b) = Binary.put a >> Binary.put b

-- | Binary serialization for ArithOp.
--
-- Compact encoding using Word8 tags for efficient serialization.
--
-- @since 0.19.2
instance Binary.Binary ArithOp where
  put = putArithOp
  get = getArithOp

-- | Encode ArithOp to Word8.
--
-- Maps arithmetic operators to compact numeric tags.
--
-- @since 0.19.2
putArithOp :: ArithOp -> Binary.Put
putArithOp Add = Binary.putWord8 0
putArithOp Sub = Binary.putWord8 1
putArithOp Mul = Binary.putWord8 2
putArithOp Div = Binary.putWord8 3

-- | Decode Word8 to ArithOp.
--
-- Handles deserialization with error checking for corrupted data.
--
-- @since 0.19.2
getArithOp :: Binary.Get ArithOp
getArithOp = do
  w <- Binary.getWord8
  case w of
    0 -> pure Add
    1 -> pure Sub
    2 -> pure Mul
    3 -> pure Div
    _ -> fail ("ArithOp: unexpected tag " ++ show w ++ " (expected 0-3). Delete canopy-stuff/ to rebuild.")

-- | Binary serialization for BinopKind.
--
-- Distinguishes native arithmetic from user-defined operators
-- with efficient tag-based encoding.
--
-- @since 0.19.2
instance Binary.Binary BinopKind where
  put kind = case kind of
    NativeArith op -> Binary.putWord8 0 >> Binary.put op
    UserDefined op home name ->
      Binary.putWord8 1 >> Binary.put op >> Binary.put home >> Binary.put name

  get = do
    tag <- Binary.getWord8
    case tag of
      0 -> fmap NativeArith Binary.get
      1 -> Monad.liftM3 UserDefined Binary.get Binary.get Binary.get
      _ -> fail ("BinopKind: unexpected tag " ++ show tag ++ " (expected 0-1). Delete canopy-stuff/ to rebuild.")

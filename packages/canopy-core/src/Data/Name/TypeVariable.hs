{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Type variable name generation for the Canopy compiler.
--
-- This module provides functionality for generating unique type variable names
-- during type inference and checking. It handles:
--
-- * Generation of names from existing type variables with indices
-- * Creation of type variable names from scheme indices
-- * Smart numbering to avoid conflicts with existing names
-- * Efficient string building for type variable identifiers
--
-- Type variables are generated with specific patterns:
--
-- * Base names like "a", "b", "c" for scheme indices < 26
-- * Extended names like "a1", "b2" for higher scheme indices
-- * Index-based names like "_v0", "_v1" for var indices
-- * Conflict-avoiding names when base names end in digits
--
-- === Usage Examples
--
-- @
-- -- Generate type variables from scheme
-- let typeA = fromTypeVariableScheme 0  -- "a"
--     typeB = fromTypeVariableScheme 1  -- "b"
--     typeZ1 = fromTypeVariableScheme 26 -- "a1"
--
-- -- Generate indexed variables
-- let var0 = fromVarIndex 0  -- "_v0"
--     var1 = fromVarIndex 1  -- "_v1"
--
-- -- Generate from existing type variable
-- let baseVar = fromChars "myType"
--     indexedVar = fromTypeVariable baseVar 1  -- "myType1" or "myType_1"
-- @
--
-- @since 0.19.1
module Data.Name.TypeVariable
  ( -- * Type Variable Generation
    fromTypeVariable,
    fromTypeVariableScheme,
    fromVarIndex,
  )
where

import Data.Name.Core (Name)
import qualified Data.Utf8 as Utf8
import GHC.Exts
  ( Int (I#),
    isTrue#,
  )
import GHC.Prim
  ( MutableByteArray#,
    copyByteArray#,
    indexWord8Array#,
    leWord#,
    newByteArray#,
    sizeofByteArray#,
    unsafeFreezeByteArray#,
    word8ToWord#,
    writeWord8Array#,
    (-#),
  )
import GHC.ST (ST (ST), runST)
import GHC.Word (Word8 (W8#))

-- FROM VAR INDEX

fromVarIndex :: Int -> Name
fromVarIndex n =
  runST
    ( do
        let !size = 2 + getIndexSize n
        mba <- newByteArray size
        writeWord8 mba 0 0x5F {- _ -}
        writeWord8 mba 1 0x76 {- v -}
        writeDigitsAtEnd mba size n
        freeze mba
    )

{-# INLINE getIndexSize #-}
getIndexSize :: Int -> Int
getIndexSize n
  | n < 10 = 1
  | n < 100 = 2
  | otherwise = ceiling (logBase 10 (fromIntegral n + 1) :: Float)

writeDigitsAtEnd :: MBA s -> Int -> Int -> ST s ()
writeDigitsAtEnd !mba !oldOffset !n =
  do
    let (q, r) = quotRem n 10
    let !newOffset = oldOffset - 1
    writeWord8 mba newOffset (0x30 + fromIntegral r)
    if q <= 0
      then return ()
      else writeDigitsAtEnd mba newOffset q

-- FROM TYPE VARIABLE

fromTypeVariable :: Name -> Int -> Name
fromTypeVariable name index
  | index <= 0 = name
  | nameEndsWithDigit name = buildTypeVarWithSeparator name index
  | otherwise = buildTypeVarDirect name index

buildTypeVarWithSeparator :: Name -> Int -> Name
buildTypeVarWithSeparator name@(Utf8.Utf8 ba#) index =
  runST $ do
    let !size = I# len# + 1 + getIndexSize index
    mba <- newByteArray size
    copyToMBA name mba
    writeWord8 mba (I# len#) 0x5F {- _ -}
    writeDigitsAtEnd mba size index
    freeze mba
  where
    len# = sizeofByteArray# ba#

buildTypeVarDirect :: Name -> Int -> Name
buildTypeVarDirect name@(Utf8.Utf8 ba#) index =
  runST $ do
    let !size = I# len# + getIndexSize index
    mba <- newByteArray size
    copyToMBA name mba
    writeDigitsAtEnd mba size index
    freeze mba
  where
    len# = sizeofByteArray# ba#

nameEndsWithDigit :: Name -> Bool
nameEndsWithDigit (Utf8.Utf8 ba#) =
  let len# = sizeofByteArray# ba#
      end# = word8ToWord# (indexWord8Array# ba# (len# -# 1#))
   in isTrue# (leWord# 0x30## end#) && isTrue# (leWord# end# 0x39##)

-- FROM TYPE VARIABLE SCHEME

fromTypeVariableScheme :: Int -> Name
fromTypeVariableScheme scheme =
  runST
    ( if scheme < 26
        then do
          mba <- newByteArray 1
          writeWord8 mba 0 (0x61 + fromIntegral scheme)
          freeze mba
        else do
          let (extra, letter) = quotRem scheme 26
          let !size = 1 + getIndexSize extra
          mba <- newByteArray size
          writeWord8 mba 0 (0x61 + fromIntegral letter)
          writeDigitsAtEnd mba size extra
          freeze mba
    )

-- PRIMITIVES

data MBA s
  = MBA# (MutableByteArray# s)

{-# INLINE newByteArray #-}
newByteArray :: Int -> ST s (MBA s)
newByteArray (I# len#) =
  ST $ \s ->
    case newByteArray# len# s of
      (# s, mba# #) -> (# s, MBA# mba# #)

{-# INLINE freeze #-}
freeze :: MBA s -> ST s Name
freeze (MBA# mba#) =
  ST $ \s ->
    case unsafeFreezeByteArray# mba# s of
      (# s, ba# #) -> (# s, Utf8.Utf8 ba# #)

{-# INLINE writeWord8 #-}
writeWord8 :: MBA s -> Int -> Word8 -> ST s ()
writeWord8 (MBA# mba#) (I# offset#) (W8# w#) =
  ST $ \s ->
    case writeWord8Array# mba# offset# w# s of
      s -> (# s, () #)

{-# INLINE copyToMBA #-}
copyToMBA :: Name -> MBA s -> ST s ()
copyToMBA (Utf8.Utf8 ba#) (MBA# mba#) =
  ST $ \s ->
    case copyByteArray# ba# 0# mba# 0# (sizeofByteArray# ba#) s of
      s -> (# s, () #)

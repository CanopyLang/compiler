{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | UTF-8 type definitions and basic operations.
--
-- This module provides the core Utf8 type and fundamental operations for:
--
-- * Type definitions and constructors
-- * Basic testing operations (empty, size, contains)
-- * Content testing operations (starts with, ends with)
-- * Comparison and equality instances
--
-- @since 0.19.1
module Data.Utf8.Types
  ( -- * Core Types
    Utf8 (..),

    -- * Basic Operations
    isEmpty,
    empty,
    size,

    -- * Content Testing
    contains,
    startsWith,
    startsWithChar,
    endsWithWord8,
  )
where

import GHC.Exts
  ( Char (C#),
    Int (I#),
    isTrue#,
  )
import GHC.Prim
import GHC.ST (ST (ST), runST)
import GHC.Word (Word8 (W8#))
import Prelude hiding (all, any, concat)

-- UTF-8

data Utf8 tipe
  = Utf8 ByteArray#

instance Show (Utf8 a) where
  show = toChars

-- EMPTY

{-# NOINLINE empty #-}
empty :: Utf8 t
empty =
  runST (newByteArray 0 >>= freeze)

isEmpty :: Utf8 t -> Bool
isEmpty (Utf8 ba#) =
  isTrue# (sizeofByteArray# ba# ==# 0#)

-- SIZE

size :: Utf8 t -> Int
size (Utf8 ba#) =
  I# (sizeofByteArray# ba#)

-- CONTAINS

contains :: Word8 -> Utf8 t -> Bool
contains (W8# word#) (Utf8 ba#) =
  containsHelp word# ba# 0# (sizeofByteArray# ba#)

containsHelp :: Word8# -> ByteArray# -> Int# -> Int# -> Bool
containsHelp word# ba# !offset# len# =
  isTrue# (offset# <# len#) && (isTrue# (eqWord8# word# (indexWord8Array# ba# offset#)) || containsHelp word# ba# (offset# +# 1#) len#)

-- STARTS WITH

{-# INLINE startsWith #-}
startsWith :: Utf8 t -> Utf8 t -> Bool
startsWith (Utf8 ba1#) (Utf8 ba2#) =
  let !len1# = sizeofByteArray# ba1#
      !len2# = sizeofByteArray# ba2#
   in isTrue# (len1# <=# len2#)
        && isTrue# (0# ==# compareByteArrays# ba1# 0# ba2# 0# len1#)

-- STARTS WITH CHAR

startsWithChar :: (Char -> Bool) -> Utf8 t -> Bool
startsWithChar isGood bytes@(Utf8 ba#) =
  not (isEmpty bytes)
    && ( let !w# = word8ToWord# (indexWord8Array# ba# 0#)
             !char
               | isTrue# (ltWord# w# 0xC0##) = C# (chr# (word2Int# w#))
               | isTrue# (ltWord# w# 0xE0##) = chr2 ba# 0# w#
               | isTrue# (ltWord# w# 0xF0##) = chr3 ba# 0# w#
               | otherwise = chr4 ba# 0# w#
          in isGood char
       )

-- ENDS WITH WORD

endsWithWord8 :: Word8 -> Utf8 t -> Bool
endsWithWord8 (W8# w#) (Utf8 ba#) =
  let len# = sizeofByteArray# ba#
   in isTrue# (len# ># 0#)
        && isTrue# (eqWord8# w# (indexWord8Array# ba# (len# -# 1#)))

-- EQUAL

instance Eq (Utf8 t) where
  (==) (Utf8 ba1#) (Utf8 ba2#) =
    let !len1# = sizeofByteArray# ba1#
        !len2# = sizeofByteArray# ba2#
     in isTrue# (len1# ==# len2#)
          && isTrue# (0# ==# compareByteArrays# ba1# 0# ba2# 0# len1#)

-- COMPARE
--
-- Sorts by length first, then compares bytes on length ties. This gives
-- consistent ordering and efficient comparison for typical identifier strings.
--

instance Ord (Utf8 t) where
  compare (Utf8 ba1#) (Utf8 ba2#) =
    let !len1# = sizeofByteArray# ba1#
        !len2# = sizeofByteArray# ba2#
        !len# = if isTrue# (len1# <# len2#) then len1# else len2#
        !cmp# = compareByteArrays# ba1# 0# ba2# 0# len#
     in case () of
          _
            | isTrue# (cmp# <# 0#) -> LT
            | isTrue# (cmp# ># 0#) -> GT
            | isTrue# (len1# <# len2#) -> LT
            | isTrue# (len1# ># len2#) -> GT
            | True -> EQ

-- CHARACTER DECODING HELPERS

{-# INLINE chr2 #-}
chr2 :: ByteArray# -> Int# -> Word# -> Char
chr2 ba# offset# firstWord# =
  let !i1# = word2Int# firstWord#
      !i2# = word2Int# (word8ToWord# (indexWord8Array# ba# (offset# +# 1#)))
      !c1# = uncheckedIShiftL# (i1# -# 0xC0#) 6#
      !c2# = i2# -# 0x80#
   in C# (chr# (c1# +# c2#))

{-# INLINE chr3 #-}
chr3 :: ByteArray# -> Int# -> Word# -> Char
chr3 ba# offset# firstWord# =
  let !i1# = word2Int# firstWord#
      !i2# = word2Int# (word8ToWord# (indexWord8Array# ba# (offset# +# 1#)))
      !i3# = word2Int# (word8ToWord# (indexWord8Array# ba# (offset# +# 2#)))
      !c1# = uncheckedIShiftL# (i1# -# 0xE0#) 12#
      !c2# = uncheckedIShiftL# (i2# -# 0x80#) 6#
      !c3# = i3# -# 0x80#
   in C# (chr# (c1# +# c2# +# c3#))

{-# INLINE chr4 #-}
chr4 :: ByteArray# -> Int# -> Word# -> Char
chr4 ba# offset# firstWord# =
  let !i1# = word2Int# firstWord#
      !i2# = word2Int# (word8ToWord# (indexWord8Array# ba# (offset# +# 1#)))
      !i3# = word2Int# (word8ToWord# (indexWord8Array# ba# (offset# +# 2#)))
      !i4# = word2Int# (word8ToWord# (indexWord8Array# ba# (offset# +# 3#)))
      !c1# = uncheckedIShiftL# (i1# -# 0xF0#) 18#
      !c2# = uncheckedIShiftL# (i2# -# 0x80#) 12#
      !c3# = uncheckedIShiftL# (i3# -# 0x80#) 6#
      !c4# = i4# -# 0x80#
   in C# (chr# (c1# +# c2# +# c3# +# c4#))

-- PRIMITIVES (used by Show instance)

data MBA s
  = MBA# (MutableByteArray# s)

newByteArray :: Int -> ST s (MBA s) -- PERF see if newPinnedByteArray for len > 256 is positive
newByteArray (I# len#) =
  ST $ \s ->
    case newByteArray# len# s of
      (# s, mba# #) -> (# s, MBA# mba# #)

freeze :: MBA s -> ST s (Utf8 t)
freeze (MBA# mba#) =
  ST $ \s ->
    case unsafeFreezeByteArray# mba# s of
      (# s, ba# #) -> (# s, Utf8 ba# #)

-- TO CHARS (used by Show instance)

toChars :: Utf8 t -> String
toChars (Utf8 ba#) =
  toCharsHelp ba# 0# (sizeofByteArray# ba#)

toCharsHelp :: ByteArray# -> Int# -> Int# -> String
toCharsHelp ba# offset# len# =
  if isTrue# (offset# >=# len#)
    then []
    else
      let !w# = word8ToWord# (indexWord8Array# ba# offset#)
          !(# char, width# #)
            | isTrue# (ltWord# w# 0xC0##) = (# C# (chr# (word2Int# w#)), 1# #)
            | isTrue# (ltWord# w# 0xE0##) = (# chr2 ba# offset# w#, 2# #)
            | isTrue# (ltWord# w# 0xF0##) = (# chr3 ba# offset# w#, 3# #)
            | otherwise = (# chr4 ba# offset# w#, 4# #)

          !newOffset# = offset# +# width#
       in char : toCharsHelp ba# newOffset# len#

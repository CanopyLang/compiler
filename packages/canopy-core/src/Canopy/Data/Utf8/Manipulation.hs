{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | UTF-8 string manipulation operations.
--
-- This module provides functionality for manipulating UTF-8 strings:
--
-- * String splitting on delimiters
-- * String joining with separators
-- * String slicing and copying operations
-- * Low-level memory operations for string building
--
-- @since 0.19.1
module Canopy.Data.Utf8.Manipulation
  ( -- * String Operations
    split,
    join,
    joinConsecutivePairSep,

    -- * Slicing
    dropBytes,

    -- * Low-level Copy Operations
    copy,
    copyFromPtr,
  )
where

import qualified Data.List as List
import Canopy.Data.Utf8.Creation (MBA (MBA#), freeze, newByteArray, writeWord8)
import Canopy.Data.Utf8.Types (Utf8 (..), empty, size)
import Foreign.Ptr (Ptr)
import GHC.Exts
  ( Int (I#),
    Ptr (Ptr),
    isTrue#,
  )
import GHC.Prim
import GHC.ST (ST (ST), runST)
import GHC.Word (Word8 (W8#))

-- SPLIT

split :: Word8 -> Utf8 t -> [Utf8 t]
split (W8# divider#) str@(Utf8 ba#) =
  splitHelp str 0 (findDividers divider# ba# 0# (sizeofByteArray# ba#) [])

splitHelp :: Utf8 t -> Int -> [Int] -> [Utf8 t]
splitHelp str start offsets =
  case offsets of
    [] ->
      [unsafeSlice str start (size str)]
    offset : offsets ->
      unsafeSlice str start offset : splitHelp str (offset + 1) offsets

findDividers :: Word8# -> ByteArray# -> Int# -> Int# -> [Int] -> [Int]
findDividers divider# ba# !offset# len# revOffsets =
  if isTrue# (offset# <# len#)
    then
      findDividers divider# ba# (offset# +# 1#) len# $
        if isTrue# (eqWord8# divider# (indexWord8Array# ba# offset#))
          then I# offset# : revOffsets
          else revOffsets
    else reverse revOffsets

unsafeSlice :: Utf8 t -> Int -> Int -> Utf8 t
unsafeSlice str start end =
  let !len = end - start
   in if len == 0
        then empty
        else runST $
          do
            mba <- newByteArray len
            copy str start mba 0 len
            freeze mba

-- DROP BYTES

-- | Drop the first @n@ bytes from a Utf8 value.
--
-- Returns 'empty' when @n@ exceeds the total size. This operates at the
-- byte level, so the caller must ensure that @n@ falls on a UTF-8 code
-- point boundary (e.g., a known ASCII prefix length).
--
-- @since 0.19.2
dropBytes :: Int -> Utf8 t -> Utf8 t
dropBytes n str
  | n <= 0 = str
  | n >= size str = empty
  | otherwise = unsafeSlice str n (size str)

-- JOIN

join :: Word8 -> [Utf8 t] -> Utf8 t
join sep strings =
  case strings of
    [] ->
      empty
    str : strs ->
      runST $
        do
          let !len = List.foldl' (\w s -> w + 1 + size s) (size str) strs
          mba <- newByteArray len
          joinHelp sep mba 0 str strs
          freeze mba

joinHelp :: Word8 -> MBA s -> Int -> Utf8 t -> [Utf8 t] -> ST s ()
joinHelp sep mba offset str strings =
  let !len = size str
   in case strings of
        [] ->
          copy str 0 mba offset len
        s : ss ->
          do
            copy str 0 mba offset len
            let !dotOffset = offset + len
            writeWord8 mba dotOffset sep
            let !newOffset = dotOffset + 1
            joinHelp sep mba newOffset s ss

joinConsecutivePairSep :: (Word8, Word8) -> [Utf8 t] -> Utf8 t
joinConsecutivePairSep (pairSep, groupSep) strings =
  join groupSep (pairStrings pairSep strings)

-- Helper function to pair consecutive elements and join them
pairStrings :: Word8 -> [Utf8 t] -> [Utf8 t]
pairStrings _ [] = []
pairStrings _ [x] = [x]  -- Odd number - last element stands alone
pairStrings pairSep (x : y : rest) = 
  let pairedStr = join pairSep [x, y]
   in pairedStr : pairStrings pairSep rest

-- COPY OPERATIONS

copy :: Utf8 t -> Int -> MBA s -> Int -> Int -> ST s ()
copy (Utf8 ba#) (I# offset#) (MBA# mba#) (I# i#) (I# len#) =
  ST $ \s ->
    case copyByteArray# ba# offset# mba# i# len# s of
      s -> (# s, () #)

copyFromPtr :: Ptr a -> MBA RealWorld -> Int -> Int -> ST RealWorld ()
copyFromPtr (Ptr src#) (MBA# mba#) (I# offset#) (I# len#) =
  ST $ \s ->
    case copyAddrToByteArray# src# mba# offset# len# s of
      s -> (# s, () #)

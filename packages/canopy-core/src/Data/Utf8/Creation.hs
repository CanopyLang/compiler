{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | UTF-8 string creation and character encoding operations.
--
-- This module provides functionality for creating UTF-8 strings from
-- various sources and handling character encoding:
--
-- * String creation from Haskell strings
-- * Character width calculation for UTF-8 encoding
-- * Efficient character-by-character encoding
-- * Low-level memory allocation for string building
--
-- @since 0.19.1
module Data.Utf8.Creation
  ( -- * String Creation
    fromChars,
    toChars,

    -- * Low-level Primitives
    MBA (MBA#),
    newByteArray,
    writeWord8,
    freeze,
  )
where

import Data.Bits (shiftR, (.&.))
import qualified Data.Char as Char
import Data.Utf8.Types (Utf8 (..))
import GHC.Exts
  ( Char (C#),
    Int (I#),
    isTrue#,
  )
import GHC.Prim
import GHC.ST (ST (ST), runST)
import GHC.Word (Word8 (W8#))

-- FROM STRING

fromChars :: String -> Utf8 t
fromChars chars =
  runST
    ( do
        mba <- newByteArray (sum (fmap getWidth chars))
        writeChars mba 0 chars
    )

writeChars :: MBA s -> Int -> String -> ST s (Utf8 t)
writeChars !mba !offset chars =
  case chars of
    [] -> freeze mba
    char : chars -> writeUtf8Char mba offset char >>= \newOffset -> writeChars mba newOffset chars

writeUtf8Char :: MBA s -> Int -> Char -> ST s Int
writeUtf8Char mba offset char
  | n < 0x80 = writeUtf8_1Byte mba offset n
  | n < 0x800 = writeUtf8_2Byte mba offset n
  | n < 0x10000 = writeUtf8_3Byte mba offset n
  | otherwise = writeUtf8_4Byte mba offset n
  where
    n = Char.ord char

writeUtf8_1Byte :: MBA s -> Int -> Int -> ST s Int
writeUtf8_1Byte mba offset n = do
  writeWord8 mba offset (fromIntegral n)
  pure (offset + 1)

writeUtf8_2Byte :: MBA s -> Int -> Int -> ST s Int
writeUtf8_2Byte mba offset n = do
  writeWord8 mba offset (fromIntegral ((shiftR n 6) + 0xC0))
  writeWord8 mba (offset + 1) (fromIntegral ((n .&. 0x3F) + 0x80))
  pure (offset + 2)

writeUtf8_3Byte :: MBA s -> Int -> Int -> ST s Int
writeUtf8_3Byte mba offset n = do
  writeWord8 mba offset (fromIntegral ((shiftR n 12) + 0xE0))
  writeWord8 mba (offset + 1) (fromIntegral ((shiftR n 6 .&. 0x3F) + 0x80))
  writeWord8 mba (offset + 2) (fromIntegral ((n .&. 0x3F) + 0x80))
  pure (offset + 3)

writeUtf8_4Byte :: MBA s -> Int -> Int -> ST s Int
writeUtf8_4Byte mba offset n = do
  writeWord8 mba offset (fromIntegral ((shiftR n 18) + 0xF0))
  writeWord8 mba (offset + 1) (fromIntegral ((shiftR n 12 .&. 0x3F) + 0x80))
  writeWord8 mba (offset + 2) (fromIntegral ((shiftR n 6 .&. 0x3F) + 0x80))
  writeWord8 mba (offset + 3) (fromIntegral ((n .&. 0x3F) + 0x80))
  pure (offset + 4)

{-# INLINE getWidth #-}
getWidth :: Char -> Int
getWidth char
  | code < 0x80 = 1
  | code < 0x800 = 2
  | code < 0x10000 = 3
  | otherwise = 4
  where
    code = Char.ord char

-- TO CHARS

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

-- PRIMITIVES

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

{-# INLINE writeWord8 #-}
writeWord8 :: MBA s -> Int -> Word8 -> ST s ()
writeWord8 (MBA# mba#) (I# offset#) (W8# w#) =
  ST $ \s ->
    case writeWord8Array# mba# offset# w# s of
      s -> (# s, () #)

{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | ByteString Builder operations for UTF-8 strings.
--
-- This module provides efficient conversion from UTF-8 strings to ByteString
-- builders, including specialized operations for:
--
-- * Basic builder conversion from UTF-8 strings
-- * Escaped builder generation for special character handling
-- * Efficient memory copying and buffer management
-- * Low-level pointer operations for performance
--
-- The builder operations are optimized for streaming and efficient memory
-- usage, supporting both regular and escaped string output for different
-- contexts like JavaScript code generation.
--
-- === Usage Examples
--
-- @
-- -- Convert UTF-8 to builder
-- let text = fromChars "Hello World"
--     builder = toBuilder text
--
-- -- Create escaped builder for JavaScript strings
-- let jsString = toEscapedBuilder 0x22 0x5C text  -- escape " with \\
--     result = toLazyByteString jsString
-- @
--
-- @since 0.19.1
module Data.Utf8.Builder
  ( -- * Builder Operations
    toBuilder,
    toEscapedBuilder,
  )
where

import Control.Monad (when)
import qualified Data.ByteString.Builder.Internal as B
import Data.Utf8.Core (Utf8 (..))
import Foreign.Ptr (minusPtr, plusPtr)
import GHC.Exts
  ( Int (I#),
    Ptr (Ptr),
    isTrue#,
  )
import GHC.IO
import GHC.Prim
import GHC.Word (Word8 (W8#))

-- TO BUILDER

{-# INLINE toBuilder #-}
toBuilder :: Utf8 t -> B.Builder
toBuilder bytes = B.builder (toBuilderHelp bytes)

{-# INLINE toBuilderHelp #-}
toBuilderHelp :: Utf8 t -> B.BuildStep a -> B.BuildStep a
toBuilderHelp bytes@(Utf8 ba#) k =
  go 0 (I# (sizeofByteArray# ba#))
  where
    go !offset !end (B.BufferRange bOffset bEnd) =
      let !bLen = minusPtr bEnd bOffset
          !len = end - offset
       in if len <= bLen
            then do
              copyToPtr bytes offset bOffset len
              let !br' = B.BufferRange (plusPtr bOffset len) bEnd
              k br'
            else do
              copyToPtr bytes offset bOffset bLen
              let !offset' = offset + bLen
              return $ B.bufferFull 1 bEnd (go offset' end)

-- TO ESCAPED BUILDER

{-# INLINE toEscapedBuilder #-}
toEscapedBuilder :: Word8 -> Word8 -> Utf8 t -> B.Builder
toEscapedBuilder before after name = B.builder (toEscapedBuilderHelp before after name)

{-# INLINE toEscapedBuilderHelp #-}
toEscapedBuilderHelp :: Word8 -> Word8 -> Utf8 t -> B.BuildStep a -> B.BuildStep a
toEscapedBuilderHelp before after name@(Utf8 ba#) k =
  go 0 (I# (sizeofByteArray# ba#))
  where
    go !offset !len (B.BufferRange bOffset bEnd) =
      let !bLen = minusPtr bEnd bOffset
       in if len <= bLen
            then do
              -- PERF test if writing word-by-word is faster
              copyToPtr name offset bOffset len
              escape before after bOffset name offset len 0
              let !newBufferRange = B.BufferRange (plusPtr bOffset len) bEnd
              k newBufferRange
            else do
              copyToPtr name offset bOffset bLen
              escape before after bOffset name offset bLen 0
              let !newOffset = offset + bLen
              let !newLength = len - bLen
              return $ B.bufferFull 1 bEnd (go newOffset newLength)

escape :: Word8 -> Word8 -> Ptr a -> Utf8 t -> Int -> Int -> Int -> IO ()
escape before@(W8# before#) after ptr name@(Utf8 ba#) offset@(I# offset#) len@(I# len#) i@(I# i#) =
  when (isTrue# (i# <# len#)) $
    if isTrue# (eqWord8# before# (indexWord8Array# ba# (offset# +# i#)))
      then do
        writeWordToPtr ptr i after
        escape before after ptr name offset len (i + 1)
      else escape before after ptr name offset len (i + 1)

-- LOW-LEVEL OPERATIONS

copyToPtr :: Utf8 t -> Int -> Ptr a -> Int -> IO ()
copyToPtr (Utf8 ba#) (I# offset#) (Ptr mba#) (I# len#) =
  IO $ \s ->
    case copyByteArrayToAddr# ba# offset# mba# len# s of
      s -> (# s, () #)

{-# INLINE writeWordToPtr #-}
writeWordToPtr :: Ptr a -> Int -> Word8 -> IO ()
writeWordToPtr (Ptr addr#) (I# offset#) (W8# word#) =
  IO $ \s ->
    case writeWord8OffAddr# addr# offset# word# s of
      s -> (# s, () #)

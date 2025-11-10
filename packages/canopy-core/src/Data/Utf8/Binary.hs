{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Binary serialization operations for UTF-8 strings.
--
-- This module provides efficient binary serialization and deserialization
-- of UTF-8 strings for the Canopy compiler. It supports:
--
-- * Compact serialization for strings under 256 bytes
-- * Full serialization for very long strings
-- * Efficient deserialization from binary data
-- * ByteString integration for serialized data
--
-- The serialization format is optimized for the common case of short strings
-- (under 256 bytes) while supporting arbitrary-length strings when needed.
-- This is crucial for efficient storage of compiled modules and caching.
--
-- === Usage Examples
--
-- @
-- -- Serialize short strings (< 256 bytes)
-- let shortText = fromChars "hello"
--     serialized = encode shortText  -- uses putUnder256
--     deserialized = decode serialized  -- uses getUnder256
--
-- -- Serialize long strings
-- let longText = fromChars (replicate 300 'a')
--     serialized = encode longText  -- uses putVeryLong
--     deserialized = decode serialized  -- uses getVeryLong
-- @
--
-- @since 0.19.1
module Data.Utf8.Binary
  ( -- * Short String Serialization (< 256 bytes)
    putUnder256,
    getUnder256,

    -- * Long String Serialization
    putVeryLong,
    getVeryLong,
  )
where

import Data.Binary (Get, Put, get, getWord8, put, putWord8)
import Data.Binary.Get.Internal (readN)
import Data.Binary.Put (putBuilder)
import qualified Data.ByteString.Internal as B
import Data.Utf8.Builder (toBuilder)
import Data.Utf8.Core (Utf8 (..), copyFromPtr, empty, freeze, newByteArray, size)
import Foreign.ForeignPtr (touchForeignPtr)
import Foreign.ForeignPtr.Unsafe (unsafeForeignPtrToPtr)
import Foreign.Ptr (plusPtr)
import GHC.IO (stToIO, unsafeDupablePerformIO)

-- SHORT STRING SERIALIZATION (< 256 bytes)

putUnder256 :: Utf8 t -> Put
putUnder256 bytes =
  do
    putWord8 (fromIntegral (size bytes))
    putBuilder (toBuilder bytes)

getUnder256 :: Get (Utf8 t)
getUnder256 =
  do
    word <- getWord8
    let !n = fromIntegral word
    readN n (copyFromByteString n)

-- LONG STRING SERIALIZATION

putVeryLong :: Utf8 t -> Put
putVeryLong bytes =
  do
    put (size bytes)
    putBuilder (toBuilder bytes)

getVeryLong :: Get (Utf8 t)
getVeryLong =
  do
    n <- get
    if n > 0
      then readN n (copyFromByteString n)
      else return empty

-- COPY FROM BYTESTRING

{-# INLINE copyFromByteString #-}
copyFromByteString :: Int -> B.ByteString -> Utf8 t
copyFromByteString len (B.PS fptr offset _) =
  unsafeDupablePerformIO
    ( do
        mba <- stToIO (newByteArray len)
        stToIO (copyFromPtr (unsafeForeignPtrToPtr fptr `plusPtr` offset) mba 0 len)
        touchForeignPtr fptr
        stToIO (freeze mba)
    )

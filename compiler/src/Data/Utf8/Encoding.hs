{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Character encoding and pointer operations for UTF-8 strings.
--
-- This module provides low-level operations for UTF-8 character encoding
-- and decoding, along with efficient pointer-based string construction.
-- It handles:
--
-- * Creation of UTF-8 strings from raw memory pointers
-- * Construction from parser snippets
-- * Character encoding validation and conversion
-- * Low-level memory operations for string building
--
-- These operations are primarily used by the parser and other low-level
-- components that work directly with memory buffers and need efficient
-- UTF-8 string construction without intermediate allocations.
--
-- === Usage Examples
--
-- @
-- -- Create UTF-8 string from memory range
-- let utf8Text = fromPtr startPtr endPtr
--
-- -- Create from parser snippet
-- let parsedText = fromSnippet snippet
-- @
--
-- === Safety Notes
--
-- These operations work directly with raw pointers and assume valid
-- UTF-8 input. They are intended for internal compiler use where the
-- input is already validated by the parser.
--
-- @since 0.19.1
module Data.Utf8.Encoding
  ( -- * Pointer-based Construction
    fromPtr,
    fromSnippet,
  )
where

import Data.Utf8.Core (Utf8 (..), copyFromPtr, freeze, newByteArray)
import Foreign.ForeignPtr.Unsafe (unsafeForeignPtrToPtr)
import Foreign.Ptr (minusPtr, plusPtr)
import GHC.Exts
  ( Ptr,
  )
import GHC.IO (stToIO, unsafeDupablePerformIO)
import GHC.Word (Word8)
import qualified Parse.Primitives as P

-- FROM PTR

fromPtr :: Ptr Word8 -> Ptr Word8 -> Utf8 t
fromPtr pos end =
  unsafeDupablePerformIO
    ( stToIO
        ( do
            let !len = minusPtr end pos
            mba <- newByteArray len
            copyFromPtr pos mba 0 len
            freeze mba
        )
    )

-- FROM SNIPPET

fromSnippet :: P.Snippet -> Utf8 t
fromSnippet (P.Snippet fptr off len _ _) =
  unsafeDupablePerformIO
    ( stToIO
        ( do
            mba <- newByteArray len
            let !pos = plusPtr (unsafeForeignPtrToPtr fptr) off
            copyFromPtr pos mba 0 len
            freeze mba
        )
    )

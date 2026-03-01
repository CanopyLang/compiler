{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | UTF-8 string operations for the Canopy compiler.
--
-- This module provides a unified interface for all UTF-8 string operations
-- in the Canopy compiler. It re-exports functionality from specialized sub-modules:
--
-- * "Data.Utf8.Core" - Basic UTF-8 operations and core type definitions
-- * "Data.Utf8.Builder" - ByteString builder operations for efficient output
-- * "Data.Utf8.Binary" - Binary serialization and deserialization
-- * "Data.Utf8.Encoding" - Character encoding and pointer-based construction
--
-- UTF-8 strings in Canopy are represented as parameterized types to enable
-- type-safe distinction between different kinds of strings (names, file content,
-- etc.) while sharing the same efficient underlying implementation.
--
-- === Usage Examples
--
-- @
-- -- Basic UTF-8 operations
-- let text = fromChars "Hello, 世界!"
--     len = size text
--     parts = split 0x2C text  -- split on comma
--
-- -- Builder operations for efficient output
-- let builder = toBuilder text
--     escaped = toEscapedBuilder 0x22 0x5C text  -- escape quotes
--
-- -- Binary serialization
-- let serialized = runPut (putUnder256 text)
--     deserialized = runGet getUnder256 serialized
--
-- -- Low-level construction
-- let fromMemory = fromPtr startPtr endPtr
-- @
--
-- @since 0.19.1
module Canopy.Data.Utf8
  ( -- * Core Types and Operations
    Utf8 (..),
    isEmpty,
    empty,
    size,

    -- * Content Testing
    contains,
    startsWith,
    startsWithChar,
    endsWithWord8,

    -- * String Operations
    split,
    join,
    joinConsecutivePairSep,

    -- * Slicing
    dropBytes,

    -- * Conversion Operations
    toChars,
    fromChars,

    -- * Builder Operations
    toBuilder,
    toEscapedBuilder,

    -- * Binary Serialization
    getUnder256,
    putUnder256,
    getVeryLong,
    putVeryLong,

    -- * Pointer-based Construction
    fromPtr,
    fromSnippet,

    -- * Low-level Primitives
    MBA,
    newByteArray,
    copyFromPtr,
    writeWord8,
    freeze,
  )
where

-- Re-export all functionality from sub-modules

import Canopy.Data.Utf8.Binary
import Canopy.Data.Utf8.Builder
import Canopy.Data.Utf8.Core
import Canopy.Data.Utf8.Encoding

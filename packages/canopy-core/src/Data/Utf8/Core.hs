{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Core UTF-8 operations for the Canopy compiler.
--
-- This module provides a unified interface for core UTF-8 operations by
-- re-exporting functionality from specialized sub-modules:
--
-- * "Data.Utf8.Types" - Type definitions and basic operations
-- * "Data.Utf8.Creation" - String creation and character encoding
-- * "Data.Utf8.Manipulation" - String manipulation operations
--
-- The Utf8 type is parameterized to allow type-safe distinction between
-- different kinds of UTF-8 strings (e.g., names, file contents, etc.).
--
-- === Usage Examples
--
-- @
-- -- Create and test UTF-8 strings
-- let text = fromChars "Hello, World!"
--     len = size text
--     isEmpty_ = isEmpty text
--
-- -- Check contents and patterns
-- when (contains 0x21 text) $  -- contains '!'
--   processExclamation
--
-- -- Split and join operations
-- let parts = split 0x2C text   -- split on ','
--     rejoined = join 0x7C parts  -- join with '|'
-- @
--
-- @since 0.19.1
module Data.Utf8.Core
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

    -- * String Operations
    split,
    join,
    joinConsecutivePairSep,

    -- * Conversion
    toChars,
    fromChars,

    -- * Low-level Primitives
    MBA,
    newByteArray,
    copyFromPtr,
    writeWord8,
    freeze,
  )
where

-- Re-export all functionality from sub-modules

import Data.Utf8.Creation
import Data.Utf8.Manipulation
import Data.Utf8.Types

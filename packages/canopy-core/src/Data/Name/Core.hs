{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Core name operations for the Canopy compiler.
--
-- This module provides the fundamental Name type and basic operations for:
--
-- * Name creation from various sources
-- * Name conversion to different formats
-- * Basic name manipulation operations
-- * Name type definitions and instances
--
-- The Name type is built on top of UTF-8 encoded byte arrays for efficient
-- memory usage and fast operations.
--
-- === Usage Examples
--
-- @
-- -- Create names from strings
-- let name = fromChars "myFunction"
--     chars = toChars name
--     builder = toBuilder name
--
-- -- Convert to Canopy string format
-- let canopyStr = toCanopyString name
-- @
--
-- @since 0.19.1
module Data.Name.Core
  ( Name,
    CANOPY_NAME,

    -- * Conversion Operations
    toChars,
    toCanopyString,
    toBuilder,

    -- * Creation Operations
    fromPtr,
    fromChars,

    -- * Utilities
    hasDot,
    splitDots,
  )
where

import qualified Canopy.String as ES
import qualified Data.Binary as Binary
import Data.ByteString.Builder (Builder)
import qualified Data.Coerce as Coerce
import qualified Data.String as Chars
import qualified Data.Utf8 as Utf8
import GHC.Exts
  ( Ptr,
  )
import GHC.Word (Word8)
import Prelude hiding (length, maybe, negate)

-- NAME

type Name =
  Utf8.Utf8 CANOPY_NAME

data CANOPY_NAME

-- INSTANCES

instance Chars.IsString (Utf8.Utf8 CANOPY_NAME) where
  fromString = Utf8.fromChars

instance Binary.Binary (Utf8.Utf8 CANOPY_NAME) where
  get = Utf8.getUnder256
  put = Utf8.putUnder256

-- TO

toChars :: Name -> String
toChars =
  Utf8.toChars

toCanopyString :: Name -> ES.String
toCanopyString =
  Coerce.coerce

{-# INLINE toBuilder #-}
toBuilder :: Name -> Builder
toBuilder =
  Utf8.toBuilder

-- FROM

fromPtr :: Ptr Word8 -> Ptr Word8 -> Name
fromPtr =
  Utf8.fromPtr

fromChars :: String -> Name
fromChars =
  Utf8.fromChars

-- HAS DOT

hasDot :: Name -> Bool
hasDot =
  Utf8.contains 0x2E {- . -}

splitDots :: Name -> [Name]
splitDots =
  Utf8.split 0x2E {- . -}

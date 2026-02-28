{-# LANGUAGE OverloadedStrings #-}

-- | Constant-time comparison utilities for cryptographic operations.
--
-- Standard '==' on 'Text' and 'ByteString' short-circuits on the first
-- differing byte, leaking information about the position of differences
-- through timing variations. This module provides comparison functions
-- that always examine every byte, preventing timing side-channel attacks.
--
-- == When to Use
--
-- Use 'secureCompare' for all comparisons involving:
--
-- * Hash digests (SHA-256, etc.)
-- * HMAC values
-- * Signatures
-- * Authentication tokens
--
-- Standard '==' is fine for:
--
-- * Non-secret data (file paths, package names)
-- * Length-prefixed formats where the length is public
-- * Literal sentinel values like @\"sha256:not-cached\"@
--
-- @since 0.19.2
module Crypto.ConstantTime
  ( -- * Comparison
    secureCompare,
    secureCompareBS,
  )
where

import Data.Bits (xor, (.|.))
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import Data.Word (Word8)

-- | Constant-time comparison of two 'Text' values.
--
-- Returns 'True' if and only if both texts are identical. The comparison
-- always examines every byte of the UTF-8 encoded representation,
-- preventing timing attacks from learning where values differ.
--
-- If the lengths differ, the function returns 'False' immediately.
-- This leaks length information, but hash digests have fixed length,
-- so this is acceptable for the intended use case.
--
-- @since 0.19.2
secureCompare :: Text.Text -> Text.Text -> Bool
secureCompare a b =
  secureCompareBS (TextEnc.encodeUtf8 a) (TextEnc.encodeUtf8 b)

-- | Constant-time comparison of two 'ByteString' values.
--
-- Returns 'True' if and only if both bytestrings are identical.
-- The comparison always examines every byte, preventing timing
-- attacks from learning where values differ.
--
-- @since 0.19.2
secureCompareBS :: ByteString -> ByteString -> Bool
secureCompareBS a b =
  BS.length a == BS.length b && constantTimeEq a b

-- | XOR all corresponding byte pairs and accumulate the result.
--
-- Returns 'True' when every byte pair is identical (XOR yields zero).
constantTimeEq :: ByteString -> ByteString -> Bool
constantTimeEq a b =
  List.foldl' accumulateXor 0 (BS.zip a b) == 0

-- | Accumulate XOR differences between byte pairs.
accumulateXor :: Word8 -> (Word8, Word8) -> Word8
accumulateXor acc (x, y) = acc .|. (x `xor` y)

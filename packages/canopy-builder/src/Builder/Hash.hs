{-# LANGUAGE StrictData #-}

-- | Content hashing for incremental compilation.
--
-- This module provides content-based hashing for detecting changes in:
--
-- * Source files
-- * Dependencies
-- * Build configuration
--
-- Uses SHA-256 hashing for reliable change detection following the
-- NEW query engine pattern.
--
-- Hash digests are stored as raw 32-byte 'ShortByteString' values
-- instead of 64-character hex strings, reducing per-hash memory
-- from ~1KB (linked list of Char) to 32 bytes.
--
-- @since 0.19.1
module Builder.Hash
  ( -- * Hash Types
    ContentHash (..),
    HashValue (..),

    -- * Hashing Functions
    hashFile,
    hashBytes,
    hashString,
    hashDependencies,

    -- * Hash Comparison
    hashesEqual,
    hashChanged,

    -- * Hash Utilities
    showHash,
    emptyHash,
    toHexString,
    fromHexString,
  )
where

import qualified Data.ByteString as BS
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Short as SBS
import qualified Data.Char as Char
import Data.Bits (shiftR, (.&.))
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.ByteString.Lazy as BSL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.ModuleName as ModuleName
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log

-- | SHA-256 digest stored as raw bytes (32 bytes).
--
-- Uses 'ShortByteString' for compact storage: 32 bytes + GHC overhead
-- instead of 64 'Char' heap cells (~1KB on 64-bit).
newtype HashValue = HashValue { unHashValue :: SBS.ShortByteString }
  deriving (Eq, Ord)

instance Show HashValue where
  show hv = "HashValue " ++ show (toHexString hv)

-- | Content hash with metadata.
data ContentHash = ContentHash
  { hashValue :: !HashValue,
    hashSource :: !String -- ^ Description of what was hashed
  }
  deriving (Show, Eq)

-- | Empty hash for initialization.
emptyHash :: ContentHash
emptyHash =
  ContentHash
    { hashValue = HashValue SBS.empty,
      hashSource = "empty"
    }

-- | Hash a file's contents.
hashFile :: FilePath -> IO ContentHash
hashFile path = do
  Log.logEvent (BuildHashComputed path)
  contents <- BS.readFile path
  return
    ContentHash
      { hashValue = computeHash contents,
        hashSource = "file:" ++ path
      }

-- | Hash raw bytes.
hashBytes :: ByteString -> ContentHash
hashBytes bytes =
  ContentHash
    { hashValue = computeHash bytes,
      hashSource = "bytes:" ++ show (BS.length bytes) ++ " bytes"
    }

-- | Hash a string.
hashString :: String -> ContentHash
hashString str =
  ContentHash
    { hashValue = computeHash (BSC.pack str),
      hashSource = "string"
    }

-- | Hash dependencies (module names and their hashes).
hashDependencies :: Map ModuleName.Raw ContentHash -> ContentHash
hashDependencies deps =
  let depStrings = map formatDep (Map.toList deps)
      combined = unlines depStrings
   in ContentHash
        { hashValue = computeHash (BSC.pack combined),
          hashSource = "dependencies:" ++ show (Map.size deps) ++ " modules"
        }
  where
    formatDep (moduleName, hash) =
      show moduleName ++ ":" ++ toHexString (hashValue hash)

-- | Compute SHA-256 hash of bytes, returning raw digest.
computeHash :: ByteString -> HashValue
computeHash bytes =
  HashValue (SBS.toShort (BSL.toStrict (SHA.bytestringDigest (SHA.sha256 (BSL.fromStrict bytes)))))

-- | Check if two hashes are equal.
hashesEqual :: ContentHash -> ContentHash -> Bool
hashesEqual h1 h2 = hashValue h1 == hashValue h2

-- | Check if hash has changed (not equal).
hashChanged :: ContentHash -> ContentHash -> Bool
hashChanged h1 h2 = not (hashesEqual h1 h2)

-- | Show hash in readable format.
showHash :: ContentHash -> String
showHash hash =
  take 8 (toHexString (hashValue hash)) ++ "... (" ++ hashSource hash ++ ")"

-- | Convert a raw hash digest to a hex string for display or JSON serialization.
toHexString :: HashValue -> String
toHexString (HashValue sbs) =
  concatMap byteToHex (SBS.unpack sbs)
  where
    byteToHex b = [hexDigit (fromIntegral (shiftR b 4)), hexDigit (fromIntegral (b .&. 0x0F))]
    hexDigit n
      | n < 10    = Char.chr (Char.ord '0' + n)
      | otherwise = Char.chr (Char.ord 'a' + n - 10)

-- | Parse a hex string back into a raw hash digest.
--
-- Returns 'Nothing' if the string contains non-hex characters
-- or has odd length.
fromHexString :: String -> Maybe HashValue
fromHexString [] = Just (HashValue SBS.empty)
fromHexString hexStr
  | odd (length hexStr) = Nothing
  | otherwise = HashValue . SBS.pack <$> go hexStr
  where
    go [] = Just []
    go (hi:lo:rest) = do
      hiByte <- hexVal hi
      loByte <- hexVal lo
      restBytes <- go rest
      Just (fromIntegral (hiByte * 16 + loByte) : restBytes)
    go [_] = Nothing
    hexVal c
      | '0' <= c && c <= '9' = Just (Char.ord c - Char.ord '0')
      | 'a' <= c && c <= 'f' = Just (Char.ord c - Char.ord 'a' + 10)
      | 'A' <= c && c <= 'F' = Just (Char.ord c - Char.ord 'A' + 10)
      | otherwise = Nothing

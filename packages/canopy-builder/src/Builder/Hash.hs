{-# OPTIONS_GHC -Wall #-}

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
-- @since 0.19.1
module Builder.Hash
  ( -- * Hash Types
    ContentHash (..),
    HashValue,

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
  )
where

import qualified Data.ByteString as BS
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.ByteString.Lazy as BSL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.ModuleName as ModuleName
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log

-- | Hash value (SHA-256 digest).
type HashValue = String

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
    { hashValue = "",
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
      show moduleName ++ ":" ++ hashValue hash

-- | Compute SHA-256 hash of bytes.
computeHash :: ByteString -> HashValue
computeHash bytes =
  SHA.showDigest (SHA.sha256 (BSL.fromStrict bytes))

-- | Check if two hashes are equal.
hashesEqual :: ContentHash -> ContentHash -> Bool
hashesEqual h1 h2 = hashValue h1 == hashValue h2

-- | Check if hash has changed (not equal).
hashChanged :: ContentHash -> ContentHash -> Bool
hashChanged h1 h2 = not (hashesEqual h1 h2)

-- | Show hash in readable format.
showHash :: ContentHash -> String
showHash hash =
  take 8 (hashValue hash) ++ "... (" ++ hashSource hash ++ ")"

{-# LANGUAGE OverloadedStrings #-}

-- | Reproducible build verification for Canopy.
--
-- This module implements the @--verify-reproducible@ flag for the
-- @canopy make@ command. It builds the code generation step twice
-- from the same compiled artifacts and compares the generated output
-- byte-for-byte. If the outputs differ, it reports the first
-- divergence point and fails the build.
--
-- Canopy's code generation is inherently deterministic (sorted maps,
-- no timestamps in output, no non-deterministic iteration), so this
-- flag serves as a safety net to detect regressions that could
-- introduce non-determinism.
--
-- == Usage
--
-- @
-- canopy make src\/Main.can --output=main.js --verify-reproducible
-- @
--
-- @since 0.19.2
module Make.Reproducible
  ( -- * Verification
    verifyBuilderReproducibility,

    -- * Content Hashing
    hashBuilder,
    formatContentHash,
    reportContentHash,
  )
where

import qualified Data.ByteString as BS
import Data.ByteString (ByteString)
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log

-- | Verify that two builders produce identical byte output.
--
-- Takes two builders (from two separate code generation passes),
-- materializes them to strict bytestrings, and compares them.
-- Returns 'Nothing' if the outputs match, or 'Just' with the
-- byte offset of the first divergence.
--
-- @since 0.19.2
verifyBuilderReproducibility :: Builder.Builder -> Builder.Builder -> IO (Maybe Int)
verifyBuilderReproducibility builder1 builder2 = do
  Log.logEvent (BuildStarted "Verifying reproducibility: comparing two builds")
  pure (findDivergence (materialize builder1) (materialize builder2))

-- | Materialize a builder to a strict bytestring for comparison.
materialize :: Builder.Builder -> ByteString
materialize = BS.toStrict . Builder.toLazyByteString

-- | Find the byte offset of the first divergence between two bytestrings.
--
-- Returns 'Nothing' if the bytestrings are identical, or 'Just offset'
-- at the first differing byte (or the length of the shorter string
-- if one is a prefix of the other).
findDivergence :: ByteString -> ByteString -> Maybe Int
findDivergence bs1 bs2
  | bs1 == bs2 = Nothing
  | otherwise = Just (countMatchingPrefix bs1 bs2)

-- | Count the number of matching prefix bytes.
countMatchingPrefix :: ByteString -> ByteString -> Int
countMatchingPrefix bs1 bs2 =
  length (takeWhile id (BS.zipWith (==) bs1 bs2))

-- | Compute the SHA-256 hash of a builder's content.
--
-- Returns the hex-encoded hash string prefixed with @sha256:@
-- for display in build output.
--
-- @since 0.19.2
hashBuilder :: Builder.Builder -> String
hashBuilder = formatContentHash . sha256Hex . materialize

-- | Format a hex hash string with the @sha256:@ prefix.
--
-- @since 0.19.2
formatContentHash :: String -> String
formatContentHash hexHash = "sha256:" <> hexHash

-- | Report the content hash of a build output to stdout.
--
-- Prints a summary with the output file path, its SHA-256 hash,
-- and whether reproducibility was verified.
--
-- @since 0.19.2
reportContentHash :: FilePath -> String -> Bool -> IO ()
reportContentHash target contentHash verified = do
  Log.logEvent (BuildStarted (Text.pack ("Output hash: " <> contentHash)))
  putStrLn ""
  putStrLn "  Build complete:"
  putStrLn ("    Output: " <> target <> " (" <> contentHash <> ")")
  putStrLn ("    Reproducible: " <> reproMsg)
  putStrLn ""
  where
    reproMsg
      | verified = "yes (two builds matched)"
      | otherwise = "not verified (use --verify-reproducible)"

-- | Compute SHA-256 hex digest of a bytestring.
sha256Hex :: ByteString -> String
sha256Hex = SHA.showDigest . SHA.sha256 . BSL.fromStrict

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Generate.JavaScript.CodeSplit.Manifest — Chunk manifest generation
--
-- Produces the JSON manifest that maps chunk IDs to their cache-busted
-- filenames.  The manifest is:
--
--   1. Embedded inline in the entry chunk's @__canopy_manifest@ variable.
--   2. Written to @manifest.json@ on disk for server-side tooling.
--
-- Content hashes use SHA-256 truncated to 8 hex characters, providing
-- sufficient collision resistance for cache-busting while keeping
-- filenames readable.
--
-- @since 0.19.2
module Generate.JavaScript.CodeSplit.Manifest
  ( generateManifest,
    generateManifestAssignment,
    contentHash,
    chunkFilename,
  )
where

import qualified Data.ByteString.Builder as B
import Data.ByteString.Builder (Builder)
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.Text as Text
import Generate.JavaScript.CodeSplit.Types
  ( ChunkId (..),
    ChunkKind (..),
    ChunkOutput (..),
  )

-- | Generate the JSON manifest mapping chunk IDs to filenames.
--
-- Produces valid JSON suitable for both inline embedding and disk output.
--
-- ==== Example output
--
-- @
-- {
--   "entry": "entry.js",
--   "chunks": {
--     "lazy-Dashboard": "chunk-Dashboard-a1b2c3d4.js",
--     "shared-0": "shared-0-e5f6a7b8.js"
--   }
-- }
-- @
--
-- @since 0.19.2
generateManifest :: [ChunkOutput] -> Builder
generateManifest outputs =
  "{" <> entryField <> chunksField <> "}"
  where
    entryField = jsonField "entry" (entryFilename outputs) True
    chunksField = ",\"chunks\":{" <> chunkEntries <> "}"
    chunkEntries = mconcat (zipCommas (map chunkEntry nonEntryOutputs))
    nonEntryOutputs = filter (not . isEntry) outputs

-- | Generate the inline JavaScript assignment for __canopy_manifest.
--
-- Produces the @__canopy_manifest = {...};@ statement that is
-- embedded in the entry chunk.
--
-- @since 0.19.2
generateManifestAssignment :: [ChunkOutput] -> Builder
generateManifestAssignment outputs =
  "__canopy_manifest = " <> manifestObj <> ";\n"
  where
    manifestObj = "{" <> mconcat (zipCommas (map manifestEntry nonEntryOutputs)) <> "}"
    nonEntryOutputs = filter (not . isEntry) outputs

-- | Compute the content hash for a builder.
--
-- Uses SHA-256, truncated to 8 hex characters.  This gives 32 bits
-- of collision resistance — more than sufficient for cache-busting.
--
-- @since 0.19.2
contentHash :: Builder -> Text.Text
contentHash builder =
  Text.take 8 (Text.pack (SHA.showDigest digest))
  where
    digest = SHA.sha256 (B.toLazyByteString builder)

-- | Compute the filename for a chunk based on its kind, ID, and content hash.
--
-- Filename patterns:
--
--   * Entry:  @entry.js@
--   * Lazy:   @chunk-\<name\>-\<hash\>.js@
--   * Shared: @shared-\<n\>-\<hash\>.js@
--
-- @since 0.19.2
chunkFilename :: ChunkKind -> ChunkId -> Text.Text -> FilePath
chunkFilename EntryChunk _ _ = "entry.js"
chunkFilename LazyChunk (ChunkId cid) hash =
  Text.unpack ("chunk-" <> stripPrefix cid <> "-" <> hash <> ".js")
chunkFilename SharedChunk (ChunkId cid) hash =
  Text.unpack (cid <> "-" <> hash <> ".js")

-- | Strip the "lazy-" prefix from a chunk ID for filename use.
stripPrefix :: Text.Text -> Text.Text
stripPrefix cid =
  maybe cid id (Text.stripPrefix "lazy-" cid)

-- | Check if a chunk output is the entry chunk.
isEntry :: ChunkOutput -> Bool
isEntry co = _coKind co == EntryChunk

-- | Find the entry filename from outputs.
entryFilename :: [ChunkOutput] -> Builder
entryFilename outputs =
  case filter isEntry outputs of
    (co : _) -> B.stringUtf8 (_coFilename co)
    [] -> "entry.js"

-- | Format a single chunk entry for the JSON manifest.
chunkEntry :: ChunkOutput -> Builder
chunkEntry co =
  jsonField (chunkIdText co) (B.stringUtf8 (_coFilename co)) False

-- | Format a manifest entry for the inline JS object.
manifestEntry :: ChunkOutput -> Builder
manifestEntry co =
  "\"" <> B.stringUtf8 (Text.unpack (chunkIdText' co)) <> "\":\""
    <> B.stringUtf8 (_coFilename co)
    <> "\""

-- | Extract chunk ID text from a ChunkOutput.
chunkIdText :: ChunkOutput -> Builder
chunkIdText co =
  let ChunkId cid = _coChunkId co
   in B.stringUtf8 (Text.unpack cid)

-- | Extract chunk ID as Text.
chunkIdText' :: ChunkOutput -> Text.Text
chunkIdText' co =
  let ChunkId cid = _coChunkId co in cid

-- | Format a JSON key-value pair.
jsonField :: Builder -> Builder -> Bool -> Builder
jsonField key value isFirst =
  (if isFirst then "" else ",")
    <> "\""
    <> key
    <> "\":\""
    <> value
    <> "\""

-- | Intersperse commas between builders.
zipCommas :: [Builder] -> [Builder]
zipCommas [] = []
zipCommas [x] = [x]
zipCommas (x : xs) = (x <> ",") : zipCommas xs

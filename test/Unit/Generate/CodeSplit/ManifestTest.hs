{-# LANGUAGE OverloadedStrings #-}

-- | Tests for chunk manifest generation.
--
-- Validates JSON manifest output, content hashing, filename generation,
-- and manifest assignment for inline embedding.
--
-- @since 0.19.2
module Unit.Generate.CodeSplit.ManifestTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.Text as Text
import Generate.JavaScript.CodeSplit.Manifest
  ( chunkFilename,
    contentHash,
    generateManifest,
    generateManifestAssignment,
  )
import Generate.JavaScript.CodeSplit.Types
  ( ChunkId (..),
    ChunkKind (..),
    ChunkOutput (..),
  )
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.CodeSplit.Manifest"
    [ contentHashTests
    , chunkFilenameTests
    , manifestTests
    , manifestAssignmentTests
    ]

-- HELPER

-- | Render a builder to a string.
renderBuilder :: BB.Builder -> String
renderBuilder = LChar8.unpack . BB.toLazyByteString

-- | Create a test chunk output.
mkChunkOutput :: ChunkKind -> String -> String -> String -> ChunkOutput
mkChunkOutput kind chunkIdStr hashStr filename =
  ChunkOutput
    { _coChunkId = ChunkId (Text.pack chunkIdStr)
    , _coKind = kind
    , _coBuilder = BB.stringUtf8 "test content"
    , _coHash = Text.pack hashStr
    , _coFilename = filename
    }

-- CONTENT HASH TESTS

contentHashTests :: TestTree
contentHashTests =
  testGroup
    "contentHash"
    [ testCase "produces 8-character hash" $ do
        let hash = contentHash (BB.stringUtf8 "hello world")
        Text.length hash @?= 8
    , testCase "deterministic: same input same hash" $ do
        let input = BB.stringUtf8 "test content for hashing"
            hash1 = contentHash input
            hash2 = contentHash input
        hash1 @?= hash2
    , testCase "different inputs produce different hashes" $ do
        let hash1 = contentHash (BB.stringUtf8 "input A")
            hash2 = contentHash (BB.stringUtf8 "input B")
        assertBool "different hashes for different inputs" (hash1 /= hash2)
    , testCase "hash is hex characters" $ do
        let hash = contentHash (BB.stringUtf8 "some content")
            isHexChar c = c `elem` ("0123456789abcdef" :: String)
        all isHexChar (Text.unpack hash) @?= True
    , testCase "empty input produces valid hash" $ do
        let hash = contentHash mempty
        Text.length hash @?= 8
    ]

-- CHUNK FILENAME TESTS

chunkFilenameTests :: TestTree
chunkFilenameTests =
  testGroup
    "chunkFilename"
    [ testCase "entry chunk filename is entry.js" $
        chunkFilename EntryChunk (ChunkId "entry") "abcd1234" @?= "entry.js"
    , testCase "lazy chunk uses chunk- prefix with hash" $
        chunkFilename LazyChunk (ChunkId "lazy-Dashboard") "a1b2c3d4"
          @?= "chunk-Dashboard-a1b2c3d4.js"
    , testCase "shared chunk uses ID with hash" $
        chunkFilename SharedChunk (ChunkId "shared-0") "e5f6a7b8"
          @?= "shared-0-e5f6a7b8.js"
    , testCase "lazy chunk strips lazy- prefix" $
        chunkFilename LazyChunk (ChunkId "lazy-Settings") "00112233"
          @?= "chunk-Settings-00112233.js"
    , testCase "entry chunk ignores hash" $
        chunkFilename EntryChunk (ChunkId "entry") "ffffffff" @?= "entry.js"
    ]

-- MANIFEST TESTS

manifestTests :: TestTree
manifestTests =
  testGroup
    "generateManifest"
    [ testCase "entry-only manifest has correct structure" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            manifest = renderBuilder (generateManifest outputs)
        manifest @?= "{\"entry\":\"entry.js\",\"chunks\":{}}"
    , testCase "entry plus lazy chunk manifest includes chunk" $ do
        let outputs =
              [ mkChunkOutput EntryChunk "entry" "abc" "entry.js"
              , mkChunkOutput LazyChunk "lazy-Dash" "def" "chunk-Dash-def.js"
              ]
            manifest = renderBuilder (generateManifest outputs)
        manifest @?= "{\"entry\":\"entry.js\",\"chunks\":{,\"lazy-Dash\":\"chunk-Dash-def.js\"}}"
    , testCase "manifest starts with open brace" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            manifest = renderBuilder (generateManifest outputs)
        case manifest of { ('{':_) -> pure (); _ -> assertFailure "expected { at start" }
    , testCase "manifest ends with close brace" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            manifest = renderBuilder (generateManifest outputs)
        last manifest @?= '}'
    , testCase "manifest includes two lazy chunk filenames" $ do
        let outputs =
              [ mkChunkOutput EntryChunk "entry" "abc" "entry.js"
              , mkChunkOutput LazyChunk "lazy-A" "111" "chunk-A-111.js"
              , mkChunkOutput LazyChunk "lazy-B" "222" "chunk-B-222.js"
              ]
            manifest = renderBuilder (generateManifest outputs)
        manifest
          @?= "{\"entry\":\"entry.js\",\"chunks\":{,\"lazy-A\":\"chunk-A-111.js\",\
              \,\"lazy-B\":\"chunk-B-222.js\"}}"
    , testCase "entry-only manifest has empty chunks" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            manifest = renderBuilder (generateManifest outputs)
        manifest @?= "{\"entry\":\"entry.js\",\"chunks\":{}}"
    ]

-- MANIFEST ASSIGNMENT TESTS

manifestAssignmentTests :: TestTree
manifestAssignmentTests =
  testGroup
    "generateManifestAssignment"
    [ testCase "entry-only produces empty object assignment" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            assignment = renderBuilder (generateManifestAssignment outputs)
        assignment @?= "__canopy_manifest = {};\n"
    , testCase "entry plus lazy chunk assignment includes chunk mapping" $ do
        let outputs =
              [ mkChunkOutput EntryChunk "entry" "abc" "entry.js"
              , mkChunkOutput LazyChunk "lazy-X" "def" "chunk-X-def.js"
              ]
            assignment = renderBuilder (generateManifestAssignment outputs)
        assignment @?= "__canopy_manifest = {\"lazy-X\":\"chunk-X-def.js\"};\n"
    , testCase "assignment starts with __canopy_manifest =" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            assignment = renderBuilder (generateManifestAssignment outputs)
        take 23 assignment @?= "__canopy_manifest = {};"
    ]

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
        assertBool "all hex chars" (all isHexChar (Text.unpack hash))
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
    [ testCase "manifest contains entry field" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            manifest = renderBuilder (generateManifest outputs)
        assertBool "contains entry" ("\"entry\":" `isSubsequenceOf` manifest)
    , testCase "manifest contains chunks field" $ do
        let outputs =
              [ mkChunkOutput EntryChunk "entry" "abc" "entry.js"
              , mkChunkOutput LazyChunk "lazy-Dash" "def" "chunk-Dash-def.js"
              ]
            manifest = renderBuilder (generateManifest outputs)
        assertBool "contains chunks" ("\"chunks\":" `isSubsequenceOf` manifest)
    , testCase "manifest starts with open brace" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            manifest = renderBuilder (generateManifest outputs)
        case manifest of
          (c : _) -> c @?= '{'
          [] -> assertFailure "empty manifest"
    , testCase "manifest ends with close brace" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            manifest = renderBuilder (generateManifest outputs)
        assertBool "ends with }" (not (null manifest) && Prelude.last manifest == '}')
    , testCase "manifest includes all lazy chunk filenames" $ do
        let outputs =
              [ mkChunkOutput EntryChunk "entry" "abc" "entry.js"
              , mkChunkOutput LazyChunk "lazy-A" "111" "chunk-A-111.js"
              , mkChunkOutput LazyChunk "lazy-B" "222" "chunk-B-222.js"
              ]
            manifest = renderBuilder (generateManifest outputs)
        assertBool "contains chunk-A" ("chunk-A-111.js" `isSubsequenceOf` manifest)
        assertBool "contains chunk-B" ("chunk-B-222.js" `isSubsequenceOf` manifest)
    , testCase "entry-only manifest has empty chunks" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            manifest = renderBuilder (generateManifest outputs)
        assertBool "has chunks field" ("\"chunks\":{}" `isSubsequenceOf` manifest)
    ]

-- | Check if all characters of needle appear in order in haystack.
isSubsequenceOf :: String -> String -> Bool
isSubsequenceOf [] _ = True
isSubsequenceOf _ [] = False
isSubsequenceOf (x:xs) (y:ys)
  | x == y = isSubsequenceOf xs ys
  | otherwise = isSubsequenceOf (x:xs) ys

-- MANIFEST ASSIGNMENT TESTS

manifestAssignmentTests :: TestTree
manifestAssignmentTests =
  testGroup
    "generateManifestAssignment"
    [ testCase "starts with __canopy_manifest =" $ do
        let outputs =
              [ mkChunkOutput EntryChunk "entry" "abc" "entry.js"
              , mkChunkOutput LazyChunk "lazy-X" "def" "chunk-X-def.js"
              ]
            assignment = renderBuilder (generateManifestAssignment outputs)
        assertBool "starts with manifest assignment"
          ("__canopy_manifest = " `isSubsequenceOf` assignment)
    , testCase "ends with semicolon and newline" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            assignment = renderBuilder (generateManifestAssignment outputs)
        assertBool "ends with semicolon" (";\n" `isSubsequenceOf` assignment)
    , testCase "entry-only has empty manifest object" $ do
        let outputs = [mkChunkOutput EntryChunk "entry" "abc" "entry.js"]
            assignment = renderBuilder (generateManifestAssignment outputs)
        assertBool "empty object" ("= {};" `isSubsequenceOf` assignment)
    ]

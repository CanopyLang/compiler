{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for reproducible build verification.
--
-- Tests the content hashing, builder comparison, and divergence
-- detection logic used by the @--verify-reproducible@ flag.
--
-- @since 0.19.2
module Unit.Make.ReproducibleTest (tests) where

import qualified Data.ByteString.Builder as Builder
import qualified Make.Reproducible as Reproducible
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase)

-- | All reproducible build verification tests.
tests :: TestTree
tests =
  testGroup
    "Reproducible Build Verification"
    [ testBuilderComparison,
      testContentHashing,
      testFormatting
    ]

-- | Test byte-for-byte comparison of builders.
testBuilderComparison :: TestTree
testBuilderComparison =
  testGroup
    "builder comparison"
    [ testCase "identical builders pass verification" $ do
        let b1 = Builder.stringUtf8 "hello world"
            b2 = Builder.stringUtf8 "hello world"
        result <- Reproducible.verifyBuilderReproducibility b1 b2
        assertEqual "identical builders should match" Nothing result,
      testCase "empty builders pass verification" $ do
        let b1 = mempty
            b2 = mempty
        result <- Reproducible.verifyBuilderReproducibility b1 b2
        assertEqual "empty builders should match" Nothing result,
      testCase "different builders fail with offset" $ do
        let b1 = Builder.stringUtf8 "hello world"
            b2 = Builder.stringUtf8 "hello earth"
        result <- Reproducible.verifyBuilderReproducibility b1 b2
        assertEqual "divergence should be at byte 6" (Just 6) result,
      testCase "prefix mismatch detected at first byte" $ do
        let b1 = Builder.stringUtf8 "abc"
            b2 = Builder.stringUtf8 "xyz"
        result <- Reproducible.verifyBuilderReproducibility b1 b2
        assertEqual "divergence should be at byte 0" (Just 0) result,
      testCase "different length builders detected" $ do
        let b1 = Builder.stringUtf8 "short"
            b2 = Builder.stringUtf8 "short and long"
        result <- Reproducible.verifyBuilderReproducibility b1 b2
        assertBool "should detect length difference" (result /= Nothing),
      testCase "large identical builders pass" $ do
        let content = replicate 10000 'x'
            b1 = Builder.stringUtf8 content
            b2 = Builder.stringUtf8 content
        result <- Reproducible.verifyBuilderReproducibility b1 b2
        assertEqual "large identical builders should match" Nothing result,
      testCase "divergence at end of large builder" $ do
        let base = replicate 9999 'x'
            b1 = Builder.stringUtf8 (base <> "a")
            b2 = Builder.stringUtf8 (base <> "b")
        result <- Reproducible.verifyBuilderReproducibility b1 b2
        assertEqual "divergence should be at byte 9999" (Just 9999) result,
      testCase "concatenated builders compare correctly" $ do
        let b1 = Builder.stringUtf8 "hello" <> Builder.stringUtf8 " world"
            b2 = Builder.stringUtf8 "hello world"
        result <- Reproducible.verifyBuilderReproducibility b1 b2
        assertEqual "equivalent concatenated builders should match" Nothing result
    ]

-- | Test content hashing produces consistent results.
testContentHashing :: TestTree
testContentHashing =
  testGroup
    "content hashing"
    [ testCase "same content produces same hash" $ do
        let b1 = Builder.stringUtf8 "deterministic content"
            b2 = Builder.stringUtf8 "deterministic content"
        assertEqual "same content should hash identically"
          (Reproducible.hashBuilder b1)
          (Reproducible.hashBuilder b2),
      testCase "different content produces different hash" $ do
        let b1 = Builder.stringUtf8 "content A"
            b2 = Builder.stringUtf8 "content B"
        assertBool "different content should hash differently"
          (Reproducible.hashBuilder b1 /= Reproducible.hashBuilder b2),
      testCase "hash has sha256: prefix" $ do
        let b = Builder.stringUtf8 "test"
            hash = Reproducible.hashBuilder b
        assertBool "hash should start with sha256:"
          (take 7 hash == "sha256:"),
      testCase "hash has correct length" $ do
        let b = Builder.stringUtf8 "test"
            hash = Reproducible.hashBuilder b
        -- sha256: prefix (7) + 64 hex chars = 71
        assertEqual "hash should be 71 chars (sha256: + 64 hex)" 71 (length hash),
      testCase "empty content has a valid hash" $ do
        let b = mempty
            hash = Reproducible.hashBuilder b
        assertBool "empty content should still have sha256: prefix"
          (take 7 hash == "sha256:"),
      testCase "hash is deterministic across calls" $ do
        let content = "some arbitrary content for hashing"
            hash1 = Reproducible.hashBuilder (Builder.stringUtf8 content)
            hash2 = Reproducible.hashBuilder (Builder.stringUtf8 content)
        assertEqual "hash should be deterministic" hash1 hash2
    ]

-- | Test formatting of content hash strings.
testFormatting :: TestTree
testFormatting =
  testGroup
    "content hash formatting"
    [ testCase "formatContentHash adds prefix" $ do
        let result = Reproducible.formatContentHash "abc123"
        assertEqual "should add sha256: prefix" "sha256:abc123" result,
      testCase "formatContentHash with empty string" $ do
        let result = Reproducible.formatContentHash ""
        assertEqual "should just be prefix" "sha256:" result
    ]

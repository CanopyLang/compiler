
-- | Unit tests for Builder.Hash module.
--
-- Tests content hashing functionality including file hashing,
-- string hashing, and dependency hashing.
--
-- @since 0.19.1
module Unit.Builder.HashTest (tests) where

import qualified Builder.Hash as Hash
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified System.IO
import System.IO (Handle)
import System.IO.Temp (withSystemTempFile)
import Test.Tasty
import Test.Tasty.HUnit

-- Helper to create test module names
mkName :: String -> Name.Name
mkName = Name.fromChars

tests :: TestTree
tests =
  testGroup
    "Builder.Hash Tests"
    [ testEmptyHash,
      testStringHashing,
      testBytesHashing,
      testFileHashing,
      testDependencyHashing,
      testHashComparison,
      testCollisionResistance,
      testDeterminism,
      testEdgeCaseInputs,
      testHexRoundTrip
    ]

testEmptyHash :: TestTree
testEmptyHash =
  testGroup
    "empty hash tests"
    [ testCase "empty hash has empty value" $
        Hash.toHexString (Hash.hashValue Hash.emptyHash) @?= "",
      testCase "empty hash has correct source" $
        Hash.hashSource Hash.emptyHash @?= "empty"
    ]

testStringHashing :: TestTree
testStringHashing =
  testGroup
    "string hashing tests"
    [ testCase "hash empty string" $ do
        let h = Hash.hashString ""
        Hash.toHexString (Hash.hashValue h) @?= "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      testCase "hash simple string" $ do
        let h = Hash.hashString "hello"
        Hash.toHexString (Hash.hashValue h) @?= "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
      testCase "hash different strings produce different hashes" $ do
        let h1 = Hash.hashString "hello"
        let h2 = Hash.hashString "world"
        Hash.hashValue h1 /= Hash.hashValue h2 @? "Different strings should have different hashes",
      testCase "hash same string produces same hash" $ do
        let h1 = Hash.hashString "test"
        let h2 = Hash.hashString "test"
        Hash.hashesEqual h1 h2 @? "Same string should produce same hash",
      testCase "hash source includes string descriptor" $
        Hash.hashSource (Hash.hashString "test") @?= "string"
    ]

testBytesHashing :: TestTree
testBytesHashing =
  testGroup
    "bytes hashing tests"
    [ testCase "hash empty bytes" $ do
        let h = Hash.hashBytes (BSC.pack "")
        Hash.toHexString (Hash.hashValue h) @?= "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      testCase "hash bytes produces same hash as string" $ do
        let hBytes = Hash.hashBytes (BSC.pack "hello")
        let hString = Hash.hashString "hello"
        Hash.hashesEqual hBytes hString @? "Bytes and string should produce same hash",
      testCase "hash source includes byte count" $ do
        let h = Hash.hashBytes (BSC.pack "test")
        "bytes:4 bytes" @=? Hash.hashSource h
    ]

testFileHashing :: TestTree
testFileHashing =
  testGroup
    "file hashing tests"
    [ testCase "hash file with content" $
        withSystemTempFile "test.txt" $ \path handle -> do
          BSC.hPutStr handle "test content"
          hClose handle
          h <- Hash.hashFile path
          Hash.hashValue h @?= Hash.hashValue (Hash.hashString "test content"),
      testCase "hash file source includes path" $
        withSystemTempFile "test.txt" $ \path handle -> do
          BSC.hPutStr handle "test"
          hClose handle
          h <- Hash.hashFile path
          ("file:" ++ path) @=? Hash.hashSource h,
      testCase "hash same file twice produces same hash" $
        withSystemTempFile "test.txt" $ \path handle -> do
          BSC.hPutStr handle "content"
          hClose handle
          h1 <- Hash.hashFile path
          h2 <- Hash.hashFile path
          Hash.hashesEqual h1 h2 @? "Same file should produce same hash"
    ]

testDependencyHashing :: TestTree
testDependencyHashing =
  testGroup
    "dependency hashing tests"
    [ testCase "hash empty dependencies" $ do
        let h = Hash.hashDependencies Map.empty
        Hash.hashSource h @?= "dependencies:0 modules",
      testCase "hash single dependency" $ do
        let modName = mkName "Main"
        let depHash = Hash.hashString "dep1"
        let deps = Map.singleton modName depHash
        let h = Hash.hashDependencies deps
        Hash.hashSource h @?= "dependencies:1 modules",
      testCase "hash multiple dependencies" $ do
        let modMain = mkName "Main"
        let modUtils = mkName "Utils"
        let h1 = Hash.hashString "dep1"
        let h2 = Hash.hashString "dep2"
        let deps = Map.fromList [(modMain, h1), (modUtils, h2)]
        let h = Hash.hashDependencies deps
        Hash.hashSource h @?= "dependencies:2 modules",
      testCase "same dependencies produce same hash" $ do
        let modName = mkName "Main"
        let depHash = Hash.hashString "dep1"
        let deps1 = Map.singleton modName depHash
        let deps2 = Map.singleton modName depHash
        let h1 = Hash.hashDependencies deps1
        let h2 = Hash.hashDependencies deps2
        Hash.hashesEqual h1 h2 @? "Same dependencies should produce same hash"
    ]

testHashComparison :: TestTree
testHashComparison =
  testGroup
    "hash comparison tests"
    [ testCase "hashesEqual with same hashes" $ do
        let h1 = Hash.hashString "test"
        let h2 = Hash.hashString "test"
        Hash.hashesEqual h1 h2 @? "Same hashes should be equal",
      testCase "hashesEqual with different hashes" $ do
        let h1 = Hash.hashString "test1"
        let h2 = Hash.hashString "test2"
        not (Hash.hashesEqual h1 h2) @? "Different hashes should not be equal",
      testCase "hashChanged with same hashes" $ do
        let h1 = Hash.hashString "test"
        let h2 = Hash.hashString "test"
        not (Hash.hashChanged h1 h2) @? "Same hashes should not be changed",
      testCase "hashChanged with different hashes" $ do
        let h1 = Hash.hashString "test1"
        let h2 = Hash.hashString "test2"
        Hash.hashChanged h1 h2 @? "Different hashes should be changed",
      testCase "showHash truncates and includes source" $ do
        let h = Hash.hashString "test"
        let shown = Hash.showHash h
        length shown < length (Hash.toHexString (Hash.hashValue h)) @? "showHash should truncate",
      testCase "showHash includes source description" $ do
        let h = Hash.hashString "test"
        let shown = Hash.showHash h
        shown @?= "9f86d081... (string)"
    ]

testCollisionResistance :: TestTree
testCollisionResistance =
  testGroup
    "hash collision resistance tests"
    [ testCase "similar strings produce different hashes" $ do
        let h1 = Hash.hashString "abc"
        let h2 = Hash.hashString "abd"
        not (Hash.hashesEqual h1 h2) @? "Similar strings should produce different hashes",
      testCase "prefix and full string produce different hashes" $ do
        let h1 = Hash.hashString "hello"
        let h2 = Hash.hashString "hello world"
        not (Hash.hashesEqual h1 h2) @? "Prefix should produce different hash from full string",
      testCase "permuted inputs produce different hashes" $ do
        let h1 = Hash.hashString "ab"
        let h2 = Hash.hashString "ba"
        not (Hash.hashesEqual h1 h2) @? "Permuted inputs should produce different hashes",
      testCase "extra whitespace changes hash" $ do
        let h1 = Hash.hashString "hello"
        let h2 = Hash.hashString "hello "
        not (Hash.hashesEqual h1 h2) @? "Trailing space should change hash",
      testCase "case change produces different hash" $ do
        let h1 = Hash.hashString "Hello"
        let h2 = Hash.hashString "hello"
        not (Hash.hashesEqual h1 h2) @? "Case difference should change hash"
    ]

testDeterminism :: TestTree
testDeterminism =
  testGroup
    "hash determinism tests"
    [ testCase "hashing same string twice gives equal hashes" $ do
        let h1 = Hash.hashString "deterministic"
        let h2 = Hash.hashString "deterministic"
        Hash.hashesEqual h1 h2 @? "Hash must be deterministic",
      testCase "hashing same bytes twice gives equal hashes" $ do
        let h1 = Hash.hashBytes (BSC.pack "bytes-test")
        let h2 = Hash.hashBytes (BSC.pack "bytes-test")
        Hash.hashesEqual h1 h2 @? "Bytes hash must be deterministic",
      testCase "hashing empty string is deterministic" $ do
        let h1 = Hash.hashString ""
        let h2 = Hash.hashString ""
        Hash.hashesEqual h1 h2 @? "Empty string hash must be deterministic",
      testCase "hashing empty bytes is deterministic" $ do
        let h1 = Hash.hashBytes (BSC.pack "")
        let h2 = Hash.hashBytes (BSC.pack "")
        Hash.hashesEqual h1 h2 @? "Empty bytes hash must be deterministic"
    ]

testEdgeCaseInputs :: TestTree
testEdgeCaseInputs =
  testGroup
    "edge case input tests"
    [ testCase "empty string hash value is non-empty hex" $ do
        let h = Hash.hashString ""
        let hex = Hash.toHexString (Hash.hashValue h)
        not (null hex) @? "Empty input hash should produce non-empty hex",
      testCase "large input can be hashed" $ do
        let large = concat (replicate 1000 "abcdefghijklmnopqrstuvwxyz")
        let h = Hash.hashString large
        let hex = Hash.toHexString (Hash.hashValue h)
        not (null hex) @? "Large input should produce a hash",
      testCase "large input hash differs from small input hash" $ do
        let large = concat (replicate 1000 "a")
        let h1 = Hash.hashString "a"
        let h2 = Hash.hashString large
        not (Hash.hashesEqual h1 h2) @? "Large and small inputs should differ",
      testCase "single character hash is deterministic" $ do
        let h1 = Hash.hashString "x"
        let h2 = Hash.hashString "x"
        Hash.hashesEqual h1 h2 @? "Single-char hash must be deterministic"
    ]

testHexRoundTrip :: TestTree
testHexRoundTrip =
  testGroup
    "hex round-trip tests"
    [ testCase "toHexString of empty hash is known constant" $ do
        let hex = Hash.toHexString (Hash.hashValue Hash.emptyHash)
        hex @?= "",
      testCase "hex output of string hash matches known SHA-256 for empty string" $ do
        let h = Hash.hashString ""
        let hex = Hash.toHexString (Hash.hashValue h)
        hex @?= "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      testCase "hex output of hello has correct length" $ do
        let h = Hash.hashString "hello"
        let hex = Hash.toHexString (Hash.hashValue h)
        length hex @?= 64,
      testCase "hex characters are all valid hex digits" $ do
        let h = Hash.hashString "round-trip-test"
        let hex = Hash.toHexString (Hash.hashValue h)
        all (\c -> c `elem` ("0123456789abcdef" :: String)) hex @?= True
    ]

hClose :: Handle -> IO ()
hClose = System.IO.hClose

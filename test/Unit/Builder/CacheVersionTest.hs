{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the ELCO versioned binary cache format.
--
-- Validates that the magic header, schema version, and compiler version
-- are correctly encoded and decoded, and that version mismatches produce
-- clear error messages.
--
-- @since 0.19.2
module Unit.Builder.CacheVersionTest (tests) where

import qualified Compiler
import qualified Data.Binary as Binary
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word16)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Builder.CacheVersion"
    [ testGroup
        "ELCO header"
        [ testCase "magic bytes are ELCO" $
            LBS.take 4 (Compiler.encodeVersioned (42 :: Int)) @?= LBS.pack [0x45, 0x4C, 0x43, 0x4F],
          testCase "header is at least 12 bytes" $
            assertBool
              "header should be at least 12 bytes before payload"
              (LBS.length (Compiler.encodeVersioned (0 :: Int)) >= 12)
        ],
      testGroup
        "round-trip"
        [ testCase "Int round-trips through versioned format" $ do
            let original = 12345 :: Int
                encoded = Compiler.encodeVersioned original
            case Compiler.decodeVersioned encoded of
              Left msg -> assertFailure ("decode failed: " ++ msg)
              Right decoded -> decoded @?= original,
          testCase "String round-trips through versioned format" $ do
            let original = "hello world" :: String
                encoded = Compiler.encodeVersioned original
            case Compiler.decodeVersioned encoded of
              Left msg -> assertFailure ("decode failed: " ++ msg)
              Right decoded -> decoded @?= original,
          testCase "tuple round-trips through versioned format" $ do
            let original = (True, 42 :: Int, "test" :: String)
                encoded = Compiler.encodeVersioned original
            case Compiler.decodeVersioned encoded of
              Left msg -> assertFailure ("decode failed: " ++ msg)
              Right decoded -> decoded @?= original
        ],
      testGroup
        "error cases"
        [ testCase "empty bytes fail with too-short message" $
            case Compiler.decodeVersioned LBS.empty :: Either String Int of
              Left msg -> assertBool "should mention too short" ("too short" `isInfixOfStr` msg)
              Right _ -> assertFailure "should fail on empty bytes",
          testCase "wrong magic fails" $
            case Compiler.decodeVersioned (LBS.pack [0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) :: Either String Int of
              Left msg -> assertBool "should mention magic" ("magic" `isInfixOfStr` msg)
              Right _ -> assertFailure "should fail on wrong magic",
          testCase "wrong schema version fails with actionable message" $ do
            -- Construct bytes with correct magic but wrong schema version (99)
            let wrongVersion =
                  LBS.pack [0x45, 0x4C, 0x43, 0x4F] -- ELCO magic
                    <> Binary.encode (99 :: Word16) -- wrong schema
                    <> Binary.encode (0 :: Word16) -- major
                    <> Binary.encode (0 :: Word16) -- minor
                    <> Binary.encode (0 :: Word16) -- patch
                    <> Binary.encode (42 :: Int) -- payload
            case Compiler.decodeVersioned wrongVersion :: Either String Int of
              Left msg -> do
                assertBool "should mention schema" ("schema" `isInfixOfStr` msg)
                assertBool "should mention rebuild" ("rebuild" `isInfixOfStr` msg)
              Right _ -> assertFailure "should fail on wrong schema version",
          testCase "truncated header fails" $
            case Compiler.decodeVersioned (LBS.pack [0x45, 0x4C, 0x43, 0x4F, 0x00]) :: Either String Int of
              Left _ -> pure ()
              Right _ -> assertFailure "should fail on truncated header"
        ]
    ]

-- | Check if needle appears in haystack (String version).
isInfixOfStr :: String -> String -> Bool
isInfixOfStr needle haystack = any (isPrefixOfStr needle) (tails haystack)

isPrefixOfStr :: String -> String -> Bool
isPrefixOfStr [] _ = True
isPrefixOfStr _ [] = False
isPrefixOfStr (x : xs) (y : ys)
  | x == y = isPrefixOfStr xs ys
  | otherwise = False

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_ : rest) = xs : tails rest

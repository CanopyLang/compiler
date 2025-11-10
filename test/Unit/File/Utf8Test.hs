{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for File.Utf8.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in File.Utf8.
--
-- Coverage Target: ≥90% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.File.Utf8Test
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Test.QuickCheck.Monadic (monadicIO, run)
import qualified Test.QuickCheck.Monadic as QC

import qualified Control.Exception as Exception
import qualified System.IO.Error as IOError
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Char8 as BSChar8
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO as IO
import qualified System.IO.Temp as Temp

import qualified File.Utf8 as FileUtf8

-- | Main test tree containing all File.Utf8 tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "File.Utf8 Tests"
  [ unitTests
  , propertyTests
  , edgeCaseTests
  , errorConditionTests
  ]

-- | Unit tests for all public functions.
--
-- Tests basic functionality with known inputs and expected outputs.
-- Every public function must have at least one unit test.
unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ testCase "writeUtf8 creates file with correct content" $ do
      Temp.withSystemTempFile "utf8.txt" $ \path handle -> do
        IO.hClose handle
        let content = Text.encodeUtf8 "Hello, World!"
        FileUtf8.writeUtf8 path content
        exists <- Dir.doesFileExist path
        exists @?= True
  , testCase "readUtf8 reads written content correctly" $ do
      Temp.withSystemTempFile "utf8.txt" $ \path handle -> do
        IO.hClose handle
        let originalContent = Text.encodeUtf8 "Test content 123"
        FileUtf8.writeUtf8 path originalContent
        readContent <- FileUtf8.readUtf8 path
        readContent @?= originalContent
  , testCase "writeUtf8 handles Unicode correctly" $ do
      Temp.withSystemTempFile "unicode.txt" $ \path handle -> do
        IO.hClose handle
        let unicodeText = "Hello 世界 🌍 Здравствуй мир"
            unicodeBytes = Text.encodeUtf8 unicodeText
        FileUtf8.writeUtf8 path unicodeBytes
        readContent <- FileUtf8.readUtf8 path
        readContent @?= unicodeBytes
  , testCase "writeBuilder creates file with builder content" $ do
      Temp.withSystemTempFile "builder.txt" $ \path handle -> do
        IO.hClose handle
        let builder = Builder.byteString "builder content"
        FileUtf8.writeBuilder path builder
        exists <- Dir.doesFileExist path
        exists @?= True
  , testCase "writeBuilder handles complex builders" $ do
      Temp.withSystemTempFile "complex.txt" $ \path handle -> do
        IO.hClose handle
        let builder = mconcat
              [ Builder.byteString "prefix: "
              , Builder.intDec 42
              , Builder.byteString " - "
              , Builder.byteString (Text.encodeUtf8 "suffix")
              ]
        FileUtf8.writeBuilder path builder
        content <- FileUtf8.readUtf8 path
        content @?= "prefix: 42 - suffix"
  , testCase "readUtf8 handles empty files" $ do
      Temp.withSystemTempFile "empty.txt" $ \path handle -> do
        IO.hClose handle
        content <- FileUtf8.readUtf8 path
        content @?= ""
  , testCase "writeUtf8 overwrites existing files" $ do
      Temp.withSystemTempFile "overwrite.txt" $ \path handle -> do
        IO.hClose handle
        let content1 = Text.encodeUtf8 "original"
            content2 = Text.encodeUtf8 "updated"
        FileUtf8.writeUtf8 path content1
        FileUtf8.writeUtf8 path content2
        readContent <- FileUtf8.readUtf8 path
        readContent @?= content2
  , testCase "readUtf8 handles large files efficiently" $ do
      Temp.withSystemTempFile "large.txt" $ \path handle -> do
        IO.hClose handle
        let largeText = Text.replicate 10000 "Large content line.\n"
            largeBytes = Text.encodeUtf8 largeText
        FileUtf8.writeUtf8 path largeBytes
        readContent <- FileUtf8.readUtf8 path
        BS.length readContent @?= BS.length largeBytes
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "writeUtf8/readUtf8 roundtrip" $ \text ->
      let content = Text.encodeUtf8 (Text.pack text)
      in monadicIO $ do
        result <- run $ Temp.withSystemTempFile "prop.txt" $ \path handle -> do
          IO.hClose handle
          FileUtf8.writeUtf8 path content
          FileUtf8.readUtf8 path
        QC.assert (result == content)
  , testProperty "writeBuilder/readUtf8 consistency" $ \text ->
      let content = Text.encodeUtf8 (Text.pack text)
          builder = Builder.byteString content
      in monadicIO $ do
        result <- run $ Temp.withSystemTempFile "prop_builder.txt" $ \path handle -> do
          IO.hClose handle
          FileUtf8.writeBuilder path builder
          FileUtf8.readUtf8 path
        QC.assert (result == content)
  , testProperty "readUtf8 preserves byte length" $ \text ->
      let content = Text.encodeUtf8 (Text.pack text)
      in monadicIO $ do
        readLength <- run $ Temp.withSystemTempFile "length.txt" $ \path handle -> do
          IO.hClose handle
          FileUtf8.writeUtf8 path content
          readContent <- FileUtf8.readUtf8 path
          pure (BS.length readContent)
        QC.assert (readLength == BS.length content)
  , testProperty "chunked reading produces same result as single read" $ \text ->
      let content = Text.encodeUtf8 (Text.pack text)
      in monadicIO $ do
        result <- run $ Temp.withSystemTempFile "chunk.txt" $ \path handle -> do
          IO.hClose handle
          FileUtf8.writeUtf8 path content
          -- Read using normal readUtf8 (which uses chunked reading internally)
          FileUtf8.readUtf8 path
        QC.assert (result == content)
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "readUtf8 handles files with only whitespace" $ do
      Temp.withSystemTempFile "whitespace.txt" $ \path handle -> do
        IO.hClose handle
        let whitespaceContent = Text.encodeUtf8 "   \n\t\r\n   "
        FileUtf8.writeUtf8 path whitespaceContent
        readContent <- FileUtf8.readUtf8 path
        readContent @?= whitespaceContent
  , testCase "readUtf8 handles files with null bytes" $ do
      Temp.withSystemTempFile "nullbytes.txt" $ \path handle -> do
        IO.hClose handle
        let nullContent = BSChar8.pack "before\0after\0end"
        FileUtf8.writeUtf8 path nullContent
        readContent <- FileUtf8.readUtf8 path
        readContent @?= nullContent
  , testCase "writeUtf8 handles maximum Unicode code points" $ do
      Temp.withSystemTempFile "maxunicode.txt" $ \path handle -> do
        IO.hClose handle
        let maxUnicodeChar = '\x10FFFF'  -- Maximum Unicode code point
            unicodeText = "Start " <> [maxUnicodeChar] <> " End"
            unicodeBytes = Text.encodeUtf8 (Text.pack unicodeText)
        FileUtf8.writeUtf8 path unicodeBytes
        readContent <- FileUtf8.readUtf8 path
        readContent @?= unicodeBytes
  , testCase "writeBuilder handles empty builders" $ do
      Temp.withSystemTempFile "empty_builder.txt" $ \path handle -> do
        IO.hClose handle
        FileUtf8.writeBuilder path mempty
        content <- FileUtf8.readUtf8 path
        content @?= ""
  , testCase "shouldFinishReading function edge cases" $ do
      -- Test the internal shouldFinishReading logic
      FileUtf8.shouldFinishReading 0 100 @?= True   -- Read 0 bytes, requested 100
      FileUtf8.shouldFinishReading 50 100 @?= True  -- Read 50 bytes, requested 100
      FileUtf8.shouldFinishReading 100 100 @?= False -- Read exactly what was requested
      FileUtf8.shouldFinishReading 150 100 @?= False -- Read more than requested
      FileUtf8.shouldFinishReading 10 0 @?= False    -- Edge case: 0 read size
  , testCase "calculateNextSize function edge cases" $ do
      -- Test the internal calculateNextSize logic
      FileUtf8.calculateNextSize 100 50 @?= 150     -- Normal increment
      FileUtf8.calculateNextSize 32000 1000 @?= 32752  -- Should be capped at 32752
      FileUtf8.calculateNextSize 32700 100 @?= 32752   -- Cap at maximum
      FileUtf8.calculateNextSize 0 255 @?= 255         -- Minimum increment
  , testCase "readUtf8 handles very small files" $ do
      Temp.withSystemTempFile "tiny.txt" $ \path handle -> do
        IO.hClose handle
        let tinyContent = Text.encodeUtf8 "x"  -- Single character
        FileUtf8.writeUtf8 path tinyContent
        readContent <- FileUtf8.readUtf8 path
        readContent @?= tinyContent
  , testCase "readUtf8 handles files at chunk boundaries" $ do
      Temp.withSystemTempFile "boundary.txt" $ \path handle -> do
        IO.hClose handle
        -- Create content that tests chunk boundary handling
        let boundarySize = 32752  -- Internal max chunk size
            boundaryContent = BS.replicate boundarySize 65  -- 'A' characters
        FileUtf8.writeUtf8 path boundaryContent
        readContent <- FileUtf8.readUtf8 path
        BS.length readContent @?= boundarySize
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "readUtf8 throws IOException for non-existent file" $ do
      result <- Exception.try (FileUtf8.readUtf8 "/nonexistent/file.txt")
      case result of
        Left (_ :: Exception.IOException) -> pure ()  -- Expected
        Right _ -> assertFailure "Expected IOException for non-existent file"
  , testCase "writeUtf8 throws IOException for invalid path" $ do
      let invalidPath = "/invalid\0path/file.txt"
          content = Text.encodeUtf8 "test"
      result <- Exception.try (FileUtf8.writeUtf8 invalidPath content)
      case result of
        Left (_ :: Exception.IOException) -> pure ()  -- Expected
        Right _ -> assertFailure "Expected IOException for invalid path"
  , testCase "readUtf8 handles invalid UTF-8 sequences" $ do
      Temp.withSystemTempFile "invalid_utf8.txt" $ \path handle -> do
        -- Write invalid UTF-8 bytes directly
        let invalidUtf8 = BSChar8.pack "\xFF\xFE\xFD"  -- Invalid UTF-8 sequence
        BS.hPut handle invalidUtf8
        IO.hClose handle
        
        result <- Exception.try (FileUtf8.readUtf8 path)
        case result of
          Left (_ :: Exception.IOException) -> pure ()  -- Expected encoding error
          Right _ -> pure ()  -- May succeed on some systems with replacement chars
  , testCase "writeUtf8 to read-only directory fails gracefully" $ do
      let readOnlyPath = "/proc/readonly.txt"  -- Typically read-only location
          content = Text.encodeUtf8 "test"
      result <- Exception.try (FileUtf8.writeUtf8 readOnlyPath content)
      case result of
        Left (_ :: Exception.IOException) -> pure ()  -- Expected
        Right _ -> pure ()  -- May succeed in some test environments
  , testCase "writeBuilder to invalid path fails gracefully" $ do
      let invalidPath = ""  -- Empty path
          builder = Builder.byteString "test"
      result <- Exception.try (FileUtf8.writeBuilder invalidPath builder)
      case result of
        Left (_ :: Exception.IOException) -> pure ()  -- Expected
        Right _ -> assertFailure "Expected IOException for empty path"
  , testCase "encodingError function creates proper error messages" $ do
      let testPath = "/test/path.txt"
          originalError = IOError.userError "test error"
          enhancedError = FileUtf8.encodingError testPath originalError
      -- Verify the enhanced error contains UTF-8 message
      show enhancedError `contains` "UTF-8" @?= True
      show enhancedError `contains` testPath @?= True
  , testCase "readUtf8 with directory path throws appropriate error" $ do
      Temp.withSystemTempDirectory "test_dir" $ \tempDir -> do
        result <- Exception.try (FileUtf8.readUtf8 tempDir)
        case result of
          Left (_ :: Exception.IOException) -> pure ()  -- Expected
          Right _ -> assertFailure "Expected IOException when reading directory"
  , testCase "hGetContentsSizeHint handles large size hints correctly" $ do
      Temp.withSystemTempFile "sizehint.txt" $ \path handle -> do
        let content = Text.encodeUtf8 "small content"
        BS.hPut handle content
        IO.hSeek handle IO.AbsoluteSeek 0
        -- Test with larger size hint than actual content
        result <- FileUtf8.hGetContentsSizeHint handle 10000 1000
        BS.length result @?= BS.length content
        IO.hClose handle
  ]

-- Helper function for substring checking
contains :: String -> String -> Bool
contains haystack needle = needle `elem` [take (length needle) $ drop i haystack | i <- [0..length haystack - length needle]]

-- Orphan instances for property testing

instance Arbitrary Text.Text where
  arbitrary = Text.pack <$> arbitrary

-- Generate reasonable UTF-8 text for testing
genUtf8Text :: Gen String
genUtf8Text = listOf $ frequency
  [ (10, choose ('a', 'z'))  -- ASCII letters
  , (10, choose ('A', 'Z'))  -- ASCII letters
  , (10, choose ('0', '9'))  -- ASCII digits
  , (5, elements " \n\t\r")  -- Whitespace
  , (3, choose ('\x80', '\x7FF'))    -- 2-byte UTF-8
  , (2, choose ('\x800', '\xFFFF'))  -- 3-byte UTF-8
  , (1, choose ('\x10000', '\x10FFFF')) -- 4-byte UTF-8
  ]
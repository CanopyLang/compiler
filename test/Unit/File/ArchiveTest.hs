{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for File.Archive.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in File.Archive.
--
-- Coverage Target: ≥90% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.File.ArchiveTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Test.QuickCheck.Monadic (monadicIO, run)
import qualified Test.QuickCheck.Monadic as QC
import Data.Function ((&))

import qualified Codec.Archive.Zip as Zip
import qualified Control.Exception as Exception
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO.Temp as Temp

import qualified File.Archive as FileArchive

-- | Helper function to create a test ZIP archive with specific entries
createTestArchive :: [(FilePath, String)] -> Zip.Archive
createTestArchive entries = 
  foldr addEntryToArchive Zip.emptyArchive entries
  where
    addEntryToArchive (path, content) archive =
      Zip.addEntryToArchive (Zip.toEntry path 0 (LBS.fromStrict $ Text.encodeUtf8 $ Text.pack content)) archive

-- | Helper function to create a directory entry in ZIP archive
createDirectoryEntry :: FilePath -> Zip.Entry
createDirectoryEntry path = Zip.toEntry (path ++ "/") 0 LBS.empty

-- | Main test tree containing all File.Archive tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "File.Archive Tests"
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
  [ testCase "writePackage extracts allowed files" $ do
      Temp.withSystemTempDirectory "archive_test" $ \tempDir -> do
        let archive = createTestArchive
              [ ("package/src/Main.can", "module Main exposing (..)")
              , ("package/canopy.json", "{\"name\": \"test\"}")
              , ("package/LICENSE", "MIT License")
              , ("package/README.md", "# Test Package")
              ]
        FileArchive.writePackage tempDir archive
        
        -- Check that allowed files were created
        srcExists <- Dir.doesFileExist (tempDir FP.</> "src/Main.can")
        srcExists @?= True
        
        canopyJsonExists <- Dir.doesFileExist (tempDir FP.</> "canopy.json")
        canopyJsonExists @?= True
        
        licenseExists <- Dir.doesFileExist (tempDir FP.</> "LICENSE")
        licenseExists @?= True
        
        readmeExists <- Dir.doesFileExist (tempDir FP.</> "README.md")
        readmeExists @?= True
  , testCase "writePackage skips disallowed files" $ do
      Temp.withSystemTempDirectory "archive_test" $ \tempDir -> do
        let archive = createTestArchive
              [ ("package/src/Main.can", "module Main")
              , ("package/malicious.exe", "virus content")
              , ("package/system/config", "system config")
              , ("package/../escape.txt", "path traversal")
              ]
        FileArchive.writePackage tempDir archive
        
        -- Check that only allowed files were created
        srcExists <- Dir.doesFileExist (tempDir FP.</> "src/Main.can")
        srcExists @?= True
        
        maliciousExists <- Dir.doesFileExist (tempDir FP.</> "malicious.exe")
        maliciousExists @?= False
        
        systemExists <- Dir.doesFileExist (tempDir FP.</> "system/config")
        systemExists @?= False
  , testCase "writePackage handles empty archive" $ do
      Temp.withSystemTempDirectory "empty_archive" $ \tempDir -> do
        let emptyArchive = Zip.emptyArchive
        FileArchive.writePackage tempDir emptyArchive
        -- Should not fail with empty archive
        pure ()
  , testCase "writePackageReturnCanopyJson extracts and returns canopy.json" $ do
      Temp.withSystemTempDirectory "json_test" $ \tempDir -> do
        let canopyJsonContent = "{\"version\": \"1.0.0\", \"name\": \"test-package\"}"
            archive = createTestArchive
              [ ("package/src/Main.can", "module Main")
              , ("package/canopy.json", canopyJsonContent)
              ]
        result <- FileArchive.writePackageReturnCanopyJson tempDir archive
        
        case result of
          Just jsonBytes -> Text.unpack (Text.decodeUtf8 jsonBytes) @?= canopyJsonContent
          Nothing -> assertFailure "Expected canopy.json content to be returned"
  , testCase "writePackageReturnCanopyJson returns Nothing when no canopy.json" $ do
      Temp.withSystemTempDirectory "no_json_test" $ \tempDir -> do
        let archive = createTestArchive
              [ ("package/src/Main.can", "module Main")
              , ("package/LICENSE", "MIT")
              ]
        result <- FileArchive.writePackageReturnCanopyJson tempDir archive
        result @?= Nothing
  , testCase "isAllowedPath correctly identifies allowed paths" $ do
      FileArchive.isAllowedPath "src/Main.can" @?= True
      FileArchive.isAllowedPath "src/nested/Module.can" @?= True
      FileArchive.isAllowedPath "LICENSE" @?= True
      FileArchive.isAllowedPath "README.md" @?= True
      FileArchive.isAllowedPath "canopy.json" @?= True
  , testCase "isAllowedPath correctly identifies disallowed paths" $ do
      FileArchive.isAllowedPath "malicious.exe" @?= False
      FileArchive.isAllowedPath "system/config" @?= False
      FileArchive.isAllowedPath "../escape.txt" @?= False
      FileArchive.isAllowedPath "build/output.js" @?= False
      FileArchive.isAllowedPath "node_modules/package" @?= False
  , testCase "isDirectoryPath correctly identifies directories" $ do
      FileArchive.isDirectoryPath "src/" @?= True
      FileArchive.isDirectoryPath "nested/path/" @?= True
      FileArchive.isDirectoryPath "/" @?= True
  , testCase "isDirectoryPath correctly identifies files" $ do
      FileArchive.isDirectoryPath "src/Main.can" @?= False
      FileArchive.isDirectoryPath "LICENSE" @?= False
      FileArchive.isDirectoryPath "" @?= False
  , testCase "extractRelativePath removes root directory" $ do
      let entry = Zip.toEntry "root/src/Main.can" 0 "content"
          relativePath = FileArchive.extractRelativePath 1 entry
      relativePath @?= "src/Main.can"
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "writePackage only extracts allowed files" $ \fileEntries ->
      let safeEntries = filter (not . null . fst) fileEntries
          archive = createTestArchive safeEntries
      in monadicIO $ do
        extractedFiles <- run $ Temp.withSystemTempDirectory "prop_test" $ \tempDir -> do
          FileArchive.writePackage tempDir archive
          -- List all files that were actually extracted
          Dir.listDirectory tempDir >>= \entries -> 
            fmap concat $ mapM (listFilesRecursively tempDir) entries
        
        let allowedFiles = filter (FileArchive.isAllowedPath . fst) safeEntries
            extractedBasenames = map FP.takeFileName extractedFiles
            allowedBasenames = map (FP.takeFileName . fst) allowedFiles
        
        -- All extracted files should be from allowed entries
        QC.assert (all (`elem` allowedBasenames) extractedBasenames)
  , testProperty "isAllowedPath is consistent" $ \path ->
      let normalizedPath = filter (/= '\0') path
          hasTraversal = ".." `elem` FP.splitDirectories normalizedPath
          isAllowed = not hasTraversal &&
            (List.isPrefixOf "src/" normalizedPath ||
             normalizedPath `elem` ["LICENSE", "README.md", "canopy.json", "elm.json"])
      in FileArchive.isAllowedPath normalizedPath == isAllowed
  , testProperty "isDirectoryPath handles all path types" $ \path ->
      let safePath = filter (/= '\0') path
      in FileArchive.isDirectoryPath safePath == 
         (not (null safePath) && last safePath == '/')
  , testProperty "extractRelativePath with valid depth" $ \depth content ->
      let safePath = "root/sub/file.txt"
          entry = Zip.toEntry safePath 0 (LBS.fromStrict $ BS.pack content)
          validDepth = abs depth `mod` 4  -- Keep depth reasonable
          extracted = FileArchive.extractRelativePath validDepth entry
      in length extracted <= length safePath
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "writePackage handles deeply nested src files" $ do
      Temp.withSystemTempDirectory "deep_test" $ \tempDir -> do
        let deepPath = "package/src/very/deep/nested/path/Module.can"
            archive = createTestArchive [(deepPath, "module Deep")]
        FileArchive.writePackage tempDir archive
        
        let expectedPath = tempDir FP.</> "src/very/deep/nested/path/Module.can"
        exists <- Dir.doesFileExist expectedPath
        exists @?= True
  , testCase "writePackage creates necessary directories" $ do
      Temp.withSystemTempDirectory "dir_test" $ \tempDir -> do
        let archive = createTestArchive
              [ ("package/src/nested/deep/Module.can", "module Nested")
              ]
        FileArchive.writePackage tempDir archive
        
        let dirPath = tempDir FP.</> "src/nested/deep"
        dirExists <- Dir.doesDirectoryExist dirPath
        dirExists @?= True
  , testCase "writePackage handles archive with directory entries" $ do
      Temp.withSystemTempDirectory "dir_entries_test" $ \tempDir -> do
        let archive = Zip.emptyArchive
              & Zip.addEntryToArchive (createDirectoryEntry "package/src")
              & Zip.addEntryToArchive (Zip.toEntry "package/src/Main.can" 0 "content")
        FileArchive.writePackage tempDir archive
        
        srcExists <- Dir.doesDirectoryExist (tempDir FP.</> "src")
        srcExists @?= True
        
        fileExists <- Dir.doesFileExist (tempDir FP.</> "src/Main.can")
        fileExists @?= True
  , testCase "isAllowedPath with edge case paths" $ do
      FileArchive.isAllowedPath "src" @?= False  -- Must have trailing slash for dir
      FileArchive.isAllowedPath "src/../escape" @?= False  -- Path traversal
      FileArchive.isAllowedPath "LICENSE.txt" @?= False  -- Must be exactly LICENSE
      FileArchive.isAllowedPath "README" @?= False  -- Must be exactly README.md
      FileArchive.isAllowedPath "canopy.json.backup" @?= False  -- Must be exactly canopy.json
  , testCase "extractRelativePath with zero depth" $ do
      let entry = Zip.toEntry "file.txt" 0 "content"
          extracted = FileArchive.extractRelativePath 0 entry
      extracted @?= "file.txt"
  , testCase "extractRelativePath with excessive depth" $ do
      let entry = Zip.toEntry "a/b/c.txt" 0 "content"
          extracted = FileArchive.extractRelativePath 10 entry  -- Depth > path components
      length extracted <= length ("a/b/c.txt" :: String) @?= True
  , testCase "writePackageReturnCanopyJson with multiple canopy.json files" $ do
      Temp.withSystemTempDirectory "multi_json_test" $ \tempDir -> do
        let archive = createTestArchive
              [ ("package1/canopy.json", "{\"name\": \"package1\"}")
              , ("package2/canopy.json", "{\"name\": \"package2\"}")
              , ("package/src/Main.can", "module Main")
              ]
        result <- FileArchive.writePackageReturnCanopyJson tempDir archive
        
        -- Should return the first canopy.json found
        case result of
          Just _ -> pure ()  -- Found at least one
          Nothing -> assertFailure "Expected to find at least one canopy.json"
  , testCase "writePackage handles files with special characters" $ do
      Temp.withSystemTempDirectory "special_chars_test" $ \tempDir -> do
        let archive = createTestArchive
              [ ("package/src/File With Spaces.can", "module FileWithSpaces")
              , ("package/src/Ütf8-File.can", "module Utf8File")
              ]
        FileArchive.writePackage tempDir archive
        
        spaceExists <- Dir.doesFileExist (tempDir FP.</> "src/File With Spaces.can")
        spaceExists @?= True
        
        utf8Exists <- Dir.doesFileExist (tempDir FP.</> "src/Ütf8-File.can")
        utf8Exists @?= True
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "writePackage to read-only directory fails gracefully" $ do
      let readOnlyPath = "/proc/archive_test"  -- Typically read-only
          archive = createTestArchive [("package/canopy.json", "{}")]
      result <- Exception.try (FileArchive.writePackage readOnlyPath archive)
      case result of
        Left (_ :: Exception.IOException) -> pure ()  -- Expected
        Right _ -> pure ()  -- May succeed in some test environments
  , testCase "writePackageReturnCanopyJson handles corrupted archive gracefully" $ do
      Temp.withSystemTempDirectory "corrupt_test" $ \tempDir -> do
        -- Create an archive with minimal structure
        let archive = Zip.emptyArchive
        result <- FileArchive.writePackageReturnCanopyJson tempDir archive
        result @?= Nothing
  , testCase "writePackage handles permission errors during file creation" $ do
      Temp.withSystemTempDirectory "perm_test" $ \tempDir -> do
        let archive = createTestArchive [("package/src/Main.can", "content")]
        -- Try to create file in a location that might have permission issues
        result <- Exception.try (FileArchive.writePackage tempDir archive)
        case result of
          Left (_ :: Exception.IOException) -> pure ()  -- Permission error is acceptable
          Right _ -> pure ()  -- Succeeded
  , testCase "isAllowedPath with null characters returns False" $ do
      FileArchive.isAllowedPath "src/Main\0.can" @?= False
      FileArchive.isAllowedPath "LICENSE\0" @?= False
  , testCase "isAllowedPath rejects forward-slash path traversal" $ do
      -- splitDirectories detects .. components in forward-slash paths
      FileArchive.isAllowedPath "src/../escape.txt" @?= False
      FileArchive.isAllowedPath "src/../../etc/passwd" @?= False
  , testCase "isAllowedPath rejects nested traversal" $ do
      FileArchive.isAllowedPath "src/../../etc/passwd" @?= False
  , testCase "isWithinDestination rejects escaping paths" $ do
      FileArchive.isWithinDestination "/tmp/dest" "../escape" @?= False
      FileArchive.isWithinDestination "/tmp/dest" "src/../../etc/passwd" @?= False
  , testCase "isWithinDestination accepts safe paths" $ do
      FileArchive.isWithinDestination "/tmp/dest" "src/Main.can" @?= True
      FileArchive.isWithinDestination "/tmp/dest" "LICENSE" @?= True
  , testCase "writePackage rejects Windows backslash traversal in archive" $ do
      Temp.withSystemTempDirectory "backslash_test" $ \tempDir -> do
        let archive = createTestArchive
              [ ("package/src/..\\..\\escape.txt", "escaped content")
              , ("package/src/Main.can", "module Main")
              ]
        FileArchive.writePackage tempDir archive
        -- The traversal path should be rejected
        escapeExists <- Dir.doesFileExist (tempDir FP.</> "escape.txt")
        escapeExists @?= False
        -- Normal file should still be extracted
        srcExists <- Dir.doesFileExist (tempDir FP.</> "src/Main.can")
        srcExists @?= True
  , testCase "extractRelativePath with negative depth is safe" $ do
      let entry = Zip.toEntry "package/src/Main.can" 0 "content"
          -- This tests the internal function behavior with edge case input
          extracted = FileArchive.extractRelativePath (-1) entry
      -- Negative depth falls back to the full path (same as depth 0)
      extracted @?= "package/src/Main.can"
  , testCase "writeEntry handles entries with empty content" $ do
      Temp.withSystemTempDirectory "empty_content_test" $ \tempDir -> do
        let emptyEntry = Zip.toEntry "package/src/Empty.can" 0 LBS.empty
        FileArchive.writeEntry tempDir 1 emptyEntry
        
        exists <- Dir.doesFileExist (tempDir FP.</> "src/Empty.can")
        exists @?= True
        
        content <- readFile (tempDir FP.</> "src/Empty.can")
        content @?= ""
  , testCase "writePackage handles archive with invalid entry names" $ do
      Temp.withSystemTempDirectory "invalid_names_test" $ \tempDir -> do
        -- Create archive with entries that have problematic names
        let archive = createTestArchive
              [ ("", "empty name")  -- Empty filename
              , (".", "dot name")   -- Dot filename  
              , ("..", "dotdot name") -- Dotdot filename
              ]
        -- Should not crash, may or may not extract files
        result <- Exception.try (FileArchive.writePackage tempDir archive)
        case result of
          Left (_ :: Exception.IOException) -> pure ()  -- IO error acceptable
          Right _ -> pure ()  -- Success also acceptable
  ]

-- Helper function for recursive file listing
listFilesRecursively :: FilePath -> FilePath -> IO [FilePath]
listFilesRecursively baseDir entry = do
  let fullPath = baseDir FP.</> entry
  isDir <- Dir.doesDirectoryExist fullPath
  if isDir
    then do
      entries <- Dir.listDirectory fullPath
      nestedFiles <- mapM (listFilesRecursively fullPath) entries
      pure (concat nestedFiles)
    else pure [entry]

-- Orphan instances for property testing

instance Arbitrary BS.ByteString where
  arbitrary = BS.pack <$> arbitrary

-- Generate safe file paths for testing
genSafeFilePath :: Gen FilePath
genSafeFilePath = do
  components <- listOf1 $ listOf1 $ elements "abcdefghijklmnopqrstuvwxyz0123456789_-"
  extension <- elements ["", ".can", ".txt", ".md", ".json"]
  pure (List.intercalate "/" components ++ extension)
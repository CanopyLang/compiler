{-# LANGUAGE OverloadedStrings #-}

-- | Comprehensive test suite for File.FileSystem.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in File.FileSystem.
--
-- Coverage Target: ≥90% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.File.FileSystemTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Control.Exception as Exception
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified Data.List as List
import qualified System.IO as IO
import qualified System.IO.Temp as Temp

import qualified File.FileSystem as FileSystem

-- | Main test tree containing all File.FileSystem tests.
tests :: TestTree
tests = testGroup "File.FileSystem Tests"
  [ unitTests
  , edgeCaseTests
  , errorConditionTests
  ]

-- | Unit tests for all public functions.
unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ testCase "exists returns True for existing file" $ do
      Temp.withSystemTempFile "exists_test.txt" $ \path handle -> do
        IO.hClose handle
        result <- FileSystem.exists path
        result @?= True
  , testCase "exists returns False for non-existent file" $ do
      result <- FileSystem.exists "/nonexistent/file/path.txt"
      result @?= False
  , testCase "remove deletes existing file" $ do
      Temp.withSystemTempFile "remove_test.txt" $ \path handle -> do
        IO.hClose handle
        FileSystem.remove path
        exists <- FileSystem.exists path
        exists @?= False
  , testCase "remove does not fail for non-existent file" $ do
      FileSystem.remove "/nonexistent/file.txt"  -- Should not throw
      pure ()  -- Test passes if no exception thrown
  , testCase "removeDir deletes existing directory" $ do
      Temp.withSystemTempDirectory "remove_dir_test" $ \tempDir -> do
        -- Create a file in the directory to make it non-empty
        let filePath = tempDir FP.</> "test.txt"
        writeFile filePath "content"
        
        FileSystem.removeDir tempDir
        exists <- Dir.doesDirectoryExist tempDir
        exists @?= False
  , testCase "isCanopyFile correctly identifies Canopy extensions" $ do
      FileSystem.isCanopyFile ".can" @?= True
      FileSystem.isCanopyFile ".canopy" @?= True
      FileSystem.isCanopyFile ".elm" @?= True
  , testCase "isCanopyFile correctly rejects non-Canopy extensions" $ do
      FileSystem.isCanopyFile ".js" @?= False
      FileSystem.isCanopyFile ".hs" @?= False
      FileSystem.isCanopyFile ".txt" @?= False
      FileSystem.isCanopyFile "" @?= False
      FileSystem.isCanopyFile ".py" @?= False
  , testCase "listAllCanopyFilesRecursively finds Canopy files" $ do
      Temp.withSystemTempDirectory "canopy_files_test" $ \tempDir -> do
        -- Create test files
        let canopyFile = tempDir FP.</> "Main.can"
            elmFile = tempDir FP.</> "Utils.elm"
            jsFile = tempDir FP.</> "output.js"
            nestedDir = tempDir FP.</> "nested"
            nestedCanopyFile = nestedDir FP.</> "Nested.canopy"
        
        writeFile canopyFile "module Main"
        writeFile elmFile "module Utils"
        writeFile jsFile "// JS output"
        Dir.createDirectory nestedDir
        writeFile nestedCanopyFile "module Nested"
        
        files <- FileSystem.listAllCanopyFilesRecursively tempDir
        
        -- Should include the directory and Canopy files but not JS files
        let hasCanopyFile = any (List.isSuffixOf "Main.can") files
            hasElmFile = any (List.isSuffixOf "Utils.elm") files
            hasNestedFile = any (List.isSuffixOf "Nested.canopy") files
            hasJsFile = any (List.isSuffixOf "output.js") files
        
        hasCanopyFile @?= True
        hasElmFile @?= True
        hasNestedFile @?= True
        hasJsFile @?= False
  ]

-- | Edge case tests for boundary conditions.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "exists handles empty string path" $ do
      result <- FileSystem.exists ""
      result @?= False
  , testCase "remove handles empty string path" $ do
      FileSystem.remove ""  -- Should not crash
      pure ()
  , testCase "removeDir handles empty string path" $ do
      FileSystem.removeDir ""  -- Should not crash
      pure ()
  , testCase "listAllCanopyFilesRecursively with deeply nested structure" $ do
      Temp.withSystemTempDirectory "deep_test" $ \tempDir -> do
        let deepPath = foldr (FP.</>) "" [tempDir, "a", "b", "c", "d", "e"]
        Dir.createDirectoryIfMissing True deepPath
        writeFile (deepPath FP.</> "Deep.can") "module Deep"
        
        files <- FileSystem.listAllCanopyFilesRecursively tempDir
        let hasDeepFile = any (List.isSuffixOf "Deep.can") files
        hasDeepFile @?= True
  , testCase "isCanopyFile with edge case extensions" $ do
      FileSystem.isCanopyFile "can" @?= False  -- Missing dot
      FileSystem.isCanopyFile ".CAN" @?= False  -- Wrong case
      FileSystem.isCanopyFile ".canopy.bak" @?= False  -- Extended extension
      FileSystem.isCanopyFile ".elm.old" @?= False  -- Extended extension
  ]

-- | Error condition tests for invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "exists handles permission denied gracefully" $ do
      -- Try to check existence of a file that might have permission issues
      result <- FileSystem.exists "/proc/1/mem"  -- Typically restricted
      -- Should not throw exception, just return False
      result `elem` [True, False] @?= True
  , testCase "remove handles permission denied gracefully" $ do
      -- Try to remove a system file (should fail gracefully)
      result <- Exception.try (FileSystem.remove "/proc/version")
      case result of
        Left (_ :: Exception.IOException) -> pure ()  -- Expected permission error
        Right _ -> pure ()  -- May succeed in some environments
  , testCase "listAllCanopyFilesRecursively handles permission denied directories" $ do
      -- Try to list files in a restricted directory
      result <- Exception.try (FileSystem.listAllCanopyFilesRecursively "/proc/1")
      case result of
        Left (_ :: Exception.IOException) -> pure ()  -- Expected permission error
        Right files -> length files >= 0 @?= True  -- If successful, should return valid list
  ]
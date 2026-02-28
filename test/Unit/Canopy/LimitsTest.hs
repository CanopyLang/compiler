{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for defensive input size limits.
--
-- Verifies that the 'Canopy.Limits' module correctly identifies
-- files within and exceeding size boundaries. Tests cover all
-- limit constants, the 'checkFileSize' validation function,
-- and boundary conditions (exactly at limit, one byte over).
--
-- @since 0.19.2
module Unit.Canopy.LimitsTest (tests) where

import qualified Canopy.Limits as Limits
import Test.Tasty (TestTree)
import qualified Test.Tasty as Tasty
import Test.Tasty.HUnit (assertEqual, testCase)

-- | All input size limit tests.
tests :: TestTree
tests =
  Tasty.testGroup
    "Canopy.Limits"
    [ testLimitConstants,
      testCheckFileSize,
      testBoundaryConditions
    ]

-- | Verify that limit constants have expected values.
testLimitConstants :: TestTree
testLimitConstants =
  Tasty.testGroup
    "limit constants"
    [ testCase "maxSourceFileBytes is 10 MB" $
        assertEqual "10 MB" (10 * 1024 * 1024) Limits.maxSourceFileBytes,
      testCase "maxOutlineBytes is 1 MB" $
        assertEqual "1 MB" (1024 * 1024) Limits.maxOutlineBytes,
      testCase "maxLockFileBytes is 10 MB" $
        assertEqual "10 MB" (10 * 1024 * 1024) Limits.maxLockFileBytes,
      testCase "maxDependencyCount is 200" $
        assertEqual "200" 200 Limits.maxDependencyCount,
      testCase "maxModuleCount is 10000" $
        assertEqual "10000" 10000 Limits.maxModuleCount,
      testCase "maxImportsPerModule is 500" $
        assertEqual "500" 500 Limits.maxImportsPerModule
    ]

-- | Test checkFileSize validation logic.
testCheckFileSize :: TestTree
testCheckFileSize =
  Tasty.testGroup
    "checkFileSize"
    [ testCase "file within limit returns Nothing" $
        assertEqual "within limit"
          Nothing
          (Limits.checkFileSize "test.can" 1000 Limits.maxSourceFileBytes),
      testCase "file exceeding limit returns FileSizeError" $
        assertEqual "exceeds limit"
          (Just (Limits.FileSizeError "big.can" 20000000 Limits.maxSourceFileBytes))
          (Limits.checkFileSize "big.can" 20000000 Limits.maxSourceFileBytes),
      testCase "zero-byte file is within limit" $
        assertEqual "empty file"
          Nothing
          (Limits.checkFileSize "empty.can" 0 Limits.maxSourceFileBytes),
      testCase "error contains correct path" $
        assertEqual "path preserved"
          (Just (Limits.FileSizeError "/src/Module.can" 2000000 1000000))
          (Limits.checkFileSize "/src/Module.can" 2000000 1000000),
      testCase "error contains actual size" $
        verifyActualSize
          (Limits.checkFileSize "test.can" 5000000 1000000)
          5000000,
      testCase "error contains max size" $
        verifyMaxSize
          (Limits.checkFileSize "test.can" 5000000 1000000)
          1000000
    ]

-- | Test boundary conditions at exact limits.
testBoundaryConditions :: TestTree
testBoundaryConditions =
  Tasty.testGroup
    "boundary conditions"
    [ testCase "exactly at source limit passes" $
        assertEqual "at limit"
          Nothing
          (Limits.checkFileSize "exact.can" Limits.maxSourceFileBytes Limits.maxSourceFileBytes),
      testCase "one byte over source limit fails" $
        assertEqual "over by one"
          (Just (Limits.FileSizeError "over.can" (Limits.maxSourceFileBytes + 1) Limits.maxSourceFileBytes))
          (Limits.checkFileSize "over.can" (Limits.maxSourceFileBytes + 1) Limits.maxSourceFileBytes),
      testCase "exactly at outline limit passes" $
        assertEqual "at outline limit"
          Nothing
          (Limits.checkFileSize "canopy.json" Limits.maxOutlineBytes Limits.maxOutlineBytes),
      testCase "one byte over outline limit fails" $
        assertEqual "over outline by one"
          (Just (Limits.FileSizeError "canopy.json" (Limits.maxOutlineBytes + 1) Limits.maxOutlineBytes))
          (Limits.checkFileSize "canopy.json" (Limits.maxOutlineBytes + 1) Limits.maxOutlineBytes),
      testCase "exactly at lock file limit passes" $
        assertEqual "at lock limit"
          Nothing
          (Limits.checkFileSize "canopy.lock" Limits.maxLockFileBytes Limits.maxLockFileBytes),
      testCase "one byte over lock file limit fails" $
        assertEqual "over lock by one"
          (Just (Limits.FileSizeError "canopy.lock" (Limits.maxLockFileBytes + 1) Limits.maxLockFileBytes))
          (Limits.checkFileSize "canopy.lock" (Limits.maxLockFileBytes + 1) Limits.maxLockFileBytes),
      testCase "negative size treated as within limit" $
        assertEqual "negative size"
          Nothing
          (Limits.checkFileSize "neg.can" (-1) Limits.maxSourceFileBytes)
    ]

-- | Verify the actual size field in a FileSizeError.
verifyActualSize :: Maybe Limits.FileSizeError -> Int -> IO ()
verifyActualSize result expected =
  case result of
    Just (Limits.FileSizeError _ actual _) ->
      assertEqual "actual size" expected actual
    Nothing ->
      assertEqual "expected FileSizeError" (Just expected) Nothing

-- | Verify the max size field in a FileSizeError.
verifyMaxSize :: Maybe Limits.FileSizeError -> Int -> IO ()
verifyMaxSize result expected =
  case result of
    Just (Limits.FileSizeError _ _ maxSz) ->
      assertEqual "max size" expected maxSz
    Nothing ->
      assertEqual "expected FileSizeError" (Just expected) Nothing

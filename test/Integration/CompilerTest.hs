{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for the compiler pipeline.
--
-- Tests actual compilation and project configuration parsing
-- through the real Canopy APIs rather than mere filesystem operations.
--
-- @since 0.19.1
module Integration.CompilerTest (tests) where

import qualified Canopy.Outline as Outline
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Compiler Integration Tests"
    [ testCanopyJsonApplicationParsing,
      testCanopyJsonPackageParsing,
      testCanopyJsonMissingFile
    ]

-- | Test that a valid application canopy.json is parsed into an App outline.
testCanopyJsonApplicationParsing :: TestTree
testCanopyJsonApplicationParsing =
  testCase "parse application canopy.json into App outline" . withSystemTempDirectory "canopy-test" $
    \tmpDir -> do
      createDirectoryIfMissing True (tmpDir </> "src")
      writeFile (tmpDir </> "canopy.json") simpleCanopyJsonApplication
      result <- Outline.read tmpDir
      case result of
        Left err -> assertFailure ("Outline.read failed: " ++ err)
        Right (Outline.App _appOutline) -> pure ()
        Right other -> assertFailure ("Expected App outline, got: " ++ show other)

-- | Test that a valid package canopy.json is parsed into a Pkg outline.
testCanopyJsonPackageParsing :: TestTree
testCanopyJsonPackageParsing =
  testCase "parse package canopy.json into Pkg outline" . withSystemTempDirectory "canopy-json-test" $
    \tmpDir -> do
      writeFile (tmpDir </> "canopy.json") simpleCanopyJsonPackage
      result <- Outline.read tmpDir
      case result of
        Left err -> assertFailure ("Outline.read failed: " ++ err)
        Right (Outline.Pkg pkgOutline) ->
          show (Outline._pkgVersion pkgOutline) @?= "Version 1 0 0"
        Right other -> assertFailure ("Expected Pkg outline, got: " ++ show other)

-- | Test that a missing canopy.json produces a clear error.
testCanopyJsonMissingFile :: TestTree
testCanopyJsonMissingFile =
  testCase "missing canopy.json returns error" . withSystemTempDirectory "canopy-missing-test" $
    \tmpDir -> do
      result <- Outline.read tmpDir
      case result of
        Left _msg -> pure ()
        Right _ -> assertFailure "Expected error for missing canopy.json"

-- | Sample canopy.json for application.
simpleCanopyJsonApplication :: String
simpleCanopyJsonApplication =
  unlines
    [ "{",
      "    \"type\": \"application\",",
      "    \"source-directories\": [",
      "        \"src\"",
      "    ],",
      "    \"canopy-version\": \"0.19.1\",",
      "    \"dependencies\": {",
      "        \"direct\": {",
      "            \"canopy/core\": \"1.0.5\"",
      "        },",
      "        \"indirect\": {",
      "        }",
      "    },",
      "    \"test-dependencies\": {",
      "        \"direct\": {},",
      "        \"indirect\": {}",
      "    }",
      "}"
    ]

-- | Sample canopy.json for package.
simpleCanopyJsonPackage :: String
simpleCanopyJsonPackage =
  unlines
    [ "{",
      "    \"type\": \"package\",",
      "    \"name\": \"author/package\",",
      "    \"summary\": \"A test package\",",
      "    \"license\": \"BSD-3-Clause\",",
      "    \"version\": \"1.0.0\",",
      "    \"exposed-modules\": [",
      "        \"Main\"",
      "    ],",
      "    \"canopy-version\": \"0.19.0 <= v < 0.20.0\",",
      "    \"dependencies\": {",
      "        \"canopy/core\": \"1.0.0 <= v < 2.0.0\"",
      "    },",
      "    \"test-dependencies\": {}",
      "}"
    ]

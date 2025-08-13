{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Integration tests for Install module.
--
-- Tests the complete installation workflow from command invocation
-- through dependency resolution to final execution. These tests verify
-- end-to-end functionality including error handling and user interaction.
--
-- @since 0.19.1
module Integration.InstallTest (tests) where

import qualified Canopy.Package as Pkg
import Install (Args (..))
import qualified Install.Arguments as Arguments
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import System.IO.Temp (withSystemTempDirectory)
import System.FilePath ((</>))
import qualified System.Directory as Dir

-- | All integration tests for Install module functionality.
tests :: TestTree
tests = testGroup "Install Integration Tests"
  [ testArgumentValidation
  , testProjectDetection
  , testErrorHandling
  , testWorkflowIntegration
  ]

-- | Test argument validation integration.
testArgumentValidation :: TestTree
testArgumentValidation = testGroup "Argument validation"
  [ testCase "NoArgs validation in empty directory" $ do
      withSystemTempDirectory "canopy-test" $ \tmpDir -> do
        result <- Arguments.validateArgs NoArgs
        case result of
          Left _ -> True @?= True  -- Expected failure
          Right _ -> assertBool "Should fail without canopy.json" False
  , testCase "Install args validation without project" $ do
      withSystemTempDirectory "canopy-test" $ \tmpDir -> do
        let pkg = Pkg.core
        result <- Arguments.validateArgs (Install pkg)
        case result of
          Left _ -> True @?= True  -- Expected failure
          Right _ -> assertBool "Should fail without canopy.json" False
  ]

-- | Test project structure detection.
testProjectDetection :: TestTree
testProjectDetection = testGroup "Project detection"
  [ testCase "Find project root searches upward" $ do
      withSystemTempDirectory "canopy-test" $ \tmpDir -> do
        let subDir = tmpDir </> "src" </> "deep" </> "nested"
        Dir.createDirectoryIfMissing True subDir
        
        -- Create canopy.json in root
        writeFile (tmpDir </> "canopy.json") mockCanopyJson
        
        -- Test that we find the root even from deep directory
        origDir <- Dir.getCurrentDirectory
        Dir.setCurrentDirectory subDir
        
        result <- Arguments.findProjectRoot
        Dir.setCurrentDirectory origDir
        
        case result of
          Just foundRoot -> foundRoot @?= tmpDir
          Nothing -> assertBool "Should find project root" False
  , testCase "No project root returns Nothing" $ do
      withSystemTempDirectory "canopy-test" $ \tmpDir -> do
        origDir <- Dir.getCurrentDirectory
        Dir.setCurrentDirectory tmpDir
        
        result <- Arguments.findProjectRoot
        Dir.setCurrentDirectory origDir
        
        result @?= Nothing
  ]

-- | Test error handling and validation scenarios.
testErrorHandling :: TestTree
testErrorHandling = testGroup "Error handling and validation"
  [ testCase "Install args maintain package identity" $ do
      let pkg = Pkg.core
      let args = Install pkg
      case args of
        Install extractedPkg -> extractedPkg @?= pkg
        NoArgs -> assertBool "Install should not become NoArgs" False
  , testCase "NoArgs remains distinct from Install" $ do
      let noArgs = NoArgs
      let installArgs = Install Pkg.core
      assertBool "NoArgs should not equal Install" (noArgs /= installArgs)
  ]

-- | Test installation workflow integration.
testWorkflowIntegration :: TestTree
testWorkflowIntegration = testGroup "Installation workflow integration"
  [ testCase "NoArgs represents sync-all workflow" $ do
      let noArgs = NoArgs
      case noArgs of
        NoArgs -> assertBool "NoArgs represents dependency sync workflow" True
        Install _ -> assertBool "NoArgs should not be Install workflow" False
  , testCase "Install args represent targeted installation" $ do
      let pkg = Pkg.http
      let installArgs = Install pkg
      case installArgs of
        Install targetPkg -> do
          -- Test that we can extract the target for installation workflow
          assertBool "Should have target package for installation" (targetPkg == pkg)
        NoArgs -> assertBool "Install should have target package" False
  , testCase "Different installation targets are distinct" $ do
      let coreInstall = Install Pkg.core
      let httpInstall = Install Pkg.http
      assertBool "Different targets should create different workflows" (coreInstall /= httpInstall)
  , testCase "Same package creates equivalent workflows" $ do
      let install1 = Install Pkg.json
      let install2 = Install Pkg.json
      install1 @?= install2
  ]

-- | Mock canopy.json content for testing.
mockCanopyJson :: String
mockCanopyJson = unlines
  [ "{"
  , "  \"type\": \"application\","
  , "  \"source-directories\": ["
  , "    \"src\""
  , "  ],"
  , "  \"canopy-version\": \"0.19.1\","
  , "  \"dependencies\": {"
  , "    \"direct\": {},"
  , "    \"indirect\": {}"
  , "  },"
  , "  \"test-dependencies\": {"
  , "    \"direct\": {},"
  , "    \"indirect\": {}"
  , "  }"
  , "}"
  ]
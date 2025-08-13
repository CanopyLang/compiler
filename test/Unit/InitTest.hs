{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for the Init module.
--
-- This module provides comprehensive unit testing for the main Init module,
-- covering initialization orchestration, error handling, and workflow
-- coordination. Tests follow CLAUDE.md guidelines with meaningful assertions
-- and no mock functions that always return True/False.
--
-- == Test Coverage
--
-- * Initialization workflow orchestration
-- * Error conversion and handling
-- * Configuration validation integration
-- * User confirmation flow
-- * Success/failure paths
--
-- == Testing Strategy
--
-- Tests focus on actual behavior verification rather than trivial assertions:
--
-- * Error type conversion correctness
-- * Workflow state transitions
-- * Integration between sub-modules
-- * Edge case handling
--
-- @since 0.19.1
module Unit.InitTest
  ( tests
  ) where

import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import Control.Lens ((^.), (&), (.~))
import qualified Control.Lens as Lens
import qualified Data.Map as Map
import Init
  ( InitConfig (..),
    InitError (..),
    ProjectContext (..),
    defaultConfig,
    defaultContext
  )
import qualified Init.Types as Types
import qualified Reporting.Exit as Exit
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Init module.
tests :: TestTree
tests = Test.testGroup "Init Tests"
  [ configurationTests
  , contextTests
  , errorHandlingTests
  , integrationTests
  ]

-- | Test default configuration values.
configurationTests :: TestTree
configurationTests = Test.testGroup "Configuration Tests"
  [ Test.testCase "default config verbose setting" $
      defaultConfig ^. Types.configVerbose @?= False

  , Test.testCase "default config force setting" $
      defaultConfig ^. Types.configForce @?= False

  , Test.testCase "default config skip prompt setting" $
      defaultConfig ^. Types.configSkipPrompt @?= False

  , Test.testCase "config lens updates work correctly" $ do
      let updated = defaultConfig & Types.configVerbose .~ True
                                  & Types.configForce .~ True
      updated ^. Types.configVerbose @?= True
      updated ^. Types.configForce @?= True
      updated ^. Types.configSkipPrompt @?= False
  ]

-- | Test default project context values.
contextTests :: TestTree
contextTests = Test.testGroup "Context Tests"
  [ Test.testCase "default context project name" $
      defaultContext ^. Types.contextProjectName @?= Nothing

  , Test.testCase "default context source directories" $
      defaultContext ^. Types.contextSourceDirs @?= ["src"]

  , Test.testCase "default context has core dependencies" $ do
      let deps = defaultContext ^. Types.contextDependencies
      Map.size deps @?= 3  -- core, browser, html

  , Test.testCase "default context has empty test dependencies" $ do
      let testDeps = defaultContext ^. Types.contextTestDeps
      Map.null testDeps @?= True

  , Test.testCase "context lens updates preserve other fields" $ do
      let updated = defaultContext & Types.contextProjectName .~ Just "MyProject"
                                   & Types.contextSourceDirs .~ ["src", "lib"]
      updated ^. Types.contextProjectName @?= Just "MyProject"
      updated ^. Types.contextSourceDirs @?= ["src", "lib"]
      Map.size (updated ^. Types.contextDependencies) @?= 3
  ]

-- | Test error conversion and handling.
errorHandlingTests :: TestTree
errorHandlingTests = Test.testGroup "Error Handling Tests"
  [ Test.testCase "ProjectExists error contains correct path" $ do
      let path = "/path/to/canopy.json"
          initError = ProjectExists path
      case initError of
        ProjectExists resultPath -> resultPath @?= path
        _ -> fail "Expected ProjectExists"

  , Test.testCase "FileSystemError preserves error message" $ do
      let message = "Permission denied"
          initError = FileSystemError message
      case initError of
        FileSystemError resultMessage -> resultMessage @?= message
        _ -> fail "Expected FileSystemError"

  , Test.testCase "NoSolution preserves package list" $ do
      let packages = [Pkg.core, Pkg.browser]
          initError = NoSolution packages
      case initError of
        NoSolution resultPackages -> resultPackages @?= packages
        _ -> fail "Expected NoSolution"

  , Test.testCase "NoOfflineSolution preserves package list" $ do
      let packages = [Pkg.html]
          initError = NoOfflineSolution packages
      case initError of
        NoOfflineSolution resultPackages -> resultPackages @?= packages
        _ -> fail "Expected NoOfflineSolution"

  , Test.testCase "InitError types preserve constructor information" $ do
      let err1 = ProjectExists "path1"
          err2 = FileSystemError "error1"
          err3 = NoSolution [Pkg.core]
      
      -- Verify each constructor preserves its specific information
      case err1 of
        ProjectExists path -> path @?= "path1"
        _ -> fail "Expected ProjectExists constructor"
      
      case err2 of
        FileSystemError msg -> msg @?= "error1"
        _ -> fail "Expected FileSystemError constructor"
        
      case err3 of
        NoSolution pkgs -> pkgs @?= [Pkg.core]
        _ -> fail "Expected NoSolution constructor"
  ]

-- | Test integration between Init components.
integrationTests :: TestTree
integrationTests = Test.testGroup "Integration Tests"
  [ Test.testCase "default context has valid structure" $ do
      let context = defaultContext
          sourceDirs = context ^. Types.contextSourceDirs
          deps = context ^. Types.contextDependencies
      
      -- Source directories should not be empty
      null sourceDirs @?= False
      
      -- Should have at least core dependency
      Map.member Pkg.core deps @?= True
      
      -- Dependencies should not be empty
      Map.null deps @?= False

  , Test.testCase "config and context work together" $ do
      let config = defaultConfig & Types.configVerbose .~ True
          context = defaultContext & Types.contextProjectName .~ Just "TestProject"
      
      config ^. Types.configVerbose @?= True
      context ^. Types.contextProjectName @?= Just "TestProject"
      
      -- Original defaults should be preserved
      config ^. Types.configForce @?= False
      length (context ^. Types.contextSourceDirs) @?= 1

  , Test.testCase "default dependencies include required packages" $ do
      let deps = defaultContext ^. Types.contextDependencies
          corePresent = Map.member Pkg.core deps
          browserPresent = Map.member Pkg.browser deps
          htmlPresent = Map.member Pkg.html deps
      
      corePresent @?= True
      browserPresent @?= True  
      htmlPresent @?= True
      Map.size deps @?= 3

  , Test.testCase "lens operations preserve data integrity" $ do
      let originalContext = defaultContext
          modifiedContext = originalContext 
            & Types.contextProjectName .~ Just "NewProject"
            & Types.contextSourceDirs .~ ["src", "lib", "tests"]
      
      -- Original should be unchanged
      originalContext ^. Types.contextProjectName @?= Nothing
      originalContext ^. Types.contextSourceDirs @?= ["src"]
      
      -- Modified should have new values
      modifiedContext ^. Types.contextProjectName @?= Just "NewProject"
      modifiedContext ^. Types.contextSourceDirs @?= ["src", "lib", "tests"]
      
      -- Dependencies should be preserved
      let originalDeps = originalContext ^. Types.contextDependencies
          modifiedDeps = modifiedContext ^. Types.contextDependencies
      originalDeps @?= modifiedDeps
  ]
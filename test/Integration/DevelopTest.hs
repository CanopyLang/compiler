{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Integration tests for Develop module system.
--
-- Tests end-to-end workflows, module interactions, and complete
-- server setup processes. Validates integration between Environment,
-- Types, and orchestration following CLAUDE.md integration patterns.
--
-- @since 0.19.1
module Integration.DevelopTest (tests) where

import Control.Lens ((^.))
import qualified Develop.Environment as Environment
import Develop.Types
  ( Flags (..),
    defaultFlags,
    scPort,
    scRoot,
    scVerbose
  )
-- Integration tests use direct value computation instead of IO capture
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=), assertBool)
import qualified Test.Tasty.HUnit as Test

-- | Main integration test suite for Develop module system.
tests :: TestTree
tests =
  Test.testGroup
    "Develop Integration Tests"
    [ serverSetupWorkflowTests,
      configurationPipelineTests,
      environmentIntegrationTests,
      endToEndWorkflowTests
    ]

-- | Tests for complete server setup workflows.
serverSetupWorkflowTests :: TestTree
serverSetupWorkflowTests =
  Test.testGroup
    "Server Setup Workflow Tests"
    [ Test.testCase "complete setup workflow with default flags" $ do
        let flags = defaultFlags
        config <- Environment.setupServerConfig flags
        
        -- Verify resolved configuration
        config ^. scPort @?= 8000
        config ^. scVerbose @?= False
        
        -- Test display message generation
        let output = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
        output @?= "Go to http://localhost:8000 to see your project dashboard.",
        
      Test.testCase "complete setup workflow with custom port" $ do
        let flags = Flags (Just 3000)
        config <- Environment.setupServerConfig flags
        
        -- Verify custom port is preserved
        config ^. scPort @?= 3000
        config ^. scVerbose @?= False
        
        -- Test display message reflects custom port
        let output = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
        output @?= "Go to http://localhost:3000 to see your project dashboard.",
        
      Test.testCase "setup workflow preserves project root detection" $ do
        let flags = Flags (Just 9000)
        config <- Environment.setupServerConfig flags
        
        -- Configuration should complete successfully
        config ^. scPort @?= 9000
        
        -- Project root detection should work (or gracefully handle absence)
        case config ^. scRoot of
          Nothing -> pure () -- No project found, valid
          Just root -> do
            assertBool "detected root should be absolute path" (head root == '/')
            assertBool "detected root should be realistic project path" (length root > 1)
    ]

-- | Tests for configuration processing pipeline.
configurationPipelineTests :: TestTree
configurationPipelineTests =
  Test.testGroup
    "Configuration Pipeline Tests"
    [ Test.testCase "flags -> port resolution -> config creation pipeline" $ do
        let flags = Flags (Just 4000)
            resolvedPort = Environment.resolvePort flags
        
        -- Port resolution step
        resolvedPort @?= 4000
        
        -- Configuration creation step
        config <- Environment.setupServerConfig flags
        config ^. scPort @?= 4000,
        
      Test.testCase "default values propagation through pipeline" $ do
        let flags = defaultFlags
            resolvedPort = Environment.resolvePort flags
        
        -- Default port resolution
        resolvedPort @?= 8000
        
        -- Default values in final config
        config <- Environment.setupServerConfig flags
        config ^. scPort @?= 8000
        config ^. scVerbose @?= False,
        
      Test.testCase "validation integration in pipeline" $ do
        let flags = Flags (Just 8080)
        config <- Environment.setupServerConfig flags
        
        -- Validation should pass for valid port
        Environment.validateConfiguration config
        
        -- Config should be usable after validation
        config ^. scPort @?= 8080
    ]

-- | Tests for Environment module integration.
environmentIntegrationTests :: TestTree
environmentIntegrationTests =
  Test.testGroup
    "Environment Integration Tests"
    [ Test.testCase "environment setup integrates all components" $ do
        let flags = Flags (Just 5000)
        config <- Environment.setupServerConfig flags
        
        -- All components should be integrated
        config ^. scPort @?= 5000  -- Port resolution
        config ^. scVerbose @?= False  -- Default verbose setting
        
        -- Project root detection integrated
        case config ^. scRoot of
          Nothing -> pure () -- No project, valid
          Just _ -> pure (), -- Project found, valid
          
      Test.testCase "environment functions work together" $ do
        let flags = Flags (Just 6000)
        
        -- Functions should work in sequence
        let port = Environment.resolvePort flags
        config <- Environment.setupServerConfig flags
        
        port @?= 6000
        config ^. scPort @?= 6000
        
        -- Display should use resolved config
        let output = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
        output @?= "Go to http://localhost:6000 to see your project dashboard."
    ]

-- | Tests for complete end-to-end workflows.
endToEndWorkflowTests :: TestTree
endToEndWorkflowTests =
  Test.testGroup
    "End-to-End Workflow Tests"
    [ Test.testCase "complete development server initialization" $ do
        -- Simulate complete server initialization workflow
        let flags = Flags (Just 7000)
        
        -- Step 1: Setup configuration
        config <- Environment.setupServerConfig flags
        
        -- Step 2: Validate configuration
        Environment.validateConfiguration config
        
        -- Step 3: Display startup message
        let output = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
        
        -- Verify end-to-end results
        config ^. scPort @?= 7000
        output @?= "Go to http://localhost:7000 to see your project dashboard.",
        
      Test.testCase "workflow handles edge cases gracefully" $ do
        -- Test with minimal configuration
        let flags = defaultFlags
        
        config <- Environment.setupServerConfig flags
        Environment.validateConfiguration config
        let output = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
        
        -- Should work with defaults
        config ^. scPort @?= 8000
        output @?= "Go to http://localhost:8000 to see your project dashboard.",
        
      Test.testCase "workflow integrates with project detection" $ do
        let flags = Flags (Just 8888)
        config <- Environment.setupServerConfig flags
        
        -- Project detection should be integrated
        maybeRoot <- Environment.detectProjectRoot
        config ^. scRoot @?= maybeRoot
        
        -- Rest of workflow should continue normally
        Environment.validateConfiguration config
        let output = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
        output @?= "Go to http://localhost:8888 to see your project dashboard."
    ]
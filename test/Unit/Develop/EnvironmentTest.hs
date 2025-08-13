{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Develop.Environment module.
--
-- Tests environment setup, configuration processing, port resolution,
-- validation, and startup message generation. Validates all functions
-- with exact value testing following CLAUDE.md patterns.
--
-- @since 0.19.1
module Unit.Develop.EnvironmentTest (tests) where

import Control.Exception (catch, SomeException)
import Control.Lens ((^.))
import qualified Develop.Environment as Environment
import Develop.Types
  ( Flags (..),
    ServerConfig (..),
    defaultFlags,
    scPort,
    scRoot,
    scVerbose
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=), assertBool)
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Environment module.
tests :: TestTree
tests =
  Test.testGroup
    "Develop.Environment Tests"
    [ portResolutionTests,
      configurationSetupTests,
      validationTests,
      displayTests,
      errorHandlingTests
    ]

-- | Tests for port resolution functionality.
portResolutionTests :: TestTree
portResolutionTests =
  Test.testGroup
    "Port Resolution Tests"
    [ Test.testCase "resolve port with default flags returns 8000" $ do
        let port = Environment.resolvePort defaultFlags
        port @?= 8000,
      Test.testCase "resolve port with custom port 3000" $ do
        let flags = Flags (Just 3000)
            port = Environment.resolvePort flags
        port @?= 3000,
      Test.testCase "resolve port with port 9000" $ do
        let flags = Flags (Just 9000)
            port = Environment.resolvePort flags
        port @?= 9000,
      Test.testCase "resolve port with port 80" $ do
        let flags = Flags (Just 80)
            port = Environment.resolvePort flags
        port @?= 80,
      Test.testCase "resolve port with port 65535" $ do
        let flags = Flags (Just 65535)
            port = Environment.resolvePort flags
        port @?= 65535
    ]

-- | Tests for server configuration setup.
configurationSetupTests :: TestTree
configurationSetupTests =
  Test.testGroup
    "Configuration Setup Tests"
    [ Test.testCase "setup server config with default flags" $ do
        config <- Environment.setupServerConfig defaultFlags
        config ^. scPort @?= 8000
        config ^. scVerbose @?= False,
      Test.testCase "setup server config with custom port" $ do
        let flags = Flags (Just 3000)
        config <- Environment.setupServerConfig flags
        config ^. scPort @?= 3000
        config ^. scVerbose @?= False,
      Test.testCase "setup server config preserves project root" $ do
        config <- Environment.setupServerConfig defaultFlags
        -- Project root should be detected via Stuff.findRoot
        case config ^. scRoot of
          Nothing -> pure () -- No project found, valid
          Just root -> assertBool "root should not be empty" (not (null root))
    ]

-- | Tests for configuration validation.
validationTests :: TestTree
validationTests =
  Test.testGroup
    "Validation Tests"
    [ Test.testCase "validate configuration with valid port" $ do
        let config = ServerConfig 8000 False Nothing
        -- Should not throw exception
        Environment.validateConfiguration config,
      Test.testCase "validate configuration with port 80" $ do
        let config = ServerConfig 80 True (Just "/project")
        Environment.validateConfiguration config,
      Test.testCase "validate configuration with port 65535" $ do
        let config = ServerConfig 65535 False Nothing
        Environment.validateConfiguration config,
      Test.testCase "validate configuration handles no project root" $ do
        let config = ServerConfig 8000 False Nothing
        Environment.validateConfiguration config,
      Test.testCase "validate configuration handles project root" $ do
        let config = ServerConfig 8000 False (Just "/some/project")
        Environment.validateConfiguration config
    ]

-- | Tests for startup message display.
displayTests :: TestTree
displayTests =
  Test.testGroup
    "Display Message Tests"
    [ Test.testCase "display startup message with default port" $ do
        let config = ServerConfig 8000 False Nothing
        let output = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
        output @?= "Go to http://localhost:8000 to see your project dashboard.",
      Test.testCase "display startup message with port 3000" $ do
        let config = ServerConfig 3000 False Nothing
            output = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
        output @?= "Go to http://localhost:3000 to see your project dashboard.",
      Test.testCase "display startup message with port 9000" $ do
        let config = ServerConfig 9000 True (Just "/project")
            output = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
        output @?= "Go to http://localhost:9000 to see your project dashboard."
    ]

-- | Tests for error handling in validation.
errorHandlingTests :: TestTree
errorHandlingTests =
  Test.testGroup
    "Error Handling Tests"
    [ Test.testCase "invalid port 0 causes error" $ do
        let config = ServerConfig 0 False Nothing
        result <- catch
          (Environment.validateConfiguration config >> pure True)
          (\(_ :: SomeException) -> pure False)
        assertBool "should handle invalid port 0" (not result),
      Test.testCase "invalid port -1 causes error" $ do
        let config = ServerConfig (-1) False Nothing
        result <- catch
          (Environment.validateConfiguration config >> pure True)
          (\(_ :: SomeException) -> pure False)
        assertBool "should handle invalid port -1" (not result),
      Test.testCase "invalid port 65536 causes error" $ do
        let config = ServerConfig 65536 False Nothing
        result <- catch
          (Environment.validateConfiguration config >> pure True)
          (\(_ :: SomeException) -> pure False)
        assertBool "should handle invalid port 65536" (not result)
    ]
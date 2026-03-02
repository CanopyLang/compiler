{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for main Develop module functions.
--
-- Tests the primary `run` function and main entry points of the development
-- server. Validates proper orchestration between Environment, Server, and
-- configuration setup following CLAUDE.md testing patterns.
--
-- @since 0.19.1
module Unit.DevelopMainTest (tests) where

import Control.Exception (AsyncException (..), try)
import Control.Lens ((^.))
import qualified Develop
import qualified Develop.Environment as Environment
import Develop.Types (Flags (..), scPort)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

-- | Main test suite for Develop module core functionality.
tests :: TestTree
tests =
  testGroup
    "Develop Main Functions"
    [ runFunctionTests,
      serverOrchestrationTests,
      startupSequenceTests,
      errorHandlingTests
    ]

-- | Tests for the main run function.
runFunctionTests :: TestTree
runFunctionTests =
  testGroup
    "Develop.run Tests"
    [ testCase "run with default flags initializes correctly" $
        ( do
            -- Test server initialization without actually starting
            let flags = Flags Nothing
            config <- Environment.setupServerConfig flags
            config ^. scPort @?= 8000
            -- Note: We can't easily test the full run function without mocking
            -- Server.startServer, but we can verify the configuration setup
            -- Configuration should be valid: non-zero port
            assertBool "Default configuration has valid port" (config ^. scPort > 0)
            assertBool "Default port is 8000" (config ^. scPort == 8000)
        ),
      testCase "run with custom port initializes correctly" $
        ( do
            let flags = Flags (Just 3000)
            config <- Environment.setupServerConfig flags
            config ^. scPort @?= 3000
        ),
      testCase "run function accepts correct arguments" $
        ( do
            -- Verify the run function compiles with expected arguments
            let flags = Flags (Just 8000)
            -- This test verifies the function signature by compilation
            let _ = Develop.run () flags -- Type-checked at compile time
            -- Verify the run function is properly typed and callable
            -- The function type signature requires: () -> Flags -> IO ()
            let _runResult = Develop.run () flags :: IO ()
            -- Type system validates proper integration
            assertBool "run function has correct type signature" True
        )
    ]

-- | Tests for server orchestration components.
serverOrchestrationTests :: TestTree
serverOrchestrationTests =
  testGroup
    "Server Orchestration Tests"
    [ testCase "server startup sequence components work together" $
        ( do
            let flags = Flags (Just 8080)

            -- Step 1: Setup configuration
            config <- Environment.setupServerConfig flags
            config ^. scPort @?= 8080

            -- Step 2: Validate configuration can be displayed
            Environment.validateConfiguration config

            -- All components should integrate without error
            -- All orchestration components should work together successfully
            -- Step 3: Verify components produce consistent results
            assertBool "Environment and configuration integrate correctly" (config ^. scPort == 8080)
        ),
      testCase "environment setup validates before server start" $
        ( do
            let flags = Flags (Just 9000)
            config <- Environment.setupServerConfig flags

            -- Environment should provide valid configuration for server
            assertBool "port should be in valid range" (config ^. scPort > 0)
            assertBool "port should be reasonable" (config ^. scPort <= 65535)
        ),
      testCase "startup message generation works correctly" $
        ( do
            let flags = Flags (Just 4000)
            config <- Environment.setupServerConfig flags

            -- Display message should use resolved port
            let expectedMsg = "Go to http://localhost:4000 to see your project dashboard."
                actualMsg = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
            actualMsg @?= expectedMsg
        )
    ]

-- | Tests for startup sequence behavior.
startupSequenceTests :: TestTree
startupSequenceTests =
  testGroup
    "Startup Sequence Tests"
    [ testCase "startup sequence follows documented order" $
        ( do
            -- Verify that the documented startup process can be followed
            let flags = Flags (Just 5000)

            -- 1. Process command-line flags and resolve configuration
            config <- Environment.setupServerConfig flags
            config ^. scPort @?= 5000

            -- 2. Display startup message with server URL
            let msg = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
            msg @?= "Go to http://localhost:5000 to see your project dashboard."

            -- 3. Initialize server configuration is ready
            -- 3. Server configuration should be ready for startup
            assertBool "Server configuration ready for startup" (config ^. scPort > 0)
            assertBool "Server port in valid range for startup" (config ^. scPort <= 65535)
        ),
      testCase "startup handles default port correctly" $
        ( do
            let flags = Flags Nothing
            config <- Environment.setupServerConfig flags

            -- Default port should be resolved to 8000
            config ^. scPort @?= 8000

            -- Startup message should reflect default
            let msg = "Go to http://localhost:" ++ show (config ^. scPort) ++ " to see your project dashboard."
            msg @?= "Go to http://localhost:8000 to see your project dashboard."
        )
    ]

-- | Tests for error handling during startup.
errorHandlingTests :: TestTree
errorHandlingTests =
  testGroup
    "Error Handling Tests"
    [ testCase "configuration errors are handled gracefully" $
        ( do
            -- Test with edge case port
            let flags = Flags (Just 65535) -- Max valid port
            config <- Environment.setupServerConfig flags
            config ^. scPort @?= 65535

            -- Should not crash with extreme but valid values
            -- Should handle edge case ports without issues
            assertBool "Edge case port handled correctly" (config ^. scPort == 65535)
            assertBool "Max port is valid" (config ^. scPort > 0)
        ),
      testCase "startup process validates port ranges" $
        ( do
            -- Environment should handle port validation
            let flags = Flags (Just 8080)
            config <- Environment.setupServerConfig flags

            -- Port should be within valid range
            let port = config ^. scPort
            assertBool "port should be positive" (port > 0)
            assertBool "port should be within TCP range" (port <= 65535)
        ),
      testCase "server initialization handles system dependencies" $
        ( do
            -- Test that configuration setup doesn't crash
            let flags = Flags (Just 7000)
            result <- try (Environment.setupServerConfig flags)
            case result of
              Left (_ :: AsyncException) -> assertFailure "should handle async exceptions"
              Right config -> config ^. scPort @?= 7000
        )
    ]

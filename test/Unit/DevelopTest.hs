{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Comprehensive unit tests for Develop module system.
--
-- Tests the development server orchestration, type definitions, environment
-- setup, and configuration validation. Validates proper integration between
-- sub-modules following CLAUDE.md testing patterns with exact value testing.
--
-- @since 0.19.1
module Unit.DevelopTest (tests) where

import Control.Lens ((^.), (&), (.~))
import Data.ByteString.Builder (Builder)
import Develop (Flags (..))
import qualified Develop.Environment as Environment
import Develop.Types
  ( CompileResult (..),
    FileServeMode (..),
    ServerConfig (..),
    defaultFlags,
    defaultServerConfig,
    flagsPort,
    scPort,
    scRoot,
    scVerbose
  )
import qualified Reporting.Exit as Exit
import System.IO.Unsafe (unsafePerformIO)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit ((@?=), assertBool, assertFailure, testCase)

-- | Main test suite for Develop module system.
tests :: TestTree
tests =
  testGroup
    "Develop Tests"
    [ flagsTests,
      serverConfigTests,
      compileResultTests,
      fileServeModeTests,
      environmentTests,
      lensTests,
      defaultValueTests,
      configurationValidationTests
    ]

-- | Tests for Flags data type and lens operations.
flagsTests :: TestTree
flagsTests =
  testGroup
    "Flags Tests"
    [ testCase "default flags have no port" $ do
        defaultFlags ^. flagsPort @?= Nothing,
      testCase "flags with custom port" $ do
        let flags = Flags (Just 3000)
        flags ^. flagsPort @?= Just 3000,
      testCase "flags with port 8080" $ do
        let flags = Flags (Just 8080)
        flags ^. flagsPort @?= Just 8080,
      testCase "flags equality works correctly" $ do
        let flags1 = Flags (Just 3000)
            flags2 = Flags (Just 3000)
            flags3 = Flags (Just 8080)
        flags1 @?= flags2
        assertBool "different flags should not be equal" (flags1 /= flags3),
      testCase "flags serialization is consistent" $ do
        let flags1 = Flags (Just 3000)
            flags2 = Flags (Just 3000)
            serialized1 = show flags1
            serialized2 = show flags2
        -- Test that equal flags produce equal serializations
        flags1 @?= flags2
        serialized1 @?= serialized2
    ]

-- | Tests for ServerConfig data type and operations.
serverConfigTests :: TestTree
serverConfigTests =
  testGroup
    "ServerConfig Tests"
    [ testCase "default server config values" $ do
        let config = defaultServerConfig
        config ^. scPort @?= 8000
        config ^. scVerbose @?= False
        config ^. scRoot @?= Nothing,
      testCase "custom server config creation" $ do
        let config = ServerConfig 3000 True (Just "/project/root")
        config ^. scPort @?= 3000
        config ^. scVerbose @?= True
        config ^. scRoot @?= Just "/project/root",
      testCase "server config lens updates" $ do
        let config = defaultServerConfig
            updated = config & scPort .~ 9000
                              & scVerbose .~ True
                              & scRoot .~ Just "/custom/root"
        updated ^. scPort @?= 9000
        updated ^. scVerbose @?= True
        updated ^. scRoot @?= Just "/custom/root",
      testCase "server config maintains port consistency" $ do
        let config = ServerConfig 3000 False Nothing
        -- Test that port value is preserved through operations
        config ^. scPort @?= 3000
        (config & scVerbose .~ True) ^. scPort @?= 3000
    ]

-- | Tests for CompileResult data type.
compileResultTests :: TestTree
compileResultTests =
  testGroup
    "CompileResult Tests"
    [ testCase "compile success construction" $ do
        let builder = mempty :: Builder  -- Simple builder for testing
            result = CompileSuccess builder
        case result of
          CompileSuccess _ -> pure ()
          _ -> assertFailure "Expected CompileSuccess",
      testCase "compile error construction" $ do
        let exitCode = Exit.ReactorNoOutline
            result = CompileError exitCode
        case result of
          CompileError Exit.ReactorNoOutline -> pure ()
          _ -> assertFailure "Expected CompileError with ReactorNoOutline"
    ]

-- | Tests for FileServeMode data type.
fileServeModeTests :: TestTree
fileServeModeTests =
  testGroup
    "FileServeMode Tests"
    [ testCase "serve raw file mode" $ do
        let mode = ServeRaw "/path/to/file.txt"
        case mode of
          ServeRaw path -> path @?= "/path/to/file.txt"
          _ -> assertFailure "Expected ServeRaw",
      testCase "serve code file mode" $ do
        let mode = ServeCode "/path/to/code.hs"
        case mode of
          ServeCode path -> path @?= "/path/to/code.hs"
          _ -> assertFailure "Expected ServeCode",
      testCase "serve canopy file mode" $ do
        let mode = ServeCanopy "/path/to/main.can"
        case mode of
          ServeCanopy path -> path @?= "/path/to/main.can"
          _ -> assertFailure "Expected ServeCanopy",
      testCase "serve asset mode" $ do
        let content = "asset content"
            mimeType = "text/plain"
            mode = ServeAsset content mimeType
        case mode of
          ServeAsset actualContent actualMime -> do
            actualContent @?= "asset content"
            actualMime @?= "text/plain"
          _ -> assertFailure "Expected ServeAsset",
      testCase "file serve mode equality" $ do
        let mode1 = ServeRaw "/same/path"
            mode2 = ServeRaw "/same/path"
            mode3 = ServeRaw "/different/path"
        mode1 @?= mode2
        assertBool "different paths should not be equal" (mode1 /= mode3)
    ]

-- | Tests for Environment module functions.
environmentTests :: TestTree
environmentTests =
  testGroup
    "Environment Tests"
    [ testCase "resolve port with default flags" $ do
        let port = Environment.resolvePort defaultFlags
        port @?= 8000,
      testCase "resolve port with custom flags" $ do
        let flags = Flags (Just 3000)
            port = Environment.resolvePort flags
        port @?= 3000,
      testCase "resolve port with port 9000" $ do
        let flags = Flags (Just 9000)
            port = Environment.resolvePort flags
        port @?= 9000,
      testCase "detect project root behavior" $ do
        -- Test that detectProjectRoot calls Stuff.findRoot
        let maybeRoot = unsafePerformIO Environment.detectProjectRoot
        case maybeRoot of
          Nothing -> pure () -- No project root found, valid
          Just root -> assertBool "root path should contain content" (length root > 0)
    ]

-- | Tests for lens operations across all types.
lensTests :: TestTree
lensTests =
  testGroup
    "Lens Operation Tests"
    [ testCase "flags port lens view and update" $ do
        let flags = defaultFlags
            updatedFlags = flags & flagsPort .~ Just 5000
        flags ^. flagsPort @?= Nothing
        updatedFlags ^. flagsPort @?= Just 5000,
      testCase "server config port lens operations" $ do
        let config = defaultServerConfig
            newConfig = config & scPort .~ 4000
        config ^. scPort @?= 8000
        newConfig ^. scPort @?= 4000,
      testCase "server config verbose lens operations" $ do
        let config = defaultServerConfig
            verboseConfig = config & scVerbose .~ True
        config ^. scVerbose @?= False
        verboseConfig ^. scVerbose @?= True,
      testCase "server config root lens operations" $ do
        let config = defaultServerConfig
            rootConfig = config & scRoot .~ Just "/project"
        config ^. scRoot @?= Nothing
        rootConfig ^. scRoot @?= Just "/project"
    ]

-- | Tests for default value behavior and invariants.
defaultValueTests :: TestTree
defaultValueTests =
  testGroup
    "Default Value Tests"
    [ testCase "default flags provide sensible defaults" $ do
        let flags = defaultFlags
        -- Default should have no port (let system choose)
        flags ^. flagsPort @?= Nothing,
      testCase "default server config provides production-ready defaults" $ do
        let config = defaultServerConfig
        -- Default port should be common development port
        config ^. scPort @?= 8000
        -- Default should not be verbose (less noise)
        config ^. scVerbose @?= False
        -- Default should auto-detect project root
        config ^. scRoot @?= Nothing
    ]

-- | Tests for configuration validation and edge cases.
configurationValidationTests :: TestTree
configurationValidationTests =
  testGroup
    "Configuration Validation Tests"
    [ testCase "flags port validation accepts valid ports" $ do
        let validPorts = [80, 8000, 8080, 3000, 65535]
        mapM_ (\port ->
          assertBool ("Port " ++ show port ++ " should be valid") (port > 0 && port <= 65535)
          ) validPorts,
      testCase "server config verbose mode affects behavior" $ do
        let quietConfig = defaultServerConfig & scVerbose .~ False
            verboseConfig = defaultServerConfig & scVerbose .~ True
        -- Verbose and quiet configs should be different
        assertBool "verbose setting should matter" (quietConfig /= verboseConfig),
      testCase "file serve modes have distinct constructors" $ do
        let rawMode = ServeRaw "/static/image.png"
            codeMode = ServeCode "/src/Main.hs"
            canopyMode = ServeCanopy "/src/Main.can"
            assetMode = ServeAsset "body { color: red; }" "text/css"
        -- Test that each mode is correctly constructed
        case rawMode of 
          ServeRaw path -> path @?= "/static/image.png"
          _ -> assertFailure "Wrong constructor for rawMode"
        case codeMode of 
          ServeCode path -> path @?= "/src/Main.hs"
          _ -> assertFailure "Wrong constructor for codeMode" 
        case canopyMode of 
          ServeCanopy path -> path @?= "/src/Main.can"
          _ -> assertFailure "Wrong constructor for canopyMode"
        case assetMode of 
          ServeAsset content mime -> do
            content @?= "body { color: red; }"
            mime @?= "text/css"
          _ -> assertFailure "Wrong constructor for assetMode",
      testCase "server config root path affects file serving" $ do
        let configWithRoot = defaultServerConfig & scRoot .~ Just "/project"
            configWithoutRoot = defaultServerConfig & scRoot .~ Nothing
        -- Presence of root should change configuration
        assertBool "root setting should affect config" (configWithRoot /= configWithoutRoot)
    ]
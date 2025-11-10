{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Develop.Types module.
--
-- Tests all type constructors, behavioral patterns, default values, and
-- data operations. Validates type safety and business logic following CLAUDE.md
-- standards with behavioral verification.
--
-- @since 0.19.1
module Unit.Develop.TypesTest (tests) where

import Control.Lens ((&), (.~), (^.))
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import Develop.Types
  ( CompileResult (..),
    FileServeMode (..),
    Flags (..),
    ServerConfig (..),
    defaultFlags,
    defaultServerConfig,
    flagsPort,
    scPort,
    scRoot,
    scVerbose,
  )
import qualified Reporting.Exit as Exit
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit (assertBool, (@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Types module.
tests :: TestTree
tests =
  Test.testGroup
    "Develop.Types Tests"
    [ flagsDataTests,
      serverConfigDataTests,
      compileResultDataTests,
      fileServeModeDataTests,
      behavioralOperationTests,
      defaultValueTests,
      equalityTests
    ]

-- | Tests for Flags data type.
flagsDataTests :: TestTree
flagsDataTests =
  Test.testGroup
    "Flags Data Type Tests"
    [ Test.testCase "flags supports no port configuration" $ do
        let flags = Flags Nothing
        case flags of
          Flags Nothing -> pure ()
          _ -> Test.assertFailure "Expected no port configuration",
      Test.testCase "flags supports specific port configuration" $ do
        let flags = Flags (Just 3000)
        case flags of
          Flags (Just 3000) -> pure ()
          _ -> Test.assertFailure "Expected port 3000 configuration",
      Test.testCase "flags supports high port numbers" $ do
        let flags = Flags (Just 8080)
        case flags of
          Flags (Just 8080) -> pure ()
          _ -> Test.assertFailure "Expected port 8080 configuration",
      Test.testCase "flags configuration can be updated" $ do
        let original = Flags Nothing
            updated = original & flagsPort .~ Just 5000
        case (original, updated) of
          (Flags Nothing, Flags (Just 5000)) -> pure ()
          _ -> Test.assertFailure "Expected successful port update",
      Test.testCase "port configuration can be cleared" $ do
        let original = Flags (Just 3000)
            cleared = original & flagsPort .~ Nothing
        case (original, cleared) of
          (Flags (Just 3000), Flags Nothing) -> pure ()
          _ -> Test.assertFailure "Expected successful port clearing"
    ]

-- | Tests for ServerConfig data type.
serverConfigDataTests :: TestTree
serverConfigDataTests =
  Test.testGroup
    "ServerConfig Data Type Tests"
    [ Test.testCase "server config supports full configuration" $ do
        let config = ServerConfig 3000 True (Just "/project")
        case config of
          ServerConfig 3000 True (Just "/project") -> pure ()
          _ -> Test.assertFailure "Expected full server configuration",
      Test.testCase "server config supports minimal configuration" $ do
        let config = ServerConfig 8000 False Nothing
        case config of
          ServerConfig 8000 False Nothing -> pure ()
          _ -> Test.assertFailure "Expected minimal server configuration",
      Test.testCase "server config preserves fields during updates" $ do
        let original = ServerConfig 3000 False (Just "/root")
            updated = original & scPort .~ 9000 & scVerbose .~ True
        case (original, updated) of
          (ServerConfig 3000 False (Just "/root"), ServerConfig 9000 True (Just "/root")) -> pure ()
          _ -> Test.assertFailure "Expected field preservation during update"
    ]

-- | Tests for CompileResult data type.
compileResultDataTests :: TestTree
compileResultDataTests =
  Test.testGroup
    "CompileResult Data Type Tests"
    [ Test.testCase "compile success with builder content" $ do
        let builder = B.stringUtf8 "console.log('Hello, world!');"
            result = CompileSuccess builder
        case result of
          CompileSuccess _ -> pure ()
          _ -> Test.assertFailure "Expected CompileSuccess",
      Test.testCase "compile error with reactor no outline" $ do
        let result = CompileError Exit.ReactorNoOutline
        case result of
          CompileError Exit.ReactorNoOutline -> pure ()
          _ -> Test.assertFailure "Expected CompileError with ReactorNoOutline",
      Test.testCase "compile error with reactor no outline" $ do
        let result = CompileError Exit.ReactorNoOutline
        case result of
          CompileError Exit.ReactorNoOutline -> pure ()
          _ -> Test.assertFailure "Expected CompileError with ReactorNoOutline"
    ]

-- | Tests for FileServeMode data type.
fileServeModeDataTests :: TestTree
fileServeModeDataTests =
  Test.testGroup
    "FileServeMode Data Type Tests"
    [ Test.testCase "serve raw mode with file path" $ do
        let mode = ServeRaw "/path/to/file.txt"
        case mode of
          ServeRaw path -> path @?= "/path/to/file.txt"
          _ -> Test.assertFailure "Expected ServeRaw",
      Test.testCase "serve code mode with source file" $ do
        let mode = ServeCode "/src/Main.hs"
        case mode of
          ServeCode path -> path @?= "/src/Main.hs"
          _ -> Test.assertFailure "Expected ServeCode",
      Test.testCase "serve canopy mode with canopy file" $ do
        let mode = ServeCanopy "/project/Main.can"
        case mode of
          ServeCanopy path -> path @?= "/project/Main.can"
          _ -> Test.assertFailure "Expected ServeCanopy",
      Test.testCase "serve asset mode with content and mime type" $ do
        let content = "body { margin: 0; }"
            mimeType = "text/css"
            mode = ServeAsset content mimeType
        case mode of
          ServeAsset actualContent actualMime -> do
            actualContent @?= "body { margin: 0; }"
            actualMime @?= "text/css"
          _ -> Test.assertFailure "Expected ServeAsset"
    ]

-- | Tests for behavioral operations across all types.
behavioralOperationTests :: TestTree
behavioralOperationTests =
  Test.testGroup
    "Behavioral Operation Tests"
    [ Test.testCase "flags distinguish port configurations" $ do
        let noPort = Flags Nothing
            withPort = Flags (Just 1234)
        case (noPort, withPort) of
          (Flags Nothing, Flags (Just 1234)) -> pure ()
          _ -> Test.assertFailure "Expected distinct port configurations",
      Test.testCase "server config port updates work correctly" $ do
        let original = ServerConfig 8000 False Nothing
            updated = original & scPort .~ 3000
        case (original, updated) of
          (ServerConfig 8000 _ _, ServerConfig 3000 _ _) -> pure ()
          _ -> Test.assertFailure "Expected successful port update",
      Test.testCase "server config verbose mode toggles correctly" $ do
        let quiet = ServerConfig 8000 False Nothing
            verbose = quiet & scVerbose .~ True
        case (quiet, verbose) of
          (ServerConfig _ False _, ServerConfig _ True _) -> pure ()
          _ -> Test.assertFailure "Expected successful verbose toggle",
      Test.testCase "server config root path updates correctly" $ do
        let defaultRoot = ServerConfig 8000 False Nothing
            customRoot = defaultRoot & scRoot .~ Just "/new/root"
        case (defaultRoot, customRoot) of
          (ServerConfig _ _ Nothing, ServerConfig _ _ (Just "/new/root")) -> pure ()
          _ -> Test.assertFailure "Expected successful root path update",
      Test.testCase "complex server config updates preserve consistency" $ do
        let original = ServerConfig 8000 False Nothing
            updated =
              original & scPort .~ 5000
                & scVerbose .~ True
                & scRoot .~ Just "/project"
        case updated of
          ServerConfig 5000 True (Just "/project") -> pure ()
          _ -> Test.assertFailure "Expected successful multi-field update"
    ]

-- | Tests for default value correctness.
defaultValueTests :: TestTree
defaultValueTests =
  Test.testGroup
    "Default Value Tests"
    [ Test.testCase "default flags provides sensible defaults" $ do
        case defaultFlags of
          Flags Nothing -> pure ()
          _ -> Test.assertFailure "Expected default flags with no port",
      Test.testCase "default server config provides standard values" $ do
        case defaultServerConfig of
          ServerConfig 8000 False Nothing -> pure ()
          _ -> Test.assertFailure "Expected standard default server config",
      Test.testCase "default values support immediate usage" $ do
        -- Should be able to use defaults directly
        case (defaultFlags, defaultServerConfig) of
          (Flags Nothing, ServerConfig 8000 False Nothing) -> pure ()
          _ -> Test.assertFailure "Expected usable default configurations"
    ]

-- | Tests for equality instances.
equalityTests :: TestTree
equalityTests =
  Test.testGroup
    "Equality Tests"
    [ Test.testCase "flags equality works correctly" $ do
        let flags1 = Flags (Just 3000)
            flags2 = Flags (Just 3000)
            flags3 = Flags (Just 8000)
            flags4 = Flags Nothing
        flags1 @?= flags2
        assertBool "different ports should not be equal" (flags1 /= flags3)
        assertBool "Nothing should not equal Just" (flags4 /= flags1),
      Test.testCase "server config equality works correctly" $ do
        let config1 = ServerConfig 3000 True (Just "/project")
            config2 = ServerConfig 3000 True (Just "/project")
            config3 = ServerConfig 8000 True (Just "/project")
        config1 @?= config2
        assertBool "different ports should not be equal" (config1 /= config3),
      Test.testCase "file serve mode equality works correctly" $ do
        let mode1 = ServeRaw "/same/path"
            mode2 = ServeRaw "/same/path"
            mode3 = ServeRaw "/different/path"
            mode4 = ServeCode "/same/path"
        mode1 @?= mode2
        assertBool "different paths should not be equal" (mode1 /= mode3)
        assertBool "different constructors should not be equal" (mode1 /= mode4)
    ]

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Develop.Types module.
--
-- Tests all type constructors, lens operations, default values, and Show
-- instances. Validates type safety and lens compliance following CLAUDE.md
-- patterns with exact value verification.
--
-- @since 0.19.1
module Unit.Develop.TypesTest (tests) where

import Control.Lens ((^.), (&), (.~))
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
    scVerbose
  )
import qualified Reporting.Exit as Exit
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=), assertBool)
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
      lensOperationTests,
      defaultValueTests,
      showInstanceTests,
      equalityTests
    ]

-- | Tests for Flags data type.
flagsDataTests :: TestTree
flagsDataTests =
  Test.testGroup
    "Flags Data Type Tests"
    [ Test.testCase "flags construction with no port" $ do
        let flags = Flags Nothing
        flags ^. flagsPort @?= Nothing,
      Test.testCase "flags construction with port 3000" $ do
        let flags = Flags (Just 3000)
        flags ^. flagsPort @?= Just 3000,
      Test.testCase "flags construction with port 8080" $ do
        let flags = Flags (Just 8080)
        flags ^. flagsPort @?= Just 8080,
      Test.testCase "flags lens update from Nothing to Just" $ do
        let flags = Flags Nothing
            updated = flags & flagsPort .~ Just 5000
        flags ^. flagsPort @?= Nothing
        updated ^. flagsPort @?= Just 5000,
      Test.testCase "flags lens update from Just to Nothing" $ do
        let flags = Flags (Just 3000)
            updated = flags & flagsPort .~ Nothing
        flags ^. flagsPort @?= Just 3000
        updated ^. flagsPort @?= Nothing
    ]

-- | Tests for ServerConfig data type.
serverConfigDataTests :: TestTree
serverConfigDataTests =
  Test.testGroup
    "ServerConfig Data Type Tests"
    [ Test.testCase "server config construction with all fields" $ do
        let config = ServerConfig 3000 True (Just "/project")
        config ^. scPort @?= 3000
        config ^. scVerbose @?= True
        config ^. scRoot @?= Just "/project",
      Test.testCase "server config construction with minimal fields" $ do
        let config = ServerConfig 8000 False Nothing
        config ^. scPort @?= 8000
        config ^. scVerbose @?= False
        config ^. scRoot @?= Nothing,
      Test.testCase "server config lens updates preserve other fields" $ do
        let config = ServerConfig 3000 False (Just "/root")
            updated = config & scPort .~ 9000 & scVerbose .~ True
        updated ^. scPort @?= 9000
        updated ^. scVerbose @?= True
        updated ^. scRoot @?= Just "/root" -- Preserved
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

-- | Tests for lens operations across all types.
lensOperationTests :: TestTree
lensOperationTests =
  Test.testGroup
    "Lens Operation Tests"
    [ Test.testCase "flags port lens view operations" $ do
        let flags1 = Flags Nothing
            flags2 = Flags (Just 1234)
        flags1 ^. flagsPort @?= Nothing
        flags2 ^. flagsPort @?= Just 1234,
      Test.testCase "server config port lens operations" $ do
        let config = ServerConfig 8000 False Nothing
            updated = config & scPort .~ 3000
        config ^. scPort @?= 8000
        updated ^. scPort @?= 3000,
      Test.testCase "server config verbose lens operations" $ do
        let config = ServerConfig 8000 False Nothing
            updated = config & scVerbose .~ True
        config ^. scVerbose @?= False
        updated ^. scVerbose @?= True,
      Test.testCase "server config root lens operations" $ do
        let config = ServerConfig 8000 False Nothing
            updated = config & scRoot .~ Just "/new/root"
        config ^. scRoot @?= Nothing
        updated ^. scRoot @?= Just "/new/root",
      Test.testCase "multiple lens updates in chain" $ do
        let config = ServerConfig 8000 False Nothing
            updated = config & scPort .~ 5000 
                              & scVerbose .~ True 
                              & scRoot .~ Just "/project"
        updated ^. scPort @?= 5000
        updated ^. scVerbose @?= True
        updated ^. scRoot @?= Just "/project"
    ]

-- | Tests for default value correctness.
defaultValueTests :: TestTree
defaultValueTests =
  Test.testGroup
    "Default Value Tests"
    [ Test.testCase "default flags has no port set" $ do
        defaultFlags ^. flagsPort @?= Nothing,
      Test.testCase "default server config has standard values" $ do
        defaultServerConfig ^. scPort @?= 8000
        defaultServerConfig ^. scVerbose @?= False
        defaultServerConfig ^. scRoot @?= Nothing,
      Test.testCase "default values are consistent with documentation" $ do
        -- Default port should be 8000 as documented
        defaultServerConfig ^. scPort @?= 8000
        -- Default verbose should be False for clean output
        defaultServerConfig ^. scVerbose @?= False
    ]

-- | Tests for Show instances producing exact output.
showInstanceTests :: TestTree
showInstanceTests =
  Test.testGroup
    "Show Instance Tests"
    [ Test.testCase "flags show with no port" $ do
        let flags = Flags Nothing
        show flags @?= "Flags {_flagsPort = Nothing}",
      Test.testCase "flags show with port 3000" $ do
        let flags = Flags (Just 3000)
        show flags @?= "Flags {_flagsPort = Just 3000}",
      Test.testCase "server config show with default values" $ do
        let config = ServerConfig 8000 False Nothing
        show config @?= "ServerConfig {_scPort = 8000, _scVerbose = False, _scRoot = Nothing}",
      Test.testCase "server config show with all fields set" $ do
        let config = ServerConfig 3000 True (Just "/project")
        show config @?= "ServerConfig {_scPort = 3000, _scVerbose = True, _scRoot = Just \"/project\"}",
      Test.testCase "file serve mode show instances" $ do
        show (ServeRaw "/file.txt") @?= "ServeRaw \"/file.txt\""
        show (ServeCode "/code.hs") @?= "ServeCode \"/code.hs\""
        show (ServeCanopy "/main.can") @?= "ServeCanopy \"/main.can\""
        show (ServeAsset "content" "text/plain") @?= "ServeAsset \"content\" \"text/plain\"",
      Test.testCase "default values show correctly" $ do
        show defaultFlags @?= "Flags {_flagsPort = Nothing}"
        show defaultServerConfig @?= "ServerConfig {_scPort = 8000, _scVerbose = False, _scRoot = Nothing}"
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
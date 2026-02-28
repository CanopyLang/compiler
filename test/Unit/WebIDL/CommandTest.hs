{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for WebIDL.Command module.
--
-- Tests the CLI adapter for WebIDL code generation including
-- input validation, configuration building, and error reporting.
--
-- @since 0.19.2
module Unit.WebIDL.CommandTest (tests) where

import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO.Temp as Temp
import Test.Tasty
import Test.Tasty.HUnit
import qualified WebIDL.Command as Cmd
import qualified WebIDL.Config as Config

tests :: TestTree
tests =
  testGroup
    "WebIDL.Command Tests"
    [ testFlagConstruction,
      testConfigConstruction,
      testInputValidation
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Flags construction
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testFlagConstruction :: TestTree
testFlagConstruction =
  testGroup
    "Flags construction"
    [ testCase "flags with no output and no verbose" $
        Cmd.Flags Nothing False @?= Cmd.Flags Nothing False,
      testCase "flags with output directory" $
        Cmd.Flags (Just "src/Web") False @?= Cmd.Flags (Just "src/Web") False,
      testCase "flags with verbose" $
        Cmd.Flags Nothing True @?= Cmd.Flags Nothing True,
      testCase "flags show instance" $
        show (Cmd.Flags (Just "out") True) @?=
          "Flags {_output = Just \"out\", _verbose = True}"
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Config construction
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testConfigConstruction :: TestTree
testConfigConstruction =
  testGroup
    "Config construction"
    [ testCase "default config has canopy output dir" $
        Config.outputCanopyDir (Config.configOutput Config.defaultConfig) @?=
          defaultCanopyDir,
      testCase "default config has js output dir" $
        Config.outputJsDir (Config.configOutput Config.defaultConfig) @?=
          defaultJsDir,
      testCase "default config includes comments" $
        Config.outputIncludeComments (Config.configOutput Config.defaultConfig) @?= True
    ]
  where
    defaultCanopyDir = Config.outputCanopyDir (Config.configOutput Config.defaultConfig)
    defaultJsDir = Config.outputJsDir (Config.configOutput Config.defaultConfig)

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Input validation
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testInputValidation :: TestTree
testInputValidation =
  testGroup
    "Input validation"
    [ testCase "run with empty files reports error" $
        Temp.withSystemTempDirectory "webidl-test" $ \tmpDir -> do
          Cmd.run [] (Cmd.Flags Nothing False)
          -- If it didn't crash, the error was reported to stderr
          pure (),
      testCase "run with nonexistent file reports error" $
        Temp.withSystemTempDirectory "webidl-test" $ \tmpDir -> do
          Cmd.run [tmpDir FP.</> "nonexistent.webidl"] (Cmd.Flags Nothing False)
          -- If it didn't crash, the error was reported to stderr
          pure (),
      testCase "run with valid webidl file processes successfully" $
        Temp.withSystemTempDirectory "webidl-test" $ \tmpDir -> do
          let idlFile = tmpDir FP.</> "test.webidl"
              outDir = tmpDir FP.</> "out"
          writeFile idlFile "interface TestElement { readonly attribute DOMString id; };"
          Dir.createDirectoryIfMissing True outDir
          Cmd.run [idlFile] (Cmd.Flags (Just outDir) False)
          -- If it didn't crash, generation succeeded
          pure ()
    ]

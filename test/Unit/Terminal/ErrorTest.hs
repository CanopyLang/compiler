{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for main Terminal.Error module.
--
-- Tests the main error handling functions and module integration
-- to ensure all sub-modules work together correctly.
--
-- @since 0.19.1
module Unit.Terminal.ErrorTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Terminal.Error
  ( ArgError (..),
    Error (..),
    Expectation (..),
    FlagError (..),
    convertErrorToDocs,
    generateCommandSuggestions,
    generateFlagSuggestions
  )
import Terminal.Internal (Args (..), CompleteArgs (..), Flag (..), Flags (..), Parser (..), RequiredArgs (..))

tests :: TestTree
tests = testGroup "Terminal.Error Tests"
  [ testErrorConversion
  , testModuleIntegration
  , testExportedFunctions
  ]

-- | Test error conversion to documentation
testErrorConversion :: TestTree
testErrorConversion = testGroup "Error Conversion Tests"
  [ testCase "converts BadFlag error" $ do
      let flagError = FlagWithValue "verbose" "true"
          error = BadFlag flagError
      docs <- convertErrorToDocs error
      assertBool "BadFlag produces documentation" (not (null docs))
  , testCase "converts BadArgs error with single error" $ do
      let expectation = Expectation "file" (pure ["test.txt"])
          argError = ArgMissing expectation
          args = Exactly (Done id)
          error = BadArgs [(args, argError)]
      docs <- convertErrorToDocs error
      assertBool "BadArgs produces documentation" (not (null docs))
  , testCase "converts BadArgs error with empty list" $ do
      let error = BadArgs []
      docs <- convertErrorToDocs error
      assertBool "Empty BadArgs produces documentation" (not (null docs))
  , testCase "converts BadArgs error with multiple errors" $ do
      let expectation = Expectation "file" (pure ["test.txt"])
          argError1 = ArgMissing expectation
          argError2 = ArgBad "invalid" expectation
          args = Exactly (Done id)
          error = BadArgs [(args, argError1), (args, argError2)]
      docs <- convertErrorToDocs error
      assertBool "Multiple BadArgs produces documentation" (not (null docs))
  ]

-- | Test module integration between sub-modules
testModuleIntegration :: TestTree
testModuleIntegration = testGroup "Module Integration Tests"
  [ testCase "error types work with display functions" $ do
      let expectation = Expectation "number" (pure ["1", "2", "3"])
          argError = ArgBad "not-a-number" expectation
      docs <- convertErrorToDocs (BadArgs [(Exactly (Done id), argError)])
      assertBool "BadArgs with ArgBad produces error documentation" (length docs >= 1)
  , testCase "suggestions integrate with error display" $ do
      let commands = ["build", "test", "install"]
          suggestions = generateCommandSuggestions "biuld" commands
      assertBool "Contains build suggestion for biuld typo" ("build" `elem` suggestions)
  , testCase "flag suggestions work with flag types" $ do
      let parser = Parser "file" "files" Just (\_ -> pure []) (\_ -> pure ["example"])
          flag = Flag "output" parser "output file"
          flags = FMore (FDone id) flag
          suggestions = generateFlagSuggestions "outpu" flags
      assertBool "Contains flag suggestions for outpu typo" (length suggestions > 0)
  ]

-- | Test exported functions are available and work
testExportedFunctions :: TestTree
testExportedFunctions = testGroup "Exported Functions Tests"
  [ testCase "all error types are exported" $ do
      let expectation = Expectation "file" (pure ["test.txt"])
          argError = ArgMissing expectation
          flagError = FlagWithValue "verbose" "true"
          badArgsError = BadArgs []
          badFlagError = BadFlag flagError
      -- Test all constructors are available and produce expected output
      show argError @?= "ArgMissing Expectation file <IO [String]>"
      show flagError @?= "FlagWithValue \"verbose\" \"true\""
      show badArgsError @?= "BadArgs [0 errors]"
      show badFlagError @?= "BadFlag (FlagWithValue \"verbose\" \"true\")"
  , testCase "suggestion functions are exported" $ do
      let commands = ["build", "test"]
          cmdSuggestions = generateCommandSuggestions "buld" commands
      let parser = Parser "file" "files" Just (\_ -> pure []) (\_ -> pure ["example"])
          flags = FDone ()
          flagSuggestions = generateFlagSuggestions "xyz" flags
      assertBool "Command suggestions finds build for buld" ("build" `elem` cmdSuggestions)
      cmdSuggestions @?= ["build"]
  , testCase "conversion functions are exported" $ do
      let expectation = Expectation "file" (pure ["test.txt"])
          argError = ArgMissing expectation
          error = BadArgs [(Exactly (Done id), argError)]
      docs <- convertErrorToDocs error
      length docs @?= 2
  ]
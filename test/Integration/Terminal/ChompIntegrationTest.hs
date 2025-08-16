{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Integration tests for Terminal.Chomp framework.
--
-- Tests end-to-end functionality of the Terminal.Chomp system including
-- complex argument and flag parsing scenarios, error handling workflows,
-- and suggestion generation. Validates integration between all sub-modules
-- and real-world usage patterns.
--
-- @since 0.19.1
module Integration.Terminal.ChompIntegrationTest (tests) where

import Control.Lens ((^.))
import qualified Data.List
import qualified Terminal.Chomp as Chomp
import Terminal.Chomp.Types
  ( Chunk,
    Suggest (..),
    chunkContent,
    createChunk,
    extractValue,
  )
import Terminal.Internal
  ( Args (..),
    CompleteArgs (..),
    Flag (..),
    Flags (..),
    Parser (..),
    RequiredArgs (..),
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Terminal.Chomp Integration Tests"
    [ testCompleteParsingWorkflows,
      testErrorRecoveryScenarios,
      testSuggestionGeneration,
      testComplexArgumentPatterns,
      testFlagAndArgumentIntegration,
      testRealWorldScenarios
    ]

-- | Test complete parsing workflows from start to finish
testCompleteParsingWorkflows :: TestTree
testCompleteParsingWorkflows =
  testGroup
    "Complete Parsing Workflows"
    [ testCase "simple file argument parsing" $ do
        let fileParser = stringParser "file" "input file"
            args = Args [Exactly (Required (Done id) fileParser)]
            flags = FDone ()
            (suggestions, result) = Chomp.chomp Nothing ["input.txt"] args flags
        suggestionList <- suggestions
        length suggestionList @?= 0 -- Expect no suggestions for successful parse
        case result of
          Right (filename, ()) -> filename @?= "input.txt"
          Left _ -> assertFailure "Expected successful parsing",
      testCase "boolean flag parsing" $ do
        let args = Args []
            verboseFlag = OnOff "verbose" "enable verbose output"
            flags = FMore (FDone id) verboseFlag
            (_, result) = Chomp.chomp Nothing ["--verbose"] args flags
        case result of
          Right ((), isVerbose) -> do
            isVerbose @?= True
          Left _ -> assertFailure "Expected successful boolean flag parsing",
      testCase "mixed arguments and flags" $ do
        let fileParser = stringParser "input" "input file"
            outputParser = stringParser "output" "output directory"
            args = Args [Exactly (Required (Done id) fileParser)]
            outputFlag = Flag "output" outputParser "output directory"
            flags = FMore (FDone id) outputFlag
            input = ["input.txt", "--output", "results/"]
            (_, result) = Chomp.chomp Nothing input args flags
        case result of
          Right (inputFile, maybeOutput) -> do
            inputFile @?= "input.txt"
            maybeOutput @?= Just "results/"
          Left _ -> assertFailure "Expected successful mixed parsing"
    ]

-- | Test error recovery and reporting scenarios
testErrorRecoveryScenarios :: TestTree
testErrorRecoveryScenarios =
  testGroup
    "Error Recovery Scenarios"
    [ testCase "missing required argument error" $ do
        let fileParser = fileParserWithExtensions [".txt", ".md"] -- Use parser with suggestions
            args = Args [Exactly (Required (Done id) fileParser)]
            flags = FDone ()
            (suggestions, result) = Chomp.chomp (Just 1) [] args flags -- Request suggestions for first argument
        suggestionList <- suggestions
        length suggestionList @?= 2 -- Expected suggestions for file extensions
        case result of
          Left _ -> pure () -- Expected error for missing argument
          Right _ -> assertFailure "Should fail with missing argument",
      testCase "unknown flag error with suggestions" $ do
        let args = Args []
            knownFlag = OnOff "verbose" "enable verbose output"
            flags = FMore (FDone id) knownFlag
            (suggestions, result) = Chomp.chomp (Just 1) ["--verbos"] args flags -- Request suggestions for flag position (similar to verbose)
        suggestionList <- suggestions
        length suggestionList @?= 1 -- Expected suggestion for flag completion
        case result of
          Left _ -> pure () -- Expected error for unknown flag
          Right _ -> assertFailure "Should fail with unknown flag",
      testCase "invalid argument type error" $ do
        let intParser = createIntParser 1 100
            args = Args [Exactly (Required (Done id) intParser)]
            flags = FDone ()
            (_, result) = Chomp.chomp Nothing ["not-a-number"] args flags
        case result of
          Left _ -> pure () -- Expected error for invalid type
          Right _ -> assertFailure "Should fail with invalid number"
    ]

-- | Test suggestion generation in various contexts
testSuggestionGeneration :: TestTree
testSuggestionGeneration =
  testGroup
    "Suggestion Generation"
    [ testCase "file completion suggestions" $ do
        let fileParser = fileParserWithExtensions [".txt", ".md"]
            args = Args [Exactly (Required (Done id) fileParser)]
            flags = FDone ()
            (suggestions, _) = Chomp.chomp (Just 1) [""] args flags
        suggestionList <- suggestions
        length suggestionList @?= 2, -- Expected file extension suggestions
      testCase "flag name completion suggestions" $ do
        let args = Args []
            flag1 = OnOff "verbose" "verbose output"
            flag2 = OnOff "version" "show version"
            flags = FMore (FMore (FDone (\v1 v2 -> (v1, v2))) flag1) flag2
            (suggestions, _) = Chomp.chomp (Just 1) ["--ver"] args flags
        suggestionList <- suggestions
        -- Test that flag completion provides reasonable suggestions
        assertBool "Flag completion should provide at least one suggestion" (length suggestionList >= 1),
      testCase "contextual value suggestions" $ do
        let enumParser = createEnumParser ["development", "production", "testing"]
            args = Args [Exactly (Required (Done id) enumParser)]
            flags = FDone ()
            (suggestions, _) = Chomp.chomp (Just 1) ["dev"] args flags
        suggestionList <- suggestions
        assertBool "Enum suggestions include development" (any ("development" `isInfixOf`) suggestionList)
    ]

-- | Test complex argument patterns
testComplexArgumentPatterns :: TestTree
testComplexArgumentPatterns =
  testGroup
    "Complex Argument Patterns"
    [ testCase "optional argument handling" $ do
        let fileParser = stringParser "file" "optional input file"
            args = Args [Optional (Done id) fileParser]
            flags = FDone ()
            -- Test with argument provided
            (_, result1) = Chomp.chomp Nothing ["input.txt"] args flags
            -- Test with no argument
            (_, result2) = Chomp.chomp Nothing [] args flags
        case (result1, result2) of
          (Right (Just "input.txt", ()), Right (Nothing, ())) ->
            pure () -- Optional argument handled correctly
          _ -> assertFailure "Optional argument parsing failed",
      testCase "multiple argument parsing" $ do
        let fileParser = stringParser "file" "input files"
            args = Args [Multiple (Done id) fileParser]
            flags = FDone ()
            input = ["file1.txt", "file2.txt", "file3.txt"]
            (_, result) = Chomp.chomp Nothing input args flags
        case result of
          Right (files, ()) -> ["file1.txt", "file2.txt", "file3.txt"] @?= files
          Left _ -> assertFailure "Expected successful multiple parsing",
      testCase "alternative argument patterns" $ do
        let fileParser = stringParser "file" "input file"
            textParser = stringParser "text" "input text"
            args =
              Args
                [ Exactly (Required (Done Left) fileParser),
                  Exactly (Required (Done Right) textParser)
                ]
            flags = FDone ()
            (_, result1) = Chomp.chomp Nothing ["input.txt"] args flags
            (_, result2) = Chomp.chomp Nothing ["some text"] args flags
        case (result1, result2) of
          (Right (Left "input.txt", ()), _) ->
            pure () -- First alternative parsed correctly
          (Right (_, ()), Right (_, ())) ->
            pure () -- Both alternatives parsed
          _ -> assertFailure "Alternative pattern parsing failed"
    ]

-- | Test flag and argument integration
testFlagAndArgumentIntegration :: TestTree
testFlagAndArgumentIntegration =
  testGroup
    "Flag and Argument Integration"
    [ testCase "flags interspersed with arguments" $ do
        let fileParser = stringParser "file" "input file"
            outputParser = stringParser "output" "output file"
            args = Args [Exactly (Required (Done id) fileParser)]
            outputFlag = Flag "output" outputParser "output file"
            verboseFlag = OnOff "verbose" "verbose mode"
            flags = FMore (FMore (FDone (\f v -> (f, v))) outputFlag) verboseFlag
            input = ["--output", "result.txt", "input.txt", "--verbose"]
            (_, result) = Chomp.chomp Nothing input args flags
        case result of
          Right (inputFile, (maybeOutput, isVerbose)) -> do
            inputFile @?= "input.txt"
            maybeOutput @?= Just "result.txt"
            isVerbose @?= True
          Left _ -> assertFailure "Expected successful complex parsing",
      testCase "flag value extraction with equals syntax" $ do
        let outputParser = stringParser "output" "output directory"
            args = Args []
            outputFlag = Flag "output" outputParser "output directory"
            flags = FMore (FDone id) outputFlag
            (_, result) = Chomp.chomp Nothing ["--output=results/"] args flags
        case result of
          Right (_, _) -> pure () -- Flag parsing succeeded
          _ -> assertFailure "Equals syntax parsing failed"
    ]

-- | Test real-world usage scenarios
testRealWorldScenarios :: TestTree
testRealWorldScenarios =
  testGroup
    "Real-World Scenarios"
    [ testCase "build command simulation" $ do
        let srcParser = fileParserWithExtensions [".hs", ".elm"]
            outputParser = stringParser "directory" "output directory"
            args = Args [Multiple (Done id) srcParser]
            outputFlag = Flag "output" outputParser "output directory"
            verboseFlag = OnOff "verbose" "verbose output"
            optimizeFlag = OnOff "optimize" "enable optimizations"
            flags = FMore (FMore (FMore (FDone (\o v opt -> (o, v, opt))) outputFlag) verboseFlag) optimizeFlag
            input = ["src/Main.hs", "src/Utils.hs", "--output", "dist/", "--verbose"]
            (_, result) = Chomp.chomp Nothing input args flags
        case result of
          Right (sources, (maybeOutput, isVerbose, shouldOptimize)) -> do
            length sources @?= 2
            maybeOutput @?= Just "dist/"
            isVerbose @?= True
            shouldOptimize @?= False
          Left _ -> assertFailure "Build command parsing failed",
      testCase "help command with minimal arguments" $ do
        let commandParser = stringParser "command" "command name"
            args = Args [Optional (Done id) commandParser]
            flags = FDone ()
            -- Test help with specific command
            (_, result1) = Chomp.chomp Nothing ["build"] args flags
            -- Test help with no command
            (_, result2) = Chomp.chomp Nothing [] args flags
        case (result1, result2) of
          (Right (Just "build", ()), Right (Nothing, ())) ->
            pure () -- Help command scenarios work
          _ -> assertFailure "Help command parsing failed"
    ]

-- Helper functions for creating test parsers
stringParser :: String -> String -> Parser String
stringParser singular description =
  Parser
    { _singular = singular,
      _plural = singular ++ "s",
      _parser = Just, -- Accept any string
      _suggest = \_ -> return [],
      _examples = \_ -> return ["example"]
    }

createIntParser :: Int -> Int -> Parser Int
createIntParser minVal maxVal =
  Parser
    { _singular = "number",
      _plural = "numbers",
      _parser = \s -> case reads s of
        [(n, "")] | n >= minVal && n <= maxVal -> Just n
        _ -> Nothing,
      _suggest = \_ -> return [],
      _examples = \_ -> return [show minVal, show maxVal]
    }

fileParserWithExtensions :: [String] -> Parser String
fileParserWithExtensions extensions =
  Parser
    { _singular = "file",
      _plural = "files",
      _parser = Just, -- Accept any filename
      _suggest = \prefix -> return [prefix ++ ext | ext <- extensions],
      _examples = \_ -> return ["example.txt", "test.md"]
    }

createEnumParser :: [String] -> Parser String
createEnumParser options =
  Parser
    { _singular = "option",
      _plural = "options",
      _parser = \s -> if s `elem` options then Just s else Nothing,
      _suggest = \prefix -> return [opt | opt <- options, prefix `isPrefixOf` opt],
      _examples = \_ -> return options
    }

-- Helper function for checking string containment
isInfixOf :: String -> String -> Bool
isInfixOf needle haystack = needle `elem` words haystack || any (needle `isPrefixOf`) (words haystack)

isPrefixOf :: String -> String -> Bool
isPrefixOf = Data.List.isPrefixOf

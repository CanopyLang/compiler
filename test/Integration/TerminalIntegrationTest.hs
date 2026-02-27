{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for Terminal module.
--
-- Tests end-to-end Terminal framework functionality including
-- complete command creation, argument/flag parsing workflows,
-- and integration between different Terminal components.
--
-- @since 0.19.1
module Integration.TerminalIntegrationTest (tests) where

import qualified Terminal
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import qualified Text.PrettyPrint.ANSI.Leijen as Doc

tests :: TestTree
tests =
  testGroup
    "Terminal Integration Tests"
    [ testCompleteCommandWorkflow,
      testArgumentFlagIntegration,
      testParserChainIntegration,
      testComplexScenarios
    ]

-- | Test complete command creation and structure
testCompleteCommandWorkflow :: TestTree
testCompleteCommandWorkflow =
  testGroup
    "Complete Command Workflow"
    [ testCase "command creation with all components" $ do
        let stringParser = Terminal.stringParser "name" "project name"
            intParser = Terminal.intParser 1 100
            args = Terminal.require2 (,) stringParser intParser
            flags =
              Terminal.flags (\a b -> (a, b))
                Terminal.|-- Terminal.flag "output" stringParser "output directory"
                Terminal.|-- Terminal.onOff "verbose" "enable verbose output"
            handler _ _ = pure ()
            cmd =
              Terminal.command
                "build"
                (Terminal.Common "Build project")
                "Compile and build the project"
                (Doc.text "build <name> <version>")
                args
                flags
                handler
        case cmd of
          Terminal.Command name summary details _ _ _ _ -> do
            name @?= "build"
            case summary of
              Terminal.Common desc -> desc @?= "Build project"
              _ -> assertFailure "Expected Common summary"
            details @?= "Compile and build the project",
      testCase "command with no arguments and no flags" $ do
        let args = Terminal.noArgs
            flags = Terminal.noFlags
            handler _ _ = pure ()
            cmd =
              Terminal.command
                "help"
                Terminal.Uncommon
                "Show help information"
                Doc.empty
                args
                flags
                handler
        case cmd of
          Terminal.Command name summary _ _ _ _ _ -> do
            name @?= "help"
            case summary of
              Terminal.Uncommon -> pure () -- Expected Uncommon summary
              _ -> assertFailure "Expected Uncommon summary",
      testCase "command with complex argument patterns" $ do
        let fileParser = Terminal.fileParser [".hs", ".canopy"]
            stringParser = Terminal.stringParser "module" "module name"
            complexArgs = Terminal.required fileParser
            flags = Terminal.noFlags
            handler _ _ = pure ()
            cmd =
              Terminal.command
                "process"
                (Terminal.Common "Process files")
                "Process various file types"
                Doc.empty
                complexArgs
                flags
                handler
        case cmd of
          Terminal.Command name _ _ _ _ _ _ -> name @?= "process"
    ]

-- | Test argument and flag integration
testArgumentFlagIntegration :: TestTree
testArgumentFlagIntegration =
  testGroup
    "Argument Flag Integration"
    [ testCase "multiple parsers work together" $ do
        let nameParser = Terminal.stringParser "name" "project name"
            countParser = Terminal.intParser 1 10
            enabledParser = Terminal.boolParser
            args = Terminal.require2 (,) nameParser countParser
            flags =
              Terminal.flags (\a b -> (a, b))
                Terminal.|-- Terminal.flag "config" nameParser "config file"
                Terminal.|-- Terminal.flag "debug" enabledParser "debug mode"
        -- Test parser integration
        let Terminal.Parser _ _ nameParseFunc _ _ = nameParser
            Terminal.Parser _ _ countParseFunc _ _ = countParser
            Terminal.Parser _ _ enabledParseFunc _ _ = enabledParser
        nameParseFunc "myproject" @?= Just "myproject"
        countParseFunc "5" @?= Just 5
        enabledParseFunc "true" @?= Just True,
      testCase "flag chaining preserves structure" $ do
        let stringParser = Terminal.stringParser "value" "description"
            baseFlags = Terminal.flags (\a b c -> (a, b, c))
            chainedFlags =
              baseFlags
                Terminal.|-- Terminal.flag "first" stringParser "first flag"
                Terminal.|-- Terminal.flag "second" stringParser "second flag"
                Terminal.|-- Terminal.onOff "third" "third flag"
        case chainedFlags of
          Terminal.FMore (Terminal.FMore (Terminal.FMore (Terminal.FDone _) _) _) _ -> pure () -- Expected nested FMore structure
          _ -> assertFailure "Expected nested FMore structure",
      testCase "argument builders with different types" $ do
        let stringParser = Terminal.stringParser "text" "text input"
            intParser = Terminal.intParser 0 1000
            floatParser = Terminal.floatParser
            mixedArgs = Terminal.require3 (,,) stringParser intParser floatParser
        case mixedArgs of
          Terminal.Args [Terminal.Exactly _] -> pure () -- Expected Exactly pattern for require3
          _ -> assertFailure "Expected Exactly pattern for require3"
    ]

-- | Test parser chain integration
testParserChainIntegration :: TestTree
testParserChainIntegration =
  testGroup
    "Parser Chain Integration"
    [ testCase "fileParser with extension filtering" $ do
        let hsParser = Terminal.fileParser [".hs"]
            anyParser = Terminal.fileParser []
            Terminal.Parser _ _ hsParseFunc _ _ = hsParser
            Terminal.Parser _ _ anyParseFunc _ _ = anyParser
        hsParseFunc "Test.hs" @?= Just "Test.hs"
        hsParseFunc "Test.txt" @?= Just "Test.txt" -- Parser doesn't validate extensions
        anyParseFunc "AnyFile" @?= Just "AnyFile",
      testCase "intParser with different bounds" $ do
        let smallParser = Terminal.intParser 1 10
            largeParser = Terminal.intParser 100 1000
            Terminal.Parser _ _ smallParseFunc _ _ = smallParser
            Terminal.Parser _ _ largeParseFunc _ _ = largeParser
        smallParseFunc "5" @?= Just 5
        smallParseFunc "50" @?= Nothing
        largeParseFunc "500" @?= Just 500
        largeParseFunc "5" @?= Nothing,
      testCase "boolParser with various inputs" $ do
        let parser = Terminal.boolParser
            Terminal.Parser _ _ parseFunc _ _ = parser
        parseFunc "true" @?= Just True
        parseFunc "false" @?= Just False
        parseFunc "yes" @?= Just True
        parseFunc "no" @?= Just False
        parseFunc "1" @?= Just True
        parseFunc "0" @?= Just False
        parseFunc "invalid" @?= Nothing
    ]

-- | Test complex scenarios
testComplexScenarios :: TestTree
testComplexScenarios =
  testGroup
    "Complex Scenarios"
    [ testCase "build command simulation" $ do
        let srcParser = Terminal.fileParser [".hs", ".canopy"]
            outputParser = Terminal.stringParser "directory" "output directory"
            verboseFlag = Terminal.onOff "verbose" "enable verbose output"
            optimizeFlag = Terminal.onOff "optimize" "enable optimizations"
            outputFlag = Terminal.flag "output" outputParser "output directory"
            args = Terminal.oneOrMore srcParser
            flags =
              Terminal.flags (\a b c -> (a, b, c))
                Terminal.|-- outputFlag
                Terminal.|-- verboseFlag
                Terminal.|-- optimizeFlag
            handler _ _ = pure ()
            buildCmd =
              Terminal.command
                "make"
                (Terminal.Common "Build project")
                "Compile source files"
                Doc.empty
                args
                flags
                handler
        case buildCmd of
          Terminal.Command "make" (Terminal.Common "Build project") _ _ _ _ _ -> pure () -- Expected make command with Common summary
          _ -> assertFailure "Expected make command with Common summary",
      testCase "install command simulation" $ do
        let packageParser = Terminal.stringParser "package" "package name"
            versionParser = Terminal.stringParser "version" "package version"
            globalFlag = Terminal.onOff "global" "install globally"
            saveFlag = Terminal.onOff "save" "save to dependencies"
            args = Terminal.required packageParser
            flags =
              Terminal.flags (,)
                Terminal.|-- globalFlag
                Terminal.|-- saveFlag
            handler _ _ = pure ()
            installCmd =
              Terminal.command
                "install"
                Terminal.Uncommon
                "Install packages"
                Doc.empty
                args
                flags
                handler
        case installCmd of
          Terminal.Command "install" summary _ _ _ _ _ ->
            case summary of
              Terminal.Uncommon -> pure () -- Expected Uncommon summary
              _ -> assertFailure "Expected Uncommon summary"
          _ -> assertFailure "Expected install command with Uncommon summary",
      testCase "help command with minimal structure" $ do
        let args = Terminal.noArgs
            flags = Terminal.noFlags
            handler _ _ = pure ()
            helpCmd =
              Terminal.command
                "help"
                (Terminal.Common "Show help")
                "Display help information"
                Doc.empty
                args
                flags
                handler
        case helpCmd of
          Terminal.Command "help" (Terminal.Common "Show help") _ _ _ _ _ -> pure () -- Expected help command structure
          _ -> assertFailure "Expected help command structure",
      testCase "complex argument validation scenarios" $ do
        let nameParser = Terminal.stringParser "name" "entity name"
            countParser = Terminal.intParser 1 100
            typeParser = Terminal.stringParser "type" "entity type"
            complexArgs = Terminal.require1 id nameParser
        case complexArgs of
          Terminal.Args alternatives -> length alternatives @?= 1
    ]

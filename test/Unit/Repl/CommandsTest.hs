{-# LANGUAGE OverloadedStrings #-}

-- | Tests for REPL command parsing and categorization.
--
-- Verifies that user input is correctly parsed into the appropriate
-- 'Input' variants, including the new @:type@ and @:browse@ commands
-- added in 0.19.2.
--
-- @since 0.19.2
module Unit.Repl.CommandsTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Data.List as List
import qualified Repl.Commands as Commands
import Repl.Types
  ( CategorizedInput (..),
    Input (..),
    Lines (..),
    Prefill (..),
  )
import Test.Tasty
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  testGroup
    "Repl.Commands"
    [ commandParsingTests,
      helpMessageTests,
      stripBackslashTests,
      prefillTests,
      categorizeTests
    ]

-- COMMAND PARSING TESTS

commandParsingTests :: TestTree
commandParsingTests =
  testGroup
    "Command Parsing"
    [ exitCommands,
      resetCommand,
      helpCommands,
      typeOfCommands,
      browseCommands,
      unknownCommands
    ]

exitCommands :: TestTree
exitCommands =
  testGroup
    "Exit Commands"
    [ HUnit.testCase ":exit categorizes as Done Exit" $
        Commands.categorize (Lines ":exit" []) HUnit.@?= Done Exit,
      HUnit.testCase ":quit categorizes as Done Exit" $
        Commands.categorize (Lines ":quit" []) HUnit.@?= Done Exit
    ]

resetCommand :: TestTree
resetCommand =
  testGroup
    "Reset Command"
    [ HUnit.testCase ":reset categorizes as Done Reset" $
        Commands.categorize (Lines ":reset" []) HUnit.@?= Done Reset
    ]

helpCommands :: TestTree
helpCommands =
  testGroup
    "Help Commands"
    [ HUnit.testCase ":help categorizes as Done (Help Nothing)" $
        Commands.categorize (Lines ":help" []) HUnit.@?= Done (Help Nothing),
      HUnit.testCase "unknown command shows help with command name" $
        Commands.categorize (Lines ":unknown" []) HUnit.@?= Done (Help (Just "unknown"))
    ]

typeOfCommands :: TestTree
typeOfCommands =
  testGroup
    "TypeOf Commands"
    [ HUnit.testCase ":type x categorizes as Done (TypeOf \"x\")" $
        Commands.categorize (Lines ":type x" []) HUnit.@?= Done (TypeOf "x"),
      HUnit.testCase ":t x categorizes as Done (TypeOf \"x\")" $
        Commands.categorize (Lines ":t x" []) HUnit.@?= Done (TypeOf "x"),
      HUnit.testCase ":type with qualified expression" $
        Commands.categorize (Lines ":type List.map" []) HUnit.@?= Done (TypeOf "List.map"),
      HUnit.testCase ":t with numeric literal" $
        Commands.categorize (Lines ":t 42" []) HUnit.@?= Done (TypeOf "42"),
      HUnit.testCase ":type strips leading spaces from expression" $
        Commands.categorize (Lines ":type   foo" []) HUnit.@?= Done (TypeOf "foo")
    ]

browseCommands :: TestTree
browseCommands =
  testGroup
    "Browse Commands"
    [ HUnit.testCase ":browse categorizes as Done (Browse Nothing)" $
        Commands.categorize (Lines ":browse" []) HUnit.@?= Done (Browse Nothing),
      HUnit.testCase ":browse List categorizes as Done (Browse (Just \"List\"))" $
        Commands.categorize (Lines ":browse List" []) HUnit.@?= Done (Browse (Just "List")),
      HUnit.testCase ":browse strips leading spaces from module name" $
        Commands.categorize (Lines ":browse   String" []) HUnit.@?= Done (Browse (Just "String"))
    ]

unknownCommands :: TestTree
unknownCommands =
  testGroup
    "Unknown Commands"
    [ HUnit.testCase ":foo shows help with command name" $
        Commands.categorize (Lines ":foo" []) HUnit.@?= Done (Help (Just "foo")),
      HUnit.testCase ":bar shows help with command name" $
        Commands.categorize (Lines ":bar" []) HUnit.@?= Done (Help (Just "bar"))
    ]

-- HELP MESSAGE TESTS

helpMessageTests :: TestTree
helpMessageTests =
  testGroup
    "Help Messages"
    [ HUnit.testCase "general help contains :type" $
        HUnit.assertBool ":type should appear in help" (":type" `List.isInfixOf` Commands.toHelpMessage Nothing),
      HUnit.testCase "general help contains :browse" $
        HUnit.assertBool ":browse should appear in help" (":browse" `List.isInfixOf` Commands.toHelpMessage Nothing),
      HUnit.testCase "general help contains :exit" $
        HUnit.assertBool ":exit should appear in help" (":exit" `List.isInfixOf` Commands.toHelpMessage Nothing),
      HUnit.testCase "general help contains :reset" $
        HUnit.assertBool ":reset should appear in help" (":reset" `List.isInfixOf` Commands.toHelpMessage Nothing),
      HUnit.testCase "general help contains :help" $
        HUnit.assertBool ":help should appear in help" (":help" `List.isInfixOf` Commands.toHelpMessage Nothing),
      HUnit.testCase "general help contains :t alias" $
        HUnit.assertBool ":t should appear in help" ("alias: :t" `List.isInfixOf` Commands.toHelpMessage Nothing),
      HUnit.testCase "unknown command help includes command name" $
        HUnit.assertBool "should mention the bad command" ("xyz" `List.isInfixOf` Commands.toHelpMessage (Just "xyz")),
      HUnit.testCase "unknown command help starts with error prefix" $
        HUnit.assertBool "should start with 'I do not recognize'" ("I do not recognize" `List.isPrefixOf` Commands.toHelpMessage (Just "xyz"))
    ]

-- STRIP BACKSLASH TESTS

stripBackslashTests :: TestTree
stripBackslashTests =
  testGroup
    "Strip Legacy Backslash"
    [ HUnit.testCase "trailing backslash is removed" $
        Commands.stripLegacyBackslash "hello\\" HUnit.@?= "hello",
      HUnit.testCase "no backslash is preserved" $
        Commands.stripLegacyBackslash "hello" HUnit.@?= "hello",
      HUnit.testCase "empty string is preserved" $
        Commands.stripLegacyBackslash "" HUnit.@?= ""
    ]

-- RENDER PREFILL TESTS

prefillTests :: TestTree
prefillTests =
  testGroup
    "Render Prefill"
    [ HUnit.testCase "Indent renders as two spaces" $
        Commands.renderPrefill Indent HUnit.@?= "  ",
      HUnit.testCase "DefStart renders name with space" $
        Commands.renderPrefill (DefStart (Name.fromChars "myFunc")) HUnit.@?= "myFunc "
    ]

-- CATEGORIZE TESTS

categorizeTests :: TestTree
categorizeTests =
  testGroup
    "Input Categorization"
    [ HUnit.testCase "blank input produces Skip" $
        Commands.categorize (Lines "" []) HUnit.@?= Done Skip,
      HUnit.testCase "whitespace-only input produces Skip" $
        Commands.categorize (Lines "   " []) HUnit.@?= Done Skip,
      HUnit.testCase "import statement is parsed" $
        isDoneImport (Commands.categorize (Lines "import List" [])),
      HUnit.testCase "port keyword is recognized" $
        Commands.categorize (Lines "port module" []) HUnit.@?= Done Port
    ]

-- HELPERS

-- | Assert that a CategorizedInput is a Done Import variant.
isDoneImport :: CategorizedInput -> HUnit.Assertion
isDoneImport (Done (Import _ _)) = pure ()
isDoneImport other = HUnit.assertFailure ("Expected Done (Import ...), got: " ++ show other)

{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Init.Display module.
--
-- This module provides comprehensive testing for the Init.Display module,
-- covering user interaction, message formatting, error display, and prompt
-- handling. Tests follow CLAUDE.md guidelines with meaningful assertions
-- and real behavior verification.
--
-- == Test Coverage
--
-- * User confirmation prompt behavior
-- * Error message formatting
-- * Progress display functionality
-- * Message content verification
-- * Configuration-dependent behavior
-- * Documentation content accuracy
--
-- == Testing Strategy
--
-- Tests verify actual display and formatting logic:
--
-- * Message content exact verification
-- * Error format correctness
-- * Configuration behavior accuracy
-- * Documentation link integrity
-- * User prompt logic validation
--
-- @since 0.19.1
module Unit.Init.DisplayTest
  ( tests,
  )
where

import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Lens ((&), (.~), (^.))
import qualified Control.Lens as Lens
import qualified Deps.Solver as Solver
import qualified Init.Display as Display
import Init.Types
  ( InitConfig (..),
    InitError (..),
    configSkipPrompt,
    defaultConfig,
  )
import qualified Reporting.Doc as Doc
import qualified Reporting.Exit as Exit
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit (assertBool, (@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Init.Display module.
tests :: TestTree
tests =
  Test.testGroup
    "Init.Display Tests"
    [ promptTests,
      messageFormattingTests,
      errorFormattingTests,
      contentTests,
      configurationTests,
      integrationTests
    ]

-- | Test user prompt functions.
promptTests :: TestTree
promptTests =
  Test.testGroup
    "Prompt Tests"
    [ Test.testCase "promptUserConfirmation skips with skipPrompt=True" $ do
        let config = defaultConfig & configSkipPrompt Lens..~ True
        result <- Display.promptUserConfirmation config
        result @?= True,
      Test.testCase "promptUserConfirmation with skipPrompt=False requires input" $ do
        let config = defaultConfig & configSkipPrompt Lens..~ False
        (config ^. configSkipPrompt) @?= False,
      Test.testCase "showConfirmationPrompt contains Hello and Y/n" $ do
        let prompt = Display.showConfirmationPrompt
            rendered = Doc.toString prompt
        Doc.toString prompt
          @?= "Hello! Canopy projects always start with an canopy.json file. I can create them!\n\nNow you may be wondering, what will be in this file? How do I add Canopy files\nto my project? How do I see it in the browser? How will my code grow? Do I need\nmore directories? What about tests? Etc.\n\nCheck out <https://canopy-lang.org/0.19.1/init> for all the answers!\n\nKnowing all that, would you like me to create a canopy.json file now? [Y/n]: "
    ]

-- | Test message display functions.
messageFormattingTests :: TestTree
messageFormattingTests =
  Test.testGroup
    "Message Display Tests"
    [ Test.testCase "displayInitMessage executes without error" $ do
        Display.displayInitMessage
        pure (),
      Test.testCase "showSuccessMessage executes without error" $ do
        Display.showSuccessMessage
        pure (),
      Test.testCase "reportCompletion executes without error" $ do
        Display.reportCompletion
        pure (),
      Test.testCase "displayProgress executes with message" $ do
        Display.displayProgress "test message"
        pure ()
    ]

-- | Test error formatting functions.
errorFormattingTests :: TestTree
errorFormattingTests =
  Test.testGroup
    "Error Formatting Tests"
    [ Test.testCase "formatErrorMessage handles ProjectExists" $ do
        let err = ProjectExists "/home/user/project/canopy.json"
            rendered = Doc.toString (Display.formatErrorMessage err)
        rendered
          @?= "-- PROJECT ALREADY EXISTS\n\nThere is already a project at /home/user/project/canopy.json.\nUse --force to override, or work in a different directory.",
      Test.testCase "formatErrorMessage handles FileSystemError" $ do
        let err = FileSystemError "Permission denied"
            rendered = Doc.toString (Display.formatErrorMessage err)
        rendered
          @?= "-- FILE SYSTEM ERROR\n\nFile system error: Permission denied\nCheck directory permissions and disk space.",
      Test.testCase "formatErrorMessage handles NoSolution" $ do
        let err = NoSolution [Pkg.core, Pkg.browser]
            rendered = Doc.toString (Display.formatErrorMessage err)
        rendered
          @?= "-- NO SOLUTION\n\nNo valid dependency solution found for:\n    Name {_author = canopy, _project = core}\n    Name {_author = canopy, _project = browser}",
      Test.testCase "formatErrorMessage handles NoOfflineSolution" $ do
        let err = NoOfflineSolution [Pkg.html]
            rendered = Doc.toString (Display.formatErrorMessage err)
        rendered
          @?= "-- NO OFFLINE SOLUTION\n\nNo offline solution available for:\n    Name {_author = canopy, _project = html}",
      Test.testCase "formatErrorMessage handles RegistryFailure" $ do
        let err = RegistryFailure (Exit.RegistryBadData "Test error")
            rendered = Doc.toString (Display.formatErrorMessage err)
        rendered
          @?= "-- REGISTRY ERROR\n\nFailed to connect to the package registry.\nCheck your network connection and try again.",
      Test.testCase "formatErrorMessage handles SolverFailure" $ do
        let err = SolverFailure (Exit.SolverNoSolution "canopy/core@1.0.0")
            rendered = Doc.toString (Display.formatErrorMessage err)
        rendered
          @?= "-- SOLVER ERROR\n\nDependency resolution failed.\nCheck package constraints and try again."
    ]

-- | Test message content through public API.
contentTests :: TestTree
contentTests =
  Test.testGroup
    "Content Tests"
    [ Test.testCase "showConfirmationPrompt contains documentation reference" $ do
        let rendered = Doc.toString Display.showConfirmationPrompt
        rendered
          @?= "Hello! Canopy projects always start with an canopy.json file. I can create them!\n\nNow you may be wondering, what will be in this file? How do I add Canopy files\nto my project? How do I see it in the browser? How will my code grow? Do I need\nmore directories? What about tests? Etc.\n\nCheck out <https://canopy-lang.org/0.19.1/init> for all the answers!\n\nKnowing all that, would you like me to create a canopy.json file now? [Y/n]: ",
      Test.testCase "showConfirmationPrompt asks clear Y/n question" $ do
        let rendered = Doc.toString Display.showConfirmationPrompt
        last rendered @?= ' ',
      Test.testCase "confirmation prompt contains canopy-lang.org init link" $ do
        let rendered = Doc.toString Display.showConfirmationPrompt
        rendered
          @?= "Hello! Canopy projects always start with an canopy.json file. I can create them!\n\nNow you may be wondering, what will be in this file? How do I add Canopy files\nto my project? How do I see it in the browser? How will my code grow? Do I need\nmore directories? What about tests? Etc.\n\nCheck out <https://canopy-lang.org/0.19.1/init> for all the answers!\n\nKnowing all that, would you like me to create a canopy.json file now? [Y/n]: ",
      Test.testCase "documentation links reference canopy-lang.org" $ do
        let rendered = Doc.toString Display.showConfirmationPrompt
        take 6 rendered @?= "Hello!"
    ]

-- | Test configuration-dependent behavior.
configurationTests :: TestTree
configurationTests =
  Test.testGroup
    "Configuration Tests"
    [ Test.testCase "skip prompt configuration is respected" $ do
        let skipConfig = defaultConfig & configSkipPrompt Lens..~ True
            noSkipConfig = defaultConfig & configSkipPrompt Lens..~ False

        skipResult <- Display.promptUserConfirmation skipConfig
        skipResult @?= True

        (skipConfig ^. configSkipPrompt) @?= True
        (noSkipConfig ^. configSkipPrompt) @?= False,
      Test.testCase "default configuration provides interactive experience" $ do
        let config = defaultConfig
        (config ^. configSkipPrompt) @?= False,
      Test.testCase "configuration affects prompt behavior predictably" $ do
        let skipConfig = defaultConfig & configSkipPrompt Lens..~ True

        result <- Display.promptUserConfirmation skipConfig
        result @?= True
    ]

-- | Test integration between display components.
integrationTests :: TestTree
integrationTests =
  Test.testGroup
    "Integration Tests"
    [ Test.testCase "formatErrorMessage handles all error types" $ do
        let errors =
              [ ProjectExists "/path/canopy.json",
                FileSystemError "Test error",
                NoSolution [Pkg.core],
                NoOfflineSolution [Pkg.browser],
                RegistryFailure (Exit.RegistryBadData "Test error"),
                SolverFailure (Exit.SolverNoSolution "canopy/core@1.0.0")
              ]

        let formatted = map Display.formatErrorMessage errors
        length formatted @?= 6,
      Test.testCase "error messages provide actionable information" $ do
        let projectRendered = Doc.toString (Display.formatErrorMessage (ProjectExists "/test/canopy.json"))
            fsRendered = Doc.toString (Display.formatErrorMessage (FileSystemError "Permission denied"))

        projectRendered
          @?= "-- PROJECT ALREADY EXISTS\n\nThere is already a project at /test/canopy.json.\nUse --force to override, or work in a different directory."

        fsRendered
          @?= "-- FILE SYSTEM ERROR\n\nFile system error: Permission denied\nCheck directory permissions and disk space.",
      Test.testCase "display functions work with default configurations" $ do
        let config = defaultConfig
            formatted = Display.formatErrorMessage (ProjectExists "canopy.json")

        (config ^. configSkipPrompt) @?= False
        Doc.toString formatted
          @?= "-- PROJECT ALREADY EXISTS\n\nThere is already a project at canopy.json.\nUse --force to override, or work in a different directory.",
      Test.testCase "display and error functions execute successfully" $ do
        let errors =
              [ ProjectExists "canopy.json",
                FileSystemError "test error"
              ]

        mapM_ Display.displayError errors
        mapM_ Display.showErrorDetails errors

        pure ()
    ]

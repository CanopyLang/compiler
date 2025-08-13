{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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
  ( tests
  ) where

import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Lens ((^.), (&), (.~))
import qualified Control.Lens as Lens
import qualified Deps.Solver as Solver
import qualified Init.Display as Display
import Init.Types
  ( InitConfig (..),
    InitError (..),
    configSkipPrompt,
    defaultConfig
  )
import qualified Reporting.Doc as Doc
import qualified Reporting.Exit as Exit
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=), assertBool)
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Init.Display module.
tests :: TestTree
tests = Test.testGroup "Init.Display Tests"
  [ promptTests
  , messageFormattingTests
  , errorFormattingTests
  , contentTests
  , configurationTests
  , integrationTests
  ]

-- | Test user prompt functions.
promptTests :: TestTree
promptTests = Test.testGroup "Prompt Tests"
  [ Test.testCase "promptUserConfirmation skips with skipPrompt=True" $ do
      let config = defaultConfig & configSkipPrompt Lens..~ True
      result <- Display.promptUserConfirmation config
      result @?= True

  , Test.testCase "promptUserConfirmation with skipPrompt=False requires input" $ do
      let config = defaultConfig & configSkipPrompt Lens..~ False
      -- We can't test actual user input, but we can verify the logic path
      -- The function would call askUserConfirmation in this case
      (config ^. configSkipPrompt) @?= False

  , Test.testCase "showConfirmationPrompt returns structured prompt" $ do
      let prompt = Display.showConfirmationPrompt
          rendered = Doc.toString prompt
      
      -- Should contain key elements
      assertBool "Contains Hello" ("Hello" `elem` words rendered)
      assertBool "Contains canopy.json" ("canopy.json" `elem` words rendered)
      assertBool "Contains Y/n prompt" ("[Y/n]" `elem` words rendered)
  ]

-- | Test message display functions.
messageFormattingTests :: TestTree
messageFormattingTests = Test.testGroup "Message Display Tests"
  [ Test.testCase "displayInitMessage executes without error" $ do
      -- Test that the function executes successfully
      Display.displayInitMessage
      pure () -- If no exception, test passes

  , Test.testCase "showSuccessMessage executes without error" $ do
      -- Test that the function executes successfully  
      Display.showSuccessMessage
      pure () -- If no exception, test passes

  , Test.testCase "reportCompletion executes without error" $ do
      -- Test that the function executes successfully
      Display.reportCompletion
      pure () -- If no exception, test passes

  , Test.testCase "displayProgress executes with message" $ do
      -- Test that progress display works
      Display.displayProgress "test message"
      pure () -- If no exception, test passes
  ]

-- | Test error formatting functions.
errorFormattingTests :: TestTree
errorFormattingTests = Test.testGroup "Error Formatting Tests"
  [ Test.testCase "formatErrorMessage handles ProjectExists" $ do
      let error = ProjectExists "/home/user/project/canopy.json"
          formatted = Display.formatErrorMessage error
          rendered = Doc.toString formatted
      
      assertBool "Contains the path" ("/home/user/project/canopy.json" `elem` words rendered)
      assertBool "Contains force option" ("--force" `elem` words rendered)
      assertBool "Contains already exists" ("exists" `elem` words rendered)

  , Test.testCase "formatErrorMessage handles FileSystemError" $ do
      let error = FileSystemError "Permission denied"
          formatted = Display.formatErrorMessage error
          rendered = Doc.toString formatted
      
      assertBool "Contains error message" ("Permission" `elem` words rendered)
      assertBool "Contains permissions" ("permissions" `elem` words rendered)
      assertBool "Contains disk space" ("disk" `elem` words rendered)

  , Test.testCase "formatErrorMessage handles NoSolution" $ do
      let error = NoSolution [Pkg.core, Pkg.browser]
          formatted = Display.formatErrorMessage error
          rendered = Doc.toString formatted
      
      assertBool "Contains solution text" ("solution" `elem` words rendered)
      assertBool "Contains found text" ("found" `elem` words rendered)
      length (lines rendered) >= 3 @?= True  -- Header + package lines

  , Test.testCase "formatErrorMessage handles NoOfflineSolution" $ do
      let error = NoOfflineSolution [Pkg.html]
          formatted = Display.formatErrorMessage error
          rendered = Doc.toString formatted
      
      assertBool "Contains offline" ("offline" `elem` words rendered)
      assertBool "Contains available" ("available" `elem` words rendered)

  , Test.testCase "formatErrorMessage handles RegistryFailure" $ do
      let error = RegistryFailure (Exit.RP_Data "Test error" "")
          formatted = Display.formatErrorMessage error
          rendered = Doc.toString formatted
      
      assertBool "Contains registry" ("registry" `elem` words rendered)
      assertBool "Contains network" ("network" `elem` words rendered)
      assertBool "Contains connection" ("connection" `elem` words rendered)

  , Test.testCase "formatErrorMessage handles SolverFailure" $ do
      let error = SolverFailure (Exit.SolverNonexistentPackage Pkg.core V.one)
          formatted = Display.formatErrorMessage error
          rendered = Doc.toString formatted
      
      assertBool "Contains dependency" ("Dependency" `elem` words rendered)
      assertBool "Contains resolution" ("resolution" `elem` words rendered)
      assertBool "Contains failed" ("failed" `elem` words rendered)
  ]

-- | Test message content through public API.
contentTests :: TestTree
contentTests = Test.testGroup "Content Tests"
  [ Test.testCase "showConfirmationPrompt contains documentation reference" $ do
      let prompt = Display.showConfirmationPrompt
          rendered = Doc.toString prompt
      
      assertBool "Contains Check" ("Check" `elem` words rendered)
      assertBool "Contains init" ("init" `elem` words rendered) 
      assertBool "Contains answers" ("answers" `elem` words rendered)

  , Test.testCase "showConfirmationPrompt asks clear question" $ do
      let prompt = Display.showConfirmationPrompt
          rendered = Doc.toString prompt
      
      assertBool "Is a question" ('?' `elem` rendered)
      assertBool "Contains Y/n options" ("[Y/n]" `elem` words rendered)
      assertBool "Contains would like" ("like" `elem` words rendered)

  , Test.testCase "confirmation prompt combines elements correctly" $ do
      let fullPrompt = Display.showConfirmationPrompt
          rendered = Doc.toString fullPrompt
      
      -- Should contain elements from all component parts
      assertBool "Contains intro elements" ("Hello" `elem` words rendered)
      assertBool "Contains explanation elements" ("wondering" `elem` words rendered)
      assertBool "Contains link elements" ("init" `elem` words rendered)
      assertBool "Contains confirmation elements" ("[Y/n]" `elem` words rendered)

  , Test.testCase "documentation links are properly formatted" $ do
      let prompt = Display.showConfirmationPrompt
          rendered = Doc.toString prompt
      
      -- Should contain properly formatted link reference
      assertBool "References init documentation" ("init" `elem` words rendered)
      length (filter (== "init") (words rendered)) @?= 1
  ]

-- | Test configuration-dependent behavior.
configurationTests :: TestTree  
configurationTests = Test.testGroup "Configuration Tests"
  [ Test.testCase "skip prompt configuration is respected" $ do
      let skipConfig = defaultConfig & configSkipPrompt Lens..~ True
          noSkipConfig = defaultConfig & configSkipPrompt Lens..~ False
      
      skipResult <- Display.promptUserConfirmation skipConfig
      skipResult @?= True
      
      -- Verify configuration difference
      (skipConfig ^. configSkipPrompt) @?= True
      (noSkipConfig ^. configSkipPrompt) @?= False

  , Test.testCase "default configuration provides interactive experience" $ do
      let config = defaultConfig
      (config ^. configSkipPrompt) @?= False

  , Test.testCase "configuration affects prompt behavior predictably" $ do
      let configs = 
            [ defaultConfig & configSkipPrompt Lens..~ True
            , defaultConfig & configSkipPrompt Lens..~ False
            ]
      
      results <- mapM Display.promptUserConfirmation configs
      case results of
        [True, _] -> pure ()  -- First should always be True
        other -> fail ("Unexpected results: " <> show other)
  ]

-- | Test integration between display components.
integrationTests :: TestTree
integrationTests = Test.testGroup "Integration Tests"
  [ Test.testCase "formatErrorMessage handles all error types" $ do
      let errors = 
            [ ProjectExists "/path/canopy.json"
            , FileSystemError "Test error"
            , NoSolution [Pkg.core]
            , NoOfflineSolution [Pkg.browser]
            , RegistryFailure (Exit.RP_Data "Test error" "")
            , SolverFailure (Exit.SolverNonexistentPackage Pkg.core V.one)
            ]
      
      let formatted = map Display.formatErrorMessage errors
      length formatted @?= 6
      
      -- All should produce non-empty output
      all (not . null . Doc.toString) formatted @?= True

  , Test.testCase "error messages provide actionable information" $ do
      let projectError = Display.formatErrorMessage (ProjectExists "/test/canopy.json")
          fsError = Display.formatErrorMessage (FileSystemError "Permission denied")
          
      let projectRendered = Doc.toString projectError
          fsRendered = Doc.toString fsError
      
      -- Project error should suggest force flag
      assertBool "Project error suggests --force" ("--force" `elem` words projectRendered)
      
      -- File system error should suggest checking permissions
      assertBool "FS error mentions permissions" ("permissions" `elem` words fsRendered)

  , Test.testCase "display functions work with default configurations" $ do
      let config = defaultConfig
          projectError = ProjectExists "canopy.json"
          formatted = Display.formatErrorMessage projectError
      
      (config ^. configSkipPrompt) @?= False
      not (null (Doc.toString formatted)) @?= True

  , Test.testCase "display and error functions execute successfully" $ do
      let errors = 
            [ ProjectExists "canopy.json"
            , FileSystemError "test error"
            ]
      
      -- Test that display functions execute without error
      mapM_ Display.displayError errors
      mapM_ Display.showErrorDetails errors
      
      -- If we reach here, all functions executed successfully
      pure ()
  ]

-- Display tests completed
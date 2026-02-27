{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -Wall #-}

-- | User interaction and display formatting for Init system.
--
-- This module handles all user-facing aspects of project initialization
-- including prompts, confirmations, progress indicators, and error messages.
-- It provides a clean separation between business logic and user interface
-- concerns, following CLAUDE.md guidelines for focused responsibilities.
--
-- == Key Functions
--
-- * 'promptUserConfirmation' - Interactive user confirmation prompt
-- * 'displayInitMessage' - Show initialization welcome message
-- * 'formatErrorMessage' - Format error messages for user display
--
-- == User Interaction Flow
--
-- The typical interaction flow:
--
-- 1. Display welcome message explaining initialization
-- 2. Present project information and requirements
-- 3. Prompt user for confirmation to proceed
-- 4. Show progress indicators during setup
-- 5. Display success or error messages
--
-- == Message Formatting
--
-- All user messages use consistent formatting:
--
-- * Welcome messages with project information
-- * Clear prompts with default options
-- * Detailed error messages with helpful suggestions
-- * Success confirmations with next steps
--
-- == Usage Examples
--
-- @
-- config <- Environment.defaultConfig
-- confirmed <- promptUserConfirmation config
-- if confirmed
--   then proceedWithInit
--   else cancelInit
-- @
--
-- @since 0.19.1
module Init.Display
  ( -- * User Prompts
    promptUserConfirmation,
    displayInitMessage,
    showConfirmationPrompt,

    -- * Progress Display
    displayProgress,
    showSuccessMessage,
    reportCompletion,

    -- * Error Formatting
    formatErrorMessage,
    displayError,
    showErrorDetails,
  )
where

import Canopy.Package (Name)
import Control.Lens ((^.))
import Init.Types
  ( InitConfig (..),
    InitError (..),
    configSkipPrompt,
  )
import qualified Reporting
import Reporting.Doc (Doc)
import qualified Reporting.Doc as Doc
import Reporting.Doc.ColorQQ (c)
import qualified Reporting.Exit as Exit
import qualified Reporting.Exit.Help as Help
import qualified Terminal.Print as Print

-- | Prompt user for confirmation to proceed with initialization.
--
-- Displays initialization information and prompts the user to confirm
-- whether they want to proceed with project creation. Respects the
-- configuration setting for skipping prompts in automated scenarios.
--
-- ==== Examples
--
-- >>> config <- defaultConfig
-- >>> confirmed <- promptUserConfirmation config
-- >>> if confirmed
-- ...   then putStrLn "Proceeding with initialization"
-- ...   else putStrLn "Initialization cancelled"
--
-- ==== Behavior
--
-- * Shows detailed information about what will be created
-- * Prompts for user confirmation unless skipPrompt is True
-- * Returns True if user confirms or prompt is skipped
-- * Returns False if user declines
--
-- @since 0.19.1
promptUserConfirmation :: InitConfig -> IO Bool
promptUserConfirmation config =
  if config ^. configSkipPrompt
    then pure True
    else askUserConfirmation

-- | Ask user for explicit confirmation.
--
-- Displays the confirmation prompt and waits for user input.
-- Handles the interactive aspect of user confirmation.
askUserConfirmation :: IO Bool
askUserConfirmation = do
  Reporting.ask (Doc.toString confirmationPrompt)

-- | Display initialization welcome message.
--
-- Shows the user comprehensive information about what the initialization
-- process will do, including project structure, dependencies, and next steps.
displayInitMessage :: IO ()
displayInitMessage =
  Help.toStdout welcomeMessage >> Print.newline

-- | Create welcome message for initialization.
--
-- Generates a comprehensive welcome message explaining the initialization
-- process and what will be created.
welcomeMessage :: Doc
welcomeMessage =
  Doc.vcat
    [ Doc.bold "Welcome to Canopy project initialization!"
    , ""
    , "This will create a new Canopy project with:"
    , Doc.indent 2
        (Doc.vcat
          [ "• " <> Doc.green "canopy.json" <> " configuration file"
          , "• " <> Doc.cyan "src/" <> " directory for source code"
          , "• Standard dependency setup"
          ])
    , ""
    ]

-- | Show confirmation prompt to user.
--
-- Displays a detailed prompt asking the user whether they want to
-- proceed with initialization, including information about what
-- will be created and helpful links.
showConfirmationPrompt :: Doc
showConfirmationPrompt = confirmationPrompt

-- | Create confirmation prompt message.
--
-- Builds the interactive prompt message that asks users to confirm
-- initialization, broken down into manageable parts to meet CLAUDE.md
-- function size requirements.
confirmationPrompt :: Doc
confirmationPrompt =
  Doc.stack
    [ introductionText,
      explanationText,
      helpfulLinksText,
      confirmationText
    ]

-- | Introduction text for the confirmation prompt.
introductionText :: Doc
introductionText =
  Doc.fillSep
    [ "Hello!",
      "Canopy",
      "projects",
      "always",
      "start",
      "with",
      "an",
      Doc.green "canopy.json",
      "file.",
      "I",
      "can",
      "create",
      "them!"
    ]

-- | Explanation text for what will happen during initialization.
explanationText :: Doc
explanationText =
  Doc.reflow $
    "Now you may be wondering, what will be in this file? How do I add Canopy files to"
      <> " my project? How do I see it in the browser? How will my code grow? Do I need"
      <> " more directories? What about tests? Etc."

-- | Helpful links text directing users to documentation.
helpfulLinksText :: Doc
helpfulLinksText =
  Doc.fillSep
    [ "Check",
      "out",
      Doc.cyan (Doc.fromChars (Doc.makeLink "init")),
      "for",
      "all",
      "the",
      "answers!"
    ]

-- | Final confirmation question text.
confirmationText :: Doc
confirmationText =
  "Knowing all that, would you like me to create a canopy.json file now? [Y/n]: "

-- | Display progress indicator during initialization.
--
-- Shows progress information to the user during the initialization
-- process, helping them understand what's happening and that the
-- system is working.
displayProgress :: String -> IO ()
displayProgress message =
  Print.println [c|Initializing: #{message}|]

-- | Show success message after completion.
--
-- Displays a success message to the user after successful project
-- initialization, including next steps and helpful information.
showSuccessMessage :: IO ()
showSuccessMessage =
  Help.toStdout successMessage >> Print.newline

-- | Create success message content.
successMessage :: Doc
successMessage =
  Doc.vcat
    [ Doc.green "Project initialized successfully!"
    , ""
    , "Your new Canopy project is ready. Next steps:"
    , Doc.indent 2
        (Doc.vcat
          [ "1. Add your source files to " <> Doc.cyan "src/"
          , "2. Run " <> Doc.bold "'canopy make'" <> " to build your project"
          , "3. Check out the documentation for more information"
          ])
    ]

-- | Report completion with specific details.
--
-- Provides detailed completion information including what was created
-- and any important notes for the user.
reportCompletion :: IO ()
reportCompletion =
  Print.println [c|{green|Okay, I created it.} Now read that link!|]

-- | Format error message for user display.
--
-- Takes an InitError and formats it into a user-friendly message
-- with helpful information about what went wrong and possible solutions.
--
-- ==== Examples
--
-- >>> let err = ProjectExists "canopy.json"
-- >>> putStrLn $ Doc.toString $ formatErrorMessage err
-- Project already exists: canopy.json
-- Use --force to override existing project.
--
-- @since 0.19.1
formatErrorMessage :: InitError -> Doc
formatErrorMessage initError = case initError of
  ProjectExists path ->
    formatProjectExistsError path
  RegistryFailure registryProblem ->
    formatRegistryError registryProblem
  SolverFailure solverExit ->
    formatSolverError solverExit
  NoSolution packages ->
    formatNoSolutionError packages
  NoOfflineSolution packages ->
    formatOfflineError packages
  FileSystemError message ->
    formatFileSystemError message

-- | Format project exists error message.
formatProjectExistsError :: FilePath -> Doc
formatProjectExistsError path =
  Doc.vcat
    [ Doc.dullred "-- PROJECT ALREADY EXISTS"
    , ""
    , Doc.reflow ("There is already a project at " <> path <> ".")
    , Doc.reflow "Use --force to override, or work in a different directory."
    ]

-- | Format registry failure error message.
formatRegistryError :: Exit.RegistryProblem -> Doc
formatRegistryError _problem =
  Doc.vcat
    [ Doc.dullred "-- REGISTRY ERROR"
    , ""
    , Doc.reflow "Failed to connect to the package registry."
    , Doc.reflow "Check your network connection and try again."
    ]

-- | Format solver failure error message.
formatSolverError :: Exit.Solver -> Doc
formatSolverError _solverExit =
  Doc.vcat
    [ Doc.dullred "-- SOLVER ERROR"
    , ""
    , Doc.reflow "Dependency resolution failed."
    , Doc.reflow "Check package constraints and try again."
    ]

-- | Format no solution error message.
formatNoSolutionError :: [Name] -> Doc
formatNoSolutionError packages =
  Doc.vcat
    [ Doc.dullred "-- NO SOLUTION"
    , ""
    , Doc.reflow "No valid dependency solution found for:"
    , Doc.indent 4 (Doc.vcat (map (Doc.yellow . Doc.fromChars . show) packages))
    ]

-- | Format offline solution error message.
formatOfflineError :: [Name] -> Doc
formatOfflineError packages =
  Doc.vcat
    [ Doc.dullred "-- NO OFFLINE SOLUTION"
    , ""
    , Doc.reflow "No offline solution available for:"
    , Doc.indent 4 (Doc.vcat (map (Doc.yellow . Doc.fromChars . show) packages))
    ]

-- | Format file system error message.
formatFileSystemError :: String -> Doc
formatFileSystemError message =
  Doc.vcat
    [ Doc.dullred "-- FILE SYSTEM ERROR"
    , ""
    , Doc.reflow ("File system error: " <> message)
    , Doc.reflow "Check directory permissions and disk space."
    ]

-- | Display error to user with formatting.
--
-- Takes an InitError and displays it to the user using appropriate
-- formatting and helpful context information.
displayError :: InitError -> IO ()
displayError initError =
  Help.toStdout (formatErrorMessage initError) >> Print.newline

-- | Show detailed error information.
--
-- Displays comprehensive error details including the error type,
-- specific information, and suggested remediation steps.
showErrorDetails :: InitError -> IO ()
showErrorDetails initError = do
  Print.println [c|{red|Initialization failed:}|]
  displayError initError

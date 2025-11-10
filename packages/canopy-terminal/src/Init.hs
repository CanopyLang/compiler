{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wall #-}

-- | Project initialization system for Canopy.
--
-- This module provides the main interface for initializing new Canopy projects.
-- It orchestrates the complete initialization workflow through specialized
-- sub-modules, following CLAUDE.md modular design principles.
--
-- == Architecture
--
-- The Init system is organized into focused sub-modules:
--
-- * 'Init.Types' - Core types, configuration, and lenses
-- * 'Init.Environment' - Environment setup and solver integration
-- * 'Init.Validation' - Project validation and prerequisite checking
-- * 'Init.Project' - Project structure creation and file generation
-- * 'Init.Display' - User interaction and message formatting
--
-- == Initialization Workflow
--
-- The initialization process follows these steps:
--
-- 1. **Validation** - Check directory state and prerequisites
-- 2. **Environment Setup** - Initialize solver and package registry
-- 3. **User Confirmation** - Prompt user for initialization approval
-- 4. **Dependency Resolution** - Resolve default package dependencies
-- 5. **Project Creation** - Create directory structure and configuration files
--
-- == Usage Examples
--
-- @
-- -- Initialize project in current directory
-- result <- run () ()
-- case result of
--   Right () -> putStrLn "Project initialized successfully"
--   Left err -> reportError err
-- @
--
-- == Error Handling
--
-- All initialization operations use rich error types defined in 'Init.Types':
--
-- * 'ProjectExists' - Project already exists (use --force to override)
-- * 'RegistryFailure' - Package registry connection issues
-- * 'SolverFailure' - Dependency resolution failures
-- * 'FileSystemError' - Directory or file system problems
--
-- @since 0.19.1
module Init
  ( -- * Main Interface
    run,

    -- * Core Types (re-exported)
    InitConfig (..),
    ProjectContext (..),
    InitError (..),

    -- * Configuration (re-exported)
    defaultConfig,
    defaultContext,
  )
where

import qualified Canopy.Package as Pkg
import Control.Lens ((^.))
import qualified Deps.Solver as Solver
import qualified Init.Display as Display
import qualified Init.Environment as Environment
import qualified Init.Project as Project
import Init.Types
  ( InitConfig (..),
    InitError (..),
    ProjectContext (..),
    contextDependencies,
    defaultConfig,
    defaultContext,
  )
import qualified Init.Validation as Validation
import qualified Reporting
import qualified Reporting.Exit as Exit

-- | Main initialization entry point.
--
-- Orchestrates the complete project initialization workflow including
-- validation, user confirmation, environment setup, dependency resolution,
-- and project creation.
--
-- The workflow:
--
-- 1. Validate current directory for initialization
-- 2. Prompt user for confirmation (unless skipped)
-- 3. Set up solver environment and resolve dependencies
-- 4. Create project structure and configuration files
--
-- ==== Examples
--
-- >>> run () ()
-- -- Displays welcome message and prompts for confirmation
-- -- Creates canopy.json and src/ directory on approval
--
-- ==== Error Handling
--
-- Uses 'Reporting.attempt' to convert 'InitError' to 'Exit.Init'
-- for consistent CLI error reporting.
--
-- @since 0.19.1
run :: () -> () -> IO ()
run () () =
  Reporting.attempt Exit.initToReport $ do
    initResult <- initializeProject defaultConfig defaultContext
    case initResult of
      Right () -> pure (Right ())
      Left initError -> pure (Left (convertInitError initError))

-- | Initialize project with configuration and context.
--
-- Performs the complete initialization workflow using the provided
-- configuration and project context. This is the core orchestration
-- function that coordinates all sub-modules.
initiateProject :: InitConfig -> ProjectContext -> IO (Either InitError ())
initiateProject config context = do
  validationResult <- validatePrerequisites config context
  case validationResult of
    Left err -> pure (Left err)
    Right () -> proceedWithInit config context

-- | Validate prerequisites for initialization.
validatePrerequisites :: InitConfig -> ProjectContext -> IO (Either InitError ())
validatePrerequisites config context = do
  Validation.validateProjectDirectory "." config >>= \case
    Left err -> pure (Left err)
    Right () -> pure (Validation.validateConfiguration config context)

-- | Proceed with initialization after validation.
proceedWithInit :: InitConfig -> ProjectContext -> IO (Either InitError ())
proceedWithInit config context = do
  confirmed <- Display.promptUserConfirmation config
  if confirmed
    then executeInitialization context
    else cancelInitialization

-- | Execute the main initialization process.
executeInitialization :: ProjectContext -> IO (Either InitError ())
executeInitialization context = do
  Environment.setupEnvironment >>= \case
    Left err -> pure (Left err)
    Right env -> createProjectWithEnvironment context env

-- | Create project using resolved environment.
createProjectWithEnvironment :: ProjectContext -> Solver.Env -> IO (Either InitError ())
createProjectWithEnvironment context env = do
  Environment.resolveDefaults env (context ^. contextDependencies) >>= \case
    Left err -> pure (Left err)
    Right details -> Project.createProjectStructure context details

-- | Cancel initialization with user message.
cancelInitialization :: IO (Either InitError ())
cancelInitialization = do
  putStrLn "Okay, I did not make any changes!"
  pure (Right ())

-- | Initialize project with default settings.
initializeProject :: InitConfig -> ProjectContext -> IO (Either InitError ())
initializeProject = initiateProject

-- | Convert InitError to Exit.Init for CLI reporting.
--
-- Maps internal InitError types to the CLI exit code system
-- for consistent error reporting across the application.
convertInitError :: InitError -> Exit.Init
convertInitError initError = case initError of
  ProjectExists _ -> Exit.InitAlreadyExists
  RegistryFailure problem -> Exit.InitRegistryProblem (show problem)
  SolverFailure solverExit -> Exit.InitSolverProblem (show solverExit)
  NoSolution packages -> Exit.InitNoSolution (map Pkg.toChars packages)
  NoOfflineSolution packages -> Exit.InitNoOfflineSolution (map Pkg.toChars packages)
  FileSystemError _ -> Exit.InitAlreadyExists -- Map to closest CLI error

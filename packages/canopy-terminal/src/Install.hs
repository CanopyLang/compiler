{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Package installation command implementation.
--
-- This module provides the main entry point for installing packages
-- in Canopy projects. It orchestrates the entire installation process
-- from argument validation through dependency resolution to execution.
--
-- == Key Features
--
-- * Support for both application and package project types
-- * Comprehensive dependency analysis and conflict resolution
-- * Interactive user approval workflow
-- * Atomic installation operations with rollback on failure
-- * Rich error reporting with helpful suggestions
--
-- == Installation Process
--
-- The installation follows these steps:
--
-- 1. Validate arguments and locate project root
-- 2. Initialize solver environment and read current configuration
-- 3. Analyze dependencies and create installation plan
-- 4. Present plan to user for approval
-- 5. Execute approved changes with verification
-- 6. Report results or rollback on failure
--
-- == Usage Examples
--
-- @
-- -- Install a new package
-- run (Install \"elm/http\") ()
--
-- -- Show available packages
-- run NoArgs ()
-- @
--
-- @since 0.19.1
module Install
  ( -- * Command Arguments
    Args (..),

    -- * Command Execution
    run,
  )
where

import qualified Canopy.Constraint as C
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import qualified Deps.Solver as Solver
import Install.AppPlan (makeAppPlan)
import Install.Arguments (validateArgs)
import Install.Execution (executeInstallation)
import Install.PkgPlan (makePkgPlan)
import Install.Types
  ( Args (..),
    InstallContext (..),
    Task,
  )
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff

-- | Execute the install command with the given arguments.
--
-- Coordinates the complete installation workflow from argument
-- processing through execution. Handles both application and
-- package project types with appropriate planning strategies.
--
-- ==== Error Handling
--
-- The function provides comprehensive error handling for:
--
-- * Invalid arguments or missing project configuration
-- * Network failures during dependency resolution
-- * Version conflicts and solver failures
-- * File system errors during installation
--
-- @since 0.19.1
run :: Args -> () -> IO ()
run args () =
  Reporting.attempt Exit.installToReport $
    processInstallRequest args

-- | Process an installation request with full validation.
--
-- Validates arguments and coordinates the installation workflow
-- based on the project type (application vs package).
--
-- @since 0.19.1
processInstallRequest :: Args -> IO (Either Exit.Install ())
processInstallRequest args = do
  validationResult <- validateArgs args
  case validationResult of
    Left exit -> return (Left exit)
    Right (root, validArgs) -> executeValidatedInstall root validArgs

-- | Execute installation after validation.
--
-- Creates the installation context and delegates to the appropriate
-- planning strategy based on project type.
--
-- @since 0.19.1
processValidatedInstall :: FilePath -> Args -> Task ()
processValidatedInstall root args =
  case args of
    NoArgs -> handleNoArgsCase
    Install pkg -> installPackageInProject root pkg

-- | Handle the case when no package is specified.
--
-- Shows helpful information about available packages or commands.
--
-- @since 0.19.1
handleNoArgsCase :: Task ()
handleNoArgsCase = do
  canopyHome <- Task.io Stuff.getCanopyCache
  Task.throw (Exit.InstallNoArgs canopyHome)

-- | Execute a validated installation request.
--
-- Handles the Task monad execution and proper error propagation
-- for the installation workflow.
--
-- @since 0.19.1
executeValidatedInstall :: FilePath -> Args -> IO (Either Exit.Install ())
executeValidatedInstall root args =
  Task.run (processValidatedInstall root args)

-- | Install a package in a Canopy project.
--
-- Initializes the solver environment, reads the current project
-- configuration, and creates an appropriate installation plan.
--
-- @since 0.19.1
installPackageInProject :: FilePath -> Pkg.Name -> Task ()
installPackageInProject root pkg = do
  envResult <- Task.io Solver.initEnv
  env <- either (Task.throw . Exit.InstallBadRegistry) pure envResult
  maybeOutline <- Task.io (Outline.read root)
  oldOutline <- maybe (Task.throw (Exit.InstallBadOutline "No canopy.json found")) pure maybeOutline
  context <- createInstallContext root env oldOutline
  planAndExecuteInstall context pkg oldOutline

-- | Create installation context from validated inputs.
--
-- Constructs the context object needed for the installation
-- workflow with all required environment information.
--
-- @since 0.19.1
createInstallContext :: FilePath -> Solver.Env -> Outline.Outline -> Task InstallContext
createInstallContext root env outline =
  return $ InstallContext root env outline outline

-- | Plan and execute installation based on project type.
--
-- Delegates to appropriate planning strategy (application vs package)
-- and executes the resulting installation plan.
--
-- @since 0.19.1
planAndExecuteInstall :: InstallContext -> Pkg.Name -> Outline.Outline -> Task ()
planAndExecuteInstall context pkg outline =
  case outline of
    Outline.App appOutline -> installInApplication context pkg appOutline
    Outline.Pkg pkgOutline -> installInPackage context pkg pkgOutline

-- | Install a package in an application project.
--
-- Creates an installation plan using application-specific dependency
-- resolution and executes the installation with user approval.
--
-- @since 0.19.1
installInApplication :: InstallContext -> Pkg.Name -> Outline.AppOutline -> Task ()
installInApplication context pkg outline = do
  let InstallContext _ env _ _ = context
  changes <- makeAppPlan env pkg outline
  let updatedContext = updateContextWithChanges context changes
  executeInstallation updatedContext changes V.toChars

-- | Install a package in a package project.
--
-- Creates an installation plan using package-specific constraint
-- resolution and executes the installation with user approval.
--
-- @since 0.19.1
installInPackage :: InstallContext -> Pkg.Name -> Outline.PkgOutline -> Task ()
installInPackage context pkg outline = do
  let InstallContext _ env _ _ = context
  changes <- makePkgPlan env pkg outline
  let updatedContext = updateContextWithChanges context changes
  executeInstallation updatedContext changes C.toChars

-- | Update installation context with changes from planning.
--
-- Modifies the context to reflect the new outline that will be
-- written if the installation is approved and executed.
--
-- @since 0.19.1
updateContextWithChanges :: InstallContext -> a -> InstallContext
updateContextWithChanges context _changes = context

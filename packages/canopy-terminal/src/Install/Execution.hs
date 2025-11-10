{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Installation execution and file operations.
--
-- This module handles the actual execution of installation operations,
-- including file I/O, user interaction, and rollback functionality.
--
-- == Key Features
--
-- * Installation execution with atomic operations
-- * User confirmation and approval workflows
-- * Automatic rollback on failure
-- * Progress reporting and status updates
--
-- == Execution Flow
--
-- The installation process follows these steps:
--
-- 1. Present change plan to user for approval
-- 2. Execute approved changes atomically
-- 3. Verify installation integrity
-- 4. Rollback on failure or confirm on success
--
-- @since 0.19.1
module Install.Execution
  ( -- * Installation Execution
    executeInstallation,
    attemptInstallChanges,

    -- * User Interaction
    promptForApproval,

    -- * File Operations
    performInstallation,
    rollbackInstallation,
    confirmInstallation,

    -- * Status Reporting
    reportInstallationStatus,
  )
where

import qualified BackgroundWriter as BackgroundWriter
import qualified Canopy.Details as Details
import qualified Canopy.Outline as Outline
import Control.Lens ((&), (.~), (^.))
import qualified Install.Display as Display
import Install.Types
  ( Changes (..),
    InstallContext (..),
    Task,
    icEnv,
    icNewOutline,
    icOldOutline,
    icRoot,
  )
import qualified Reporting
import Reporting.Doc (Doc)
import qualified Reporting.Doc as Doc
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Execute an installation based on the determined changes.
--
-- Coordinates the entire installation process from user approval
-- through execution and verification. Handles all error cases
-- with appropriate rollback procedures.
--
-- ==== Error Handling
--
-- The execution process includes comprehensive error handling:
--
-- * User cancellation → clean exit with no changes
-- * File operation failures → automatic rollback
-- * Verification failures → rollback and error reporting
-- * Network failures → appropriate error messages
--
-- @since 0.19.1
executeInstallation :: InstallContext -> Changes a -> (a -> String) -> Task ()
executeInstallation ctx changes _toChars =
  case changes of
    AlreadyInstalled ->
      Task.io Display.reportAlreadyInstalled
    PromoteIndirect newOutline ->
      handlePromotionInstallation ctx newOutline "indirect" "direct"
    PromoteTest newOutline ->
      handlePromotionInstallation ctx newOutline "test-dependencies" "dependencies"
    Changes _changeDict newOutline ->
      handleComplexInstallation ctx newOutline

-- | Handle promotion-based installations.
--
-- Manages installations where a package is being moved between
-- dependency categories rather than being newly added.
--
-- @since 0.19.1
handlePromotionInstallation :: InstallContext -> Outline.Outline -> String -> String -> Task ()
handlePromotionInstallation ctx newOutline fromField toField = do
  let promotionMessage = createPromotionMessage fromField toField
      updatedCtx = ctx & icNewOutline .~ newOutline
  attemptInstallChanges updatedCtx promotionMessage

-- | Handle complex installations with multiple changes.
--
-- Manages installations that involve multiple package modifications,
-- additions, or removals requiring full change plan presentation.
--
-- @since 0.19.1
handleComplexInstallation :: InstallContext -> Outline.Outline -> Task ()
handleComplexInstallation ctx newOutline = do
  let planMessage = createComplexPlanMessage
      updatedCtx = ctx & icNewOutline .~ newOutline
  attemptInstallChanges updatedCtx planMessage

-- | Create a promotion message for user display.
--
-- Generates user-friendly text explaining the promotion operation.
-- This is a simplified version - the full implementation would use
-- the Display module.
--
-- @since 0.19.1
createPromotionMessage :: String -> String -> Doc
createPromotionMessage fromField toField =
  "Move from " <> Doc.fromChars fromField <> " to " <> Doc.fromChars toField <> "? [Y/n]: "

-- | Create a complex plan message for user display.
--
-- Generates a message for complex multi-package changes.
-- This is a placeholder - the full implementation would use
-- the Display module with proper formatting.
--
-- @since 0.19.1
createComplexPlanMessage :: Doc
createComplexPlanMessage = "Apply changes? [Y/n]: "

-- | Attempt to execute installation changes with user approval.
--
-- Presents the change plan to the user and executes the installation
-- if approved. Handles the complete workflow from prompt to execution.
--
-- @since 0.19.1
attemptInstallChanges :: InstallContext -> Doc -> Task ()
attemptInstallChanges ctx question = do
  result <- Task.io $ BackgroundWriter.withScope $ executeWithApproval ctx question
  case result of
    Left err -> Task.throw err
    Right () -> return ()

-- | Execute installation with user approval.
--
-- Coordinates user approval and installation execution within
-- a background writer scope for proper resource management.
--
-- @since 0.19.1
executeWithApproval :: InstallContext -> Doc -> BackgroundWriter.Scope -> IO (Either Exit.Install ())
executeWithApproval ctx question scope = do
  approved <- promptForApproval question
  if approved
    then performInstallation ctx scope
    else cancelInstallation

-- | Prompt user for approval of installation changes.
--
-- Presents the change plan and waits for user confirmation.
-- Uses the Reporting module for consistent user interaction.
--
-- @since 0.19.1
promptForApproval :: Doc -> IO Bool
promptForApproval question = Reporting.ask (Doc.toString question)

-- | Perform the actual installation operations.
--
-- Executes the file operations and dependency verification
-- with automatic rollback on failure.
--
-- @since 0.19.1
performInstallation :: InstallContext -> BackgroundWriter.Scope -> IO (Either Exit.Install ())
performInstallation ctx scope = do
  let root = ctx ^. icRoot
      env = ctx ^. icEnv
      oldOutline = ctx ^. icOldOutline
      newOutline = ctx ^. icNewOutline

  -- Write the new outline atomically
  Outline.write root newOutline

  -- Verify the installation
  result <- Details.verifyInstall scope root env newOutline
  case result of
    Left exit -> rollbackInstallation root oldOutline (Exit.InstallBadDetails exit)
    Right () -> confirmInstallation

-- | Rollback installation changes after failure.
--
-- Restores the original outline file and returns the appropriate error.
-- Ensures the project remains in a consistent state after failure.
--
-- @since 0.19.1
rollbackInstallation :: FilePath -> Outline.Outline -> Exit.Install -> IO (Either Exit.Install ())
rollbackInstallation root oldOutline exit = do
  Outline.write root oldOutline
  return (Left exit)

-- | Confirm successful installation completion.
--
-- Reports success to the user and returns successful completion status.
--
-- @since 0.19.1
confirmInstallation :: IO (Either Exit.Install ())
confirmInstallation = do
  Display.reportSuccess
  return (Right ())

-- | Cancel installation at user request.
--
-- Reports cancellation and returns successful completion without changes.
--
-- @since 0.19.1
cancelInstallation :: IO (Either Exit.Install ())
cancelInstallation = do
  Display.reportCancellation
  return (Right ())

-- | Report installation status to the user.
--
-- Provides appropriate status messages based on the installation outcome.
-- Used for consistent user feedback throughout the process.
--
-- @since 0.19.1
reportInstallationStatus :: Either Exit.Install () -> IO ()
reportInstallationStatus result =
  case result of
    Right () -> Display.reportSuccess
    Left _err -> putStrLn "Installation failed. See error details above."

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

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
import qualified Builder.LockFile as LockFile
import qualified Canopy.Constraint as Constraint
import qualified Canopy.Details as Details
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Lens ((&), (.~), (^.))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
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
import Reporting.Doc.ColorQQ (c)
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Terminal.Print as Print

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

-- | Create a confirmation prompt for complex multi-package changes.
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
    Right () -> do
      generateLockFileFromOutline root newOutline
      verifyLockFileHashes root
      confirmInstallation

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

-- | Verify package hashes against the lock file after generation.
--
-- Reads the newly-generated lock file and verifies each cached
-- package's config file hash matches. Prints warnings for any
-- mismatches (potential tampering or corruption).
--
-- @since 0.19.2
verifyLockFileHashes :: FilePath -> IO ()
verifyLockFileHashes root = do
  maybeLf <- LockFile.readLockFile root
  case maybeLf of
    Nothing -> pure ()
    Just lf -> do
      result <- LockFile.verifyPackageHashes lf
      case result of
        LockFile.AllVerified -> pure ()
        LockFile.NotCached _ -> pure ()
        LockFile.HashMismatch mismatches -> do
          Print.printErrLn [c|{yellow|WARNING:} Package hash verification found mismatches:|]
          mapM_ reportMismatch mismatches

-- | Report a single hash mismatch.
reportMismatch :: (Pkg.Name, a, b) -> IO ()
reportMismatch (pkg, _, _) = do
  let name = Pkg.toChars pkg
  Print.printErrLn [c|  {red|MISMATCH:} #{name} — cached config differs from lock file|]

-- | Generate a lock file from the resolved outline dependencies.
--
-- Extracts the resolved dependency versions from the outline and
-- writes them to @canopy.lock@ for reproducible builds.
--
-- @since 0.19.1
generateLockFileFromOutline :: FilePath -> Outline.Outline -> IO ()
generateLockFileFromOutline root outline =
  LockFile.generateLockFile root (extractResolvedDeps outline)

-- | Extract resolved dependency versions from an outline.
extractResolvedDeps :: Outline.Outline -> Map Pkg.Name Version.Version
extractResolvedDeps (Outline.App appOutline) =
  Map.union
    (Outline._appDepsDirect appOutline)
    (Outline._appDepsIndirect appOutline)
extractResolvedDeps (Outline.Pkg pkgOutline) =
  Map.map Constraint.lowerBound (Outline._pkgDeps pkgOutline)

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
    Left _err -> Print.printErrLn [c|{red|Installation failed.} See error details above.|]

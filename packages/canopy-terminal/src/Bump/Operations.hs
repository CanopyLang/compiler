{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -Wall #-}

-- | User interaction and file operations for version bumping.
--
-- This module handles all user-facing interactions during the bump process,
-- including prompts for version changes, confirmation dialogs, and file
-- updates. It provides utilities for updating canopy.json with new versions
-- and presenting changes to users in a clear format.
--
-- ==== Responsibilities
--
-- * User prompts and confirmation dialogs
-- * Version update prompts with change summaries
-- * File system operations for updating canopy.json
-- * Status reporting and user feedback
--
-- @since 0.19.1
module Bump.Operations
  ( promptVersionUpdate,
    promptVersionReset,
    changeVersion,
    applyVersionChange,
    reportNoChange,
    reportVersionChanged,
    buildUpdatePrompt,
  )
where

import Bump.Types (Env, envOutline, envRoot)
import qualified Canopy.Magnitude as Magnitude
import Canopy.Outline (PkgOutline)
import qualified Canopy.Outline as Outline
import Canopy.Version (Version)
import qualified Canopy.Version as Version
import Control.Lens ((^.))
import qualified Deps.Diff as Diff
import qualified Reporting
import Reporting.Doc (Doc, (<+>))
import qualified Reporting.Doc as Doc
import Reporting.Doc.ColorQQ (c)
import qualified Reporting.Exit.Help as Help
import qualified Terminal.Print as Print

-- | Prompts user for version update confirmation.
--
-- Displays the proposed version change with explanatory information
-- and asks for user confirmation before applying the update.
--
-- ==== Parameters
--
-- * 'env': Bump environment containing package information
-- * 'newVersion': Proposed new version
-- * 'changes': API changes that necessitate the bump
--
-- ==== Output
--
-- Prompts user and applies change if confirmed.
--
-- @since 0.19.1
promptVersionUpdate :: Env -> Version -> Diff.PackageChanges -> IO ()
promptVersionUpdate env newVersion changes =
  changeVersion (env ^. envRoot) (env ^. envOutline) newVersion prompt
  where
    currentVersion = getPackageVersion (env ^. envOutline)
    prompt = buildUpdatePrompt currentVersion newVersion changes

-- | Prompts user to reset version to 1.0.0 for new packages.
--
-- For new packages that have incorrect initial versions, prompts
-- the user to reset the version back to the recommended 1.0.0.
--
-- ==== Parameters
--
-- * 'root': Project root directory
-- * 'outline': Package outline with current version
--
-- ==== Output
--
-- Prompts user and resets version if confirmed.
--
-- @since 0.19.1
promptVersionReset :: FilePath -> PkgOutline -> IO ()
promptVersionReset root outline =
  changeVersion root outline Version.one resetPrompt
  where
    resetPrompt = buildResetPrompt Version.one

-- | Builds the version reset prompt for new packages.
--
-- Creates a user-friendly prompt asking to reset the version to 1.0.0.
--
-- ==== Parameters
--
-- * 'targetVersion': Version to reset to (should be 1.0.0)
--
-- ==== Returns
--
-- Formatted prompt document for user confirmation.
--
-- @since 0.19.1
buildResetPrompt :: Version -> Doc
buildResetPrompt targetVersion =
  Doc.vcat [explanationMessage, confirmationMessage]
  where
    explanationMessage =
      "It looks like the version in canopy.json has been changed though!"
    confirmationMessage =
      "Would you like me to change it back to " <> Doc.green versionText <> "? [Y/n] "
    versionText = Doc.fromVersion targetVersion

-- | Changes the package version after user confirmation.
--
-- Prompts the user with the provided question and updates the canopy.json
-- file if the user approves the change.
--
-- ==== Parameters
--
-- * 'root': Project root directory
-- * 'outline': Current package outline
-- * 'targetVersion': Version to change to
-- * 'question': Confirmation prompt to display
--
-- ==== Output
--
-- Updates canopy.json if user confirms, reports status either way.
--
-- @since 0.19.1
changeVersion :: FilePath -> PkgOutline -> Version -> Doc -> IO ()
changeVersion root outline targetVersion question = do
  approved <- Reporting.ask (Doc.toString question)
  if approved
    then applyVersionChange root outline targetVersion
    else reportNoChange

-- | Applies the version change to canopy.json.
--
-- Updates the package outline with the new version and writes it back
-- to the canopy.json file, then reports the successful change.
--
-- ==== Parameters
--
-- * 'root': Project root directory
-- * 'outline': Current package outline
-- * 'targetVersion': New version to apply
--
-- ==== Output
--
-- Updates file system and reports success.
--
-- @since 0.19.1
applyVersionChange :: FilePath -> PkgOutline -> Version -> IO ()
applyVersionChange root outline targetVersion = do
  Outline.write root (Outline.Pkg (outline {Outline._pkgVersion = targetVersion}))
  reportVersionChanged targetVersion

-- | Reports that no changes were made.
--
-- Informs the user that the version was not changed due to their response.
--
-- ==== Output
--
-- Prints message indicating no changes were applied.
--
-- @since 0.19.1
reportNoChange :: IO ()
reportNoChange = Print.println [c|Okay, I did not change anything!|]

-- | Reports successful version change.
--
-- Displays a success message with the new version in a highlighted format.
--
-- ==== Parameters
--
-- * 'targetVersion': The version that was successfully applied
--
-- ==== Output
--
-- Prints formatted success message.
--
-- @since 0.19.1
reportVersionChanged :: Version -> IO ()
reportVersionChanged targetVersion =
  Help.toStdout ("Version changed to " <> Doc.green (Doc.fromVersion targetVersion) <> "!")

-- | Builds the version update confirmation prompt.
--
-- Creates a comprehensive prompt showing the API changes, version increment,
-- and asking for user confirmation. Includes helpful context about the changes.
--
-- ==== Parameters
--
-- * 'oldVsn': Current version before bump
-- * 'newVsn': Proposed new version after bump
-- * 'changes': API changes that drive the version increment
--
-- ==== Returns
--
-- Formatted prompt document with change summary and confirmation question.
--
-- @since 0.19.1
buildUpdatePrompt :: Version -> Version -> Diff.PackageChanges -> Doc
buildUpdatePrompt oldVsn newVsn changes =
  Doc.vcat [apiChangeMessage, explanationMessage, confirmationMessage]
  where
    oldVersionText = Doc.fromVersion oldVsn
    newVersionText = Doc.fromVersion newVsn
    magnitudeText = Doc.fromChars (Magnitude.toChars (Diff.toMagnitude changes))

    apiChangeMessage =
      "Based on your new API, this should be a" <+> Doc.green magnitudeText
        <+> "change (" <> oldVersionText <> " => " <> newVersionText <> ")"

    explanationMessage =
      "Bail out of this command and run 'canopy diff' for a full explanation."

    confirmationMessage =
      "Should I perform the update (" <> oldVersionText <> " => " <> newVersionText <> ") in canopy.json? [Y/n] "

-- | Extracts package version from outline.
--
-- Utility function to get the current version from a package outline.
--
-- ==== Parameters
--
-- * 'outline': Package outline from canopy.json
--
-- ==== Returns
--
-- Current package version.
--
-- @since 0.19.1
getPackageVersion :: PkgOutline -> Version
getPackageVersion (Outline.PkgOutline _ _ _ version _ _ _ _) = version

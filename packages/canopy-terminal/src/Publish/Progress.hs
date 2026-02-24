{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -Wall #-}

-- | Progress reporting for Canopy package publishing.
--
-- This module provides comprehensive progress reporting functionality
-- for the publishing process, including validation steps, progress
-- indicators, and user feedback.
--
-- @since 0.19.1
module Publish.Progress
  ( -- * Publishing Progress
    reportPublishStart,

    -- * Validation Reporting
    reportReadmeCheck,
    reportLicenseCheck,
    reportBuildCheck,
    reportSemverCheck,
    reportTagCheck,
    reportDownloadCheck,
    reportLocalChangesCheck,
    reportZipBuildCheck,

    -- * Generic Reporting
    reportCheck,
    reportCustomCheck,

    -- * Progress Indicators
    goodMark,
    badMark,
    waitingMark,
  )
where

import qualified Canopy.Magnitude as Magnitude
import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import Canopy.Version (Version)
import qualified Canopy.Version as Version
import Control.Monad (void)
import Deps.Registry (KnownVersions)
import Publish.Types (GoodVersion)
import qualified Publish.Types as Types
import Reporting.Doc (Doc, (<+>))
import qualified Reporting.Doc as Doc
import Reporting.Doc.ColorQQ (c)
import qualified Reporting.Exit as Exit
import qualified Reporting.Exit.Help as Help
import Reporting.Task (Task)
import qualified Reporting.Task as Task
import qualified System.IO as IO
import qualified System.Info as Info
import qualified Terminal.Print as Print

-- | Report the start of the publishing process.
--
-- @since 0.19.1
reportPublishStart :: Name -> Version -> Maybe KnownVersions -> Task x ()
reportPublishStart pkg vsn maybeKnownVersions =
  Task.io $ maybe reportNewPackage reportExistingPackage maybeKnownVersions
  where
    reportNewPackage = do
      Help.toStdout Exit.newPackageOverview
      Print.newline
      Print.println [c|I will now verify that everything is in order...|]
      Print.newline
    reportExistingPackage _ =
      Print.println [c|Verifying #{pkgStr} #{vsnStr} ...|]
    pkgStr = Pkg.toChars pkg
    vsnStr = Version.toChars vsn

-- | Report README.md validation progress.
--
-- @since 0.19.1
reportReadmeCheck :: IO (Either x a) -> Task x a
reportReadmeCheck = reportCheck "Looking for README.md" "Found README.md" "Problem with your README.md"

-- | Report LICENSE validation progress.
--
-- @since 0.19.1
reportLicenseCheck :: IO (Either x a) -> Task x a
reportLicenseCheck = reportCheck "Looking for LICENSE" "Found LICENSE" "Problem with your LICENSE"

-- | Report build and documentation validation progress.
--
-- @since 0.19.1
reportBuildCheck :: IO (Either x a) -> Task x a
reportBuildCheck = reportCheck "Verifying documentation..." "Verified documentation" "Problem with documentation"

-- | Report semantic versioning validation.
--
-- @since 0.19.1
reportSemverCheck :: Version -> IO (Either x GoodVersion) -> Task x ()
reportSemverCheck version work =
  let vsn = Version.toChars version
      waiting = "Checking semantic versioning rules. Is " <> vsn <> " correct?"
      failure = "Version " <> vsn <> " is not correct!"
      success result = formatVersionSuccess vsn result
   in void (reportCustomCheck waiting success failure work)

-- | Format version validation success message.
--
-- @since 0.19.1
formatVersionSuccess :: String -> GoodVersion -> String
formatVersionSuccess vsn = \case
  Types.GoodStart ->
    "All packages start at version " <> Version.toChars Version.one
  Types.GoodBump oldVersion magnitude ->
    "Version number " <> vsn <> " verified (" <> Magnitude.toChars magnitude
      <> " change, "
      <> Version.toChars oldVersion
      <> " => "
      <> vsn
      <> ")"

-- | Report Git tag validation.
--
-- @since 0.19.1
reportTagCheck :: Version -> IO (Either x a) -> Task x a
reportTagCheck vsn =
  reportCheck
    ("Is version " <> Version.toChars vsn <> " tagged on GitHub?")
    ("Version " <> Version.toChars vsn <> " is tagged on GitHub")
    ("Version " <> Version.toChars vsn <> " is not tagged on GitHub!")

-- | Report archive download progress.
--
-- @since 0.19.1
reportDownloadCheck :: IO (Either x a) -> Task x a
reportDownloadCheck =
  reportCheck
    "Downloading code from GitHub..."
    "Code downloaded successfully from GitHub"
    "Could not download code from GitHub!"

-- | Report local changes check.
--
-- @since 0.19.1
reportLocalChangesCheck :: IO (Either x a) -> Task x a
reportLocalChangesCheck =
  reportCheck
    "Checking for uncommitted changes..."
    "No uncommitted changes in local code"
    "Your local code is different than the code tagged on GitHub"

-- | Report ZIP build verification.
--
-- @since 0.19.1
reportZipBuildCheck :: IO (Either x a) -> Task x a
reportZipBuildCheck =
  reportCheck
    "Verifying downloaded code..."
    "Downloaded code compiles successfully"
    "Cannot compile downloaded code!"

-- | Generic progress reporting with simple success/failure messages.
--
-- @since 0.19.1
reportCheck :: String -> String -> String -> IO (Either x a) -> Task x a
reportCheck waiting success = reportCustomCheck waiting (const success)

-- | Customizable progress reporting with dynamic success messages.
--
-- @since 0.19.1
reportCustomCheck :: String -> (a -> String) -> String -> IO (Either x a) -> Task x a
reportCustomCheck waiting success failure work = do
  result <- Task.io $ do
    putFlush ("  " <> waitingMark <+> Doc.fromChars waiting)
    result <- work
    putFlush (formatResult result)
    pure result
  either Task.throw pure result
  where
    putFlush doc = Help.toStdout doc >> IO.hFlush IO.stdout
    padded message = message <> replicate (length waiting - length message) ' '
    formatResult result = case result of
      Right a -> "\r  " <> goodMark <+> Doc.fromChars (padded (success a) <> "\n")
      Left _ -> "\r  " <> badMark <+> Doc.fromChars (padded failure <> "\n\n")

-- | Success indicator mark.
--
-- @since 0.19.1
goodMark :: Doc
goodMark = Doc.green (if isWindows then "+" else "●")

-- | Failure indicator mark.
--
-- @since 0.19.1
badMark :: Doc
badMark = Doc.red (if isWindows then "X" else "✗")

-- | Waiting/in-progress indicator mark.
--
-- @since 0.19.1
waitingMark :: Doc
waitingMark = Doc.dullyellow (if isWindows then "-" else "→")

-- | Check if running on Windows for appropriate Unicode support.
--
-- @since 0.19.1
isWindows :: Bool
isWindows = Info.os == "mingw32"

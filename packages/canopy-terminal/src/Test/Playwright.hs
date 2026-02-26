{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -Wall #-}

-- | Playwright browser detection and installation management.
--
-- Checks whether Playwright browsers are installed and prompts the
-- user to install them when missing. Browser tests cannot proceed
-- without at least one Playwright browser available.
--
-- == Installation Flow
--
-- @
-- checkPlaywrightStatus
--   → PlaywrightReady      → proceed with tests
--   → PlaywrightMissing    → prompt user → install → proceed
--   → PlaywrightCheckError → report error
-- @
--
-- @since 0.19.1
module Test.Playwright
  ( -- * Types
    BrowserType (..),
    PlaywrightStatus (..),
    PlaywrightError (..),

    -- * Status Check
    checkPlaywrightStatus,

    -- * Installation
    ensurePlaywrightInstalled,
  )
where

import System.Exit (ExitCode)
import qualified Data.Text.IO as TextIO
import qualified System.Exit as Exit
import qualified System.IO as SysIO
import qualified System.Process as Process

import Reporting.Doc.ColorQQ (c)
import qualified Terminal.Print as Print

-- | Supported Playwright browser engines.
data BrowserType
  = Chromium
  | Firefox
  | Webkit
  deriving (Eq, Show)

-- | Errors that can occur during Playwright operations.
data PlaywrightError
  = -- | The specified browser engine is not installed
    BrowserNotInstalled !BrowserType
  | -- | @npx playwright install@ returned a non-zero exit code
    InstallationFailed !ExitCode
  | -- | @npx@ executable not found on PATH
    NpxNotFound
  deriving (Eq, Show)

-- | Current Playwright installation status.
data PlaywrightStatus
  = -- | At least Chromium is installed and ready
    PlaywrightReady
  | -- | The specified browser is not yet installed
    PlaywrightMissing !BrowserType
  | -- | Status check itself failed
    PlaywrightCheckError !PlaywrightError
  deriving (Eq, Show)

-- | Check whether Playwright browsers are installed.
--
-- Runs @npx playwright install --dry-run chromium@ to detect
-- installation status without modifying the system.
--
-- @since 0.19.1
checkPlaywrightStatus :: IO PlaywrightStatus
checkPlaywrightStatus = do
  (exitCode, _, _) <-
    Process.readProcessWithExitCode
      "npx"
      ["playwright", "install", "--dry-run", "chromium"]
      ""
  pure (interpretExitCode exitCode)
  where
    interpretExitCode Exit.ExitSuccess = PlaywrightReady
    interpretExitCode (Exit.ExitFailure _) = PlaywrightMissing Chromium

-- | Ensure Playwright is installed, prompting the user if needed.
--
-- Returns 'True' when browsers are available (either already installed
-- or successfully installed after user confirmation). Returns 'False'
-- when the user declines installation or installation fails.
--
-- @since 0.19.1
ensurePlaywrightInstalled :: IO Bool
ensurePlaywrightInstalled =
  checkPlaywrightStatus >>= handleStatus
  where
    handleStatus PlaywrightReady = pure True
    handleStatus (PlaywrightMissing _) = promptAndInstall
    handleStatus (PlaywrightCheckError _) = promptAndInstall

-- | Prompt user for installation confirmation and run installer.
promptAndInstall :: IO Bool
promptAndInstall = do
  printInstallPrompt
  response <- TextIO.getLine
  handleResponse response
  where
    handleResponse r
      | r `elem` ["", "y", "Y", "yes", "Yes"] = runPlaywrightInstall
      | otherwise = pure False

-- | Display the installation prompt explaining what will happen.
printInstallPrompt :: IO ()
printInstallPrompt = do
  Print.println [c|Browser tests require Playwright browsers to be installed.|]
  Print.newline
  Print.println [c|The following command will be run:|]
  Print.println [c|    npx playwright install chromium|]
  Print.newline
  Print.println [c|This will download ~150MB of browser binaries.|]
  Print.newline
  Print.print [c|Proceed? [Y/n] |]
  SysIO.hFlush SysIO.stdout

-- | Execute Playwright browser installation.
runPlaywrightInstall :: IO Bool
runPlaywrightInstall = do
  Print.println [c|Installing Playwright browsers...|]
  exitCode <- Process.rawSystem "npx" ["playwright", "install", "chromium"]
  reportResult exitCode
  where
    reportResult Exit.ExitSuccess = do
      Print.println [c|{green|Playwright installed successfully.}|]
      pure True
    reportResult _ = do
      Print.printErrLn [c|{red|Playwright installation failed.}|]
      pure False


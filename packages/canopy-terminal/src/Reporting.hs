{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Pure reporting and error display for Terminal.
--
-- Provides error reporting styles and output formatting for Terminal commands.
-- Supports both terminal and JSON output formats.
--
-- @since 0.19.1
module Reporting
  ( -- * Style Types
    Style (..),
    silent,
    terminal,
    json,

    -- * Error Display
    attempt,
    attemptWithStyle,

    -- * User Interaction
    ask,

    -- * Generation Reporting
    reportGenerate,
  )
where

import qualified Canopy.ModuleName as ModuleName
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NonEmptyList
import qualified Reporting.Ask as Ask
import qualified Reporting.Doc as Doc
import qualified Reporting.Exit as Exit
import System.IO (hPutStrLn, stdout)

-- | Reporting style for error output.
data Style
  = Silent -- ^ No output
  | Terminal -- ^ Human-readable terminal output
  | Json -- ^ JSON-formatted output
  deriving (Eq, Show)

-- | Silent reporting style.
silent :: Style
silent = Silent

-- | Terminal reporting style (default).
terminal :: Style
terminal = Terminal

-- | JSON reporting style.
json :: Style
json = Json

-- | Attempt an action with default terminal reporting style.
--
-- Runs the action and reports errors to the terminal using the default style.
-- This is a convenience wrapper around attemptWithStyle.
attempt ::
  (e -> Exit.Report) ->
  IO (Either e a) ->
  IO ()
attempt = attemptWithStyle Terminal

-- | Attempt an action with specific reporting style.
--
-- Runs the action and reports errors using the specified style.
-- Returns the result or prints error to stderr.
attemptWithStyle ::
  Style ->
  (e -> Exit.Report) ->
  IO (Either e a) ->
  IO ()
attemptWithStyle style toReport action = do
  result <- action
  case result of
    Right _ -> pure ()
    Left err -> reportError style (toReport err)

-- | Report error using specified style.
reportError :: Style -> Exit.Report -> IO ()
reportError style report =
  case style of
    Silent -> pure ()
    Terminal -> hPutStrLn stdout (show report)
    Json -> hPutStrLn stdout (Doc.toString report) -- TODO: proper JSON formatting

-- | Report successful generation.
--
-- Outputs generation success message showing modules compiled and output file.
reportGenerate :: Style -> List ModuleName.Raw -> FilePath -> IO ()
reportGenerate style moduleNames targetPath =
  case style of
    Silent -> pure ()
    Terminal -> printGenerationSuccess moduleNames targetPath
    Json -> pure () -- TODO: proper JSON formatting

-- | Print generation success message.
printGenerationSuccess :: List ModuleName.Raw -> FilePath -> IO ()
printGenerationSuccess moduleNames targetPath = do
  let count = length (NonEmptyList.toList moduleNames)
      modulesWord = if count == 1 then "module" else "modules"
  hPutStrLn stdout ("Success! Compiled " ++ show count ++ " " ++ modulesWord ++ " to " ++ targetPath)

-- | Ask user a question.
ask :: String -> IO Bool
ask = Ask.ask

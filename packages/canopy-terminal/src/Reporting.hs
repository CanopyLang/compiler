{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

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
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import Canopy.Data.NonEmptyList (List)
import qualified Canopy.Data.NonEmptyList as NonEmptyList
import qualified Json.Encode as Encode
import qualified Json.String as Json
import qualified Reporting.Ask as Ask
import qualified Reporting.Doc as Doc
import Reporting.Doc.ColorQQ (c)
import qualified Reporting.Exit as Exit
import qualified System.IO as IO
import qualified Terminal.Output as Output
import qualified Terminal.Print as Print

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
reportError style report_ =
  case style of
    Silent -> pure ()
    Terminal -> Print.printErrLn report_
    Json -> outputJson (Doc.encode report_)

-- | Report successful generation.
--
-- Outputs generation success message showing modules compiled and output file.
reportGenerate :: Style -> List ModuleName.Raw -> FilePath -> IO ()
reportGenerate style moduleNames targetPath =
  case style of
    Silent -> pure ()
    Terminal -> printGenerationSuccess moduleNames targetPath
    Json -> outputJson (buildGenerateJson moduleNames targetPath)

-- | Output a JSON value to IO.stdout.
outputJson :: Encode.Value -> IO ()
outputJson value =
  LBS.hPut IO.stdout (BB.toLazyByteString (Encode.encode value))
    >> IO.hPutStrLn IO.stdout ""

-- | Build JSON value for generation success report.
buildGenerateJson :: List ModuleName.Raw -> FilePath -> Encode.Value
buildGenerateJson moduleNames targetPath =
  Encode.object
    [ (Json.fromChars "type", Encode.string (Json.fromChars "compile-success"))
    , (Json.fromChars "target", Encode.string (Json.fromChars targetPath))
    , (Json.fromChars "count", Encode.int (length (NonEmptyList.toList moduleNames)))
    ]

-- | Print generation success message.
printGenerationSuccess :: List ModuleName.Raw -> FilePath -> IO ()
printGenerationSuccess moduleNames targetPath =
  Print.println [c|{green|Success!} Compiled #{countStr} to {cyan|#{targetPath}}|]
  where
    countStr = Output.showCount (length (NonEmptyList.toList moduleNames)) "module"

-- | Ask user a question.
ask :: String -> IO Bool
ask = Ask.ask

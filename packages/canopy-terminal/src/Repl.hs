{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wall #-}

-- | Interactive Read-Eval-Print Loop for Canopy.
--
-- This module provides the main REPL interface for interactive
-- Canopy development. It coordinates between input parsing,
-- evaluation, and output display.
--
-- The REPL supports:
--
-- * Interactive expression evaluation
-- * Type and value declarations
-- * Module imports
-- * Multi-line input with smart continuation
-- * Command system (:help, :reset, :exit)
-- * Auto-completion
-- * History management
--
-- @since 0.19.1
module Repl
  ( -- * Main Interface
    run,

    -- * Configuration
    Flags (..),

    -- * Re-exports for compatibility
    Lines (..),
    Input (..),
    Prefill (..),
    CategorizedInput (..),
    categorize,
    State (..),
    Output (..),
    toByteString,
  )
where

import qualified Canopy.Version as Version
import Control.Monad.State.Strict (StateT)
import qualified Control.Monad.State.Strict as State
import qualified Control.Monad.Trans as Trans
import Data.ByteString (ByteString)
import qualified Repl.Commands as Commands
import qualified Repl.Eval as Eval
import qualified Repl.State as State
import Repl.Types
  ( CategorizedInput,
    Env,
    Flags,
    Input,
    Lines,
    M,
    Output,
    Prefill,
    State,
  )
import qualified Repl.Types as Types
import Reporting.Doc ((<+>))
import qualified Reporting.Doc as Doc
import qualified Stuff
import System.Console.Haskeline (InputT, Settings)
import qualified System.Console.Haskeline as Haskeline
import System.Exit (ExitCode)
import qualified System.Exit as Exit
import System.FilePath ((</>))
import qualified System.IO as IO

-- | Main REPL entry point.
--
-- Initializes the REPL environment and starts the interactive loop.
--
-- @since 0.19.1
run :: () -> Flags -> IO ()
run () flags = do
  printWelcomeMessage
  settings <- initSettings
  env <- Eval.initEnv flags
  exitCode <- State.evalStateT (runRepl settings env) State.initialState
  Exit.exitWith exitCode

-- | Run the REPL with Haskeline integration.
--
-- @since 0.19.1
runRepl :: Settings M -> Env -> StateT State IO ExitCode
runRepl settings env =
  Haskeline.runInputT settings (Haskeline.withInterrupt (loop env State.initialState))

-- | Main REPL loop.
--
-- @since 0.19.1
loop :: Env -> State -> InputT M ExitCode
loop env state =
  Haskeline.handleInterrupt (pure Types.Skip) (readInput state)
    >>= Trans.liftIO . Eval.eval env state
    >>= \case
      Types.Loop newState -> do
        Trans.lift (State.put newState)
        loop env newState
      Types.End exitCode -> pure exitCode

-- | Read and parse user input.
--
-- @since 0.19.1
readInput :: State -> InputT M Input
readInput _state =
  Haskeline.getInputLine "> "
    >>= \case
      Nothing -> pure Types.Exit
      Just chars -> processInitialLine (Commands.stripLegacyBackslash chars)

-- | Process the first line of input.
--
-- @since 0.19.1
processInitialLine :: String -> InputT M Input
processInitialLine chars =
  case Commands.categorize (Types.Lines chars []) of
    Types.Done input -> pure input
    Types.Continue prefill ->
      readMoreLines (Types.Lines chars []) prefill

-- | Read additional lines for multi-line input.
--
-- @since 0.19.1
readMoreLines :: Lines -> Prefill -> InputT M Input
readMoreLines previousLines prefill =
  Haskeline.getInputLineWithInitial "| " (Commands.renderPrefill prefill, "")
    >>= \case
      Nothing -> pure Types.Skip
      Just chars -> processAdditionalLine previousLines chars

-- | Process additional lines in multi-line input.
--
-- @since 0.19.1
processAdditionalLine :: Lines -> String -> InputT M Input
processAdditionalLine previousLines chars =
  case Commands.categorize newLines of
    Types.Done input -> pure input
    Types.Continue prefill -> readMoreLines newLines prefill
  where
    newLines = Types.addLine (Commands.stripLegacyBackslash chars) previousLines

-- | Print welcome message on startup.
--
-- @since 0.19.1
printWelcomeMessage :: IO ()
printWelcomeMessage =
  Doc.toAnsi
    IO.stdout
    ( Doc.vcat
        [ Doc.black (Doc.fromChars "----") <+> Doc.dullcyan title <+> Doc.black (Doc.fromChars dashes),
          Doc.black (Doc.fromChars ("Say :help for help and :exit to exit! More at " <> Doc.makeLink "repl")),
          Doc.black (Doc.fromChars "--------------------------------------------------------------------------------"),
          Doc.empty
        ]
    )
  where
    vsn = Version.toChars Version.compiler
    title = Doc.fromChars "Canopy" <+> Doc.fromChars vsn
    dashes = replicate (70 - length vsn) '-'

-- | Initialize Haskeline settings.
--
-- @since 0.19.1
initSettings :: IO (Settings M)
initSettings = do
  cache <- Stuff.getReplCache
  pure
    Haskeline.Settings
      { Haskeline.historyFile = Just (cache </> "history"),
        Haskeline.autoAddHistory = True,
        Haskeline.complete = Haskeline.completeWord Nothing " \n" State.lookupCompletions
      }

-- Re-exports for backward compatibility
categorize :: Lines -> CategorizedInput
categorize = Commands.categorize

toByteString :: State -> Output -> ByteString
toByteString = State.toByteString

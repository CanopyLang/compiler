{-# OPTIONS_GHC -Wall #-}

-- | REPL evaluation engine and JavaScript execution.
--
-- This module handles the core evaluation logic of the REPL,
-- including compilation, JavaScript generation, and execution
-- of user code through the configured interpreter.
--
-- @since 0.19.1
module Repl.Eval
  ( -- * Evaluation
    eval,
    attemptEval,

    -- * JavaScript Execution
    interpret,

    -- * Environment Setup
    initEnv,
    getRoot,
    getInterpreter,
  )
where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Constraint as C
import qualified Canopy.Details as Details
import qualified Canopy.Licenses as Licenses
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Applicative ((<|>))
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Generate
import Repl.Commands (toHelpMessage)
import Repl.State (addDecl, addImport, addType, initialState, toByteString)
import Repl.Types
  ( Env (..),
    Flags (..),
    Input (..),
    Outcome (..),
    Output (..),
    State (..),
    toPrintName,
  )
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff
import qualified System.Console.Haskeline as Repl
import qualified System.Directory as Dir
import System.Exit (ExitCode)
import qualified System.Exit as Exit
import System.FilePath ((</>))
import qualified System.IO as IO
import qualified System.Process as Proc

-- | Main evaluation function for REPL input.
--
-- Processes user input and returns the next outcome (continue or exit).
-- Handles interruption gracefully and delegates to specific handlers
-- based on input type.
--
-- @since 0.19.1
eval :: Env -> State -> Input -> IO Outcome
eval env state input =
  Repl.handleInterrupt handleInterrupt (processInput env state input)
  where
    handleInterrupt = putStrLn "<cancelled>" >> pure (Loop state)

-- | Process different types of input.
--
-- @since 0.19.1
processInput :: Env -> State -> Input -> IO Outcome
processInput _ state Skip = pure (Loop state)
processInput _ _ Exit = pure (End Exit.ExitSuccess)
processInput _ _ Reset = putStrLn "<reset>" >> pure (Loop initialState)
processInput _ state (Help maybeCmd) =
  putStrLn (toHelpMessage maybeCmd) >> pure (Loop state)
processInput _ state Port =
  putStrLn "I cannot handle port declarations." >> pure (Loop state)
processInput env oldState (Import name src) =
  Loop <$> attemptEval env oldState (addImport name src oldState) OutputNothing
processInput env oldState (Type name src) =
  Loop <$> attemptEval env oldState (addType name src oldState) OutputNothing
processInput env oldState (Decl name src) =
  Loop <$> attemptEval env oldState (addDecl name src oldState) (OutputDecl name)
processInput env state (Expr src) =
  Loop <$> attemptEval env state state (OutputExpr src)

-- | Attempt to evaluate code with error handling.
--
-- Compiles the current state to JavaScript and executes it,
-- returning either the old state (on error) or new state (on success).
--
-- @since 0.19.1
attemptEval :: Env -> State -> State -> Output -> IO State
attemptEval (Env root interpreter ansi) oldState newState output =
  compileAndExecute >>= handleResult
  where
    compileAndExecute = do
      compResult <- BW.withScope (runCompilation root ansi newState output)
      case compResult of
        Left err -> pure (Left err)
        Right Nothing -> pure (Right Nothing)
        Right (Just javascript) -> do
          result <- executeJavaScript interpreter javascript
          pure (Right result)

    handleResult = either handleError handleSuccess

    handleError exit = Exit.toStderr (Exit.replToReport exit) >> pure oldState
    handleSuccess = maybe (pure newState) checkExecution

    checkExecution javascript = do
      exitCode <- interpret interpreter javascript
      pure (if exitCode == Exit.ExitSuccess then newState else oldState)

-- | Run compilation task.
--
-- @since 0.19.1
runCompilation :: FilePath -> Bool -> State -> Output -> BW.Scope -> IO (Either Exit.Repl (Maybe Builder))
runCompilation rootDir enableAnsi state output scope =
  Stuff.withRootLock rootDir (Task.run compilationTask)
  where
    compilationTask = do
      details <- Task.eio Exit.ReplBadDetails (Details.load Reporting.silent scope rootDir)
      artifacts <- Task.eio id (Build.fromRepl rootDir details (toByteString state output))
      traverse (generateJavaScript rootDir details enableAnsi artifacts) (toPrintName output)

    generateJavaScript projectRoot projectDetails projectAnsi artifacts name =
      Task.mapError Exit.ReplBadGenerate (Generate.repl projectRoot projectDetails projectAnsi artifacts name)

-- | Execute JavaScript and return result.
--
-- @since 0.19.1
executeJavaScript :: FilePath -> Builder -> IO (Maybe Builder)
executeJavaScript interpreter javascript = do
  exitCode <- interpret interpreter javascript
  pure (if exitCode == Exit.ExitSuccess then Just javascript else Nothing)

-- | Execute JavaScript code through interpreter.
--
-- @since 0.19.1
interpret :: FilePath -> Builder -> IO ExitCode
interpret interpreter javascript =
  Proc.withCreateProcess createProcess executeCode
  where
    createProcess = (Proc.proc interpreter []) {Proc.std_in = Proc.CreatePipe}
    executeCode (Just stdin) _ _ handle = do
      B.hPutBuilder stdin javascript
      IO.hClose stdin
      Proc.waitForProcess handle
    executeCode _ _ _ _ = pure (Exit.ExitFailure 1)

-- | Initialize REPL environment from flags.
--
-- @since 0.19.1
initEnv :: Flags -> IO Env
initEnv (Flags maybeInterpreter noColors) = do
  root <- getRoot
  interpreter <- getInterpreter maybeInterpreter
  pure (Env root interpreter (not noColors))

-- | Find or create project root directory.
--
-- @since 0.19.1
getRoot :: IO FilePath
getRoot = do
  maybeRoot <- Stuff.findRoot
  maybe createTempRoot pure maybeRoot
  where
    createTempRoot = do
      cache <- Stuff.getReplCache
      let root = cache </> "tmp"
      Dir.createDirectoryIfMissing True (root </> "src")
      Outline.write root defaultOutline
      pure root

    defaultOutline =
      Outline.Pkg
        ( Outline.PkgOutline
            Pkg.dummyName
            Outline.defaultSummary
            Licenses.bsd3
            V.one
            (Outline.ExposedList [])
            defaultDeps
            Map.empty
            C.defaultCanopy
        )

-- | Default package dependencies for REPL.
--
-- @since 0.19.1
defaultDeps :: Map Pkg.Name C.Constraint
defaultDeps =
  Map.fromList
    [ (Pkg.core, C.anything),
      (Pkg.json, C.anything),
      (Pkg.html, C.anything)
    ]

-- | Find JavaScript interpreter executable.
--
-- @since 0.19.1
getInterpreter :: Maybe String -> IO FilePath
getInterpreter maybeName =
  case maybeName of
    Just name -> getInterpreterHelp name (Dir.findExecutable name)
    Nothing -> getInterpreterHelp "node` or `nodejs" findNodeExecutable

-- | Find node or nodejs executable.
--
-- @since 0.19.1
findNodeExecutable :: IO (Maybe FilePath)
findNodeExecutable = do
  nodeExe <- Dir.findExecutable "node"
  nodejsExe <- Dir.findExecutable "nodejs"
  pure (nodeExe <|> nodejsExe)

-- | Helper for interpreter lookup with error handling.
--
-- @since 0.19.1
getInterpreterHelp :: String -> IO (Maybe FilePath) -> IO FilePath
getInterpreterHelp name findExe = do
  maybePath <- findExe
  case maybePath of
    Just path -> pure path
    Nothing -> do
      IO.hPutStrLn IO.stderr (exeNotFound name)
      Exit.exitFailure

-- | Error message for missing interpreter.
--
-- @since 0.19.1
exeNotFound :: String -> String
exeNotFound name =
  "The REPL relies on node.js to execute JavaScript code outside the browser.\n"
    ++ "I could not find executable `"
    ++ name
    ++ "` on your PATH though!\n\n"
    ++ "You can install node.js from <http://nodejs.org/>. If it is already installed\n"
    ++ "but has a different name, use the --interpreter flag."

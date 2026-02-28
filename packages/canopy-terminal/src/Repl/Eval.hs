{-# LANGUAGE QuasiQuotes #-}

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
import qualified Canopy.Constraint as Constraint
import qualified Canopy.Data.Name as Name
import qualified Canopy.Details as Details
import qualified Canopy.Interface as Interface
import qualified Canopy.Licenses as Licenses
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Applicative ((<|>))
import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Generate
import qualified Repl.Commands as Commands
import Repl.State (addDecl, addImport, addType, initialState)
import Repl.Types
  ( Env (..),
    Flags (..),
    Input (..),
    Outcome (..),
    Output (..),
    State (..),
    toPrintName,
  )
import qualified Repl.TypeQuery as TypeQuery
import qualified Reporting
import Reporting.Doc.ColorQQ (c)
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
import qualified Terminal.Print as Print

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
    handleInterrupt = Print.println [c|{yellow|<cancelled>}|] >> pure (Loop state)

-- | Process different types of input.
--
-- @since 0.19.1
processInput :: Env -> State -> Input -> IO Outcome
processInput _ state Skip = pure (Loop state)
processInput _ _ Exit = pure (End Exit.ExitSuccess)
processInput _ _ Reset = Print.println [c|{yellow|<reset>}|] >> pure (Loop initialState)
processInput _ state (Help maybeCmd) =
  Print.println [c|#{helpMsg}|] >> pure (Loop state)
  where
    helpMsg = Commands.toHelpMessage maybeCmd
processInput _ state Port =
  Print.println [c|{yellow|I cannot handle port declarations.}|] >> pure (Loop state)
processInput env oldState (Import name src) =
  Loop <$> attemptEval env oldState (addImport name src oldState) OutputNothing
processInput env oldState (Type name src) =
  Loop <$> attemptEval env oldState (addType name src oldState) OutputNothing
processInput env oldState (Decl name src) =
  Loop <$> attemptEval env oldState (addDecl name src oldState) (OutputDecl name)
processInput env state (Expr src) =
  Loop <$> attemptEval env state state (OutputExpr src)
processInput env state (TypeOf exprStr) =
  handleTypeOf env state exprStr >> pure (Loop state)
processInput env state (Browse maybeMod) =
  handleBrowse env state maybeMod >> pure (Loop state)

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
    compileAndExecute =
      BW.withScope (runCompilation root ansi newState output)
        >>= either (pure . Left) (fmap Right . maybeExecute)

    maybeExecute = maybe (pure Nothing) (executeJavaScript interpreter)

    handleResult = either handleError handleSuccess

    handleError exit = Exit.toStderr (Exit.replToReport exit) >> pure oldState
    handleSuccess = maybe (pure newState) checkExecution

    checkExecution javascript = do
      exitCode <- interpret interpreter javascript
      pure (if exitCode == Exit.ExitSuccess then newState else oldState)

-- | Handle the @:type@ command by compiling the expression and
-- extracting its type from the resulting interface.
--
-- The expression is wrapped as a declaration and compiled through
-- the normal pipeline.  On success, the type is extracted from the
-- compiled module's interface and displayed.
--
-- @since 0.19.2
handleTypeOf :: Env -> State -> String -> IO ()
handleTypeOf (Env root _interpreter _ansi) state exprStr = do
  result <- BW.withScope (compileForTypeOf root state exprStr)
  case result of
    Left exit -> Exit.toStderr (Exit.replToReport exit)
    Right Nothing -> Print.println [c|{red|I could not determine the type of that expression.}|]
    Right (Just typeStr) -> Print.println [c|#{typeStr}|]

-- | Compile an expression and extract its type.
--
-- Writes the current REPL state plus the expression as a temporary
-- source module, compiles it, and looks up the type of the expression
-- binding in the resulting interface.
--
-- @since 0.19.2
compileForTypeOf :: FilePath -> State -> String -> BW.Scope -> IO (Either Exit.Repl (Maybe String))
compileForTypeOf rootDir state exprStr scope = do
  writeReplSource rootDir state exprStr
  Stuff.withRootLock rootDir (Task.run typeTask)
  where
    typeTask = do
      details <- loadDetails scope rootDir
      artifacts <- compileRepl rootDir details
      pure (findTypeInModules Name.replValueToPrint (Build._artifactsModules artifacts))

    loadDetails sc rd =
      Task.io (Details.load Reporting.silent sc rd)
        >>= either (Task.throw . Exit.ReplBadDetails) pure

    compileRepl rd det =
      Task.io (Build.fromRepl rd det)
        >>= either (Task.throw . Exit.ReplCannotBuild) pure

-- | Search for a name's type across compiled modules.
--
-- @since 0.19.2
findTypeInModules :: Name.Name -> [Build.Module] -> Maybe String
findTypeInModules name modules =
  case modules of
    [] -> Nothing
    Build.Fresh _ iface _ : rest ->
      maybe (findTypeInModules name rest) Just (TypeQuery.formatTypeOf name iface)

-- | Write the REPL module source file to disk for compilation.
--
-- Creates a Canopy source module at @\<root\>\/src\/Main.can@ containing
-- the accumulated REPL state (imports, types, declarations) plus the
-- given expression wrapped as a @replValueToPrint@ binding.  The module
-- is named @Main@ to match what 'Build.fromRepl' expects.
--
-- @since 0.19.2
writeReplSource :: FilePath -> State -> String -> IO ()
writeReplSource rootDir (State imports types decls) exprStr =
  BS.writeFile sourcePath (LBS.toStrict (BB.toLazyByteString moduleBuilder))
  where
    sourcePath = rootDir </> "src" </> "Main.can"

    moduleBuilder =
      mconcat
        [ BB.stringUtf8 "module Main exposing (..)\n",
          Map.foldr mappend mempty imports,
          Map.foldr mappend mempty types,
          Map.foldr mappend mempty decls,
          Name.toBuilder Name.replValueToPrint,
          BB.stringUtf8 " =\n  ",
          BB.byteString (BSC.pack exprStr),
          BB.stringUtf8 "\n"
        ]

-- | Handle the @:browse@ command by listing module exports.
--
-- When no module name is given, lists all available modules from
-- the dependency interfaces.  When a module name is specified,
-- displays its exported values and types.
--
-- @since 0.19.2
handleBrowse :: Env -> State -> Maybe String -> IO ()
handleBrowse (Env root _interpreter _ansi) _state maybeMod = do
  result <- BW.withScope (compileForBrowse root)
  either (Exit.toStderr . Exit.replToReport) (displayBrowseResult maybeMod) result

-- | Display browse results, dispatching based on whether a module
-- name was provided.
--
-- @since 0.19.2
displayBrowseResult :: Maybe String -> Build.Artifacts -> IO ()
displayBrowseResult maybeMod artifacts =
  maybe displayAllModules (browseModule artifacts) maybeMod
  where
    stateInfo = TypeQuery.formatBrowseState artifacts
    displayAllModules = Print.println [c|#{stateInfo}|]

-- | Compile the REPL project to access dependency interfaces.
--
-- @since 0.19.2
compileForBrowse :: FilePath -> BW.Scope -> IO (Either Exit.Repl Build.Artifacts)
compileForBrowse rootDir scope =
  Stuff.withRootLock rootDir (Task.run browseTask)
  where
    browseTask = do
      details <- loadDetails scope rootDir
      Task.io (Build.fromRepl rootDir details)
        >>= either (Task.throw . Exit.ReplCannotBuild) pure

    loadDetails sc rd =
      Task.io (Details.load Reporting.silent sc rd)
        >>= either (Task.throw . Exit.ReplBadDetails) pure

-- | Browse a specific module's exports.
--
-- @since 0.19.2
browseModule :: Build.Artifacts -> String -> IO ()
browseModule artifacts modName =
  case findModuleInterface (Name.fromChars modName) (Build._artifactsDeps artifacts) of
    Nothing -> Print.println [c|{red|I cannot find a module named #{modName}.}|]
    Just iface -> Print.println [c|#{browseOutput}|]
      where
        browseOutput = TypeQuery.formatBrowseModule (Name.fromChars modName) iface

-- | Find a module's public interface by raw name.
--
-- @since 0.19.2
findModuleInterface ::
  ModuleName.Raw ->
  Map ModuleName.Canonical Interface.DependencyInterface ->
  Maybe Interface.Interface
findModuleInterface rawName deps =
  case Map.elems (Map.filterWithKey matchesRawName deps) of
    Interface.Public iface : _ -> Just iface
    _ -> Nothing
  where
    matchesRawName (ModuleName.Canonical _ name) _ = name == rawName

-- | Run compilation task.
--
-- @since 0.19.1
runCompilation :: FilePath -> Bool -> State -> Output -> BW.Scope -> IO (Either Exit.Repl (Maybe Builder))
runCompilation rootDir enableAnsi _state output scope =
  Stuff.withRootLock rootDir (Task.run compilationTask)
  where
    compilationTask = do
      details <- Task.io (Details.load Reporting.silent scope rootDir) >>= either (Task.throw . Exit.ReplBadDetails) pure
      artifacts <- Task.io (Build.fromRepl rootDir details) >>= either (Task.throw . Exit.ReplCannotBuild) pure
      traverse (generateJavaScript rootDir details enableAnsi artifacts) (toPrintName output)

    generateJavaScript projectRoot projectDetails projectAnsi artifacts name =
      let config = Generate.ReplConfig projectAnsi name
      in Task.mapError Exit.ReplBadGenerate (Generate.repl projectRoot projectDetails config artifacts)

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
      BB.hPutBuilder stdin javascript
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
            Version.one
            (Outline.ExposedList [])
            defaultDeps
            Map.empty
            Constraint.defaultCanopy
        )

-- | Default package dependencies for REPL.
--
-- @since 0.19.1
defaultDeps :: Map Pkg.Name Constraint.Constraint
defaultDeps =
  Map.fromList
    [ (Pkg.core, Constraint.anything),
      (Pkg.json, Constraint.anything),
      (Pkg.html, Constraint.anything)
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
      let errMsg = exeNotFound name
      Print.printErrLn [c|#{errMsg}|]
      Exit.exitFailure

-- | Error message for missing interpreter.
--
-- @since 0.19.1
exeNotFound :: String -> String
exeNotFound name =
  "The REPL relies on node.js to execute JavaScript code outside the browser.\n" <> ("I could not find executable `" <> (name <> ("` on your PATH though!\n\n" <> ("You can install node.js from <http://nodejs.org/>. If it is already installed\n" <> "but has a different name, use the --interpreter flag."))))

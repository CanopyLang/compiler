{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Execute custom scripts defined in canopy.json.
--
-- When a project defines a @\"scripts\"@ field in its @canopy.json@,
-- the build system can invoke named scripts at specific lifecycle
-- points (e.g., before or after a build).
--
-- == Supported Script Hooks
--
-- * @prebuild@  -- Runs before compilation begins.
-- * @postbuild@ -- Runs after successful compilation.
-- * @test@      -- Runs as the test command.
--
-- Scripts are executed via the system shell (@\/bin\/sh -c@ on Unix,
-- @cmd \/c@ on Windows).
--
-- @since 0.19.2
module Scripts
  ( -- * Script Execution
    runScript,
    runHook,
    runBuildHook,

    -- * Script Lookup
    lookupScript,
    hasScript,

    -- * Types
    ScriptResult (..),
    ScriptName,
  )
where

import qualified Canopy.Details as Details
import qualified Canopy.Outline as Outline
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Reporting.Doc.ColorQQ (c)
import qualified System.Exit as Exit
import qualified System.Process as Process
import qualified Terminal.Print as Print

-- | Name of a script defined in the @\"scripts\"@ field.
type ScriptName = Text.Text

-- | Result of running a script.
--
-- @since 0.19.2
data ScriptResult
  = -- | Script completed successfully.
    ScriptSuccess
  | -- | Script exited with a non-zero code.
    ScriptFailure !Int
  | -- | No script with the given name was found.
    ScriptNotFound
  deriving (Eq, Show)

-- | Look up a named script in the application outline.
--
-- Returns 'Nothing' if the outline has no @\"scripts\"@ field or
-- the requested name is not present.
--
-- @since 0.19.2
lookupScript :: ScriptName -> Outline.AppOutline -> Maybe Text.Text
lookupScript name appOutline =
  Outline._appScripts appOutline >>= Map.lookup name

-- | Check whether a named script exists in the application outline.
--
-- @since 0.19.2
hasScript :: ScriptName -> Outline.AppOutline -> Bool
hasScript name appOutline =
  case lookupScript name appOutline of
    Just _ -> True
    Nothing -> False

-- | Run a named script from the application outline.
--
-- Looks up the script by name, then executes it via the system shell.
-- Prints the script name and command before execution.
--
-- @since 0.19.2
runScript :: ScriptName -> Outline.AppOutline -> IO ScriptResult
runScript name appOutline =
  maybe (pure ScriptNotFound) executeCommand (lookupScript name appOutline)
  where
    executeCommand cmd = do
      let cmdStr = Text.unpack cmd
          nameStr = Text.unpack name
      Print.println [c|{bold|Running script} {cyan|#{nameStr}}: #{cmdStr}|]
      exitCode <- Process.system cmdStr
      toScriptResult nameStr exitCode

-- | Run a build lifecycle hook if it is defined.
--
-- Unlike 'runScript', this function silently succeeds when the hook
-- is not defined.  If the hook IS defined and fails, it returns
-- the 'ScriptFailure'.
--
-- @since 0.19.2
runHook :: ScriptName -> Outline.AppOutline -> IO ScriptResult
runHook name appOutline =
  if hasScript name appOutline
    then runScript name appOutline
    else pure ScriptSuccess

-- | Run a build lifecycle hook using project 'Details.Details'.
--
-- Extracts the 'Outline.AppOutline' from the validated outline.
-- For package projects (which have no scripts field), this is a no-op.
--
-- @since 0.19.2
runBuildHook :: ScriptName -> Details.Details -> IO ScriptResult
runBuildHook name details =
  case Details._detailsOutline details of
    Details.ValidApp appOutline -> runHook name appOutline
    Details.ValidPkg {} -> pure ScriptSuccess

-- | Convert a process exit code to a 'ScriptResult' and print status.
toScriptResult :: String -> Exit.ExitCode -> IO ScriptResult
toScriptResult name Exit.ExitSuccess = do
  Print.println [c|{green|Script} {cyan|#{name}} {green|completed successfully.}|]
  pure ScriptSuccess
toScriptResult name (Exit.ExitFailure code) = do
  let codeStr = show code
  Print.println [c|{red|Script} {cyan|#{name}} {red|failed with exit code} #{codeStr}|]
  pure (ScriptFailure code)

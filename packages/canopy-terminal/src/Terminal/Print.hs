{-# OPTIONS_GHC -Wall #-}

-- | TTY-aware terminal output using 'P.Doc' values.
--
-- Renders colorized 'P.Doc' output when connected to a terminal device,
-- automatically stripping ANSI escape codes when piped or redirected.
-- Also respects the @NO_COLOR@ environment variable
-- (<https://no-color.org/>) — when set to any non-empty value, all color
-- output is suppressed regardless of terminal detection.
--
-- Pair with @Reporting.Doc.ColorQQ@ to produce colored, interpolated
-- terminal messages:
--
-- @
-- Print.println [c|{green|Success!} Compiled %{count} modules|]
-- @
--
-- @since 0.19.1
module Terminal.Print
  ( println,
    print,
    newline,
    printErrLn,
    printErr,
  )
where

import qualified GHC.IO.Handle as Handle
import qualified Reporting.Doc as D
import qualified System.Environment as Env
import qualified System.IO as IO
import qualified Text.PrettyPrint.ANSI.Leijen as P
import Prelude hiding (print)

-- | Print a 'P.Doc' to stdout with a trailing newline. Colors if TTY.
println :: P.Doc -> IO ()
println doc = printToHandle IO.stdout doc >> IO.putStrLn ""

-- | Print a 'P.Doc' to stdout without a trailing newline. Colors if TTY.
print :: P.Doc -> IO ()
print = printToHandle IO.stdout

-- | Print a blank line to stdout.
newline :: IO ()
newline = IO.putStrLn ""

-- | Print a 'P.Doc' to stderr with a trailing newline. Colors if TTY.
printErrLn :: P.Doc -> IO ()
printErrLn doc = printToHandle IO.stderr doc >> IO.hPutStrLn IO.stderr ""

-- | Print a 'P.Doc' to stderr without a trailing newline. Colors if TTY.
printErr :: P.Doc -> IO ()
printErr = printToHandle IO.stderr

-- | Render a 'P.Doc' to a handle, choosing ANSI or plain based on TTY
-- detection and the @NO_COLOR@ environment variable.
--
-- When @NO_COLOR@ is set to any non-empty value, ANSI output is suppressed
-- even if the handle is connected to a terminal. See <https://no-color.org/>.
printToHandle :: IO.Handle -> P.Doc -> IO ()
printToHandle handle doc = do
  useColor <- shouldUseColor handle
  if useColor
    then D.toAnsi handle doc
    else IO.hPutStr handle (D.toString doc)

-- | Determine whether to emit ANSI color codes for the given handle.
--
-- Returns 'True' only when the handle is a terminal device AND the
-- @NO_COLOR@ environment variable is either unset or empty.
shouldUseColor :: IO.Handle -> IO Bool
shouldUseColor handle = do
  isTerminal <- Handle.hIsTerminalDevice handle
  if not isTerminal
    then pure False
    else isColorEnabled

-- | Check whether color output is enabled based on @NO_COLOR@ env var.
isColorEnabled :: IO Bool
isColorEnabled = do
  noColor <- Env.lookupEnv "NO_COLOR"
  pure (not (isNonEmpty noColor))
  where
    isNonEmpty Nothing = False
    isNonEmpty (Just "") = False
    isNonEmpty (Just _) = True

{-# LANGUAGE OverloadedStrings #-}

-- | Kit command dispatcher.
--
-- Routes incoming 'KitCommand' values to the appropriate command
-- implementation ('Kit.New', 'Kit.Dev', 'Kit.Build'). This module
-- is the single entry point used by the CLI command definitions.
--
-- @since 0.19.2
module Kit
  ( run
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Kit.Build as Build
import qualified Kit.Dev as Dev
import qualified Kit.New as New
import Kit.Types (KitCommand (..))
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Exit.Kit as ExitKit

-- | Dispatch a 'KitCommand' to the corresponding implementation.
--
-- @since 0.19.2
run :: KitCommand -> IO ()
run (KitNew name) = runNew name
run (KitDev flags) = Dev.dev flags
run (KitBuild flags) = Build.build flags

-- | Run project scaffolding and report the result.
runNew :: Text.Text -> IO ()
runNew name =
  New.scaffold name >>= reportScaffoldResult

-- | Print a success message or an error report for scaffolding.
reportScaffoldResult :: Either ExitKit.Kit Text.Text -> IO ()
reportScaffoldResult (Right msg) = TextIO.putStrLn msg
reportScaffoldResult (Left err) = Help.toStderr (ExitKit.kitToReport err)

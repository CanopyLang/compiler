{-# LANGUAGE OverloadedStrings #-}

-- | CLI command definitions for the Kit framework.
--
-- Provides three top-level commands for the Kit application framework:
--
--   * @canopy kit-new \<name\>@ -- scaffold a new Kit project
--   * @canopy kit-dev@ -- start the development server
--   * @canopy kit-build@ -- produce a production build
--
-- Each command follows the standard 'Terminal.Command' pattern with
-- argument parsers, flag configurations, and help text.
--
-- @since 0.19.2
module CLI.Commands.Kit
  ( createKitNewCommand
  , createKitDevCommand
  , createKitBuildCommand
  ) where

import CLI.Documentation (reflowText, stackDocuments)
import CLI.Parsers (createPortParser)
import CLI.Types (Command, (|--))
import qualified Data.Text as Text
import qualified Kit
import Kit.Types (KitBuildFlags (..), KitCommand (..), KitDevFlags (..))
import qualified Terminal
import qualified Terminal.Helpers as Terminal
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Create the @kit-new@ command for scaffolding a Kit project.
--
-- @since 0.19.2
createKitNewCommand :: Command
createKitNewCommand =
  Terminal.Command "kit-new" (Terminal.Common summary) details example args Terminal.noFlags runKitNew
  where
    summary = "Create a new Kit project with file-system routing, layouts, and Vite."
    details = "The `kit-new` command scaffolds a complete Kit application:"
    example = kitNewExample
    args = Terminal.require1 id (Terminal.stringParser "PROJECT_NAME" "project name")

-- | Help text example for the @kit-new@ command.
kitNewExample :: PP.Doc
kitNewExample =
  stackDocuments
    [ reflowText "For example:"
    , PP.indent 4 (PP.green "canopy kit-new my-app")
    , reflowText "This creates a my-app/ directory with routes, layouts, canopy.json, and Vite configuration."
    ]

-- | Create the @kit-dev@ command for the development server.
--
-- @since 0.19.2
createKitDevCommand :: Command
createKitDevCommand =
  Terminal.Command "kit-dev" (Terminal.Common summary) details example Terminal.noArgs flags runKitDev
  where
    summary = "Start the Kit development server with hot reloading and route watching."
    details = "The `kit-dev` command starts a Vite dev server and watches for route changes:"
    example = PP.indent 4 (PP.green "canopy kit-dev")
    flags = createKitDevFlags

-- | Create the @kit-build@ command for production builds.
--
-- @since 0.19.2
createKitBuildCommand :: Command
createKitBuildCommand =
  Terminal.Command "kit-build" (Terminal.Common summary) details example Terminal.noArgs flags runKitBuild
  where
    summary = "Build a Kit application for production deployment."
    details = "The `kit-build` command compiles, pre-renders, and bundles your Kit app:"
    example = kitBuildExample
    flags = createKitBuildFlags

-- | Help text example for the @kit-build@ command.
kitBuildExample :: PP.Doc
kitBuildExample =
  stackDocuments
    [ reflowText "For example:"
    , PP.indent 4 (PP.green "canopy kit-build --optimize")
    , reflowText "This compiles your Canopy code with optimizations and bundles it with Vite."
    ]

-- | Handler for the @kit-new@ command.
runKitNew :: String -> () -> IO ()
runKitNew projectName () =
  Kit.run (KitNew (Text.pack projectName))

-- | Handler for the @kit-dev@ command.
runKitDev :: () -> KitDevFlags -> IO ()
runKitDev () flags =
  Kit.run (KitDev flags)

-- | Handler for the @kit-build@ command.
runKitBuild :: () -> KitBuildFlags -> IO ()
runKitBuild () flags =
  Kit.run (KitBuild flags)

-- | Flag configuration for the @kit-dev@ command.
createKitDevFlags :: Terminal.Flags KitDevFlags
createKitDevFlags =
  Terminal.flags KitDevFlags
    |-- Terminal.flag "port" createPortParser "Port for the development server (default: 5173)."
    |-- Terminal.onOff "open" "Open a browser window automatically when the server starts."

-- | Flag configuration for the @kit-build@ command.
createKitBuildFlags :: Terminal.Flags KitBuildFlags
createKitBuildFlags =
  Terminal.flags KitBuildFlags
    |-- Terminal.onOff "optimize" "Enable Canopy optimizations for smaller, faster output."
    |-- Terminal.flag "output" kitOutputParser "Override the default output directory (build/)."

-- | Parser for the @--output@ flag on @kit-build@.
kitOutputParser :: Terminal.Parser FilePath
kitOutputParser =
  Terminal.Parser
    { Terminal._singular = "output directory"
    , Terminal._plural = "output directories"
    , Terminal._parser = Just
    , Terminal._suggest = \_ -> pure []
    , Terminal._examples = \_ -> pure ["build", "dist", "out"]
    }

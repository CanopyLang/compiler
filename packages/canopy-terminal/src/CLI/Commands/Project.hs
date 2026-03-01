{-# LANGUAGE OverloadedStrings #-}

-- | CLI command definitions for project management.
--
-- Contains init, new, and setup commands for creating and configuring
-- Canopy projects.
--
-- @since 0.19.1
module CLI.Commands.Project
  ( createInitCommand,
    createNewCommand,
    createSetupCommand,
  )
where

import CLI.Documentation (reflowText, stackDocuments)
import CLI.Types (Command, (|--))
import qualified Init
import qualified New
import qualified Setup
import qualified Terminal
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Create the init command for starting new Canopy projects.
--
-- @since 0.19.1
createInitCommand :: Command
createInitCommand =
  Terminal.Command "init" (Terminal.Common summary) details example Terminal.noArgs Terminal.noFlags Init.run
  where
    summary =
      "Start a Canopy project. It creates a starter canopy.json file and\
      \ provides a link explaining what to do from there."
    details = "The `init` command helps start Canopy projects:"
    example =
      reflowText
        "It will ask permission to create a canopy.json file, the one thing common\
        \ to all Canopy projects. It also provides a link explaining what to do from there."

-- | Create the new command for scaffolding complete Canopy projects.
--
-- @since 0.19.1
createNewCommand :: Command
createNewCommand =
  Terminal.Command "new" (Terminal.Common summary) details example args flags New.run
  where
    summary =
      "Create a new Canopy project in a fresh directory with all the files\
      \ you need to get started."
    details = "The `new` command creates a complete Canopy project:"
    example =
      stackDocuments
        [ reflowText "For example:",
          PP.indent 4 (PP.green "canopy new my-app"),
          reflowText
            "This creates a my-app/ directory with canopy.json, a starter Main.can,\
            \ and initializes a git repository."
        ]
    args = Terminal.require1 id (Terminal.stringParser "PROJECT_NAME" "project name")
    flags = createNewFlags

-- | Create the setup command for package environment bootstrap.
--
-- @since 0.19.1
createSetupCommand :: Command
createSetupCommand =
  Terminal.Command "setup" (Terminal.Common summary) details example Terminal.noArgs flags Setup.run
  where
    summary = "Set up the Canopy package environment. Downloads the package registry and locates standard library packages."
    details = "The `setup` command initializes your Canopy development environment:"
    example = PP.indent 4 (PP.green "canopy setup")
    flags = createSetupFlags

-- FLAGS

createNewFlags :: Terminal.Flags New.Flags
createNewFlags =
  Terminal.flags New.Flags
    |-- Terminal.flag "template" New.templateParser "Project template to use: app (default) or package."
    |-- Terminal.onOff "no-git" "Skip git repository initialization."

createSetupFlags :: Terminal.Flags Setup.Flags
createSetupFlags =
  Terminal.flags Setup.Flags
    |-- Terminal.onOff "verbose" "Show verbose output during setup."

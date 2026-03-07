{-# LANGUAGE OverloadedStrings #-}

-- | CLI command definitions for local package linking.
--
-- Contains link and unlink commands for local package development
-- via symlinks in the global cache.
--
-- @since 0.19.2
module CLI.Commands.Link
  ( createLinkCommand,
    createUnlinkCommand,
  )
where

import CLI.Documentation (reflowText, stackDocuments)
import CLI.Types (Command)
import qualified Link
import qualified Terminal
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Create the link command for local package development.
--
-- @since 0.19.2
createLinkCommand :: Command
createLinkCommand =
  Terminal.Command "link" (Terminal.Common summary) details example args Terminal.noFlags linkHandler
  where
    summary =
      "Register a local package in the global cache via symlink for development."
    details = "The `link` command creates a symlink from ~/.canopy/packages/ to a local package directory:"
    example =
      stackDocuments
        [ reflowText "In a package directory:",
          PP.indent 4 (PP.green "canopy link"),
          reflowText "Or specify a path:",
          PP.indent 4 (PP.green "canopy link ./packages/canopy/json")
        ]
    args = Terminal.optional (Terminal.fileParser [])

-- | Create the unlink command for removing package symlinks.
--
-- @since 0.19.2
createUnlinkCommand :: Command
createUnlinkCommand =
  Terminal.Command "unlink" Terminal.Uncommon details example args Terminal.noFlags unlinkHandler
  where
    details = "The `unlink` command removes a package symlink from the global cache:"
    example = PP.indent 4 (PP.green "canopy unlink")
    args = Terminal.optional (Terminal.fileParser [])

-- | Handler for the link command.
linkHandler :: Maybe FilePath -> () -> IO ()
linkHandler maybePath () = Link.runLink maybePath Link.LinkFlags

-- | Handler for the unlink command.
unlinkHandler :: Maybe FilePath -> () -> IO ()
unlinkHandler maybePath () = Link.runUnlink maybePath Link.UnlinkFlags

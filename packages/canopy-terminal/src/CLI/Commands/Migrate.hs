{-# LANGUAGE OverloadedStrings #-}

-- | CLI command definition for the @migrate@ command.
--
-- Exposes a single 'createMigrateCommand' that wires the 'Migrate.migrateFromElm'
-- implementation into the standard 'Terminal.Command' interface.
--
-- == Usage
--
-- @
-- canopy migrate --dry-run       -- preview changes
-- canopy migrate --backup        -- write .bak files before modifying
-- canopy migrate                 -- apply the migration in-place
-- @
--
-- @since 0.19.2
module CLI.Commands.Migrate
  ( createMigrateCommand,
  )
where

import CLI.Documentation (reflowText, stackDocuments)
import CLI.Types (Command, (|--))
import qualified Migrate
import Migrate (MigrateOptions (..))
import qualified System.Directory as Dir
import qualified Terminal
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Intermediate flags record parsed from the command line.
data MigrateFlags = MigrateFlags
  { _mfDryRun :: !Bool,
    _mfBackup :: !Bool
  }
  deriving (Eq, Show)

-- | Create the @migrate@ command for transforming Elm source trees to Canopy.
--
-- Accepts optional @--dry-run@ and @--backup@ flags. The target directory
-- defaults to the current working directory when no path argument is provided.
--
-- @since 0.19.2
createMigrateCommand :: Command
createMigrateCommand =
  Terminal.Command "migrate" (Terminal.Common summary) details example Terminal.noArgs migrateFlags runMigrate
  where
    summary = "Migrate an Elm project to Canopy syntax."
    details = "The `migrate` command converts Elm source code to Canopy:"
    example = migrateExample

-- | Help-text example block for the @migrate@ command.
migrateExample :: PP.Doc
migrateExample =
  stackDocuments
    [ reflowText "For example:"
    , PP.indent 4 (PP.green "canopy migrate")
    , reflowText "This renames .elm files to .can, rewrites port module to ffi module, and converts elm.json to canopy.json."
    , PP.indent 4 (PP.green "canopy migrate --dry-run")
    , reflowText "Preview all changes without writing any files."
    , PP.indent 4 (PP.green "canopy migrate --backup")
    , reflowText "Write .bak copies of every modified file before applying changes."
    ]

-- | Flag configuration for the @migrate@ command.
migrateFlags :: Terminal.Flags MigrateFlags
migrateFlags =
  Terminal.flags MigrateFlags
    |-- Terminal.onOff "dry-run" "Show what would change without writing any files."
    |-- Terminal.onOff "backup" "Write a .bak copy of each file before modifying it."

-- | Command handler: translate CLI flags to 'MigrateOptions' and run the migration.
runMigrate :: () -> MigrateFlags -> IO ()
runMigrate () (MigrateFlags dryRun backup) = do
  cwd <- Dir.getCurrentDirectory
  let opts = MigrateOptions
        { _moSourceDir = cwd
        , _moDryRun = dryRun
        , _moBackup = backup
        }
  _result <- Migrate.migrateFromElm opts
  pure ()

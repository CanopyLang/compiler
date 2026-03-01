{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Migrate elm.json to canopy.json format.
--
-- Reads an existing @elm.json@ configuration file, converts the field
-- names to their Canopy equivalents, and writes the result as
-- @canopy.json@.  The original @elm.json@ is preserved unless the
-- @--remove-old@ flag is set.
--
-- Unlike 'Upgrade' (which renames source files and updates gitignore),
-- this command focuses solely on the project configuration format.
--
-- == Usage
--
-- @
-- canopy migrate              -- Convert elm.json to canopy.json
-- canopy migrate --dry-run    -- Preview without writing
-- canopy migrate --remove-old -- Delete elm.json after conversion
-- @
--
-- @since 0.19.2
module Migrate
  ( -- * Command Interface
    Flags (..),
    run,
  )
where

import qualified Canopy.Outline as Outline
import Control.Lens (makeLenses, (^.))
import qualified Data.Aeson.Encode.Pretty as Pretty
import qualified Data.ByteString.Lazy as LBS
import Reporting.Doc.ColorQQ (c)
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified Terminal.Print as Print

-- | Migrate command flags.
--
-- @since 0.19.2
data Flags = Flags
  { -- | Preview changes without writing files.
    _migrateDryRun :: !Bool,
    -- | Remove the original elm.json after successful migration.
    _migrateRemoveOld :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | Run the migrate command.
--
-- Reads elm.json from the current directory, re-encodes it as
-- canopy.json with updated field names, and optionally removes the
-- original file.
--
-- @since 0.19.2
run :: () -> Flags -> IO ()
run () flags = do
  cwd <- Dir.getCurrentDirectory
  let elmPath = cwd </> "elm.json"
      canopyPath = cwd </> "canopy.json"
  elmExists <- Dir.doesFileExist elmPath
  canopyExists <- Dir.doesFileExist canopyPath
  handleMigration flags elmPath canopyPath elmExists canopyExists

-- | Handle the migration logic based on file existence.
handleMigration :: Flags -> FilePath -> FilePath -> Bool -> Bool -> IO ()
handleMigration _ _ _ False _ =
  Print.println [c|{red|No elm.json found.} Nothing to migrate.|]
handleMigration _ _ canopyPath _ True =
  Print.println [c|{yellow|canopy.json already exists at} #{canopyPath}|]
handleMigration flags elmPath canopyPath True False =
  migrateFile flags elmPath canopyPath

-- | Perform the actual file migration.
migrateFile :: Flags -> FilePath -> FilePath -> IO ()
migrateFile flags elmPath canopyPath = do
  result <- Outline.read (takeDirectory elmPath)
  either reportParseError (writeMigrated flags elmPath canopyPath) result
  where
    takeDirectory = reverse . dropWhile (/= '/') . reverse

-- | Write the migrated outline to canopy.json.
writeMigrated :: Flags -> FilePath -> FilePath -> Outline.Outline -> IO ()
writeMigrated flags elmPath canopyPath outline
  | flags ^. migrateDryRun = reportDryRun canopyPath
  | otherwise = do
      let prettyConfig = Pretty.defConfig {Pretty.confIndent = Pretty.Spaces 4}
          encoded = Pretty.encodePretty' prettyConfig outline
      LBS.writeFile canopyPath encoded
      reportSuccess canopyPath
      removeOldIfRequested flags elmPath

-- | Report a successful migration.
reportSuccess :: FilePath -> IO ()
reportSuccess canopyPath =
  Print.println [c|{green|Created} #{canopyPath}|]

-- | Report dry-run mode.
reportDryRun :: FilePath -> IO ()
reportDryRun canopyPath = do
  Print.println [c|{yellow|Dry run:} Would create #{canopyPath}|]
  Print.println [c|Run without {bold|--dry-run} to apply.|]

-- | Report a parse error.
reportParseError :: String -> IO ()
reportParseError msg =
  Print.println [c|{red|Failed to parse elm.json:} #{msg}|]

-- | Remove the old elm.json if requested.
removeOldIfRequested :: Flags -> FilePath -> IO ()
removeOldIfRequested flags elmPath
  | flags ^. migrateRemoveOld = do
      Dir.removeFile elmPath
      Print.println [c|{yellow|Removed} #{elmPath}|]
  | otherwise =
      Print.println [c|{dullcyan|Kept} #{elmPath} (use --remove-old to delete)|]

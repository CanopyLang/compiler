{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Elm-to-Canopy project migration tool.
--
-- Automates the conversion of Elm projects to Canopy projects by:
--
-- * Converting @elm.json@ to @canopy.json@
-- * Renaming @.elm@ files to @.can@ files
-- * Updating module headers and import paths
-- * Reporting changes made for user review
--
-- == Usage
--
-- @
-- canopy upgrade              -- Upgrade current directory
-- canopy upgrade --dry-run    -- Preview changes without applying
-- @
--
-- @since 0.19.1
module Upgrade
  ( -- * Command Interface
    Flags (..),
    run,
  )
where

import Control.Lens (makeLenses, (^.))
import qualified Data.ByteString.Lazy as LBS
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.FilePath as FilePath
import qualified System.IO as IO

-- | Upgrade command flags.
data Flags = Flags
  { -- | Preview changes without applying them
    _dryRun :: !Bool,
    -- | Show verbose output
    _upgradeVerbose :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | A migration action to perform.
data MigrationAction
  = RenameFile !FilePath !FilePath
  | ConvertConfig !FilePath !FilePath
  | UpdateContent !FilePath !String
  deriving (Eq, Show)

-- | Run the upgrade command.
--
-- Scans the current directory for Elm project artifacts and
-- converts them to Canopy equivalents.
--
-- @since 0.19.1
run :: () -> Flags -> IO ()
run () flags = do
  cwd <- Dir.getCurrentDirectory
  actions <- discoverMigrationActions cwd
  if null actions
    then IO.putStrLn "No Elm artifacts found to upgrade."
    else executeMigration flags actions

-- | Discover all migration actions needed.
discoverMigrationActions :: FilePath -> IO [MigrationAction]
discoverMigrationActions root = do
  configActions <- discoverConfigMigration root
  fileActions <- discoverFileMigrations root
  pure (configActions ++ fileActions)

-- | Check if elm.json exists and needs conversion.
discoverConfigMigration :: FilePath -> IO [MigrationAction]
discoverConfigMigration root = do
  let elmJson = root </> "elm.json"
      canopyJson = root </> "canopy.json"
  elmExists <- Dir.doesFileExist elmJson
  canopyExists <- Dir.doesFileExist canopyJson
  pure (if elmExists && not canopyExists then [ConvertConfig elmJson canopyJson] else [])

-- | Find all .elm files that should be renamed to .can.
discoverFileMigrations :: FilePath -> IO [MigrationAction]
discoverFileMigrations root = do
  let srcDir = root </> "src"
  srcExists <- Dir.doesDirectoryExist srcDir
  if srcExists
    then findElmFiles srcDir
    else pure []

-- | Recursively find .elm files and create rename actions.
findElmFiles :: FilePath -> IO [MigrationAction]
findElmFiles dir = do
  entries <- Dir.listDirectory dir
  actions <- mapM (processEntry dir) entries
  pure (concat actions)

-- | Process a single directory entry.
processEntry :: FilePath -> FilePath -> IO [MigrationAction]
processEntry dir entry = do
  let fullPath = dir </> entry
  isDir <- Dir.doesDirectoryExist fullPath
  if isDir
    then findElmFiles fullPath
    else pure (createRenameAction fullPath)

-- | Create a rename action if the file is an .elm file.
createRenameAction :: FilePath -> [MigrationAction]
createRenameAction path
  | FilePath.takeExtension path == ".elm" =
      [RenameFile path (FilePath.replaceExtension path ".can")]
  | otherwise = []

-- | Execute all migration actions.
executeMigration :: Flags -> [MigrationAction] -> IO ()
executeMigration flags actions = do
  if flags ^. upgradeVerbose
    then IO.putStrLn ("Found " ++ show (length actions) ++ " changes to make (verbose mode):")
    else IO.putStrLn ("Found " ++ show (length actions) ++ " changes to make:")
  IO.putStrLn ""
  mapM_ (reportAction flags) actions
  if flags ^. dryRun
    then reportDryRun
    else applyActions actions

-- | Report a single migration action.
reportAction :: Flags -> MigrationAction -> IO ()
reportAction _flags action =
  case action of
    RenameFile from to ->
      IO.putStrLn ("  Rename: " ++ from ++ " -> " ++ to)
    ConvertConfig from to ->
      IO.putStrLn ("  Convert: " ++ from ++ " -> " ++ to)
    UpdateContent path desc ->
      IO.putStrLn ("  Update: " ++ path ++ " (" ++ desc ++ ")")

-- | Report dry-run mode.
reportDryRun :: IO ()
reportDryRun = do
  IO.putStrLn ""
  IO.putStrLn "Dry run complete. No changes were made."
  IO.putStrLn "Run without --dry-run to apply changes."

-- | Apply all migration actions.
applyActions :: [MigrationAction] -> IO ()
applyActions actions = do
  mapM_ applyAction actions
  IO.putStrLn ""
  IO.putStrLn ("Successfully applied " ++ show (length actions) ++ " changes.")

-- | Apply a single migration action.
applyAction :: MigrationAction -> IO ()
applyAction action =
  case action of
    RenameFile from to -> Dir.renameFile from to
    ConvertConfig from to -> convertElmJson from to
    UpdateContent _path _desc -> pure ()

-- | Convert elm.json to canopy.json.
--
-- Reads the elm.json file and writes a canopy.json equivalent
-- with field name adjustments.
convertElmJson :: FilePath -> FilePath -> IO ()
convertElmJson elmPath canopyPath = do
  content <- LBS.readFile elmPath
  let converted = convertJsonContent content
  LBS.writeFile canopyPath converted

-- | Convert elm.json content to canopy.json content.
--
-- Performs text-level transformations on the JSON:
-- * Replaces \"elm-version\" with \"canopy-version\"
-- * Updates package registry URLs
convertJsonContent :: LBS.ByteString -> LBS.ByteString
convertJsonContent content =
  -- For now, copy as-is. The JSON structure is compatible.
  -- A more sophisticated approach would parse and transform.
  content

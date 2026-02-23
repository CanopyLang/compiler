{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Elm-to-Canopy project migration tool.
--
-- Automates the conversion of Elm projects to Canopy projects by:
--
-- * Converting @elm.json@ to @canopy.json@
-- * Renaming @.elm@ files to @.can@ files
-- * Updating @.gitignore@ entries from @elm-stuff@ to @.canopy-stuff@
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

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Control.Lens (makeLenses, (^.))
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
  = -- | Rename a file from old path to new path
    RenameFile !FilePath !FilePath
  | -- | Convert elm.json to canopy.json
    ConvertConfig !FilePath !FilePath
  | -- | Apply text replacements to a file
    UpdateContent !FilePath !String ![(BS.ByteString, BS.ByteString)]
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
  contentActions <- discoverContentUpdates root
  pure (configActions ++ fileActions ++ contentActions)

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

-- | Discover content updates for supporting files.
--
-- Checks for .gitignore and similar files that reference
-- Elm-specific paths or terminology.
discoverContentUpdates :: FilePath -> IO [MigrationAction]
discoverContentUpdates root = do
  gitignoreAction <- discoverGitignoreUpdate root
  pure gitignoreAction

-- | Check if .gitignore needs elm-stuff → .canopy-stuff update.
discoverGitignoreUpdate :: FilePath -> IO [MigrationAction]
discoverGitignoreUpdate root = do
  let gitignorePath = root </> ".gitignore"
  exists <- Dir.doesFileExist gitignorePath
  if exists
    then do
      content <- BS.readFile gitignorePath
      pure (if BS.isInfixOf "elm-stuff" content
            then [UpdateContent gitignorePath "update elm-stuff references" gitignoreReplacements]
            else [])
    else pure []

-- | Replacements for .gitignore content.
gitignoreReplacements :: [(BS.ByteString, BS.ByteString)]
gitignoreReplacements =
  [ ("elm-stuff", ".canopy-stuff")
  ]

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
  IO.putStrLn ("Found " ++ show (length actions) ++ " changes to make:")
  IO.putStrLn ""
  mapM_ reportAction actions
  verboseLog flags ("Processing " ++ show (length actions) ++ " migration actions")
  if flags ^. dryRun
    then reportDryRun
    else applyActions actions

-- | Report a single migration action.
reportAction :: MigrationAction -> IO ()
reportAction (RenameFile from to) =
  IO.putStrLn ("  Rename: " ++ from ++ " -> " ++ to)
reportAction (ConvertConfig from to) =
  IO.putStrLn ("  Convert: " ++ from ++ " -> " ++ to)
reportAction (UpdateContent path desc _) =
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
applyAction (RenameFile from to) = Dir.renameFile from to
applyAction (ConvertConfig from to) = convertElmJson from to
applyAction (UpdateContent path _ replacements) = applyReplacements path replacements

-- | Apply text replacements to a file.
applyReplacements :: FilePath -> [(BS.ByteString, BS.ByteString)] -> IO ()
applyReplacements path replacements = do
  content <- BS.readFile path
  let updated = foldl applyReplacement content replacements
  BS.writeFile path updated

-- | Apply a single replacement to ByteString content.
applyReplacement :: BS.ByteString -> (BS.ByteString, BS.ByteString) -> BS.ByteString
applyReplacement content (needle, replacement) =
  replaceAll needle replacement content

-- | Replace all occurrences of needle with replacement.
replaceAll :: BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString
replaceAll needle replacement haystack =
  case BS.breakSubstring needle haystack of
    (before, after)
      | BS.null after -> haystack
      | otherwise ->
          before <> replacement <> replaceAll needle replacement (BS.drop (BS.length needle) after)

-- | Convert elm.json to canopy.json.
--
-- Reads the elm.json file and writes a canopy.json equivalent
-- with field name adjustments.
convertElmJson :: FilePath -> FilePath -> IO ()
convertElmJson elmPath canopyPath = do
  content <- LBS.readFile elmPath
  LBS.writeFile canopyPath (convertJsonContent content)

-- | Convert elm.json content to canopy.json content.
--
-- Performs text-level transformations on the JSON:
--
-- * Replaces @\"elm-version\"@ with @\"canopy-version\"@
-- * Replaces @\"elm-explorations\"@ author with @\"canopy-explorations\"@
-- * Updates package source URL references
convertJsonContent :: LBS.ByteString -> LBS.ByteString
convertJsonContent content =
  foldl applyLazyReplacement content jsonReplacements

-- | Replacements for elm.json → canopy.json conversion.
jsonReplacements :: [(LBS.ByteString, LBS.ByteString)]
jsonReplacements =
  [ ("\"elm-version\"", "\"canopy-version\"")
  , ("\"elm-explorations\"", "\"canopy-explorations\"")
  , ("\"elm-stuff\"", "\".canopy-stuff\"")
  ]

-- | Apply a single replacement to lazy ByteString content.
applyLazyReplacement :: LBS.ByteString -> (LBS.ByteString, LBS.ByteString) -> LBS.ByteString
applyLazyReplacement content (needle, replacement) =
  replaceLazyAll needle replacement content

-- | Replace all occurrences in lazy ByteString.
replaceLazyAll :: LBS.ByteString -> LBS.ByteString -> LBS.ByteString -> LBS.ByteString
replaceLazyAll needle replacement haystack =
  let strict = LBS.toStrict haystack
      needleStrict = LBS.toStrict needle
      replacementStrict = LBS.toStrict replacement
   in LBS.fromStrict (replaceAll needleStrict replacementStrict strict)

-- | Log a message if verbose mode is enabled.
verboseLog :: Flags -> String -> IO ()
verboseLog flags message =
  if flags ^. upgradeVerbose
    then IO.putStrLn ("  [verbose] " ++ message)
    else pure ()

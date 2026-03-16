{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Elm-to-Canopy source code migration codemod.
--
-- Transforms Elm source trees into Canopy syntax by applying a set of
-- well-defined text-level transformations. No AST parsing is required —
-- all rewrites operate line-by-line or as whole-file substitutions.
--
-- == Transformations Applied
--
-- * @.elm@ file extensions are renamed to @.can@
-- * @port module@ declarations are rewritten to @ffi module@
-- * @elm.json@ is converted to @canopy.json@ with field and package renames
-- * Package author prefixes @elm/@ are replaced with @canopy/@ in source imports
-- * @elm-stuff@ directory references are updated to @.canopy-stuff@
--
-- == Usage
--
-- @
-- let opts = MigrateOptions { _moSourceDir = ".", _moDryRun = False, _moBackup = True }
-- result <- migrateFromElm opts
-- print (_mrFilesModified result)
-- @
--
-- @since 0.19.2
module Migrate
  ( -- * Entry Point
    migrateFromElm,

    -- * Types
    MigrateOptions (..),
    MigrateResult (..),

    -- * Lenses
    moSourceDir,
    moDryRun,
    moBackup,
    mrFilesModified,
    mrChangesApplied,
    mrWarnings,

    -- * Transformations
    transformFileContent,
    renameElmFile,
    convertProjectFile,
  )
where

import Control.Lens (makeLenses, (^.))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Convert.PackageMap as PackageMap
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.FilePath as FilePath
import qualified Terminal.Output as Output
import qualified Terminal.Print as Print
import Reporting.Doc.ColorQQ (c)

-- | Options controlling the migration run.
--
-- @since 0.19.2
data MigrateOptions = MigrateOptions
  { -- | Root directory containing the Elm project to migrate.
    _moSourceDir :: !FilePath,
    -- | When 'True', report what would change but do not write any files.
    _moDryRun :: !Bool,
    -- | When 'True', write a @.bak@ copy of each file before modifying it.
    _moBackup :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''MigrateOptions

-- | Summary of a completed migration run.
--
-- @since 0.19.2
data MigrateResult = MigrateResult
  { -- | Number of files that were (or would be) modified.
    _mrFilesModified :: !Int,
    -- | Total number of individual changes applied across all files.
    _mrChangesApplied :: !Int,
    -- | Non-fatal warnings encountered during migration.
    _mrWarnings :: ![Text.Text]
  }
  deriving (Eq, Show)

makeLenses ''MigrateResult

-- | A single migration action to perform on the filesystem.
data MigrationAction
  = -- | Rename a @.elm@ file to @.can@ (and transform its content).
    MigrateSourceFile !FilePath !FilePath
  | -- | Convert @elm.json@ to @canopy.json@.
    ConvertProjectFile !FilePath !FilePath
  | -- | Apply byte-level replacements to an existing file.
    UpdateContent !FilePath ![(BS.ByteString, BS.ByteString)]
  deriving (Eq, Show)

-- | Run the @from-elm@ migration on the directory specified in 'MigrateOptions'.
--
-- Discovers all Elm artifacts under '_moSourceDir', reports what will change,
-- and — unless '_moDryRun' is set — applies the transformations.
--
-- @since 0.19.2
migrateFromElm :: MigrateOptions -> IO MigrateResult
migrateFromElm opts = do
  actions <- discoverActions (opts ^. moSourceDir)
  reportDiscovery actions
  if opts ^. moDryRun
    then reportDryRun actions
    else applyActions opts actions

-- | Discover all migration actions in the given root directory.
discoverActions :: FilePath -> IO [MigrationAction]
discoverActions root = do
  projActions <- discoverProjectFileMigration root
  srcActions <- discoverSourceFileMigrations root
  gitActions <- discoverGitignoreUpdate root
  pure (projActions ++ srcActions ++ gitActions)

-- | Check whether @elm.json@ exists and needs to become @canopy.json@.
discoverProjectFileMigration :: FilePath -> IO [MigrationAction]
discoverProjectFileMigration root = do
  let elmJson = root </> "elm.json"
      canopyJson = root </> "canopy.json"
  elmExists <- Dir.doesFileExist elmJson
  canopyExists <- Dir.doesFileExist canopyJson
  pure (if elmExists && not canopyExists
        then [ConvertProjectFile elmJson canopyJson]
        else [])

-- | Recursively find all @.elm@ files under @\<root\>\/src@.
discoverSourceFileMigrations :: FilePath -> IO [MigrationAction]
discoverSourceFileMigrations root = do
  let srcDir = root </> "src"
  exists <- Dir.doesDirectoryExist srcDir
  if exists
    then findElmFiles srcDir
    else pure []

-- | Check whether @.gitignore@ references @elm-stuff@ and needs updating.
discoverGitignoreUpdate :: FilePath -> IO [MigrationAction]
discoverGitignoreUpdate root = do
  let path = root </> ".gitignore"
  exists <- Dir.doesFileExist path
  if not exists
    then pure []
    else do
      content <- BS.readFile path
      pure (if BS.isInfixOf "elm-stuff" content
            then [UpdateContent path gitignoreReplacements]
            else [])

-- | Byte replacements for @.gitignore@ migration.
gitignoreReplacements :: [(BS.ByteString, BS.ByteString)]
gitignoreReplacements =
  [("elm-stuff", ".canopy-stuff")]

-- | Walk a directory tree and produce 'MigrateSourceFile' actions for @.elm@ files.
findElmFiles :: FilePath -> IO [MigrationAction]
findElmFiles dir = do
  entries <- Dir.listDirectory dir
  nested <- mapM (processEntry dir) entries
  pure (concat nested)

-- | Process one filesystem entry, recursing into sub-directories.
processEntry :: FilePath -> FilePath -> IO [MigrationAction]
processEntry dir entry = do
  let full = dir </> entry
  isDir <- Dir.doesDirectoryExist full
  if isDir
    then findElmFiles full
    else pure (sourceFileAction full)

-- | Produce a 'MigrateSourceFile' action if the path ends in @.elm@.
sourceFileAction :: FilePath -> [MigrationAction]
sourceFileAction path
  | FilePath.takeExtension path == ".elm" =
      [MigrateSourceFile path (FilePath.replaceExtension path ".can")]
  | otherwise = []

-- | Print a summary of what was discovered.
reportDiscovery :: [MigrationAction] -> IO ()
reportDiscovery [] =
  Print.println [c|No Elm artifacts found to migrate.|]
reportDiscovery actions = do
  let countStr = Output.showCount (length actions) "change"
  Print.println [c|Found {bold|#{countStr}} to apply:|]
  Print.newline
  mapM_ reportAction actions

-- | Print a description of a single action.
reportAction :: MigrationAction -> IO ()
reportAction (MigrateSourceFile from to) =
  Print.println [c|  {cyan|Rename + transform:} #{from} -> #{to}|]
reportAction (ConvertProjectFile from to) =
  Print.println [c|  {cyan|Convert:} #{from} -> #{to}|]
reportAction (UpdateContent path _) =
  Print.println [c|  {cyan|Update:} #{path}|]

-- | Report the result of a dry run without applying anything.
reportDryRun :: [MigrationAction] -> IO MigrateResult
reportDryRun actions = do
  Print.newline
  Print.println [c|{yellow|Dry run complete.} No files were modified.|]
  Print.println [c|Run without {bold|--dry-run} to apply changes.|]
  pure (MigrateResult 0 (length actions) [])

-- | Apply all discovered actions and return a result summary.
applyActions :: MigrateOptions -> [MigrationAction] -> IO MigrateResult
applyActions opts actions = do
  results <- mapM (applyAction opts) actions
  let (files, changes) = List.foldl' sumResult (0, 0) results
      changesSummary = Output.showCount changes "change"
      filesSummary = Output.showCount files "file"
  Print.newline
  Print.println [c|{green|Migration complete.} #{changesSummary} applied to #{filesSummary}.|]
  pure (MigrateResult files changes [])

-- | Accumulate per-action file and change counts.
sumResult :: (Int, Int) -> (Int, Int) -> (Int, Int)
sumResult (fa, ca) (fb, cb) = (fa + fb, ca + cb)

-- | Apply a single migration action, returning (filesModified, changesApplied).
applyAction :: MigrateOptions -> MigrationAction -> IO (Int, Int)
applyAction opts = \case
  MigrateSourceFile from to -> applySourceFileMigration opts from to
  ConvertProjectFile from to -> convertProjectFile from to >> pure (1, 1)
  UpdateContent path replacements -> applyContentUpdate opts path replacements

-- | Transform and rename a single @.elm@ source file.
applySourceFileMigration :: MigrateOptions -> FilePath -> FilePath -> IO (Int, Int)
applySourceFileMigration opts from to = do
  content <- BS.readFile from
  let transformed = TE.encodeUtf8 (transformFileContent (TE.decodeUtf8 content))
  applyBackup opts from
  BS.writeFile to transformed
  Dir.removeFile from
  pure (1, 1)

-- | Apply byte-level replacements to a content file.
applyContentUpdate :: MigrateOptions -> FilePath -> [(BS.ByteString, BS.ByteString)] -> IO (Int, Int)
applyContentUpdate opts path replacements = do
  content <- BS.readFile path
  applyBackup opts path
  BS.writeFile path (List.foldl' applyReplacement content replacements)
  pure (1, length replacements)

-- | Write a @.bak@ copy of a file when backup mode is enabled.
applyBackup :: MigrateOptions -> FilePath -> IO ()
applyBackup opts path =
  if opts ^. moBackup
    then Dir.copyFile path (path ++ ".bak")
    else pure ()

-- | Apply all line-level and token-level transformations to a source file's content.
--
-- Transformations are applied in order:
--
-- 1. @port module@ → @ffi module@
-- 2. @import Elm.@ module prefixes → @import Canopy.@ equivalents
--
-- The function operates on 'Text.Text' so that unicode source is handled correctly.
--
-- @since 0.19.2
transformFileContent :: Text.Text -> Text.Text
transformFileContent =
  Text.unlines . map transformLine . Text.lines

-- | Apply all transformations to a single source line.
transformLine :: Text.Text -> Text.Text
transformLine line =
  List.foldl' applyTextReplacement line sourceLineReplacements

-- | Apply a single search-and-replace to a 'Text.Text' value.
applyTextReplacement :: Text.Text -> (Text.Text, Text.Text) -> Text.Text
applyTextReplacement content (needle, replacement) =
  Text.replace needle replacement content

-- | Text replacements applied to every line of a @.elm@ source file.
--
-- Only syntactic tokens that differ between Elm and Canopy are listed here.
-- Import paths that map onto canopy.json package names are handled at the
-- project-file level by 'convertProjectFile'.
sourceLineReplacements :: [(Text.Text, Text.Text)]
sourceLineReplacements =
  [ ("port module", "ffi module")
  ]

-- | Rename a @.elm@ file to @.can@ in place, transforming its content.
--
-- If the destination already exists it is overwritten.
--
-- @since 0.19.2
renameElmFile :: FilePath -> IO ()
renameElmFile path = do
  content <- BS.readFile path
  let transformed = TE.encodeUtf8 (transformFileContent (TE.decodeUtf8 content))
      newPath = FilePath.replaceExtension path ".can"
  BS.writeFile newPath transformed
  Dir.removeFile path

-- | Convert an @elm.json@ file to @canopy.json@ format.
--
-- Returns 'Just' the written content on success, or 'Nothing' if the
-- source file did not exist.
--
-- @since 0.19.2
convertProjectFile :: FilePath -> FilePath -> IO (Maybe Text.Text)
convertProjectFile from to = do
  exists <- Dir.doesFileExist from
  if not exists
    then pure Nothing
    else do
      content <- LBS.readFile from
      let converted = convertJsonContent content
      LBS.writeFile to converted
      pure (Just (TE.decodeUtf8 (LBS.toStrict converted)))

-- | Apply all JSON-level transformations to @elm.json@ content.
convertJsonContent :: LBS.ByteString -> LBS.ByteString
convertJsonContent content =
  List.foldl' applyLazyReplacement content jsonReplacements

-- | Replacements applied to @elm.json@ to produce @canopy.json@.
--
-- Delegates to 'PackageMap.elmToCanopyLazyReplacements' as the single
-- source of truth for all elm-to-canopy package mappings.
jsonReplacements :: [(LBS.ByteString, LBS.ByteString)]
jsonReplacements = PackageMap.elmToCanopyLazyReplacements

-- | Apply a lazy ByteString search-and-replace.
applyLazyReplacement :: LBS.ByteString -> (LBS.ByteString, LBS.ByteString) -> LBS.ByteString
applyLazyReplacement content (needle, replacement) =
  LBS.fromStrict (replaceAllStrict needleS replacementS (LBS.toStrict content))
  where
    needleS = LBS.toStrict needle
    replacementS = LBS.toStrict replacement

-- | Apply a strict ByteString search-and-replace globally.
applyReplacement :: BS.ByteString -> (BS.ByteString, BS.ByteString) -> BS.ByteString
applyReplacement content (needle, replacement) =
  replaceAllStrict needle replacement content

-- | Replace every non-overlapping occurrence of @needle@ in @haystack@.
replaceAllStrict :: BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString
replaceAllStrict needle replacement haystack =
  case BS.breakSubstring needle haystack of
    (before, after)
      | BS.null after -> haystack
      | otherwise ->
          before
            <> replacement
            <> replaceAllStrict needle replacement (BS.drop (BS.length needle) after)

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Fmt - CLI handler for the @canopy format@ / @canopy fmt@ command.
--
-- This module implements the source code formatter for Canopy @.can@ files.
-- It supports three primary modes:
--
-- * __Normal__ - Format files in-place (default)
-- * __Check__ - Exit non-zero when any file would change; useful in CI
-- * __Stdin__ - Read from stdin, write normalized source to stdout
--
-- == Usage
--
-- @
-- canopy fmt src\/Main.can          -- format single file in-place
-- canopy fmt                        -- format every .can file under src\/
-- canopy fmt --check src\/Main.can  -- CI mode: fail if file is not formatted
-- canopy fmt --stdin < src\/Foo.can -- pipe mode
-- canopy fmt --indent=2             -- use 2-space indentation
-- canopy fmt --line-width=100       -- target 100-column lines
-- @
--
-- == Architecture
--
-- The handler delegates to 'Format.formatFile' (pure AST round-trip) from
-- the @canopy-core@ package and handles all IO concerns here:
-- file discovery, reading, writing, and result reporting.
--
-- @since 0.19.1
module Fmt
  ( -- * Main entry point
    run,

    -- * Flags
    Flags (..),
  )
where

import qualified Data.ByteString as BS
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Format (FormatConfig (..))
import qualified Format
import qualified System.Directory as Dir
import Reporting.Doc.ColorQQ (c)
import qualified System.Exit as Exit
import qualified System.FilePath as FP
import qualified Terminal.Print as Print

-- ---------------------------------------------------------------------------
-- Flags
-- ---------------------------------------------------------------------------

-- | Configuration flags for the @fmt@ command.
--
-- All flags default to 'False' / 'Nothing'; the CLI layer fills them in
-- via 'Terminal.flag' / 'Terminal.onOff'.
--
-- @since 0.19.1
data Flags = Flags
  { _check :: !Bool
  -- ^ When 'True', report which files would change and exit non-zero instead
  -- of writing them. Suitable for CI gating.
  , _stdin :: !Bool
  -- ^ When 'True', read source from stdin and write formatted output to
  -- stdout; ignore any file-path arguments.
  , _indent :: !(Maybe Int)
  -- ^ Number of spaces per indentation level. Defaults to 4 when 'Nothing'.
  , _lineWidth :: !(Maybe Int)
  -- ^ Target maximum line width. Defaults to 80 when 'Nothing'.
  }
  deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- | Build a 'FormatConfig' from the CLI flags, using sensible defaults.
--
-- @since 0.19.1
buildConfig :: Flags -> FormatConfig
buildConfig flags = FormatConfig
  { _fmtIndent = Maybe.fromMaybe 4 (_indent flags)
  , _fmtLineWidth = Maybe.fromMaybe 80 (_lineWidth flags)
  }

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

-- | Main entry point called by the CLI framework.
--
-- Dispatches to 'runStdin', 'runCheckMode', or 'runFormatMode' depending
-- on which flags are active.
--
-- @since 0.19.1
run :: [FilePath] -> Flags -> IO ()
run paths flags
  | _stdin flags = runStdin config
  | _check flags = runCheckMode config paths
  | otherwise = runFormatMode config paths
  where
    config = buildConfig flags

-- ---------------------------------------------------------------------------
-- Stdin mode
-- ---------------------------------------------------------------------------

-- | Read source from stdin, format it, write result to stdout.
--
-- Reports a parse error to stderr and exits non-zero when the input is
-- syntactically invalid.
runStdin :: FormatConfig -> IO ()
runStdin config = do
  bytes <- BS.getContents
  either reportParseError writeFormatted (Format.formatBytes config bytes)
  where
    reportParseError err = do
      let errStr = show err
      Print.printErrLn [c|{red|canopy fmt:} parse error: #{errStr}|]
      Exit.exitWith (Exit.ExitFailure 1)
    writeFormatted formatted =
      BS.putStr (Text.encodeUtf8 formatted)

-- ---------------------------------------------------------------------------
-- Check mode
-- ---------------------------------------------------------------------------

-- | Check whether any file needs formatting; exit non-zero if so.
--
-- Does not modify any files. Reports each file that would change to stderr.
runCheckMode :: FormatConfig -> [FilePath] -> IO ()
runCheckMode config paths = do
  targets <- resolveTargets paths
  results <- mapM (checkFile config) targets
  reportCheckResults [p | (p, NeedsFormatting) <- results]

-- | Report check results and exit appropriately.
reportCheckResults :: [FilePath] -> IO ()
reportCheckResults [] = Print.println [c|{green|All files are formatted.}|]
reportCheckResults unformatted = do
  Print.printErrLn [c|{red|The following files are not formatted:}|]
  mapM_ (\p -> Print.printErrLn [c|  {cyan|#{p}}|]) unformatted
  Exit.exitWith (Exit.ExitFailure 1)

-- | Outcome of checking whether a single file needs formatting.
data CheckResult = AlreadyFormatted | NeedsFormatting
  deriving (Eq)

-- | Determine whether a single file is already formatted.
checkFile :: FormatConfig -> FilePath -> IO (FilePath, CheckResult)
checkFile config path = do
  original <- BS.readFile path
  pure (path, classifyResult original (Format.formatBytes config original))

-- | Classify whether formatted output differs from the original.
classifyResult :: BS.ByteString -> Either e Text.Text -> CheckResult
classifyResult _ (Left _) = AlreadyFormatted
classifyResult original (Right formatted)
  | original == Text.encodeUtf8 formatted = AlreadyFormatted
  | otherwise = NeedsFormatting

-- ---------------------------------------------------------------------------
-- Format mode
-- ---------------------------------------------------------------------------

-- | Format files in-place.
--
-- Reports parse errors to stderr but continues processing remaining files.
runFormatMode :: FormatConfig -> [FilePath] -> IO ()
runFormatMode config paths = do
  targets <- resolveTargets paths
  mapM_ (formatFileInPlace config) targets

-- | Format a single file in-place, writing back only when the output differs.
formatFileInPlace :: FormatConfig -> FilePath -> IO ()
formatFileInPlace config path = do
  original <- BS.readFile path
  either (reportError path) (writeIfChanged path original) (Format.formatBytes config original)
  where
    reportError p err = do
      let errStr = show err
      Print.printErrLn [c|{red|canopy fmt:} {cyan|#{p}}: #{errStr}|]
    writeIfChanged p orig formatted =
      writeWhenChanged p orig (Text.encodeUtf8 formatted)

-- | Write new content only if it differs from the current file content.
writeWhenChanged :: FilePath -> BS.ByteString -> BS.ByteString -> IO ()
writeWhenChanged path original new
  | original == new = pure ()
  | otherwise = do
      BS.writeFile path new
      Print.println [c|{green|Formatted:} {cyan|#{path}}|]

-- ---------------------------------------------------------------------------
-- Target resolution
-- ---------------------------------------------------------------------------

-- | Resolve the list of target paths to a flat list of @.can@ files.
--
-- When no paths are provided the formatter discovers every @.can@ file
-- under the @src/@ directory of the current project, if it exists.
resolveTargets :: [FilePath] -> IO [FilePath]
resolveTargets [] = discoverCanopyFiles "src"
resolveTargets paths = do
  expanded <- mapM expandPath paths
  pure (List.nub (concat expanded))

-- | Expand a single path to a list of @.can@ files.
--
-- Directories are searched recursively; plain @.can@ files are returned
-- as-is; anything else is silently ignored.
expandPath :: FilePath -> IO [FilePath]
expandPath path = do
  isDir <- Dir.doesDirectoryExist path
  if isDir
    then discoverCanopyFiles path
    else pure [path | isCanopyFile path]

-- | Recursively collect all @.can@ files under a directory.
discoverCanopyFiles :: FilePath -> IO [FilePath]
discoverCanopyFiles dir = do
  exists <- Dir.doesDirectoryExist dir
  if not exists
    then pure []
    else do
      entries <- Dir.listDirectory dir
      let fullPaths = map (dir FP.</>) entries
      files <- filterFiles fullPaths
      dirs <- filterDirs fullPaths
      nested <- mapM discoverCanopyFiles (filter isNotHidden dirs)
      pure (filter isCanopyFile files ++ concat nested)

-- | Filter a list of paths to only existing regular files.
filterFiles :: [FilePath] -> IO [FilePath]
filterFiles = fmap concat . mapM keepIfFile
  where
    keepIfFile p = do
      isFile <- Dir.doesFileExist p
      pure (if isFile then [p] else [])

-- | Filter a list of paths to only existing directories.
filterDirs :: [FilePath] -> IO [FilePath]
filterDirs = fmap concat . mapM keepIfDir
  where
    keepIfDir p = do
      isDir <- Dir.doesDirectoryExist p
      pure (if isDir then [p] else [])

-- | Predicate: is the path a Canopy source file?
isCanopyFile :: FilePath -> Bool
isCanopyFile p = FP.takeExtension p `elem` [".can", ".canopy"]

-- | Predicate: is the directory not a hidden directory?
isNotHidden :: FilePath -> Bool
isNotHidden = not . List.isPrefixOf "." . FP.takeFileName

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Format
import qualified System.Directory as Dir
import qualified System.Exit as Exit
import qualified System.FilePath as FP
import qualified System.IO as IO

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
  }
  deriving (Eq, Show)

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
  | _stdin flags = runStdin
  | _check flags = runCheckMode paths
  | otherwise = runFormatMode paths

-- ---------------------------------------------------------------------------
-- Stdin mode
-- ---------------------------------------------------------------------------

-- | Read source from stdin, format it, write result to stdout.
--
-- Reports a parse error to stderr and exits non-zero when the input is
-- syntactically invalid.
runStdin :: IO ()
runStdin = do
  bytes <- BS.getContents
  case Format.formatBytes bytes of
    Left err -> do
      IO.hPutStrLn IO.stderr ("canopy fmt: parse error: " ++ show err)
      Exit.exitWith (Exit.ExitFailure 1)
    Right formatted ->
      BS.putStr (Text.encodeUtf8 formatted)

-- ---------------------------------------------------------------------------
-- Check mode
-- ---------------------------------------------------------------------------

-- | Check whether any file needs formatting; exit non-zero if so.
--
-- Does not modify any files. Reports each file that would change to stderr.
runCheckMode :: [FilePath] -> IO ()
runCheckMode paths = do
  targets <- resolveTargets paths
  results <- mapM checkFile targets
  let unformatted = [p | (p, NeedsFormatting) <- results]
  reportCheckResults unformatted

-- | Report check results and exit appropriately.
reportCheckResults :: [FilePath] -> IO ()
reportCheckResults [] = putStrLn "All files are formatted."
reportCheckResults unformatted = do
  IO.hPutStrLn IO.stderr "The following files are not formatted:"
  mapM_ (\p -> IO.hPutStrLn IO.stderr ("  " ++ p)) unformatted
  Exit.exitWith (Exit.ExitFailure 1)

-- | Outcome of checking whether a single file needs formatting.
data CheckResult = AlreadyFormatted | NeedsFormatting
  deriving (Eq)

-- | Determine whether a single file is already formatted.
checkFile :: FilePath -> IO (FilePath, CheckResult)
checkFile path = do
  original <- BS.readFile path
  case Format.formatBytes original of
    Left _ -> pure (path, AlreadyFormatted)
    Right formatted ->
      pure (path, classifyChange original formatted)

-- | Classify whether formatted output differs from the original.
classifyChange :: BS.ByteString -> Text.Text -> CheckResult
classifyChange original formatted =
  if original == Text.encodeUtf8 formatted
    then AlreadyFormatted
    else NeedsFormatting

-- ---------------------------------------------------------------------------
-- Format mode
-- ---------------------------------------------------------------------------

-- | Format files in-place.
--
-- Reports parse errors to stderr but continues processing remaining files.
runFormatMode :: [FilePath] -> IO ()
runFormatMode paths = do
  targets <- resolveTargets paths
  mapM_ formatFileInPlace targets

-- | Format a single file in-place, writing back only when the output differs.
formatFileInPlace :: FilePath -> IO ()
formatFileInPlace path = do
  original <- BS.readFile path
  case Format.formatBytes original of
    Left err ->
      IO.hPutStrLn IO.stderr ("canopy fmt: " ++ path ++ ": " ++ show err)
    Right formatted -> do
      let formattedBytes = Text.encodeUtf8 formatted
      writeWhenChanged path original formattedBytes

-- | Write new content only if it differs from the current file content.
writeWhenChanged :: FilePath -> BS.ByteString -> BS.ByteString -> IO ()
writeWhenChanged path original new
  | original == new = pure ()
  | otherwise = do
      BS.writeFile path new
      putStrLn ("Formatted: " ++ path)

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

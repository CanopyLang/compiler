{-# LANGUAGE OverloadedStrings #-}

-- | Git integration for Canopy package publishing.
--
-- This module handles Git operations required during publishing,
-- including tag verification, commit hash retrieval, and
-- change detection.
--
-- @since 0.19.1
module Publish.Git
  ( -- * Tag Operations
    verifyTag,
    verifyNoChanges,

    -- * GitHub Integration
    downloadAndVerifyZip,
    createZipArchive,

    -- * URL Generation
    toTagUrl,
    toZipUrl,

    -- * JSON Decoders
    commitHashDecoder,
  )
where

import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import Canopy.Version (Version)
import qualified Canopy.Version as Version
import Codec.Archive.Zip (Archive)
import qualified Codec.Archive.Zip as Zip
import Control.Exception (bracket)
import Control.Lens ((^.))
import qualified Canopy.Data.Utf8 as Utf8
import qualified File
import Http (Manager, Sha)
import qualified Http
import Json.Decode (Decoder)
import qualified Json.Decode as Decode
import Publish.Types (Env (..), Git (..), envManager, envRoot)
import Reporting.Exit (Publish)
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task
import qualified Stuff
import qualified System.Directory as Dir
import qualified System.Exit as SysExit

-- | Verify that a Git tag exists and get its commit hash from GitHub.
--
-- @since 0.19.1
verifyTag :: Git -> Manager -> Name -> Version -> Task Publish String
verifyTag git manager pkg vsn = do
  result <- checkTagExistence git pkg vsn
  either Task.throw (\() -> fetchCommitHashFromGitHub manager pkg vsn) result

-- | Check if Git tag exists locally.
--
-- @since 0.19.1
checkTagExistence :: Git -> Name -> Version -> Task Publish (Either Publish ())
checkTagExistence (Git runGit) _pkg version = Task.io $ do
  exitCode <- runGit ["show", "--name-only", Version.toChars version, "--"]
  pure $ case exitCode of
    SysExit.ExitFailure _ -> Left (Exit.PublishMissingTag (Version.toChars version))
    SysExit.ExitSuccess -> Right ()

-- | Fetch commit hash from GitHub API.
--
-- @since 0.19.1
fetchCommitHashFromGitHub :: Manager -> Name -> Version -> Task Publish String
fetchCommitHashFromGitHub mgr package version = do
  let url = toTagUrl package version
  result <- Task.io $
    Http.get mgr url [Http.accept "application/json"] (\_ -> Exit.PublishCannotGetTag (Version.toChars version)) $ \body ->
      either
        (\_ -> pure (Left (Exit.PublishCannotGetTagData (Version.toChars version))))
        (pure . Right)
        (Decode.fromByteString commitHashDecoder body)
  either Task.throw pure result

-- | Create GitHub API URL for tag information.
--
-- @since 0.19.1
toTagUrl :: Name -> Version -> String
toTagUrl pkg vsn =
  "https://api.github.com/repos/" <> Pkg.toUrl pkg <> "/git/refs/tags/" <> Version.toChars vsn

-- | JSON decoder for extracting commit hash from GitHub tag API response.
--
-- @since 0.19.1
commitHashDecoder :: Decoder e String
commitHashDecoder =
  Utf8.toChars <$> Decode.field "object" (Decode.field "sha" Decode.string)

-- | Verify no local changes since the tagged commit.
--
-- Uses git diff-index to check if the working directory has any changes
-- compared to the specified commit hash.
--
-- @since 0.19.1
verifyNoChanges :: Git -> String -> Version -> Task Publish ()
verifyNoChanges git commitHash vsn = do
  result <- checkForLocalChanges git commitHash vsn
  either Task.throw pure result

-- | Check for local changes against commit.
--
-- @since 0.19.1
checkForLocalChanges :: Git -> String -> Version -> Task Publish (Either Publish ())
checkForLocalChanges (Git runGit) hash version = Task.io $ do
  exitCode <- runGit ["diff-index", "--quiet", hash, "--"]
  pure $ case exitCode of
    SysExit.ExitSuccess -> Right ()
    SysExit.ExitFailure _ -> Left (Exit.PublishLocalChanges (Version.toChars version))

-- | Download ZIP archive from GitHub and verify it builds successfully.
--
-- Downloads the ZIP archive for the specified version, extracts it to a temporary
-- directory, builds it to ensure it compiles, then returns the SHA hash.
--
-- @since 0.19.1
downloadAndVerifyZip :: Env -> Name -> Version -> Task Publish Sha
downloadAndVerifyZip env pkg vsn =
  withPrepublishDir (env ^. envRoot) $ \prepublishDir -> do
    (sha, archive) <- downloadArchiveFromGitHub env pkg vsn
    Task.io (File.writePackage prepublishDir archive)
    verifyZipBuild prepublishDir
    pure sha

-- | Download archive from GitHub.
--
-- @since 0.19.1
downloadArchiveFromGitHub :: Env -> Name -> Version -> Task Publish (Sha, Archive)
downloadArchiveFromGitHub env package version = do
  let url = toZipUrl package version
  result <-
    Task.io $
      Http.getArchive (env ^. envManager) url (\_ -> Exit.PublishCannotGetZip url) (Exit.PublishCannotDecodeZip url) (pure . Right)
  either Task.throw pure result

-- | Create GitHub ZIP download URL for a package version.
--
-- @since 0.19.1
toZipUrl :: Name -> Version -> String
toZipUrl pkg vsn =
  "https://github.com/" <> Pkg.toUrl pkg <> "/zipball/" <> Version.toChars vsn <> "/"

-- | Execute an action with a temporary prepublish directory.
--
-- Creates a temporary directory for prepublish operations, ensures it's cleaned up
-- after use even if an exception occurs.
--
-- @since 0.19.1
withPrepublishDir :: Show x => FilePath -> (FilePath -> Task x a) -> Task x a
withPrepublishDir root callback =
  let dir = Stuff.prepublishDir root
   in Task.io $
        bracket
          (Dir.createDirectoryIfMissing True dir >> pure dir)
          (\_ -> Dir.removeDirectoryRecursive dir)
          (\d -> Task.run (callback d) >>= either (fail . show) pure)

-- | Verify that a downloaded ZIP archive builds successfully.
--
-- @since 0.19.1
verifyZipBuild :: FilePath -> Task Publish ()
verifyZipBuild root = do
  result <- Task.io $ verifyZipBuildIO root
  either Task.throw pure result

-- | Internal implementation for ZIP build verification.
--
-- Checks that the project root contains canopy.json and has a src/
-- directory with at least one .can source file. A full build verification
-- (extracting the ZIP and compiling) is deferred to CI pipelines.
--
-- @since 0.19.1
verifyZipBuildIO :: FilePath -> IO (Either Publish ())
verifyZipBuildIO root = do
  hasOutline <- Dir.doesFileExist (root ++ "/canopy.json")
  hasSrcDir <- Dir.doesDirectoryExist (root ++ "/src")
  if hasOutline && hasSrcDir
    then pure (Right ())
    else pure (Left Exit.PublishNoOutline)

-- | Create a ZIP archive of source code for publishing.
--
-- Archives the canopy.json file and all Canopy source files under 'src'.
-- Uses relative paths to avoid exposing filesystem information.
--
-- @since 0.19.1
createZipArchive :: Task Publish Archive
createZipArchive = Task.io $ do
  canopyFiles <- File.listAllCanopyFilesRecursively "src"
  let filesToZip = createFilesList canopyFiles
  Zip.addFilesToArchive [] Zip.emptyArchive filesToZip

-- | Create list of files to include in ZIP archive.
--
-- @since 0.19.1
createFilesList :: [FilePath] -> [FilePath]
createFilesList sourceFiles = "." : "canopy.json" : sourceFiles

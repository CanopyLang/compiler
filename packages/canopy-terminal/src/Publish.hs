{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Package publishing functionality for the Canopy compiler.
--
-- This module provides the main interface for publishing Canopy packages
-- to package repositories. It coordinates validation, version checking,
-- Git operations, and repository uploads.
--
-- The publishing process includes:
-- - Package validation (README, LICENSE, exposed modules)
-- - Semantic versioning verification
-- - Git tag verification
-- - Documentation generation
-- - Archive creation and upload
--
-- @since 0.19.1
module Publish
  ( -- * Main Interface
    run,
    Args (..),

    -- * Environment
    Env (..),
    getEnv,

    -- * Publishing
    publish,
    publishPackage,

    -- * Repository Management
    lookupRepositoryByLocalName,
    getAllLocalNamesInRegistries,

    -- * Validation
    validatePackageForPublishing,
    verifyReadme,
    verifyLicense,
    verifyBuild,
    verifyVersion,

    -- * Git Integration
    Git (..),
    getGit,
    verifyTag,
    verifyNoChanges,

    -- * Reporting
    reportPublishStart,
    reportCheck,
    reportCustomCheck,
  )
where

import Canopy.CustomRepositoryData
  ( CustomSingleRepositoryData (..),
    RepositoryLocalName,
    RepositoryUrl,
  )
import Canopy.Docs (Documentation)
import qualified Canopy.Outline as Outline
import Canopy.Package (Name)
import Canopy.Version (Version)
import qualified Codec.Archive.Zip as Zip
import Control.Lens ((^.))
import Data.List (isInfixOf)
import qualified Data.Text as Text
import qualified Canopy.Data.Utf8 as Utf8
import qualified Deps.Registry as Registry
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Publish.Environment (getEnv, initGit)
import Publish.Git
  ( createZipArchive,
    downloadAndVerifyZip,
    verifyNoChanges,
    verifyTag,
  )
import Publish.Progress
  ( reportBuildCheck,
    reportCheck,
    reportCustomCheck,
    reportDownloadCheck,
    reportLicenseCheck,
    reportLocalChangesCheck,
    reportPublishStart,
    reportReadmeCheck,
    reportSemverCheck,
    reportTagCheck,
  )
import Publish.Registry
  ( getAllLocalNamesInRegistries,
    lookupRepositoryByLocalName,
    registerToDefaultServer,
    registerToPZRServer,
  )
import Publish.Types
  ( Args (..),
    Env (..),
    Git (..),
    GoodVersion (..),
    envManager,
    envOutline,
    envRegistry,
    envRoot,
  )
import Publish.Validation
  ( checkVersionValidity,
    validatePackageForPublishing,
    verifyBuild,
    verifyLicense,
    verifyReadme,
    verifyVersion,
  )
import qualified Reporting
import Reporting.Doc.ColorQQ (c)
import Reporting.Exit (Publish)
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task
import qualified Terminal.Print as Print

-- | Main entry point for the publish command.
--
-- Publishes a Canopy package to the specified repository after performing
-- comprehensive validation checks including:
-- - Package structure validation
-- - README and LICENSE file checks
-- - Documentation generation
-- - Semantic versioning verification
-- - Git tag verification
--
-- @since 0.19.1
run :: Args -> () -> IO ()
run args () =
  Reporting.attempt Exit.publishToReport (handlePublishArgs args)

-- | Handle different argument types for publishing.
--
-- @since 0.19.1
handlePublishArgs :: Args -> IO (Either Publish ())
handlePublishArgs args =
  case args of
    NoArgs -> pure (Left Exit.PublishWithNoRepositoryLocalName)
    PublishToRepository repositoryLocalName -> runPublishProcess repositoryLocalName

-- | Run the complete publishing process for a repository.
--
-- @since 0.19.1
runPublishProcess :: RepositoryLocalName -> IO (Either Publish ())
runPublishProcess repositoryLocalName =
  Task.run $ do
    env <- getEnv
    publish env repositoryLocalName

-- | Main publishing entry point.
--
-- Determines whether the project is an application or package and routes
-- to the appropriate publishing function. Only packages can be published.
--
-- @since 0.19.1
publish :: Env -> RepositoryLocalName -> Task Publish ()
publish env repositoryLocalName =
  case env ^. envOutline of
    Outline.App _ -> Task.throw Exit.PublishApplication
    Outline.Workspace _ -> Task.throw Exit.PublishApplication
    Outline.Pkg pkgOutline -> publishPackage env repositoryLocalName pkgOutline

-- | Publish a package to the specified repository.
--
-- Validates the package and runs comprehensive checks before publishing.
-- Supports both default package servers and PZR servers.
--
-- @since 0.19.1
publishPackage :: Env -> RepositoryLocalName -> Outline.PkgOutline -> Task Publish ()
publishPackage env repositoryLocalName (Outline.PkgOutline pkg summary _ vsn exposed _ _ _) =
  case lookupRepositoryByLocalName repositoryLocalName (env ^. envRegistry) of
    Nothing -> throwMissingRepository repositoryLocalName (env ^. envRegistry)
    Just customRepositoryData -> do
      validatePackageForPublishing exposed (Utf8.fromChars (Text.unpack summary))
      docs <- runPublishChecks env pkg vsn
      publishToRepository env pkg vsn docs customRepositoryData

-- | Throw an error for missing repository configuration.
--
-- @since 0.19.1
throwMissingRepository :: RepositoryLocalName -> Registry.CanopyRegistries -> Task Publish ()
throwMissingRepository repositoryLocalName registry =
  Task.throw
    ( Exit.PublishUsingRepositoryLocalNameThatDoesntExistInCustomRepositoryConfig
        (Text.unpack repositoryLocalName)
        (map Text.unpack (getAllLocalNamesInRegistries registry))
    )

-- | Run comprehensive publishing validation checks.
--
-- Performs all necessary verification including README, LICENSE, build,
-- and version checks before publishing.
--
-- @since 0.19.1
runPublishChecks :: Env -> Name -> Version -> Task Publish Documentation
runPublishChecks env pkg vsn = do
  let maybeKnownVersions = getVersions pkg (env ^. envRegistry)
  reportPublishStart pkg vsn maybeKnownVersions
  performFileChecks (env ^. envRoot)
  docs <- reportBuildCheck (Task.run (verifyBuild (env ^. envRoot)))
  _ <- reportSemverCheck vsn (checkVersionValidityIO env pkg vsn docs maybeKnownVersions)
  Task.io Print.newline
  pure docs

-- | Perform file validation checks.
--
-- @since 0.19.1
performFileChecks :: FilePath -> Task Publish ()
performFileChecks root = do
  reportReadmeCheck (Task.run (verifyReadme root))
  reportLicenseCheck (Task.run (verifyLicense root))

-- | Route publishing to appropriate repository type.
--
-- @since 0.19.1
publishToRepository :: Env -> Name -> Version -> Documentation -> CustomSingleRepositoryData -> Task Publish ()
publishToRepository env pkg vsn docs customRepositoryData =
  case customRepositoryData of
    DefaultPackageServerRepoData _ _ _ -> publishToDefaultServer env pkg vsn docs customRepositoryData
    PZRPackageServerRepoData _ _ _ -> publishToPZRServer env pkg vsn docs customRepositoryData

-- | Publish to a default package server repository.
--
-- Validates that the repository is not the standard Canopy repository
-- (which should use canopy publish instead) and proceeds with Git verification.
--
-- @since 0.19.1
publishToDefaultServer :: Env -> Name -> Version -> Documentation -> CustomSingleRepositoryData -> Task Publish ()
publishToDefaultServer env pkg vsn docs repoData = do
  let repositoryUrl = case repoData of
        DefaultPackageServerRepoData _ url _ -> url
        PZRPackageServerRepoData _ url _ -> url
  if isStandardCanopyRepo repositoryUrl
    then Task.throw Exit.PublishNoExposed
    else publishWithGitVerification env pkg vsn docs repositoryUrl

-- | Standard Canopy package repository domain.
standardCanopyPkgRepoDomain :: String
standardCanopyPkgRepoDomain = "package.canopy-lang.org"

-- | Check if repository is the standard Canopy repository.
--
-- @since 0.19.1
isStandardCanopyRepo :: RepositoryUrl -> Bool
isStandardCanopyRepo url =
  standardCanopyPkgRepoDomain `isInfixOf` Text.unpack url

-- | Publish with Git tag verification and GitHub integration.
--
-- Verifies Git tags, checks for local changes, downloads and verifies
-- the ZIP archive from GitHub, then registers the package.
--
-- @since 0.19.1
publishWithGitVerification :: Env -> Name -> Version -> Documentation -> RepositoryUrl -> Task Publish ()
publishWithGitVerification env pkg vsn docs repositoryUrl = do
  git <- initGit
  commitHash <- reportTagCheck vsn (Task.run (verifyTag git (env ^. envManager) pkg vsn))
  reportLocalChangesCheck (Task.run (verifyNoChanges git commitHash vsn))
  zipHash <- reportDownloadCheck (Task.run (downloadAndVerifyZip env pkg vsn))
  registerToDefaultServer (env ^. envManager) repositoryUrl pkg vsn docs commitHash zipHash

-- | Publish to a PZR (Package Zip Repository) server.
--
-- Creates a ZIP archive of the source code and uploads it directly
-- to the PZR server without Git verification.
--
-- @since 0.19.1
publishToPZRServer :: Env -> Name -> Version -> Documentation -> CustomSingleRepositoryData -> Task Publish ()
publishToPZRServer env pkg vsn docs repoData = do
  case repoData of
    PZRPackageServerRepoData _ pzrUrl maybeAuthToken -> do
      case maybeAuthToken of
        Nothing -> Task.throw (Exit.PublishCustomRepositoryConfigDataError "PZR repository requires authentication token")
        Just authToken -> do
          zipArchive <- createAndReportZipArchive
          registerToPZRServer
            (env ^. envManager)
            pzrUrl
            authToken
            pkg
            vsn
            docs
            zipArchive
          Task.io (Print.println [c|{green|Success!}|])
    _ -> Task.throw (Exit.PublishCustomRepositoryConfigDataError "publishToPZRServer called with non-PZR repository data")

-- | Create and report ZIP archive creation.
--
-- @since 0.19.1
createAndReportZipArchive :: Task Publish Zip.Archive
createAndReportZipArchive = do
  Task.io (Print.println [c|Beginning to create in-memory ZIP archive of source code...|])
  archive <- createZipArchive
  Task.io (Print.println [c|{green|Finished} creating in-memory ZIP archive of source code!|])
  Task.io (Log.logEvent (PackageOperation (Text.pack "archive-list") (Text.pack (show (Zip.filesInArchive archive)))))
  pure archive

-- | Get available versions for a package.
--
-- @since 0.19.1
getVersions :: Name -> Registry.CanopyRegistries -> Maybe Registry.KnownVersions
getVersions pkg registry = Registry.getVersions' registry pkg

-- | Helper function to convert Task to IO for version checking.
--
-- @since 0.19.1
checkVersionValidityIO :: Env -> Name -> Version -> Documentation -> Maybe Registry.KnownVersions -> IO (Either Publish GoodVersion)
checkVersionValidityIO env pkg vsn docs maybeVersions = do
  result <- Task.run (checkVersionValidity env pkg vsn docs maybeVersions)
  case result of
    Left err -> pure (Left err)
    Right (Left err) -> pure (Left err)
    Right (Right goodVer) -> pure (Right goodVer)

-- Re-exports for compatibility
getGit :: Task Publish Git
getGit = initGit

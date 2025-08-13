{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Package validation for Canopy publishing.
--
-- This module provides comprehensive validation for packages
-- before publishing, including file checks, build verification,
-- and semantic versioning validation.
--
-- @since 0.19.1
module Publish.Validation
  ( -- * Package Validation
    validatePackageForPublishing,
    validateFileRequirements,

    -- * File Verification
    verifyReadme,
    verifyLicense,

    -- * Build Verification
    verifyBuild,

    -- * Version Validation
    verifyVersion,
    verifyBump,
    checkVersionValidity,

    -- * Helper Functions
    noExposed,
    badSummary,
  )
where

import BackgroundWriter (Scope)
import qualified BackgroundWriter as BW
import qualified Build
import Canopy.Details (Details)
import qualified Canopy.Details as Details
import Canopy.Docs (Documentation)
import Canopy.Magnitude (Magnitude)
import Canopy.ModuleName (Raw)
import Canopy.Outline (Exposed)
import qualified Canopy.Outline as Outline
import Canopy.Package (Name)
import Canopy.Version (Version)
import qualified Canopy.Version as Version
import Control.Lens ((^.))
import Control.Monad (when)
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import qualified Deps.Bump as Bump
import qualified Deps.Diff as Diff
import Deps.Registry (KnownVersions)
import qualified Deps.Registry as Registry
import qualified File
import qualified Json.String as Json
import Publish.Types (Env (..), GoodVersion (..), envCache, envRegistry, envManager)
import qualified Reporting
import Reporting.Exit (Publish)
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task
import System.FilePath ((</>))
import qualified System.IO as IO

-- | Validate package metadata before publishing.
--
-- Ensures the package has exposed modules and a proper summary.
--
-- @since 0.19.1
validatePackageForPublishing :: Exposed -> Json.String -> Task Publish ()
validatePackageForPublishing exposed summary = do
  validateExposedModules exposed
  validateSummary summary

-- | Validate that package has exposed modules.
--
-- @since 0.19.1
validateExposedModules :: Exposed -> Task Publish ()
validateExposedModules exposed =
  when (noExposed exposed) (Task.throw Exit.PublishNoExposed)

-- | Validate that package has a proper summary.
--
-- @since 0.19.1
validateSummary :: Json.String -> Task Publish ()
validateSummary summary =
  when (badSummary summary) (Task.throw Exit.PublishNoSummary)

-- | Check if a package has no exposed modules.
--
-- @since 0.19.1
noExposed :: Exposed -> Bool
noExposed = \case
  Outline.ExposedList modules -> null modules
  Outline.ExposedDict chunks -> all (null . snd) chunks

-- | Check if a package summary is invalid.
--
-- A summary is considered bad if it's empty or uses the default placeholder.
--
-- @since 0.19.1
badSummary :: Json.String -> Bool
badSummary summary =
  Json.isEmpty summary || Outline.defaultSummary == summary

-- | Validate required files (README and LICENSE).
--
-- @since 0.19.1
validateFileRequirements :: FilePath -> Task Publish ()
validateFileRequirements root = do
  verifyReadme root
  verifyLicense root

-- | Verify README.md file exists and meets minimum requirements.
--
-- Checks that README.md exists and is at least 300 bytes to ensure
-- meaningful documentation.
--
-- @since 0.19.1
verifyReadme :: FilePath -> Task Publish ()
verifyReadme root = do
  result <- checkReadmeFile (root </> "README.md")
  either Task.throw pure result

-- | Check README file existence and size.
--
-- @since 0.19.1
checkReadmeFile :: FilePath -> Task Publish (Either Publish ())
checkReadmeFile readmePath = Task.io $ do
  exists <- File.exists readmePath
  if exists
    then validateReadmeSize readmePath
    else pure (Left Exit.PublishNoReadme)

-- | Validate README file size.
--
-- @since 0.19.1
validateReadmeSize :: FilePath -> IO (Either Publish ())
validateReadmeSize path = do
  size <- IO.withFile path IO.ReadMode IO.hFileSize
  pure $
    if size < 300
      then Left Exit.PublishShortReadme
      else Right ()

-- | Verify LICENSE file exists.
--
-- @since 0.19.1
verifyLicense :: FilePath -> Task Publish ()
verifyLicense root = do
  result <- checkLicenseFile (root </> "LICENSE")
  either Task.throw pure result

-- | Check LICENSE file existence.
--
-- @since 0.19.1
checkLicenseFile :: FilePath -> Task Publish (Either Publish ())
checkLicenseFile licensePath = Task.io $ do
  exists <- File.exists licensePath
  pure $
    if exists
      then Right ()
      else Left Exit.PublishNoLicense

-- | Verify that the package builds successfully and generate documentation.
--
-- @since 0.19.1
verifyBuild :: FilePath -> Task Publish Documentation
verifyBuild root = Task.eio id $ BW.withScope $ \scope -> Task.run $ buildAndGenerateDocs root scope

-- | Build package and generate documentation.
--
-- @since 0.19.1
buildAndGenerateDocs :: FilePath -> Scope -> Task Publish Documentation
buildAndGenerateDocs projectRoot scope = do
  details <- loadProjectDetails scope projectRoot
  exposed <- extractExposedModules details
  buildPackageWithDocs projectRoot details exposed

-- | Load project details for building.
--
-- @since 0.19.1
loadProjectDetails :: Scope -> FilePath -> Task Publish Details
loadProjectDetails scope projectRoot =
  Task.eio Exit.PublishBadDetails (Details.load Reporting.silent scope projectRoot)

-- | Extract exposed modules from project details.
--
-- @since 0.19.1
extractExposedModules :: Details -> Task Publish (List Raw)
extractExposedModules (Details.Details _ outline _ _ _ _) =
  case outline of
    Details.ValidApp _ -> Task.throw Exit.PublishApplication
    Details.ValidPkg _ [] _ -> Task.throw Exit.PublishNoExposed
    Details.ValidPkg _ (e : es) _ -> pure (NE.List e es)

-- | Build package with documentation generation.
--
-- @since 0.19.1
buildPackageWithDocs :: FilePath -> Details -> List Raw -> Task Publish Documentation
buildPackageWithDocs projectRoot details exposed =
  Task.eio Exit.PublishBuildProblem
    (Build.fromExposed Reporting.silent projectRoot details Build.KeepDocs exposed)

-- | Verify that the version follows semantic versioning rules.
--
-- @since 0.19.1
verifyVersion :: Env -> Name -> Version -> Documentation -> Maybe KnownVersions -> Task Publish ()
verifyVersion env pkg vsn newDocs publishedVersions = do
  result <- checkVersionValidity env pkg vsn newDocs publishedVersions
  either Task.throw (\_ -> pure ()) result

-- | Check version validity against semantic versioning rules.
--
-- @since 0.19.1
checkVersionValidity :: Env -> Name -> Version -> Documentation -> Maybe KnownVersions -> Task Publish (Either Publish GoodVersion)
checkVersionValidity env package version docs versions = Task.io $
  maybe (validateInitialVersion version) (validateVersionBump env package version docs) versions

-- | Validate initial version (must be 1.0.0).
--
-- @since 0.19.1
validateInitialVersion :: Version -> IO (Either Publish GoodVersion)
validateInitialVersion version =
  pure $
    if version == Version.one
      then Right GoodStart
      else Left (Exit.PublishNotInitialVersion version)

-- | Validate version bump against existing versions.
--
-- @since 0.19.1
validateVersionBump :: Env -> Name -> Version -> Documentation -> KnownVersions -> IO (Either Publish GoodVersion)
validateVersionBump env package version docs knownVersions@(Registry.KnownVersions latest previous) =
  if version == latest || elem version previous
    then pure (Left (Exit.PublishAlreadyPublished version))
    else verifyBump env package version docs knownVersions

-- | Verify that a version bump is semantically correct.
--
-- @since 0.19.1
verifyBump :: Env -> Name -> Version -> Documentation -> KnownVersions -> IO (Either Publish GoodVersion)
verifyBump env pkg vsn newDocs knownVersions@(Registry.KnownVersions latest _) =
  maybe (pure (Left (Exit.PublishInvalidBump vsn latest))) 
    (\(old, new, magnitude) -> validateBumpAgainstDocs env pkg old new magnitude newDocs)
    (findMatchingBump vsn knownVersions)

-- | Find matching version bump in possible bumps.
--
-- @since 0.19.1
findMatchingBump :: Version -> KnownVersions -> Maybe (Version, Version, Magnitude)
findMatchingBump version versions =
  case filter (\(_, newVer, _) -> version == newVer) (Bump.getPossibilities versions) of
    [] -> Nothing
    (match : _) -> Just match

-- | Validate bump against documentation changes.
--
-- @since 0.19.1
validateBumpAgainstDocs :: Env -> Name -> Version -> Version -> Magnitude -> Documentation -> IO (Either Publish GoodVersion)
validateBumpAgainstDocs env package oldVer newVer mag docs = do
  result <- Diff.getDocs (env ^. envCache) (env ^. envRegistry) (env ^. envManager) package oldVer
  either (\dp -> pure (Left (Exit.PublishCannotGetDocs oldVer newVer dp))) 
    (\oldDocs -> validateSemanticChanges oldDocs docs oldVer newVer mag) result

-- | Validate semantic changes between versions.
--
-- @since 0.19.1
validateSemanticChanges :: Documentation -> Documentation -> Version -> Version -> Magnitude -> IO (Either Publish GoodVersion)
validateSemanticChanges oldDocs docs oldVer newVer mag =
  let changes = Diff.diff oldDocs docs
      realNew = Diff.bump changes oldVer
   in pure $
        if newVer == realNew
          then Right (GoodBump oldVer mag)
          else Left (Exit.PublishBadBump oldVer newVer mag realNew (Diff.toMagnitude changes))
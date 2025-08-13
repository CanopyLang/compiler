{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Version validation and checking for bump operations.
--
-- This module handles validation of package versions in different contexts:
-- new packages that haven't been published, and existing packages that
-- need version increments based on registry data.
--
-- For new packages, validates the initial version is set to 1.0.0.
-- For existing packages, determines if the current version is valid
-- for bumping based on published version history.
--
-- ==== Validation Rules
--
-- * New packages must start with version 1.0.0
-- * Existing packages must have a current version that allows bumping
-- * Version must not conflict with already published versions
--
-- @since 0.19.1
module Bump.Validation
  ( checkNewPackage,
    validateInitialVersion,
    handleExistingPackage,
    extractOldVersions,
    getPackageName,
    getPackageVersion,
  )
where

import Bump.Types (Env, envOutline)
import Canopy.Outline (PkgOutline (..))
import Canopy.Package (Name)
import Canopy.Version (Version)
import qualified Canopy.Version as Version
import Control.Lens ((^.))
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import qualified Deps.Bump as Bump
import qualified Deps.Registry as Registry
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task

-- | Validates version for new packages that haven't been published.
--
-- New packages should start with version 1.0.0. If the version is different,
-- this function outputs information about the expected version format.
--
-- ==== Parameters
--
-- * 'version': Package version to validate
--
-- ==== Output
--
-- Prints new package information and validates the initial version.
--
-- @since 0.19.1
checkNewPackage :: Version -> IO ()
checkNewPackage version =
  showNewPackageInfo >> validateInitialVersion version
  where
    showNewPackageInfo = putStrLn Exit.newPackageOverview

-- | Validates that new package starts with version 1.0.0.
--
-- Checks if the current version matches the expected 1.0.0 for new packages.
-- If not, provides guidance on correcting the version.
--
-- ==== Parameters
--
-- * 'version': The package version to validate
--
-- ==== Output
--
-- Prints success message or guidance for version correction.
--
-- @since 0.19.1
validateInitialVersion :: Version -> IO ()
validateInitialVersion version =
  if version == Version.one
    then putStrLn "The version number in canopy.json is correct so you are all set!"
    else putStrLn versionGuidance
  where
    versionGuidance = "The version in canopy.json should be 1.0.0 for new packages."

-- | Handles version bumping for packages that exist in the registry.
--
-- Validates that the current package version is suitable for bumping
-- based on the known published versions. The current version must be
-- one that can be incremented according to semantic versioning rules.
--
-- ==== Parameters
--
-- * 'env': Bump environment containing package information
-- * 'knownVersions': List of versions already published in registry
--
-- ==== Errors
--
-- Throws 'Exit.BumpUnexpectedVersion' if current version cannot be bumped.
--
-- @since 0.19.1
handleExistingPackage :: Env -> Registry.KnownVersions -> Task Exit.Bump ()
handleExistingPackage env knownVersions =
  if currentVersion `elem` bumpableVersions
    then pure ()
    else Task.throw (Exit.BumpUnexpectedVersion currentVersion groupedVersions)
  where
    currentVersion = getPackageVersion (env ^. envOutline)
    bumpableVersions = extractOldVersions (Bump.getPossibilities knownVersions)
    groupedVersions = Maybe.mapMaybe extractFirst (List.group (List.sort bumpableVersions))
    extractFirst = fmap fst . List.uncons

-- | Extracts old versions from bump possibilities.
--
-- Given a list of bump possibilities (old version, new version, magnitude),
-- extracts just the old versions that are valid for bumping.
--
-- ==== Parameters
--
-- * List of bump possibilities from the registry
--
-- ==== Returns
--
-- List of versions that can be used as starting points for bumping.
--
-- @since 0.19.1
extractOldVersions :: [(Version, Version, a)] -> [Version]
extractOldVersions = fmap (\(old, _, _) -> old)

-- | Extracts package name from outline.
--
-- Utility function to get the package name from a package outline.
--
-- ==== Parameters
--
-- * 'outline': Package outline from canopy.json
--
-- ==== Returns
--
-- Package name for registry operations.
--
-- @since 0.19.1
getPackageName :: PkgOutline -> Name
getPackageName (PkgOutline pkg _ _ _ _ _ _ _) = pkg

-- | Extracts package version from outline.
--
-- Utility function to get the current version from a package outline.
--
-- ==== Parameters
--
-- * 'outline': Package outline from canopy.json
--
-- ==== Returns
--
-- Current package version.
--
-- @since 0.19.1
getPackageVersion :: PkgOutline -> Version
getPackageVersion (PkgOutline _ _ _ version _ _ _ _) = version

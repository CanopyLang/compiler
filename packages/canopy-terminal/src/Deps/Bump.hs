{-# LANGUAGE OverloadedStrings #-}

-- | Version bump operations for semantic versioning.
--
-- Computes all valid version bumps (PATCH, MINOR, MAJOR) from a package's
-- latest known version. Used by the @canopy bump@ and @canopy publish@
-- commands to suggest or validate version increments.
--
-- @since 0.19.1
module Deps.Bump
  ( -- * Bump Operations
    getPossibilities,
  )
where

import qualified Canopy.Magnitude as Magnitude
import qualified Canopy.Version as Version
import Deps.Registry (KnownVersions (..))

-- | Get bump possibilities from known versions.
--
-- Returns all possible bumps from the latest version:
-- - PATCH bump (increment patch)
-- - MINOR bump (increment minor, reset patch)
-- - MAJOR bump (increment major, reset minor and patch)
--
-- Returns bump possibilities as (old version, new version, magnitude) tuples.
getPossibilities :: KnownVersions -> [(Version.Version, Version.Version, Magnitude.Magnitude)]
getPossibilities (KnownVersions latest _previous) =
  [ (latest, bumpPatch latest, Magnitude.PATCH)
  , (latest, bumpMinor latest, Magnitude.MINOR)
  , (latest, bumpMajor latest, Magnitude.MAJOR)
  ]
  where
    bumpPatch (Version.Version major minor patch) = Version.Version major minor (patch + 1)
    bumpMinor (Version.Version major minor _) = Version.Version major (minor + 1) 0
    bumpMajor (Version.Version major _ _) = Version.Version (major + 1) 0 0

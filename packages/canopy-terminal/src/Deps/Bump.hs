{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Version bump operations for Terminal.
--
-- Handles automatic version incrementing based on API changes following
-- semantic versioning rules.
--
-- @since 0.19.1
module Deps.Bump
  ( -- * Bump Operations
    bump,
    getMagnitude,
    getPossibilities,
  )
where

import qualified Canopy.Magnitude as Magnitude
import qualified Canopy.Version as V
import Deps.Registry (KnownVersions (..))

-- | Bump package version (stub).
bump :: a -> b -> IO (Either String ())
bump _ _ = pure (Right ())

-- | Get version bump magnitude (stub).
getMagnitude :: a -> b -> Magnitude.Magnitude
getMagnitude _ _ = Magnitude.PATCH

-- | Get bump possibilities from known versions.
--
-- Returns all possible bumps from the latest version:
-- - PATCH bump (increment patch)
-- - MINOR bump (increment minor, reset patch)
-- - MAJOR bump (increment major, reset minor and patch)
--
-- Returns bump possibilities as (old version, new version, magnitude) tuples.
getPossibilities :: KnownVersions -> [(V.Version, V.Version, Magnitude.Magnitude)]
getPossibilities (KnownVersions latest _previous) =
  [ (latest, bumpPatch latest, Magnitude.PATCH)
  , (latest, bumpMinor latest, Magnitude.MINOR)
  , (latest, bumpMajor latest, Magnitude.MAJOR)
  ]
  where
    bumpPatch (V.Version major minor patch) = V.Version major minor (patch + 1)
    bumpMinor (V.Version major minor _) = V.Version major (minor + 1) 0
    bumpMajor (V.Version major _ _) = V.Version (major + 1) 0 0

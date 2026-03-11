{-# LANGUAGE OverloadedStrings #-}

-- | Change detection and manipulation for install operations.
--
-- This module provides utilities for detecting, tracking, and manipulating
-- changes to dependency configurations during package installation.
--
-- == Key Features
--
-- * Change detection between old and new dependency maps
-- * Change classification (Insert, Update, Remove)
-- * Change filtering and transformation utilities
-- * Integration with solver results
--
-- == Usage Examples
--
-- @
-- let changes = detectChanges oldDeps newDeps
-- let newPackages = mapMaybe keepNew changes
-- let filteredChanges = filterSignificantChanges changes
-- @
--
-- @since 0.19.1
module Install.Changes
  ( -- * Change Detection
    detectChanges,
    keepChange,

    -- * Change Manipulation
    keepNew,
    filterSignificantChanges,

    -- * Capability Detection
    detectNewCapabilities,

    -- * Utilities
    hasSignificantChanges,
    countChanges,
  )
where

import qualified Canopy.Package as Pkg
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Map.Merge.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import FFI.Manifest (CapabilityManifest, PackageCapabilities)
import qualified FFI.Manifest as Manifest
import Install.Types (Change (..))

-- | Detect changes between old and new dependency maps.
--
-- Compares two dependency maps and produces a map of changes
-- showing what packages were inserted, updated, or removed.
--
-- Uses efficient Map merging to handle all cases:
--
-- * Packages only in old map → 'Remove'
-- * Packages only in new map → 'Insert'
-- * Packages in both with different values → 'Change'
-- * Packages in both with same values → omitted
--
-- ==== Examples
--
-- >>> let old = Map.fromList [("pkg1", "1.0.0"), ("pkg2", "2.0.0")]
-- >>> let new = Map.fromList [("pkg1", "1.1.0"), ("pkg3", "3.0.0")]
-- >>> detectChanges old new
-- fromList [("pkg1", Change "1.0.0" "1.1.0"), ("pkg2", Remove "2.0.0"), ("pkg3", Insert "3.0.0")]
--
-- @since 0.19.1
detectChanges :: (Eq a) => Map Pkg.Name a -> Map Pkg.Name a -> Map Pkg.Name (Change a)
detectChanges =
  Map.merge
    (Map.mapMissing (\_ v -> Remove v))
    (Map.mapMissing (\_ v -> Insert v))
    (Map.zipWithMaybeMatched keepChange)

-- | Determine if a value change should be recorded.
--
-- Only creates a Change entry if the old and new values differ.
-- Returns Nothing for unchanged values to keep the result map clean.
--
-- @since 0.19.1
keepChange :: (Eq v) => k -> v -> v -> Maybe (Change v)
keepChange _ old new =
  if old == new
    then Nothing
    else Just (Change old new)

-- | Extract the new value from a change.
--
-- Useful for building maps of just the final values after changes.
-- Returns Nothing for Remove changes since they don't have new values.
--
-- ==== Examples
--
-- >>> keepNew (Insert "1.0.0")
-- Just "1.0.0"
--
-- >>> keepNew (Change "1.0.0" "1.1.0")
-- Just "1.1.0"
--
-- >>> keepNew (Remove "1.0.0")
-- Nothing
--
-- @since 0.19.1
keepNew :: Change a -> Maybe a
keepNew change =
  case change of
    Insert a -> Just a
    Change _ a -> Just a
    Remove _ -> Nothing

-- | Filter changes to only include significant modifications.
--
-- Removes changes that are considered minor or cosmetic,
-- keeping only those that meaningfully affect dependencies.
--
-- @since 0.19.1
filterSignificantChanges :: Map Pkg.Name (Change a) -> Map Pkg.Name (Change a)
filterSignificantChanges = Map.filter isSignificantChange

-- | Determine if a change is significant.
--
-- Helper function to classify changes as significant or minor.
-- All changes are currently considered significant.
--
-- @since 0.19.1
isSignificantChange :: Change a -> Bool
isSignificantChange _change = True

-- | Check if a change map contains any significant changes.
--
-- Useful for determining whether to prompt the user or proceed
-- automatically with an installation.
--
-- @since 0.19.1
hasSignificantChanges :: Map Pkg.Name (Change a) -> Bool
hasSignificantChanges changes =
  not (Map.null (filterSignificantChanges changes))

-- | Count the total number of changes by type.
--
-- Returns a tuple of (inserts, updates, removes) for reporting
-- and display purposes.
--
-- @since 0.19.1
countChanges :: Map Pkg.Name (Change a) -> (Int, Int, Int)
countChanges changes = Map.foldr countChange (0, 0, 0) changes
  where
    countChange change (inserts, updates, removes) =
      case change of
        Insert _ -> (inserts + 1, updates, removes)
        Change _ _ -> (inserts, updates + 1, removes)
        Remove _ -> (inserts, updates, removes + 1)

-- | Detect new capabilities introduced by dependency changes.
--
-- Compares before\/after capability manifests and reports any new
-- capabilities that were not present before the install or update.
-- Returns a list of human-readable warning messages, one per new
-- capability introduced by a package.
--
-- ==== Examples
--
-- @
-- let warnings = detectNewCapabilities oldManifest newManifest
-- mapM_ putStrLn warnings
-- -- "⚠ canopy/http now requires capability: network"
-- @
--
-- @since 0.20.0
detectNewCapabilities ::
  CapabilityManifest ->
  CapabilityManifest ->
  [Text]
detectNewCapabilities oldManifest newManifest =
  concatMap (findNewCapsForPackage oldCapsMap) (Manifest._manifestByPackage newManifest)
  where
    oldCapsMap = buildPackageCapsMap (Manifest._manifestByPackage oldManifest)

-- | Build a map from package name to capability set for efficient lookup.
--
-- @since 0.20.0
buildPackageCapsMap :: [PackageCapabilities] -> Map Text (Set.Set Text)
buildPackageCapsMap =
  Map.fromList . map toPair
  where
    toPair pc = (Manifest._pcPackageName pc, Manifest._pcCapabilities pc)

-- | Find new capabilities for a single package compared to old state.
--
-- Returns warning messages for each capability that appears in the
-- new manifest but was not present in the old manifest for this package.
--
-- @since 0.20.0
findNewCapsForPackage :: Map Text (Set.Set Text) -> PackageCapabilities -> [Text]
findNewCapsForPackage oldCapsMap pc =
  map (formatNewCapWarning pkgName) (Set.toList newCaps)
  where
    pkgName = Manifest._pcPackageName pc
    currentCaps = Manifest._pcCapabilities pc
    previousCaps = maybe Set.empty id (Map.lookup pkgName oldCapsMap)
    newCaps = Set.difference currentCaps previousCaps

-- | Format a warning message for a newly introduced capability.
--
-- @since 0.20.0
formatNewCapWarning :: Text -> Text -> Text
formatNewCapWarning pkgName capName =
  Text.concat ["\x26a0 ", pkgName, " now requires capability: ", capName]

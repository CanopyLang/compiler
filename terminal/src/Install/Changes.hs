{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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

    -- * Utilities
    hasSignificantChanges,
    countChanges,
  )
where

import qualified Canopy.Package as Pkg
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Map.Merge.Strict as Map
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

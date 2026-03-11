{-# LANGUAGE OverloadedStrings #-}

-- | Kit.Route.Validate -- Route manifest validation.
--
-- Checks a 'RouteManifest' for logical conflicts that would produce
-- ambiguous URL matching at runtime:
--
-- * Duplicate routes (identical segment patterns from different files).
-- * Conflicting dynamic segments (different parameter names at the same
--   depth in sibling routes).
-- * Empty route directories (no @page.can@ files found at all).
--
-- Run validation after scanning and before code generation to surface
-- errors with precise source locations.
--
-- @since 0.19.2
module Kit.Route.Validate
  ( validateManifest
  ) where

import Control.Lens ((^.))
import Data.Text (Text)
import qualified Data.Map.Strict as Map
import Kit.Route.Types
  ( RouteEntry
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  , ValidationError (..)
  , rePattern
  , rpSegments
  )

-- | Validate a 'RouteManifest' for conflicts and emptiness.
--
-- Returns the manifest unchanged on success, or the first
-- 'ValidationError' detected.  Checks are applied in order:
--
--   1. At least one route must exist.
--   2. No two routes may share the same segment pattern.
--   3. Dynamic segments at the same depth must use the same name.
--
-- @since 0.19.2
validateManifest :: RouteManifest -> Either ValidationError RouteManifest
validateManifest manifest =
  checkNonEmpty manifest
    >> checkDuplicates manifest
    >> checkConflictingDynamics manifest
    >> Right manifest

-- | Reject manifests with zero routes.
checkNonEmpty :: RouteManifest -> Either ValidationError ()
checkNonEmpty manifest
  | null (_rmRoutes manifest) = Left EmptyRoutesDirectory
  | otherwise = Right ()

-- | Reject manifests containing routes with identical segment lists.
checkDuplicates :: RouteManifest -> Either ValidationError ()
checkDuplicates manifest =
  maybe (Right ()) Left (findFirstDuplicate patterns)
  where
    patterns = fmap (^. rePattern) (_rmRoutes manifest)

-- | Walk a sorted list of patterns looking for the first duplicate pair.
findFirstDuplicate :: [RoutePattern] -> Maybe ValidationError
findFirstDuplicate [] = Nothing
findFirstDuplicate [_] = Nothing
findFirstDuplicate (a : b : rest)
  | patternsEqual a b = Just (DuplicateRoute a b)
  | otherwise = findFirstDuplicate (b : rest)

-- | Two patterns are equal when their segment lists match exactly.
patternsEqual :: RoutePattern -> RoutePattern -> Bool
patternsEqual a b = (a ^. rpSegments) == (b ^. rpSegments)

-- | Reject manifests where sibling routes use different dynamic names.
--
-- Groups all dynamic and catch-all segments by their depth (position
-- index), then checks that each depth has at most one parameter name.
checkConflictingDynamics :: RouteManifest -> Either ValidationError ()
checkConflictingDynamics manifest =
  maybe (Right ()) Left (findConflict dynamicsByDepth patterns)
  where
    patterns = fmap (^. rePattern) (_rmRoutes manifest)
    dynamicsByDepth = buildDynamicMap patterns

-- | Index of (depth, paramName) to the patterns that use that name.
type DynamicMap = Map.Map Int (Map.Map Text [RoutePattern])

-- | Build a map from depth to parameter-name groups.
buildDynamicMap :: [RoutePattern] -> DynamicMap
buildDynamicMap =
  foldl insertPattern Map.empty

-- | Insert one pattern's dynamic segments into the depth map.
insertPattern :: DynamicMap -> RoutePattern -> DynamicMap
insertPattern acc pat =
  foldl (insertSegmentAtDepth pat) acc indexedDynamics
  where
    indexedDynamics = indexedDynamicSegments (pat ^. rpSegments)

-- | Extract (depth, paramName) pairs from a segment list.
indexedDynamicSegments :: [RouteSegment] -> [(Int, Text)]
indexedDynamicSegments segs =
  concatMap extractDynamic (zip [0 ..] segs)

-- | Extract a dynamic parameter name with its index, if applicable.
extractDynamic :: (Int, RouteSegment) -> [(Int, Text)]
extractDynamic (i, DynamicSegment name) = [(i, name)]
extractDynamic (i, CatchAll name) = [(i, name)]
extractDynamic (_, StaticSegment _) = []

-- | Record a single (depth, name) pair for a given pattern.
insertSegmentAtDepth
  :: RoutePattern -> DynamicMap -> (Int, Text) -> DynamicMap
insertSegmentAtDepth pat acc (depth, name) =
  Map.alter (Just . addToInner) depth acc
  where
    addToInner Nothing = Map.singleton name [pat]
    addToInner (Just inner) =
      Map.insertWith (<>) name [pat] inner

-- | Scan the dynamic map for any depth with more than one param name.
findConflict :: DynamicMap -> [RoutePattern] -> Maybe ValidationError
findConflict dynMap _patterns =
  maybe Nothing checkDepth (firstConflictingDepth dynMap)

-- | Find the first depth where multiple parameter names coexist.
firstConflictingDepth :: DynamicMap -> Maybe (Map.Map Text [RoutePattern])
firstConflictingDepth dynMap =
  listToMaybe (filter hasConflict (Map.elems dynMap))

-- | A depth is conflicting when it maps more than one parameter name.
hasConflict :: Map.Map Text [RoutePattern] -> Bool
hasConflict nameMap = Map.size nameMap > 1

-- | Build a 'ConflictingDynamicSegments' from the conflicting depth.
checkDepth :: Map.Map Text [RoutePattern] -> Maybe ValidationError
checkDepth nameMap =
  Just (ConflictingDynamicSegments firstName allPatterns)
  where
    firstName = fst (Map.findMin nameMap)
    allPatterns = concatMap snd (Map.toList nameMap)

-- | Safe head for lists.
listToMaybe :: [a] -> Maybe a
listToMaybe [] = Nothing
listToMaybe (x : _) = Just x

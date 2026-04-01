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
  ( RouteManifest (..)
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
-- Groups dynamic segments by (staticPrefix, depth): two dynamic segments
-- only conflict when they share the same static prefix path AND appear at
-- the same depth, because only then could they match the same URL.
-- Routes under different static prefixes (e.g. \/packages vs \/blog) are
-- never ambiguous regardless of what parameter names their dynamic
-- segments use.
checkConflictingDynamics :: RouteManifest -> Either ValidationError ()
checkConflictingDynamics manifest =
  maybe (Right ()) Left (findConflict dynamicsByScopeAndDepth)
  where
    patterns = fmap (^. rePattern) (_rmRoutes manifest)
    dynamicsByScopeAndDepth = buildDynamicMap patterns

-- | Index of (staticPrefix, depth) -> paramName -> [RoutePattern].
--
-- The 'staticPrefix' is the list of static segment names that precede the
-- dynamic segment.  Two dynamic segments are siblings only when their
-- prefixes match AND they sit at the same depth.
type DynamicMap = Map.Map ([Text], Int) (Map.Map Text [RoutePattern])

-- | Build a map keyed by (staticPrefix, depth) from all patterns.
buildDynamicMap :: [RoutePattern] -> DynamicMap
buildDynamicMap = foldl insertPattern Map.empty

-- | Insert one pattern's dynamic segments into the scope-keyed map.
insertPattern :: DynamicMap -> RoutePattern -> DynamicMap
insertPattern acc pat =
  foldl (insertScopedSegment pat) acc (scopedDynamics (pat ^. rpSegments))

-- | Extract (staticPrefix, depth, paramName) for each dynamic segment.
--
-- The static prefix grows with each 'StaticSegment' encountered.  This
-- ensures that \/packages\/[author] and \/blog\/[slug] carry different
-- prefixes and are never grouped together.
scopedDynamics :: [RouteSegment] -> [([Text], Int, Text)]
scopedDynamics = go [] 0
  where
    go _prefix _depth [] = []
    go prefix depth (StaticSegment name : rest) =
      go (prefix ++ [name]) (depth + 1) rest
    go prefix depth (DynamicSegment name : rest) =
      (prefix, depth, name) : go prefix (depth + 1) rest
    go prefix depth (CatchAll name : rest) =
      (prefix, depth, name) : go prefix (depth + 1) rest

-- | Record a single (scope, depth, name) triple for a given pattern.
insertScopedSegment
  :: RoutePattern -> DynamicMap -> ([Text], Int, Text) -> DynamicMap
insertScopedSegment pat acc (scope, depth, name) =
  Map.alter (Just . addToInner) (scope, depth) acc
  where
    addToInner Nothing = Map.singleton name [pat]
    addToInner (Just inner) = Map.insertWith (<>) name [pat] inner

-- | Scan the dynamic map for any scope+depth with more than one param name.
findConflict :: DynamicMap -> Maybe ValidationError
findConflict dynMap =
  maybe Nothing checkNameMap (firstConflictingEntry dynMap)

-- | Find the first entry where multiple parameter names coexist.
firstConflictingEntry :: DynamicMap -> Maybe (Map.Map Text [RoutePattern])
firstConflictingEntry dynMap =
  listToMaybe (filter hasConflict (Map.elems dynMap))

-- | A scope+depth entry is conflicting when more than one parameter name
-- appears at that exact position.
hasConflict :: Map.Map Text [RoutePattern] -> Bool
hasConflict nameMap = Map.size nameMap > 1

-- | Build a 'ConflictingDynamicSegments' from the conflicting entry.
checkNameMap :: Map.Map Text [RoutePattern] -> Maybe ValidationError
checkNameMap nameMap =
  Just (ConflictingDynamicSegments firstName allPatterns)
  where
    firstName = fst (Map.findMin nameMap)
    allPatterns = concatMap snd (Map.toList nameMap)

-- | Safe head for lists.
listToMaybe :: [a] -> Maybe a
listToMaybe [] = Nothing
listToMaybe (x : _) = Just x

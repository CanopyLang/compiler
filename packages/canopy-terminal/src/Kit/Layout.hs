{-# LANGUAGE OverloadedStrings #-}

-- | Layout resolution for Kit route hierarchies.
--
-- Resolves which layout module applies to each route by matching the
-- route's segment prefix against the layout entries discovered during
-- route scanning. A layout entry at a given directory level wraps all
-- routes whose path starts with that prefix.
--
-- @since 0.19.2
module Kit.Layout
  ( LayoutBinding (..)
  , resolveLayouts
  ) where

import qualified Data.List as List
import Kit.Route.Types
  ( LayoutEntry (..)
  , RouteManifest (..)
  , RouteSegment (..)
  )
import qualified Kit.Route.Types as Route

-- | A resolved binding between a route prefix and its layout module.
--
-- @since 0.19.2
data LayoutBinding = LayoutBinding
  { _lbPrefix :: ![RouteSegment]
    -- ^ Route prefix this layout applies to.
  , _lbModulePath :: !FilePath
    -- ^ Path to the layout module file.
  } deriving (Eq, Show)

-- | Resolve layout bindings from a 'RouteManifest'.
--
-- Converts each 'LayoutEntry' discovered during scanning into a
-- 'LayoutBinding'. The entries are sorted by prefix length (longest
-- first) so that the most specific layout takes precedence during
-- rendering.
--
-- @since 0.19.2
resolveLayouts :: RouteManifest -> [LayoutBinding]
resolveLayouts manifest =
  List.sortBy compareByPrefixLength (fmap toBinding layouts)
  where
    layouts = Route._rmLayouts manifest
    toBinding entry = LayoutBinding (Route._lePrefix entry) (Route._leModulePath entry)

-- | Compare layout bindings by prefix length, longest first.
compareByPrefixLength :: LayoutBinding -> LayoutBinding -> Ordering
compareByPrefixLength a b =
  compare (length (_lbPrefix b)) (length (_lbPrefix a))

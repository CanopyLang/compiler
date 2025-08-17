{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Main module gathering and lookup for the Generate subsystem.
--
-- This module handles the collection and organization of main entry
-- points from build roots, mapping them to their corresponding
-- optimized representations for code generation.
--
-- === Main Resolution Process
--
-- @
-- Build.Root -> Package + Objects -> ModuleName.Canonical + Opt.Main
-- @
--
-- === Root Types
--
-- * Inside roots: Modules within the current package
-- * Outside roots: External modules with explicit graphs
--
-- === Usage Examples
--
-- @
-- -- Gather all main entry points
-- let mains = gatherMains pkg objects roots
-- 
-- -- Generate code with collected mains
-- JS.generate mode graph mains
-- @
--
-- === Main Module Resolution
--
-- The system resolves main modules by:
--
-- 1. Iterating through all build roots
-- 2. Looking up corresponding local graphs
-- 3. Extracting main functions from graphs
-- 4. Creating canonical module name mappings
--
-- @since 0.19.1
module Generate.Mains
  ( -- * Main Gathering Functions
    gatherMains
  , lookupMain
  ) where

import qualified AST.Optimized as Opt
import qualified Build
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens ((^.))
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Data.NonEmptyList as NE
import qualified Generate.Types as Types
import Generate.Types (Objects(..))

-- | Gather main entry points from build roots.
--
-- This function collects all main entry points from the provided
-- build roots, creating a mapping from canonical module names
-- to their optimized main representations.
--
-- === Parameters
--
-- * 'pkg': Package name for canonical module name construction
-- * 'objects': Objects container with local graphs
-- * 'roots': Non-empty list of build roots to process
--
-- === Returns
--
-- A Map from canonical module names to optimized main representations.
--
-- === Root Processing
--
-- * Inside roots: Look up in local graphs using package name
-- * Outside roots: Use provided graph directly
-- * Missing mains: Filtered out of result map
--
-- === Examples
--
-- @
-- let mains = gatherMains pkg objects roots
-- case Map.lookup targetModule mains of
--   Just main -> generateForMain main
--   Nothing -> reportNoMain targetModule
-- @
--
-- @since 0.19.1
gatherMains 
  :: Pkg.Name
  -- ^ Package name for canonical module name construction
  -> Objects
  -- ^ Objects container with local graphs
  -> NE.List Build.Root
  -- ^ Non-empty list of build roots to process
  -> Map ModuleName.Canonical Opt.Main
  -- ^ Map from canonical module names to main representations
gatherMains pkg objects roots =
  Map.fromList $ Maybe.mapMaybe (lookupMain pkg (objects ^. Types.localGraphs)) (NE.toList roots)

-- | Look up main entry point from a build root.
--
-- This function attempts to locate and extract the main entry
-- point from a single build root, handling both inside and
-- outside root types appropriately.
--
-- === Parameters
--
-- * 'pkg': Package name for canonical module name construction
-- * 'locals': Map of local graphs to search
-- * 'root': Build root to process
--
-- === Returns
--
-- Maybe a tuple of canonical module name and main representation.
-- Returns Nothing if no main is found.
--
-- === Root Type Handling
--
-- * Inside: Look up module in locals map, extract main if present
-- * Outside: Use provided graph directly, extract main if present
--
-- === Examples
--
-- @
-- case lookupMain pkg locals root of
--   Just (canonicalName, main) -> processMain canonicalName main
--   Nothing -> continueWithoutMain
-- @
--
-- @since 0.19.1
lookupMain 
  :: Pkg.Name
  -- ^ Package name for canonical module name construction
  -> Map ModuleName.Raw Opt.LocalGraph
  -- ^ Map of local graphs to search
  -> Build.Root
  -- ^ Build root to process
  -> Maybe (ModuleName.Canonical, Opt.Main)
  -- ^ Maybe canonical module name and main representation
lookupMain pkg locals root =
  let toPair name (Opt.LocalGraph maybeMain _ _) =
        (,) (ModuleName.Canonical pkg name) <$> maybeMain
   in case root of
        Build.Inside name -> Map.lookup name locals >>= toPair name
        Build.Outside name _ g -> toPair name g
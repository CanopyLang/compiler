{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module processing operations for build artifacts.
--
-- This module handles the processing and classification of individual modules
-- during artifact assembly. It manages the transformation of compilation
-- results into properly categorized module entries and handles the distinction
-- between root and internal modules.
--
-- === Primary Responsibilities
--
-- * Internal module processing and classification ('addInside', 'addInsideSafe')
-- * Root module processing ('addOutside')
-- * Module type determination (Fresh vs Cached)
-- * Root module identification and filtering
-- * Error handling for problematic modules
--
-- === Usage Examples
--
-- @
-- -- Add internal module to collection
-- let modules = addInside moduleName result []
--
-- -- Add internal module with root safety checking
-- let modules = addInsideSafe rootResults moduleName result []
--
-- -- Add root module to collection
-- let modules = addOutside results rootResult []
--
-- -- Check if module is a root module
-- if isRootModule rootResults moduleName
--   then handleAsRoot moduleName
--   else handleAsInternal moduleName
-- @
--
-- === Module Classification
--
-- Modules are classified into distinct types:
--
-- * **Fresh**: Newly compiled with current interfaces and objects
-- * **Cached**: Previously compiled, loaded from cache with MVar
-- * **Root**: Entry point modules specified by user
-- * **Internal**: Dependency modules discovered during build
--
-- === Error Handling
--
-- Problematic modules are handled gracefully:
--
-- * 'RNotFound': Missing dependencies (runtime error for internal, ignored for safe)
-- * 'RProblem': Compilation errors (runtime error for internal, ignored for safe)
-- * 'RBlocked': Blocked dependencies (runtime error for internal, ignored for safe)
--
-- The 'addInsideSafe' variant ignores problematic modules instead of failing,
-- which is appropriate when some dependencies may legitimately be unavailable.
--
-- @since 0.19.1
module Build.Artifacts.Processing
  ( -- * Module Processing
    addInside
  , addInsideSafe
  , addOutside
    
  -- * Root Module Utilities
  , getRootNames
  , getRootName
  , isRootModule
  , matchesRootName
    
  -- * Error Handling
  , badInside
  ) where

-- Canopy-specific imports
import qualified Canopy.ModuleName as ModuleName

-- Build system imports
import Build.Types
  ( Result (..)
  , Root (..)
  , RootResult (..)
  , Module (..)
  , Artifacts (..)
  )

-- Standard library imports
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import qualified Debug.Trace as Trace

-- | Add an internal module to the module collection.
--
-- Processes compilation results for internal (non-root) modules and
-- adds them to the artifact module list. Handles both fresh compilation
-- results and cached modules appropriately.
--
-- ==== Module Types Generated
--
-- * 'Fresh': For newly compiled modules with interfaces and objects
-- * 'Cached': For modules loaded from cache with MVars
--
-- ==== Error Handling
--
-- Problematic modules (compilation errors, missing dependencies) trigger
-- runtime errors since they should have been caught during the compilation
-- phase and prevented from reaching artifact assembly.
--
-- ==== Result Type Processing
--
-- * 'RNew'/'RSame': Creates Fresh module entries
-- * 'RCached': Creates Cached module entry with MVar
-- * 'RForeign'/'RKernel': Ignored (handled elsewhere)
-- * 'RNotFound'/'RProblem'/'RBlocked': Runtime errors
--
-- @since 0.19.1
addInside :: ModuleName.Raw -> Result -> [Module] -> [Module]
addInside name result modules =
  case result of
    RNew _ iface objs _ -> Fresh name iface objs : modules
    RSame _ iface objs _ -> Fresh name iface objs : modules
    RCached main _ mvar -> Cached name main mvar : modules
    RNotFound _ -> error (badInside name)
    RProblem _ -> error (badInside name)
    RBlocked -> error (badInside name)
    RForeign _ -> modules
    RKernel -> modules

-- | Add an internal module with root module safety checking.
--
-- Enhanced version of 'addInside' that skips root modules to prevent
-- duplication. Root modules are handled separately by 'addOutside' to
-- ensure proper artifact structure.
--
-- ==== Root Module Handling
--
-- Root modules are processed by 'addOutside' and should not be included
-- in the internal module list. This function performs the necessary
-- filtering to maintain clean separation.
--
-- ==== Safe Error Handling
--
-- Unlike 'addInside', this function gracefully ignores problematic
-- modules rather than failing with runtime errors. This approach is
-- appropriate when processing large result sets where some dependencies
-- may legitimately be unavailable.
--
-- @since 0.19.1
addInsideSafe :: List RootResult -> ModuleName.Raw -> Result -> [Module] -> [Module]
addInsideSafe rootResults name result modules =
  -- Root modules should never be processed by addInside since they're handled by addOutside
  if isRootModule rootResults name
    then modules -- Skip root modules entirely
    else case result of
      RNew _ iface objs _ -> Fresh name iface objs : modules
      RSame _ iface objs _ -> Fresh name iface objs : modules
      RCached main _ mvar -> Cached name main mvar : modules
      RNotFound _ -> modules -- Ignore problematic dependencies
      RProblem _ -> modules -- Ignore problematic dependencies
      RBlocked -> modules -- Ignore problematic dependencies
      RForeign _ -> modules
      RKernel -> modules

-- | Add a root module to the module collection.
--
-- Processes root module results and adds them to the artifact module list.
-- Root modules are the entry points specified by the user and require
-- special handling to ensure they're properly included in artifacts.
--
-- ==== Root Module Processing
--
-- * 'RInside': Root module within project structure
-- * 'ROutsideOk': Successfully compiled external root module
-- * 'ROutsideErr'/'ROutsideBlocked': Problematic roots are ignored
--
-- ==== Error Diagnostics
--
-- The function includes diagnostic tracing for problematic root modules
-- to aid in debugging build issues.
--
-- @since 0.19.1
addOutside :: Map.Map ModuleName.Raw Result -> RootResult -> [Module] -> [Module]
addOutside results root modules =
  case root of
    RInside name -> processInsideRoot results name modules
    ROutsideOk name iface objs -> Fresh name iface objs : modules
    ROutsideErr _ -> modules
    ROutsideBlocked -> modules

-- | Process inside root module result.
--
-- Handles the case where a root module is internal to the project by
-- looking up its compilation result and processing it appropriately.
--
-- @since 0.19.1
processInsideRoot :: Map.Map ModuleName.Raw Result -> ModuleName.Raw -> [Module] -> [Module]
processInsideRoot results name modules =
  case Map.lookup name results of
    Just result -> processFoundResult name result modules
    Nothing -> modules

-- | Process found result for inside root.
--
-- Converts a found compilation result into the appropriate module entry,
-- with special handling for problematic results that may indicate build
-- system issues.
--
-- @since 0.19.1
processFoundResult :: ModuleName.Raw -> Result -> [Module] -> [Module]
processFoundResult name result modules =
  case result of
    RNew _ iface objs _ -> Fresh name iface objs : modules
    RSame _ iface objs _ -> Fresh name iface objs : modules
    RCached main _ mvar -> Cached name main mvar : modules
    RNotFound prob -> Trace.trace ("WARNING: Main module has RNotFound status: " <> show prob) modules
    _ -> modules -- Other problematic results are skipped

-- | Extract root module names from artifacts.
--
-- Utility function to get the list of root module names from a complete
-- artifacts structure. Used for dependency analysis and build reporting.
--
-- @since 0.19.1
getRootNames :: Artifacts -> NE.List ModuleName.Raw
getRootNames (Artifacts _ _ roots _ _) =
  fmap getRootName roots

-- | Extract the name from a root module.
--
-- Gets the module name from any type of root module, whether it's
-- internal to the project or external.
--
-- ==== Root Type Handling
--
-- * 'Inside': Extract internal module name
-- * 'Outside': Extract external module name (ignoring interface/objects)
--
-- @since 0.19.1
getRootName :: Root -> ModuleName.Raw
getRootName root =
  case root of
    Inside name -> name
    Outside name _ _ -> name

-- | Check if a module name corresponds to a root module.
--
-- Determines whether a given module name matches any of the root modules
-- in the result set. Used to prevent duplicate processing of root modules.
--
-- ==== Matching Strategy
--
-- Tests the module name against each root result using 'matchesRootName'
-- to handle the various root result types appropriately.
--
-- @since 0.19.1
isRootModule :: List RootResult -> ModuleName.Raw -> Bool
isRootModule rootResults name =
  List.any (matchesRootName name) (NE.toList rootResults)

-- | Check if a module name matches a specific root result.
--
-- Tests whether a module name corresponds to a particular root result,
-- handling both successful and failed root compilation results.
--
-- ==== Root Result Matching
--
-- * 'RInside'/'ROutsideOk': Match module name directly
-- * 'ROutsideErr'/'ROutsideBlocked': Never match (no valid name)
--
-- @since 0.19.1
matchesRootName :: ModuleName.Raw -> RootResult -> Bool
matchesRootName name rootResult =
  case rootResult of
    RInside n -> n == name
    ROutsideOk n _ _ -> n == name
    ROutsideErr _ -> False
    ROutsideBlocked -> False

-- | Generate error message for problematic internal modules.
--
-- Creates a descriptive error message when an internal module has
-- compilation problems that should have been caught earlier in the
-- build process.
--
-- ==== Error Context
--
-- This error indicates a build system inconsistency where problematic
-- modules reached the artifact assembly phase without being properly
-- handled during compilation.
--
-- @since 0.19.1
badInside :: ModuleName.Raw -> String
badInside name =
  "Error from `" <> (Name.toChars name <> "` should have been reported already.")
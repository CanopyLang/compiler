{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Artifact management coordinating interface for the Canopy compiler.
--
-- This module serves as the primary interface for build artifact operations,
-- coordinating between specialized collection and processing modules. It
-- provides a unified API for artifact assembly while maintaining clean
-- separation of concerns.
--
-- === Architecture Overview
--
-- The artifact management system is decomposed into focused modules:
--
-- * "Build.Artifacts.Collection" - Artifact assembly and problem gathering
-- * "Build.Artifacts.Processing" - Module processing and classification
-- * "Build.Artifacts.Management" - Coordinating interface (this module)
--
-- === Primary Responsibilities
--
-- * Unified API for artifact operations
-- * Re-export of collection and processing functionality
-- * Coordination between specialized sub-modules
-- * Backwards compatibility for existing code
--
-- === Usage Examples
--
-- @
-- -- Convert compilation results to artifacts
-- artifacts <- toArtifacts env dependencies results rootResults
-- case artifacts of
--   Left problem -> handleBuildProblem problem
--   Right artifacts -> packageArtifacts artifacts
--
-- -- Add modules to artifact collection
-- let modules = addInside moduleName result []
-- let moreModules = addOutside results rootResult modules
--
-- -- Check root module status
-- if isRootModule rootResults moduleName
--   then handleAsRoot moduleName
--   else handleAsInternal moduleName
-- @
--
-- === Module Integration
--
-- This coordinating module ensures seamless integration between:
--
-- * Artifact collection operations ('Collection' module)
-- * Module processing operations ('Processing' module)
-- * External build system components
--
-- All functions maintain their original signatures and behavior while
-- being implemented through the specialized sub-modules.
--
-- @since 0.19.1
module Build.Artifacts.Management
  ( -- * Artifact Assembly
    toArtifacts
  , gatherProblemsOrMains
    
  -- * Module Collection
  , addInside
  , addInsideSafe
  , addOutside
    
  -- * Utility Functions
  , getRootNames
  , getRootName
  , isRootModule
  , matchesRootName
  , badInside
  ) where

-- Sub-module imports
import Build.Artifacts.Collection
  ( toArtifacts
  , gatherProblemsOrMains
  )
import Build.Artifacts.Processing
  ( addInside
  , addInsideSafe
  , addOutside
  , getRootNames
  , getRootName
  , isRootModule
  , matchesRootName
  , badInside
  )


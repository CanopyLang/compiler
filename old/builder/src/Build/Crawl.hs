{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module crawling functionality for the Build system.
--
-- This module provides a clean coordinating interface for module crawling
-- and discovery functionality. It serves as the main entry point that
-- orchestrates the various focused sub-modules:
--
-- * "Build.Crawl.Discovery" - Module discovery and file finding
-- * "Build.Crawl.Processing" - Module processing and validation  
-- * "Build.Crawl.Dependencies" - Dependency crawling and root handling
--
-- The crawling system handles comprehensive module resolution including:
--
-- @
-- 1. Module Discovery:
--    - File path resolution with extension priority (.can > .canopy > .elm)
--    - Source directory traversal
--    - Kernel module detection
--
-- 2. Module Processing:
--    - Source parsing and validation
--    - Name consistency checking
--    - Ambiguity resolution
--
-- 3. Dependency Management:
--    - Concurrent dependency crawling
--    - Root module handling
--    - Foreign dependency resolution
-- @
--
-- === Usage Examples
--
-- @
-- -- Main entry point for module crawling
-- status <- crawlModule config moduleName
-- 
-- -- File-based crawling with validation
-- status <- crawlFile env mvar docsNeed name path time buildID
--
-- -- Root module processing
-- rootStatus <- crawlRoot env mvar rootLocation
-- @
--
-- === Integration with Build System
--
-- This module integrates seamlessly with the broader build system through:
--   * Build.Config for crawling configuration
--   * Build.Types for status and environment types
--   * Concurrent processing using MVars for coordination
--
-- @since 0.19.1
module Build.Crawl
  ( -- * Main Crawling Functions
    module Build.Crawl.Processing
    -- * Discovery Functions
  , module Build.Crawl.Discovery
    -- * Dependency Functions
  , module Build.Crawl.Dependencies
  ) where

-- Re-export sub-modules
import Build.Crawl.Discovery
import Build.Crawl.Processing  
import Build.Crawl.Dependencies
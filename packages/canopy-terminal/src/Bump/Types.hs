{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Foundation types and lenses for the Bump module.
--
-- This module defines core data types used throughout the version bumping
-- system, including the environment record and related utilities.
-- All record fields are equipped with lenses for safe manipulation.
--
-- The main type 'Env' holds all context needed for bump operations:
-- project root, package cache, HTTP manager, registry data, and outline.
--
-- ==== Examples
--
-- >>> env <- getEnv
-- >>> env ^. envRoot
-- "/path/to/project"
--
-- >>> env & envCache .~ newCache
-- Env { ... }
--
-- @since 0.19.1
module Bump.Types
  ( Env (..),
    envRoot,
    envCache,
    envManager,
    envRegistry,
    envOutline,
  )
where

import Canopy.Outline (PkgOutline)
import Control.Lens (makeLenses)
import qualified Deps.Registry as Registry
import qualified Http
import qualified Stuff

-- | Environment data containing all necessary context for version bumping.
--
-- This record holds the project root, package cache, HTTP manager,
-- registry information, and package outline needed for bump operations.
--
-- ==== Fields
--
-- * 'envRoot': Absolute path to the project root directory
-- * 'envCache': Package cache for dependency resolution
-- * 'envManager': HTTP manager for network operations
-- * 'envRegistry': Registry configuration for package lookups
-- * 'envOutline': Parsed package outline from canopy.json
--
-- All fields are strict to prevent space leaks and equipped with lenses
-- for safe access and modification patterns.
--
-- @since 0.19.1
data Env = Env
  { -- | Project root directory path
    _envRoot :: !FilePath,
    -- | Package cache for dependencies
    _envCache :: !Stuff.PackageCache,
    -- | HTTP manager for network requests
    _envManager :: !Http.Manager,
    -- | Registry configuration
    _envRegistry :: !Registry.CanopyRegistries,
    -- | Package outline from canopy.json
    _envOutline :: !PkgOutline
  }

-- | Generate lenses for Env record fields.
--
-- Creates the following lenses:
--   * 'envRoot' :: Lens' Env FilePath
--   * 'envCache' :: Lens' Env Stuff.PackageCache
--   * 'envManager' :: Lens' Env Http.Manager
--   * 'envRegistry' :: Lens' Env Registry.CanopyRegistries
--   * 'envOutline' :: Lens' Env PkgOutline
makeLenses ''Env

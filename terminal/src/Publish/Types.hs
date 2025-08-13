{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core types for Canopy package publishing.
--
-- This module contains all fundamental types used throughout
-- the publishing system, including environment configuration,
-- command line arguments, and validation types.
--
-- @since 0.19.1
module Publish.Types
  ( -- * Configuration
    Args (..),
    Env (..),

    -- * Environment Lenses
    envRoot,
    envCache,
    envManager,
    envRegistry,
    envOutline,

    -- * Publishing Types
    GoodVersion (..),
    RegistrationData (..),

    -- * RegistrationData Lenses
    regPkg,
    regVersion,
    regDocs,
    regCommitHash,
    regSha,

    -- * Git Operations
    Git (..),
  )
where

import Canopy.CustomRepositoryData (RepositoryLocalName)
import Canopy.Docs (Documentation)
import qualified Canopy.Magnitude as Magnitude
import Canopy.Outline (Outline)
import Canopy.Package (Name)
import Canopy.Version (Version)
import Control.Lens (makeLenses)
import Deps.Registry (ZokkaRegistries)
import Http (Manager, Sha)
import Stuff (PackageCache)
import qualified System.Exit as SysExit

-- | Command line arguments for the publish command.
--
-- @since 0.19.1
data Args
  = -- | No arguments provided
    NoArgs
  | -- | Publish to specified repository
    PublishToRepository !RepositoryLocalName
  deriving (Eq, Show)

-- | Publishing environment containing all necessary context.
--
-- Contains the project root, package cache, HTTP manager, registry information,
-- and parsed outline required for the publishing process.
--
-- @since 0.19.1
data Env = Env
  { -- | Project root directory
    _envRoot :: !FilePath,
    -- | Package cache for dependency resolution
    _envCache :: !PackageCache,
    -- | HTTP manager for network requests
    _envManager :: !Manager,
    -- | Available package registries
    _envRegistry :: !ZokkaRegistries,
    -- | Parsed project outline (canopy.json)
    _envOutline :: !Outline
  }

makeLenses ''Env

-- | Represents a valid version for publishing.
--
-- @since 0.19.1
data GoodVersion
  = -- | First version (1.0.0)
    GoodStart
  | -- | Valid version bump with magnitude
    GoodBump !Version !Magnitude.Magnitude
  deriving (Eq)

-- | Package registration data for HTTP upload.
--
-- @since 0.19.1
data RegistrationData = RegistrationData
  { -- | Package name
    _regPkg :: !Name,
    -- | Package version
    _regVersion :: !Version,
    -- | Generated documentation
    _regDocs :: !Documentation,
    -- | Git commit hash
    _regCommitHash :: !String,
    -- | ZIP file SHA hash
    _regSha :: !Sha
  }

makeLenses ''RegistrationData

-- | Git command wrapper for executing Git operations.
--
-- @since 0.19.1
newtype Git = Git
  { -- | Execute Git command with arguments
    _runGit :: [String] -> IO SysExit.ExitCode
  }

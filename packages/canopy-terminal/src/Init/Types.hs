{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Core types and data structures for Init system.
--
-- This module defines the foundational types used throughout the Init system,
-- including configuration data, project setup parameters, and initialization
-- context. All types are equipped with lenses for clean record operations
-- following CLAUDE.md guidelines.
--
-- == Key Types
--
-- * 'InitConfig' - Configuration for initialization process
-- * 'ProjectContext' - Project setup context and metadata
-- * 'InitError' - Comprehensive error types for init failures
-- * 'DefaultDeps' - Default dependency configuration
--
-- == Lens Usage
--
-- All record types provide lenses for field access and updates:
--
-- @
-- config <- Environment.defaultConfig
-- let updatedConfig = config & configVerbose .~ True
--                           & configForce .~ False
-- @
--
-- == Error Handling
--
-- The 'InitError' type captures all possible initialization failures:
--
-- * 'ProjectExists' - canopy.json already exists
-- * 'RegistryFailure' - Package registry connection issues
-- * 'SolverFailure' - Dependency resolution failures
-- * 'FileSystemError' - Directory creation or file writing issues
--
-- @since 0.19.1
module Init.Types
  ( -- * Configuration Types
    InitConfig (..),
    ProjectContext (..),
    DefaultDeps (..),

    -- * Error Types
    InitError (..),

    -- * Lenses
    configVerbose,
    configForce,
    configSkipPrompt,
    contextProjectName,
    contextSourceDirs,
    contextDependencies,
    contextTestDeps,
    depsCore,
    depsBrowser,
    depsHtml,

    -- * Configuration
    defaultConfig,
    defaultContext,
    defaultDependencies,
    defaultDeps,
  )
where

import qualified Canopy.Constraint as Con
import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import Control.Lens (makeLenses)
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Reporting.Exit as Exit

-- | Configuration for the initialization process.
--
-- Controls behavior of project initialization including user interaction,
-- validation strictness, and output verbosity.
data InitConfig = InitConfig
  { -- | Enable verbose output during initialization
    _configVerbose :: !Bool,
    -- | Force initialization even if canopy.json exists
    _configForce :: !Bool,
    -- | Skip user confirmation prompt
    _configSkipPrompt :: !Bool
  }
  deriving (Eq, Show)

-- | Project context containing setup parameters.
--
-- Encapsulates all information needed to create a new Canopy project,
-- including source directories, dependencies, and project metadata.
data ProjectContext = ProjectContext
  { -- | Optional project name override
    _contextProjectName :: !(Maybe String),
    -- | List of source directories (default: ["src"])
    _contextSourceDirs :: ![String],
    -- | Direct project dependencies
    _contextDependencies :: !(Map Name Con.Constraint),
    -- | Test-only dependencies
    _contextTestDeps :: !(Map Name Con.Constraint)
  }
  deriving (Eq, Show)

-- | Default dependency configuration for new projects.
--
-- Specifies the standard dependencies that every new Canopy project
-- should include by default.
data DefaultDeps = DefaultDeps
  { -- | Core language package constraint
    _depsCore :: !Con.Constraint,
    -- | Browser API package constraint
    _depsBrowser :: !Con.Constraint,
    -- | HTML package constraint
    _depsHtml :: !Con.Constraint
  }
  deriving (Eq, Show)

-- | Comprehensive error types for initialization failures.
--
-- Captures all possible failure modes during project initialization,
-- providing rich error information for user feedback.
data InitError
  = -- | Project already exists at path
    ProjectExists !FilePath
  | -- | Package registry connection or communication failure
    RegistryFailure !Exit.RegistryProblem
  | -- | Dependency resolution failure
    SolverFailure !Exit.Solver
  | -- | No valid dependency solution found for packages
    NoSolution ![Name]
  | -- | No offline solution available for packages
    NoOfflineSolution ![Name]
  | -- | File system operation failure with description
    FileSystemError !String
  deriving (Show)

-- Generate lenses for all record types
makeLenses ''InitConfig
makeLenses ''ProjectContext
makeLenses ''DefaultDeps

-- | Default configuration for initialization.
--
-- Provides sensible defaults for the initialization process with minimal
-- user interaction required.
--
-- >>> defaultConfig ^. configVerbose
-- False
--
-- >>> defaultConfig ^. configForce
-- False
defaultConfig :: InitConfig
defaultConfig =
  InitConfig
    { _configVerbose = False,
      _configForce = False,
      _configSkipPrompt = False
    }

-- | Default project context for standard Canopy applications.
--
-- Sets up a typical project structure with standard source directories
-- and core dependencies.
--
-- >>> defaultContext ^. contextSourceDirs
-- ["src"]
--
-- >>> Map.keys (defaultContext ^. contextDependencies)
-- [core, browser, html]
defaultContext :: ProjectContext
defaultContext =
  ProjectContext
    { _contextProjectName = Nothing,
      _contextSourceDirs = ["src"],
      _contextDependencies = defaultDependencies,
      _contextTestDeps = Map.empty
    }

-- | Standard default dependencies for new projects.
--
-- Every new Canopy project includes these essential packages:
-- core (language fundamentals), browser (DOM APIs), and html (HTML generation).
defaultDependencies :: Map Name Con.Constraint
defaultDependencies =
  Map.fromList
    [ (Pkg.core, Con.anything),
      (Pkg.browser, Con.anything),
      (Pkg.html, Con.anything)
    ]

-- | Default dependency constraints.
--
-- Provides the standard constraint configuration used for new projects.
defaultDeps :: DefaultDeps
defaultDeps =
  DefaultDeps
    { _depsCore = Con.anything,
      _depsBrowser = Con.anything,
      _depsHtml = Con.anything
    }

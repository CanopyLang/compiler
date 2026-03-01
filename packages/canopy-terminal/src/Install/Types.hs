{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Install system core types and data structures.
--
-- This module defines all the core types used throughout the Install system:
--
-- * Command-line arguments and configuration types
-- * Installation state and context management
-- * Change tracking and display structures
-- * Error types and validation results
--
-- == Architecture
--
-- All types use lens-based access patterns for consistency:
--
-- * Record fields are prefixed with underscores
-- * Lenses are generated using Template Haskell
-- * Access uses lens operators (^., &, .~, %~)
--
-- == Usage Examples
--
-- @
-- ctx <- createContext root env oldOutline newOutline
-- let ctxRoot = ctx ^. icRoot
-- let updatedCtx = ctx & icEnv .~ newEnv
-- @
--
-- @since 0.19.1
module Install.Types
  ( -- * Arguments
    Args (..),

    -- * Flags
    Flags (..),

    -- * Installation Context
    InstallContext (..),

    -- ** Lenses
    icRoot,
    icEnv,
    icOldOutline,
    icNewOutline,
    icOffline,
    icNoVerify,

    -- * Changes
    Changes (..),
    Change (..),

    -- * User Interface
    ChangePlanRequest (..),

    -- ** Lenses
    cprContext,
    cprToChars,
    cprChangeDict,
    ChangeDocs (..),

    -- ** Lenses
    docInserts,
    docChanges,
    docRemoves,
    Widths (..),

    -- ** Lenses
    nameWidth,
    leftWidth,
    rightWidth,

    -- * Dependencies
    ExistingDep (..),

    -- * Task Type
    Task,
  )
where

import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Lens.TH (makeLenses)
import Data.Map.Strict (Map)
import qualified Deps.Solver as Solver
import Reporting.Doc (Doc)
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Command-line arguments for the install command.
--
-- Represents the different modes of package installation:
--
-- * 'NoArgs' - Install all dependencies from canopy.json
-- * 'Install' - Install a specific named package
--
-- @since 0.19.1
data Args
  = NoArgs
  | Install Pkg.Name
  deriving (Eq, Show)

-- | Command-line flags for the install command.
--
-- Controls optional behaviour such as disabling fallback to the
-- Elm registry when canopy-lang.org is unreachable, restricting
-- resolution to locally cached packages only, or skipping
-- cryptographic signature verification.
--
-- @since 0.19.2
data Flags = Flags
  { -- | When 'True', disable fallback from canopy-lang.org to elm-lang.org.
    _installNoFallback :: !Bool,
    -- | When 'True', skip all network requests and use only cached packages.
    _installOffline :: !Bool,
    -- | When 'True', skip lock file hash and signature verification entirely.
    _installNoVerify :: !Bool
  }
  deriving (Eq, Show)

-- | Installation context containing all necessary state.
--
-- Bundles together the file system root, solver environment,
-- outline information, and network policy needed for installation
-- operations.
--
-- @since 0.19.1
data InstallContext = InstallContext
  { -- | Project root directory
    _icRoot :: !FilePath,
    -- | Solver environment with registry information
    _icEnv :: !Solver.Env,
    -- | Original canopy.json outline before changes
    _icOldOutline :: !Outline.Outline,
    -- | Updated canopy.json outline after changes
    _icNewOutline :: !Outline.Outline,
    -- | When 'True', skip all network requests and use only cached packages.
    _icOffline :: !Bool,
    -- | When 'True', skip lock file hash and signature verification.
    _icNoVerify :: !Bool
  }

-- | Changes to be applied to dependency configuration.
--
-- Represents different types of dependency modifications:
--
-- * 'AlreadyInstalled' - Package is already present
-- * 'PromoteTest' - Move from test-dependencies to dependencies
-- * 'PromoteIndirect' - Move from indirect to direct dependencies
-- * 'Changes' - Complex set of additions/modifications/removals
--
-- @since 0.19.1
data Changes vsn
  = AlreadyInstalled
  | PromoteTest Outline.Outline
  | PromoteIndirect Outline.Outline
  | Changes (Map Pkg.Name (Change vsn)) Outline.Outline
  deriving (Show)

-- | Individual change to a package dependency.
--
-- Tracks the specific type of modification being made:
--
-- * 'Insert' - Add new dependency
-- * 'Change' - Update existing dependency version/constraint
-- * 'Remove' - Remove existing dependency
--
-- @since 0.19.1
data Change a
  = Insert a
  | Change a a
  | Remove a
  deriving (Eq, Show)

-- | Request for displaying a change plan to the user.
--
-- Contains all information needed to format and display
-- proposed changes for user approval.
--
-- @since 0.19.1
data ChangePlanRequest a = ChangePlanRequest
  { -- | Installation context
    _cprContext :: !InstallContext,
    -- | Function to convert version/constraint to string
    _cprToChars :: !(a -> String),
    -- | Map of package changes to display
    _cprChangeDict :: !(Map Pkg.Name (Change a))
  }

-- | Documentation for formatting change displays.
--
-- Organizes changes by type for structured presentation
-- to users during installation confirmation.
--
-- @since 0.19.1
data ChangeDocs = ChangeDocs
  { -- | New packages being added
    _docInserts :: ![Doc],
    -- | Existing packages being modified
    _docChanges :: ![Doc],
    -- | Packages being removed
    _docRemoves :: ![Doc]
  }

-- | Column widths for aligned change display formatting.
--
-- Tracks maximum widths needed for proper table alignment
-- when showing dependency changes to users.
--
-- @since 0.19.1
data Widths = Widths
  { -- | Maximum package name width
    _nameWidth :: !Int,
    -- | Maximum left column (old version) width
    _leftWidth :: !Int,
    -- | Maximum right column (new version) width
    _rightWidth :: !Int
  }
  deriving (Eq, Show)

-- | Existing dependency found in project configuration.
--
-- Represents different locations where a package might
-- already exist in the project's dependency structure.
--
-- @since 0.19.1
data ExistingDep
  = -- | Found in indirect dependencies
    IndirectDep Version.Version
  | -- | Found in test direct dependencies
    TestDirectDep Version.Version
  | -- | Found in test indirect dependencies
    TestIndirectDep Version.Version
  deriving (Eq, Show)

-- | Task monad for install operations.
--
-- Specialized Task type that can throw Install-specific
-- errors during execution.
--
-- @since 0.19.1
type Task a = Task.Task Exit.Install a

-- Generate lenses for all record types
makeLenses ''InstallContext
makeLenses ''ChangePlanRequest
makeLenses ''ChangeDocs
makeLenses ''Widths

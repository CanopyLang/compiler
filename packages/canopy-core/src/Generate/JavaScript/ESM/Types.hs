{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Types for ESM (ES Module) output generation.
--
-- Defines the data structures used to represent per-module ESM output,
-- module bundles for graph partitioning, and the complete ESM output
-- structure.
--
-- @since 0.20.0
module Generate.JavaScript.ESM.Types
  ( -- * Output Types
    ESMOutput (..),
    eoRuntime,
    eoModules,
    eoFFIModules,
    eoEntry,

    -- * Module Bundle Types
    ModuleBundle (..),
    mbHome,
    mbGlobals,
    mbExternalDeps,
    mbKernelDeps,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import Control.Lens.TH (makeLenses)
import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder)
import Data.Map.Strict (Map)
import Data.Set (Set)

-- | Complete ESM output containing all generated files.
--
-- Each field represents a separate output file or group of files
-- that together form a working ES module application.
--
-- @since 0.20.0
data ESMOutput = ESMOutput
  { -- | @canopy-runtime.js@ — runtime primitives as ESM exports
    _eoRuntime :: !Builder,
    -- | Per-module @.js@ files keyed by canonical module name
    _eoModules :: !(Map ModuleName.Canonical Builder),
    -- | Per-FFI @.js@ files keyed by alias path
    _eoFFIModules :: !(Map String Builder),
    -- | @main.js@ entry point that imports and starts the app
    _eoEntry :: !Builder
  }

-- | A partition of the global graph for a single Canopy module.
--
-- Groups all globals belonging to a module together with their
-- external dependencies (globals from other modules) and kernel
-- function references.
--
-- @since 0.20.0
data ModuleBundle = ModuleBundle
  { -- | The canonical module name this bundle belongs to
    _mbHome :: !ModuleName.Canonical,
    -- | Globals defined in this module with their node definitions
    _mbGlobals :: !(Map Name.Name Opt.Node),
    -- | Globals from other modules that this module depends on
    _mbExternalDeps :: !(Set Opt.Global),
    -- | Kernel\/runtime function names needed by this module
    _mbKernelDeps :: !(Set ByteString)
  }

makeLenses ''ESMOutput
makeLenses ''ModuleBundle

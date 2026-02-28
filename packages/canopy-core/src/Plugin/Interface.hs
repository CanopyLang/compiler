{-# LANGUAGE OverloadedStrings #-}

-- | Compiler plugin interface definitions.
--
-- Provides the core types for the Canopy compiler plugin system.  Plugins
-- register transformations at specific compiler phases and are executed
-- by the 'Plugin.Pipeline' module during compilation.
--
-- == Phases
--
-- Plugins operate at one of four compiler phases, each receiving and
-- producing a specific AST representation:
--
-- 1. 'AfterParse' -- Source AST transformations
-- 2. 'AfterCanonicalize' -- Canonical AST transformations
-- 3. 'AfterOptimize' -- Optimized AST transformations
-- 4. 'CustomLint' -- Lint-phase analysis producing warnings
--
-- == Error Handling
--
-- All plugin transformations return @'Either' 'PluginError'@ so that
-- plugin failures produce actionable error messages without crashing
-- the compiler.
--
-- @since 0.19.2
module Plugin.Interface
  ( -- * Plugin Type
    Plugin (..),
    PluginPhase (..),
    PluginTransform (..),

    -- * Errors
    PluginError (..),
    PluginWarning (..),

    -- * Plugin Metadata
    PluginMeta (..),
  )
where

import qualified Data.Text as Text

-- | Compiler phases where plugins can hook.
--
-- @since 0.19.2
data PluginPhase
  = -- | After parsing: access to the raw source AST.
    AfterParse
  | -- | After name resolution and canonicalization.
    AfterCanonicalize
  | -- | After optimization passes.
    AfterOptimize
  | -- | Custom lint analysis phase (produces warnings, no AST mutation).
    CustomLint
  deriving (Eq, Show, Ord)

-- | A compiler plugin with its metadata and transformation.
--
-- @since 0.19.2
data Plugin = Plugin
  { _pluginMeta :: !PluginMeta,
    _pluginPhase :: !PluginPhase,
    _pluginTransform :: !PluginTransform
  }

-- | Plugin metadata for identification and version tracking.
--
-- @since 0.19.2
data PluginMeta = PluginMeta
  { _pluginName :: !Text.Text,
    _pluginVersion :: !Text.Text,
    _pluginDescription :: !Text.Text
  }
  deriving (Eq, Show)

-- | Plugin transformation types.
--
-- Each constructor corresponds to a 'PluginPhase' and operates on
-- the appropriate AST representation.  Plugins are opaque functions
-- that receive an input and either produce a transformed output or
-- a 'PluginError'.
--
-- The transformation functions use @()@ as the AST type placeholder.
-- When the plugin system is integrated into the compiler pipeline,
-- these will be parameterized over the actual AST types.
--
-- @since 0.19.2
data PluginTransform
  = -- | Transform the source AST after parsing.
    SourceTransform (PluginAction ())
  | -- | Transform the canonical AST after name resolution.
    CanonicalTransform (PluginAction ())
  | -- | Transform the optimized AST.
    OptimizedTransform (PluginAction ())
  | -- | Produce lint warnings without modifying the AST.
    LintAnalysis (LintAction ())

-- | A plugin transformation action.
--
-- @since 0.19.2
type PluginAction a = a -> Either PluginError a

-- | A lint analysis action producing warnings.
--
-- @since 0.19.2
type LintAction a = a -> Either PluginError [PluginWarning]

-- | Errors produced by plugins.
--
-- @since 0.19.2
data PluginError = PluginError
  { _errorPlugin :: !Text.Text,
    _errorMessage :: !Text.Text,
    _errorDetails :: !(Maybe Text.Text)
  }
  deriving (Eq, Show)

-- | Warnings produced by lint plugins.
--
-- @since 0.19.2
data PluginWarning = PluginWarning
  { _warningPlugin :: !Text.Text,
    _warningMessage :: !Text.Text,
    _warningLocation :: !(Maybe Text.Text)
  }
  deriving (Eq, Show)

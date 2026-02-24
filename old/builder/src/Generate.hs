{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Code generation coordination for the Canopy compiler.
--
-- This module provides the main entry points for code generation,
-- coordinating between object loading, type extraction, validation,
-- and JavaScript generation for different build modes.
--
-- === Build Modes
--
-- * Debug: Full type information for debugging
-- * Development: Fast compilation without optimization
-- * Production: Optimized code with minification
-- * REPL: Interactive evaluation support
--
-- === Generation Pipeline
--
-- @
-- Build.Artifacts -> Objects -> GlobalGraph -> JavaScript
-- @
--
-- === Usage Examples
--
-- @
-- -- Generate debug build with type information
-- result <- debug root details artifacts
--
-- -- Generate optimized production build
-- result <- prod root details artifacts
--
-- -- Generate for REPL evaluation
-- result <- repl root details ansi replArtifacts name
-- @
--
-- === Error Handling
--
-- All generation functions return Task types that can fail with
-- appropriate generation errors for troubleshooting.
--
-- @since 0.19.1
module Generate
  ( -- * Generation Functions
    debug
  , dev
  , prod
  , prodElmCompatible
  , repl
    -- * Configuration Types
  , ReplConfig(..)
    -- * Re-exports from sub-modules
  , module Generate.Types
  , module Generate.Objects
  , module Generate.Validation
  , module Generate.Mains
  ) where

import qualified Build
import qualified Canopy.Details as Details
import Control.Lens (makeLenses, (^.))
import Data.ByteString.Builder (Builder)
import Data.Map ((!))  -- Map unused until FFI info is properly collected
import qualified Data.Name as N
import qualified Generate.JavaScript as JS
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import qualified Generate.Objects as Objects
import qualified Generate.Validation as Validation
import qualified Generate.Mains as Mains
-- Re-export sub-modules
import Generate.Types
import Generate.Objects
import Generate.Validation
import Generate.Mains

-- | Configuration for REPL code generation.
--
-- Groups REPL-specific generation parameters to maintain
-- function parameter limits while preserving clarity.
--
-- @since 0.19.1
data ReplConfig = ReplConfig
  { _replConfigAnsi :: !Bool
    -- ^ Whether to use ANSI color codes in output
  , _replConfigName :: !N.Name
    -- ^ Name of the expression to evaluate
  } deriving (Eq, Show)

-- Generate lenses for ReplConfig
makeLenses ''ReplConfig

-- | Generate debug build with full type information.
--
-- This function generates JavaScript code with complete type information
-- for debugging purposes. The debug build includes all type annotations
-- and maintains full symbol information for development tools.
--
-- === Parameters
--
-- * 'root': Root directory for the project
-- * 'details': Project details and configuration
-- * 'artifacts': Build artifacts containing modules and interfaces
--
-- === Returns
--
-- A Task containing the generated JavaScript as a Builder.
--
-- === Generation Process
--
-- 1. Load objects and types concurrently
-- 2. Finalize loaded objects
-- 3. Create development mode with type information
-- 4. Generate JavaScript with debug symbols
--
-- === Examples
--
-- @
-- result <- debug root details artifacts
-- case result of
--   Right js -> writeBuilder outputPath js
--   Left err -> reportError err
-- @
--
-- === Error Conditions
--
-- Returns Task failure for:
--
-- * Missing or corrupted object files
-- * Interface loading failures
-- * Type extraction errors
-- * JavaScript generation errors
--
-- @since 0.19.1
debug :: FilePath -> Details.Details -> Build.Artifacts -> Task Builder
debug root details (Build.Artifacts pkg _ roots modules ffiInfo) = do
  loading <- Objects.loadObjects root details modules
  objects <- Objects.finalizeObjects loading
  let mode = Mode.Dev Nothing True  -- Elm-compatible mode without debug info
  let graph = Objects.objectsToGlobalGraph objects
  let mains = Mains.gatherMains pkg objects roots
  return $ JS.generate mode graph mains ffiInfo

-- | Generate development build without type information.
--
-- This function generates JavaScript code optimized for development
-- speed without full type information. Faster than debug mode while
-- maintaining readability.
--
-- === Parameters
--
-- * 'root': Root directory for the project
-- * 'details': Project details and configuration
-- * 'artifacts': Build artifacts containing modules and roots
--
-- === Returns
--
-- A Task containing the generated JavaScript as a Builder.
--
-- === Examples
--
-- @
-- result <- dev root details artifacts
-- case result of
--   Right js -> writeBuilder outputPath js
--   Left err -> reportError err
-- @
--
-- === Error Conditions
--
-- Returns Task failure for:
--
-- * Object loading failures
-- * Missing module files
-- * JavaScript generation errors
--
-- @since 0.19.1
dev :: FilePath -> Details.Details -> Build.Artifacts -> Task Builder
dev root details (Build.Artifacts pkg _ roots modules ffiInfo) = do
  objects <- Objects.loadObjects root details modules >>= Objects.finalizeObjects
  let mode = Mode.Dev Nothing False  -- Use Canopy mode, not elm-compatible mode
  let graph = Objects.objectsToGlobalGraph objects
  let mains = Mains.gatherMains pkg objects roots
  return $ JS.generate mode graph mains ffiInfo

-- | Generate optimized production build.
--
-- This function generates highly optimized JavaScript code suitable
-- for production deployment. Includes minification, dead code elimination,
-- and field name shortening.
--
-- === Parameters
--
-- * 'root': Root directory for the project
-- * 'details': Project details and configuration
-- * 'artifacts': Build artifacts containing modules and roots
--
-- === Returns
--
-- A Task containing the optimized JavaScript as a Builder.
--
-- === Validation
--
-- Validates that no debug statements are present before optimization.
--
-- === Examples
--
-- @
-- result <- prod root details artifacts
-- case result of
--   Right js -> writeBuilder outputPath js
--   Left err -> reportError err
-- @
--
-- === Error Conditions
--
-- Returns Task failure for:
--
-- * Debug statements found in code (GenerateCannotOptimizeDebugValues)
-- * Object loading failures
-- * Missing module files
-- * JavaScript generation errors
--
-- @since 0.19.1
prod :: FilePath -> Details.Details -> Build.Artifacts -> Task Builder
prod root details (Build.Artifacts pkg _ roots modules ffiInfo) = do
  objects <- Objects.loadObjects root details modules >>= Objects.finalizeObjects
  Validation.checkForDebugUses objects
  let graph = Objects.objectsToGlobalGraph objects
  let mode = Mode.Prod (Mode.shortenFieldNames graph) False StringPool.emptyPool
  let mains = Mains.gatherMains pkg objects roots
  return $ JS.generate mode graph mains ffiInfo

-- | Generate optimized production build with Elm compatibility.
--
-- This function generates highly optimized JavaScript code that is
-- compatible with Elm's output format, suitable for golden tests
-- and comparison with Elm compiler output.
--
-- === Parameters
--
-- * 'root': Root directory for the project
-- * 'details': Project details and configuration
-- * 'artifacts': Build artifacts containing modules and roots
--
-- === Returns
--
-- A Task containing the optimized elm-compatible JavaScript as a Builder.
--
-- @since 0.19.1
prodElmCompatible :: FilePath -> Details.Details -> Build.Artifacts -> Task Builder
prodElmCompatible root details (Build.Artifacts pkg _ roots modules ffiInfo) = do
  objects <- Objects.loadObjects root details modules >>= Objects.finalizeObjects
  Validation.checkForDebugUses objects
  let graph = Objects.objectsToGlobalGraph objects
  let mode = Mode.Prod (Mode.shortenFieldNames graph) True StringPool.emptyPool
  let mains = Mains.gatherMains pkg objects roots
  return $ JS.generate mode graph mains ffiInfo

-- | Generate code for REPL evaluation.
--
-- This function generates JavaScript code optimized for interactive
-- evaluation in the REPL environment, supporting dynamic loading
-- and evaluation of expressions.
--
-- === Parameters
--
-- * 'root': Root directory for the project
-- * 'details': Project details and configuration
-- * 'config': REPL configuration (ANSI mode and expression name)
-- * 'replArtifacts': REPL-specific artifacts and annotations
--
-- === Returns
--
-- A Task containing the REPL JavaScript as a Builder.
--
-- === Examples
--
-- @
-- let config = ReplConfig True exprName
-- result <- repl root details config replArtifacts
-- case result of
--   Right js -> evaluateInRepl js
--   Left err -> reportError err
-- @
--
-- === Error Conditions
--
-- Returns Task failure for:
--
-- * Object loading failures
-- * Missing REPL artifacts
-- * Expression annotation errors
-- * JavaScript generation errors
--
-- @since 0.19.1
repl :: FilePath -> Details.Details -> ReplConfig -> Build.ReplArtifacts -> Task Builder
repl root details config (Build.ReplArtifacts home modules localizer annotations) = do
  objects <- Objects.loadObjects root details modules >>= Objects.finalizeObjects
  let graph = Objects.objectsToGlobalGraph objects
  return $ JS.generateForRepl ansi localizer graph home name (annotations ! name)
  where
    ansi = config ^. replConfigAnsi
    name = config ^. replConfigName

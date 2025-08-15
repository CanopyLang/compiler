{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall -fno-warn-unused-do-bind #-}

-- | Core compilation pipeline for Canopy modules.
--
-- This module orchestrates the complete compilation process from source AST
-- to optimized artifacts. It coordinates multiple compilation phases including
-- canonicalization, type checking, pattern match validation, and optimization.
--
-- == Compilation Pipeline
--
-- The compilation process follows these sequential phases:
--
-- 1. **Canonicalization** - Resolve names and validate module structure
-- 2. **Type Checking** - Infer and validate types with constraint solving
-- 3. **Pattern Validation** - Ensure exhaustive pattern match coverage
-- 4. **Optimization** - Generate optimized intermediate representation
--
-- == Usage Examples
--
-- @
-- import qualified Compile
-- import qualified Canopy.Package as Pkg
-- import qualified AST.Source as Src
--
-- -- Compile a source module
-- compileModule :: Pkg.Name -> Interfaces -> Src.Module -> Either Error Artifacts
-- compileModule pkg ifaces sourceModule =
--   Compile.compile pkg ifaces sourceModule
-- @
--
-- == Error Handling
--
-- All compilation phases use 'Either' for error propagation with rich error types:
--   * 'E.BadNames' - Canonicalization failures (undefined names, scope errors)
--   * 'E.BadTypes' - Type checking failures (type mismatches, constraint violations)
--   * 'E.BadPatterns' - Pattern match failures (non-exhaustive patterns)
--   * 'E.BadMains' - Optimization failures (invalid main functions)
--
-- @since 0.19.1
module Compile
  ( -- * Core Types
    Artifacts (..),

    -- * Compilation Interface
    compile,

    -- * Lens Accessors
    artifactsModule,
    artifactsTypes,
    artifactsGraph,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canonicalize.Module as Canonicalize
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens (makeLenses)
import Data.Map (Map)
import qualified Data.Name as Name
import qualified Nitpick.PatternMatches as PatternMatches
import qualified Optimize.Module as Optimize
import qualified Reporting.Error as E
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Reporting.Result as R
import System.IO.Unsafe (unsafePerformIO)
import qualified Type.Constrain.Module as Type
import qualified Type.Solve as Type

-- | Compilation artifacts containing all outputs from the compilation pipeline.
--
-- The 'Artifacts' type encapsulates the complete result of successfully compiling
-- a source module through all compilation phases. Each field represents the output
-- of a specific compilation stage.
--
-- == Field Documentation
--
-- * '_artifactsModule' - Canonicalized AST with resolved names and validated structure
-- * '_artifactsTypes' - Type annotations for all definitions in the module
-- * '_artifactsGraph' - Optimized local dependency graph for code generation
--
-- == Usage Examples
--
-- @
-- import Control.Lens ((^.))
--
-- -- Access compilation artifacts using lenses
-- processArtifacts :: Artifacts -> IO ()
-- processArtifacts artifacts = do
--   let canonical = artifacts ^. artifactsModule
--       typeMap = artifacts ^. artifactsTypes
--       optimized = artifacts ^. artifactsGraph
--   -- Process each artifact...
-- @
--
-- @since 0.19.1
data Artifacts = Artifacts
  { _artifactsModule :: !Can.Module,
    _artifactsTypes :: !(Map Name.Name Can.Annotation),
    _artifactsGraph :: !Opt.LocalGraph
  }

-- | Generate lens accessors for Artifacts record fields.
--
-- Creates the following lenses:
--   * 'artifactsModule' - Access the canonicalized module
--   * 'artifactsTypes' - Access the type annotation map
--   * 'artifactsGraph' - Access the optimized dependency graph
--
-- @since 0.19.1
makeLenses ''Artifacts

-- | Compile a source module through the complete compilation pipeline.
--
-- Orchestrates all compilation phases in sequence, ensuring each phase
-- completes successfully before proceeding to the next. The compilation
-- process is pure and deterministic - the same input will always produce
-- the same output or the same error.
--
-- == Compilation Phases
--
-- 1. **Canonicalization** - Resolves names, validates imports, and creates canonical AST
-- 2. **Type Checking** - Infers types and validates type constraints
-- 3. **Pattern Validation** - Ensures pattern matches are exhaustive and non-redundant
-- 4. **Optimization** - Generates optimized intermediate representation
--
-- == Examples
--
-- >>> import qualified Canopy.Package as Pkg
-- >>> import qualified Data.Map as Map
-- >>> compile Pkg.core Map.empty sourceModule
-- Right (Artifacts {...})
--
-- >>> compile invalidPkg interfaces malformedModule
-- Left (E.BadNames [...])
--
-- == Error Conditions
--
-- Returns 'Left' with specific error types for each phase:
--   * 'E.BadNames' - Undefined variables, invalid imports, scope violations
--   * 'E.BadTypes' - Type mismatches, constraint failures, infinite types
--   * 'E.BadPatterns' - Non-exhaustive patterns, redundant patterns
--   * 'E.BadMains' - Invalid main function, optimization failures
--
-- @since 0.19.1
compile ::
  -- | Package name for the module being compiled
  Pkg.Name ->
  -- | Available module interfaces for dependency resolution
  Map ModuleName.Raw I.Interface ->
  -- | Source module to compile
  Src.Module ->
  -- | Compilation artifacts or error
  Either E.Error Artifacts
compile pkg ifaces modul = do
  canonical <- canonicalize pkg ifaces modul
  annotations <- typeCheck modul canonical
  () <- nitpick canonical
  objects <- optimize modul annotations canonical
  return (Artifacts canonical annotations objects)

-- COMPILATION PHASES
--
-- Each phase represents a distinct transformation in the compilation pipeline.
-- Phases are kept as internal functions to maintain clean separation of concerns
-- while providing focused error handling for each compilation stage.

-- | Transform source AST to canonical AST with resolved names.
--
-- Canonicalization resolves all names to their definitions, validates import
-- statements, and ensures all referenced symbols are available. This phase
-- catches undefined variable errors and import-related issues.
--
-- == Process
--
-- 1. Resolve all name references to their definitions
-- 2. Validate import statements and exposed symbols
-- 3. Build canonical AST with fully qualified names
-- 4. Detect circular dependencies and scope violations
--
-- == Error Cases
--
-- * Undefined variables or functions
-- * Invalid import statements
-- * Circular module dependencies
-- * Name shadowing violations
-- * Scope resolution failures
--
-- @since 0.19.1
canonicalize ::
  -- | Package context for name resolution
  Pkg.Name ->
  -- | Available module interfaces
  Map ModuleName.Raw I.Interface ->
  -- | Source module to canonicalize
  Src.Module ->
  -- | Canonical module or canonicalization errors
  Either E.Error Can.Module
canonicalize pkg ifaces modul =
  case snd . R.run $ Canonicalize.canonicalize pkg ifaces modul of
    Right canonical -> Right canonical
    Left errors -> Left $ E.BadNames errors

-- | Perform type inference and checking on canonical AST.
--
-- Type checking generates type constraints from the canonical AST and solves
-- them to produce type annotations for all definitions. This phase catches
-- type errors, constraint violations, and ensures type safety.
--
-- == Process
--
-- 1. Generate type constraints from canonical AST expressions
-- 2. Solve constraint system using unification and subtyping
-- 3. Produce type annotations mapping names to their inferred types
-- 4. Validate type correctness and detect infinite types
--
-- == Error Cases
--
-- * Type mismatches between expected and actual types
-- * Unsolvable type constraints
-- * Infinite or recursive type definitions
-- * Missing type class instances
-- * Constraint solver failures
--
-- @since 0.19.1
typeCheck ::
  -- | Original source module for error localization
  Src.Module ->
  -- | Canonical module to type check
  Can.Module ->
  -- | Type annotations or type errors
  Either E.Error (Map Name.Name Can.Annotation)
typeCheck modul canonical =
  case unsafePerformIO (Type.constrain canonical >>= Type.run) of
    Right annotations -> Right annotations
    Left errors -> Left (E.BadTypes (Localizer.fromModule modul) errors)

-- | Validate pattern match exhaustiveness and detect redundant patterns.
--
-- Pattern validation ensures that all pattern matches are exhaustive (cover
-- all possible cases) and contain no redundant or unreachable patterns. This
-- prevents runtime pattern match failures and warns about dead code.
--
-- == Process
--
-- 1. Analyze all pattern matches in the canonical AST
-- 2. Check exhaustiveness using decision tree construction
-- 3. Detect redundant or unreachable patterns
-- 4. Validate guard conditions and boolean patterns
--
-- == Error Cases
--
-- * Non-exhaustive pattern matches (missing cases)
-- * Redundant patterns that will never be reached
-- * Overlapping patterns with same precedence
-- * Invalid guard conditions in patterns
--
-- @since 0.19.1
nitpick ::
  -- | Canonical module to validate patterns in
  Can.Module ->
  -- | Success or pattern match errors
  Either E.Error ()
nitpick canonical =
  case PatternMatches.check canonical of
    Right () -> Right ()
    Left errors -> Left (E.BadPatterns errors)

-- | Generate optimized intermediate representation for code generation.
--
-- Optimization transforms the canonical AST into an optimized local dependency
-- graph suitable for efficient code generation. This phase performs various
-- optimizations while preserving semantic correctness.
--
-- == Process
--
-- 1. Transform canonical AST to optimized intermediate representation
-- 2. Apply dead code elimination and inlining optimizations
-- 3. Build local dependency graph for efficient code generation
-- 4. Validate main function signatures and entry points
--
-- == Error Cases
--
-- * Invalid main function signatures
-- * Optimization failures that break semantics
-- * Circular dependencies in optimization graph
-- * Code generation preparation failures
--
-- @since 0.19.1
optimize ::
  -- | Original source module for error localization
  Src.Module ->
  -- | Type annotations from type checking phase
  Map Name.Name Can.Annotation ->
  -- | Canonical module to optimize
  Can.Module ->
  -- | Optimized dependency graph or optimization errors
  Either E.Error Opt.LocalGraph
optimize modul annotations canonical =
  case snd . R.run $ Optimize.optimize annotations canonical of
    Right localGraph -> Right localGraph
    Left errors -> Left (E.BadMains (Localizer.fromModule modul) errors)

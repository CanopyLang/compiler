{-# LANGUAGE OverloadedStrings #-}

-- | AST.Canonical - Canonicalized AST after name resolution and type inference preparation
--
-- This module defines the Canonical AST representation used after the canonicalization
-- phase. Canonical AST differs from Source AST by having all names fully resolved to
-- their home modules, imports processed, and additional cached information for efficient
-- type inference and optimization.
--
-- The canonicalization process transforms the Source AST by:
-- * Resolving all qualified names to their canonical module homes
-- * Processing import declarations and exposing lists
-- * Caching metadata needed for later compiler phases
-- * Validating scoping and basic semantic constraints
--
-- == Key Features
--
-- * **Name Resolution** - All variables resolved to canonical module locations
-- * **Import Processing** - Imports resolved and scoping validated
-- * **Metadata Caching** - Performance data cached for later phases
-- * **Type Preparation** - AST prepared for efficient type inference
-- * **Optimization Ready** - Structure optimized for compiler transformations
--
-- == Architecture
--
-- The Canonical AST builds on Source AST with these enhancements:
--
-- * 'Expr' - Expressions with resolved names and cached type annotations
-- * 'Pattern' - Patterns with constructor metadata and exhaustiveness info
-- * 'Type' - Types with resolved names and alias expansion support
-- * 'Module' - Modules with processed imports and resolved exports
-- * 'Def' - Definitions with scope resolution and type preparation
--
-- Each construct includes caching annotations marked with "CACHE" comments
-- explaining what data is cached and why it improves performance.
--
-- == Module Structure
--
-- Type definitions live in "AST.Canonical.Types". Serialization instances are
-- defined in "AST.Canonical.Binary" and "AST.Canonical.Json". This module
-- re-exports everything for backward compatibility.
--
-- Focused sub-module imports are available:
--
-- * "AST.Canonical.Expr" - Expression types only
-- * "AST.Canonical.Module" - Module structure types only
--
-- == Caching Strategy
--
-- The Canonical AST aggressively caches information to avoid expensive lookups
-- in later compiler phases:
--
-- * **Type Information** - For efficient type inference (marked "CACHE for inference")
-- * **Constructor Data** - For exhaustiveness checking (marked "CACHE for exhaustiveness")
-- * **Optimization Hints** - For code generation (marked "CACHE for optimization")
-- * **Module Metadata** - For dependency analysis and linking
--
-- This caching strategy transforms O(log n) dictionary lookups into O(1) field access.
--
-- == Usage Examples
--
-- === Variable Resolution
--
-- @
-- -- Source AST: VarQual LowVar "List" "map"
-- -- Canonical AST: VarForeign (Canonical Package.core "List") "map" annotation
--
-- -- Local variable remains: VarLocal "x"
-- -- Top-level becomes: VarTopLevel home "myFunction"
-- @
--
-- === Constructor Patterns
--
-- @
-- -- Canonical pattern with cached metadata
-- let maybePattern = PCtor
--   { _p_home = ModuleName.Canonical Package.core "Maybe"
--   , _p_type = "Maybe"
--   , _p_union = cachedUnionInfo  -- CACHE for exhaustiveness
--   , _p_name = "Just"
--   , _p_index = Index.first      -- CACHE for code generation
--   , _p_args = [PatternCtorArg Index.first typeInfo argPattern]
--   }
-- @
--
-- === Module Structure
--
-- @
-- -- Complete canonical module
-- let canonicalModule = Module
--   { _name = ModuleName.Canonical package "MyModule"
--   , _exports = processedExports
--   , _docs = preservedDocs
--   , _decls = optimizedDeclarations
--   , _unions = resolvedUnions
--   , _aliases = expandedAliases
--   , _binops = resolvedOperators
--   , _effects = processedEffects
--   }
-- @
--
-- == Error Handling
--
-- Canonical AST assumes successful canonicalization - any name resolution
-- or scoping errors should be caught during the canonicalization phase.
-- The canonical representation should be internally consistent.
--
-- == Performance Characteristics
--
-- * **Memory Usage**: Higher than Source AST due to cached metadata
-- * **Construction**: O(n * log m) where n = nodes, m = module scope size
-- * **Access**: O(1) for most cached lookups vs O(log n) dictionary access
-- * **Type Inference**: Significantly faster due to pre-cached type information
--
-- == Thread Safety
--
-- All Canonical AST types are immutable and thread-safe. The cached metadata
-- is computed during canonicalization and remains constant thereafter.
--
-- @since 0.19.1
module AST.Canonical
  ( Expr,
    Expr_ (..),
    CaseBranch (..),
    FieldUpdate (..),
    CtorOpts (..),
    -- operators
    ArithOp (..),
    BinopKind (..),
    -- definitions
    Def (..),
    Decls (..),
    -- patterns
    Pattern,
    Pattern_ (..),
    PatternCtorArg (..),
    -- types
    Annotation (..),
    Type (..),
    AliasType (..),
    FieldType (..),
    fieldsToList,
    -- modules
    Module (..),
    Alias (..),
    Binop (..),
    Union (..),
    Ctor (..),
    Exports (..),
    Export (..),
    Effects (..),
    Port (..),
    Manager (Cmd, SubManager, Fx),
  )
where

import AST.Canonical.Binary ()
import AST.Canonical.Json ()
import AST.Canonical.Types
  ( Alias (..),
    AliasType (..),
    Annotation (..),
    ArithOp (..),
    BinopKind (..),
    CaseBranch (..),
    Ctor (..),
    CtorOpts (..),
    Decls (..),
    Def (..),
    Effects (..),
    Export (..),
    Exports (..),
    Expr,
    Expr_ (..),
    FieldType (..),
    FieldUpdate (..),
    Manager (Cmd, Fx, SubManager),
    Module (..),
    Pattern,
    Pattern_ (..),
    PatternCtorArg (..),
    Port (..),
    Type (..),
    Union (..),
    Binop (..),
    fieldsToList,
  )

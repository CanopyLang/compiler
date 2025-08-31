{-# OPTIONS_GHC -Wall #-}

-- | AST.Utils.Type - Type manipulation utilities for canonical types
--
-- This module provides essential utilities for manipulating and analyzing
-- canonical type representations. These functions are used throughout the
-- compiler for type inference, alias resolution, and type checking operations.
--
-- The utilities handle the complexities of type aliases, lambda types, and
-- nested type structures, providing clean interfaces for common type
-- manipulation patterns.
--
-- == Key Features
--
-- * **Lambda Deconstruction** - Extract function argument types from lambda chains
-- * **Alias Resolution** - Substitute type parameters in alias definitions
-- * **Deep Alias Expansion** - Recursively expand all aliases in type trees
-- * **Iterated Expansion** - Follow alias chains to their final resolved types
--
-- == Architecture
--
-- The module provides several levels of type manipulation:
--
-- * 'delambda' - Flattens function types into argument lists
-- * 'dealias' - Performs single-level alias parameter substitution
-- * 'deepDealias' - Recursively expands all aliases in a type
-- * 'iteratedDealias' - Follows alias chains to final concrete types
--
-- Each function handles the recursive structure of types while preserving
-- type correctness and maintaining performance.
--
-- == Usage Examples
--
-- === Lambda Type Deconstruction
--
-- @
-- -- Extract argument types from function type
-- let funcType = TLambda intType (TLambda stringType boolType)
-- let argTypes = delambda funcType
-- -- Result: [intType, stringType, boolType]
-- @
--
-- === Type Alias Resolution
--
-- @
-- -- Resolve type alias with parameters
-- let aliasArgs = [("a", intType), ("b", stringType)]
-- let aliasBody = Holey (TRecord [("x", TVar "a"), ("y", TVar "b")] Nothing)
-- let resolved = dealias aliasArgs aliasBody
-- -- Result: TRecord [("x", intType), ("y", stringType)] Nothing
-- @
--
-- === Deep Alias Expansion
--
-- @
-- -- Recursively expand all aliases in complex type
-- let complexType = TType home "MyAlias" [TType home "OtherAlias" []]
-- let expanded = deepDealias complexType
-- -- Result: All aliases expanded to their concrete types
-- @
--
-- === Iterative Alias Following
--
-- @
-- -- Follow alias chain to final type
-- let chainedAlias = TAlias home "First" [] (Holey (TAlias home "Second" [] ...))
-- let finalType = iteratedDealias chainedAlias
-- -- Result: The final concrete type after following all aliases
-- @
--
-- == Error Handling
--
-- All functions in this module are total and handle malformed types gracefully:
--
-- * Missing type variables in alias substitution use defaults
-- * Circular aliases are handled by alias type structure
-- * Malformed type trees are preserved rather than causing errors
--
-- == Performance Characteristics
--
-- * **Lambda Deconstruction**: O(n) where n is function arity
-- * **Alias Resolution**: O(m * k) where m = type size, k = substitutions
-- * **Deep Expansion**: O(n * d) where n = type size, d = nesting depth
-- * **Iteration**: O(c) where c = alias chain length
--
-- == Thread Safety
--
-- All functions are pure and thread-safe. Type manipulation can be performed
-- concurrently across multiple threads without synchronization.
--
-- @since 0.19.1
module AST.Utils.Type
  ( delambda,
    dealias,
    deepDealias,
    iteratedDealias,
  )
where

import AST.Canonical (AliasType (..), FieldType (..), Type (..))
import qualified Data.Map as Map
import qualified Data.Name as Name

-- DELAMBDA

-- | Deconstruct a function type into its argument types.
--
-- Flattens a chain of lambda types into a list of argument types followed
-- by the final result type. This is useful for analyzing function signatures
-- and understanding function arity.
--
-- The function handles arbitrarily nested lambda types and preserves the
-- order of arguments as they appear in the type signature.
--
-- ==== Examples
--
-- >>> delambda intType
-- [intType]
--
-- >>> delambda (TLambda stringType intType)
-- [stringType, intType]
--
-- >>> delambda (TLambda intType (TLambda stringType boolType))
-- [intType, stringType, boolType]
--
-- @since 0.19.1
delambda :: Type -> [Type]
delambda tipe =
  case tipe of
    TLambda arg result ->
      arg : delambda result
    _ ->
      [tipe]

-- DEALIAS

-- | Resolve type alias by substituting parameters.
--
-- Performs parameter substitution in type alias definitions, replacing
-- type variables with their concrete type arguments. Handles both "holey"
-- aliases (requiring substitution) and "filled" aliases (already resolved).
--
-- For holey aliases, performs a complete traversal of the type structure
-- to substitute all occurrences of type variables. For filled aliases,
-- returns the already-resolved type directly.
--
-- ==== Examples
--
-- >>> let args = [("a", intType), ("b", stringType)]
-- >>> let holey = Holey (TRecord [("x", TVar "a")] Nothing)
-- >>> dealias args holey
-- TRecord [("x", intType)] Nothing
--
-- >>> let filled = Filled concreteType
-- >>> dealias args filled
-- concreteType
--
-- @since 0.19.1
dealias :: [(Name.Name, Type)] -> AliasType -> Type
dealias args aliasType =
  case aliasType of
    Holey tipe ->
      dealiasHelp (Map.fromList args) tipe
    Filled tipe ->
      tipe

dealiasHelp :: Map.Map Name.Name Type -> Type -> Type
dealiasHelp typeTable tipe =
  case tipe of
    TLambda a b ->
      TLambda
        (dealiasHelp typeTable a)
        (dealiasHelp typeTable b)
    TVar x ->
      Map.findWithDefault tipe x typeTable
    TRecord fields ext ->
      TRecord (Map.map (dealiasField typeTable) fields) ext
    TAlias home name args t' ->
      TAlias home name (fmap (fmap (dealiasHelp typeTable)) args) t'
    TType home name args ->
      TType home name (fmap (dealiasHelp typeTable) args)
    TUnit ->
      TUnit
    TTuple a b maybeC ->
      TTuple
        (dealiasHelp typeTable a)
        (dealiasHelp typeTable b)
        (fmap (dealiasHelp typeTable) maybeC)

dealiasField :: Map.Map Name.Name Type -> FieldType -> FieldType
dealiasField typeTable (FieldType index tipe) =
  FieldType index (dealiasHelp typeTable tipe)

-- DEEP DEALIAS

-- | Recursively expand all type aliases in a type tree.
--
-- Performs deep expansion of all type aliases within a type structure,
-- recursively processing nested types and expanding aliases at every level.
-- This produces a type representation with all aliases fully resolved.
--
-- The function preserves the overall type structure while expanding aliases
-- in-place. It handles complex nested structures including records, tuples,
-- and parameterized types.
--
-- ==== Examples
--
-- >>> let aliasType = TAlias home "List" [("a", intType)] (Holey listDef)
-- >>> deepDealias aliasType
-- -- Result: listDef with "a" substituted with intType
--
-- >>> let recordWithAlias = TRecord [("field", aliasType)] Nothing
-- >>> deepDealias recordWithAlias
-- -- Result: TRecord [("field", expandedAliasType)] Nothing
--
-- @since 0.19.1
deepDealias :: Type -> Type
deepDealias tipe =
  case tipe of
    TLambda a b ->
      TLambda (deepDealias a) (deepDealias b)
    TVar _ ->
      tipe
    TRecord fields ext ->
      TRecord (Map.map deepDealiasField fields) ext
    TAlias _ _ args tipe' ->
      deepDealias (dealias args tipe')
    TType home name args ->
      TType home name (fmap deepDealias args)
    TUnit ->
      TUnit
    TTuple a b c ->
      TTuple (deepDealias a) (deepDealias b) (fmap deepDealias c)

deepDealiasField :: FieldType -> FieldType
deepDealiasField (FieldType index tipe) =
  FieldType index (deepDealias tipe)

-- ITERATED DEALIAS

-- | Follow alias chains to their final concrete type.
--
-- Repeatedly expands type aliases until a non-alias type is reached,
-- effectively following alias chains to their final destination. This
-- is useful for finding the "true" type behind a series of aliases.
--
-- The function handles alias chains of arbitrary length and stops when
-- it encounters a non-alias type. For non-alias types, returns the
-- input unchanged.
--
-- ==== Examples
--
-- >>> let chainedAlias = TAlias home "A" [] (Holey (TAlias home "B" [] ...))
-- >>> iteratedDealias chainedAlias
-- -- Result: The final concrete type after expanding all aliases
--
-- >>> iteratedDealias intType
-- intType  -- Non-alias types are returned unchanged
--
-- @since 0.19.1
iteratedDealias :: Type -> Type
iteratedDealias tipe =
  case tipe of
    TAlias _ _ args realType ->
      iteratedDealias (dealias args realType)
    _ ->
      tipe

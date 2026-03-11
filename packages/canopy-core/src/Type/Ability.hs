{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Type.Ability - Ability constraint types and resolution for the type system.
--
-- This module provides the data structures and resolution logic for user-defined
-- ability constraints (analogous to type classes). Ability constraints are a
-- user-facing mechanism that coexists with the built-in magic-type constraints
-- (@number@, @comparable@, @appendable@, @compappend@) already handled by the
-- solver — they do not replace those.
--
-- == Overview
--
-- An /ability/ is a named interface that a type can implement:
--
-- @
-- ability Eq a where
--   eq : a -> a -> Bool
-- @
--
-- When the type checker encounters a call to @eq@, it looks up @eq@ in the
-- 'AbilityEnv', discovers it belongs to the @Eq@ ability, and records an
-- 'AbilityConstraint' linking the call-site region and the type variable to
-- that ability.
--
-- After standard unification, 'checkAbilityConstraints' verifies that every
-- accumulated constraint has a matching 'ImplInfo' in the environment.
--
-- == Coexistence with magic types
--
-- The 'AbilityEnv' is consulted only for user-defined names. The built-in
-- super-type machinery (@Number@, @Comparable@, @Appendable@, @CompAppend@) in
-- "Type.Solve" and "Type.Unify" is left completely untouched.
--
-- @since 0.20.0
module Type.Ability
  ( -- * Constraint types
    AbilityConstraint (..),
    AbilityEnv (..),
    AbilityInfo (..),
    ImplInfo (..),
    AbilityError (..),

    -- * Construction
    emptyAbilityEnv,

    -- * Queries
    lookupMethod,
    resolveAbility,

    -- * Validation
    checkAbilityConstraints,
  )
where

import qualified AST.Canonical as Can
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import Type.Type (Type, Variable)

-- ---------------------------------------------------------------------------
-- Core data types
-- ---------------------------------------------------------------------------

-- | A single ability constraint emitted during constraint generation.
--
-- Records that the inferred type at 'Ann.Region' must implement the named
-- ability.  The 'Variable' is the union-find variable that will be resolved
-- to a concrete type by the solver before 'checkAbilityConstraints' is
-- called.
data AbilityConstraint = AbilityConstraint
  { _acAbility :: !Name.Name
  -- ^ The ability that must be satisfied (e.g. @"Eq"@).
  , _acType :: !Variable
  -- ^ The type variable constrained to implement the ability.
  , _acRegion :: !Ann.Region
  -- ^ Source location for error reporting.
  }

-- | The environment of known ability declarations and implementations.
--
-- Constructed during canonicalization and threaded through the type checker.
-- An empty 'AbilityEnv' means no user-defined abilities are in scope, which
-- is the default for all existing modules.
data AbilityEnv = AbilityEnv
  { _aeAbilities :: !(Map.Map Name.Name AbilityInfo)
  -- ^ All declared abilities, keyed by ability name.
  , _aeImpls :: !(Map.Map (Name.Name, Name.Name) ImplInfo)
  -- ^ Concrete implementations, keyed by @(ability, typeName)@.
  }

-- | Static information about a single ability declaration.
--
-- Holds the method signatures and any super-ability requirements.
-- Super-abilities must also be satisfied when this ability is required.
data AbilityInfo = AbilityInfo
  { _aiMethods :: !(Map.Map Name.Name Type)
  -- ^ Map from method name to its type.
  , _aiSuperAbilities :: ![Name.Name]
  -- ^ Names of abilities that must also be satisfied.
  }

-- | A concrete implementation of an ability for a specific type.
--
-- The 'Can.Def' values are the method implementations provided by the user.
data ImplInfo = ImplInfo
  { _iiMethods :: !(Map.Map Name.Name Can.Def)
  -- ^ Map from method name to its implementation definition.
  }

-- | An error produced when an ability constraint cannot be satisfied.
data AbilityError
  = -- | No implementation found for the given ability and type name.
    MissingImpl
      !Name.Name
      -- ^ The ability that was required.
      !Name.Name
      -- ^ The concrete type name for which no implementation exists.
      !Ann.Region
      -- ^ Source location of the constraint.
  | -- | An implementation exists but is missing required methods.
    IncompleteImpl
      !Name.Name
      -- ^ The ability.
      !Name.Name
      -- ^ The type name.
      ![Name.Name]
      -- ^ The method names that are absent from the implementation.

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

-- | Construct an empty 'AbilityEnv' with no declared abilities or impls.
--
-- Used as the default environment for modules that do not define abilities.
--
-- @since 0.20.0
emptyAbilityEnv :: AbilityEnv
emptyAbilityEnv = AbilityEnv
  { _aeAbilities = Map.empty
  , _aeImpls = Map.empty
  }

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

-- | Look up which ability owns a given method name.
--
-- Returns @Just (abilityName, methodType)@ when the name is found as a method
-- in any declared ability, or 'Nothing' when the name is not an ability method.
-- When multiple abilities define the same method name the first match (in
-- alphabetical key order) wins.
--
-- @since 0.20.0
lookupMethod :: AbilityEnv -> Name.Name -> Maybe (Name.Name, Type)
lookupMethod env methodName =
  Map.foldlWithKey' findIn Nothing (_aeAbilities env)
  where
    findIn (Just found) _ _ = Just found
    findIn Nothing abilityName info =
      fmap (\t -> (abilityName, t)) (Map.lookup methodName (_aiMethods info))

-- | Resolve a concrete implementation of an ability for a named type.
--
-- Returns the 'ImplInfo' when an implementation for @(abilityName, typeName)@
-- exists in the environment, otherwise 'Nothing'.
--
-- @since 0.20.0
resolveAbility :: AbilityEnv -> Name.Name -> Name.Name -> Maybe ImplInfo
resolveAbility env abilityName typeName =
  Map.lookup (abilityName, typeName) (_aeImpls env)

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

-- | Check all accumulated ability constraints after type solving.
--
-- For each 'AbilityConstraint' this function looks up the ability and verifies
-- that every registered implementation for it is complete (all declared methods
-- are present).  Constraints for abilities not found in the environment are
-- silently skipped — the constraint may be satisfied externally.
--
-- Returns @Right ()@ when all constraints are satisfied, or @Left errors@
-- with one 'AbilityError' per failed constraint.
--
-- @since 0.20.0
checkAbilityConstraints :: AbilityEnv -> [AbilityConstraint] -> Either [AbilityError] ()
checkAbilityConstraints env constraints =
  case concatMap (checkOne env) constraints of
    [] -> Right ()
    errs -> Left errs

-- | Check a single 'AbilityConstraint', returning any errors found.
checkOne :: AbilityEnv -> AbilityConstraint -> [AbilityError]
checkOne env (AbilityConstraint abilityName _typeVar _region) =
  maybe [] (checkImplsForAbility env abilityName) (Map.lookup abilityName (_aeAbilities env))

-- | Verify that all registered implementations for an ability are complete.
--
-- An implementation is /complete/ when its method map contains every method
-- declared by the ability.  Missing methods produce an 'IncompleteImpl' error.
checkImplsForAbility :: AbilityEnv -> Name.Name -> AbilityInfo -> [AbilityError]
checkImplsForAbility env abilityName info =
  concatMap checkImpl relevantImpls
  where
    relevantImpls =
      [ (typeName, implInfo)
      | ((aName, typeName), implInfo) <- Map.toList (_aeImpls env)
      , aName == abilityName
      ]
    checkImpl (typeName, implInfo) =
      let missing = filter absent (Map.keys (_aiMethods info))
      in if null missing then [] else [IncompleteImpl abilityName typeName missing]
      where
        absent m = not (Map.member m (_iiMethods implInfo))

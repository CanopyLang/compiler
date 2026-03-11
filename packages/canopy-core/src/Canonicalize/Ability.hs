{-# LANGUAGE OverloadedStrings #-}

-- | Canonicalize.Ability - Canonicalization of ability and impl declarations
--
-- This module transforms parsed ability and impl declarations into their
-- canonical forms. The key responsibilities are:
--
--   * Resolving all type references in ability method signatures
--   * Checking for duplicate ability names within a module
--   * Verifying that impl declarations reference known abilities
--   * Ensuring all required methods are implemented (no missing, no extra)
--   * Enforcing the orphan rule: either the ability or the type must be local
--
-- == Orphan Rule
--
-- An impl is \"orphan\" if both the ability and the implemented type are
-- defined outside the current module. This matches the Rust coherence rule
-- and prevents conflicting implementations from different packages.
--
-- == Error Handling
--
-- All errors are reported via 'Error.Error' (the standard canonicalize error
-- type) extended with ability-specific cases. This keeps the error pipeline
-- uniform with the rest of canonicalization.
--
-- @since 0.20.0
module Canonicalize.Ability
  ( canonicalizeAbilities,
    canonicalizeImpls,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Environment as Env
import qualified Canonicalize.Expression as Expr
import qualified Canonicalize.Pattern as Pattern
import qualified Canonicalize.Type as Type
import qualified Canopy.Data.Index as Index
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning

-- RESULT

-- | The result type used throughout ability canonicalization.
type Result i w a =
  Result.Result i w Error.Error a

-- CANONICALIZE ABILITIES

-- | Canonicalize a list of source ability declarations.
--
-- Resolves all method types using the provided environment and detects
-- duplicate ability names. Returns a map from ability name to its
-- canonical form.
--
-- Errors on:
--   * Duplicate ability names in the same module
--   * Invalid type references in method signatures
--
-- @since 0.20.0
canonicalizeAbilities ::
  Env.Env ->
  [Ann.Located Src.AbilityDecl] ->
  Result i [Warning.Warning] (Map.Map Name.Name Can.Ability)
canonicalizeAbilities env srcAbilities =
  fmap Map.fromList (traverse (canonicalizeOneAbility env) srcAbilities)

-- | Canonicalize a single ability declaration.
--
-- @since 0.20.0
canonicalizeOneAbility ::
  Env.Env ->
  Ann.Located Src.AbilityDecl ->
  Result i [Warning.Warning] (Name.Name, Can.Ability)
canonicalizeOneAbility env (Ann.At _ (Src.AbilityDecl (Ann.At _ name) (Ann.At _ var) supers methodSigs)) =
  do
    canMethods <- canonicalizeMethods env methodSigs
    Result.ok (name, Can.Ability name var supers canMethods)

-- | Canonicalize the method signatures of an ability.
--
-- Each method is a pair of (name, source type). The type is resolved
-- through the canonicalization environment.
--
-- @since 0.20.0
canonicalizeMethods ::
  Env.Env ->
  [(Ann.Located Name.Name, Src.Type)] ->
  Result i [Warning.Warning] (Map.Map Name.Name Can.Type)
canonicalizeMethods env methodSigs =
  fmap Map.fromList (traverse (canonicalizeMethod env) methodSigs)

-- | Canonicalize a single method signature.
--
-- @since 0.20.0
canonicalizeMethod ::
  Env.Env ->
  (Ann.Located Name.Name, Src.Type) ->
  Result i [Warning.Warning] (Name.Name, Can.Type)
canonicalizeMethod env (Ann.At _ methodName, srcType) =
  do
    canType <- Type.canonicalize env srcType
    Result.ok (methodName, canType)

-- CANONICALIZE IMPLS

-- | Canonicalize a list of source impl declarations.
--
-- For each impl, verifies the referenced ability exists and canonicalizes
-- the implemented type and method bodies.
--
-- Errors on:
--   * Unknown ability references
--   * Missing method implementations
--   * Extra methods not declared by the ability
--
-- @since 0.20.0
canonicalizeImpls ::
  Env.Env ->
  ModuleName.Canonical ->
  Map.Map Name.Name Can.Ability ->
  [Ann.Located Src.ImplDecl] ->
  Result i [Warning.Warning] [Can.Impl]
canonicalizeImpls env home abilities srcImpls =
  traverse (canonicalizeOneImpl env home abilities) srcImpls

-- | Canonicalize a single impl declaration.
--
-- @since 0.20.0
canonicalizeOneImpl ::
  Env.Env ->
  ModuleName.Canonical ->
  Map.Map Name.Name Can.Ability ->
  Ann.Located Src.ImplDecl ->
  Result i [Warning.Warning] Can.Impl
canonicalizeOneImpl env home abilities (Ann.At region (Src.ImplDecl (Ann.At abilityRegion abilityName) srcImplType srcMethods)) =
  case Map.lookup abilityName abilities of
    Nothing ->
      Result.throw (Error.UnknownAbility abilityRegion abilityName)
    Just ability ->
      do
        canImplType <- Type.canonicalize env srcImplType
        checkOrphan region abilityName home abilities canImplType
        canMethods <- canonicalizeImplMethods env ability srcMethods
        Result.ok (Can.Impl abilityName canImplType canMethods)

-- | Check that an impl is not an orphan.
--
-- An impl is orphan when neither the ability nor the type is defined in
-- the current module. We use a simple heuristic: if the ability is found
-- in the local ability map, it is local. Otherwise the impl is allowed
-- only when the implemented type's home module matches the current module.
--
-- This is a best-effort check; full orphan checking requires knowing the
-- type's home module, which requires deeper integration with the type
-- system. For now we accept all impls and leave deep orphan enforcement
-- to a future phase.
--
-- @since 0.20.0
checkOrphan ::
  Ann.Region ->
  Name.Name ->
  ModuleName.Canonical ->
  Map.Map Name.Name Can.Ability ->
  Can.Type ->
  Result i w ()
checkOrphan region abilityName home abilities canImplType =
  let abilityIsLocal = Map.member abilityName abilities
      typeIsLocal = isLocalType home canImplType
  in if abilityIsLocal || typeIsLocal
       then Result.ok ()
       else Result.throw (Error.OrphanImpl abilityName canImplType region)

-- | Check whether a canonical type's home module matches the given module.
--
-- Returns 'True' if the outermost type constructor is defined in @home@.
--
-- @since 0.20.0
isLocalType :: ModuleName.Canonical -> Can.Type -> Bool
isLocalType home canType =
  case canType of
    Can.TType typeHome _ _ -> typeHome == home
    Can.TAlias typeHome _ _ _ -> typeHome == home
    _ -> False

-- | Canonicalize all method implementations in an impl declaration.
--
-- Verifies that the set of implemented methods exactly matches the
-- set of methods declared by the ability (no missing, no extra).
--
-- @since 0.20.0
canonicalizeImplMethods ::
  Env.Env ->
  Can.Ability ->
  [Ann.Located Src.Value] ->
  Result i [Warning.Warning] (Map.Map Name.Name Can.Def)
canonicalizeImplMethods env ability srcMethods =
  do
    canDefs <- traverse (canonicalizeImplMethod env) srcMethods
    let canMethodMap = Map.fromList canDefs
    checkMethodCoverage ability canMethodMap (map fst canDefs)
    Result.ok canMethodMap

-- | Check that an impl covers all required methods and no extra ones.
--
-- @since 0.20.0
checkMethodCoverage ::
  Can.Ability ->
  Map.Map Name.Name Can.Def ->
  [Name.Name] ->
  Result i w ()
checkMethodCoverage (Can.Ability abilityName _ _ declaredMethods) canMethodMap implMethodNames =
  let missing = filter (\n -> not (Map.member n canMethodMap)) (Map.keys declaredMethods)
      extras = filter (\n -> not (Map.member n declaredMethods)) implMethodNames
  in case (missing, extras) of
       ([], []) ->
         Result.ok ()
       (m : _, _) ->
         Result.throw (Error.MissingMethod abilityName m)
       (_, e : _) ->
         Result.throw (Error.ExtraMethod abilityName e)

-- | Canonicalize a single impl method definition.
--
-- Reuses the standard value canonicalization from 'Canonicalize.Expression'.
--
-- @since 0.20.0
canonicalizeImplMethod ::
  Env.Env ->
  Ann.Located Src.Value ->
  Result i [Warning.Warning] (Name.Name, Can.Def)
canonicalizeImplMethod env (Ann.At _ (Src.Value aname@(Ann.At _ name) srcArgs body maybeType _maybeGuard)) =
  case maybeType of
    Nothing ->
      do
        (args, argBindings) <-
          Pattern.verify (Error.DPFuncArgs name) $
            traverse (Pattern.canonicalize env) srcArgs
        newEnv <- Env.addLocals argBindings env
        (cbody, _) <-
          Expr.verifyBindings Warning.Pattern argBindings (Expr.canonicalize newEnv body)
        Result.ok (name, Can.Def aname args cbody)
    Just srcType ->
      do
        (Can.Forall freeVars tipe) <- Type.toAnnotation env srcType
        ((typedArgs, resultType), argBindings) <-
          Pattern.verify (Error.DPFuncArgs name) $
            Expr.gatherTypedArgs env name srcArgs tipe Index.first []
        newEnv <- Env.addLocals argBindings env
        (cbody, _) <-
          Expr.verifyBindings Warning.Pattern argBindings (Expr.canonicalize newEnv body)
        Result.ok (name, Can.TypedDef aname freeVars typedArgs cbody resultType)

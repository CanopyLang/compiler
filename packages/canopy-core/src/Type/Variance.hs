{-# LANGUAGE OverloadedStrings #-}

-- | Type.Variance - Variance checking for type parameters
--
-- Verifies that declared variance annotations match actual usage:
--
--   * Covariant (@+a@) parameters must only appear in positive (output) positions
--   * Contravariant (@-a@) parameters must only appear in negative (input) positions
--   * Invariant parameters (default) have no restrictions
--
-- Polarity flips at each function arrow: the argument of a function is in
-- negative position relative to the enclosing type expression, while the
-- result is in positive position.
--
-- @since 0.20.0
module Type.Variance
  ( checkAliasVariance,
    checkUnionVariance,
    Polarity (..),
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result

-- | Polarity tracks whether a type variable appears in a positive (output)
-- or negative (input) position within a type expression.
--
-- @since 0.20.0
data Polarity
  = -- | Output position: return types, record fields.
    Positive
  | -- | Input position: function arguments.
    Negative
  deriving (Eq, Show)

-- | Flip the polarity for a function argument.
--
-- @since 0.20.0
flipPolarity :: Polarity -> Polarity
flipPolarity Positive = Negative
flipPolarity Negative = Positive

-- RESULT

type Result i w a =
  Result.Result i w Error.Error a

-- | Check variance annotations for a type alias.
--
-- Verifies that each type parameter with a declared variance annotation
-- only appears in positions consistent with that variance. Invariant
-- parameters are always valid and are skipped.
--
-- @since 0.20.0
checkAliasVariance :: Ann.Region -> Name.Name -> [Name.Name] -> [Can.Variance] -> Can.Type -> Result i w ()
checkAliasVariance region typeName vars variances tipe =
  mapM_ (checkOneParam region typeName tipe) (zip vars variances)

-- | Check variance annotations for a union type.
--
-- Verifies that each type parameter with a declared variance annotation
-- only appears in positions consistent with that variance across all
-- constructor argument types.
--
-- @since 0.20.0
checkUnionVariance :: Ann.Region -> Name.Name -> [Name.Name] -> [Can.Variance] -> [Can.Ctor] -> Result i w ()
checkUnionVariance region typeName vars variances ctors =
  mapM_ (checkOneParamInCtors region typeName ctors) (zip vars variances)

-- | Check a single parameter's variance across all constructor arguments.
checkOneParamInCtors :: Ann.Region -> Name.Name -> [Can.Ctor] -> (Name.Name, Can.Variance) -> Result i w ()
checkOneParamInCtors region typeName ctors (varName, variance) =
  mapM_ (\(Can.Ctor _ _ _ args) -> mapM_ (checkVarInType region typeName varName variance Positive) args) ctors

-- | Check a single type parameter against the declared variance in a type body.
checkOneParam :: Ann.Region -> Name.Name -> Can.Type -> (Name.Name, Can.Variance) -> Result i w ()
checkOneParam region typeName tipe (varName, variance) =
  checkVarInType region typeName varName variance Positive tipe

-- | Walk a canonical type and verify that a specific type variable only
-- appears in positions consistent with its declared variance.
--
-- Covariant parameters must not appear in negative positions.
-- Contravariant parameters must not appear in positive positions.
-- Invariant parameters are unconstrained.
checkVarInType :: Ann.Region -> Name.Name -> Name.Name -> Can.Variance -> Polarity -> Can.Type -> Result i w ()
checkVarInType region typeName varName variance polarity tipe =
  case tipe of
    Can.TVar name
      | name == varName -> checkPosition region typeName varName variance polarity
      | otherwise -> Result.ok ()

    Can.TLambda arg result ->
      checkVarInType region typeName varName variance (flipPolarity polarity) arg
        >> checkVarInType region typeName varName variance polarity result

    Can.TType _ _ args ->
      mapM_ (checkVarInType region typeName varName variance polarity) args

    Can.TRecord fields _ ->
      mapM_ (\(_, fieldType) -> checkVarInType region typeName varName variance polarity fieldType)
        (Can.fieldsToList fields)

    Can.TUnit ->
      Result.ok ()

    Can.TTuple a b maybeC ->
      checkVarInType region typeName varName variance polarity a
        >> checkVarInType region typeName varName variance polarity b
        >> maybe (Result.ok ()) (checkVarInType region typeName varName variance polarity) maybeC

    Can.TAlias _ _ args aliasType ->
      mapM_ (checkVarInType region typeName varName variance polarity . snd) args
        >> checkVarInAliasType region typeName varName variance polarity aliasType

-- | Check variance in an alias type (which may be filled or holey).
checkVarInAliasType :: Ann.Region -> Name.Name -> Name.Name -> Can.Variance -> Polarity -> Can.AliasType -> Result i w ()
checkVarInAliasType region typeName varName variance polarity aliasType =
  case aliasType of
    Can.Holey _ -> Result.ok ()
    Can.Filled t -> checkVarInType region typeName varName variance polarity t

-- | Verify that the polarity matches the declared variance.
checkPosition :: Ann.Region -> Name.Name -> Name.Name -> Can.Variance -> Polarity -> Result i w ()
checkPosition region typeName varName variance polarity =
  case (variance, polarity) of
    (Can.Covariant, Negative) ->
      Result.throw (Error.VarianceViolation region typeName varName Can.Covariant Error.NegativePosition)
    (Can.Contravariant, Positive) ->
      Result.throw (Error.VarianceViolation region typeName varName Can.Contravariant Error.PositivePosition)
    _ ->
      Result.ok ()

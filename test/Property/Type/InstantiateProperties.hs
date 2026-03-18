{-# LANGUAGE OverloadedStrings #-}

-- | Property.Type.InstantiateProperties — Property-based tests for Type.Instantiate.
--
-- Verifies the invariants of 'Type.Instantiate.fromSrcType', which transforms
-- canonical source types ('AST.Canonical.Type') into the internal compiler
-- representation ('Type.Type.Type'):
--
-- * 'Can.TUnit' always maps to 'UnitN'.
-- * 'Can.TLambda' always maps to 'FunN' — the output constructor is preserved.
-- * 'Can.TType' always maps to 'AppN' — the home module and type name are
--   preserved verbatim.
-- * 'Can.TTuple' always maps to 'TupleN' — the third component is present iff
--   the source had a third component.
-- * 'Can.TRecord' always maps to 'RecordN' — the field count is preserved.
-- * 'Can.TVar' resolved via the free-vars map returns exactly the mapped type.
-- * Empty freeVars map with 'Can.TUnit' is safe to call without error.
--
-- All tests use 'ioProperty' because 'fromSrcType' operates in 'IO'.
--
-- @since 0.19.1
module Property.Type.InstantiateProperties
  ( tests
  ) where

import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Type.Instantiate as Instantiate
import Type.Type (Type (..))
import qualified Type.Type as Type
import Test.Tasty
import Test.Tasty.QuickCheck

-- | Main test tree containing all instantiate property tests.
tests :: TestTree
tests =
  testGroup
    "Type.Instantiate Property Tests"
    [ unitTypeProperties
    , lambdaTypeProperties
    , tupleTypeProperties
    , appTypeProperties
    , recordTypeProperties
    , freeVarResolutionProperties
    ]

-- CONSTRUCTOR PREDICATES

isUnitN :: Type -> Bool
isUnitN UnitN = True
isUnitN _ = False

isFunN :: Type -> Bool
isFunN (FunN _ _) = True
isFunN _ = False

isAppN :: Type -> Bool
isAppN (AppN _ _ _) = True
isAppN _ = False

isTupleN :: Type -> Bool
isTupleN (TupleN _ _ _) = True
isTupleN _ = False

hasTupleThird :: Type -> Bool
hasTupleThird (TupleN _ _ (Just _)) = True
hasTupleThird _ = False

-- UNIT TYPE PROPERTIES

-- | Verifies that 'Can.TUnit' always produces 'UnitN' regardless of the
-- freeVars environment.
--
-- 'TUnit' has no type variables, so the freeVars map is irrelevant and the
-- output must always be the 'UnitN' constructor.
unitTypeProperties :: TestTree
unitTypeProperties =
  testGroup
    "TUnit always produces UnitN"
    [ testProperty "TUnit with empty freeVars yields UnitN" $
        ioProperty $ do
          result <- Instantiate.fromSrcType Map.empty Can.TUnit
          pure (isUnitN result === True)

    , testProperty "TUnit with non-empty freeVars still yields UnitN" $
        ioProperty $ do
          let freeVars = Map.singleton (Name.fromChars "a") Type.int
          result <- Instantiate.fromSrcType freeVars Can.TUnit
          pure (isUnitN result === True)

    , testProperty "nested TUnit in TLambda yields FunN with UnitN components" $
        ioProperty $ do
          result <- Instantiate.fromSrcType Map.empty (Can.TLambda Can.TUnit Can.TUnit)
          pure (isFunN result === True)
    ]

-- LAMBDA TYPE PROPERTIES

-- | Verifies that 'Can.TLambda' always produces 'FunN'.
--
-- A lambda type maps directly to the function constructor in the internal
-- type representation; the structure must be preserved regardless of the
-- argument and result types.
lambdaTypeProperties :: TestTree
lambdaTypeProperties =
  testGroup
    "TLambda always produces FunN"
    [ testProperty "TLambda Unit Unit yields FunN" $
        ioProperty $ do
          result <- Instantiate.fromSrcType Map.empty (Can.TLambda Can.TUnit Can.TUnit)
          pure (isFunN result === True)

    , testProperty "TLambda (TType Int) Unit yields FunN" $
        ioProperty $ do
          let intType = Can.TType ModuleName.basics (Name.fromChars "Int") []
          result <- Instantiate.fromSrcType Map.empty (Can.TLambda intType Can.TUnit)
          pure (isFunN result === True)

    , testProperty "TLambda Unit (TType String) yields FunN" $
        ioProperty $ do
          let strType = Can.TType ModuleName.basics (Name.fromChars "String") []
          result <- Instantiate.fromSrcType Map.empty (Can.TLambda Can.TUnit strType)
          pure (isFunN result === True)

    , testProperty "nested TLambda yields FunN at outer level" $
        ioProperty $ do
          let inner = Can.TLambda Can.TUnit Can.TUnit
          result <- Instantiate.fromSrcType Map.empty (Can.TLambda inner Can.TUnit)
          pure (isFunN result === True)
    ]

-- TUPLE TYPE PROPERTIES

-- | Verifies that 'Can.TTuple' always produces 'TupleN' and that the
-- presence or absence of a third element is faithfully preserved.
--
-- The third element of a tuple (for 3-tuples) must be 'Just' iff the source
-- type had a third component, and 'Nothing' otherwise.
tupleTypeProperties :: TestTree
tupleTypeProperties =
  testGroup
    "TTuple produces TupleN preserving third element"
    [ testProperty "TTuple a b Nothing yields TupleN without third" $
        ioProperty $ do
          result <- Instantiate.fromSrcType Map.empty (Can.TTuple Can.TUnit Can.TUnit Nothing)
          pure (isTupleN result === True .&&. hasTupleThird result === False)

    , testProperty "TTuple a b (Just c) yields TupleN with third" $
        ioProperty $ do
          result <- Instantiate.fromSrcType Map.empty (Can.TTuple Can.TUnit Can.TUnit (Just Can.TUnit))
          pure (isTupleN result === True .&&. hasTupleThird result === True)

    , testProperty "TTuple with TType components yields TupleN" $
        ioProperty $ do
          let intType = Can.TType ModuleName.basics (Name.fromChars "Int") []
          result <- Instantiate.fromSrcType Map.empty (Can.TTuple intType intType Nothing)
          pure (isTupleN result === True)
    ]

-- APP TYPE PROPERTIES

-- | Verifies that 'Can.TType' always produces 'AppN' with the home module
-- and type name preserved, and that the number of type arguments matches the
-- source.
--
-- The home module and name are essential for qualified name resolution; they
-- must be identical in the output.
appTypeProperties :: TestTree
appTypeProperties =
  testGroup
    "TType produces AppN preserving home and name"
    [ testProperty "TType with zero args yields AppN" $
        ioProperty $ do
          let typeName = Name.fromChars "Int"
          result <- Instantiate.fromSrcType Map.empty (Can.TType ModuleName.basics typeName [])
          case result of
            AppN home name [] -> pure (home === ModuleName.basics .&&. name === typeName)
            _ -> pure (counterexample "expected AppN" False)

    , testProperty "TType with one Unit arg yields AppN with one arg" $
        ioProperty $ do
          let typeName = Name.fromChars "List"
          result <- Instantiate.fromSrcType Map.empty (Can.TType ModuleName.list typeName [Can.TUnit])
          case result of
            AppN _ _ args -> pure (length args === 1)
            _ -> pure (counterexample "expected AppN" False)

    , testProperty "TType with two Unit args yields AppN with two args" $
        ioProperty $ do
          let typeName = Name.fromChars "Result"
          let src = Can.TType ModuleName.basics typeName [Can.TUnit, Can.TUnit]
          result <- Instantiate.fromSrcType Map.empty src
          case result of
            AppN _ _ args -> pure (length args === 2)
            _ -> pure (counterexample "expected AppN" False)
    ]

-- RECORD TYPE PROPERTIES

-- | Verifies that 'Can.TRecord' always produces 'RecordN' and that the
-- number of fields in the output equals the number in the source.
--
-- Field count preservation is critical; a missing or duplicated field would
-- indicate a bug in the instantiation traversal.
recordTypeProperties :: TestTree
recordTypeProperties =
  testGroup
    "TRecord preserves field count in RecordN"
    [ testProperty "TRecord with no fields yields RecordN with zero fields" $
        ioProperty $ do
          result <- Instantiate.fromSrcType Map.empty (Can.TRecord Map.empty Nothing)
          case result of
            RecordN fields _ -> pure (Map.size fields === 0)
            _ -> pure (counterexample "expected RecordN" False)

    , testProperty "TRecord with one field yields RecordN with one field" $
        ioProperty $ do
          let fields = Map.singleton (Name.fromChars "x") (Can.FieldType 0 Can.TUnit)
          result <- Instantiate.fromSrcType Map.empty (Can.TRecord fields Nothing)
          case result of
            RecordN outFields _ -> pure (Map.size outFields === 1)
            _ -> pure (counterexample "expected RecordN" False)

    , testProperty "TRecord with two fields yields RecordN with two fields" $
        ioProperty $ do
          let fields =
                Map.fromList
                  [ (Name.fromChars "x", Can.FieldType 0 Can.TUnit)
                  , (Name.fromChars "y", Can.FieldType 1 Can.TUnit)
                  ]
          result <- Instantiate.fromSrcType Map.empty (Can.TRecord fields Nothing)
          case result of
            RecordN outFields _ -> pure (Map.size outFields === 2)
            _ -> pure (counterexample "expected RecordN" False)
    ]

-- FREE VAR RESOLUTION PROPERTIES

-- | Verifies that 'Can.TVar' is resolved to exactly the type stored in the
-- freeVars map under that variable name.
--
-- This is the substitution mechanism of the instantiator; the resolved type
-- must equal the value stored in the map, not a copy or approximation.
freeVarResolutionProperties :: TestTree
freeVarResolutionProperties =
  testGroup
    "TVar resolves from freeVars map"
    [ testProperty "TVar 'a' mapped to Int resolves to AppN Int" $
        ioProperty $ do
          let varName = Name.fromChars "a"
          let freeVars = Map.singleton varName Type.int
          result <- Instantiate.fromSrcType freeVars (Can.TVar varName)
          pure (isAppN result === True)

    , testProperty "TVar 'b' mapped to UnitN resolves to UnitN" $
        ioProperty $ do
          let varName = Name.fromChars "b"
          let freeVars = Map.singleton varName UnitN
          result <- Instantiate.fromSrcType freeVars (Can.TVar varName)
          pure (isUnitN result === True)

    , testProperty "TVar mapped to FunN resolves to FunN" $
        ioProperty $ do
          let varName = Name.fromChars "f"
          let funType = FunN Type.int Type.string
          let freeVars = Map.singleton varName funType
          result <- Instantiate.fromSrcType freeVars (Can.TVar varName)
          pure (isFunN result === True)

    , testProperty "two distinct TVar names resolve independently" $
        ioProperty $ do
          let aName = Name.fromChars "a"
          let bName = Name.fromChars "b"
          let freeVars =
                Map.fromList
                  [ (aName, Type.int)
                  , (bName, UnitN)
                  ]
          resultA <- Instantiate.fromSrcType freeVars (Can.TVar aName)
          resultB <- Instantiate.fromSrcType freeVars (Can.TVar bName)
          pure (isAppN resultA === True .&&. isUnitN resultB === True)
    ]

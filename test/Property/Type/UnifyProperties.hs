{-# LANGUAGE OverloadedStrings #-}

-- | Property.Type.UnifyProperties - Property-based tests for type unification
--
-- This module provides property-based tests for the type unification system,
-- verifying that unification obeys its core invariants:
--
-- * Self-unification of flexible variables always succeeds
-- * After successful unification, variables become equivalent
-- * Flexible variables unify with any concrete type
-- * Rigid variables with different names always fail to unify
-- * Two flexible variables always unify successfully
--
-- All tests use IO-based property testing via 'ioProperty' because the
-- unification system operates in IO through mutable union-find structures.
--
-- @since 0.19.1
module Property.Type.UnifyProperties
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package
import qualified Canopy.Data.Name as Name
import Type.Type (Descriptor (Descriptor), Content (..), FlatType (..), Variable)
import qualified Type.Type as Type
import qualified Data.Map.Strict as Map
import qualified Type.Unify as Unify
import qualified Type.UnionFind as UF

-- | Main test tree containing all unification property tests.
tests :: TestTree
tests = testGroup "Unification Property Tests"
  [ flexSelfUnifyProperties
  , flexFlexUnifyProperties
  , rigidMismatchProperties
  , unifyEquivalenceProperties
  , flexConcreteProperties
  ]

-- | Verifies that unifying a flexible variable with itself always produces Ok.
--
-- This is a fundamental invariant: self-unification must be idempotent and
-- must never fail, regardless of how many times it is performed.
flexSelfUnifyProperties :: TestTree
flexSelfUnifyProperties = testGroup "Flex Self-Unify"
  [ testProperty "flex var unifies with itself" $ ioProperty $ do
      v <- Type.mkFlexVar
      result <- Unify.unify Map.empty v v
      pure (isOk result)

  , testProperty "flex var self-unify is idempotent" $ ioProperty $ do
      v <- Type.mkFlexVar
      result1 <- Unify.unify Map.empty v v
      result2 <- Unify.unify Map.empty v v
      pure (isOk result1 .&&. isOk result2)

  , testProperty "flex number unifies with itself" $ ioProperty $ do
      v <- Type.mkFlexNumber
      result <- Unify.unify Map.empty v v
      pure (isOk result)

  , testProperty "named flex var unifies with itself" $ ioProperty $ do
      v <- Type.nameToFlex (Name.fromChars "a")
      result <- Unify.unify Map.empty v v
      pure (isOk result)

  , testProperty "self-unify preserves variable rank" $ ioProperty $ do
      v <- Type.mkFlexVar
      Descriptor _ rankBefore _ _ <- UF.get v
      _ <- Unify.unify Map.empty v v
      Descriptor _ rankAfter _ _ <- UF.get v
      pure (rankBefore === rankAfter)
  ]

-- | Verifies that two distinct flexible variables always unify successfully.
--
-- Flexible variables represent unknowns in the type system. Two unknowns
-- should always be unifiable because they impose no constraints.
flexFlexUnifyProperties :: TestTree
flexFlexUnifyProperties = testGroup "Flex-Flex Unify"
  [ testProperty "two fresh flex vars always unify" $ ioProperty $ do
      v1 <- Type.mkFlexVar
      v2 <- Type.mkFlexVar
      result <- Unify.unify Map.empty v1 v2
      pure (isOk result)

  , testProperty "two named flex vars always unify" $ ioProperty $ do
      v1 <- Type.nameToFlex (Name.fromChars "a")
      v2 <- Type.nameToFlex (Name.fromChars "b")
      result <- Unify.unify Map.empty v1 v2
      pure (isOk result)

  , testProperty "flex number and flex var unify" $ ioProperty $ do
      v1 <- Type.mkFlexNumber
      v2 <- Type.mkFlexVar
      result <- Unify.unify Map.empty v1 v2
      pure (isOk result)

  , testProperty "two flex numbers unify" $ ioProperty $ do
      v1 <- Type.mkFlexNumber
      v2 <- Type.mkFlexNumber
      result <- Unify.unify Map.empty v1 v2
      pure (isOk result)

  , testProperty "multiple flex vars unify in sequence" $ ioProperty $ do
      v1 <- Type.mkFlexVar
      v2 <- Type.mkFlexVar
      v3 <- Type.mkFlexVar
      r1 <- Unify.unify Map.empty v1 v2
      r2 <- Unify.unify Map.empty v2 v3
      pure (isOk r1 .&&. isOk r2)
  ]

-- | Verifies that rigid variables with different names always fail to unify.
--
-- Rigid variables represent user-specified type variables that must remain
-- distinct. Two rigid variables with different names cannot be unified.
rigidMismatchProperties :: TestTree
rigidMismatchProperties = testGroup "Rigid Mismatch"
  [ testProperty "rigid vars with different names fail" $ ioProperty $ do
      v1 <- Type.nameToRigid (Name.fromChars "a")
      v2 <- Type.nameToRigid (Name.fromChars "b")
      result <- Unify.unify Map.empty v1 v2
      pure (isErr result)

  , testProperty "rigid var with different single-char names fail" $ ioProperty $ do
      v1 <- Type.nameToRigid (Name.fromChars "x")
      v2 <- Type.nameToRigid (Name.fromChars "y")
      result <- Unify.unify Map.empty v1 v2
      pure (isErr result)

  , testProperty "rigid var unifies with itself" $ ioProperty $ do
      v <- Type.nameToRigid (Name.fromChars "a")
      result <- Unify.unify Map.empty v v
      pure (isOk result)

  , testProperty "flex var unifies with rigid var" $ ioProperty $ do
      flex <- Type.mkFlexVar
      rigid <- Type.nameToRigid (Name.fromChars "a")
      result <- Unify.unify Map.empty flex rigid
      pure (isOk result)

  , testProperty "rigid var does not unify with different rigid" $ ioProperty $ do
      v1 <- Type.nameToRigid (Name.fromChars "alpha")
      v2 <- Type.nameToRigid (Name.fromChars "beta")
      result <- Unify.unify Map.empty v1 v2
      pure (isErr result)
  ]

-- | Verifies that after successful unification, variables become equivalent
-- in the union-find structure.
--
-- This is a critical invariant: if unify returns Ok, the two variables
-- must be in the same equivalence class.
unifyEquivalenceProperties :: TestTree
unifyEquivalenceProperties = testGroup "Unify Equivalence"
  [ testProperty "after flex-flex unify, vars are equivalent" $ ioProperty $ do
      v1 <- Type.mkFlexVar
      v2 <- Type.mkFlexVar
      result <- Unify.unify Map.empty v1 v2
      eq <- UF.equivalent v1 v2
      pure (isOk result .&&. eq === True)

  , testProperty "after flex-rigid unify, vars are equivalent" $ ioProperty $ do
      flex <- Type.mkFlexVar
      rigid <- Type.nameToRigid (Name.fromChars "t")
      result <- Unify.unify Map.empty flex rigid
      eq <- UF.equivalent flex rigid
      pure (isOk result .&&. eq === True)

  , testProperty "after chain unify, all vars are equivalent" $ ioProperty $ do
      v1 <- Type.mkFlexVar
      v2 <- Type.mkFlexVar
      v3 <- Type.mkFlexVar
      _ <- Unify.unify Map.empty v1 v2
      _ <- Unify.unify Map.empty v2 v3
      eq13 <- UF.equivalent v1 v3
      pure (eq13 === True)

  , testProperty "failed unify does not make vars equivalent" $ ioProperty $ do
      v1 <- Type.nameToRigid (Name.fromChars "a")
      v2 <- Type.nameToRigid (Name.fromChars "b")
      _ <- Unify.unify Map.empty v1 v2
      eq <- UF.equivalent v1 v2
      pure (eq === False)

  , testProperty "self-unify preserves equivalence" $ ioProperty $ do
      v <- Type.mkFlexVar
      _ <- Unify.unify Map.empty v v
      eq <- UF.equivalent v v
      pure (eq === True)
  ]

-- | Verifies that a flexible variable can unify with concrete structure types
-- built from the Type module primitives.
--
-- Flex variables are unconstrained, so they should accept any concrete type
-- shape when unified via a structure variable.
flexConcreteProperties :: TestTree
flexConcreteProperties = testGroup "Flex-Concrete Unify"
  [ testProperty "flex var unifies with Int structure" $ ioProperty $ do
      flex <- Type.mkFlexVar
      intVar <- mkStructureVar (App1 basicsModule "Int" [])
      result <- Unify.unify Map.empty flex intVar
      pure (isOk result)

  , testProperty "flex var unifies with Float structure" $ ioProperty $ do
      flex <- Type.mkFlexVar
      floatVar <- mkStructureVar (App1 basicsModule "Float" [])
      result <- Unify.unify Map.empty flex floatVar
      pure (isOk result)

  , testProperty "flex var unifies with String structure" $ ioProperty $ do
      flex <- Type.mkFlexVar
      strVar <- mkStructureVar (App1 stringModule "String" [])
      result <- Unify.unify Map.empty flex strVar
      pure (isOk result)

  , testProperty "flex var unifies with Unit structure" $ ioProperty $ do
      flex <- Type.mkFlexVar
      unitVar <- mkStructureVar Unit1
      result <- Unify.unify Map.empty flex unitVar
      pure (isOk result)

  , testProperty "flex var unifies with EmptyRecord structure" $ ioProperty $ do
      flex <- Type.mkFlexVar
      recVar <- mkStructureVar EmptyRecord1
      result <- Unify.unify Map.empty flex recVar
      pure (isOk result)
  ]

-- HELPERS

-- | Check whether a unification Answer is Ok.
isOk :: Unify.Answer -> Bool
isOk (Unify.Ok _) = True
isOk (Unify.Err _ _ _) = False

-- | Check whether a unification Answer is Err.
isErr :: Unify.Answer -> Bool
isErr = not . isOk

-- | Create a fresh variable with the given structure content.
mkStructureVar :: FlatType -> IO Variable
mkStructureVar flatType =
  UF.fresh (Descriptor (Structure flatType) Type.noRank Type.noMark Nothing)

-- | The Basics module canonical name used for Int, Float, Bool.
basicsModule :: ModuleName.Canonical
basicsModule = ModuleName.Canonical Package.core "Basics"

-- | The String module canonical name.
stringModule :: ModuleName.Canonical
stringModule = ModuleName.Canonical Package.core "String"

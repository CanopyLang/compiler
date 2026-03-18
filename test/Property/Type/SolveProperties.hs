{-# LANGUAGE OverloadedStrings #-}

-- | Property.Type.SolveProperties — Property-based tests for the constraint solver.
--
-- Verifies that the 'Type.Solve.run' function satisfies its core invariants
-- across arbitrarily constructed constraints:
--
-- * 'CTrue' always succeeds regardless of how many times it is composed.
-- * Commutativity of 'CAnd': @CAnd [a, b]@ succeeds if and only if
--   @CAnd [b, a]@ succeeds.
-- * Idempotence of 'CTrue': @CAnd [CTrue, CTrue, …]@ always succeeds.
-- * Failure monotonicity: if a constraint fails, wrapping it in @CAnd@
--   with any other constraint still fails.
-- * A 'CEqual' constraint on identical concrete types always succeeds.
-- * A 'CEqual' constraint on two distinct concrete primitive types always fails.
--
-- All tests use 'ioProperty' because the solver operates in 'IO' via mutable
-- union-find state.
--
-- @since 0.19.1
module Property.Type.SolveProperties
  ( tests
  ) where

import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Type as Error
import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Type.Solve as Solve
import Type.Type (Constraint (..), Type (..))
import qualified Type.Type as Type

-- | Main test tree containing all constraint solver property tests.
tests :: TestTree
tests =
  testGroup
    "Type.Solve Property Tests"
    [ cTrueProperties
    , cAndCommutativityProperties
    , cTrueIdempotenceProperties
    , failureMonotonicityProperties
    , cEqualSameTypeProperties
    , cEqualDistinctTypeProperties
    ]

-- HELPERS

-- | Standard region used for all test constraints.
testRegion :: Ann.Region
testRegion =
  Ann.Region (Ann.Position 1 1) (Ann.Position 1 1)

-- | Build a 'CEqual' constraint asserting that two types must unify.
mkCEqual :: Type -> Type -> Constraint
mkCEqual actual expected =
  CEqual testRegion Error.Number actual (Error.NoExpectation expected)

-- | Determine whether a solver result represents success.
isSolveSuccess :: Either a b -> Bool
isSolveSuccess (Right _) = True
isSolveSuccess (Left _) = False

-- | A small list of distinct concrete primitive types for use in generators.
--
-- These are the four primitives that are guaranteed to be mutually
-- incompatible under the Canopy type system.
primTypes :: [Type]
primTypes = [Type.int, Type.string, Type.bool, Type.float]

-- | Generate a pair of distinct primitive types by index.
--
-- Uses index-based selection so that the two types are guaranteed to be
-- different concrete primitives. The index pair (i, j) where i /= j is
-- computed first, then both types are looked up in 'primTypes' via
-- 'safeIndex', which returns 'Nothing' on out-of-bounds.
genDistinctPrimPair :: Gen (Type, Type)
genDistinctPrimPair = do
  i <- choose (0, length primTypes - 1)
  j <- suchThat (choose (0, length primTypes - 1)) (/= i)
  pure (safeIndex i, safeIndex j)
  where
    safeIndex n = maybe Type.int id (lookup n (zip [0..] primTypes))

-- CTRUE PROPERTIES

-- | Verifies that any number of 'CTrue' constraints composed with 'CAnd'
-- always succeed.
--
-- 'CTrue' is the identity element of the constraint lattice; it must never
-- cause solver failure regardless of composition depth.
cTrueProperties :: TestTree
cTrueProperties =
  testGroup
    "CTrue always succeeds"
    [ testProperty "CTrue alone succeeds" $
        ioProperty $ do
          result <- Solve.run CTrue
          pure (isSolveSuccess result === True)

    , testProperty "CAnd of N CTrue constraints succeeds" $
        forAll (choose (0, 10)) $ \n ->
          ioProperty $ do
            result <- Solve.run (CAnd (replicate n CTrue))
            pure (isSolveSuccess result === True)

    , testProperty "CSaveTheEnvironment succeeds" $
        ioProperty $ do
          result <- Solve.run CSaveTheEnvironment
          pure (isSolveSuccess result === True)

    , testProperty "CCaseBranchesIsolated of CTrue constraints succeeds" $
        forAll (choose (0, 5)) $ \n ->
          ioProperty $ do
            result <- Solve.run (CCaseBranchesIsolated (replicate n CTrue))
            pure (isSolveSuccess result === True)
    ]

-- CAND COMMUTATIVITY PROPERTIES

-- | Verifies that 'CAnd' is commutative with respect to success/failure
-- for pairs of constraints.
--
-- The order of constraints in 'CAnd' must not affect whether the overall
-- constraint succeeds or fails.
cAndCommutativityProperties :: TestTree
cAndCommutativityProperties =
  testGroup
    "CAnd commutativity"
    [ testProperty "CAnd [CTrue, matching CEqual] commutes" $
        ioProperty $ do
          let c = mkCEqual Type.int Type.int
          r1 <- Solve.run (CAnd [CTrue, c])
          r2 <- Solve.run (CAnd [c, CTrue])
          pure (isSolveSuccess r1 === isSolveSuccess r2)

    , testProperty "CAnd [CTrue, failing CEqual] commutes" $
        ioProperty $ do
          let bad = mkCEqual Type.int Type.string
          r1 <- Solve.run (CAnd [CTrue, bad])
          r2 <- Solve.run (CAnd [bad, CTrue])
          pure (isSolveSuccess r1 === isSolveSuccess r2)

    , testProperty "CAnd [matching, matching] same success both orders" $
        ioProperty $ do
          let c1 = mkCEqual Type.int Type.int
          let c2 = mkCEqual Type.bool Type.bool
          r1 <- Solve.run (CAnd [c1, c2])
          r2 <- Solve.run (CAnd [c2, c1])
          pure (isSolveSuccess r1 === True .&&. isSolveSuccess r2 === True)
    ]

-- CTRUE IDEMPOTENCE PROPERTIES

-- | Verifies that adding 'CTrue' to any successful constraint preserves success,
-- and adding it to any failing constraint preserves failure.
--
-- This confirms that 'CTrue' behaves as a unit element under 'CAnd'.
cTrueIdempotenceProperties :: TestTree
cTrueIdempotenceProperties =
  testGroup
    "CTrue idempotence under CAnd"
    [ testProperty "CAnd [c, CTrue] has same outcome as c alone (success case)" $
        ioProperty $ do
          let c = mkCEqual Type.float Type.float
          r1 <- Solve.run c
          r2 <- Solve.run (CAnd [c, CTrue])
          pure (isSolveSuccess r1 === isSolveSuccess r2)

    , testProperty "CAnd [c, CTrue] has same outcome as c alone (failure case)" $
        ioProperty $ do
          let c = mkCEqual Type.int Type.bool
          r1 <- Solve.run c
          r2 <- Solve.run (CAnd [c, CTrue])
          pure (isSolveSuccess r1 === isSolveSuccess r2)

    , testProperty "prepending CTrue to CAnd preserves outcome" $
        ioProperty $ do
          let c1 = mkCEqual Type.int Type.int
          let c2 = mkCEqual Type.string Type.string
          r1 <- Solve.run (CAnd [c1, c2])
          r2 <- Solve.run (CAnd [CTrue, c1, c2])
          pure (isSolveSuccess r1 === isSolveSuccess r2)
    ]

-- FAILURE MONOTONICITY PROPERTIES

-- | Verifies that a failing constraint embedded in 'CAnd' propagates failure,
-- regardless of what other constraints surround it.
--
-- Failure is monotone: one bad constraint taints the whole 'CAnd'.
failureMonotonicityProperties :: TestTree
failureMonotonicityProperties =
  testGroup
    "Failure monotonicity"
    [ testProperty "bad constraint in CAnd with CTrue always fails" $
        ioProperty $ do
          let bad = mkCEqual Type.int Type.string
          result <- Solve.run (CAnd [bad, CTrue])
          pure (isSolveSuccess result === False)

    , testProperty "bad constraint in CAnd with good constraint always fails" $
        ioProperty $ do
          let bad = mkCEqual Type.int Type.string
          let good = mkCEqual Type.bool Type.bool
          result <- Solve.run (CAnd [good, bad])
          pure (isSolveSuccess result === False)

    , testProperty "CCaseBranchesIsolated with one bad branch fails" $
        ioProperty $ do
          let bad = mkCEqual Type.int Type.float
          result <- Solve.run (CCaseBranchesIsolated [CTrue, bad, CTrue])
          pure (isSolveSuccess result === False)
    ]

-- CEQUAL SAME TYPE PROPERTIES

-- | Verifies that 'CEqual' on identical primitive types always succeeds.
--
-- Unifying a type with itself is always valid; this property checks that
-- every concrete primitive satisfies reflexive unification via the solver.
cEqualSameTypeProperties :: TestTree
cEqualSameTypeProperties =
  testGroup
    "CEqual same type always succeeds"
    [ testProperty "CEqual Int Int succeeds" $
        ioProperty $ do
          result <- Solve.run (mkCEqual Type.int Type.int)
          pure (isSolveSuccess result === True)

    , testProperty "CEqual String String succeeds" $
        ioProperty $ do
          result <- Solve.run (mkCEqual Type.string Type.string)
          pure (isSolveSuccess result === True)

    , testProperty "CEqual Bool Bool succeeds" $
        ioProperty $ do
          result <- Solve.run (mkCEqual Type.bool Type.bool)
          pure (isSolveSuccess result === True)

    , testProperty "CEqual Float Float succeeds" $
        ioProperty $ do
          result <- Solve.run (mkCEqual Type.float Type.float)
          pure (isSolveSuccess result === True)

    , testProperty "CEqual Char Char succeeds" $
        ioProperty $ do
          result <- Solve.run (mkCEqual Type.char Type.char)
          pure (isSolveSuccess result === True)

    , testProperty "CEqual UnitN UnitN succeeds" $
        ioProperty $ do
          result <- Solve.run (mkCEqual UnitN UnitN)
          pure (isSolveSuccess result === True)

    , testProperty "CEqual FunN same components succeeds" $
        ioProperty $ do
          let funType = FunN Type.int Type.string
          result <- Solve.run (mkCEqual funType funType)
          pure (isSolveSuccess result === True)
    ]

-- CEQUAL DISTINCT TYPE PROPERTIES

-- | Verifies that 'CEqual' on two distinct primitive types always fails.
--
-- Two different concrete primitives are never unifiable; the solver must
-- report a type error for each such pairing.
cEqualDistinctTypeProperties :: TestTree
cEqualDistinctTypeProperties =
  testGroup
    "CEqual distinct primitives always fails"
    [ testProperty "CEqual Int String fails" $
        ioProperty $ do
          result <- Solve.run (mkCEqual Type.int Type.string)
          pure (isSolveSuccess result === False)

    , testProperty "CEqual Int Bool fails" $
        ioProperty $ do
          result <- Solve.run (mkCEqual Type.int Type.bool)
          pure (isSolveSuccess result === False)

    , testProperty "CEqual Float Bool fails" $
        ioProperty $ do
          result <- Solve.run (mkCEqual Type.float Type.bool)
          pure (isSolveSuccess result === False)

    , testProperty "CEqual String Bool fails" $
        ioProperty $ do
          result <- Solve.run (mkCEqual Type.string Type.bool)
          pure (isSolveSuccess result === False)

    , testProperty "CEqual (Int -> String) (Int -> Bool) fails" $
        ioProperty $ do
          let fun1 = FunN Type.int Type.string
          let fun2 = FunN Type.int Type.bool
          result <- Solve.run (mkCEqual fun1 fun2)
          pure (isSolveSuccess result === False)

    , testProperty "arbitrary distinct primitive pair always fails" $
        forAllBlind genDistinctPrimPair $ \(t1, t2) ->
          ioProperty $ do
            result <- Solve.run (mkCEqual t1 t2)
            pure (isSolveSuccess result === False)
    ]

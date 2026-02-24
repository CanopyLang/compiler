{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Property.Type.UnionFindProperties - Property-based tests for the union-find structure
--
-- This module provides property-based tests for the union-find data structure
-- used to track type variable equivalences during unification. The properties
-- verified include:
--
-- * fresh/get roundtrip: creating a point and reading it returns the original value
-- * set/get roundtrip: setting a point's value and reading it returns the new value
-- * union/equivalent: after union, the two points are equivalent
-- * Equivalence is reflexive: every point is equivalent to itself
-- * Equivalence is symmetric: if a ~ b then b ~ a
-- * Non-unioned points are not equivalent
--
-- All tests use IO-based property testing via 'ioProperty' because the
-- union-find structure uses mutable IORefs internally.
--
-- @since 0.19.1
module Property.Type.UnionFindProperties
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Type.UnionFind as UF

-- | Main test tree containing all union-find property tests.
tests :: TestTree
tests = testGroup "UnionFind Property Tests"
  [ freshGetProperties
  , setGetProperties
  , unionEquivalentProperties
  , equivalenceReflexiveProperties
  , equivalenceSymmetryProperties
  , nonUnionedProperties
  ]

-- | Verifies that creating a fresh point and immediately reading it
-- returns the original value that was stored.
--
-- This is the fundamental contract of the union-find: a freshly created
-- point must hold exactly the value it was initialized with.
freshGetProperties :: TestTree
freshGetProperties = testGroup "Fresh/Get Roundtrip"
  [ testProperty "fresh Int then get returns original" $ \(n :: Int) ->
      ioProperty $ do
        p <- UF.fresh n
        val <- UF.get p
        pure (val === n)

  , testProperty "fresh String then get returns original" $ \(s :: String) ->
      ioProperty $ do
        p <- UF.fresh s
        val <- UF.get p
        pure (val === s)

  , testProperty "fresh Bool then get returns original" $ \(b :: Bool) ->
      ioProperty $ do
        p <- UF.fresh b
        val <- UF.get p
        pure (val === b)

  , testProperty "fresh negative Int then get returns original" $ \(n :: Int) ->
      ioProperty $ do
        p <- UF.fresh (negate (abs n))
        val <- UF.get p
        pure (val === negate (abs n))

  , testProperty "fresh unit tuple then get returns original" $
      ioProperty $ do
        p <- UF.fresh ()
        val <- UF.get p
        pure (val === ())
  ]

-- | Verifies that setting a point's descriptor and then getting it
-- returns the newly set value, not the original.
--
-- This tests that set correctly overwrites the stored value.
setGetProperties :: TestTree
setGetProperties = testGroup "Set/Get Roundtrip"
  [ testProperty "set then get returns new value" $ \(n :: Int) (m :: Int) ->
      ioProperty $ do
        p <- UF.fresh n
        UF.set p m
        val <- UF.get p
        pure (val === m)

  , testProperty "multiple sets, get returns last" $ \(a :: Int) (b :: Int) (c :: Int) ->
      ioProperty $ do
        p <- UF.fresh a
        UF.set p b
        UF.set p c
        val <- UF.get p
        pure (val === c)

  , testProperty "set preserves value through repr" $ \(n :: Int) (m :: Int) ->
      ioProperty $ do
        p <- UF.fresh n
        UF.set p m
        _ <- UF.repr p
        val <- UF.get p
        pure (val === m)

  , testProperty "set on linked point updates correctly" $ \(a :: Int) (b :: Int) (c :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        UF.union p1 p2 c
        val1 <- UF.get p1
        val2 <- UF.get p2
        pure (val1 === c .&&. val2 === c)

  , testProperty "modify changes value correctly" $ \(n :: Int) ->
      ioProperty $ do
        p <- UF.fresh n
        UF.modify p (+ 1)
        val <- UF.get p
        pure (val === n + 1)
  ]

-- | Verifies that after unioning two points with a value, the points
-- become equivalent and both hold the union value.
--
-- The union operation is the core merge of the union-find structure.
unionEquivalentProperties :: TestTree
unionEquivalentProperties = testGroup "Union/Equivalent"
  [ testProperty "union makes points equivalent" $ \(a :: Int) (b :: Int) (c :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        UF.union p1 p2 c
        eq <- UF.equivalent p1 p2
        pure (eq === True)

  , testProperty "union stores the provided value" $ \(a :: Int) (b :: Int) (c :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        UF.union p1 p2 c
        val1 <- UF.get p1
        val2 <- UF.get p2
        pure (val1 === c .&&. val2 === c)

  , testProperty "union three points transitively" $ \(a :: Int) (b :: Int) (c :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        p3 <- UF.fresh c
        UF.union p1 p2 10
        UF.union p2 p3 20
        eq <- UF.equivalent p1 p3
        pure (eq === True)

  , testProperty "union with self is idempotent" $ \(n :: Int) ->
      ioProperty $ do
        p <- UF.fresh n
        UF.union p p 42
        val <- UF.get p
        pure (val === 42)

  , testProperty "union marks one point as redundant" $ \(a :: Int) (b :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        r1Before <- UF.redundant p1
        r2Before <- UF.redundant p2
        UF.union p1 p2 0
        r1After <- UF.redundant p1
        r2After <- UF.redundant p2
        let beforeNeitherRedundant = not r1Before .&&. not r2Before
        let afterExactlyOneRedundant = (r1After && not r2After) .||. (not r1After && r2After)
        pure (beforeNeitherRedundant .&&. afterExactlyOneRedundant)
  ]

-- | Verifies that equivalence is reflexive: every point is equivalent
-- to itself, regardless of whether it has been unioned with anything.
equivalenceReflexiveProperties :: TestTree
equivalenceReflexiveProperties = testGroup "Equivalence Reflexive"
  [ testProperty "fresh point is equivalent to itself" $ \(n :: Int) ->
      ioProperty $ do
        p <- UF.fresh n
        eq <- UF.equivalent p p
        pure (eq === True)

  , testProperty "point is equivalent to itself after set" $ \(n :: Int) (m :: Int) ->
      ioProperty $ do
        p <- UF.fresh n
        UF.set p m
        eq <- UF.equivalent p p
        pure (eq === True)

  , testProperty "point is equivalent to itself after union" $ \(a :: Int) (b :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        UF.union p1 p2 0
        eq1 <- UF.equivalent p1 p1
        eq2 <- UF.equivalent p2 p2
        pure (eq1 === True .&&. eq2 === True)

  , testProperty "repr preserves reflexive equivalence" $ \(n :: Int) ->
      ioProperty $ do
        p <- UF.fresh n
        _ <- UF.repr p
        eq <- UF.equivalent p p
        pure (eq === True)

  , testProperty "fresh point is not redundant" $ \(n :: Int) ->
      ioProperty $ do
        p <- UF.fresh n
        r <- UF.redundant p
        pure (r === False)
  ]

-- | Verifies that equivalence is symmetric after union:
-- if equivalent a b then equivalent b a.
equivalenceSymmetryProperties :: TestTree
equivalenceSymmetryProperties = testGroup "Equivalence Symmetry"
  [ testProperty "equivalent is symmetric after union" $ \(a :: Int) (b :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        UF.union p1 p2 0
        eq12 <- UF.equivalent p1 p2
        eq21 <- UF.equivalent p2 p1
        pure (eq12 === True .&&. eq21 === True)

  , testProperty "equivalent is symmetric for unrelated points" $ \(a :: Int) (b :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        eq12 <- UF.equivalent p1 p2
        eq21 <- UF.equivalent p2 p1
        pure (eq12 === eq21)

  , testProperty "equivalent is symmetric after chain union" $ \(a :: Int) (b :: Int) (c :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        p3 <- UF.fresh c
        UF.union p1 p2 0
        UF.union p2 p3 0
        eq13 <- UF.equivalent p1 p3
        eq31 <- UF.equivalent p3 p1
        pure (eq13 === True .&&. eq31 === True)

  , testProperty "non-equivalent is also symmetric" $ \(a :: Int) (b :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        eq12 <- UF.equivalent p1 p2
        eq21 <- UF.equivalent p2 p1
        pure (eq12 === False .&&. eq21 === False)

  , testProperty "symmetry holds after multiple unions" $ \(a :: Int) (b :: Int) (c :: Int) (d :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        p3 <- UF.fresh c
        p4 <- UF.fresh d
        UF.union p1 p2 0
        UF.union p3 p4 0
        eq12 <- UF.equivalent p1 p2
        eq21 <- UF.equivalent p2 p1
        eq34 <- UF.equivalent p3 p4
        eq43 <- UF.equivalent p4 p3
        eq13 <- UF.equivalent p1 p3
        eq31 <- UF.equivalent p3 p1
        pure (eq12 === eq21 .&&. eq34 === eq43 .&&. eq13 === eq31)
  ]

-- | Verifies that points that have never been unioned together are
-- not equivalent.
nonUnionedProperties :: TestTree
nonUnionedProperties = testGroup "Non-Unioned Points"
  [ testProperty "two fresh points are not equivalent" $ \(a :: Int) (b :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        eq <- UF.equivalent p1 p2
        pure (eq === False)

  , testProperty "three fresh points are pairwise non-equivalent" $ \(a :: Int) (b :: Int) (c :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        p3 <- UF.fresh c
        eq12 <- UF.equivalent p1 p2
        eq13 <- UF.equivalent p1 p3
        eq23 <- UF.equivalent p2 p3
        pure (eq12 === False .&&. eq13 === False .&&. eq23 === False)

  , testProperty "union of subset leaves others non-equivalent" $ \(a :: Int) (b :: Int) (c :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        p3 <- UF.fresh c
        UF.union p1 p2 0
        eq13 <- UF.equivalent p1 p3
        eq23 <- UF.equivalent p2 p3
        pure (eq13 === False .&&. eq23 === False)

  , testProperty "set does not create equivalence" $ \(a :: Int) (b :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        UF.set p1 b
        eq <- UF.equivalent p1 p2
        pure (eq === False)

  , testProperty "modify does not create equivalence" $ \(a :: Int) (b :: Int) ->
      ioProperty $ do
        p1 <- UF.fresh a
        p2 <- UF.fresh b
        UF.modify p1 (const b)
        eq <- UF.equivalent p1 p2
        pure (eq === False)
  ]

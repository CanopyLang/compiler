{-# OPTIONS_GHC -Wall #-}

{-|
Module: Unit.Type.UnionFindTest
Description: Comprehensive test suite for Type.UnionFind module
Copyright: (c) 2024 Canopy Contributors
License: BSD-3-Clause

Tests for the union-find data structure used by the type inference engine.
Covers point creation, value access and mutation, union and equivalence
operations, union-by-weight heuristic, path compression, and multi-element
equivalence classes.

Coverage Target: >= 80% line coverage
Test Categories: Unit, Edge Case

@since 0.19.1
-}
module Unit.Type.UnionFindTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Type.UnionFind as UF

-- | Main test tree containing all Type.UnionFind tests.
tests :: TestTree
tests = testGroup "Type.UnionFind Tests"
  [ freshAndGetTests
  , setTests
  , modifyTests
  , unionAndEquivalentTests
  , redundantTests
  , reprTests
  , equivalenceClassTests
  , unionByWeightTests
  , pathCompressionTests
  , selfUnionTests
  , distinctPointsTests
  , setAfterUnionTests
  , modifyAfterUnionTests
  , largeChainTests
  ]

-- | Tests for 'fresh' and 'get' — basic point creation and value retrieval.
freshAndGetTests :: TestTree
freshAndGetTests = testGroup "fresh and get"
  [ testCase "fresh creates point with initial Int value" $ do
      p <- UF.fresh (42 :: Int)
      val <- UF.get p
      val @?= 42
  , testCase "fresh creates point with initial String value" $ do
      p <- UF.fresh "hello"
      val <- UF.get p
      val @?= "hello"
  , testCase "fresh creates point with initial list value" $ do
      p <- UF.fresh ([1, 2, 3] :: [Int])
      val <- UF.get p
      val @?= [1, 2, 3]
  ]

-- | Tests for 'set' — mutating the descriptor of a point.
setTests :: TestTree
setTests = testGroup "set"
  [ testCase "set changes value and get returns new value" $ do
      p <- UF.fresh (0 :: Int)
      UF.set p 99
      val <- UF.get p
      val @?= 99
  , testCase "set twice keeps latest value" $ do
      p <- UF.fresh "first"
      UF.set p "second"
      UF.set p "third"
      val <- UF.get p
      val @?= "third"
  ]

-- | Tests for 'modify' — applying a function to the descriptor.
modifyTests :: TestTree
modifyTests = testGroup "modify"
  [ testCase "modify applies function to value" $ do
      p <- UF.fresh (10 :: Int)
      UF.modify p (+ 5)
      val <- UF.get p
      val @?= 15
  , testCase "modify twice chains function applications" $ do
      p <- UF.fresh (1 :: Int)
      UF.modify p (* 3)
      UF.modify p (+ 10)
      val <- UF.get p
      val @?= 13
  , testCase "modify with id is identity" $ do
      p <- UF.fresh (42 :: Int)
      UF.modify p id
      val <- UF.get p
      val @?= 42
  ]

-- | Tests for 'union' and 'equivalent' — merging points and checking membership.
unionAndEquivalentTests :: TestTree
unionAndEquivalentTests = testGroup "union and equivalent"
  [ testCase "equivalent returns True after union" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      UF.union p1 p2 100
      eq <- UF.equivalent p1 p2
      eq @?= True
  , testCase "equivalent returns False for unrelated points" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      eq <- UF.equivalent p1 p2
      eq @?= False
  , testCase "union sets new descriptor value" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      UF.union p1 p2 999
      val1 <- UF.get p1
      val2 <- UF.get p2
      val1 @?= 999
      val2 @?= 999
  , testCase "equivalent is reflexive" $ do
      p <- UF.fresh (1 :: Int)
      eq <- UF.equivalent p p
      eq @?= True
  ]

-- | Tests for 'redundant' — checking whether a point is a root or a link.
redundantTests :: TestTree
redundantTests = testGroup "redundant"
  [ testCase "fresh point is not redundant" $ do
      p <- UF.fresh (1 :: Int)
      r <- UF.redundant p
      r @?= False
  , testCase "after union one point becomes redundant" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      UF.union p1 p2 100
      r1 <- UF.redundant p1
      r2 <- UF.redundant p2
      -- Exactly one of p1 or p2 should be redundant (the one linked under the other).
      -- With equal weights the implementation links p2 under p1, making p2 redundant.
      (r1, r2) @?= (False, True)
  , testCase "root point is never redundant" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      p3 <- UF.fresh 3
      UF.union p1 p2 10
      UF.union p1 p3 20
      rootP1 <- UF.redundant p1
      rootP1 @?= False
  ]

-- | Tests for 'repr' — finding the root representative of a point.
reprTests :: TestTree
reprTests = testGroup "repr"
  [ testCase "repr of fresh point is itself" $ do
      p <- UF.fresh (1 :: Int)
      r <- UF.repr p
      (r == p) @?= True
  , testCase "repr of unioned points returns same root" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      UF.union p1 p2 100
      r1 <- UF.repr p1
      r2 <- UF.repr p2
      (r1 == r2) @?= True
  , testCase "repr is idempotent" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      UF.union p1 p2 100
      r1 <- UF.repr p2
      r2 <- UF.repr r1
      (r1 == r2) @?= True
  ]

-- | Tests for transitive equivalence classes built from multiple unions.
equivalenceClassTests :: TestTree
equivalenceClassTests = testGroup "equivalence classes"
  [ testCase "A union B, B union C implies A equivalent C" $ do
      a <- UF.fresh ("A" :: String)
      b <- UF.fresh "B"
      c <- UF.fresh "C"
      UF.union a b "AB"
      UF.union b c "ABC"
      eq <- UF.equivalent a c
      eq @?= True
  , testCase "transitive chain of four points" $ do
      a <- UF.fresh (1 :: Int)
      b <- UF.fresh 2
      c <- UF.fresh 3
      d <- UF.fresh 4
      UF.union a b 10
      UF.union b c 20
      UF.union c d 30
      eqAD <- UF.equivalent a d
      eqAD @?= True
      val <- UF.get a
      val @?= 30
  , testCase "two separate equivalence classes remain distinct" $ do
      a <- UF.fresh (1 :: Int)
      b <- UF.fresh 2
      c <- UF.fresh 3
      d <- UF.fresh 4
      UF.union a b 10
      UF.union c d 20
      eqAB <- UF.equivalent a b
      eqCD <- UF.equivalent c d
      eqAC <- UF.equivalent a c
      eqBD <- UF.equivalent b d
      eqAB @?= True
      eqCD @?= True
      eqAC @?= False
      eqBD @?= False
  , testCase "merging two equivalence classes connects all members" $ do
      a <- UF.fresh (1 :: Int)
      b <- UF.fresh 2
      c <- UF.fresh 3
      d <- UF.fresh 4
      UF.union a b 10
      UF.union c d 20
      UF.union b c 30
      eqAD <- UF.equivalent a d
      eqAD @?= True
      valA <- UF.get a
      valD <- UF.get d
      valA @?= valD
  ]

-- | Tests for union-by-weight heuristic: smaller tree linked under larger tree.
unionByWeightTests :: TestTree
unionByWeightTests = testGroup "union by weight"
  [ testCase "larger tree becomes root when weights differ" $ do
      -- Build a tree of weight 3 rooted at p1
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      p3 <- UF.fresh 3
      UF.union p1 p2 10
      UF.union p1 p3 20
      -- p4 is a singleton (weight 1)
      p4 <- UF.fresh 4
      UF.union p1 p4 30
      -- p1's tree is heavier, so p4 should link under p1's root
      rootP4 <- UF.repr p4
      rootP1 <- UF.repr p1
      (rootP4 == rootP1) @?= True
      r4 <- UF.redundant p4
      r4 @?= True
  , testCase "equal-weight union links second under first" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      -- Both have weight 1; implementation links p2 under p1
      UF.union p1 p2 100
      r1 <- UF.redundant p1
      r2 <- UF.redundant p2
      r1 @?= False
      r2 @?= True
  ]

-- | Tests for path compression — repr should flatten chains.
pathCompressionTests :: TestTree
pathCompressionTests = testGroup "path compression"
  [ testCase "repr compresses path so second call is direct" $ do
      -- Build a chain: p3 -> p2 -> p1 (root)
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      p3 <- UF.fresh 3
      -- p2 links under p1
      UF.union p1 p2 10
      -- p3 links under p2 (which links under p1)
      UF.union p2 p3 20
      -- First repr call from p3 traverses the chain and compresses
      root1 <- UF.repr p3
      -- Second repr call should be direct (path already compressed)
      root2 <- UF.repr p3
      (root1 == root2) @?= True
      -- Both should point to the same root as p1
      rootP1 <- UF.repr p1
      (root1 == rootP1) @?= True
  , testCase "get works correctly after path compression" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      p3 <- UF.fresh 3
      UF.union p1 p2 10
      UF.union p2 p3 20
      -- Force path compression
      _ <- UF.repr p3
      val <- UF.get p3
      val @?= 20
  ]

-- | Tests for union of a point with itself.
selfUnionTests :: TestTree
selfUnionTests = testGroup "self union"
  [ testCase "union with self updates descriptor" $ do
      p <- UF.fresh (1 :: Int)
      UF.union p p 42
      val <- UF.get p
      val @?= 42
  , testCase "union with self does not create link" $ do
      p <- UF.fresh (1 :: Int)
      UF.union p p 42
      r <- UF.redundant p
      r @?= False
  , testCase "union with self is idempotent for structure" $ do
      p <- UF.fresh (1 :: Int)
      UF.union p p 10
      UF.union p p 20
      val <- UF.get p
      val @?= 20
      r <- UF.redundant p
      r @?= False
  ]

-- | Tests that multiple fresh points are distinct.
distinctPointsTests :: TestTree
distinctPointsTests = testGroup "distinct points"
  [ testCase "two fresh points are not equal" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 1
      (p1 == p2) @?= False
  , testCase "two fresh points are not equivalent" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 1
      eq <- UF.equivalent p1 p2
      eq @?= False
  , testCase "many fresh points are all distinct" $ do
      points <- mapM UF.fresh ([1..10] :: [Int])
      eqs <- mapM (uncurry UF.equivalent) (allPairs points)
      all (== False) eqs @?= True
  ]

-- | Tests for 'set' after 'union' — verifying mutations target the representative.
setAfterUnionTests :: TestTree
setAfterUnionTests = testGroup "set after union"
  [ testCase "set on non-root point affects shared descriptor" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      UF.union p1 p2 100
      UF.set p2 200
      val1 <- UF.get p1
      val2 <- UF.get p2
      val1 @?= 200
      val2 @?= 200
  , testCase "set on root point affects shared descriptor" $ do
      p1 <- UF.fresh (1 :: Int)
      p2 <- UF.fresh 2
      UF.union p1 p2 100
      UF.set p1 300
      val2 <- UF.get p2
      val2 @?= 300
  , testCase "set after transitive union visible from all members" $ do
      a <- UF.fresh (1 :: Int)
      b <- UF.fresh 2
      c <- UF.fresh 3
      UF.union a b 10
      UF.union b c 20
      UF.set c 999
      valA <- UF.get a
      valB <- UF.get b
      valC <- UF.get c
      valA @?= 999
      valB @?= 999
      valC @?= 999
  ]

-- | Tests for 'modify' after 'union' — function application on the shared descriptor.
modifyAfterUnionTests :: TestTree
modifyAfterUnionTests = testGroup "modify after union"
  [ testCase "modify on non-root point modifies shared descriptor" $ do
      p1 <- UF.fresh (10 :: Int)
      p2 <- UF.fresh 20
      UF.union p1 p2 100
      UF.modify p2 (+ 50)
      val1 <- UF.get p1
      val2 <- UF.get p2
      val1 @?= 150
      val2 @?= 150
  , testCase "modify chained across union" $ do
      a <- UF.fresh (0 :: Int)
      b <- UF.fresh 0
      c <- UF.fresh 0
      UF.union a b 1
      UF.union b c 2
      UF.modify a (+ 10)
      UF.modify c (* 3)
      val <- UF.get b
      val @?= 36
  ]

-- | Tests for large chains to verify correctness at scale.
largeChainTests :: TestTree
largeChainTests = testGroup "large chains"
  [ testCase "chain of 100 unions forms single equivalence class" $ do
      points <- mapM UF.fresh [1..100 :: Int]
      unionChain points
      eqFirstLast <- UF.equivalent (Prelude.head points) (Prelude.last points)
      eqFirstLast @?= True
  , testCase "all points in chain of 50 share same value" $ do
      points <- mapM UF.fresh [1..50 :: Int]
      unionChain points
      vals <- mapM UF.get points
      all (== Prelude.last vals) vals @?= True
  , testCase "repr converges for all points in large chain" $ do
      points <- mapM UF.fresh [1..100 :: Int]
      unionChain points
      roots <- mapM UF.repr points
      let firstRoot = Prelude.head roots
      all (== firstRoot) roots @?= True
  ]

-- | Generate all distinct pairs from a list.
allPairs :: [a] -> [(a, a)]
allPairs [] = []
allPairs (x : xs) = Prelude.map (\y -> (x, y)) xs ++ allPairs xs

-- | Union a list of points in a chain: p1 with p2, p2 with p3, etc.
-- Uses the index as the new descriptor for each union step.
unionChain :: [UF.Point Int] -> IO ()
unionChain [] = pure ()
unionChain [_] = pure ()
unionChain (x : y : rest) = do
  UF.union x y 0
  unionChain (y : rest)

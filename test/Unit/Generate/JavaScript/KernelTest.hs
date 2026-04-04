{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Generate.JavaScript.KernelTest - Tests for Kernel JS code generation
--
-- This module provides unit tests for the pure functions exported by
-- "Generate.JavaScript.Kernel". The focus is on the Trie operations
-- (which are entirely pure and easy to construct), the drawCycle helper,
-- and the generateEnum / generateBox statement-level generators.
--
-- == Test Coverage
--
-- * Trie construction: emptyTrie, addToTrie, segmentsToTrie
-- * Trie merging: merge, checkedMerge
-- * Deep segment paths: three-level nesting verification
-- * Overlapping merges: shared-prefix key accumulation
-- * Export serialisation shape: trie sub-map sizes
-- * drawCycle: verifies the cycle diagram contains expected names
-- * generateEnum (Dev mode): verifies Var statement is produced
-- * generateBox (Dev mode): verifies Var statement is produced
--
-- @since 0.19.1
module Unit.Generate.JavaScript.KernelTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import qualified Data.Set as Set
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Kernel as Kernel
import qualified Generate.Mode as Mode

-- | Root test tree for Generate.JavaScript.Kernel.
tests :: TestTree
tests = testGroup "Generate.JavaScript.Kernel Tests"
  [ emptyTrieTests
  , segmentsToTrieTests
  , addToTrieTests
  , mergeTests
  , checkedMergeTests
  , drawCycleTests
  , generateEnumTests
  , generateBoxTests
  , deepSegmentTrieTests
  , overlappingMergeTests
  ]

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | Development mode with no debug types and all flags off.
devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

-- | A simple canonical module name using the basics package.
basicsHome :: ModuleName.Canonical
basicsHome = ModuleName.basics

-- | A second canonical home for merge/collision tests.
listHome :: ModuleName.Canonical
listHome = ModuleName.list

-- | A third canonical home for three-module tests.
maybeHome :: ModuleName.Canonical
maybeHome = ModuleName.maybe

-- | Global referencing the identity function in Basics.
identityGlobal :: Opt.Global
identityGlobal = Opt.Global basicsHome Name.identity

-- ---------------------------------------------------------------------------
-- emptyTrie
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.emptyTrie'.
--
-- An empty trie has no main and no sub-tries.
emptyTrieTests :: TestTree
emptyTrieTests = testGroup "emptyTrie"
  [ testCase "emptyTrie has no main" $
      assertBool "emptyTrie _main should be Nothing" (isNothing (Kernel._main Kernel.emptyTrie))

  , testCase "emptyTrie has empty subs map" $
      Map.null (Kernel._subs Kernel.emptyTrie) @?= True
  ]

-- ---------------------------------------------------------------------------
-- segmentsToTrie
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.segmentsToTrie'.
segmentsToTrieTests :: TestTree
segmentsToTrieTests = testGroup "segmentsToTrie"
  [ testCase "empty segments produces leaf trie with main" $
      let trie = Kernel.segmentsToTrie basicsHome [] Opt.TestMain
      in show (Kernel._main trie) @?= show (Just (basicsHome, Opt.TestMain))

  , testCase "empty segments produces leaf trie with no subs" $
      let trie = Kernel.segmentsToTrie basicsHome [] Opt.TestMain
      in Map.null (Kernel._subs trie) @?= True

  , testCase "single segment produces no main at root" $
      let trie = Kernel.segmentsToTrie basicsHome [Name.fromChars "App"] Opt.TestMain
      in assertBool "segmentsToTrie with segment: _main should be Nothing" (isNothing (Kernel._main trie))

  , testCase "single segment produces one sub-entry" $
      let trie = Kernel.segmentsToTrie basicsHome [Name.fromChars "App"] Opt.TestMain
      in Map.size (Kernel._subs trie) @?= 1

  , testCase "two segments produces nested sub-tries" $
      let segs = [Name.fromChars "App", Name.fromChars "Main"]
          trie = Kernel.segmentsToTrie basicsHome segs Opt.TestMain
          outerSubs = Kernel._subs trie
      in Map.size outerSubs @?= 1
  ]

-- ---------------------------------------------------------------------------
-- addToTrie
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.addToTrie'.
--
-- addToTrie inserts a module into the trie using its dot-separated name
-- segments extracted from the Canonical module's _module field.
addToTrieTests :: TestTree
addToTrieTests = testGroup "addToTrie"
  [ testCase "inserting into emptyTrie produces non-empty subs" $
      let trie = Kernel.addToTrie basicsHome Opt.TestMain Kernel.emptyTrie
      in Map.null (Kernel._subs trie) @?= False

  , testCase "two distinct modules produce two sub-entries at root" $
      let trie0 = Kernel.emptyTrie
          trie1 = Kernel.addToTrie basicsHome Opt.TestMain trie0
          trie2 = Kernel.addToTrie listHome Opt.TestMain trie1
      in Map.size (Kernel._subs trie2) @?= 2

  , testCase "same module inserted once appears exactly once" $
      let trie = Kernel.addToTrie basicsHome Opt.TestMain Kernel.emptyTrie
      in Map.size (Kernel._subs trie) @?= 1
  ]

-- ---------------------------------------------------------------------------
-- merge
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.merge'.
mergeTests :: TestTree
mergeTests = testGroup "merge"
  [ testCase "merging two empty tries yields empty trie" $
      let merged = Kernel.merge Kernel.emptyTrie Kernel.emptyTrie
      in do
           assertBool "merged empty tries: _main should be Nothing" (isNothing (Kernel._main merged))
           Map.null (Kernel._subs merged) @?= True

  , testCase "merging non-overlapping single-segment tries combines subs" $
      let t1 = Kernel.segmentsToTrie basicsHome [Name.fromChars "Basics"] Opt.TestMain
          t2 = Kernel.segmentsToTrie listHome [Name.fromChars "List"] Opt.TestMain
          merged = Kernel.merge t1 t2
      in Map.size (Kernel._subs merged) @?= 2

  , testCase "merging two tries with same sub-key recurses into that sub" $
      let t1 = Kernel.segmentsToTrie basicsHome [Name.fromChars "App", Name.fromChars "Main"] Opt.TestMain
          t2 = Kernel.segmentsToTrie listHome [Name.fromChars "App", Name.fromChars "Other"] Opt.TestMain
          merged = Kernel.merge t1 t2
          appSub = Map.lookup (Name.fromChars "App") (Kernel._subs merged)
      in fmap (Map.size . Kernel._subs) appSub @?= Just 2
  ]

-- ---------------------------------------------------------------------------
-- checkedMerge
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.checkedMerge'.
--
-- checkedMerge is pure: Nothing+Nothing=Nothing, Nothing+Just=Just,
-- Just+Nothing=Just. The Just+Just case calls InternalError.report so
-- we cannot test it without catching the error signal.
checkedMergeTests :: TestTree
checkedMergeTests = testGroup "checkedMerge"
  [ testCase "Nothing and Nothing yields Nothing" $
      Kernel.checkedMerge (Nothing :: Maybe Int) Nothing @?= Nothing

  , testCase "Nothing and Just yields Just" $
      Kernel.checkedMerge (Nothing :: Maybe Int) (Just 42) @?= Just 42

  , testCase "Just and Nothing yields Just" $
      Kernel.checkedMerge (Just 42 :: Maybe Int) Nothing @?= Just 42
  ]

-- ---------------------------------------------------------------------------
-- drawCycle
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.drawCycle'.
--
-- The output is a ByteString Builder; we render it via show on the
-- lazy ByteString for inspection.
drawCycleTests :: TestTree
drawCycleTests = testGroup "drawCycle"
  [ testCase "single-name cycle contains that name" $
      let result = show (Kernel.drawCycle [Name.fromChars "foo"])
      in assertBool "should contain 'foo'" ("foo" `containedIn` result)

  , testCase "two-name cycle contains both names" $
      let result = show (Kernel.drawCycle [Name.fromChars "alpha", Name.fromChars "beta"])
      in assertBool "should contain both names"
           (("alpha" `containedIn` result) && ("beta" `containedIn` result))

  , testCase "empty cycle produces some output" $
      let result = show (Kernel.drawCycle [])
      in assertBool "should produce non-empty output" (not (null result))
  ]

-- | Check whether a substring appears in a string.
containedIn :: String -> String -> Bool
containedIn sub str = sub `elem` tails str
  where
    tails [] = []
    tails s@(_ : rest) = (take (length sub) s) : tails rest

-- ---------------------------------------------------------------------------
-- generateEnum
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.generateEnum' in Dev mode.
--
-- In Dev mode the result is a JS.Var statement wrapping a constructor call.
generateEnumTests :: TestTree
generateEnumTests = testGroup "generateEnum (Dev mode)"
  [ testCase "generateEnum produces JS.Var statement" $
      let stmt = Kernel.generateEnum devMode identityGlobal Index.first
      in case stmt of
           JS.Var _ _ -> pure ()
           other -> assertFailure ("Expected JS.Var, got: " ++ show other)

  , testCase "generateEnum with second index produces JS.Var statement" $
      let stmt = Kernel.generateEnum devMode identityGlobal Index.second
      in case stmt of
           JS.Var _ _ -> pure ()
           other -> assertFailure ("Expected JS.Var, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- generateBox
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.generateBox' in Dev mode.
--
-- In Dev mode the result is a JS.Var statement wrapping a constructor call.
generateBoxTests :: TestTree
generateBoxTests = testGroup "generateBox (Dev mode)"
  [ testCase "generateBox produces JS.Var statement" $
      let stmt = Kernel.generateBox devMode identityGlobal
      in case stmt of
           JS.Var _ _ -> pure ()
           other -> assertFailure ("Expected JS.Var, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- Deep segment trie tests
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.segmentsToTrie' with three-level path segments.
--
-- Verifies that deeply nested paths produce the correct trie structure
-- with proper nesting of sub-tries at every level.
deepSegmentTrieTests :: TestTree
deepSegmentTrieTests = testGroup "deep segment trie construction"
  [ testCase "three-level path has exactly one sub at each nesting level" $
      let segs = map Name.fromChars ["A", "B", "C"]
          trie = Kernel.segmentsToTrie basicsHome segs Opt.TestMain
          level1 = Kernel._subs trie
          level2 = maybe Map.empty Kernel._subs (Map.lookup (Name.fromChars "A") level1)
      in do
           Map.size level1 @?= 1
           Map.size level2 @?= 1

  , testCase "three-level path innermost sub has one entry" $
      let segs = map Name.fromChars ["A", "B", "C"]
          trie = Kernel.segmentsToTrie basicsHome segs Opt.TestMain
          level1 = Kernel._subs trie
          level2 = maybe Map.empty Kernel._subs (Map.lookup (Name.fromChars "A") level1)
          level3 = maybe Map.empty Kernel._subs (Map.lookup (Name.fromChars "B") level2)
      in Map.size level3 @?= 1

  , testCase "three-level path leaf node has no further subs" $
      let segs = map Name.fromChars ["A", "B", "C"]
          trie = Kernel.segmentsToTrie basicsHome segs Opt.TestMain
          level1 = Kernel._subs trie
          level2 = maybe Map.empty Kernel._subs (Map.lookup (Name.fromChars "A") level1)
          level3 = maybe Map.empty Kernel._subs (Map.lookup (Name.fromChars "B") level2)
          leaf = Map.lookup (Name.fromChars "C") level3
      in assertBool "leaf sub should be empty"
           (maybe True (Map.null . Kernel._subs) leaf)
  ]

-- ---------------------------------------------------------------------------
-- Overlapping merge tests
-- ---------------------------------------------------------------------------

-- | Tests for 'Kernel.merge' with shared prefix keys.
--
-- Verifies that merging tries with overlapping keys correctly recurses
-- into shared sub-tries and accumulates all entries from both sides.
overlappingMergeTests :: TestTree
overlappingMergeTests = testGroup "merge with overlapping keys"
  [ testCase "two paths sharing a prefix key merge inner subs" $
      let t1 = Kernel.segmentsToTrie basicsHome [Name.fromChars "X", Name.fromChars "A"] Opt.TestMain
          t2 = Kernel.segmentsToTrie listHome  [Name.fromChars "X", Name.fromChars "B"] Opt.TestMain
          merged = Kernel.merge t1 t2
          xSub = Map.lookup (Name.fromChars "X") (Kernel._subs merged)
          innerSize = fmap (Map.size . Kernel._subs) xSub
      in innerSize @?= Just 2

  , testCase "merging leaf trie with branch trie preserves both" $
      let leafTrie = Kernel.segmentsToTrie basicsHome [] Opt.TestMain
          branchTrie = Kernel.segmentsToTrie listHome [Name.fromChars "Sub"] Opt.TestMain
          merged = Kernel.merge leafTrie branchTrie
      in do
           assertBool "merged trie should retain main from leafTrie"
             (case Kernel._main merged of Just _ -> True; Nothing -> False)
           Map.size (Kernel._subs merged) @?= 1

  , testCase "addToTrie three distinct modules yields three root subs" $
      let trie0 = Kernel.emptyTrie
          trie1 = Kernel.addToTrie basicsHome Opt.TestMain trie0
          trie2 = Kernel.addToTrie listHome Opt.TestMain trie1
          trie3 = Kernel.addToTrie maybeHome Opt.TestMain trie2
      in Map.size (Kernel._subs trie3) @?= 3
  ]

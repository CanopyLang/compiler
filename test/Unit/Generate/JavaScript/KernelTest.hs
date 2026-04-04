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

  , testCase "empty cycle contains box borders" $
      let result = show (Kernel.drawCycle [])
      in assertBool "should contain top border" ("\x250C" `containedIn` result)
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

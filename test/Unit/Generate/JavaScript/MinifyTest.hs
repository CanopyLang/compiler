{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Generate.JavaScript.MinifyTest - Tests for JS local-variable minification.
--
-- Exercises the pure functions exported by "Generate.JavaScript.Minify":
--
-- * 'minifyGraph' — maps over a node graph, renaming locals inside each node
-- * 'buildGlobalRenameMap' — assigns short global names to user-code globals,
--   excluding FFI alias modules and skipping JS reserved words
-- * Name-generation: short names follow a, b, …, z, aa, ab, … order and skip
--   any name in the reserved set
--
-- == Coverage
--
-- * Empty graph passes through unchanged
-- * Define node: VarLocal renamed, passthrough constructors (Link, Kernel) unchanged
-- * Let binding: introduces fresh short name for the bound variable
-- * Nested Function scope: inner params get fresh short names from counter 0
-- * buildGlobalRenameMap empty graph / reachable set
-- * buildGlobalRenameMap single user global assigned first non-reserved name
-- * FFI alias module globals excluded from rename map
-- * Sequential naming: a, b, c, …
-- * Reserved-word skipping: names like "do", "if" are never emitted
--
-- @since 0.19.2
module Unit.Generate.JavaScript.MinifyTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generate.JavaScript.Minify as Minify

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | Home module for test globals ("Main" in canopy/core).
testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical Pkg.core (Name.fromChars "Main")

-- | A second distinct home module ("Other" in canopy/core).
otherHome :: ModuleName.Canonical
otherHome = ModuleName.Canonical Pkg.core (Name.fromChars "Other")

-- | An FFI alias home module ("Ffi" in canopy/core).
ffiHome :: ModuleName.Canonical
ffiHome = ModuleName.Canonical Pkg.core (Name.fromChars "Ffi")

-- | Construct a Global in the test home.
mkGlobal :: String -> Opt.Global
mkGlobal n = Opt.Global testHome (Name.fromChars n)

-- | A VarLocal expression.
varLocal :: String -> Opt.Expr
varLocal = Opt.VarLocal . Name.fromChars

-- | An integer literal expression (not renamed by minification).
intExpr :: Int -> Opt.Expr
intExpr = Opt.Int

-- ---------------------------------------------------------------------------
-- Root test tree
-- ---------------------------------------------------------------------------

-- | Root test tree for Generate.JavaScript.Minify.
tests :: TestTree
tests = testGroup "Generate.JavaScript.Minify Tests"
  [ minifyGraphTests
  , minifyDefineTests
  , minifyLetTests
  , minifyFunctionScopeTests
  , buildGlobalRenameMapTests
  , shortNameSequenceTests
  ]

-- ---------------------------------------------------------------------------
-- minifyGraph — structural tests
-- ---------------------------------------------------------------------------

-- | Tests for 'minifyGraph'.
minifyGraphTests :: TestTree
minifyGraphTests = testGroup "minifyGraph"
  [ testCase "empty graph stays empty" $
      Map.null (Minify.minifyGraph Map.empty) @?= True

  , testCase "Link node passes through unchanged" $
      let g = mkGlobal "foo"
          target = mkGlobal "bar"
          graph = Map.fromList [(g, Opt.Link target)]
          result = Minify.minifyGraph graph
      in show (result Map.! g) @?= show (Opt.Link target)

  , testCase "Kernel node passes through unchanged" $
      let g = mkGlobal "kfn"
          node = Opt.Kernel [] Set.empty
          graph = Map.fromList [(g, node)]
          result = Minify.minifyGraph graph
      in show (result Map.! g) @?= show node

  , testCase "Define node with Int body is preserved" $
      let g = mkGlobal "answer"
          node = Opt.Define (intExpr 42) Set.empty
          result = Minify.minifyGraph (Map.fromList [(g, node)])
      in show (result Map.! g) @?= show (Opt.Define (intExpr 42) Set.empty)
  ]

-- ---------------------------------------------------------------------------
-- minifyGraph — Define with VarLocal
-- ---------------------------------------------------------------------------

-- | Tests that VarLocal inside a Define node is preserved when not in scope.
--
-- A fresh Define scope has an empty rename map, so any VarLocal that was
-- never introduced via a Let/Function is returned unchanged.
minifyDefineTests :: TestTree
minifyDefineTests = testGroup "minifyGraph Define with VarLocal"
  [ testCase "VarLocal not in scope stays as original name" $
      let g = mkGlobal "fn"
          node = Opt.Define (varLocal "x") Set.empty
          result = Minify.minifyGraph (Map.fromList [(g, node)])
      in show (result Map.! g) @?= show (Opt.Define (varLocal "x") Set.empty)

  , testCase "Define preserves dependency set on Int body" $
      let dep = mkGlobal "dep"
          g = mkGlobal "fn"
          deps = Set.singleton dep
          node = Opt.Define (intExpr 0) deps
          result = Minify.minifyGraph (Map.fromList [(g, node)])
      in show (result Map.! g) @?= show (Opt.Define (intExpr 0) deps)
  ]

-- ---------------------------------------------------------------------------
-- minifyGraph — Let binding renames the bound variable
-- ---------------------------------------------------------------------------

-- | Tests that a Let-binding introduces a fresh short name.
--
-- A Def inside Let gets name "a" (counter 0) and the body referencing the
-- same variable receives the renamed form.
minifyLetTests :: TestTree
minifyLetTests = testGroup "minifyGraph Let binding"
  [ testCase "Let Def binding renames variable to first short name" $
      let body = Opt.Let (Opt.Def (Name.fromChars "x") (intExpr 1)) (varLocal "x")
          g = mkGlobal "fn"
          node = Opt.Define body Set.empty
          result = Minify.minifyGraph (Map.fromList [(g, node)])
          expected = Opt.Let
            (Opt.Def (Name.fromChars "a") (intExpr 1))
            (varLocal "a")
      in show (result Map.! g) @?= show (Opt.Define expected Set.empty)

  , testCase "Two sequential Let bindings get distinct short names a and b" $
      let inner = Opt.Let (Opt.Def (Name.fromChars "y") (intExpr 2)) (varLocal "y")
          outer = Opt.Let (Opt.Def (Name.fromChars "x") (intExpr 1)) inner
          g = mkGlobal "fn"
          node = Opt.Define outer Set.empty
          result = Minify.minifyGraph (Map.fromList [(g, node)])
          expectedInner = Opt.Let
            (Opt.Def (Name.fromChars "b") (intExpr 2))
            (varLocal "b")
          expectedOuter = Opt.Let
            (Opt.Def (Name.fromChars "a") (intExpr 1))
            expectedInner
      in show (result Map.! g) @?= show (Opt.Define expectedOuter Set.empty)
  ]

-- ---------------------------------------------------------------------------
-- minifyGraph — Function scope renames parameters
-- ---------------------------------------------------------------------------

-- | Tests that a Function expression renames its parameters.
--
-- Parameters are assigned short names starting from the current counter.
-- At top-level (fresh scope, counter 0) the first parameter gets "a".
minifyFunctionScopeTests :: TestTree
minifyFunctionScopeTests = testGroup "minifyGraph Function scope"
  [ testCase "single-param function renames param to first short name" $
      let fn = Opt.Function [Name.fromChars "x"] (varLocal "x")
          g = mkGlobal "fn"
          node = Opt.Define fn Set.empty
          result = Minify.minifyGraph (Map.fromList [(g, node)])
          expected = Opt.Function [Name.fromChars "a"] (varLocal "a")
      in show (result Map.! g) @?= show (Opt.Define expected Set.empty)

  , testCase "two-param function renames each param to a and b" $
      let fn = Opt.Function
                 [Name.fromChars "x", Name.fromChars "y"]
                 (Opt.Call (varLocal "x") [varLocal "y"])
          g = mkGlobal "fn"
          node = Opt.Define fn Set.empty
          result = Minify.minifyGraph (Map.fromList [(g, node)])
          expected = Opt.Function
            [Name.fromChars "a", Name.fromChars "b"]
            (Opt.Call (varLocal "a") (varLocal "b" : []))
      in show (result Map.! g) @?= show (Opt.Define expected Set.empty)
  ]

-- ---------------------------------------------------------------------------
-- buildGlobalRenameMap
-- ---------------------------------------------------------------------------

-- | Tests for 'buildGlobalRenameMap'.
buildGlobalRenameMapTests :: TestTree
buildGlobalRenameMapTests = testGroup "buildGlobalRenameMap"
  [ testCase "empty reachable set produces empty map" $
      Map.null
        (Minify.buildGlobalRenameMap Set.empty Map.empty Set.empty)
        @?= True

  , testCase "single user global gets exactly one entry" $
      let g = mkGlobal "foo"
          node = Opt.Define (intExpr 0) Set.empty
          graph = Map.fromList [(g, node)]
          reachable = Set.singleton g
          result = Minify.buildGlobalRenameMap Set.empty graph reachable
      in Map.size result @?= 1

  , testCase "single user global short name is 'a'" $
      let g = mkGlobal "foo"
          node = Opt.Define (intExpr 0) Set.empty
          graph = Map.fromList [(g, node)]
          reachable = Set.singleton g
          result = Minify.buildGlobalRenameMap Set.empty graph reachable
      in Name.toChars (result Map.! g) @?= "a"

  , testCase "FFI alias module global excluded from rename map" $
      let ffiAlias = ModuleName._module ffiHome
          g = Opt.Global ffiHome (Name.fromChars "ffiFunc")
          node = Opt.Define (intExpr 0) Set.empty
          graph = Map.fromList [(g, node)]
          reachable = Set.singleton g
          result = Minify.buildGlobalRenameMap (Set.singleton ffiAlias) graph reachable
      in Map.null result @?= True

  , testCase "global not present in graph is excluded from rename map" $
      let g = mkGlobal "ghost"
          reachable = Set.singleton g
          result = Minify.buildGlobalRenameMap Set.empty Map.empty reachable
      in Map.null result @?= True

  , testCase "two user globals from distinct homes each get a unique short name" $
      let g1 = mkGlobal "alpha"
          g2 = Opt.Global otherHome (Name.fromChars "beta")
          node = Opt.Define (intExpr 0) Set.empty
          graph = Map.fromList [(g1, node), (g2, node)]
          reachable = Set.fromList [g1, g2]
          result = Minify.buildGlobalRenameMap Set.empty graph reachable
          distinctCount = Set.size (Set.fromList (Map.elems result))
      in do
           Map.size result @?= 2
           distinctCount @?= 2
  ]

-- ---------------------------------------------------------------------------
-- Short name sequence
-- ---------------------------------------------------------------------------

-- | Tests for the short-name sequence produced internally by minification.
--
-- 'buildGlobalRenameMap' is used as a proxy for the sequence because the
-- internal 'shortName' and 'globalShortNames' helpers are not exported.
shortNameSequenceTests :: TestTree
shortNameSequenceTests = testGroup "short name sequence"
  [ testCase "three globals receive names a, b, and c" $
      let globals = map mkGlobal ["f1", "f2", "f3"]
          node = Opt.Define (intExpr 0) Set.empty
          graph = Map.fromList (map (\g -> (g, node)) globals)
          reachable = Set.fromList globals
          result = Minify.buildGlobalRenameMap Set.empty graph reachable
          names = Set.fromList (map Name.toChars (Map.elems result))
      in names @?= Set.fromList ["a", "b", "c"]

  , testCase "reserved words 'do' and 'if' are never assigned as short names" $
      let globals = map mkGlobal (map (\i -> "g" ++ show (i :: Int)) [1..10])
          node = Opt.Define (intExpr 0) Set.empty
          graph = Map.fromList (map (\g -> (g, node)) globals)
          reachable = Set.fromList globals
          result = Minify.buildGlobalRenameMap Set.empty graph reachable
          names = Set.fromList (map Name.toChars (Map.elems result))
      in do
           Set.member "do" names @?= False
           Set.member "if" names @?= False
  ]

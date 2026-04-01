
-- | Tests for 'Generate.JavaScript.Minify'.
--
-- Covers local variable renaming ('minifyGraph') and global short-name
-- assignment ('buildGlobalRenameMap').
--
-- @since 0.19.2
module Unit.Generate.MinifyTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map
import Canopy.Data.Name (Name)
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import qualified Generate.JavaScript.Minify as Minify
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Minify"
    [ functionArgTests,
      letBindingTests,
      nestedScopeTests,
      globalPreservationTests,
      kernelPreservationTests,
      buildGlobalRenameMapTests
    ]

-- | Assert Show-based equality for Opt.Expr (no Eq instance).
_assertExprEq :: String -> Opt.Expr -> Opt.Expr -> Assertion
_assertExprEq msg expected actual =
  assertEqual msg (show expected) (show actual)

-- FUNCTION ARG TESTS

functionArgTests :: TestTree
functionArgTests =
  testGroup
    "function args are renamed"
    [ testCase "single arg renamed to a" $
        let input = defineNode (Opt.Function [name "message"] (Opt.VarLocal (name "message")))
            result = Minify.minifyGraph (Map.singleton testGlobal input)
            expected = defineNode (Opt.Function [name "a"] (Opt.VarLocal (name "a")))
         in assertNodeExprEq "single arg" expected (lookupNode testGlobal result),
      testCase "three args renamed to a, b, c" $
        let input = defineNode (Opt.Function [name "first", name "second", name "third"] (Opt.VarLocal (name "second")))
            result = Minify.minifyGraph (Map.singleton testGlobal input)
            expected = defineNode (Opt.Function [name "a", name "b", name "c"] (Opt.VarLocal (name "b")))
         in assertNodeExprEq "three args" expected (lookupNode testGlobal result)
    ]

-- LET BINDING TESTS

letBindingTests :: TestTree
letBindingTests =
  testGroup
    "let-binding names are renamed"
    [ testCase "let-bound var renamed" $
        let input = defineNode
              (Opt.Let
                (Opt.Def (name "result") (Opt.Int 42))
                (Opt.VarLocal (name "result")))
            result = Minify.minifyGraph (Map.singleton testGlobal input)
            expected = defineNode
              (Opt.Let
                (Opt.Def (name "a") (Opt.Int 42))
                (Opt.VarLocal (name "a")))
         in assertNodeExprEq "let renamed" expected (lookupNode testGlobal result)
    ]

-- NESTED SCOPE TESTS

nestedScopeTests :: TestTree
nestedScopeTests =
  testGroup
    "nested functions get independent scopes"
    [ testCase "inner function reuses names" $
        let input = defineNode
              (Opt.Function [name "outer"]
                (Opt.Call
                  (Opt.Function [name "inner"] (Opt.VarLocal (name "inner")))
                  [Opt.VarLocal (name "outer")]))
            result = Minify.minifyGraph (Map.singleton testGlobal input)
            -- outer -> a, inner -> b (continues counter from outer scope)
            expected = defineNode
              (Opt.Function [name "a"]
                (Opt.Call
                  (Opt.Function [name "b"] (Opt.VarLocal (name "b")))
                  [Opt.VarLocal (name "a")]))
         in assertNodeExprEq "nested scopes" expected (lookupNode testGlobal result)
    ]

-- GLOBAL PRESERVATION TESTS

globalPreservationTests :: TestTree
globalPreservationTests =
  testGroup
    "global references are NOT renamed"
    [ testCase "VarGlobal passes through unchanged" $
        let globalRef = Opt.VarGlobal (Opt.Global testHome (name "helper"))
            input = defineNode globalRef
            result = Minify.minifyGraph (Map.singleton testGlobal input)
         in assertNodeExprEq "global preserved" input (lookupNode testGlobal result)
    ]

-- KERNEL PRESERVATION TESTS

kernelPreservationTests :: TestTree
kernelPreservationTests =
  testGroup
    "kernel references are NOT renamed"
    [ testCase "VarRuntime passes through unchanged" $
        let kernelRef = Opt.VarRuntime (name "utils") (name "eq")
            input = defineNode kernelRef
            result = Minify.minifyGraph (Map.singleton testGlobal input)
         in assertNodeExprEq "kernel preserved" input (lookupNode testGlobal result)
    ]

-- HELPERS

name :: String -> Name
name = Name.fromChars

testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical Pkg.core (name "Test")

testGlobal :: Opt.Global
testGlobal = Opt.Global testHome (name "myFunc")

defineNode :: Opt.Expr -> Opt.Node
defineNode expr = Opt.Define expr Set.empty

lookupNode :: Opt.Global -> Map.Map Opt.Global Opt.Node -> Opt.Node
lookupNode g m = case Map.lookup g m of
  Just n -> n
  Nothing -> Opt.Define (Opt.Int 0) Set.empty

assertNodeExprEq :: String -> Opt.Node -> Opt.Node -> Assertion
assertNodeExprEq msg expected actual =
  assertEqual msg (show expected) (show actual)


-- BUILD GLOBAL RENAME MAP TESTS

buildGlobalRenameMapTests :: TestTree
buildGlobalRenameMapTests =
  testGroup
    "buildGlobalRenameMap"
    [ testCase "empty reachable set produces empty rename map" $
        let result = Minify.buildGlobalRenameMap Set.empty Map.empty Set.empty
         in Map.size result @?= 0,
      testCase "single user global gets a short name assigned" $
        let graph = Map.singleton testGlobal (defineNode (Opt.Int 1))
            reachable = Set.singleton testGlobal
            result = Minify.buildGlobalRenameMap Set.empty graph reachable
         in Map.member testGlobal result @?= True,
      testCase "global from FFI alias module is excluded from rename map" $
        let aliasModName = Name.fromChars "MyFFI"
            ffiHome = ModuleName.Canonical Pkg.core aliasModName
            ffiGlobal = Opt.Global ffiHome (name "jsFunc")
            graph = Map.singleton ffiGlobal (defineNode (Opt.Int 1))
            reachable = Set.singleton ffiGlobal
            ffiAliases = Set.singleton aliasModName
            result = Minify.buildGlobalRenameMap ffiAliases graph reachable
         in Map.member ffiGlobal result @?= False,
      testCase "global not in graph is excluded from rename map" $
        let notInGraph = Opt.Global testHome (name "phantom")
            graph = Map.singleton testGlobal (defineNode (Opt.Int 1))
            reachable = Set.singleton notInGraph
            result = Minify.buildGlobalRenameMap Set.empty graph reachable
         in Map.member notInGraph result @?= False,
      testCase "assigned names do not include JS reserved word 'if'" $
        let result = Minify.buildGlobalRenameMap Set.empty manyGlobalsGraph manyReachable
            assignedNames = map Name.toChars (Map.elems result)
         in elem "if" assignedNames @?= False,
      testCase "assigned names do not include JS reserved word 'for'" $
        let result = Minify.buildGlobalRenameMap Set.empty manyGlobalsGraph manyReachable
            assignedNames = map Name.toChars (Map.elems result)
         in elem "for" assignedNames @?= False,
      testCase "two user globals get different short names" $
        let g1 = Opt.Global testHome (name "func1")
            g2 = Opt.Global testHome (name "func2")
            graph = Map.fromList
              [ (g1, defineNode (Opt.Int 1))
              , (g2, defineNode (Opt.Int 2))
              ]
            reachable = Set.fromList [g1, g2]
            result = Minify.buildGlobalRenameMap Set.empty graph reachable
            names = Map.elems result
         in length (Set.fromList names) @?= 2,
      testCase "same input produces same output (deterministic)" $
        let graph = Map.singleton testGlobal (defineNode (Opt.Int 1))
            reachable = Set.singleton testGlobal
            result1 = Minify.buildGlobalRenameMap Set.empty graph reachable
            result2 = Minify.buildGlobalRenameMap Set.empty graph reachable
         in result1 @?= result2
    ]
  where
    manyGlobalsGraph :: Map.Map Opt.Global Opt.Node
    manyGlobalsGraph =
      Map.fromList
        [ (Opt.Global testHome (name n), defineNode (Opt.Int 0))
        | n <- map (\i -> "func" ++ show i) [(1 :: Int)..50]
        ]
    manyReachable :: Set.Set Opt.Global
    manyReachable = Map.keysSet manyGlobalsGraph

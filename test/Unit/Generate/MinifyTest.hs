{-# OPTIONS_GHC -Wall #-}

module Unit.Generate.MinifyTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map
import Data.Name (Name)
import qualified Data.Name as Name
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
      kernelPreservationTests
    ]

-- | Assert Show-based equality for Opt.Expr (no Eq instance).
assertExprEq :: String -> Opt.Expr -> Opt.Expr -> Assertion
assertExprEq msg expected actual =
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
    [ testCase "VarKernel passes through unchanged" $
        let kernelRef = Opt.VarKernel (name "utils") (name "eq")
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

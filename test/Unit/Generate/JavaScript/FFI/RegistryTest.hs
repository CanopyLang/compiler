{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.JavaScript.FFI.Registry'.
--
-- Covers:
--   * 'buildFFIRegistry' / 'buildFFIRegistryFull' — registry construction,
--     parse failure handling, comma-declaration aliases
--   * 'closeFFIDeps' — transitive dependency closure
--   * 'emitNeededBlocks' — source-order emission, prod vs dev rendering
--   * 'FFIRegistryResult' fields on success and failure
--
-- @since 0.20.2
module Unit.Generate.JavaScript.FFI.RegistryTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Generate.JavaScript.FFI.Registry as Registry
import Test.Tasty
import Test.Tasty.HUnit


tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.FFI.Registry"
    [ buildRegistryTests,
      buildRegistryFullTests,
      closeFFIDepsTests,
      emitNeededBlocksTests
    ]


-- BUILD REGISTRY TESTS

buildRegistryTests :: TestTree
buildRegistryTests =
  testGroup
    "buildFFIRegistry"
    [ testCase "single function produces one registry entry" $
        let reg = Registry.buildFFIRegistry "function foo() { return 1; }"
         in Map.size reg @?= 1,
      testCase "single function entry has correct id" $
        let reg = Registry.buildFFIRegistry "function foo() { return 1; }"
         in Map.member (Registry.FFIBlockId "foo") reg @?= True,
      testCase "single function with no known deps has empty deps" $
        let reg = Registry.buildFFIRegistry "function foo() { return 1; }"
         in case Map.lookup (Registry.FFIBlockId "foo") reg of
              Nothing -> assertFailure "Expected foo in registry"
              Just block -> Registry._fbDeps block @?= Set.empty,
      testCase "two independent functions produce two entries" $
        let reg = Registry.buildFFIRegistry "function a() { return 1; }\nfunction b() { return 2; }"
         in Map.size reg @?= 2,
      testCase "two independent functions have empty deps" $ do
        let reg = Registry.buildFFIRegistry "function a() { return 1; }\nfunction b() { return 2; }"
        case Map.lookup (Registry.FFIBlockId "a") reg of
          Nothing -> assertFailure "Expected a in registry"
          Just block -> Registry._fbDeps block @?= Set.empty
        case Map.lookup (Registry.FFIBlockId "b") reg of
          Nothing -> assertFailure "Expected b in registry"
          Just block -> Registry._fbDeps block @?= Set.empty,
      testCase "function calling another has that dep recorded" $
        let js = "function helper() { return 1; }\nfunction main() { return helper(); }"
            reg = Registry.buildFFIRegistry js
         in case Map.lookup (Registry.FFIBlockId "main") reg of
              Nothing -> assertFailure "Expected main in registry"
              Just block ->
                Set.member (Registry.FFIBlockId "helper") (Registry._fbDeps block) @?= True,
      testCase "called function has empty deps (no further deps)" $
        let js = "function helper() { return 1; }\nfunction main() { return helper(); }"
            reg = Registry.buildFFIRegistry js
         in case Map.lookup (Registry.FFIBlockId "helper") reg of
              Nothing -> assertFailure "Expected helper in registry"
              Just block -> Registry._fbDeps block @?= Set.empty,
      testCase "invalid JS produces empty registry" $
        let reg = Registry.buildFFIRegistry "<<< this is not JavaScript >>>"
         in Map.size reg @?= 0,
      testCase "empty string produces empty registry" $
        let reg = Registry.buildFFIRegistry ""
         in Map.size reg @?= 0,
      testCase "var A = 0, B = 1 produces entries for both A and B" $ do
        let reg = Registry.buildFFIRegistry "var A = 0, B = 1;"
        Map.member (Registry.FFIBlockId "A") reg @?= True
        Map.member (Registry.FFIBlockId "B") reg @?= True,
      testCase "string key in bracket access does not create spurious dep" $
        -- This is the canonical regression: args['node'] must NOT dep on var node
        let js = "var node = 1;\nvar f = function(args) { return args['node']; };"
            reg = Registry.buildFFIRegistry js
         in case Map.lookup (Registry.FFIBlockId "f") reg of
              Nothing -> assertFailure "Expected f in registry"
              Just block ->
                Set.member (Registry.FFIBlockId "node") (Registry._fbDeps block) @?= False
    ]


-- BUILD REGISTRY FULL TESTS

buildRegistryFullTests :: TestTree
buildRegistryFullTests =
  testGroup
    "buildFFIRegistryFull"
    [ testCase "valid JS: frrRegistry is non-empty" $
        let result = Registry.buildFFIRegistryFull "var x = 1;"
         in Map.size (Registry._frrRegistry result) @?= 1,
      testCase "valid JS: frrFullAST is non-empty" $
        let result = Registry.buildFFIRegistryFull "var x = 1;"
         in null (Registry._frrFullAST result) @?= False,
      testCase "invalid JS: frrRegistry is empty" $
        let result = Registry.buildFFIRegistryFull "<<< not JS >>>"
         in Map.size (Registry._frrRegistry result) @?= 0,
      testCase "invalid JS: frrFullAST is empty" $
        let result = Registry.buildFFIRegistryFull "<<< not JS >>>"
         in Registry._frrFullAST result @?= [],
      testCase "both registry and fullAST from single parse" $ do
        let result = Registry.buildFFIRegistryFull "function foo() {}\nfunction bar() {}"
        Map.size (Registry._frrRegistry result) @?= 2
        null (Registry._frrFullAST result) @?= False
    ]


-- CLOSE FFI DEPS TESTS

closeFFIDepsTests :: TestTree
closeFFIDepsTests =
  testGroup
    "closeFFIDeps"
    [ testCase "empty seed produces empty closed set" $
        let reg = Registry.buildFFIRegistry "function a() {} function b() {}"
         in Registry.closeFFIDeps reg Set.empty @?= Set.empty,
      testCase "single seed with no deps stays singleton" $
        let reg = Registry.buildFFIRegistry "function a() { return 1; }"
            seed = Set.singleton (Registry.FFIBlockId "a")
            result = Registry.closeFFIDeps reg seed
         in Set.member (Registry.FFIBlockId "a") result @?= True,
      testCase "single seed with no deps does not grow" $
        let reg = Registry.buildFFIRegistry "function a() { return 1; }"
            seed = Set.singleton (Registry.FFIBlockId "a")
            result = Registry.closeFFIDeps reg seed
         in Set.size result @?= 1,
      testCase "transitive chain A->B->C: seeding A yields all three" $
        let js = "function c() { return 1; }\nfunction b() { return c(); }\nfunction a() { return b(); }"
            reg = Registry.buildFFIRegistry js
            seed = Set.singleton (Registry.FFIBlockId "a")
            result = Registry.closeFFIDeps reg seed
         in Set.size result @?= 3,
      testCase "transitive chain: result includes each intermediate dep" $
        let js = "function c() { return 1; }\nfunction b() { return c(); }\nfunction a() { return b(); }"
            reg = Registry.buildFFIRegistry js
            seed = Set.singleton (Registry.FFIBlockId "a")
            result = Registry.closeFFIDeps reg seed
         in do Set.member (Registry.FFIBlockId "a") result @?= True
               Set.member (Registry.FFIBlockId "b") result @?= True
               Set.member (Registry.FFIBlockId "c") result @?= True,
      testCase "already-closed seed is unchanged" $
        let js = "function a() { return 1; }\nfunction b() { return a(); }"
            reg = Registry.buildFFIRegistry js
            fullSeed = Set.fromList [Registry.FFIBlockId "a", Registry.FFIBlockId "b"]
            result = Registry.closeFFIDeps reg fullSeed
         in Set.size result @?= 2,
      testCase "non-existent id in seed does not crash" $
        let reg = Registry.buildFFIRegistry "function a() {}"
            seed = Set.singleton (Registry.FFIBlockId "nonexistent")
            result = Registry.closeFFIDeps reg seed
         in Set.size result @?= 1
    ]


-- EMIT NEEDED BLOCKS TESTS

emitNeededBlocksTests :: TestTree
emitNeededBlocksTests =
  testGroup
    "emitNeededBlocks"
    [ testCase "emitting single block produces non-empty output" $
        let reg = Registry.buildFFIRegistry "function foo() { return 1; }"
            needed = Set.singleton (Registry.FFIBlockId "foo")
            output = builderToString (Registry.emitNeededBlocks False reg needed)
         in null output @?= False,
      testCase "emitting empty set produces empty output" $
        let reg = Registry.buildFFIRegistry "function foo() { return 1; }"
            output = builderToString (Registry.emitNeededBlocks False reg Set.empty)
         in output @?= "",
      testCase "dev mode output contains the function name" $
        let reg = Registry.buildFFIRegistry "function myFunc() { return 42; }"
            needed = Set.singleton (Registry.FFIBlockId "myFunc")
            output = builderToString (Registry.emitNeededBlocks False reg needed)
         in "myFunc" `isInfixOf` output @?= True,
      testCase "prod mode output contains the function name" $
        let reg = Registry.buildFFIRegistry "function prodFn() { return 1; }"
            needed = Set.singleton (Registry.FFIBlockId "prodFn")
            output = builderToString (Registry.emitNeededBlocks True reg needed)
         in "prodFn" `isInfixOf` output @?= True,
      testCase "blocks emitted in source order (first declared comes first)" $
        let js = Text.pack "function alpha() { return 1; }\nfunction beta() { return alpha(); }"
            reg = Registry.buildFFIRegistryFull js
            needed = Set.fromList
              [ Registry.FFIBlockId "alpha"
              , Registry.FFIBlockId "beta"
              ]
            output = builderToString (Registry.emitNeededBlocks False (Registry._frrRegistry reg) needed)
            alphaPos = findIndex "alpha" output
            betaPos  = findIndex "beta" output
         in alphaPos < betaPos @?= True
    ]


-- HELPERS

builderToString :: BB.Builder -> String
builderToString = LChar8.unpack . BB.toLazyByteString

isInfixOf :: String -> String -> Bool
isInfixOf needle haystack = go needle haystack
  where
    go [] _ = True
    go _ [] = False
    go ns@(n : ns') (h : hs)
      | n == h = go ns' hs || go ns hs
      | otherwise = go ns hs

findIndex :: String -> String -> Int
findIndex needle haystack = go 0 haystack
  where
    go i [] = i + length haystack
    go i hs@(_ : hs')
      | needle `isPrefixOf` hs = i
      | otherwise = go (i + 1) hs'
    isPrefixOf [] _ = True
    isPrefixOf _ [] = False
    isPrefixOf (x : xs) (y : ys) = x == y && isPrefixOf xs ys

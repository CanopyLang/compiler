{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Tests for chunk loader runtime generation.
--
-- Validates that the JavaScript runtime includes all required functions
-- and global variables for chunk loading, registration, and prefetching.
--
-- @since 0.19.2
module Unit.Generate.CodeSplit.RuntimeTest (tests) where

import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy.Char8 as LChar8
import Generate.JavaScript.CodeSplit.Runtime (chunkRuntime)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.CodeSplit.Runtime"
    [ runtimeContentTests
    , runtimeFunctionTests
    , runtimeVariableTests
    ]

-- | Render the runtime to a string for assertions.
runtimeStr :: String
runtimeStr = LChar8.unpack (B.toLazyByteString chunkRuntime)

-- | Check if a string is contained in another.
contains :: String -> String -> Bool
contains needle haystack = any (isPrefixOf needle) (tails haystack)

isPrefixOf :: String -> String -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_ : rest) = xs : tails rest

-- CONTENT TESTS

runtimeContentTests :: TestTree
runtimeContentTests =
  testGroup
    "Runtime content"
    [ testCase "runtime is non-empty" $
        assertBool "non-empty runtime" (not (null runtimeStr))
    , testCase "runtime is valid JavaScript (has function keyword)" $
        assertBool "contains function" (contains "function" runtimeStr)
    , testCase "runtime uses var declarations" $
        assertBool "contains var" (contains "var" runtimeStr)
    ]

-- FUNCTION TESTS

runtimeFunctionTests :: TestTree
runtimeFunctionTests =
  testGroup
    "Required functions"
    [ testCase "contains __canopy_register function" $
        assertBool "__canopy_register present"
          (contains "__canopy_register" runtimeStr)
    , testCase "contains __canopy_load function" $
        assertBool "__canopy_load present"
          (contains "__canopy_load" runtimeStr)
    , testCase "contains __canopy_prefetch function" $
        assertBool "__canopy_prefetch present"
          (contains "__canopy_prefetch" runtimeStr)
    , testCase "register takes id and factory params" $
        assertBool "register(id, factory)"
          (contains "__canopy_register(id, factory)" runtimeStr)
    , testCase "load creates script element for async loading" $
        assertBool "createElement('script')"
          (contains "createElement('script')" runtimeStr)
    , testCase "prefetch creates link element" $
        assertBool "createElement('link')"
          (contains "createElement('link')" runtimeStr)
    , testCase "load returns Promise for async case" $
        assertBool "new Promise"
          (contains "new Promise" runtimeStr)
    , testCase "load handles error case" $
        assertBool "reject present"
          (contains "reject" runtimeStr)
    , testCase "prefetch sets rel=prefetch" $
        assertBool "rel = 'prefetch'"
          (contains "rel = 'prefetch'" runtimeStr)
    ]

-- VARIABLE TESTS

runtimeVariableTests :: TestTree
runtimeVariableTests =
  testGroup
    "Required variables"
    [ testCase "contains __canopy_chunks object" $
        assertBool "__canopy_chunks present"
          (contains "__canopy_chunks" runtimeStr)
    , testCase "contains __canopy_loaded object" $
        assertBool "__canopy_loaded present"
          (contains "__canopy_loaded" runtimeStr)
    , testCase "contains __canopy_manifest object" $
        assertBool "__canopy_manifest present"
          (contains "__canopy_manifest" runtimeStr)
    , testCase "chunks initialized as empty object" $
        assertBool "__canopy_chunks = {}"
          (contains "__canopy_chunks = {}" runtimeStr)
    , testCase "loaded initialized as empty object" $
        assertBool "__canopy_loaded = {}"
          (contains "__canopy_loaded = {}" runtimeStr)
    , testCase "manifest initialized as empty object" $
        assertBool "__canopy_manifest = {}"
          (contains "__canopy_manifest = {}" runtimeStr)
    ]

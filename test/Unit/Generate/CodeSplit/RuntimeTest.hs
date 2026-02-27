{-# LANGUAGE OverloadedStrings #-}

-- | Tests for chunk loader runtime generation.
--
-- Validates that the JavaScript runtime includes all required functions
-- and global variables for chunk loading, registration, and prefetching.
--
-- @since 0.19.2
module Unit.Generate.CodeSplit.RuntimeTest (tests) where

import qualified Data.ByteString.Builder as BB
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
runtimeStr = LChar8.unpack (BB.toLazyByteString chunkRuntime)

-- CONTENT TESTS

runtimeContentTests :: TestTree
runtimeContentTests =
  testGroup
    "Runtime content"
    [ testCase "runtime has expected length" $
        length runtimeStr @?= 1122
    , testCase "runtime starts with var __canopy_chunks" $
        take 27 runtimeStr @?= "\nvar __canopy_chunks = {};\n"
    , testCase "runtime contains all three var declarations" $
        take 80 (dropWhile (== '\n') runtimeStr)
          @?= "var __canopy_chunks = {};\nvar __canopy_loaded = {};\nvar __canopy_manifest = {};\n"
    ]

-- FUNCTION TESTS

runtimeFunctionTests :: TestTree
runtimeFunctionTests =
  testGroup
    "Required functions"
    [ testCase "contains __canopy_register function" $
        runtimeStr @?= expectedRuntime
    ]

-- VARIABLE TESTS

runtimeVariableTests :: TestTree
runtimeVariableTests =
  testGroup
    "Required variables"
    [ testCase "chunks initialized as empty object" $
        ("var __canopy_chunks = {};" `elem` lines runtimeStr) @?= True
    , testCase "loaded initialized as empty object" $
        ("var __canopy_loaded = {};" `elem` lines runtimeStr) @?= True
    , testCase "manifest initialized as empty object" $
        ("var __canopy_manifest = {};" `elem` lines runtimeStr) @?= True
    ]

-- | The exact expected runtime content.
expectedRuntime :: String
expectedRuntime =
  "\nvar __canopy_chunks = {};\nvar __canopy_loaded = {};\nvar __canopy_manifest = {};\n\
  \function __canopy_register(id, factory) {\n\
  \  __canopy_chunks[id] = factory;\n\
  \}\n\
  \function __canopy_load(id) {\n\
  \  if (__canopy_loaded[id]) return __canopy_loaded[id];\n\
  \  if (__canopy_chunks[id]) {\n\
  \    __canopy_loaded[id] = __canopy_chunks[id]();\n\
  \    return __canopy_loaded[id];\n\
  \  }\n\
  \  return new Promise(function(resolve, reject) {\n\
  \    var s = document.createElement('script');\n\
  \    s.src = __canopy_manifest[id];\n\
  \    s.onload = function() {\n\
  \      if (__canopy_chunks[id]) {\n\
  \        __canopy_loaded[id] = __canopy_chunks[id]();\n\
  \        resolve(__canopy_loaded[id]);\n\
  \      } else {\n\
  \        reject(new Error('Chunk ' + id + ' did not register'));\n\
  \      }\n\
  \    };\n\
  \    s.onerror = function() {\n\
  \      reject(new Error('Failed to load chunk ' + id));\n\
  \    };\n\
  \    document.head.appendChild(s);\n\
  \  });\n\
  \}\n\
  \function __canopy_prefetch(id) {\n\
  \  if (__canopy_chunks[id] || __canopy_loaded[id]) return;\n\
  \  var link = document.createElement('link');\n\
  \  link.rel = 'prefetch';\n\
  \  link.as = 'script';\n\
  \  link.href = __canopy_manifest[id];\n\
  \  document.head.appendChild(link);\n\
  \}\n"

{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.JavaScript.Runtime.Registry'.
--
-- Covers:
--   * 'registry' — the top-level CAF parses correctly and is non-empty
--   * 'allIds' — contains expected well-known runtime identifiers
--   * 'runtimeIdFromKernel' — correct name mangling convention
--   * 'closeDeps' — transitive dependency closure includes seed and transitives
--   * 'topoEmit' — emits valid output for a seed set
--   * 'exportedRuntimeNames' — non-empty and contains known names
--
-- @since 0.20.4
module Unit.Generate.JavaScript.Runtime.RegistryTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Canopy.Data.Name as Name
import qualified Generate.JavaScript.Runtime.Registry as RR
import Test.Tasty
import Test.Tasty.HUnit


tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Runtime.Registry"
    [ registrySanityTests,
      allIdsTests,
      runtimeIdFromKernelTests,
      closeDepsTests,
      topoEmitTests,
      exportedNamesTests
    ]


-- REGISTRY SANITY TESTS

registrySanityTests :: TestTree
registrySanityTests =
  testGroup
    "registry (CAF)"
    [ testCase "registry is non-empty (runtime parsed successfully)" $
        Map.size RR.registry > 0 @?= True,
      testCase "registry contains _Utils_eq" $
        Map.member (RR.RuntimeId "_Utils_eq") RR.registry @?= True,
      testCase "registry contains _List_Nil" $
        Map.member (RR.RuntimeId "_List_Nil") RR.registry @?= True,
      testCase "registry contains _List_Cons" $
        Map.member (RR.RuntimeId "_List_Cons") RR.registry @?= True,
      testCase "lookupDef returns Just for known id" $
        case RR.lookupDef (RR.RuntimeId "_Utils_eq") of
          Nothing -> assertFailure "_Utils_eq should exist in registry"
          Just def -> null (RR._rdStatements def) @?= False,
      testCase "lookupDef returns Nothing for unknown id" $
        RR.lookupDef (RR.RuntimeId "_does_not_exist_ever") @?= Nothing
    ]


-- ALL IDS TESTS

allIdsTests :: TestTree
allIdsTests =
  testGroup
    "allIds"
    [ testCase "allIds is non-empty" $
        Set.size RR.allIds > 0 @?= True,
      testCase "allIds contains _Utils_eq" $
        Set.member (RR.RuntimeId "_Utils_eq") RR.allIds @?= True,
      testCase "allIds contains _List_Nil" $
        Set.member (RR.RuntimeId "_List_Nil") RR.allIds @?= True,
      testCase "allIds size matches registry size" $
        Set.size RR.allIds @?= Map.size RR.registry
    ]


-- RUNTIME ID FROM KERNEL TESTS

runtimeIdFromKernelTests :: TestTree
runtimeIdFromKernelTests =
  testGroup
    "runtimeIdFromKernel"
    [ testCase "Utils eq maps to _Utils_eq" $
        RR.runtimeIdFromKernel (Name.fromChars "Utils") (Name.fromChars "eq")
          @?= RR.RuntimeId "_Utils_eq",
      testCase "List Cons maps to _List_Cons" $
        RR.runtimeIdFromKernel (Name.fromChars "List") (Name.fromChars "Cons")
          @?= RR.RuntimeId "_List_Cons",
      testCase "Scheduler rawSpawn maps to _Scheduler_rawSpawn" $
        RR.runtimeIdFromKernel (Name.fromChars "Scheduler") (Name.fromChars "rawSpawn")
          @?= RR.RuntimeId "_Scheduler_rawSpawn",
      testCase "result of runtimeIdFromKernel is present in registry (Utils eq)" $
        let rid = RR.runtimeIdFromKernel (Name.fromChars "Utils") (Name.fromChars "eq")
         in Map.member rid RR.registry @?= True
    ]


-- CLOSE DEPS TESTS

closeDepsTests :: TestTree
closeDepsTests =
  testGroup
    "closeDeps"
    [ testCase "empty seed produces empty closure" $
        RR.closeDeps Set.empty @?= Set.empty,
      testCase "singleton seed includes itself" $
        let seed = Set.singleton (RR.RuntimeId "_Utils_eq")
            result = RR.closeDeps seed
         in Set.member (RR.RuntimeId "_Utils_eq") result @?= True,
      testCase "singleton seed closure is non-empty" $
        let seed = Set.singleton (RR.RuntimeId "_Utils_eq")
            result = RR.closeDeps seed
         in Set.size result >= 1 @?= True,
      testCase "closed set is superset of seed" $
        let seed = Set.singleton (RR.RuntimeId "_List_Cons")
            result = RR.closeDeps seed
         in Set.isSubsetOf seed result @?= True,
      testCase "closure is idempotent: closing already-closed set is unchanged" $
        let seed = Set.singleton (RR.RuntimeId "_Utils_eq")
            firstClosure = RR.closeDeps seed
            secondClosure = RR.closeDeps firstClosure
         in secondClosure @?= firstClosure,
      testCase "unknown id in seed: closure is singleton (no deps found)" $
        let seed = Set.singleton (RR.RuntimeId "_does_not_exist_xxx")
            result = RR.closeDeps seed
         in Set.size result @?= 1
    ]


-- TOPO EMIT TESTS

topoEmitTests :: TestTree
topoEmitTests =
  testGroup
    "topoEmit"
    [ testCase "emitting empty set produces empty output" $
        builderToString (RR.topoEmit False Set.empty) @?= "",
      testCase "emitting singleton produces non-empty output" $
        let seed = Set.singleton (RR.RuntimeId "_Utils_eq")
            output = builderToString (RR.topoEmit False seed)
         in null output @?= False,
      testCase "emitted output contains the function name" $
        let seed = Set.singleton (RR.RuntimeId "_Utils_eq")
            output = builderToString (RR.topoEmit False seed)
         in "_Utils_eq" `isInfixOf` output @?= True,
      testCase "prod mode output is non-empty" $
        let seed = Set.singleton (RR.RuntimeId "_Utils_eq")
            output = builderToString (RR.topoEmit True seed)
         in null output @?= False,
      testCase "prod mode output still contains function name" $
        let seed = Set.singleton (RR.RuntimeId "_Utils_eq")
            output = builderToString (RR.topoEmit True seed)
         in "_Utils_eq" `isInfixOf` output @?= True
    ]


-- EXPORTED NAMES TESTS

exportedNamesTests :: TestTree
exportedNamesTests =
  testGroup
    "exportedRuntimeNames"
    [ testCase "exportedRuntimeNames is non-empty" $
        null RR.exportedRuntimeNames @?= False,
      testCase "exportedRuntimeNames contains _Utils_eq" $
        elem "_Utils_eq" RR.exportedRuntimeNames @?= True,
      testCase "exportedRuntimeNames contains _List_Nil" $
        elem "_List_Nil" RR.exportedRuntimeNames @?= True
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

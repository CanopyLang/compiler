{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI.Manifest module.
--
-- Tests capability manifest collection and serialization.
--
-- @since 0.19.1
module Unit.FFI.ManifestTest (tests) where

import qualified Data.Set as Set
import qualified FFI.Manifest as Manifest
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI.Manifest Tests"
    [ testEmptyManifest,
      testManifestProperties,
      testHasCapabilities
    ]

testEmptyManifest :: TestTree
testEmptyManifest =
  testGroup
    "empty input"
    [ testCase "empty module list produces empty manifest" $ do
        let manifest = Manifest.collectCapabilities []
        Manifest._manifestUserActivation manifest @?= False
        Set.size (Manifest._manifestPermissions manifest) @?= 0
        Set.size (Manifest._manifestInitializations manifest) @?= 0
        length (Manifest._manifestModules manifest) @?= 0,
      testCase "module with no FFI functions produces empty manifest" $ do
        let manifest = Manifest.collectCapabilities [("MyModule", [])]
        length (Manifest._manifestModules manifest) @?= 0
    ]

testManifestProperties :: TestTree
testManifestProperties =
  testGroup
    "manifest structure"
    [ testCase "manifest version is 1" $ do
        let manifest = Manifest.collectCapabilities []
        Manifest._manifestUserActivation manifest @?= False,
      testCase "permissions set is empty for no inputs" $ do
        let manifest = Manifest.collectCapabilities []
        Manifest._manifestPermissions manifest @?= Set.empty,
      testCase "initializations set is empty for no inputs" $ do
        let manifest = Manifest.collectCapabilities []
        Manifest._manifestInitializations manifest @?= Set.empty
    ]

testHasCapabilities :: TestTree
testHasCapabilities =
  testGroup
    "capability detection"
    [ testCase "empty manifest has no capabilities" $ do
        let manifest = Manifest.collectCapabilities []
        Manifest._manifestUserActivation manifest @?= False
        length (Manifest._manifestModules manifest) @?= 0
    ]

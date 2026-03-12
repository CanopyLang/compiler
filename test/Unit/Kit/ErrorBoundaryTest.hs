{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit.ErrorBoundary resolution.
--
-- Tests that 'resolveErrorBoundaries' correctly maps route prefixes
-- to error boundary module names derived from file paths. Verifies
-- path stripping, segment formatting, and capitalization logic.
--
-- @since 0.20.1
module Unit.Kit.ErrorBoundaryTest
  ( tests
  ) where

import qualified Data.Map.Strict as Map
import Kit.ErrorBoundary (resolveErrorBoundaries)
import Kit.Route.Types
  ( LayoutEntry (..)
  , RouteManifest (..)
  , RouteSegment (..)
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit


tests :: TestTree
tests =
  Test.testGroup "Kit.ErrorBoundary"
    [ emptyManifestNoBoundariesTest
    , singleBoundaryTest
    , boundaryPrefixKeyTest
    , boundaryModuleNameTest
    , dynamicSegmentPrefixKeyTest
    , catchAllSegmentPrefixKeyTest
    , rootBoundaryEmptyKeyTest
    , multipleBoundariesTest
    , nestedPathModuleNameTest
    , srcPrefixStrippedTest
    , canSuffixStrippedTest
    , capitalizationTest
    ]

emptyManifestNoBoundariesTest :: TestTree
emptyManifestNoBoundariesTest =
  HUnit.testCase "empty manifest produces empty map" $
    resolveErrorBoundaries emptyManifest @?= Map.empty

singleBoundaryTest :: TestTree
singleBoundaryTest =
  HUnit.testCase "single error boundary produces one entry" $
    Map.size (resolveErrorBoundaries singleBoundaryManifest) @?= 1

boundaryPrefixKeyTest :: TestTree
boundaryPrefixKeyTest =
  HUnit.testCase "static segment prefix becomes map key" $
    Map.member "users" (resolveErrorBoundaries singleBoundaryManifest) @?= True

boundaryModuleNameTest :: TestTree
boundaryModuleNameTest =
  HUnit.testCase "file path becomes dotted module name" $
    Map.lookup "users" (resolveErrorBoundaries singleBoundaryManifest)
      @?= Just "Routes.Users.Error"

dynamicSegmentPrefixKeyTest :: TestTree
dynamicSegmentPrefixKeyTest =
  HUnit.testCase "dynamic segment formatted with brackets in key" $
    Map.member "users/[id]" (resolveErrorBoundaries dynamicBoundaryManifest) @?= True

catchAllSegmentPrefixKeyTest :: TestTree
catchAllSegmentPrefixKeyTest =
  HUnit.testCase "catch-all segment formatted with brackets in key" $
    Map.member "docs/[...rest]" (resolveErrorBoundaries catchAllBoundaryManifest) @?= True

rootBoundaryEmptyKeyTest :: TestTree
rootBoundaryEmptyKeyTest =
  HUnit.testCase "root boundary has empty string key" $
    Map.member "" (resolveErrorBoundaries rootBoundaryManifest) @?= True

multipleBoundariesTest :: TestTree
multipleBoundariesTest =
  HUnit.testCase "multiple boundaries produce multiple entries" $
    Map.size (resolveErrorBoundaries multiBoundaryManifest) @?= 2

nestedPathModuleNameTest :: TestTree
nestedPathModuleNameTest =
  HUnit.testCase "nested path produces nested module name" $
    Map.lookup "users/[id]" (resolveErrorBoundaries dynamicBoundaryManifest)
      @?= Just "Routes.Users.[id].Error"

srcPrefixStrippedTest :: TestTree
srcPrefixStrippedTest =
  HUnit.testCase "src/ prefix is stripped from module name" $
    Map.lookup "" (resolveErrorBoundaries rootBoundaryManifest)
      @?= Just "Routes.Error"

canSuffixStrippedTest :: TestTree
canSuffixStrippedTest =
  HUnit.testCase ".can suffix is stripped from module name" $
    Map.lookup "users" result @?= Just "Routes.Users.Error"
  where
    result = resolveErrorBoundaries singleBoundaryManifest

capitalizationTest :: TestTree
capitalizationTest =
  HUnit.testCase "path segments are capitalized" $
    Map.lookup "users" result @?= Just "Routes.Users.Error"
  where
    result = resolveErrorBoundaries singleBoundaryManifest

-- Test fixtures

emptyManifest :: RouteManifest
emptyManifest = RouteManifest [] [] []

singleBoundaryManifest :: RouteManifest
singleBoundaryManifest = RouteManifest
  { _rmRoutes = []
  , _rmLayouts = []
  , _rmErrorBoundaries =
      [ LayoutEntry [StaticSegment "users"] "src/routes/users/error.can"
      ]
  }

dynamicBoundaryManifest :: RouteManifest
dynamicBoundaryManifest = RouteManifest
  { _rmRoutes = []
  , _rmLayouts = []
  , _rmErrorBoundaries =
      [ LayoutEntry [StaticSegment "users", DynamicSegment "id"] "src/routes/users/[id]/error.can"
      ]
  }

catchAllBoundaryManifest :: RouteManifest
catchAllBoundaryManifest = RouteManifest
  { _rmRoutes = []
  , _rmLayouts = []
  , _rmErrorBoundaries =
      [ LayoutEntry [StaticSegment "docs", CatchAll "rest"] "src/routes/docs/[...rest]/error.can"
      ]
  }

rootBoundaryManifest :: RouteManifest
rootBoundaryManifest = RouteManifest
  { _rmRoutes = []
  , _rmLayouts = []
  , _rmErrorBoundaries =
      [ LayoutEntry [] "src/routes/error.can"
      ]
  }

multiBoundaryManifest :: RouteManifest
multiBoundaryManifest = RouteManifest
  { _rmRoutes = []
  , _rmLayouts = []
  , _rmErrorBoundaries =
      [ LayoutEntry [StaticSegment "users"] "src/routes/users/error.can"
      , LayoutEntry [StaticSegment "admin"] "src/routes/admin/error.can"
      ]
  }

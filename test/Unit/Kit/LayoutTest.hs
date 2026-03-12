{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit.Layout resolution.
--
-- Tests that 'resolveLayouts' correctly converts layout entries
-- from a route manifest and sorts them by prefix length (longest
-- first) for most-specific-match precedence.
--
-- @since 0.20.1
module Unit.Kit.LayoutTest
  ( tests
  ) where

import Kit.Layout (LayoutBinding (..), resolveLayouts)
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
  Test.testGroup "Kit.Layout"
    [ emptyManifestNoLayoutsTest
    , singleLayoutBindingTest
    , layoutPrefixPreservedTest
    , layoutModulePathPreservedTest
    , layoutsSortedByPrefixLengthTest
    , longestPrefixFirstTest
    , rootLayoutShortestPrefixTest
    , layoutBindingShowTest
    , layoutBindingEqualityTest
    ]

emptyManifestNoLayoutsTest :: TestTree
emptyManifestNoLayoutsTest =
  HUnit.testCase "empty manifest produces no layout bindings" $
    resolveLayouts emptyManifest @?= []

singleLayoutBindingTest :: TestTree
singleLayoutBindingTest =
  HUnit.testCase "single layout entry produces one binding" $
    length (resolveLayouts singleLayoutManifest) @?= 1

layoutPrefixPreservedTest :: TestTree
layoutPrefixPreservedTest =
  HUnit.testCase "layout prefix segments are preserved" $
    fmap _lbPrefix (resolveLayouts singleLayoutManifest) @?= [[StaticSegment "users"]]

layoutModulePathPreservedTest :: TestTree
layoutModulePathPreservedTest =
  HUnit.testCase "layout module path is preserved" $
    fmap _lbModulePath (resolveLayouts singleLayoutManifest) @?= ["src/routes/users/layout.can"]

layoutsSortedByPrefixLengthTest :: TestTree
layoutsSortedByPrefixLengthTest =
  HUnit.testCase "layouts sorted longest prefix first" $
    fmap (length . _lbPrefix) bindings @?= [2, 1, 0]
  where
    bindings = resolveLayouts multiLayoutManifest

longestPrefixFirstTest :: TestTree
longestPrefixFirstTest =
  HUnit.testCase "most specific layout appears first" $
    fmap _lbPrefix bindings @?= [ [StaticSegment "users", StaticSegment "settings"]
                                 , [StaticSegment "users"]
                                 , []
                                 ]
  where
    bindings = resolveLayouts multiLayoutManifest

rootLayoutShortestPrefixTest :: TestTree
rootLayoutShortestPrefixTest =
  HUnit.testCase "root layout appears last" $
    _lbPrefix (last bindings) @?= []
  where
    bindings = resolveLayouts multiLayoutManifest

layoutBindingShowTest :: TestTree
layoutBindingShowTest =
  HUnit.testCase "show LayoutBinding" $
    show binding @?= "LayoutBinding {_lbPrefix = [StaticSegment \"users\"], _lbModulePath = \"src/routes/users/layout.can\"}"
  where
    binding = LayoutBinding [StaticSegment "users"] "src/routes/users/layout.can"

layoutBindingEqualityTest :: TestTree
layoutBindingEqualityTest =
  HUnit.testCase "LayoutBinding equality" $
    (binding1 == binding2) @?= False
  where
    binding1 = LayoutBinding [StaticSegment "users"] "src/routes/users/layout.can"
    binding2 = LayoutBinding [StaticSegment "admin"] "src/routes/admin/layout.can"

-- Test fixtures

emptyManifest :: RouteManifest
emptyManifest = RouteManifest [] [] []

singleLayoutManifest :: RouteManifest
singleLayoutManifest = RouteManifest
  { _rmRoutes = []
  , _rmLayouts = [usersLayout]
  , _rmErrorBoundaries = []
  }

multiLayoutManifest :: RouteManifest
multiLayoutManifest = RouteManifest
  { _rmRoutes = []
  , _rmLayouts = [rootLayout, usersLayout, usersSettingsLayout]
  , _rmErrorBoundaries = []
  }

rootLayout :: LayoutEntry
rootLayout = LayoutEntry
  { _lePrefix = []
  , _leModulePath = "src/routes/layout.can"
  }

usersLayout :: LayoutEntry
usersLayout = LayoutEntry
  { _lePrefix = [StaticSegment "users"]
  , _leModulePath = "src/routes/users/layout.can"
  }

usersSettingsLayout :: LayoutEntry
usersSettingsLayout = LayoutEntry
  { _lePrefix = [StaticSegment "users", StaticSegment "settings"]
  , _leModulePath = "src/routes/users/settings/layout.can"
  }

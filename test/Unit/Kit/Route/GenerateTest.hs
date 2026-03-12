{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit route code generation.
--
-- Tests that the Routes.can module generator produces correct output
-- for various route configurations: static, dynamic, catch-all, and
-- mixed route manifests.
--
-- @since 0.20.1
module Unit.Kit.Route.GenerateTest
  ( tests
  ) where

import qualified Data.Text as Text
import Kit.Route.Types
  ( RouteEntry (..)
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  , PageKind (..)
  )
import qualified Kit.Route.Generate as Generate
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup "Kit.Route.Generate"
    [ generatesModuleHeader
    , generatesStaticRouteParser
    , generatesDynamicRouteParser
    , generatesLazyImports
    , generatesEmptyManifest
    , generatesMultipleRoutes
    ]


-- | Generated module starts with correct header.
generatesModuleHeader :: TestTree
generatesModuleHeader =
  HUnit.testCase "generated module has correct header" $ do
    let output = Generate.generateRoutesModule singleRouteManifest
    HUnit.assertBool "starts with module declaration"
      (Text.isPrefixOf "module Routes" output)

-- | Static route produces a literal parser segment.
generatesStaticRouteParser :: TestTree
generatesStaticRouteParser =
  HUnit.testCase "static route produces literal segment" $ do
    let output = Generate.generateRoutesModule singleRouteManifest
    HUnit.assertBool "contains route pattern"
      ("about" `Text.isInfixOf` output)

-- | Dynamic route produces a parser with variable capture.
generatesDynamicRouteParser :: TestTree
generatesDynamicRouteParser =
  HUnit.testCase "dynamic route produces variable capture" $ do
    let output = Generate.generateRoutesModule dynamicRouteManifest
    HUnit.assertBool "contains dynamic segment reference"
      ("id" `Text.isInfixOf` output)

-- | Lazy imports are generated for each route module.
generatesLazyImports :: TestTree
generatesLazyImports =
  HUnit.testCase "generates lazy imports for route modules" $ do
    let output = Generate.generateRoutesModule twoRouteManifest
    HUnit.assertBool "contains lazy import for About"
      ("lazy import" `Text.isInfixOf` output)

-- | Empty manifest produces a module with no routes.
generatesEmptyManifest :: TestTree
generatesEmptyManifest =
  HUnit.testCase "empty manifest produces valid module" $ do
    let output = Generate.generateRoutesModule emptyManifest
    HUnit.assertBool "is non-empty"
      (not (Text.null output))
    HUnit.assertBool "has module header"
      ("module Routes" `Text.isPrefixOf` output)

-- | Multiple routes produce entries for each.
generatesMultipleRoutes :: TestTree
generatesMultipleRoutes =
  HUnit.testCase "multiple routes produce multiple entries" $ do
    let output = Generate.generateRoutesModule twoRouteManifest
    HUnit.assertBool "contains About"
      ("About" `Text.isInfixOf` output)
    HUnit.assertBool "contains Contact"
      ("Contact" `Text.isInfixOf` output)


-- TEST DATA


emptyManifest :: RouteManifest
emptyManifest = RouteManifest [] [] []

singleRouteManifest :: RouteManifest
singleRouteManifest = RouteManifest
  { _rmRoutes =
      [ RouteEntry
          { _rePattern = RoutePattern [StaticSegment "about"] "src/routes/about/page.can"
          , _rePageKind = StaticPage
          , _reSourceFile = "src/routes/about/page.can"
          , _reModuleName = "Routes.About"
          }
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

dynamicRouteManifest :: RouteManifest
dynamicRouteManifest = RouteManifest
  { _rmRoutes =
      [ RouteEntry
          { _rePattern = RoutePattern
              [StaticSegment "users", DynamicSegment "id"]
              "src/routes/users/[id]/page.can"
          , _rePageKind = DynamicPage
          , _reSourceFile = "src/routes/users/[id]/page.can"
          , _reModuleName = "Routes.Users.Param_Id"
          }
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

twoRouteManifest :: RouteManifest
twoRouteManifest = RouteManifest
  { _rmRoutes =
      [ RouteEntry
          { _rePattern = RoutePattern [StaticSegment "about"] "src/routes/about/page.can"
          , _rePageKind = StaticPage
          , _reSourceFile = "src/routes/about/page.can"
          , _reModuleName = "Routes.About"
          }
      , RouteEntry
          { _rePattern = RoutePattern [StaticSegment "contact"] "src/routes/contact/page.can"
          , _rePageKind = StaticPage
          , _reSourceFile = "src/routes/contact/page.can"
          , _reModuleName = "Routes.Contact"
          }
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

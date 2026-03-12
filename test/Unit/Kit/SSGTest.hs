{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit static site generation.
--
-- Tests that the SSG pipeline produces correct HTML shells for static
-- routes and properly skips dynamic routes.
--
-- @since 0.20.1
module Unit.Kit.SSGTest
  ( tests
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Kit.Route.Types
  ( RouteEntry (..)
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  , PageKind (..)
  )
import qualified Kit.SSG as SSG
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup "Kit.SSG"
    [ generatesStaticPage
    , skipsDynamicRoutes
    , skipsApiRoutes
    , generatesDoctype
    , generatesScriptTag
    , generatesMultiplePages
    , emptyManifestProducesNoPages
    , generatesCorrectFilePath
    ]


-- | Static routes produce an HTML shell.
generatesStaticPage :: TestTree
generatesStaticPage =
  HUnit.testCase "static route produces HTML output" $ do
    let pages = SSG.generateStaticPages singleStaticManifest
    Map.size pages @?= 1

-- | Dynamic routes are not pre-rendered.
skipsDynamicRoutes :: TestTree
skipsDynamicRoutes =
  HUnit.testCase "dynamic routes are skipped" $ do
    let pages = SSG.generateStaticPages dynamicOnlyManifest
    Map.size pages @?= 0

-- | API routes are not pre-rendered.
skipsApiRoutes :: TestTree
skipsApiRoutes =
  HUnit.testCase "API routes are skipped" $ do
    let pages = SSG.generateStaticPages apiOnlyManifest
    Map.size pages @?= 0

-- | Generated HTML includes DOCTYPE declaration.
generatesDoctype :: TestTree
generatesDoctype =
  HUnit.testCase "generated HTML includes DOCTYPE" $ do
    let pages = SSG.generateStaticPages singleStaticManifest
        content = head (Map.elems pages)
    HUnit.assertBool "starts with DOCTYPE"
      ("<!DOCTYPE html>" `Text.isPrefixOf` content)

-- | Generated HTML includes the main.js script tag.
generatesScriptTag :: TestTree
generatesScriptTag =
  HUnit.testCase "generated HTML includes script tag" $ do
    let pages = SSG.generateStaticPages singleStaticManifest
        content = head (Map.elems pages)
    HUnit.assertBool "contains script tag"
      ("main.js" `Text.isInfixOf` content)

-- | Mixed manifest generates only static pages.
generatesMultiplePages :: TestTree
generatesMultiplePages =
  HUnit.testCase "mixed manifest generates only static pages" $ do
    let pages = SSG.generateStaticPages mixedManifest
    Map.size pages @?= 2

-- | Empty manifest produces no pages.
emptyManifestProducesNoPages :: TestTree
emptyManifestProducesNoPages =
  HUnit.testCase "empty manifest produces no pages" $ do
    let pages = SSG.generateStaticPages emptyManifest
    Map.size pages @?= 0

-- | Output file paths use index.html convention.
generatesCorrectFilePath :: TestTree
generatesCorrectFilePath =
  HUnit.testCase "output paths use /index.html convention" $ do
    let pages = SSG.generateStaticPages singleStaticManifest
        paths = Map.keys pages
    HUnit.assertBool "path ends with index.html"
      (all (Text.isSuffixOf "index.html" . Text.pack) paths)


-- TEST DATA


emptyManifest :: RouteManifest
emptyManifest = RouteManifest [] [] []

singleStaticManifest :: RouteManifest
singleStaticManifest = RouteManifest
  { _rmRoutes =
      [ mkRoute [StaticSegment "about"] StaticPage "Routes.About"
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

dynamicOnlyManifest :: RouteManifest
dynamicOnlyManifest = RouteManifest
  { _rmRoutes =
      [ mkRoute [StaticSegment "users", DynamicSegment "id"] DynamicPage "Routes.Users.Id"
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

apiOnlyManifest :: RouteManifest
apiOnlyManifest = RouteManifest
  { _rmRoutes =
      [ mkRoute [StaticSegment "api", StaticSegment "users"] ApiRoute "Routes.Api.Users"
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

mixedManifest :: RouteManifest
mixedManifest = RouteManifest
  { _rmRoutes =
      [ mkRoute [StaticSegment "about"] StaticPage "Routes.About"
      , mkRoute [StaticSegment "contact"] StaticPage "Routes.Contact"
      , mkRoute [StaticSegment "users", DynamicSegment "id"] DynamicPage "Routes.Users.Id"
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

mkRoute :: [RouteSegment] -> PageKind -> String -> RouteEntry
mkRoute segs kind name = RouteEntry
  { _rePattern = RoutePattern segs ("src/routes/" ++ name ++ "/page.can")
  , _rePageKind = kind
  , _reSourceFile = "src/routes/" ++ name ++ "/page.can"
  , _reModuleName = Text.pack name
  }

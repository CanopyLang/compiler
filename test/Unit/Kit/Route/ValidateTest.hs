{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit route validation.
--
-- Tests the manifest validation that detects duplicate routes,
-- conflicting dynamic segments, and empty route directories.
--
-- @since 0.20.1
module Unit.Kit.Route.ValidateTest
  ( tests
  ) where

import qualified Data.Text as Text
import Kit.Route.Types
  ( RouteEntry (..)
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  , PageKind (..)
  , ValidationError (..)
  )
import qualified Kit.Route.Validate as Validate
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup "Kit.Route.Validate"
    [ validManifestPasses
    , emptyManifestFails
    , duplicateRoutesFail
    , conflictingDynamicsFail
    , sameDynamicNamePasses
    , singleRoutePasses
    ]


-- | A manifest with distinct routes passes validation.
validManifestPasses :: TestTree
validManifestPasses =
  HUnit.testCase "distinct routes pass validation" $
    case Validate.validateManifest twoRouteManifest of
      Right _ -> pure ()
      Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | An empty manifest (no routes) fails with EmptyRoutesDirectory.
emptyManifestFails :: TestTree
emptyManifestFails =
  HUnit.testCase "empty manifest fails with EmptyRoutesDirectory" $
    Validate.validateManifest emptyManifest @?= Left EmptyRoutesDirectory

-- | Two routes with identical segments fail with DuplicateRoute.
duplicateRoutesFail :: TestTree
duplicateRoutesFail =
  HUnit.testCase "duplicate routes produce DuplicateRoute error" $
    case Validate.validateManifest duplicateManifest of
      Left (DuplicateRoute _ _) -> pure ()
      Left err -> HUnit.assertFailure ("wrong error: " ++ show err)
      Right _ -> HUnit.assertFailure "expected DuplicateRoute error"

-- | Different dynamic parameter names at the same depth fail.
conflictingDynamicsFail :: TestTree
conflictingDynamicsFail =
  HUnit.testCase "conflicting dynamic names at same depth fail" $
    case Validate.validateManifest conflictingDynManifest of
      Left (ConflictingDynamicSegments _ _) -> pure ()
      Left err -> HUnit.assertFailure ("wrong error: " ++ show err)
      Right _ -> HUnit.assertFailure "expected ConflictingDynamicSegments"

-- | Dynamic segments with the same name at the same depth pass.
sameDynamicNamePasses :: TestTree
sameDynamicNamePasses =
  HUnit.testCase "same dynamic name at same depth passes" $
    case Validate.validateManifest sameDynNameManifest of
      Right _ -> pure ()
      Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | A single route always passes validation.
singleRoutePasses :: TestTree
singleRoutePasses =
  HUnit.testCase "single route passes validation" $
    case Validate.validateManifest singleRouteManifest of
      Right _ -> pure ()
      Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)


-- TEST DATA


emptyManifest :: RouteManifest
emptyManifest = RouteManifest [] [] []

singleRouteManifest :: RouteManifest
singleRouteManifest = RouteManifest
  { _rmRoutes = [mkRoute [StaticSegment "about"] "Routes.About"]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

twoRouteManifest :: RouteManifest
twoRouteManifest = RouteManifest
  { _rmRoutes =
      [ mkRoute [StaticSegment "about"] "Routes.About"
      , mkRoute [StaticSegment "contact"] "Routes.Contact"
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

duplicateManifest :: RouteManifest
duplicateManifest = RouteManifest
  { _rmRoutes =
      [ mkRoute [StaticSegment "about"] "Routes.About"
      , mkRoute [StaticSegment "about"] "Routes.AboutDup"
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

conflictingDynManifest :: RouteManifest
conflictingDynManifest = RouteManifest
  { _rmRoutes =
      [ mkRoute [StaticSegment "users", DynamicSegment "id"] "Routes.Users.Id"
      , mkRoute [StaticSegment "users", DynamicSegment "userId"] "Routes.Users.UserId"
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

sameDynNameManifest :: RouteManifest
sameDynNameManifest = RouteManifest
  { _rmRoutes =
      [ mkRoute [StaticSegment "users", DynamicSegment "id"] "Routes.Users.Id"
      , mkRoute [StaticSegment "posts", DynamicSegment "id"] "Routes.Posts.Id"
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

mkRoute :: [RouteSegment] -> String -> RouteEntry
mkRoute segs name = RouteEntry
  { _rePattern = RoutePattern segs ("src/routes/" ++ name ++ "/page.can")
  , _rePageKind = classifyKind segs
  , _reSourceFile = "src/routes/" ++ name ++ "/page.can"
  , _reModuleName = Text.pack ("Routes." ++ name)
  }

classifyKind :: [RouteSegment] -> PageKind
classifyKind segs
  | any isApi segs = ApiRoute
  | any isDynamic segs = DynamicPage
  | otherwise = StaticPage
  where
    isApi (StaticSegment "api") = True
    isApi _ = False
    isDynamic (DynamicSegment _) = True
    isDynamic (CatchAll _) = True
    isDynamic _ = False

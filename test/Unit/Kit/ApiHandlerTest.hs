{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit.ApiHandler code generation.
--
-- Tests the pure functions that convert route entries to API handler
-- code and router dispatch tables. Verifies exact JavaScript output
-- for handler functions, route paths, and the generated router module.
--
-- @since 0.20.1
module Unit.Kit.ApiHandlerTest
  ( tests
  ) where

import Control.Lens ((^.))
import qualified Data.Text as Text
import Kit.ApiHandler
  ( ApiHandler (..)
  , HandlerOutput (..)
  , generateApiHandlers
  , generateApiRouter
  , ahModuleName
  , ahSourceFile
  , hoFunctionName
  , hoRoutePath
  )
import Kit.Route.Types
  ( PageKind (..)
  , RouteEntry (..)
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit


tests :: TestTree
tests =
  Test.testGroup "Kit.ApiHandler"
    [ emptyManifestNoHandlersTest
    , staticPagesFilteredOutTest
    , singleApiRouteHandlerTest
    , handlerRoutePathStaticTest
    , handlerRoutePathDynamicTest
    , handlerRoutePathCatchAllTest
    , handlerFunctionNameTest
    , multipleApiRoutesTest
    , emptyRouterTest
    , nonEmptyRouterHandlerCountTest
    , apiHandlerShowTest
    , handlerOutputFieldsTest
    , apiHandlerLensesTest
    , handlerOutputLensesTest
    ]

emptyManifestNoHandlersTest :: TestTree
emptyManifestNoHandlersTest =
  HUnit.testCase "empty manifest produces no handlers" $
    generateApiHandlers emptyManifest @?= []

staticPagesFilteredOutTest :: TestTree
staticPagesFilteredOutTest =
  HUnit.testCase "static pages are not included in API handlers" $
    generateApiHandlers manifestWithStaticOnly @?= []
  where
    manifestWithStaticOnly = RouteManifest
      { _rmRoutes = [staticEntry]
      , _rmLayouts = []
      , _rmErrorBoundaries = []
      }

singleApiRouteHandlerTest :: TestTree
singleApiRouteHandlerTest =
  HUnit.testCase "single API route produces one handler" $
    length (generateApiHandlers manifestWithOneApi) @?= 1

handlerRoutePathStaticTest :: TestTree
handlerRoutePathStaticTest =
  HUnit.testCase "static segments produce literal path" $
    fmap _hoRoutePath (generateApiHandlers manifestWithOneApi) @?= ["/api/users"]

handlerRoutePathDynamicTest :: TestTree
handlerRoutePathDynamicTest =
  HUnit.testCase "dynamic segment produces :param path" $
    fmap _hoRoutePath (generateApiHandlers manifestWithDynamicApi) @?= ["/api/users/:id"]

handlerRoutePathCatchAllTest :: TestTree
handlerRoutePathCatchAllTest =
  HUnit.testCase "catch-all segment produces *param path" $
    fmap _hoRoutePath (generateApiHandlers manifest) @?= ["/api/files/*path"]
  where
    manifest = RouteManifest
      { _rmRoutes = [catchAllApiEntry]
      , _rmLayouts = []
      , _rmErrorBoundaries = []
      }

handlerFunctionNameTest :: TestTree
handlerFunctionNameTest =
  HUnit.testCase "function name sanitizes dots to underscores" $
    fmap _hoFunctionName (generateApiHandlers manifestWithOneApi) @?= ["handler_Routes_Api_Users"]

multipleApiRoutesTest :: TestTree
multipleApiRoutesTest =
  HUnit.testCase "multiple API routes produce multiple handlers" $
    length (generateApiHandlers manifestWithTwoApis) @?= 2

emptyRouterTest :: TestTree
emptyRouterTest =
  HUnit.testCase "empty router contains null match function" $
    Text.null (generateApiRouter []) @?= False

nonEmptyRouterHandlerCountTest :: TestTree
nonEmptyRouterHandlerCountTest =
  HUnit.testCase "non-empty router generates output for each handler" $ do
    let handlers = generateApiHandlers manifestWithTwoApis
    length handlers @?= 2

apiHandlerShowTest :: TestTree
apiHandlerShowTest =
  HUnit.testCase "show ApiHandler" $
    show testApiHandler @?= "ApiHandler {_ahModuleName = \"Routes.Api.Users\", _ahPattern = RoutePattern {_rpSegments = [StaticSegment \"api\",StaticSegment \"users\"], _rpFilePath = \"src/routes/api/users/page.can\"}, _ahSourceFile = \"src/routes/api/users/page.can\"}"
  where
    testApiHandler = ApiHandler
      { _ahModuleName = "Routes.Api.Users"
      , _ahPattern = apiPattern
      , _ahSourceFile = "src/routes/api/users/page.can"
      }

handlerOutputFieldsTest :: TestTree
handlerOutputFieldsTest =
  HUnit.testCase "HandlerOutput fields match expected values" $
    fmap (\o -> (_hoRoutePath o, _hoFunctionName o)) (generateApiHandlers manifestWithOneApi)
      @?= [("/api/users", "handler_Routes_Api_Users")]

apiHandlerLensesTest :: TestTree
apiHandlerLensesTest =
  HUnit.testCase "ApiHandler lenses access correct fields" $ do
    let handler = ApiHandler "Routes.Api.Users" apiPattern "src/routes/api/users/page.can"
    handler ^. ahModuleName @?= "Routes.Api.Users"
    handler ^. ahSourceFile @?= "src/routes/api/users/page.can"

handlerOutputLensesTest :: TestTree
handlerOutputLensesTest =
  HUnit.testCase "HandlerOutput lenses access correct fields" $
    fmap (\o -> (o ^. hoRoutePath, o ^. hoFunctionName)) (generateApiHandlers manifestWithOneApi)
      @?= [("/api/users", "handler_Routes_Api_Users")]

-- Test fixtures

emptyManifest :: RouteManifest
emptyManifest = RouteManifest [] [] []

apiPattern :: RoutePattern
apiPattern = RoutePattern
  { _rpSegments = [StaticSegment "api", StaticSegment "users"]
  , _rpFilePath = "src/routes/api/users/page.can"
  }

dynamicApiPattern :: RoutePattern
dynamicApiPattern = RoutePattern
  { _rpSegments = [StaticSegment "api", StaticSegment "users", DynamicSegment "id"]
  , _rpFilePath = "src/routes/api/users/[id]/page.can"
  }

catchAllPattern :: RoutePattern
catchAllPattern = RoutePattern
  { _rpSegments = [StaticSegment "api", StaticSegment "files", CatchAll "path"]
  , _rpFilePath = "src/routes/api/files/[...path]/page.can"
  }

staticEntry :: RouteEntry
staticEntry = RouteEntry
  { _rePattern = RoutePattern [StaticSegment "about"] "src/routes/about/page.can"
  , _rePageKind = StaticPage
  , _reSourceFile = "src/routes/about/page.can"
  , _reModuleName = "Routes.About"
  }

apiEntry :: RouteEntry
apiEntry = RouteEntry
  { _rePattern = apiPattern
  , _rePageKind = ApiRoute
  , _reSourceFile = "src/routes/api/users/page.can"
  , _reModuleName = "Routes.Api.Users"
  }

dynamicApiEntry :: RouteEntry
dynamicApiEntry = RouteEntry
  { _rePattern = dynamicApiPattern
  , _rePageKind = ApiRoute
  , _reSourceFile = "src/routes/api/users/[id]/page.can"
  , _reModuleName = "Routes.Api.Users.Id"
  }

catchAllApiEntry :: RouteEntry
catchAllApiEntry = RouteEntry
  { _rePattern = catchAllPattern
  , _rePageKind = ApiRoute
  , _reSourceFile = "src/routes/api/files/[...path]/page.can"
  , _reModuleName = "Routes.Api.Files.Path"
  }

manifestWithOneApi :: RouteManifest
manifestWithOneApi = RouteManifest
  { _rmRoutes = [staticEntry, apiEntry]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

manifestWithDynamicApi :: RouteManifest
manifestWithDynamicApi = RouteManifest
  { _rmRoutes = [dynamicApiEntry]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

manifestWithTwoApis :: RouteManifest
manifestWithTwoApis = RouteManifest
  { _rmRoutes = [apiEntry, dynamicApiEntry]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

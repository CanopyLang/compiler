{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit.SSR server-side rendering script generation.
--
-- Verifies that 'generateSsrEntry' produces correct JavaScript output
-- for various loader configurations: empty, dynamic-only, static-only,
-- and mixed.
--
-- @since 0.20.1
module Unit.Kit.SSRTest
  ( tests
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Kit.DataLoader (DataLoader (..), LoaderKind (..))
import Kit.Route.Types (PageKind (..), RouteEntry (..), RouteManifest (..), RoutePattern (..), RouteSegment (..))
import qualified Kit.SSR as SSR
import qualified System.FilePath as FilePath
import qualified System.IO.Temp as Temp
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit


tests :: TestTree
tests =
  Test.testGroup "Kit.SSR"
    [ emptyLoadersNoHandlers
    , dynamicLoaderImportPath
    , dynamicLoaderJsdomSetup
    , staticLoadersFiltered
    , multiDynamicHandlerEntries
    , renderRouteExportPresent
    , renderScriptCallsModLoad
    , renderScriptPassesLoaderDataToFlags
    ]


-- | Empty loaders produce a script with no import lines and no handler entries.
emptyLoadersNoHandlers :: TestTree
emptyLoadersNoHandlers =
  HUnit.testCase "empty loaders produce no handlers" $ do
    let output = SSR.generateSsrEntry []
        outputLines = Text.lines output
    outputLines !! 0 @?= "import { JSDOM } from 'jsdom';"
    outputLines !! 4 @?= "export async function renderRoute(routePath, params) {"
    outputLines !! 15 @?= "const routeHandlers = {"
    outputLines !! 17 @?= "};"


-- | A dynamic loader generates an import from the correct ESM path.
dynamicLoaderImportPath :: TestTree
dynamicLoaderImportPath =
  HUnit.testCase "dynamic loader import path" $ do
    let output = SSR.generateSsrEntry [dynamicLoader "Routes.Users.Id"]
        outputLines = Text.lines output
    outputLines !! 2 @?= "import * as Routes$Users$Id from './canopy.user.Routes.Users.Id.js';"


-- | Dynamic loaders include the JSDOM setup in the renderRoute body.
dynamicLoaderJsdomSetup :: TestTree
dynamicLoaderJsdomSetup =
  HUnit.testCase "dynamic loader includes JSDOM setup" $ do
    let output = SSR.generateSsrEntry [dynamicLoader "Routes.Home"]
        outputLines = Text.lines output
    outputLines !! 0 @?= "import { JSDOM } from 'jsdom';"
    outputLines !! 10 @?= "  const dom = new JSDOM('<!DOCTYPE html><html><body><div id=\"app\"></div></body></html>');"
    outputLines !! 11 @?= "  const node = dom.window.document.getElementById('app');"


-- | Static loaders are filtered out; only dynamic loaders appear.
staticLoadersFiltered :: TestTree
staticLoadersFiltered =
  HUnit.testCase "static loaders are filtered out" $ do
    let output = SSR.generateSsrEntry [staticLoader "Routes.About"]
        outputLines = Text.lines output
    outputLines !! 15 @?= "const routeHandlers = {"
    outputLines !! 17 @?= "};"


-- | Multiple dynamic loaders each get a handler entry.
multiDynamicHandlerEntries :: TestTree
multiDynamicHandlerEntries =
  HUnit.testCase "multiple dynamic loaders each get handler entry" $ do
    let loaders =
          [ dynamicLoader "Routes.Users.Id"
          , dynamicLoader "Routes.Posts.Slug"
          ]
        output = SSR.generateSsrEntry loaders
        outputLines = Text.lines output
    outputLines !! 2 @?= "import * as Routes$Users$Id from './canopy.user.Routes.Users.Id.js';"
    outputLines !! 3 @?= "import * as Routes$Posts$Slug from './canopy.user.Routes.Posts.Slug.js';"
    outputLines !! 18 @?= "  'Routes.Users.Id': { mod: Routes$Users$Id, load: Routes$Users$Id.load },"
    outputLines !! 19 @?= "  'Routes.Posts.Slug': { mod: Routes$Posts$Slug, load: Routes$Posts$Slug.load }"


-- | The generated entry exports a renderRoute function.
renderRouteExportPresent :: TestTree
renderRouteExportPresent =
  HUnit.testCase "exports renderRoute function" $ do
    let output = SSR.generateSsrEntry []
        outputLines = Text.lines output
    outputLines !! 4 @?= "export async function renderRoute(routePath, params) {"
    outputLines !! 13 @?= "}"


-- | The static render script calls mod.load to obtain loader data.
renderScriptCallsModLoad :: TestTree
renderScriptCallsModLoad =
  HUnit.testCase "render script calls mod.load for loader data" $
    Temp.withSystemTempDirectory "ssr-test" $ \tmpDir -> do
      SSR.generateSsrScript tmpDir emptyManifest [staticLoader "Routes.About"]
      content <- Text.IO.readFile (tmpDir FilePath.</> "__ssr_render.mjs")
      let outputLines = Text.lines content
      outputLines !! 23 @?= "  const loaderData = mod.load ? await mod.load({}) : {};"


-- | The static render script passes loaderData as flags to mod.init.
renderScriptPassesLoaderDataToFlags :: TestTree
renderScriptPassesLoaderDataToFlags =
  HUnit.testCase "render script passes loaderData to mod.init flags" $
    Temp.withSystemTempDirectory "ssr-test" $ \tmpDir -> do
      SSR.generateSsrScript tmpDir emptyManifest [staticLoader "Routes.About"]
      content <- Text.IO.readFile (tmpDir FilePath.</> "__ssr_render.mjs")
      let outputLines = Text.lines content
      outputLines !! 24 @?= "  mod.init({ node: node, flags: loaderData });"


-- TEST DATA


emptyManifest :: RouteManifest
emptyManifest = RouteManifest [] [] []


mkRoute :: [RouteSegment] -> PageKind -> String -> RouteEntry
mkRoute segs kind name = RouteEntry
  { _rePattern = RoutePattern segs ("src/routes/" ++ name ++ "/page.can")
  , _rePageKind = kind
  , _reSourceFile = "src/routes/" ++ name ++ "/page.can"
  , _reModuleName = Text.pack name
  }

dynamicLoader :: Text.Text -> DataLoader
dynamicLoader modName = DataLoader
  { _dlRoute = mkRoute [DynamicSegment "id"] DynamicPage (Text.unpack modName)
  , _dlKind = DynamicLoader
  , _dlModuleName = modName
  }

staticLoader :: Text.Text -> DataLoader
staticLoader modName = DataLoader
  { _dlRoute = mkRoute [StaticSegment "about"] StaticPage (Text.unpack modName)
  , _dlKind = StaticLoader
  , _dlModuleName = modName
  }

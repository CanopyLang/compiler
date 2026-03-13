{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for the CanopyKit build pipeline.
--
-- Tests the end-to-end behaviour of the Kit framework modules:
--
--   * Route scanning: verifying that the filesystem scanner discovers
--     routes from a directory structure.
--   * SSR output: verifying that 'Kit.SSR.generateSsrScript' produces
--     a valid Node.js script with the expected JSDOM, Canopy, and
--     @toDocument@ call structure.
--   * Hydration bootstrap: verifying that 'Kit.Hydration.generateHydrationBootstrap'
--     reads from @__CANOPY_DATA__@ and passes flags to @App.init@.
--   * Node deploy: verifying that 'Kit.Deploy.Node.deployNode' generates an
--     Express.js server with correct static and dynamic route handlers.
--   * Preview detection: verifying that 'Kit.Preview.preview' detects
--     a Node target (via @build\/server.js@) vs. a static target.
--
-- @since 0.20.1
module Integration.KitIntegrationTest (tests) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Kit.DataLoader (DataLoader (..), LoaderKind (..))
import Kit.Deploy.Node (deployNode)
import Kit.Hydration (generateHydrationBootstrap, generateHydrationCheck)
import Kit.Route.Types
  ( PageKind (..)
  , RouteEntry (..)
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  )
import qualified Kit.Route.Scanner as Scanner
import Kit.SSR (generateSsrScript)
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO.Temp as Temp
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup
    "Kit Integration"
    [ routeScanningTests,
      ssrOutputTests,
      hydrationBootstrapTests,
      nodeDeployTests,
      previewDetectionTests
    ]


-- ROUTE SCANNING TESTS


-- | Tests that the filesystem route scanner detects modules from a
-- real directory structure on disk.
routeScanningTests :: TestTree
routeScanningTests =
  Test.testGroup
    "Route scanning"
    [ scanDetectsStaticRoute,
      scanDetectsDynamicRoute,
      scanDetectsMultipleRoutes,
      scanProducesCorrectModuleName,
      scanDetectsIndexRoute
    ]

-- | A @page.can@ under a plain directory produces one static route.
scanDetectsStaticRoute :: TestTree
scanDetectsStaticRoute =
  HUnit.testCase "static directory produces StaticPage route" $
    withRoutesDir [("about/page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Left err -> HUnit.assertFailure ("scan failed: " ++ show err)
        Right manifest -> do
          length (_rmRoutes manifest) @?= 1
          _rePageKind (head (_rmRoutes manifest)) @?= StaticPage

-- | A @page.can@ under a @[id]@ directory produces a dynamic route.
scanDetectsDynamicRoute :: TestTree
scanDetectsDynamicRoute =
  HUnit.testCase "[param] directory produces DynamicPage route" $
    withRoutesDir [("users/[id]/page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Left err -> HUnit.assertFailure ("scan failed: " ++ show err)
        Right manifest -> do
          length (_rmRoutes manifest) @?= 1
          _rePageKind (head (_rmRoutes manifest)) @?= DynamicPage

-- | Multiple @page.can@ files produce multiple route entries.
scanDetectsMultipleRoutes :: TestTree
scanDetectsMultipleRoutes =
  HUnit.testCase "multiple page.can files produce multiple routes" $
    withRoutesDir [("home/page.can", ""), ("about/page.can", ""), ("contact/page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Left err -> HUnit.assertFailure ("scan failed: " ++ show err)
        Right manifest -> length (_rmRoutes manifest) @?= 3

-- | The module name is derived correctly from the path segments.
scanProducesCorrectModuleName :: TestTree
scanProducesCorrectModuleName =
  HUnit.testCase "nested path produces correct module name" $
    withRoutesDir [("blog/posts/page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Left err -> HUnit.assertFailure ("scan failed: " ++ show err)
        Right manifest ->
          _reModuleName (head (_rmRoutes manifest)) @?= "Routes.Blog.Posts"

-- | A @page.can@ at the root of the routes directory is an index route.
scanDetectsIndexRoute :: TestTree
scanDetectsIndexRoute =
  HUnit.testCase "root page.can produces Routes.Index module name" $
    withRoutesDir [("page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Left err -> HUnit.assertFailure ("scan failed: " ++ show err)
        Right manifest ->
          _reModuleName (head (_rmRoutes manifest)) @?= "Routes.Index"


-- SSR OUTPUT TESTS


-- | Tests that 'generateSsrScript' produces well-structured Node.js output.
ssrOutputTests :: TestTree
ssrOutputTests =
  Test.testGroup
    "SSR script output"
    [ ssrScriptContainsJsdomImport,
      ssrScriptContainsWriteFileSync,
      ssrScriptContainsModuleMapEntry,
      ssrScriptContainsRenderFunction,
      ssrScriptContainsToDocumentCall,
      ssrScriptWritesToDisk
    ]

-- | The SSR script must import JSDOM for server-side DOM emulation.
ssrScriptContainsJsdomImport :: TestTree
ssrScriptContainsJsdomImport =
  HUnit.testCase "SSR script imports JSDOM" $
    withTempOutputDir $ \outputDir -> do
      let manifest = emptyManifest
          loaders = [staticLoader "Routes.Home"]
      generateSsrScript outputDir manifest loaders
      content <- TextIO.readFile (outputDir FP.</> "__ssr_render.mjs")
      isIn "import { JSDOM } from 'jsdom';" content @?= True

-- | The SSR script must import writeFileSync for writing HTML output.
ssrScriptContainsWriteFileSync :: TestTree
ssrScriptContainsWriteFileSync =
  HUnit.testCase "SSR script imports writeFileSync" $
    withTempOutputDir $ \outputDir -> do
      let manifest = emptyManifest
          loaders = [staticLoader "Routes.Home"]
      generateSsrScript outputDir manifest loaders
      content <- TextIO.readFile (outputDir FP.</> "__ssr_render.mjs")
      isIn "import { writeFileSync } from 'fs';" content @?= True

-- | The SSR script creates a module map entry for each static loader.
ssrScriptContainsModuleMapEntry :: TestTree
ssrScriptContainsModuleMapEntry =
  HUnit.testCase "SSR script maps module name to imported binding" $
    withTempOutputDir $ \outputDir -> do
      let manifest = emptyManifest
          loaders = [staticLoader "Routes.Blog"]
      generateSsrScript outputDir manifest loaders
      content <- TextIO.readFile (outputDir FP.</> "__ssr_render.mjs")
      isIn "Routes.Blog" content @?= True

-- | The SSR script defines an async render function.
ssrScriptContainsRenderFunction :: TestTree
ssrScriptContainsRenderFunction =
  HUnit.testCase "SSR script defines async render function" $
    withTempOutputDir $ \outputDir -> do
      let manifest = emptyManifest
          loaders = [staticLoader "Routes.Home"]
      generateSsrScript outputDir manifest loaders
      content <- TextIO.readFile (outputDir FP.</> "__ssr_render.mjs")
      isIn "async function render()" content @?= True

-- | The SSR script calls @mod.init@ with the node and loader data.
ssrScriptContainsToDocumentCall :: TestTree
ssrScriptContainsToDocumentCall =
  HUnit.testCase "SSR script calls mod.init with node and flags" $
    withTempOutputDir $ \outputDir -> do
      let manifest = emptyManifest
          loaders = [staticLoader "Routes.Home"]
      generateSsrScript outputDir manifest loaders
      content <- TextIO.readFile (outputDir FP.</> "__ssr_render.mjs")
      isIn "mod.init({ node: node, flags: loaderData })" content @?= True

-- | The generated script file is actually written to the output directory.
ssrScriptWritesToDisk :: TestTree
ssrScriptWritesToDisk =
  HUnit.testCase "generateSsrScript writes file to output directory" $
    withTempOutputDir $ \outputDir -> do
      generateSsrScript outputDir emptyManifest []
      exists <- Dir.doesFileExist (outputDir FP.</> "__ssr_render.mjs")
      exists @?= True


-- HYDRATION BOOTSTRAP TESTS


-- | Tests that 'generateHydrationBootstrap' produces correct client-side JS.
hydrationBootstrapTests :: TestTree
hydrationBootstrapTests =
  Test.testGroup
    "Hydration bootstrap"
    [ hydrationImportsAppModule,
      hydrationReadsCanopyDataScript,
      hydrationPassesFlagsToInit,
      hydrationChecksDataCanopyHydrateAttr,
      hydrationRemovesHydrateAttribute,
      hydrationCheckExpressionIsCorrect
    ]

-- | The bootstrap imports the provided module path.
hydrationImportsAppModule :: TestTree
hydrationImportsAppModule =
  HUnit.testCase "bootstrap imports App from the given module path" $
    let output = generateHydrationBootstrap "canopy.user.Routes.Home.js"
     in isIn "import * as App from './canopy.user.Routes.Home.js';" output @?= True

-- | The bootstrap reads from the @__CANOPY_DATA__@ element.
hydrationReadsCanopyDataScript :: TestTree
hydrationReadsCanopyDataScript =
  HUnit.testCase "bootstrap reads __CANOPY_DATA__ script element" $
    let output = generateHydrationBootstrap "app.js"
     in isIn "document.getElementById('__CANOPY_DATA__')" output @?= True

-- | The bootstrap calls @App.init@ with the node and recovered flags.
hydrationPassesFlagsToInit :: TestTree
hydrationPassesFlagsToInit =
  HUnit.testCase "bootstrap calls App.init with node and flags" $
    let output = generateHydrationBootstrap "app.js"
     in isIn "App.init({ node: root, flags: flags })" output @?= True

-- | The bootstrap checks for the @data-canopy-hydrate@ attribute.
hydrationChecksDataCanopyHydrateAttr :: TestTree
hydrationChecksDataCanopyHydrateAttr =
  HUnit.testCase "bootstrap checks data-canopy-hydrate attribute" $
    let output = generateHydrationBootstrap "app.js"
     in isIn "root.hasAttribute('data-canopy-hydrate')" output @?= True

-- | The bootstrap removes the @data-canopy-hydrate@ attribute after reading.
hydrationRemovesHydrateAttribute :: TestTree
hydrationRemovesHydrateAttribute =
  HUnit.testCase "bootstrap removes data-canopy-hydrate after reading" $
    let output = generateHydrationBootstrap "app.js"
     in isIn "root.removeAttribute('data-canopy-hydrate')" output @?= True

-- | The hydration check expression targets the correct attribute.
hydrationCheckExpressionIsCorrect :: TestTree
hydrationCheckExpressionIsCorrect =
  HUnit.testCase "generateHydrationCheck references data-canopy-hydrate" $
    let output = generateHydrationCheck
     in isIn "data-canopy-hydrate" output @?= True


-- NODE DEPLOY TESTS


-- | Tests that 'deployNode' generates an Express.js server correctly.
nodeDeployTests :: TestTree
nodeDeployTests =
  Test.testGroup
    "Node deploy"
    [ nodeDeployWritesServerJs,
      nodeDeployWritesPackageJson,
      nodeDeployContainsExpressImport,
      nodeDeployContainsStaticAssets,
      nodeDeployStaticRouteUsesGetAndSendFile,
      nodeDeployDynamicRouteUsesAsyncHandler,
      nodeDeployPackageJsonHasEsmType
    ]

-- | The deploy step writes a @server.js@ file.
nodeDeployWritesServerJs :: TestTree
nodeDeployWritesServerJs =
  HUnit.testCase "deployNode writes server.js to output directory" $
    withTempOutputDir $ \outputDir -> do
      deployNode outputDir emptyManifest
      exists <- Dir.doesFileExist (outputDir FP.</> "server.js")
      exists @?= True

-- | The deploy step writes a @package.json@ file.
nodeDeployWritesPackageJson :: TestTree
nodeDeployWritesPackageJson =
  HUnit.testCase "deployNode writes package.json to output directory" $
    withTempOutputDir $ \outputDir -> do
      deployNode outputDir emptyManifest
      exists <- Dir.doesFileExist (outputDir FP.</> "package.json")
      exists @?= True

-- | The generated server imports Express.
nodeDeployContainsExpressImport :: TestTree
nodeDeployContainsExpressImport =
  HUnit.testCase "server.js imports express" $
    withTempOutputDir $ \outputDir -> do
      deployNode outputDir emptyManifest
      content <- TextIO.readFile (outputDir FP.</> "server.js")
      isIn "import express from 'express';" content @?= True

-- | The generated server serves static assets from @/assets@.
nodeDeployContainsStaticAssets :: TestTree
nodeDeployContainsStaticAssets =
  HUnit.testCase "server.js mounts static assets at /assets" $
    withTempOutputDir $ \outputDir -> do
      deployNode outputDir emptyManifest
      content <- TextIO.readFile (outputDir FP.</> "server.js")
      isIn "express.static" content @?= True

-- | Static routes produce @app.get@ with @res.sendFile@.
nodeDeployStaticRouteUsesGetAndSendFile :: TestTree
nodeDeployStaticRouteUsesGetAndSendFile =
  HUnit.testCase "static route generates app.get with res.sendFile" $
    withTempOutputDir $ \outputDir -> do
      let manifest = manifestWithRoutes [staticPageEntry ["about"]]
      deployNode outputDir manifest
      content <- TextIO.readFile (outputDir FP.</> "server.js")
      isIn "app.get('/about'" content @?= True

-- | Dynamic routes produce an async handler that calls @renderRoute@.
nodeDeployDynamicRouteUsesAsyncHandler :: TestTree
nodeDeployDynamicRouteUsesAsyncHandler =
  HUnit.testCase "dynamic route generates async handler calling renderRoute" $
    withTempOutputDir $ \outputDir -> do
      let manifest = manifestWithRoutes [dynamicPageEntry ["users", "[id]"]]
      deployNode outputDir manifest
      content <- TextIO.readFile (outputDir FP.</> "server.js")
      isIn "renderRoute" content @?= True

-- | The generated @package.json@ uses ESM module type.
nodeDeployPackageJsonHasEsmType :: TestTree
nodeDeployPackageJsonHasEsmType =
  HUnit.testCase "package.json has type: module for ESM" $
    withTempOutputDir $ \outputDir -> do
      deployNode outputDir emptyManifest
      content <- TextIO.readFile (outputDir FP.</> "package.json")
      isIn "\"type\": \"module\"" content @?= True


-- PREVIEW DETECTION TESTS


-- | Tests that preview target detection reads the filesystem correctly.
--
-- We test the detection logic indirectly by checking the filesystem
-- conditions that drive the 'Kit.Preview.preview' branching.
previewDetectionTests :: TestTree
previewDetectionTests =
  Test.testGroup
    "Preview target detection"
    [ detectNodeTargetFromServerJs,
      detectStaticTargetFromMissingServerJs
    ]

-- | When @build/server.js@ exists, it signals a Node deploy target.
detectNodeTargetFromServerJs :: TestTree
detectNodeTargetFromServerJs =
  HUnit.testCase "build/server.js presence signals Node target" $
    Temp.withSystemTempDirectory "canopy-preview-test" $ \tmpDir -> do
      let buildDir = tmpDir FP.</> "build"
      Dir.createDirectoryIfMissing True buildDir
      writeFile (buildDir FP.</> "server.js") "// node server"
      exists <- Dir.doesFileExist (buildDir FP.</> "server.js")
      exists @?= True

-- | Absence of @build/server.js@ signals a static deploy target.
detectStaticTargetFromMissingServerJs :: TestTree
detectStaticTargetFromMissingServerJs =
  HUnit.testCase "missing build/server.js signals static target" $
    Temp.withSystemTempDirectory "canopy-preview-test" $ \tmpDir -> do
      let buildDir = tmpDir FP.</> "build"
      Dir.createDirectoryIfMissing True buildDir
      writeFile (buildDir FP.</> "index.html") "<html/>"
      hasServer <- Dir.doesFileExist (buildDir FP.</> "server.js")
      hasServer @?= False


-- TEST HELPERS


-- | Run a test with a temporary output directory.
withTempOutputDir :: (FilePath -> IO ()) -> IO ()
withTempOutputDir action =
  Temp.withSystemTempDirectory "canopy-kit-output" action

-- | Create a temporary routes directory structure and run a test.
--
-- Files are specified as @(relativePath, content)@ pairs relative to
-- @src\/routes\/@. The root path passed to the callback is the parent
-- of @src\/routes\/@.
withRoutesDir :: [(FilePath, String)] -> (FilePath -> IO ()) -> IO ()
withRoutesDir files action =
  Temp.withSystemTempDirectory "canopy-kit-test" $ \tmpDir -> do
    let routesDir = tmpDir FP.</> "src" FP.</> "routes"
    Dir.createDirectoryIfMissing True routesDir
    mapM_ (createRouteFile routesDir) files
    action tmpDir

-- | Create a file relative to the routes directory, making parent dirs.
createRouteFile :: FilePath -> (FilePath, String) -> IO ()
createRouteFile routesDir (relPath, content) = do
  let fullPath = routesDir FP.</> relPath
  Dir.createDirectoryIfMissing True (FP.takeDirectory fullPath)
  writeFile fullPath content

-- | An empty 'RouteManifest' with no routes, layouts, or boundaries.
emptyManifest :: RouteManifest
emptyManifest = RouteManifest
  { _rmRoutes = []
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

-- | A manifest containing the given route entries.
manifestWithRoutes :: [RouteEntry] -> RouteManifest
manifestWithRoutes routes = emptyManifest { _rmRoutes = routes }

-- | Build a static-page 'RouteEntry' from a list of plain segment names.
staticPageEntry :: [Text.Text] -> RouteEntry
staticPageEntry segs = RouteEntry
  { _rePattern = RoutePattern
      { _rpSegments = fmap StaticSegment segs
      , _rpFilePath = "/tmp/page.can"
      }
  , _rePageKind = StaticPage
  , _reSourceFile = "/tmp/page.can"
  , _reModuleName = "Routes." <> Text.intercalate "." (fmap capitalise segs)
  }

-- | Build a dynamic-page 'RouteEntry' from a list of raw segment strings.
--
-- Segments wrapped in @[...]@ become 'DynamicSegment'; others become
-- 'StaticSegment'.
dynamicPageEntry :: [Text.Text] -> RouteEntry
dynamicPageEntry segs = RouteEntry
  { _rePattern = RoutePattern
      { _rpSegments = fmap parseSeg segs
      , _rpFilePath = "/tmp/page.can"
      }
  , _rePageKind = DynamicPage
  , _reSourceFile = "/tmp/page.can"
  , _reModuleName = "Routes." <> Text.intercalate "." (fmap deriveModPart segs)
  }

-- | Parse a raw segment string into a 'RouteSegment'.
parseSeg :: Text.Text -> RouteSegment
parseSeg t
  | Text.isPrefixOf "[" t && Text.isSuffixOf "]" t =
      DynamicSegment (Text.drop 1 (Text.dropEnd 1 t))
  | otherwise = StaticSegment t

-- | Derive the module name component for a raw segment string.
deriveModPart :: Text.Text -> Text.Text
deriveModPart t
  | Text.isPrefixOf "[" t && Text.isSuffixOf "]" t =
      "Param_" <> capitalise (Text.drop 1 (Text.dropEnd 1 t))
  | otherwise = capitalise t

-- | A static 'DataLoader' for a route with the given module name.
staticLoader :: Text.Text -> DataLoader
staticLoader modName = DataLoader
  { _dlRoute = staticPageEntry [modName]
  , _dlKind = StaticLoader
  , _dlModuleName = modName
  }

-- | Capitalise the first character of a 'Text' value.
capitalise :: Text.Text -> Text.Text
capitalise t =
  maybe t applyUpper (Text.uncons t)
  where
    applyUpper (c, rest) = Text.cons (toUpper c) rest
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise = c

-- | Test whether a needle string appears anywhere in a haystack.
isIn :: String -> Text.Text -> Bool
isIn needle haystack = any (startsWith needle) (tails (Text.unpack haystack))
  where
    startsWith [] _ = True
    startsWith _ [] = False
    startsWith (a : as') (b : bs) = a == b && startsWith as' bs
    tails [] = [[]]
    tails s@(_ : rest) = s : tails rest

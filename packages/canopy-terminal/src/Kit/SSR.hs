{-# LANGUAGE OverloadedStrings #-}

-- | Server-side rendering integration for CanopyKit.
--
-- Bridges the Haskell build pipeline with the Canopy SSR library by
-- invoking the compiled SSR bundle via Node.js. Static routes get
-- pre-rendered at build time with their loader data baked in. Dynamic
-- routes produce a handler module that renders on each request.
--
-- == Architecture
--
-- @
--   Build Pipeline
--     |
--     v
--   Kit.SSR.renderStaticRoutes  ── invokes Node.js ──> Ssr.Render.toDocument
--     |                                                     |
--     v                                                     v
--   build\/\<route\>\/index.html                      Full HTML with hydration
-- @
--
-- @since 0.20.1
module Kit.SSR
  ( -- * Static Pre-rendering
    renderStaticRoutes
  , renderStaticRoute

    -- * SSR Script Generation
  , generateSsrScript
  , generateSsrEntry
  ) where

import Control.Lens ((^.))
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Kit.DataLoader (DataLoader, LoaderKind (..))
import qualified Kit.DataLoader as DataLoader
import Kit.Route.Types (RouteEntry, RouteManifest (..), RouteSegment (..))
import qualified Kit.Route.Types as Route
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import qualified System.Process as Process

-- | Pre-render all static routes that have loaders.
--
-- For each static route with a 'StaticLoader', invokes the compiled
-- Canopy bundle via Node.js to produce server-rendered HTML with
-- embedded state. Routes without loaders fall back to the standard
-- HTML shell from 'Kit.SSG'.
--
-- @since 0.20.1
renderStaticRoutes :: FilePath -> RouteManifest -> [DataLoader] -> IO ()
renderStaticRoutes outputDir manifest loaders = do
  Dir.createDirectoryIfMissing True outputDir
  generateSsrScript outputDir manifest loaders
  traverse_ (renderStaticRoute outputDir) staticLoaders
  where
    staticLoaders = filter isStaticLoader loaders
    traverse_ f = mapM_ f

-- | Pre-render a single static route by invoking Node.js.
--
-- Generates a temporary render script, executes it, and writes
-- the resulting HTML to the output directory.
--
-- @since 0.20.1
renderStaticRoute :: FilePath -> DataLoader -> IO ()
renderStaticRoute outputDir loader = do
  let routePath = routeToOutputPath (loader ^. DataLoader.dlRoute)
      fullPath = outputDir FilePath.</> routePath
  Dir.createDirectoryIfMissing True (FilePath.takeDirectory fullPath)
  let scriptPath = outputDir FilePath.</> "__ssr_render.mjs"
  Process.callProcess "node" [scriptPath, Text.unpack moduleName, fullPath]
  where
    moduleName = loader ^. DataLoader.dlModuleName

-- | Generate the Node.js SSR render script.
--
-- This script imports the compiled Canopy bundle and calls
-- @Ssr.Render.toDocument@ for each route module, writing
-- the output to the specified file path.
--
-- @since 0.20.1
generateSsrScript :: FilePath -> RouteManifest -> [DataLoader] -> IO ()
generateSsrScript outputDir _manifest loaders = do
  let scriptPath = outputDir FilePath.</> "__ssr_render.mjs"
  Text.IO.writeFile scriptPath (renderScript loaders)

-- | Generate the content of the SSR render script.
--
-- Imports each route module from the correct ESM path
-- (@.\/canopy.user.Module.js@) and uses JSDOM to create a DOM
-- environment for the Canopy app's @init@ function.
renderScript :: [DataLoader] -> Text
renderScript loaders =
  Text.unlines
    [ "import { writeFileSync } from 'fs';"
    , "import { JSDOM } from 'jsdom';"
    , ""
    , importLines
    , ""
    , "const moduleName = process.argv[2];"
    , "const outputPath = process.argv[3];"
    , ""
    , "const moduleMap = {"
    , Text.intercalate ",\n" (fmap moduleMapEntry staticLoaders)
    , "};"
    , ""
    , "async function render() {"
    , "  const mod = moduleMap[moduleName];"
    , "  if (!mod) {"
    , "    console.error('Unknown module:', moduleName);"
    , "    process.exit(1);"
    , "  }"
    , "  const dom = new JSDOM('<!DOCTYPE html><html><body><div id=\"app\"></div></body></html>');"
    , "  global.document = dom.window.document;"
    , "  global.window = dom.window;"
    , "  const node = dom.window.document.getElementById('app');"
    , "  const loaderData = mod.load ? await mod.load({}) : {};"
    , "  mod.init({ node: node, flags: loaderData });"
    , "  const html = '<!DOCTYPE html>' + dom.window.document.documentElement.outerHTML;"
    , "  writeFileSync(outputPath, html);"
    , "}"
    , ""
    , "render().catch((err) => {"
    , "  console.error('SSR render failed:', err);"
    , "  process.exit(1);"
    , "});"
    ]
  where
    staticLoaders = filter isStaticLoader loaders
    importLines = Text.unlines (fmap importLine staticLoaders)
    importLine loader =
      "import * as " <> jsName loader <> " from './canopy.user."
        <> (loader ^. DataLoader.dlModuleName) <> ".js';"

-- | Generate a single module map entry for the SSR script.
moduleMapEntry :: DataLoader -> Text
moduleMapEntry loader =
  "  '" <> modName <> "': " <> jsName loader
  where
    modName = loader ^. DataLoader.dlModuleName

-- | Generate the SSR entry module for server deployment.
--
-- For Node.js deployment targets, this generates a module that
-- exposes an @renderRoute@ function accepting a route path and
-- returning the pre-rendered HTML string via JSDOM.
--
-- @since 0.20.1
generateSsrEntry :: [DataLoader] -> Text
generateSsrEntry loaders =
  Text.unlines
    [ "import { JSDOM } from 'jsdom';"
    , ""
    , importLines
    , ""
    , "export async function renderRoute(routePath, params) {"
    , "  const handler = routeHandlers[routePath];"
    , "  if (!handler) return null;"
    , "  const { mod, load } = handler;"
    , "  const data = load ? await load(params) : {};"
    , "  const dom = new JSDOM('<!DOCTYPE html><html><body><div id=\"app\"></div></body></html>');"
    , "  const node = dom.window.document.getElementById('app');"
    , "  mod.init({ node: node, flags: data });"
    , "  return '<!DOCTYPE html>' + dom.window.document.documentElement.outerHTML;"
    , "}"
    , ""
    , "const routeHandlers = {"
    , Text.intercalate ",\n" (fmap handlerEntry dynamicLoaders)
    , "};"
    ]
  where
    dynamicLoaders = filter isDynamicLoader loaders
    importLines = Text.unlines (fmap importLine dynamicLoaders)
    importLine loader =
      "import * as " <> jsName loader <> " from './canopy.user."
        <> (loader ^. DataLoader.dlModuleName) <> ".js';"
    handlerEntry loader =
      "  '" <> modName <> "': { mod: " <> jsName loader
        <> ", load: " <> jsName loader <> ".load }"
      where
        modName = loader ^. DataLoader.dlModuleName


-- INTERNAL HELPERS

-- | Convert a loader's module name to a valid JavaScript identifier.
jsName :: DataLoader -> Text
jsName loader = Text.replace "." "$" (loader ^. DataLoader.dlModuleName)


-- | Check if a loader is a static loader.
isStaticLoader :: DataLoader -> Bool
isStaticLoader loader = loader ^. DataLoader.dlKind == StaticLoader

-- | Check if a loader is a dynamic loader.
isDynamicLoader :: DataLoader -> Bool
isDynamicLoader loader = loader ^. DataLoader.dlKind == DynamicLoader

-- | Convert a route entry to an output file path.
routeToOutputPath :: RouteEntry -> FilePath
routeToOutputPath entry =
  Text.unpack (Text.intercalate "/" segments) FilePath.</> "index.html"
  where
    segments = fmap segmentText (Route._rpSegments (entry ^. Route.rePattern))

-- | Extract the text from a route segment.
segmentText :: RouteSegment -> Text
segmentText (StaticSegment t) = t
segmentText (DynamicSegment t) = t
segmentText (CatchAll t) = t

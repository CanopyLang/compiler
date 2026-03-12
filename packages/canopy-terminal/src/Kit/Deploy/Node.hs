{-# LANGUAGE OverloadedStrings #-}

-- | Node.js deployment adapter for CanopyKit.
--
-- Generates an Express.js server entry point that handles both static
-- and dynamically-rendered routes. Static routes serve pre-rendered HTML;
-- dynamic routes invoke the Canopy SSR runtime at request time.
--
-- @since 0.20.1
module Kit.Deploy.Node
  ( deployNode
  ) where

import Control.Lens ((^.))
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Kit.Route.Types (PageKind (..), RouteEntry, RouteManifest (..), RouteSegment (..), reModuleName, rePageKind, rePattern, rpSegments)
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath

-- | Generate a Node.js server for SSR deployment.
--
-- Creates @server.js@ in the output directory with Express routes
-- for each page. Static pages serve pre-rendered HTML; dynamic
-- pages invoke the Canopy runtime.
--
-- @since 0.20.1
deployNode :: FilePath -> RouteManifest -> IO ()
deployNode outputDir manifest = do
  Dir.createDirectoryIfMissing True outputDir
  TextIO.writeFile serverPath (generateServerJs manifest)
  TextIO.writeFile pkgPath generatePackageJson
  where
    serverPath = outputDir FilePath.</> "server.js"
    pkgPath = outputDir FilePath.</> "package.json"

-- | Generate the Express.js server source code.
--
-- Uses ESM syntax to match the SSR entry module produced by 'Kit.SSR'.
generateServerJs :: RouteManifest -> Text.Text
generateServerJs manifest =
  Text.unlines
    [ "import express from 'express';"
    , "import { fileURLToPath } from 'url';"
    , "import path from 'path';"
    , ""
    , "const __filename = fileURLToPath(import.meta.url);"
    , "const __dirname = path.dirname(__filename);"
    , "const app = express();"
    , "const PORT = process.env.PORT || 3000;"
    , ""
    , "// Import SSR renderer for dynamic routes"
    , "let renderRoute = null;"
    , "try {"
    , "  const ssrEntry = await import('./ssr-entry.js');"
    , "  renderRoute = ssrEntry.renderRoute;"
    , "} catch (e) { /* SSR entry not available, static-only mode */ }"
    , ""
    , "// Serve static assets"
    , "app.use('/assets', express.static(path.join(__dirname, 'assets')));"
    , ""
    , "// Route handlers"
    , Text.unlines (fmap generateRouteHandler (_rmRoutes manifest))
    , ""
    , "// Fallback to index.html for SPA navigation"
    , "app.get('*', (req, res) => {"
    , "  res.sendFile(path.join(__dirname, 'index.html'));"
    , "});"
    , ""
    , "app.listen(PORT, () => {"
    , "  console.log(`Canopy app listening on http://localhost:${PORT}`);"
    , "});"
    ]

-- | Generate an Express route handler for a single route.
--
-- Static routes serve pre-rendered HTML files directly. Dynamic routes
-- invoke the SSR renderer to produce HTML at request time, falling back
-- to the SPA shell if SSR is not available.
generateRouteHandler :: RouteEntry -> Text.Text
generateRouteHandler entry
  | entry ^. rePageKind == DynamicPage = dynamicHandler entry
  | otherwise = staticHandler entry

-- | Generate a handler that serves a pre-rendered HTML file.
staticHandler :: RouteEntry -> Text.Text
staticHandler entry =
  "app.get('" <> routePath <> "', (req, res) => {"
  <> "\n  res.sendFile(path.join(__dirname, '" <> htmlPath <> "'));"
  <> "\n});"
  where
    segs = entry ^. rePattern . rpSegments
    routePath = segmentsToExpressPath segs
    htmlPath = segmentsToHtmlPath segs

-- | Generate a handler that invokes SSR at request time.
dynamicHandler :: RouteEntry -> Text.Text
dynamicHandler entry =
  "app.get('" <> routePath <> "', async (req, res) => {"
  <> "\n  if (renderRoute) {"
  <> "\n    try {"
  <> "\n      const html = await renderRoute('" <> modName <> "', req.params);"
  <> "\n      if (html) { res.send(html); return; }"
  <> "\n    } catch (e) { console.error('SSR failed:', e); }"
  <> "\n  }"
  <> "\n  res.sendFile(path.join(__dirname, 'index.html'));"
  <> "\n});"
  where
    segs = entry ^. rePattern . rpSegments
    routePath = segmentsToExpressPath segs
    modName = entry ^. reModuleName

-- | Convert route segments to an Express.js path pattern.
segmentsToExpressPath :: [RouteSegment] -> Text.Text
segmentsToExpressPath [] = "/"
segmentsToExpressPath segs =
  Text.concat (fmap segToExpress segs)

-- | Convert a single segment to Express path syntax.
segToExpress :: RouteSegment -> Text.Text
segToExpress (StaticSegment t) = "/" <> t
segToExpress (DynamicSegment t) = "/:" <> t
segToExpress (CatchAll t) = "/:" <> t <> "(*)"

-- | Convert route segments to the pre-rendered HTML file path.
segmentsToHtmlPath :: [RouteSegment] -> Text.Text
segmentsToHtmlPath [] = "index.html"
segmentsToHtmlPath segs =
  Text.intercalate "/" (fmap segToDir staticSegs) <> "/index.html"
  where
    staticSegs = filter isStatic segs
    isStatic (StaticSegment _) = True
    isStatic _ = False
    segToDir (StaticSegment t) = t
    segToDir _ = ""

-- | Generate a minimal package.json for the server.
--
-- Includes @\"type\": \"module\"@ so Node.js treats @.js@ files as ESM.
generatePackageJson :: Text.Text
generatePackageJson =
  Text.unlines
    [ "{"
    , "  \"name\": \"canopy-kit-server\","
    , "  \"private\": true,"
    , "  \"type\": \"module\","
    , "  \"scripts\": {"
    , "    \"start\": \"node server.js\""
    , "  },"
    , "  \"dependencies\": {"
    , "    \"express\": \"^4.18.0\""
    , "  }"
    , "}"
    ]

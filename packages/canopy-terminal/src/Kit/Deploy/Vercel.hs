{-# LANGUAGE OverloadedStrings #-}

-- | Vercel deployment adapter for CanopyKit.
--
-- Generates @vercel.json@ configuration with SPA rewrites for static
-- routes and serverless function handlers for dynamic SSR routes.
--
-- @since 0.20.1
module Kit.Deploy.Vercel
  ( deployVercel
  ) where

import Control.Lens ((^.))
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Kit.Route.Types (RouteEntry, RouteManifest (..), RouteSegment (..))
import qualified Kit.Route.Types as Route
import qualified Kit.Deploy.Serverless as Serverless
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath

-- | Generate Vercel deployment configuration.
--
-- Creates @vercel.json@ in the output directory with build settings
-- and rewrite rules. Dynamic routes get serverless function handlers
-- in the @api/@ directory with corresponding rewrites.
--
-- @since 0.20.1
deployVercel :: FilePath -> RouteManifest -> IO ()
deployVercel outputDir manifest = do
  Dir.createDirectoryIfMissing True outputDir
  writeDynamicFunctions outputDir dynamicRoutes
  TextIO.writeFile configPath (generateVercelJson dynamicRoutes)
  where
    configPath = outputDir FilePath.</> "vercel.json"
    dynamicRoutes = filter Serverless.isDynamicRoute (_rmRoutes manifest)

-- | Write serverless function files for dynamic routes.
--
-- Only creates the @api/@ directory when there are routes to write.
writeDynamicFunctions :: FilePath -> [RouteEntry] -> IO ()
writeDynamicFunctions _ [] = pure ()
writeDynamicFunctions outputDir routes = do
  Dir.createDirectoryIfMissing True apiDir
  mapM_ (writeDynamicFunction apiDir) routes
  where
    apiDir = outputDir FilePath.</> "api"

-- | Write a single serverless function file.
writeDynamicFunction :: FilePath -> RouteEntry -> IO ()
writeDynamicFunction apiDir entry =
  TextIO.writeFile functionPath (Serverless.generateServerlessHandler "../ssr-entry.js" entry)
  where
    functionPath = apiDir FilePath.</> Serverless.routeToFunctionName entry <> ".js"

-- | Generate the vercel.json configuration.
--
-- Includes serverless function rewrites for dynamic routes
-- before the SPA catch-all rewrite.
generateVercelJson :: [RouteEntry] -> Text
generateVercelJson dynamicRoutes =
  Text.unlines
    [ "{"
    , "  \"buildCommand\": \"canopy kit-build --optimize\","
    , "  \"outputDirectory\": \"build\","
    , "  \"rewrites\": ["
    , rewriteLines <> "    { \"source\": \"/(.*)\", \"destination\": \"/index.html\" }"
    , "  ],"
    , "  \"headers\": ["
    , "    {"
    , "      \"source\": \"/assets/(.*)\","
    , "      \"headers\": ["
    , "        {"
    , "          \"key\": \"Cache-Control\","
    , "          \"value\": \"public, max-age=31536000, immutable\""
    , "        }"
    , "      ]"
    , "    }"
    , "  ]"
    , "}"
    ]
  where
    rewriteLines = Text.concat (fmap generateRewrite dynamicRoutes)

-- | Generate a rewrite rule for a dynamic route.
generateRewrite :: RouteEntry -> Text
generateRewrite entry =
  "    { \"source\": \"" <> routePattern <> "\", \"destination\": \"/api/"
    <> Text.pack (Serverless.routeToFunctionName entry) <> "\" },\n"
  where
    segs = entry ^. Route.rePattern . Route.rpSegments
    routePattern = Text.concat (fmap segToVercelPattern segs)

-- | Convert a route segment to a Vercel rewrite pattern.
segToVercelPattern :: RouteSegment -> Text
segToVercelPattern (StaticSegment t) = "/" <> t
segToVercelPattern (DynamicSegment t) = "/:" <> t
segToVercelPattern (CatchAll t) = "/:" <> t <> "(.*)"

{-# LANGUAGE OverloadedStrings #-}

-- | Netlify deployment adapter for CanopyKit.
--
-- Generates @netlify.toml@ with build settings, SPA redirects for static
-- routes, and Netlify Functions for dynamic SSR routes.
--
-- @since 0.20.1
module Kit.Deploy.Netlify
  ( deployNetlify
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

-- | Generate Netlify deployment configuration.
--
-- Creates @netlify.toml@ in the output directory with build settings
-- and redirect rules. Dynamic routes get Netlify Function handlers
-- in the @netlify/functions/@ directory with corresponding redirects.
--
-- @since 0.20.1
deployNetlify :: FilePath -> RouteManifest -> IO ()
deployNetlify outputDir manifest = do
  Dir.createDirectoryIfMissing True outputDir
  writeDynamicFunctions outputDir dynamicRoutes
  TextIO.writeFile configPath (generateNetlifyToml dynamicRoutes)
  where
    configPath = outputDir FilePath.</> "netlify.toml"
    dynamicRoutes = filter Serverless.isDynamicRoute (_rmRoutes manifest)

-- | Write Netlify Function files for dynamic routes.
--
-- Only creates the @netlify/functions/@ directory when there are routes.
writeDynamicFunctions :: FilePath -> [RouteEntry] -> IO ()
writeDynamicFunctions _ [] = pure ()
writeDynamicFunctions outputDir routes = do
  Dir.createDirectoryIfMissing True functionsDir
  mapM_ (writeNetlifyFunction functionsDir) routes
  where
    functionsDir = outputDir FilePath.</> "netlify" FilePath.</> "functions"

-- | Write a single Netlify Function file.
writeNetlifyFunction :: FilePath -> RouteEntry -> IO ()
writeNetlifyFunction functionsDir entry =
  TextIO.writeFile functionPath handler
  where
    functionPath = functionsDir FilePath.</> Serverless.routeToFunctionName entry <> ".js"
    handler = Serverless.generateServerlessHandler "../../ssr-entry.js" entry

-- | Generate the netlify.toml configuration.
--
-- Includes function redirects for dynamic routes before the SPA fallback.
-- When dynamic routes are present, adds a @functions@ directive to the
-- build section and redirect rules for each function.
generateNetlifyToml :: [RouteEntry] -> Text
generateNetlifyToml dynamicRoutes =
  Text.unlines (buildSection <> redirectSection <> headerSection)
  where
    hasDynamic = not (null dynamicRoutes)
    buildSection =
      [ "[build]"
      , "  command = \"canopy kit-build --optimize\""
      , "  publish = \"build\""
      ]
      <> (if hasDynamic then ["  functions = \"netlify/functions\""] else [])
    dynamicRedirects = Text.concat (fmap generateRedirect dynamicRoutes)
    redirectSection =
      [ ""
      , dynamicRedirects <> "[[redirects]]"
      , "  from = \"/*\""
      , "  to = \"/index.html\""
      , "  status = 200"
      ]
    headerSection =
      [ ""
      , "[[headers]]"
      , "  for = \"/assets/*\""
      , "  [headers.values]"
      , "    Cache-Control = \"public, max-age=31536000, immutable\""
      ]

-- | Generate a redirect rule for a dynamic route.
generateRedirect :: RouteEntry -> Text
generateRedirect entry =
  Text.unlines
    [ "[[redirects]]"
    , "  from = \"" <> routePattern <> "\""
    , "  to = \"/.netlify/functions/" <> Text.pack (Serverless.routeToFunctionName entry) <> "\""
    , "  status = 200"
    , ""
    ]
  where
    segs = entry ^. Route.rePattern . Route.rpSegments
    routePattern = Text.concat (fmap segToNetlifyPattern segs)

-- | Convert a route segment to a Netlify redirect pattern.
segToNetlifyPattern :: RouteSegment -> Text
segToNetlifyPattern (StaticSegment t) = "/" <> t
segToNetlifyPattern (DynamicSegment _) = "/:splat"
segToNetlifyPattern (CatchAll _) = "/*"

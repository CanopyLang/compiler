{-# LANGUAGE OverloadedStrings #-}

-- | Vercel deployment adapter for CanopyKit.
--
-- Generates a @vercel.json@ configuration with appropriate rewrites
-- for client-side routing and optional serverless functions for
-- SSR routes.
--
-- @since 0.20.1
module Kit.Deploy.Vercel
  ( deployVercel
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Kit.Route.Types (RouteManifest)
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath

-- | Generate Vercel deployment configuration.
--
-- Creates @vercel.json@ in the output directory with build settings
-- and rewrite rules for SPA routing.
--
-- @since 0.20.1
deployVercel :: FilePath -> RouteManifest -> IO ()
deployVercel outputDir _manifest = do
  Dir.createDirectoryIfMissing True outputDir
  TextIO.writeFile configPath generateVercelJson
  where
    configPath = outputDir FilePath.</> "vercel.json"

-- | Generate the vercel.json configuration.
generateVercelJson :: Text.Text
generateVercelJson =
  Text.unlines
    [ "{"
    , "  \"buildCommand\": \"canopy kit-build --optimize\","
    , "  \"outputDirectory\": \"build\","
    , "  \"rewrites\": ["
    , "    { \"source\": \"/(.*)\", \"destination\": \"/index.html\" }"
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

{-# LANGUAGE OverloadedStrings #-}

-- | Netlify deployment adapter for CanopyKit.
--
-- Generates a @netlify.toml@ configuration with build settings
-- and redirect rules for SPA routing.
--
-- @since 0.20.1
module Kit.Deploy.Netlify
  ( deployNetlify
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Kit.Route.Types (RouteManifest)
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath

-- | Generate Netlify deployment configuration.
--
-- Creates @netlify.toml@ in the output directory with build settings
-- and redirect rules for SPA client-side routing.
--
-- @since 0.20.1
deployNetlify :: FilePath -> RouteManifest -> IO ()
deployNetlify outputDir _manifest = do
  Dir.createDirectoryIfMissing True outputDir
  TextIO.writeFile configPath generateNetlifyToml
  where
    configPath = outputDir FilePath.</> "netlify.toml"

-- | Generate the netlify.toml configuration.
generateNetlifyToml :: Text.Text
generateNetlifyToml =
  Text.unlines
    [ "[build]"
    , "  command = \"canopy kit-build --optimize\""
    , "  publish = \"build\""
    , ""
    , "[[redirects]]"
    , "  from = \"/*\""
    , "  to = \"/index.html\""
    , "  status = 200"
    , ""
    , "[[headers]]"
    , "  for = \"/assets/*\""
    , "  [headers.values]"
    , "    Cache-Control = \"public, max-age=31536000, immutable\""
    ]

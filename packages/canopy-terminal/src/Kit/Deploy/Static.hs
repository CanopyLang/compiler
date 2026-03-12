{-# LANGUAGE OverloadedStrings #-}

-- | Static deployment adapter for CanopyKit.
--
-- Produces a fully static site in the build directory. All pages are
-- pre-rendered at build time. This is the default build target.
--
-- @since 0.20.1
module Kit.Deploy.Static
  ( deployStatic
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Kit.Route.Types (RouteManifest)
import qualified Kit.SSG as SSG
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath

-- | Generate a static site from the route manifest.
--
-- Writes pre-rendered HTML files for every route into the output
-- directory. Each route gets its own @index.html@ for clean URLs.
--
-- @since 0.20.1
deployStatic :: FilePath -> RouteManifest -> IO ()
deployStatic outputDir manifest = do
  Dir.createDirectoryIfMissing True outputDir
  let pages = SSG.generateStaticPages manifest
  _ <- Map.traverseWithKey (writePage outputDir) pages
  pure ()

-- | Write a single pre-rendered page to disk.
writePage :: FilePath -> FilePath -> Text.Text -> IO ()
writePage outputDir path content = do
  let fullPath = outputDir FilePath.</> path
  Dir.createDirectoryIfMissing True (FilePath.takeDirectory fullPath)
  TextIO.writeFile fullPath content

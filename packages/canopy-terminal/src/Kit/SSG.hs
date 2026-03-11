{-# LANGUAGE OverloadedStrings #-}

-- | Static site generation for Kit applications.
--
-- Pre-renders static pages (those with no dynamic route segments) into
-- HTML shells suitable for serving as the initial page load. Each shell
-- includes the @DOCTYPE@, a basic HTML structure, a script tag that loads
-- the compiled JavaScript entry point, and a meta-tags placeholder.
--
-- @since 0.19.2
module Kit.SSG
  ( generateStaticPages
  ) where

import Control.Lens ((^.))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Kit.Route.Types
  ( PageKind (..)
  , RouteEntry (..)
  , RouteManifest (..)
  , RouteSegment (..)
  , rePageKind
  , rePattern
  )
import qualified Kit.Route.Types as Route

-- | Generate HTML shells for every static route in the manifest.
--
-- Dynamic routes (those containing 'DynamicSegment' or 'CatchAll' segments)
-- are skipped because their content depends on runtime parameters.
--
-- Returns a 'Map' from output file paths (relative to the build directory)
-- to the rendered HTML content.
--
-- @since 0.19.2
generateStaticPages :: RouteManifest -> Map.Map FilePath Text
generateStaticPages manifest =
  Map.fromList (fmap toEntry staticRoutes)
  where
    staticRoutes = filter isStaticRoute (Route._rmRoutes manifest)
    toEntry route = (routeToFilePath route, renderHtmlShell route)

-- | Determine whether a route entry is fully static.
isStaticRoute :: RouteEntry -> Bool
isStaticRoute route =
  route ^. rePageKind == StaticPage && allSegmentsStatic (route ^. rePattern)

-- | Check that every segment in a route pattern is a 'StaticSegment'.
allSegmentsStatic :: Route.RoutePattern -> Bool
allSegmentsStatic pattern =
  all isStatic (Route._rpSegments pattern)
  where
    isStatic (StaticSegment _) = True
    isStatic (DynamicSegment _) = False
    isStatic (CatchAll _) = False

-- | Convert a route entry to an output file path.
routeToFilePath :: RouteEntry -> FilePath
routeToFilePath route =
  Text.unpack (Text.intercalate "/" segments) ++ "/index.html"
  where
    segments = fmap segmentText (Route._rpSegments (route ^. rePattern))

-- | Extract the text content from a static route segment.
segmentText :: RouteSegment -> Text
segmentText (StaticSegment t) = t
segmentText (DynamicSegment t) = t
segmentText (CatchAll t) = t

-- | Render a complete HTML shell document for a static page.
renderHtmlShell :: RouteEntry -> Text
renderHtmlShell route =
  Text.unlines
    [ "<!DOCTYPE html>"
    , "<html lang=\"en\">"
    , renderHead route
    , renderBody route
    , "</html>"
    ]

-- | Render the @<head>@ section with meta tags and title placeholder.
renderHead :: RouteEntry -> Text
renderHead route =
  Text.unlines
    [ "  <head>"
    , "    <meta charset=\"utf-8\" />"
    , "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />"
    , "    <title>" <> Route._reModuleName route <> "</title>"
    , "  </head>"
    ]

-- | Render the @<body>@ section with the application mount and script tag.
renderBody :: RouteEntry -> Text
renderBody _route =
  Text.unlines
    [ "  <body>"
    , "    <div id=\"app\"></div>"
    , "    <script type=\"module\" src=\"/main.js\"></script>"
    , "  </body>"
    ]

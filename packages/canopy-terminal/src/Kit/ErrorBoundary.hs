{-# LANGUAGE OverloadedStrings #-}

-- | Error boundary resolution for Kit route hierarchies.
--
-- Recognizes @error.can@ files in route directories and maps route
-- prefixes to their error boundary modules. At runtime, when a page
-- produces an error, the framework renders the nearest error boundary
-- in the route hierarchy instead of the page itself.
--
-- @since 0.19.2
module Kit.ErrorBoundary
  ( resolveErrorBoundaries
  ) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Kit.Route.Types
  ( LayoutEntry (..)
  , RouteManifest (..)
  , RouteSegment (..)
  )
import qualified Kit.Route.Types as Route

-- | Build a map from route prefixes to error boundary module names.
--
-- Each entry in the manifest's error boundary list produces a key
-- derived from its route segment prefix (e.g. @"users"@) and a
-- value that is the Canopy module name derived from the file path
-- (e.g. @"Routes.Users.Error"@).
--
-- @since 0.19.2
resolveErrorBoundaries :: RouteManifest -> Map.Map Text Text
resolveErrorBoundaries manifest =
  Map.fromList (fmap toBoundaryPair boundaries)
  where
    boundaries = Route._rmErrorBoundaries manifest
    toBoundaryPair entry = (prefixToKey entry, pathToModuleName entry)

-- | Convert the route prefix segments of a layout entry to a map key.
prefixToKey :: LayoutEntry -> Text
prefixToKey entry =
  Text.intercalate "/" (fmap segmentToText (Route._lePrefix entry))

-- | Extract the text label from a route segment.
segmentToText :: RouteSegment -> Text
segmentToText (StaticSegment t) = t
segmentToText (DynamicSegment t) = "[" <> t <> "]"
segmentToText (CatchAll t) = "[..." <> t <> "]"

-- | Derive a Canopy module name from the layout entry's file path.
--
-- Strips the @src/@ prefix and @.can@ suffix, splits on @/@, and
-- capitalizes each segment to produce a dotted module name.
pathToModuleName :: LayoutEntry -> Text
pathToModuleName entry =
  Text.intercalate "." (fmap capitalize segments)
  where
    raw = Text.pack (Route._leModulePath entry)
    stripped = stripSrcPrefix (stripCanSuffix raw)
    segments = filter (not . Text.null) (Text.splitOn "/" stripped)

-- | Strip a leading @src/@ prefix from a path.
stripSrcPrefix :: Text -> Text
stripSrcPrefix path =
  maybe path id (Text.stripPrefix "src/" path)

-- | Strip a trailing @.can@ suffix from a path.
stripCanSuffix :: Text -> Text
stripCanSuffix path =
  maybe path id (Text.stripSuffix ".can" path)

-- | Capitalize the first character of a text value.
capitalize :: Text -> Text
capitalize t =
  maybe t (\(c, rest) -> Text.cons (toUpperChar c) rest) (Text.uncons t)

-- | Convert a character to uppercase if it is a lowercase ASCII letter.
toUpperChar :: Char -> Char
toUpperChar c
  | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
  | otherwise = c

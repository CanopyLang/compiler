{-# LANGUAGE OverloadedStrings #-}

-- | Kit.Route.Generate -- Canopy source code generation for routes.
--
-- Generates a @Routes.can@ module from a validated 'RouteManifest'.
-- The generated module exposes:
--
-- * A @Route@ custom type with one variant per discovered route.
-- * An @href@ function that converts a @Route@ value to a URL string.
-- * A @parser@ that matches URL path segments to @Route@ values.
--
-- The output is valid Canopy source text that can be written to disk
-- and compiled as part of the application.
--
-- @since 0.19.2
module Kit.Route.Generate
  ( generateRoutesModule
  ) where

import Control.Lens ((^.))
import Data.Text (Text)
import qualified Data.Text as Text
import Kit.Route.Types
  ( RouteEntry
  , RouteManifest (..)
  , RouteSegment (..)
  , reModuleName
  , rePattern
  , rpSegments
  )

-- | Generate a complete @Routes.can@ module from a manifest.
--
-- The generated module includes lazy imports for each route page module
-- to enable automatic code splitting per route. Each page is loaded
-- on demand when the user navigates to that route.
--
-- @since 0.19.2
generateRoutesModule :: RouteManifest -> Text
generateRoutesModule manifest =
  Text.intercalate "\n\n" sections
  where
    routes = _rmRoutes manifest
    sections =
      [ generateModuleHeader
      , generateLazyImports routes
      , generateRouteType routes
      , generateHref routes
      , generateParser routes
      ]

-- | Emit @lazy import@ declarations for each route page module.
--
-- Produces one @lazy import Pages.Dashboard@ line per route,
-- which enables code splitting: each page module is loaded on demand
-- when the user navigates to that route.
--
-- @since 0.20.1
generateLazyImports :: [RouteEntry] -> Text
generateLazyImports routes =
  Text.intercalate "\n" (fmap lazyImportLine routes)

-- | Emit a single lazy import line for a route entry.
lazyImportLine :: RouteEntry -> Text
lazyImportLine entry =
  "lazy import " <> (entry ^. reModuleName)

-- | Emit the module declaration and exposing list.
generateModuleHeader :: Text
generateModuleHeader =
  "module Routes exposing (Route(..), href, parser)"

-- | Emit the @Route@ custom type with one variant per route.
generateRouteType :: [RouteEntry] -> Text
generateRouteType routes =
  Text.intercalate "\n" ("type Route" : variantLines)
  where
    variantLines = zipWith prefixVariant prefixes (fmap routeVariant routes)
    prefixes = "    = " : repeat "    | "

-- | Attach the union prefix (@=@ or @|@) to a variant line.
prefixVariant :: Text -> Text -> Text
prefixVariant prefix variant = prefix <> variant

-- | Build the variant name and parameter types for a single route.
routeVariant :: RouteEntry -> Text
routeVariant entry =
  appendParams variantName params
  where
    segs = entry ^. rePattern . rpSegments
    variantName = segmentsToVariantName segs
    params = dynamicParamTypes segs

-- | Append @String@ type parameters to a variant name.
appendParams :: Text -> [Text] -> Text
appendParams name [] = name
appendParams name ps = name <> " " <> Text.intercalate " " ps

-- | Extract @String@ type annotations for dynamic segments.
dynamicParamTypes :: [RouteSegment] -> [Text]
dynamicParamTypes = concatMap segmentParamType

-- | Yield @[\"String\"]@ for dynamic segments, @[]@ for static.
segmentParamType :: RouteSegment -> [Text]
segmentParamType (DynamicSegment _) = ["String"]
segmentParamType (CatchAll _) = ["String"]
segmentParamType (StaticSegment _) = []

-- | Emit the @href@ function mapping routes to URL strings.
generateHref :: [RouteEntry] -> Text
generateHref routes =
  Text.intercalate "\n" (header <> caseArms)
  where
    header =
      [ "href : Route -> String"
      , "href route ="
      , "    case route of"
      ]
    caseArms = fmap (hrefArm . (^. rePattern . rpSegments)) routes

-- | Build one @case@ arm for the @href@ function.
hrefArm :: [RouteSegment] -> Text
hrefArm segs =
  "        " <> pattern_ <> " -> " <> urlExpr
  where
    pattern_ = hrefPattern segs
    urlExpr = hrefUrl segs

-- | Build the pattern side of an href case arm.
hrefPattern :: [RouteSegment] -> Text
hrefPattern segs =
  appendParams (segmentsToVariantName segs) (dynamicParamNames segs)

-- | Extract lowercase parameter variable names from dynamic segments.
dynamicParamNames :: [RouteSegment] -> [Text]
dynamicParamNames = concatMap segmentParamName

-- | Yield the parameter name for dynamic segments.
segmentParamName :: RouteSegment -> [Text]
segmentParamName (DynamicSegment name) = [name]
segmentParamName (CatchAll name) = [name]
segmentParamName (StaticSegment _) = []

-- | Build the URL string expression for an href case arm.
hrefUrl :: [RouteSegment] -> Text
hrefUrl [] = "\"/\""
hrefUrl segs =
  wrapConcat (fmap segmentToUrlPart segs)

-- | Convert a segment to its URL string contribution.
segmentToUrlPart :: RouteSegment -> Text
segmentToUrlPart (StaticSegment t) = "\"/" <> t <> "\""
segmentToUrlPart (DynamicSegment name) = "\"/\" ++ " <> name
segmentToUrlPart (CatchAll name) = "\"/\" ++ " <> name

-- | Join URL parts with @++@ concatenation.
wrapConcat :: [Text] -> Text
wrapConcat [] = "\"/\""
wrapConcat parts = Text.intercalate " ++ " parts

-- | Emit the @parser@ function matching URL segments to routes.
generateParser :: [RouteEntry] -> Text
generateParser routes =
  Text.intercalate "\n" (header <> caseArms <> [fallthrough])
  where
    header =
      [ "parser : List String -> Maybe Route"
      , "parser segments ="
      , "    case segments of"
      ]
    caseArms = fmap (parserArm . (^. rePattern . rpSegments)) routes
    fallthrough = "        _ -> Nothing"

-- | Build one @case@ arm for the @parser@ function.
parserArm :: [RouteSegment] -> Text
parserArm segs =
  "        " <> listPattern <> " -> Just " <> constructor
  where
    listPattern = parserListPattern segs
    constructor = parserConstructor segs

-- | Build the list pattern for matching URL segments.
parserListPattern :: [RouteSegment] -> Text
parserListPattern [] = "[]"
parserListPattern segs =
  "[ " <> Text.intercalate ", " (fmap segmentMatchExpr segs) <> " ]"

-- | Build the match expression for a single segment in a list pattern.
segmentMatchExpr :: RouteSegment -> Text
segmentMatchExpr (StaticSegment t) = "\"" <> t <> "\""
segmentMatchExpr (DynamicSegment name) = name
segmentMatchExpr (CatchAll name) = name

-- | Build the constructor expression for the result of a parser arm.
parserConstructor :: [RouteSegment] -> Text
parserConstructor segs =
  appendParams (segmentsToVariantName segs) (dynamicParamNames segs)

-- | Convert a list of route segments to a PascalCase variant name.
--
-- An empty segment list produces @Home@. Static segments are
-- capitalised and concatenated. Dynamic segments contribute their
-- capitalised parameter name.
--
-- @since 0.19.2
segmentsToVariantName :: [RouteSegment] -> Text
segmentsToVariantName [] = "Home"
segmentsToVariantName segs =
  Text.concat (fmap segmentToVariantPart segs)

-- | Convert one segment to its variant name contribution.
segmentToVariantPart :: RouteSegment -> Text
segmentToVariantPart (StaticSegment t) = capitalise t
segmentToVariantPart (DynamicSegment t) = capitalise t
segmentToVariantPart (CatchAll t) = capitalise t

-- | Capitalise the first character of a text value.
capitalise :: Text -> Text
capitalise t =
  maybe t applyUpper (Text.uncons t)
  where
    applyUpper (c, rest) = Text.cons (toUpper c) rest
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise = c

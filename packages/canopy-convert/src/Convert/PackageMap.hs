{-# LANGUAGE OverloadedStrings #-}

-- | Single source of truth for elm/* to canopy/* package name mappings.
--
-- This module defines the authoritative mapping table used by both the
-- @migrate@ command (source-level transforms) and the @convert@ command
-- (package-level transforms). All elm stdlib packages that have been
-- manually ported to Canopy are listed here.
--
-- Community packages (non-elm/* namespaced) do not need entries here —
-- they keep their original author/project names. Only the elm/* stdlib
-- dependencies referenced in their elm.json files get remapped.
--
-- @since 0.19.2
module Convert.PackageMap
  ( -- * Package Mappings
    elmToCanopyPackages,
    elmToCanopyJsonReplacements,
    elmToCanopyLazyReplacements,

    -- * Lookup
    remapPackageName,
  )
where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE

-- | Authoritative mapping from elm package names to canopy equivalents.
--
-- Only includes elm-namespaced stdlib packages that have been manually
-- ported. Community packages keep their original names.
--
-- @since 0.19.2
elmToCanopyPackages :: Map Text Text
elmToCanopyPackages =
  Map.fromList
    [ ("elm/core", "canopy/core"),
      ("elm/json", "canopy/json"),
      ("elm/html", "canopy/html"),
      ("elm/browser", "canopy/browser"),
      ("elm/http", "canopy/http"),
      ("elm/url", "canopy/url"),
      ("elm/time", "canopy/time"),
      ("elm/virtual-dom", "canopy/virtual-dom"),
      ("elm/random", "canopy/random"),
      ("elm/bytes", "canopy/bytes"),
      ("elm/file", "canopy/file"),
      ("elm/parser", "canopy/parser"),
      ("elm/regex", "canopy/regex"),
      ("elm/svg", "canopy/svg"),
      ("elm/project-metadata-utils", "canopy/project-metadata-utils")
    ]

-- | Remap a package name from elm to canopy namespace if it exists in the map.
--
-- Community packages (not in the map) are returned unchanged.
--
-- >>> remapPackageName "elm/core"
-- "canopy/core"
--
-- >>> remapPackageName "elm-community/list-extra"
-- "elm-community/list-extra"
--
-- @since 0.19.2
remapPackageName :: Text -> Text
remapPackageName name =
  Map.findWithDefault name name elmToCanopyPackages

-- | JSON-level replacements for converting elm.json to canopy.json.
--
-- Includes both package name remappings and field name changes
-- (e.g. @elm-version@ to @canopy-version@). Values are strict
-- 'BS.ByteString' pairs for use with strict byte replacement.
--
-- @since 0.19.2
elmToCanopyJsonReplacements :: [(BS.ByteString, BS.ByteString)]
elmToCanopyJsonReplacements =
  fieldReplacements ++ packageReplacements
  where
    fieldReplacements =
      [ ("\"elm-version\"", "\"canopy-version\""),
        ("\"elm-explorations\"", "\"canopy-explorations\""),
        ("\"elm-stuff\"", "\".canopy-stuff\"")
      ]
    packageReplacements =
      fmap toStrictPair (Map.toList elmToCanopyPackages)
    toStrictPair (from, to) =
      (TE.encodeUtf8 (quote from), TE.encodeUtf8 (quote to))
    quote t = "\"" <> t <> "\""

-- | Lazy 'LBS.ByteString' version of 'elmToCanopyJsonReplacements'.
--
-- Provided for backwards compatibility with 'Migrate.jsonReplacements'.
--
-- @since 0.19.2
elmToCanopyLazyReplacements :: [(LBS.ByteString, LBS.ByteString)]
elmToCanopyLazyReplacements =
  fmap toLazy elmToCanopyJsonReplacements
  where
    toLazy (a, b) = (LBS.fromStrict a, LBS.fromStrict b)


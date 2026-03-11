{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Kit.Route.Types -- Core types for file-system route scanning.
--
-- Defines the data structures that represent the result of scanning a
-- @src\/routes\/@ directory tree: individual route segments, full route
-- patterns, page classifications, layout bindings, error boundaries,
-- and the aggregate 'RouteManifest'.
--
-- These types flow through the scanning, validation, and code-generation
-- pipeline:
--
--   1. 'Kit.Route.Scanner' produces a 'RouteManifest' from disk.
--   2. 'Kit.Route.Validate' checks the manifest for conflicts.
--   3. 'Kit.Route.Generate' emits a @Routes.can@ source module.
--   4. 'Kit.Route.ClientNav' emits a JavaScript navigation runtime.
--
-- @since 0.19.2
module Kit.Route.Types
  ( RouteSegment (..)
  , RoutePattern (..)
  , RouteManifest (..)
  , LayoutEntry (..)
  , PageKind (..)
  , RouteEntry (..)
  , ScanError (..)
  , ValidationError (..)
    -- * Lenses
  , rpSegments
  , rpFilePath
  , rmRoutes
  , rmLayouts
  , rmErrorBoundaries
  , lePrefix
  , leModulePath
  , rePattern
  , rePageKind
  , reSourceFile
  , reModuleName
  ) where

import Control.Lens (makeLenses)
import Data.Text (Text)

-- | A single segment within a URL route pattern.
--
-- Route segments are parsed from directory names in the @src\/routes\/@ tree:
--
-- * Plain directory names become 'StaticSegment' values.
-- * Names wrapped in square brackets (@[param]@) become 'DynamicSegment' values.
-- * Names wrapped in @[...name]@ become 'CatchAll' values that match
--   one or more trailing path components.
--
-- @since 0.19.2
data RouteSegment
  = StaticSegment !Text
    -- ^ Literal URL segment, e.g. @"about"@ for @\/about@.
  | DynamicSegment !Text
    -- ^ Named parameter, e.g. @"id"@ for @\/users\/[id]@.
  | CatchAll !Text
    -- ^ Catch-all parameter, e.g. @"rest"@ for @\/docs\/[...rest]@.
  deriving (Eq, Ord, Show)

-- | A complete route pattern built from one or more segments.
--
-- Preserves the original file path so that error messages and code
-- generation can reference the source location on disk.
--
-- @since 0.19.2
data RoutePattern = RoutePattern
  { _rpSegments :: ![RouteSegment]
    -- ^ Ordered segments from root to leaf.
  , _rpFilePath :: !FilePath
    -- ^ Absolute path to the @page.can@ file that defines this route.
  } deriving (Eq, Ord, Show)

-- | Classification of a route page.
--
-- Determines how the route is rendered and what lifecycle hooks are
-- available to the page module:
--
-- * 'StaticPage' -- pre-rendered at build time with no dynamic data.
-- * 'DynamicPage' -- rendered at request time; may depend on route params.
-- * 'ApiRoute' -- returns JSON instead of HTML; no view function required.
--
-- @since 0.19.2
data PageKind
  = StaticPage
  | DynamicPage
  | ApiRoute
  deriving (Eq, Ord, Show)

-- | A single route discovered during directory scanning.
--
-- Combines the parsed 'RoutePattern' with metadata needed for code
-- generation: the page classification, the original source file, and the
-- Canopy module name derived from the file path.
--
-- @since 0.19.2
data RouteEntry = RouteEntry
  { _rePattern :: !RoutePattern
    -- ^ Parsed URL pattern for this route.
  , _rePageKind :: !PageKind
    -- ^ Whether this is a static page, dynamic page, or API route.
  , _reSourceFile :: !FilePath
    -- ^ Absolute path to the @page.can@ source file.
  , _reModuleName :: !Text
    -- ^ Canopy module name (e.g. @"Routes.Users.Id"@).
  } deriving (Eq, Ord, Show)

-- | Association between a route prefix and a layout module.
--
-- Layout entries are discovered by finding @layout.can@ files in the
-- routes directory tree. Every route whose pattern starts with the
-- layout's prefix is wrapped in that layout during rendering.
--
-- @since 0.19.2
data LayoutEntry = LayoutEntry
  { _lePrefix :: ![RouteSegment]
    -- ^ Route prefix this layout applies to.
  , _leModulePath :: !FilePath
    -- ^ Absolute path to the @layout.can@ module.
  } deriving (Eq, Ord, Show)

-- | Aggregate result of scanning the @src\/routes\/@ directory.
--
-- Contains every route, layout, and error boundary discovered during
-- the scan. This structure is the input to both validation
-- ('Kit.Route.Validate') and code generation ('Kit.Route.Generate',
-- 'Kit.Route.ClientNav').
--
-- @since 0.19.2
data RouteManifest = RouteManifest
  { _rmRoutes :: ![RouteEntry]
    -- ^ All discovered page routes.
  , _rmLayouts :: ![LayoutEntry]
    -- ^ All discovered layout modules.
  , _rmErrorBoundaries :: ![LayoutEntry]
    -- ^ All discovered @error.can@ boundaries (same shape as layouts).
  } deriving (Eq, Show)

-- | Errors that can occur while scanning the filesystem.
--
-- These represent IO-level failures or malformed directory names that
-- prevent the scanner from producing a valid 'RouteManifest'.
--
-- @since 0.19.2
data ScanError
  = DirectoryNotFound !FilePath
    -- ^ The @src\/routes\/@ directory does not exist.
  | InvalidSegmentName !FilePath !Text
    -- ^ A directory name could not be parsed as a valid route segment.
    --   Carries the directory path and the offending name.
  | IOScanError !FilePath !Text
    -- ^ An IO error occurred while reading the given path.
  deriving (Eq, Show)

-- | Errors detected during manifest validation.
--
-- These represent logical conflicts between routes that would produce
-- ambiguous URL matching at runtime.
--
-- @since 0.19.2
data ValidationError
  = DuplicateRoute !RoutePattern !RoutePattern
    -- ^ Two routes resolve to the same URL pattern.
  | ConflictingDynamicSegments !Text ![RoutePattern]
    -- ^ Multiple dynamic parameter names at the same path level.
  | EmptyRoutesDirectory
    -- ^ The routes directory exists but contains no page files.
  deriving (Eq, Show)

makeLenses ''RoutePattern
makeLenses ''RouteEntry
makeLenses ''LayoutEntry
makeLenses ''RouteManifest

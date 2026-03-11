{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Data loader detection and code generation for CanopyKit.
--
-- Scans route modules for @load@ function exports and generates
-- a unified @Loaders.can@ module that wires loader output into
-- page init functions.
--
-- Loaders come in two variants:
--
--   * 'StaticLoader': Runs at build time, output is serialized to JSON
--   * 'DynamicLoader': Runs at request time via fetch calls
--
-- In dev mode, all loaders are forced to 'DynamicLoader' for instant feedback.
--
-- @since 0.19.2
module Kit.DataLoader
  ( -- * Types
    DataLoader (..)
  , LoaderKind (..)

    -- * Lenses
  , dlRoute
  , dlKind
  , dlModuleName

    -- * Detection
  , detectLoaders

    -- * Code Generation
  , generateLoaderModule
  ) where

import Control.Lens (makeLenses, (^.))
import Data.Text (Text)
import qualified Data.Text as Text
import Kit.Route.Types (RouteEntry)
import qualified Kit.Route.Types as Route


-- | Kind of data loader.
data LoaderKind
  = StaticLoader
    -- ^ Runs at build time; output serialized to JSON.
  | DynamicLoader
    -- ^ Runs at request time via fetch call.
  deriving (Eq, Show)


-- | A detected data loader for a route module.
data DataLoader = DataLoader
  { _dlRoute :: !RouteEntry
    -- ^ The route this loader is associated with.
  , _dlKind :: !LoaderKind
    -- ^ Whether to run statically or dynamically.
  , _dlModuleName :: !Text
    -- ^ Fully qualified module name containing the @load@ function.
  } deriving (Show)

makeLenses ''DataLoader


-- | Detect data loaders from route entries.
--
-- Scans each route's module for a @load@ function export.
-- Currently returns an empty list as loader detection requires
-- parsing module exports, which will be integrated with the
-- route scanner in a future release.
--
-- @since 0.19.2
detectLoaders :: [RouteEntry] -> IO [DataLoader]
detectLoaders _routes = pure []


-- | Generate a @Loaders.can@ module from detected loaders.
--
-- Produces a Canopy module that imports each loader's module and
-- exposes a unified @loaders@ dictionary mapping route patterns
-- to their loader functions.
--
-- When no loaders are detected, generates a module with an empty
-- @loaders@ value.
--
-- @since 0.19.2
generateLoaderModule :: [DataLoader] -> Text
generateLoaderModule [] = emptyLoaderModule
generateLoaderModule loaders =
  Text.unlines
    [ "module Loaders exposing (loaders)"
    , ""
    , Text.unlines (fmap generateImport loaders)
    , ""
    , "loaders ="
    , "  [ " <> Text.intercalate "\n  , " (fmap generateEntry loaders)
    , "  ]"
    ]
  where
    generateImport loader =
      "import " <> (loader ^. dlModuleName)

    generateEntry loader =
      "{ route = \"" <> routePattern loader <> "\""
      <> ", load = " <> (loader ^. dlModuleName) <> ".load"
      <> " }"

    routePattern loader =
      Route._reModuleName (loader ^. dlRoute)


-- | Module content when no loaders are found.
emptyLoaderModule :: Text
emptyLoaderModule =
  Text.unlines
    [ "module Loaders exposing (loaders)"
    , ""
    , ""
    , "loaders ="
    , "  []"
    ]

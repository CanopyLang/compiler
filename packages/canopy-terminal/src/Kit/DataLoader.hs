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
  , detectLoadersDev

    -- * Code Generation
  , generateLoaderModule
  ) where

import Control.Lens (makeLenses, (^.))
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Kit.Route.Types (RouteEntry)
import qualified Kit.Route.Types as Route
import qualified System.Directory as Dir


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


-- | Detect data loaders from route entries (production mode).
--
-- Scans each route's source file for a @load@ function definition.
-- Classifies as 'StaticLoader' if the return type is pure, or
-- 'DynamicLoader' if it returns a Task.
--
-- @since 0.20.1
detectLoaders :: [RouteEntry] -> IO [DataLoader]
detectLoaders routes = do
  results <- traverse (detectOneLoader False) routes
  pure (mapMaybe id results)

-- | Detect data loaders in dev mode (all forced to DynamicLoader).
--
-- In development, all loaders are treated as dynamic for instant
-- feedback without requiring a full rebuild.
--
-- @since 0.20.1
detectLoadersDev :: [RouteEntry] -> IO [DataLoader]
detectLoadersDev routes = do
  results <- traverse (detectOneLoader True) routes
  pure (mapMaybe id results)

-- | Check a single route entry for a load function.
detectOneLoader :: Bool -> RouteEntry -> IO (Maybe DataLoader)
detectOneLoader forceDynamic entry = do
  let srcFile = Route._reSourceFile entry
  exists <- Dir.doesFileExist srcFile
  if exists
    then detectFromSource forceDynamic entry srcFile
    else pure Nothing

-- | Parse source file to detect a load function export.
detectFromSource :: Bool -> RouteEntry -> FilePath -> IO (Maybe DataLoader)
detectFromSource forceDynamic entry srcFile = do
  content <- Text.IO.readFile srcFile
  pure (buildLoader forceDynamic entry content)

-- | Build a DataLoader if the source exports a load function.
buildLoader :: Bool -> RouteEntry -> Text -> Maybe DataLoader
buildLoader forceDynamic entry content
  | not (hasLoadFunction content) = Nothing
  | otherwise = Just DataLoader
      { _dlRoute = entry
      , _dlKind = classifyLoader forceDynamic content
      , _dlModuleName = Route._reModuleName entry
      }

-- | Check if source content defines a load function.
hasLoadFunction :: Text -> Bool
hasLoadFunction content =
  any isLoadDefinition (Text.lines content)

-- | Check if a line is a load function definition.
isLoadDefinition :: Text -> Bool
isLoadDefinition line =
  Text.isPrefixOf "load " stripped || Text.isPrefixOf "load :" stripped
  where
    stripped = Text.stripStart line

-- | Classify whether a loader is static or dynamic.
classifyLoader :: Bool -> Text -> LoaderKind
classifyLoader True _ = DynamicLoader
classifyLoader False content
  | hasTaskReturn content = DynamicLoader
  | otherwise = StaticLoader

-- | Check if the load function's type signature returns a Task.
hasTaskReturn :: Text -> Bool
hasTaskReturn content =
  "Task" `Text.isInfixOf` joinedSignature
  where
    joinedSignature = Text.unwords (findLoadSignature content)

-- | Find all lines that are part of the load type signature.
--
-- After finding the @load :@ annotation line, collects continuation
-- lines (indented lines that are not new definitions) until the next
-- unindented line or definition.
findLoadSignature :: Text -> [Text]
findLoadSignature content =
  case dropWhile (not . isLoadTypeAnnotation) (Text.lines content) of
    [] -> []
    (sig : rest) -> sig : takeWhile isContinuation rest

-- | Check if a line is the load function's type annotation.
isLoadTypeAnnotation :: Text -> Bool
isLoadTypeAnnotation line =
  Text.isPrefixOf "load :" (Text.stripStart line)

-- | Check if a line is a continuation of a multi-line type signature.
--
-- A continuation line is indented (starts with whitespace) and is not
-- a new definition (does not start with an identifier at column 0).
isContinuation :: Text -> Bool
isContinuation line
  | Text.null line = False
  | Text.null (Text.stripStart line) = False
  | otherwise = Text.head line == ' ' || Text.head line == '\t'


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

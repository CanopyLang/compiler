{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | File watcher integration with the query engine.
--
-- Bridges the file system watcher ('Watch.files') with the query engine's
-- invalidation system ('Engine.invalidateAndPropagate'). When a watched
-- source file changes, this module computes its new content hash and
-- invalidates the corresponding 'ParseModuleQuery', triggering cascading
-- invalidation of all dependent queries (canonicalize, type-check,
-- optimize, generate).
--
-- == Usage
--
-- @
-- engine <- Engine.initEngine
-- let handler = createInvalidationHandler engine Parse.Application
-- Watch.files handler [\"src\/Main.can\", \"src\/Utils.can\"]
-- @
--
-- @since 0.20.0
module Watch.QueryIntegration
  ( createInvalidationHandler,
  )
where

import qualified Control.Exception as Exception
import qualified Data.ByteString as BS
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified Parse.Module as Parse
import Query.Engine (QueryEngine)
import qualified Query.Engine as Engine
import Query.Simple (ContentHash, Query (..))
import qualified Query.Simple as Query
import System.FSNotify (Event)
import qualified System.FSNotify as FSNotify

-- | Create a file change handler that invalidates queries on change.
--
-- When a watched file changes, computes its new content hash and
-- invalidates the corresponding 'ParseModuleQuery' in the engine,
-- triggering cascading invalidation of dependent queries.
--
-- File read errors are caught and logged rather than propagated,
-- since the watcher must continue operating after transient failures
-- (e.g., the file is briefly locked during an editor save).
--
-- @since 0.20.0
createInvalidationHandler ::
  -- | Query engine to invalidate entries in
  QueryEngine ->
  -- | Project type for constructing parse queries
  Parse.ProjectType ->
  -- | Event handler suitable for 'Watch.files'
  (Event -> IO ())
createInvalidationHandler engine projectType event =
  Exception.catch
    (invalidateForEvent engine projectType path)
    (logReadError path)
  where
    path = FSNotify.eventPath event

-- | Invalidate the parse query for a changed file.
--
-- Reads the file, computes a SHA256 content hash, constructs the
-- appropriate 'ParseModuleQuery', and delegates to
-- 'Engine.invalidateAndPropagate' for cascading invalidation.
--
-- @since 0.20.0
invalidateForEvent ::
  QueryEngine ->
  Parse.ProjectType ->
  FilePath ->
  IO ()
invalidateForEvent engine projectType path = do
  Log.logEvent (BuildHashComputed path)
  contentHash <- computeFileHash path
  let query = buildParseQuery path contentHash projectType
  Engine.invalidateAndPropagate engine query

-- | Read a file and compute its SHA256 content hash.
--
-- @since 0.20.0
computeFileHash :: FilePath -> IO ContentHash
computeFileHash path =
  fmap Query.computeContentHash (BS.readFile path)

-- | Build a 'ParseModuleQuery' from file path, hash, and project type.
--
-- @since 0.20.0
buildParseQuery :: FilePath -> ContentHash -> Parse.ProjectType -> Query
buildParseQuery path hash projectType =
  ParseModuleQuery
    { parseFile = path,
      parseHash = hash,
      parseProjectType = projectType
    }

-- | Log a file read error without crashing the watcher.
--
-- @since 0.20.0
logReadError :: FilePath -> Exception.IOException -> IO ()
logReadError path ex =
  Log.logEvent (BuildFailed msg)
  where
    msg = "File read failed during invalidation: "
      <> Text.pack path
      <> " ("
      <> Text.pack (show ex)
      <> ")"

{-# LANGUAGE OverloadedStrings #-}

-- | Optimization query for the new compiler.
--
-- This module wraps the existing Optimize.Module.optimize function
-- in the query system, providing caching and debug logging.
--
-- @since 0.19.1
module Queries.Optimize
  ( optimizeModuleQuery,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import Control.Monad (when)
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.Text as Text
import Logging.Event (LogEvent (..), OptStats (..))
import qualified Logging.Logger as Log
import Query.Simple
import qualified Optimize.Module as Optimize
import qualified Reporting.Result as Result

-- | Optimize a canonical module to produce optimized AST.
--
-- This query wraps Optimize.Module.optimize with debug logging.
-- Takes canonical module and type annotations, returns optimized LocalGraph.
optimizeModuleQuery ::
  Map Name.Name Can.Annotation ->
  Can.Module ->
  IO (Either QueryError Opt.LocalGraph)
optimizeModuleQuery annotations canonModule@(Can.Module modName _ _ _ _ _ _ _ _) = do
  let modNameText = Text.pack (show modName)
  Log.logEvent (OptimizeStarted modNameText)

  case Result.run (Optimize.optimize annotations canonModule) of
    (_warnings, Left err) -> do
      Log.logEvent (OptimizeFailed modNameText (Text.pack (show err)))
      return (Left (OtherError ("Optimization error: " ++ show err)))
    (_warnings, Right localGraph@(Opt.LocalGraph _maybeMain nodes _fields _locs)) -> do
      let nodeCount = Map.size nodes
      Log.logEvent (OptimizeCompleted modNameText (OptStats nodeCount 0 0))
      enabled <- Log.isEnabled
      when enabled (emitOptTraceEvents modNameText localGraph)
      return (Right localGraph)

-- | Emit TRACE-level optimization events from the LocalGraph.
--
-- Analyzes the optimized graph to emit decision tree and branch
-- statistics without modifying the pure optimization pipeline.
emitOptTraceEvents :: Text.Text -> Opt.LocalGraph -> IO ()
emitOptTraceEvents modNameText (Opt.LocalGraph _main nodes _fields _locs) = do
  let nodeCount = Map.size nodes
  Log.logEvent (OptimizeDecisionTree modNameText nodeCount 0)

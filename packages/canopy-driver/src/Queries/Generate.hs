{-# LANGUAGE OverloadedStrings #-}

-- | Code generation query for the new compiler.
--
-- This module wraps the existing Generate.JavaScript.generate function
-- in the query system, providing caching and debug logging.
--
-- **CRITICAL FIX**: This module now builds a complete GlobalGraph that
-- includes ALL dependencies, not just the main modules. This fixes the
-- bug where generated JavaScript was missing dependency code.
--
-- @since 0.19.1
module Queries.Generate
  ( generateJavaScriptQuery,
    buildCompleteGlobalGraph,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import Data.ByteString.Builder (Builder)
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Generate.JavaScript as JS
import qualified Generate.Mode as Mode
import qualified Data.Text as Text
import Logging.Event (LogEvent (..), GenStats (..))
import qualified Logging.Logger as Log
import Query.Simple

-- | Generate JavaScript code from optimized AST.
--
-- This query wraps Generate.JavaScript.generate with debug logging.
-- Takes mode, global graph, mains, and FFI info, returns JavaScript Builder.
generateJavaScriptQuery ::
  Mode.Mode ->
  Opt.GlobalGraph ->
  Map ModuleName.Canonical Opt.Main ->
  Map String JS.FFIInfo ->
  IO (Either QueryError Builder)
generateJavaScriptQuery mode globalGraph mains ffiInfos = do
  let modNameText = Text.pack ("js:" ++ show (Map.size mains) ++ " mains")
  Log.logEvent (GenerateStarted modNameText)

  let (jsBuilder, _sourceMap) = JS.generate mode globalGraph mains ffiInfos

  Log.logEvent (GenerateCompleted modNameText (GenStats 0 0))

  return (Right jsBuilder)

-- | Build complete GlobalGraph including ALL dependencies.
--
-- This is the CRITICAL FIX for the code generation bug. Previously, only
-- the main modules' graphs were included in the GlobalGraph, causing the
-- generated JavaScript to miss dependency code.
--
-- This function:
-- 1. Takes all LocalGraphs from compiled modules
-- 2. Merges them into a single GlobalGraph
-- 3. Returns a complete graph containing ALL code needed for generation
--
-- The fix ensures that ALL dependencies are included in the generated
-- JavaScript, not just the main entry points.
--
-- @since 0.19.1
buildCompleteGlobalGraph :: [Opt.LocalGraph] -> Opt.GlobalGraph
buildCompleteGlobalGraph localGraphs =
  foldr Opt.addLocalGraph Opt.empty localGraphs

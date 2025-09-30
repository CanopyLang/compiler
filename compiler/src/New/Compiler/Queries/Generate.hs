{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Code generation query for the new compiler.
--
-- This module wraps the existing Generate.JavaScript.generate function
-- in the query system, providing caching and debug logging.
--
-- @since 0.19.1
module New.Compiler.Queries.Generate
  ( generateJavaScriptQuery,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import Data.ByteString.Builder (Builder)
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Generate.JavaScript as JS
import qualified Generate.Mode as Mode
import qualified New.Compiler.Debug.Logger as Logger
import New.Compiler.Debug.Logger (DebugCategory (..))
import New.Compiler.Query.Simple

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
  Logger.debug CODEGEN ("Generate: Starting JavaScript generation")
  Logger.debug CODEGEN ("Generate: Mode: " ++ show mode)
  Logger.debug CODEGEN ("Generate: Mains count: " ++ show (Map.size mains))
  Logger.debug CODEGEN ("Generate: FFI count: " ++ show (Map.size ffiInfos))

  logGlobalGraphStats globalGraph

  -- Generate JavaScript using existing generator
  let jsBuilder = JS.generate mode globalGraph mains ffiInfos

  -- Log generation statistics
  Logger.debug CODEGEN "Generate: JavaScript generated successfully"
  Logger.debug CODEGEN "Generate: Success"

  return (Right jsBuilder)

-- | Log global graph statistics.
logGlobalGraphStats :: Opt.GlobalGraph -> IO ()
logGlobalGraphStats (Opt.GlobalGraph graph foreigns) = do
  Logger.debug CODEGEN ("Generate: Global graph statistics:")
  Logger.debug CODEGEN ("  - Globals: " ++ show (Map.size graph))
  Logger.debug CODEGEN ("  - Foreigns: " ++ show (Map.size foreigns))

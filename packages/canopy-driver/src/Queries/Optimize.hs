{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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
import Data.Map (Map)
import qualified Data.Name as Name
import qualified Debug.Logger as Logger
import Debug.Logger (DebugCategory (..))
import Query.Simple
import qualified Optimize.Module as Optimize
import qualified Reporting.Result as Result
import qualified Reporting.Warning as W

-- | Optimize a canonical module to produce optimized AST.
--
-- This query wraps Optimize.Module.optimize with debug logging.
-- Takes canonical module and type annotations, returns optimized LocalGraph.
optimizeModuleQuery ::
  Map Name.Name Can.Annotation ->
  Can.Module ->
  IO (Either QueryError Opt.LocalGraph)
optimizeModuleQuery annotations canonModule@(Can.Module modName _ _ _ _ _ _ _) = do
  Logger.debug COMPILE_DEBUG ("Optimize: Starting for module: " ++ show modName)
  Logger.debug COMPILE_DEBUG ("Optimize: Annotations count: " ++ show (length annotations))

  -- Run optimization using existing optimizer
  case Result.run (Optimize.optimize annotations canonModule) of
    (_warnings, Left err) -> do
      Logger.debug COMPILE_DEBUG ("Optimize: Failed with error: " ++ show err)
      return (Left (OtherError ("Optimization error: " ++ show err)))
    (warnings, Right localGraph) -> do
      Logger.debug COMPILE_DEBUG ("Optimize: Success with " ++ show (length warnings) ++ " warnings")
      logWarnings warnings
      logOptimizationStats localGraph
      return (Right localGraph)

-- | Log optimization warnings.
logWarnings :: [W.Warning] -> IO ()
logWarnings [] = return ()
logWarnings warnings = do
  Logger.debug COMPILE_DEBUG ("Optimize: Warnings:")
  mapM_ logWarning warnings

-- | Log single warning.
logWarning :: W.Warning -> IO ()
logWarning _warning =
  Logger.debug COMPILE_DEBUG "  - <warning>"

-- | Log optimization statistics.
logOptimizationStats :: Opt.LocalGraph -> IO ()
logOptimizationStats (Opt.LocalGraph maybeMain nodes fields) = do
  Logger.debug COMPILE_DEBUG ("Optimize: Statistics:")
  Logger.debug COMPILE_DEBUG ("  - Has main: " ++ show (isJust maybeMain))
  Logger.debug COMPILE_DEBUG ("  - Nodes: " ++ show (length nodes))
  Logger.debug COMPILE_DEBUG ("  - Fields: " ++ show (length fields))
  where
    isJust Nothing = False
    isJust (Just _) = True

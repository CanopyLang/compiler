{-# OPTIONS_GHC -Wall #-}

-- | Query-based type checking with caching and debug logging.
--
-- This module wraps the existing Type.Constrain and Type.Solve
-- implementations in a query-based architecture with comprehensive
-- debug logging.
--
-- @since 0.19.1
module Queries.Type.Check
  ( -- * Query Execution
    typeCheckModuleQuery,
  )
where

import qualified AST.Canonical as Can
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import qualified Debug.Logger as Logger
import Debug.Logger (DebugCategory (..))
import Query.Simple
import qualified Reporting.Error.Type as Error
import qualified Type.Constrain.Module as Constrain
import qualified Type.Solve as Solve
import Type.Type (Constraint)

-- | Execute a type check module query.
typeCheckModuleQuery ::
  Can.Module ->
  IO (Either QueryError (Map Name.Name Can.Annotation))
typeCheckModuleQuery canonical = do
  let modName = Can._name canonical
  Logger.debug TYPE ("Starting type checking for: " ++ show modName)

  logModuleStructure canonical

  Logger.debug TYPE "Generating type constraints"
  constraint <- Constrain.constrain canonical
  logConstraintInfo constraint

  Logger.debug TYPE "Running type solver"
  solveResult <- Solve.run constraint

  case solveResult of
    Left errors -> do
      Logger.debug TYPE ("Type checking failed: " ++ show (countErrors errors))
      logTypeErrors errors
      return (Left (processErrors errors))
    Right typeMap -> do
      Logger.debug TYPE ("Type checking success: " ++ show (Map.size typeMap) ++ " bindings")
      logTypedBindings typeMap
      return (Right typeMap)

-- | Log canonical module structure.
logModuleStructure :: Can.Module -> IO ()
logModuleStructure canonical = do
  let unionCount = Map.size (Can._unions canonical)
      aliasCount = Map.size (Can._aliases canonical)
      effectsInfo = describeEffects (Can._effects canonical)

  Logger.debug TYPE ("Unions: " ++ show unionCount)
  Logger.debug TYPE ("Aliases: " ++ show aliasCount)
  Logger.debug TYPE ("Effects: " ++ effectsInfo)

-- | Describe module effects.
describeEffects :: Can.Effects -> String
describeEffects effects =
  case effects of
    Can.NoEffects -> "none"
    Can.Ports _ -> "ports"
    Can.FFI -> "FFI"
    Can.Manager {} -> "manager"

-- | Log constraint information.
logConstraintInfo :: Constraint -> IO ()
logConstraintInfo _ =
  Logger.debug TYPE "Constraints generated"

-- | Count errors in list.
countErrors :: List a -> Int
countErrors (NE.List _ xs) = 1 + length xs

-- | Log type errors.
logTypeErrors :: List Error.Error -> IO ()
logTypeErrors errors = do
  let count = countErrors errors
      errorList = NE.toList errors
  Logger.debug TYPE ("Total type errors: " ++ show count)
  mapM_ logSingleError errorList

-- | Log a single type error.
logSingleError :: Error.Error -> IO ()
logSingleError err =
  Logger.debug TYPE ("Type error: " ++ show err)

-- | Log typed bindings.
logTypedBindings :: Map Name.Name Can.Annotation -> IO ()
logTypedBindings typeMap = do
  Logger.debug TYPE ("Typed bindings: " ++ show (Map.size typeMap))
  _ <- Map.traverseWithKey logBinding typeMap
  return ()

-- | Log a single binding.
logBinding :: Name.Name -> Can.Annotation -> IO ()
logBinding name _ =
  Logger.debug TYPE ("  " ++ show name)

-- | Convert type errors to QueryError.
processErrors :: List Error.Error -> QueryError
processErrors errors =
  TypeError (show (NE.head errors))

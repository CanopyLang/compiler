{-# OPTIONS_GHC -Wall #-}

-- | Query-based canonicalization with caching and debug logging.
--
-- This module wraps the existing Canonicalize.Module implementation
-- in a query-based architecture with content-hash caching and
-- comprehensive debug logging.
--
-- @since 0.19.1
module Queries.Canonicalize.Module
  ( -- * Query Execution
    canonicalizeModuleQuery,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Module as Canonicalize
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.OneOrMore as OneOrMore
import qualified Debug.Logger as Logger
import Debug.Logger (DebugCategory (..))
import Query.Simple
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.InternalError as InternalError
import qualified Reporting.Result as Result

-- | Execute a canonicalize module query.
canonicalizeModuleQuery ::
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  Map String String ->
  Src.Module ->
  IO (Either QueryError Can.Module)
canonicalizeModuleQuery pkg ifaces ffiContent modul = do
  let modName = Src.getName modul
  Logger.debug TYPE ("Starting canonicalization for: " ++ show modName)
  Logger.debug TYPE ("Package: " ++ show pkg)
  Logger.debug TYPE ("Interfaces available: " ++ show (Map.size ifaces))

  logModuleStructure modul

  let result = Canonicalize.canonicalize pkg ifaces ffiContent modul
  case processResult result of
    Left err -> do
      Logger.debug TYPE ("Canonicalization failed: " ++ show err)
      return (Left err)
    Right canonical -> do
      Logger.debug TYPE ("Canonicalization success: " ++ show (Can._name canonical))
      logCanonicalInfo canonical
      return (Right canonical)

-- | Log source module structure.
logModuleStructure :: Src.Module -> IO ()
logModuleStructure modul = do
  let importCount = length (Src._imports modul)
      foreignCount = length (Src._foreignImports modul)

  Logger.debug TYPE ("Source imports: " ++ show importCount)
  Logger.debug TYPE ("Foreign imports: " ++ show foreignCount)

-- | Log canonical module information.
logCanonicalInfo :: Can.Module -> IO ()
logCanonicalInfo canonical = do
  let unionCount = Map.size (Can._unions canonical)
      aliasCount = Map.size (Can._aliases canonical)
      binopCount = Map.size (Can._binops canonical)

  Logger.debug TYPE ("Unions: " ++ show unionCount)
  Logger.debug TYPE ("Aliases: " ++ show aliasCount)
  Logger.debug TYPE ("Binops: " ++ show binopCount)

-- | Process Result type into Either QueryError.
processResult ::
  Result.Result i w Error.Error Can.Module ->
  Either QueryError Can.Module
processResult result =
  let (_, output) = Result.run (toEmptyWarnings result)
   in case output of
        Left errors -> Left (processErrors errors)
        Right canonical -> Right canonical

-- | Convert Result to empty warnings type.
toEmptyWarnings ::
  Result.Result i w e a ->
  Result.Result () [w] e a
toEmptyWarnings (Result.Result k) =
  Result.Result
    ( \() w bad good ->
        k phantomInfo phantomWarnings (\_ _ -> bad () w) (\_ _ -> good () w)
    )
  where
    phantomInfo = InternalError.report
      "Queries.Canonicalize.Module.toEmptyWarnings"
      "phantom info value evaluated"
      "The initial info accumulator in toEmptyWarnings should never be evaluated. The CPS callbacks discard it. If this fires, it indicates a change in Result internals."
    phantomWarnings = InternalError.report
      "Queries.Canonicalize.Module.toEmptyWarnings"
      "phantom warnings value evaluated"
      "The initial warnings accumulator in toEmptyWarnings should never be evaluated. The CPS callbacks discard it. If this fires, it indicates a change in Result internals."

-- | Convert canonicalization errors to QueryError.
processErrors :: OneOrMore.OneOrMore Error.Error -> QueryError
processErrors errors =
  TypeError (show (OneOrMore.destruct (\h _ -> h) errors))

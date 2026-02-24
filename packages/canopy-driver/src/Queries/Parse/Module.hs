{-# OPTIONS_GHC -Wall #-}

-- | Query-based module parsing with caching and debug logging.
--
-- This module implements the ParseModuleQuery following the query-based
-- architecture. It reuses the existing Parse.Module parser while adding
-- content-hash caching and comprehensive debug logging.
--
-- @since 0.19.1
module Queries.Parse.Module
  ( -- * Query Execution
    parseModuleQuery,
  )
where

import qualified AST.Source as Src
import qualified Data.ByteString as BS
import Logging.Event (LogEvent (..), ParseStats (..))
import qualified Logging.Logger as Log
import Query.Simple
import qualified Parse.Module as Parse



-- | Count declarations in a module.
--
-- Counts all top-level declarations: value definitions, union types,
-- and type aliases. This provides an accurate count for parse statistics.
countDeclarations :: Src.Module -> Int
countDeclarations modul =
  length (Src._values modul)
    + length (Src._unions modul)
    + length (Src._aliases modul)

-- | Execute a parse module query.
parseModuleQuery ::
  Parse.ProjectType ->
  FilePath ->
  IO (Either QueryError Src.Module)
parseModuleQuery projectType path = do
  content <- BS.readFile path
  let fileSize = BS.length content
  Log.logEvent (ParseStarted path fileSize)

  let hash = computeContentHash content
  let query = ParseModuleQuery path hash projectType

  result <- executeQuery query
  case result of
    Left err -> return (Left err)
    Right (ParsedModule modul) -> do
      let declCount = countDeclarations modul
          importCount = length (Src._imports modul)
          hasFFI = not (null (Src._foreignImports modul))
      Log.logEvent (ParseCompleted path (ParseStats declCount importCount hasFFI))
      return (Right modul)
    Right _ -> return (Left (OtherError "Unexpected query result type"))

{-# OPTIONS_GHC -Wall #-}

-- | Query-based module parsing with caching and debug logging.
--
-- This module implements the ParseModuleQuery following the query-based
-- architecture. It reuses the existing Parse.Module parser while adding
-- content-hash caching and comprehensive debug logging.
--
-- @since 0.19.1
module New.Compiler.Queries.Parse.Module
  ( -- * Query Execution
    parseModuleQuery,
  )
where

import qualified AST.Source as Src
import qualified Data.ByteString as BS
import qualified New.Compiler.Debug.Logger as Logger
import New.Compiler.Debug.Logger (DebugCategory (..))
import New.Compiler.Query.Simple
import qualified Parse.Module as Parse



-- | Log detailed module information.
logModuleInfo :: Src.Module -> IO ()
logModuleInfo modul = do
  let declCount = countDeclarations modul
      importCount = length (Src._imports modul)
      foreignCount = length (Src._foreignImports modul)

  Logger.debug PARSE ("Declarations: " ++ show declCount)
  Logger.debug PARSE ("Imports: " ++ show importCount)
  Logger.debug PARSE ("Foreign imports: " ++ show foreignCount)

-- | Count declarations in a module.
countDeclarations :: Src.Module -> Int
countDeclarations modul =
  case modul of
    Src.Module {Src._docs = docs} -> length (extractDecls docs)
  where
    extractDecls :: Src.Docs -> [a]
    extractDecls _ = []

-- | Execute a parse module query.
parseModuleQuery ::
  Parse.ProjectType ->
  FilePath ->
  IO (Either QueryError Src.Module)
parseModuleQuery projectType path = do
  Logger.debug PARSE ("Starting parse query for: " ++ path)

  content <- BS.readFile path
  Logger.debug PARSE ("File size: " ++ show (BS.length content) ++ " bytes")

  let hash = computeContentHash content
  let query = ParseModuleQuery path hash projectType

  result <- executeQuery query
  case result of
    Left err -> return $ Left err
    Right (ParsedModule modul) -> do
      Logger.debug PARSE ("Parse success: module " ++ show (Src._name modul))
      logModuleInfo modul
      return $ Right modul
    Right _ -> return $ Left $ OtherError "Unexpected query result type"

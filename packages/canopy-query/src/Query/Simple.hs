{-# LANGUAGE GADTs #-}
{-# OPTIONS_GHC -Wall #-}

-- | Simplified query system without complex type families.
--
-- This uses a simpler GADT approach that's easier to work with in Haskell.
--
-- @since 0.19.1
module Query.Simple
  ( -- * Query Types
    Query (..),
    QueryResult (..),
    QueryError (..),

    -- * Query Execution
    executeQuery,

    -- * Cache Types
    ContentHash (..),
    computeContentHash,
  )
where

import qualified AST.Source as Src
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import Data.ByteString (ByteString)
import qualified Parse.Module as Parse

-- | Content hash for cache invalidation.
newtype ContentHash = ContentHash ByteString
  deriving (Eq, Ord, Show)

-- | Compute content hash using SHA256.
--
-- This produces a cryptographically secure hash that uniquely identifies
-- the content. Different content will produce different hashes (no collisions
-- in practice).
--
-- @since 0.19.1
computeContentHash :: ByteString -> ContentHash
computeContentHash = ContentHash . SHA256.hash

-- | Query errors.
data QueryError
  = ParseError FilePath String
  | TypeError String
  | FileNotFound FilePath
  | OtherError String
  deriving (Show, Eq)

-- | Query results (existential type).
data QueryResult
  = ParsedModule Src.Module
  | CanonicalizedModule
  | TypedModule
  | OptimizedModule
  deriving (Show)

-- | Query type using GADT.
data Query where
  ParseModuleQuery ::
    { parseFile :: FilePath,
      parseHash :: ContentHash,
      parseProjectType :: Parse.ProjectType
    } ->
    Query

instance Show Query where
  show (ParseModuleQuery path hash _) =
    "ParseModuleQuery " ++ path ++ " " ++ show hash

-- Make Query comparable.
instance Eq Query where
  (ParseModuleQuery f1 h1 _) == (ParseModuleQuery f2 h2 _) =
    f1 == f2 && h1 == h2

instance Ord Query where
  compare (ParseModuleQuery f1 h1 _) (ParseModuleQuery f2 h2 _) =
    compare (f1, h1) (f2, h2)

-- | Execute a query.
executeQuery :: Query -> IO (Either QueryError QueryResult)
executeQuery query = case query of
  ParseModuleQuery path _ projectType -> do
    content <- BS.readFile path
    case Parse.fromByteString projectType content of
      Left err -> return $ Left $ ParseError path (show err)
      Right modul -> return $ Right $ ParsedModule modul

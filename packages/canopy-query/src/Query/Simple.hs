{-# LANGUAGE GADTs #-}

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
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import qualified Parse.Cache
import qualified Parse.Module as Parse
import Reporting.Diagnostic (Diagnostic)
import qualified Reporting.Error.Syntax as Syntax
import qualified Reporting.Render.Code as Code
import System.IO.Unsafe (unsafePerformIO)

-- | Global parse cache (module-level IORef for sharing across queries).
--
-- This is safe because:
-- 1. Parse cache is append-only (never invalidated)
-- 2. Concurrent access is thread-safe with IORef
-- 3. Improves performance by caching across query executions
{-# NOINLINE globalParseCache #-}
globalParseCache :: IORef Parse.Cache.ParseCache
globalParseCache = unsafePerformIO (newIORef Parse.Cache.emptyCache)

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
--
-- 'DiagnosticError' carries structured 'Diagnostic' values from the
-- compiler phases. These provide rich error output with error codes,
-- source spans, and suggestions. The legacy string-based constructors
-- are retained for backwards compatibility.
data QueryError
  = ParseError FilePath String
  | TypeError String
  | FileNotFound FilePath
  | OtherError String
  | DiagnosticError FilePath [Diagnostic]
  | TimeoutError FilePath
  deriving (Show)

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

-- | Execute a query with parse caching.
--
-- Parse errors are converted to structured 'DiagnosticError' values
-- using the source bytes for proper snippet rendering.
executeQuery :: Query -> IO (Either QueryError QueryResult)
executeQuery query = case query of
  ParseModuleQuery path _ projectType -> do
    content <- BS.readFile path
    cache <- readIORef globalParseCache
    let (result, newCache) = Parse.Cache.cacheLookupOrParse path projectType content cache
    writeIORef globalParseCache newCache
    case result of
      Left err ->
        let source = Code.toSource content
            diag = Syntax.toDiagnostic source err
         in return (Left (DiagnosticError path [diag]))
      Right modul -> return (Right (ParsedModule modul))

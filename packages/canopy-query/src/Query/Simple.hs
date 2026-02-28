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

-- | Global parse cache shared across query executions.
--
-- __SAFETY__: This use of 'unsafePerformIO' is safe because:
--
--   1. __Single initialization__: The @NOINLINE@ pragma prevents GHC from
--      inlining or duplicating this CAF. The 'IORef' is created exactly
--      once, starting with an empty cache.
--   2. __Thread safety__: Reads use 'readIORef' and writes use 'writeIORef'.
--      In the current single-threaded query executor, there is no concurrent
--      access. If the executor becomes multi-threaded, these must be upgraded
--      to 'atomicModifyIORef'' to avoid lost updates.
--   3. __Append-only semantics__: The cache grows monotonically -- entries
--      are added but never removed or overwritten. Even if a race condition
--      caused a stale read, the worst outcome is a redundant re-parse, not
--      incorrect behavior.
--
-- __Alternatives rejected__:
--
--   * Threading the cache via 'StateT' would require changing the
--     'executeQuery' signature and all call sites.
--   * An 'MVar' would add unnecessary contention for the current
--     single-threaded use case.
--
-- @since 0.19.1
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

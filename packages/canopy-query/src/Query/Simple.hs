{-# LANGUAGE GADTs #-}

-- | Simplified query system with full phase caching.
--
-- This uses a GADT approach for type-safe queries across all compilation
-- phases: parse, canonicalize, type-check, optimize, and interface generation.
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
    combineHashes,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canopy.Data.Name as Name
import qualified Canopy.Interface as Interface
import qualified Crypto.Hash.SHA256 as SHA256
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
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
-- @since 0.19.1
{-# NOINLINE globalParseCache #-}
globalParseCache :: IORef Parse.Cache.ParseCache
globalParseCache = unsafePerformIO (newIORef Parse.Cache.emptyCache)

-- | Content hash for cache invalidation.
newtype ContentHash = ContentHash ByteString
  deriving (Eq, Ord, Show)

-- | Compute content hash using SHA256.
--
-- @since 0.19.1
computeContentHash :: ByteString -> ContentHash
computeContentHash = ContentHash . SHA256.hash

-- | Combine multiple hashes into one for composite cache keys.
--
-- Used to compute input hashes for phases that depend on multiple inputs
-- (e.g., canonicalization depends on parse result + package name + interfaces).
--
-- @since 0.19.2
combineHashes :: [ContentHash] -> ContentHash
combineHashes hashes =
  ContentHash (SHA256.hash (BS.concat (fmap extractHash hashes)))
  where
    extractHash (ContentHash h) = h

-- | Query errors.
--
-- 'DiagnosticError' carries structured 'Diagnostic' values from the
-- compiler phases. These provide rich error output with error codes,
-- source spans, and suggestions.
data QueryError
  = ParseError FilePath String
  | TypeError String
  | FileNotFound FilePath
  | OtherError String
  | DiagnosticError FilePath [Diagnostic]
  | TimeoutError FilePath
  deriving (Show)

-- | Query results with real data for all phases.
--
-- Each constructor carries the actual compilation artifact so that
-- downstream phases can retrieve cached results directly.
--
-- @since 0.19.2
data QueryResult
  = ParsedModule !Src.Module
  | CanonicalizedModule !Can.Module
  | TypeCheckedModule !(Map Name.Name Can.Annotation)
  | OptimizedModule !Opt.LocalGraph
  | ModuleInterface !Interface.Interface

instance Show QueryResult where
  show (ParsedModule _) = "ParsedModule"
  show (CanonicalizedModule _) = "CanonicalizedModule"
  show (TypeCheckedModule m) = "TypeCheckedModule(" ++ show (Map.size m) ++ " entries)"
  show (OptimizedModule g) = "OptimizedModule(" ++ show g ++ ")"
  show (ModuleInterface _) = "ModuleInterface"

-- | Query type using GADT for all compilation phases.
--
-- Each query includes a 'ContentHash' that represents the hash of all
-- inputs to that phase. Cache lookup checks both the query identity
-- and hash equality for correctness.
--
-- @since 0.19.2
data Query where
  ParseModuleQuery ::
    { parseFile :: !FilePath,
      parseHash :: !ContentHash,
      parseProjectType :: !Parse.ProjectType
    } ->
    Query
  CanonicalizeQuery ::
    { canonFile :: !FilePath,
      canonHash :: !ContentHash
    } ->
    Query
  TypeCheckQuery ::
    { typeCheckFile :: !FilePath,
      typeCheckHash :: !ContentHash
    } ->
    Query
  OptimizeQuery ::
    { optimizeFile :: !FilePath,
      optimizeHash :: !ContentHash
    } ->
    Query
  InterfaceQuery ::
    { ifaceFile :: !FilePath,
      ifaceHash :: !ContentHash
    } ->
    Query

instance Show Query where
  show (ParseModuleQuery path hash _) =
    "ParseModuleQuery " ++ path ++ " " ++ show hash
  show (CanonicalizeQuery path hash) =
    "CanonicalizeQuery " ++ path ++ " " ++ show hash
  show (TypeCheckQuery path hash) =
    "TypeCheckQuery " ++ path ++ " " ++ show hash
  show (OptimizeQuery path hash) =
    "OptimizeQuery " ++ path ++ " " ++ show hash
  show (InterfaceQuery path hash) =
    "InterfaceQuery " ++ path ++ " " ++ show hash

instance Eq Query where
  (ParseModuleQuery f1 h1 _) == (ParseModuleQuery f2 h2 _) =
    f1 == f2 && h1 == h2
  (CanonicalizeQuery f1 h1) == (CanonicalizeQuery f2 h2) =
    f1 == f2 && h1 == h2
  (TypeCheckQuery f1 h1) == (TypeCheckQuery f2 h2) =
    f1 == f2 && h1 == h2
  (OptimizeQuery f1 h1) == (OptimizeQuery f2 h2) =
    f1 == f2 && h1 == h2
  (InterfaceQuery f1 h1) == (InterfaceQuery f2 h2) =
    f1 == f2 && h1 == h2
  _ == _ = False

instance Ord Query where
  compare q1 q2 = compare (queryTag q1, queryKey q1) (queryTag q2, queryKey q2)

-- | Numeric tag for query ordering.
queryTag :: Query -> Int
queryTag ParseModuleQuery {} = 0
queryTag CanonicalizeQuery {} = 1
queryTag TypeCheckQuery {} = 2
queryTag OptimizeQuery {} = 3
queryTag InterfaceQuery {} = 4

-- | Composite key for query ordering within the same tag.
queryKey :: Query -> (FilePath, ContentHash)
queryKey (ParseModuleQuery f h _) = (f, h)
queryKey (CanonicalizeQuery f h) = (f, h)
queryKey (TypeCheckQuery f h) = (f, h)
queryKey (OptimizeQuery f h) = (f, h)
queryKey (InterfaceQuery f h) = (f, h)

-- | Execute a query directly (only parse queries execute here).
--
-- Non-parse queries are cached and executed by the Driver, which has
-- access to all the context needed (package name, interfaces, etc.).
-- This function only handles ParseModuleQuery.
--
-- @since 0.19.1
executeQuery :: Query -> IO (Either QueryError QueryResult)
executeQuery (ParseModuleQuery path _ projectType) = do
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
executeQuery _ = return (Left (OtherError "Non-parse queries must be executed through the Driver"))

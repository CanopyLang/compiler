{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Generate.JavaScript.CodeSplit.Types - Core types for code splitting
--
-- Defines the fundamental data structures used throughout the code splitting
-- pipeline: chunk identifiers, chunk classification, chunk graphs, split
-- configuration, and output descriptors.
--
-- Code splitting partitions a program's global definitions into multiple
-- JavaScript files (chunks) based on @lazy import@ declarations in source
-- code. The entry chunk contains the runtime and eagerly-loaded code, while
-- lazy chunks are loaded on demand.
--
-- @since 0.19.2
module Generate.JavaScript.CodeSplit.Types
  ( ChunkId (..),
    ChunkKind (..),
    Chunk (..),
    ChunkGraph (..),
    SplitConfig (..),
    SplitOutput (..),
    ChunkOutput (..),
    ChunkContext (..),
    ChunkGraphCache (..),
    -- lenses
    chunkId,
    chunkKind,
    chunkGlobals,
    chunkDeps,
    chunkModule,
    cgEntry,
    cgLazy,
    cgShared,
    cgGlobalToChunk,
    scLazyModules,
    scMinSharedRefs,
    soChunks,
    soManifest,
    coChunkId,
    coKind,
    coBuilder,
    coHash,
    coFilename,
    ccCurrentChunk,
    ccGlobalToChunk,
    cacheConfig,
    cacheGraphHash,
    cacheResult,
    -- helpers
    entryChunkId,
    isEntryChunk,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import Control.Lens (makeLenses)
import Data.ByteString.Builder (Builder)
import Data.Map.Strict (Map)
import Data.Set (Set)
import qualified Data.Text as Text

-- | Unique identifier for a generated chunk.
--
-- Chunk IDs are deterministic strings derived from the chunk's content
-- or module name. They appear in filenames and the chunk manifest.
--
-- @since 0.19.2
newtype ChunkId = ChunkId Text.Text
  deriving (Eq, Ord, Show)

-- | Classification of a chunk.
--
-- Determines the role of a chunk in the loading graph:
--
-- * 'EntryChunk' — contains the runtime, manifest, and eagerly-loaded code
-- * 'LazyChunk' — loaded on demand when a lazy-imported module is accessed
-- * 'SharedChunk' — extracted common code referenced by multiple chunks
--
-- @since 0.19.2
data ChunkKind
  = EntryChunk
  | LazyChunk
  | SharedChunk
  deriving (Eq, Ord, Show)

-- | A single chunk of code to be emitted as a JavaScript file.
--
-- Each chunk owns a disjoint subset of the program's global definitions.
-- The chunk graph guarantees that every reachable global belongs to exactly
-- one chunk and that the dependency edges between chunks form a DAG.
--
-- @since 0.19.2
data Chunk = Chunk
  { _chunkId :: !ChunkId,
    _chunkKind :: !ChunkKind,
    _chunkGlobals :: !(Set Opt.Global),
    _chunkDeps :: !(Set ChunkId),
    _chunkModule :: !(Maybe ModuleName.Canonical)
  }
  deriving (Eq, Show)

-- | Complete chunk graph after analysis.
--
-- Represents the full partitioning of a program's globals into chunks.
-- Invariants:
--
-- * @union(all chunk globals) == reachable globals@
-- * @intersection(chunk_i globals, chunk_j globals) == empty@ for all i /= j
-- * The entry chunk has no incoming chunk dependencies
-- * The dependency graph between chunks is acyclic
--
-- @since 0.19.2
data ChunkGraph = ChunkGraph
  { _cgEntry :: !Chunk,
    _cgLazy :: ![Chunk],
    _cgShared :: ![Chunk],
    _cgGlobalToChunk :: !(Map Opt.Global ChunkId)
  }
  deriving (Eq, Show)

-- | Configuration derived from source-level lazy imports.
--
-- Controls the behaviour of the chunk analysis algorithm.
-- '_scLazyModules' is populated from the canonical module's lazy import set.
-- '_scMinSharedRefs' sets the minimum number of chunk references before a
-- global is extracted into a shared chunk (default: 2).
--
-- @since 0.19.2
data SplitConfig = SplitConfig
  { _scLazyModules :: !(Set ModuleName.Canonical),
    _scMinSharedRefs :: !Int
  }
  deriving (Eq, Show)

-- | Final output of the code splitting pipeline.
--
-- Contains the generated JavaScript for every chunk plus the JSON manifest
-- mapping chunk IDs to filenames.
--
-- @since 0.19.2
data SplitOutput = SplitOutput
  { _soChunks :: ![ChunkOutput],
    _soManifest :: !Builder
  }

-- | Output for a single chunk.
--
-- Carries the generated JavaScript, content hash for cache-busting, and
-- the filename that will appear in the manifest and on disk.
--
-- @since 0.19.2
data ChunkOutput = ChunkOutput
  { _coChunkId :: !ChunkId,
    _coKind :: !ChunkKind,
    _coBuilder :: !Builder,
    _coHash :: !Text.Text,
    _coFilename :: !FilePath
  }

-- | Context threaded through expression generation for chunk-aware references.
--
-- When code splitting is active, expression generation checks whether a
-- referenced global belongs to the current chunk or a different one.
-- Same-chunk references remain direct variable access; cross-chunk references
-- emit @__canopy_load("chunk-id").$global_name@.
--
-- When 'NoSplitting' is used, behaviour is identical to the existing
-- single-file code generation path.
--
-- @since 0.19.2
data ChunkContext
  = ChunkContext
      { _ccCurrentChunk :: !ChunkId,
        _ccGlobalToChunk :: !(Map Opt.Global ChunkId)
      }
  | NoSplitting
  deriving (Eq, Show)

-- | The well-known chunk ID for the entry chunk.
--
-- @since 0.19.2
entryChunkId :: ChunkId
entryChunkId = ChunkId "entry"

-- | Test whether a chunk ID is the entry chunk.
--
-- @since 0.19.2
isEntryChunk :: ChunkId -> Bool
isEntryChunk (ChunkId cid) = cid == "entry"

-- | Cache entry for chunk graph analysis.
--
-- Stores the inputs (config + graph hash) alongside the analysis result.
-- If both the 'SplitConfig' and graph hash match on a subsequent build,
-- the cached 'ChunkGraph' can be reused without re-running the analysis.
--
-- The graph hash is computed from the global graph's key set, not its full
-- content, since node-level changes that do not add or remove globals do
-- not affect the chunk partitioning.
--
-- @since 0.19.2
data ChunkGraphCache = ChunkGraphCache
  { _cacheConfig :: !SplitConfig,
    _cacheGraphHash :: !Int,
    _cacheResult :: !ChunkGraph
  }
  deriving (Eq, Show)

makeLenses ''Chunk
makeLenses ''ChunkGraph
makeLenses ''SplitConfig
makeLenses ''SplitOutput
makeLenses ''ChunkOutput
makeLenses ''ChunkContext
makeLenses ''ChunkGraphCache

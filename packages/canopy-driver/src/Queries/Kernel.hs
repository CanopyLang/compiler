{-# LANGUAGE OverloadedStrings #-}

-- | Kernel module query system.
--
-- This module provides queries for analyzing and caching kernel modules
-- (built-in Canopy modules like Basics, List, Maybe, etc.). These modules
-- have special JavaScript implementations that require special handling.
--
-- == Usage Examples
--
-- @
-- import qualified Queries.Kernel as KernelQuery
--
-- analyzeKernel :: FilePath -> IO (Either QueryError KernelContent)
-- analyzeKernel path = KernelQuery.kernelFileQuery pkg foreigns path
-- @
--
-- @since 0.19.1
module Queries.Kernel
  ( -- * Query Functions
    kernelFileQuery,
    kernelContentQuery,

    -- * Re-exports
    Content (..),
    Chunk (..),
  )
where

import qualified Canopy.Kernel as Kernel
import Canopy.Kernel (Chunk (..), Content (..))
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Map.Strict (Map)
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Query.Simple

-- | Query for analyzing a kernel module file.
--
-- Parses kernel JavaScript code and extracts chunks for compilation.
-- Results are cached based on file content hash.
--
-- @since 0.19.1
kernelFileQuery ::
  Pkg.Name ->
  Map ModuleName.Raw Pkg.Name ->
  FilePath ->
  IO (Either QueryError Content)
kernelFileQuery pkg foreigns kernelFile = do
  Log.logEvent (KernelStarted kernelFile)

  contentBytes <- BS.readFile kernelFile

  kernelContentQuery pkg foreigns contentBytes

-- | Query for parsing kernel content from ByteString.
--
-- Parses kernel JavaScript code and extracts imports and chunks.
--
-- @since 0.19.1
kernelContentQuery ::
  Pkg.Name ->
  Map ModuleName.Raw Pkg.Name ->
  ByteString ->
  IO (Either QueryError Content)
kernelContentQuery pkg foreigns contentBytes = do
  case Kernel.fromByteString pkg foreigns contentBytes of
    Nothing -> do
      Log.logEvent (KernelFailed "<kernel>" (Text.pack "Failed to parse kernel module"))
      return (Left (ParseError "<kernel>" "Failed to parse kernel module"))
    Just content@(Content _imports chunks) -> do
      Log.logEvent (KernelCompleted "<kernel>" (length chunks))
      return (Right content)

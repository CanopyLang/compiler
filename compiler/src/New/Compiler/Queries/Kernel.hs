{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Kernel module query system.
--
-- This module provides queries for analyzing and caching kernel modules
-- (built-in Canopy modules like Basics, List, Maybe, etc.). These modules
-- have special JavaScript implementations that require special handling.
--
-- == Usage Examples
--
-- @
-- import qualified New.Compiler.Queries.Kernel as KernelQuery
--
-- analyzeKernel :: FilePath -> IO (Either QueryError KernelContent)
-- analyzeKernel path = KernelQuery.kernelFileQuery pkg foreigns path
-- @
--
-- @since 0.19.1
module New.Compiler.Queries.Kernel
  ( -- * Query Functions
    kernelFileQuery,
    kernelContentQuery,

    -- * Re-exports
    Content (..),
    Chunk (..),
  )
where

import qualified AST.Source as Src
import qualified Reporting.Annotation as A
import qualified Canopy.Kernel as Kernel
import Canopy.Kernel (Chunk (..), Content (..))
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Map (Map)
import qualified New.Compiler.Debug.Logger as Logger
import New.Compiler.Debug.Logger (DebugCategory (..))
import New.Compiler.Query.Simple

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
  Logger.debug KERNEL_DEBUG ("Analyzing kernel file: " ++ kernelFile)
  Logger.debug KERNEL_DEBUG ("Package: " ++ show pkg)

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
  Logger.debug KERNEL_DEBUG ("Parsing kernel content (" ++ show (BS.length contentBytes) ++ " bytes)")

  case Kernel.fromByteString pkg foreigns contentBytes of
    Nothing -> do
      Logger.debug KERNEL_DEBUG "Kernel parse failed"
      return (Left (ParseError "<kernel>" "Failed to parse kernel module"))
    Just content -> do
      logKernelContent content
      Logger.debug KERNEL_DEBUG "Kernel parse succeeded"
      return (Right content)

-- | Log kernel content details.
logKernelContent :: Content -> IO ()
logKernelContent (Content imports chunks) = do
  Logger.debug KERNEL_DEBUG ("Kernel imports: " ++ show (length imports))
  Logger.debug KERNEL_DEBUG ("Kernel chunks: " ++ show (length chunks))

  mapM_ logImport imports
  mapM_ logChunk chunks
  where
    logImport :: Src.Import -> IO ()
    logImport (Src.Import (A.At _ name) _ _) =
      Logger.debug KERNEL_DEBUG ("  Import: " ++ show name)

    logChunk :: Chunk -> IO ()
    logChunk chunk = case chunk of
      JS bs ->
        Logger.debug KERNEL_DEBUG ("  JS chunk: " ++ show (BS.length bs) ++ " bytes")
      CanopyVar modName varName ->
        Logger.debug KERNEL_DEBUG ("  Canopy var: " ++ show modName ++ "." ++ show varName)
      JsVar name1 name2 ->
        Logger.debug KERNEL_DEBUG ("  JS var: " ++ show name1 ++ " -> " ++ show name2)
      CanopyField name ->
        Logger.debug KERNEL_DEBUG ("  Canopy field: " ++ show name)
      JsField idx ->
        Logger.debug KERNEL_DEBUG ("  JS field: " ++ show idx)
      JsEnum idx ->
        Logger.debug KERNEL_DEBUG ("  JS enum: " ++ show idx)
      Debug ->
        Logger.debug KERNEL_DEBUG "  Debug marker"
      Prod ->
        Logger.debug KERNEL_DEBUG "  Prod marker"

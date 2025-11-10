{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | UTF-8 text file operations for the Canopy build system.
--
-- This module provides robust UTF-8 text file I/O with proper encoding
-- handling and error reporting. All operations enforce UTF-8 encoding
-- and provide detailed error messages for encoding issues.
--
-- UTF-8 files are used throughout the build system for:
--   * Source code files (.can, .canopy, .elm)
--   * Generated JavaScript output
--   * Documentation and README files
--   * Configuration files
--
-- ==== Examples
--
-- >>> content <- readUtf8 "src/Main.can"
-- >>> let processed = processSourceCode content
-- >>> writeUtf8 "build/Main.js" processed
--
-- >>> writeBuilder "output.js" (Builder.fromText jsCode)
--
-- ==== Error Handling
--
-- UTF-8 operations handle several error conditions:
--   * Invalid UTF-8 sequences (clear error messages)
--   * File access permissions (propagated)
--   * Disk space issues during writes
--   * Large file handling with chunked reads
--
-- @since 0.19.1
module File.Utf8
  ( -- * UTF-8 File Operations
    writeUtf8
  , readUtf8
  , writeBuilder
    -- * Internal Operations
  , withUtf8
  , hGetContentsSizeHint
  , useZeroIfNotRegularFile
  , encodingError
    -- * Size Calculation Helpers
  , shouldFinishReading
  , calculateNextSize
  ) where

import Control.Exception (IOException)
import GHC.IO.Exception (IOErrorType (InvalidArgument))
import qualified Control.Exception as Exception
import qualified Control.Monad as Monad
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Internal as BSInternal
import qualified Data.List as List
import qualified Foreign.ForeignPtr as FPtr
import qualified System.IO as IO
import qualified System.IO.Error as IOError

-- | Write UTF-8 content to a file.
--
-- Sets the file handle to UTF-8 encoding before writing to ensure
-- proper character encoding. The content should already be UTF-8 encoded.
--
-- >>> writeUtf8 "output.txt" (Text.encodeUtf8 "Hello, 世界!")
--
-- ==== Errors
--
-- Throws 'IOException' if:
--   * Cannot create or write to the file
--   * Insufficient permissions
--   * Disk space exhausted
writeUtf8 :: FilePath -> BS.ByteString -> IO ()
writeUtf8 path content =
  withUtf8 path IO.WriteMode (writeContentToHandle content)

-- | Write content to a UTF-8 handle.
writeContentToHandle :: BS.ByteString -> IO.Handle -> IO ()
writeContentToHandle content handle = BS.hPut handle content

-- | Execute an action with a UTF-8 encoded file handle.
--
-- Ensures the handle is set to UTF-8 encoding before executing
-- the provided action. This prevents encoding-related errors.
withUtf8 :: FilePath -> IO.IOMode -> (IO.Handle -> IO a) -> IO a
withUtf8 path mode action =
  IO.withFile path mode (executeWithUtf8Encoding action)

-- | Set UTF-8 encoding on handle and execute action.
executeWithUtf8Encoding :: (IO.Handle -> IO a) -> IO.Handle -> IO a
executeWithUtf8Encoding action handle = do
  IO.hSetEncoding handle IO.utf8
  action handle

-- | Read UTF-8 content from a file.
--
-- Reads the entire file with proper UTF-8 decoding and provides
-- helpful error messages for encoding issues. Uses chunked reading
-- for efficient memory usage with large files.
--
-- >>> content <- readUtf8 "src/Main.can"
-- >>> processCanopySource content
--
-- ==== Errors
--
-- Throws 'IOException' with enhanced error messages for:
--   * Invalid UTF-8 sequences
--   * File access errors
--   * Permission issues
readUtf8 :: FilePath -> IO BS.ByteString
readUtf8 path =
  withUtf8 path IO.ReadMode (readUtf8Content path)

-- | Read UTF-8 content from handle with size optimization.
readUtf8Content :: FilePath -> IO.Handle -> IO BS.ByteString
readUtf8Content path handle =
  IOError.modifyIOError (encodingError path) $ do
    fileSize <- Exception.catch (IO.hFileSize handle) useZeroIfNotRegularFile
    let readSize = calculateInitialReadSize fileSize
        incrementSize = calculateIncrementSize readSize
    hGetContentsSizeHint handle readSize incrementSize

-- | Calculate initial read size from file size.
calculateInitialReadSize :: Integer -> Int
calculateInitialReadSize fileSize = max 0 (fromIntegral fileSize) + 1

-- | Calculate increment size for chunked reading.
calculateIncrementSize :: Int -> Int
calculateIncrementSize readSize = max 255 readSize

-- | Handle case where file size cannot be determined.
--
-- Returns zero size for non-regular files (pipes, devices, etc.)
-- where hFileSize would fail.
useZeroIfNotRegularFile :: IOException -> IO Integer
useZeroIfNotRegularFile _ = Monad.return 0

-- | Read file contents with size hint for efficient memory allocation.
--
-- Uses chunked reading to handle large files without excessive memory
-- usage. Dynamically adjusts chunk sizes based on actual read amounts.
hGetContentsSizeHint :: IO.Handle -> Int -> Int -> IO BS.ByteString
hGetContentsSizeHint handle readSize incrementSize =
  readChunks [] readSize incrementSize
  where
    readChunks chunks currentSize increment = do
      chunk <- readSingleChunk handle currentSize
      let readCount = BS.length chunk
      if shouldFinishReading readCount currentSize
        then pure (concatenateChunks (chunk : chunks))
        else readChunks (chunk : chunks) increment (calculateNextSize currentSize increment)

-- | Read a single chunk from the handle.
readSingleChunk :: IO.Handle -> Int -> IO BS.ByteString
readSingleChunk handle size = do
  fp <- BSInternal.mallocByteString size
  readCount <- FPtr.withForeignPtr fp $ \buf -> IO.hGetBuf handle buf size
  pure (BSInternal.PS fp 0 readCount)

-- | Concatenate chunks in reverse order for efficiency.
concatenateChunks :: [BS.ByteString] -> BS.ByteString
concatenateChunks chunks = BS.concat (List.reverse chunks)

-- | Determine if reading should finish based on bytes read.
--
-- Stops reading when we read fewer bytes than requested,
-- indicating end of file.
shouldFinishReading :: Int -> Int -> Bool
shouldFinishReading readCount readSize = readCount < readSize && readSize > 0

-- | Calculate next read size for chunked reading.
--
-- Increases read size but caps at a reasonable maximum to
-- prevent excessive memory allocation.
calculateNextSize :: Int -> Int -> Int
calculateNextSize readSize incrementSize = min 32752 (readSize + incrementSize)

-- | Convert generic IOError to UTF-8 specific error.
--
-- Provides clear error messages specifically for UTF-8 encoding
-- issues while preserving other error types.
encodingError :: FilePath -> IOError -> IOError
encodingError path ioErr =
  case IOError.ioeGetErrorType ioErr of
    InvalidArgument -> createUtf8Error path
    _ -> IOError.annotateIOError 
           (IOError.userError ("UTF-8 encoding error: " ++ IOError.ioeGetErrorString ioErr))
           ""
           Nothing
           (Just path)

-- | Create UTF-8 specific error with helpful message.
createUtf8Error :: FilePath -> IOError
createUtf8Error path =
  IOError.annotateIOError
    (IOError.userError "Bad encoding; the file must be valid UTF-8")
    ""
    Nothing
    (Just path)

-- | Write a ByteString Builder to a file.
--
-- Optimized for writing generated content like JavaScript code.
-- Uses binary mode with block buffering for performance.
--
-- >>> writeBuilder "output.js" (Builder.fromText jsCode)
--
-- ==== Performance
--
-- Uses block buffering and binary mode for efficient writes
-- of large generated content.
writeBuilder :: FilePath -> Builder.Builder -> IO ()
writeBuilder path builder =
  IO.withBinaryFile path IO.WriteMode (writeBuilderToHandle builder)

-- | Write builder content to handle with optimization.
writeBuilderToHandle :: Builder.Builder -> IO.Handle -> IO ()
writeBuilderToHandle builder handle = do
  IO.hSetBuffering handle (IO.BlockBuffering Nothing)
  Builder.hPutBuilder handle builder
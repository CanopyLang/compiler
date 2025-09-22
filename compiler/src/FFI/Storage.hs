{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Global storage for FFI file contents and alias information
--
-- This module provides shared storage for FFI JavaScript file contents
-- that are read during canonicalization and used during generation.
-- Now includes proper alias tracking to fix namespace generation.
--
-- @since 0.19.1
module FFI.Storage
  ( FFIInfo(..)
  , storeFFIContent
  , storeFFIInfo
  , getStoredFFIContent
  , getStoredFFIInfo
  , clearFFIContent
  ) where

import qualified Data.Map.Strict as Map
import Data.Map (Map)
import Data.IORef (IORef, newIORef, modifyIORef', readIORef, writeIORef)
import qualified System.IO.Unsafe

-- | Information about an FFI import
data FFIInfo = FFIInfo
  { ffiFilePath :: !String    -- ^ Path to the JavaScript file
  , ffiContent  :: !String    -- ^ Content of the JavaScript file
  , ffiAlias    :: !String    -- ^ Alias used in the import statement
  } deriving (Eq, Show)

-- | Global storage for FFI file contents (legacy compatibility)
{-# NOINLINE ffiContentStore #-}
ffiContentStore :: IORef (Map String String)
ffiContentStore = System.IO.Unsafe.unsafePerformIO (newIORef Map.empty)

-- | Global storage for FFI information with aliases
{-# NOINLINE ffiInfoStore #-}
ffiInfoStore :: IORef (Map String FFIInfo)
ffiInfoStore = System.IO.Unsafe.unsafePerformIO (newIORef Map.empty)

-- | Store FFI content for later use in generation (legacy compatibility)
storeFFIContent :: String -> String -> IO ()
storeFFIContent filePath content = do
  modifyIORef' ffiContentStore (Map.insert filePath content)

-- | Store FFI information including alias for proper namespace generation
storeFFIInfo :: String -> String -> String -> IO ()
storeFFIInfo filePath content alias = do
  let ffiInfo = FFIInfo filePath content alias
  modifyIORef' ffiInfoStore (Map.insert filePath ffiInfo)
  -- Also store in legacy format for compatibility
  storeFFIContent filePath content

-- | Get stored FFI content from canonicalization phase (legacy compatibility)
getStoredFFIContent :: IO (Map String String)
getStoredFFIContent = readIORef ffiContentStore

-- | Get stored FFI information with aliases
getStoredFFIInfo :: IO (Map String FFIInfo)
getStoredFFIInfo = readIORef ffiInfoStore

-- | Clear all stored FFI content
clearFFIContent :: IO ()
clearFFIContent = do
  writeIORef ffiContentStore Map.empty
  writeIORef ffiInfoStore Map.empty
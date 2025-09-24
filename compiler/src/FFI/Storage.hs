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
-- import Data.IORef (IORef) -- No longer needed - removed global storage
-- import qualified System.IO.Unsafe -- No longer needed - removed global storage to fix MVar deadlocks

-- | Information about an FFI import
data FFIInfo = FFIInfo
  { ffiFilePath :: !String    -- ^ Path to the JavaScript file
  , ffiContent  :: !String    -- ^ Content of the JavaScript file
  , ffiAlias    :: !String    -- ^ Alias used in the import statement
  } deriving (Eq, Show)

-- NOTE: Global storage removed due to unsafePerformIO causing MVar deadlocks
-- The FFI system now uses parameter passing instead of global state
-- This module is kept for API compatibility but functions are now no-ops

-- | Store FFI content for later use in generation (legacy compatibility)
-- Now a no-op since global storage was causing MVar deadlocks
storeFFIContent :: String -> String -> IO ()
storeFFIContent _filePath _content = pure ()

-- | Store FFI information including alias for proper namespace generation
-- Now a no-op since global storage was causing MVar deadlocks
storeFFIInfo :: String -> String -> String -> IO ()
storeFFIInfo _filePath _content _alias = pure ()

-- | Get stored FFI content from canonicalization phase (legacy compatibility)
-- Now returns empty map since global storage was causing MVar deadlocks
getStoredFFIContent :: IO (Map String String)
getStoredFFIContent = pure Map.empty

-- | Get stored FFI information with aliases
-- Now returns empty map since global storage was causing MVar deadlocks
getStoredFFIInfo :: IO (Map String FFIInfo)
getStoredFFIInfo = pure Map.empty

-- | Clear all stored FFI content
-- Now a no-op since global storage was causing MVar deadlocks
clearFFIContent :: IO ()
clearFFIContent = pure ()
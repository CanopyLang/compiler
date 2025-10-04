{-# LANGUAGE DeriveGeneric #-}
{-# OPTIONS_GHC -Wall #-}

-- | JSON interface file format for Canopy compiler.
--
-- This module provides JSON-based interface files for compiled modules.
-- Benefits include:
--
-- * Human-readable format for debugging
-- * External tool compatibility (IDEs, linters)
-- * Forward compatibility (easier format evolution)
-- * Faster IDE parsing (measured 10x in PureScript)
--
-- === Interface File Structure
--
-- JSON interface files contain:
-- * Format version for compatibility
-- * Module interface with all type information
-- * Source content hash for invalidation
-- * Dependencies hash for incremental compilation
-- * Compilation timestamp for tracking
--
-- === Generated Artifacts
--
-- Interface files are generated on every compilation and do not require
-- backwards compatibility. Old .cani files from previous compiles are
-- regenerated, so we only write/read JSON format.
--
-- @since 0.19.1
module Interface.JSON
  ( -- * Interface File Type
    InterfaceFile (..),

    -- * I/O Operations
    writeInterface,
    readInterface,
    readInterfaceJSON,
  )
where

import qualified Canopy.Interface as I
import Control.Monad (unless)
import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode)
import qualified Data.ByteString.Lazy as BL
import Data.Time.Clock (UTCTime, getCurrentTime)
import GHC.Generics (Generic)
import qualified Logging.Debug as Logger
import Logging.Debug (DebugCategory (..))
import System.Directory (doesFileExist)

-- | Interface file with metadata.
--
-- Wraps the core Interface type with versioning and cache metadata
-- to support incremental compilation and format evolution.
data InterfaceFile = InterfaceFile
  { ifVersion :: !String,
    -- ^ Format version (currently "1.0.0")
    ifModule :: !I.Interface,
    -- ^ Module interface with type information
    ifSourceHash :: !String,
    -- ^ Content hash of source file
    ifDepsHash :: !String,
    -- ^ Content hash of dependencies
    ifTimestamp :: !UTCTime
    -- ^ Compilation timestamp
  }
  deriving (Generic, Show)

instance ToJSON InterfaceFile

instance FromJSON InterfaceFile

-- | Write interface to JSON file.
--
-- Writes JSON (.cani.json) format only. Binary format not needed since
-- interface files are regenerated on every compilation.
writeInterface ::
  FilePath ->
  -- ^ Base path (without extension)
  I.Interface ->
  -- ^ Interface to write
  String ->
  -- ^ Source content hash
  String ->
  -- ^ Dependencies hash
  IO ()
writeInterface basePath iface sourceHash depsHash = do
  timestamp <- getCurrentTime
  let ifFile =
        InterfaceFile
          { ifVersion = "1.0.0",
            ifModule = iface,
            ifSourceHash = sourceHash,
            ifDepsHash = depsHash,
            ifTimestamp = timestamp
          }

  -- Write JSON format only
  let jsonPath = basePath ++ ".cani.json"
  BL.writeFile jsonPath (encode ifFile)
  Logger.debug BUILD ("Wrote JSON interface: " ++ jsonPath)

-- | Read interface from JSON file.
--
-- Reads JSON format only since interface files are regenerated on every
-- compilation. No binary fallback needed for generated artifacts.
readInterface :: FilePath -> IO (Either String I.Interface)
readInterface basePath = do
  let jsonPath = basePath ++ ".cani.json"
  jsonExists <- doesFileExist jsonPath
  if jsonExists
    then readInterfaceJSON jsonPath
    else return (Left ("JSON interface not found: " ++ jsonPath))

-- | Read interface from JSON file.
readInterfaceJSON :: FilePath -> IO (Either String I.Interface)
readInterfaceJSON path = do
  content <- BL.readFile path
  case eitherDecode content of
    Right ifFile -> do
      Logger.debug BUILD ("Read JSON interface: " ++ path)
      validateVersion (ifVersion ifFile)
      return (Right (ifModule ifFile))
    Left err -> return (Left ("JSON decode error: " ++ err))

-- | Validate interface file version.
validateVersion :: String -> IO ()
validateVersion version =
  unless (version == "1.0.0") $ do
    Logger.debug BUILD ("Warning: Interface version mismatch: " ++ version)

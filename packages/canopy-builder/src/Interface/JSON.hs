{-# LANGUAGE DeriveGeneric #-}

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

import qualified Canopy.Interface as Interface
import qualified Control.Monad as Monad
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as Text
import Data.Time.Clock (UTCTime)
import qualified Data.Time.Clock as Time
import GHC.Generics (Generic)
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified System.Directory as Dir

-- | Interface file with metadata.
--
-- Wraps the core Interface type with versioning and cache metadata
-- to support incremental compilation and format evolution.
data InterfaceFile = InterfaceFile
  { ifVersion :: !String,
    -- ^ Format version (currently "1.0.0")
    ifModule :: !Interface.Interface,
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
  Interface.Interface ->
  -- ^ Interface to write
  String ->
  -- ^ Source content hash
  String ->
  -- ^ Dependencies hash
  IO ()
writeInterface basePath iface sourceHash depsHash = do
  timestamp <- Time.getCurrentTime
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
  BL.writeFile jsonPath (Aeson.encode ifFile)
  Log.logEvent (InterfaceSaved jsonPath)

-- | Read interface from JSON file.
--
-- Reads JSON format only since interface files are regenerated on every
-- compilation. No binary fallback needed for generated artifacts.
readInterface :: FilePath -> IO (Either String Interface.Interface)
readInterface basePath = do
  let jsonPath = basePath ++ ".cani.json"
  jsonExists <- Dir.doesFileExist jsonPath
  if jsonExists
    then readInterfaceJSON jsonPath
    else return (Left ("JSON interface not found: " ++ jsonPath))

-- | Read interface from JSON file.
readInterfaceJSON :: FilePath -> IO (Either String Interface.Interface)
readInterfaceJSON path = do
  content <- BL.readFile path
  case Aeson.eitherDecode content of
    Right ifFile -> do
      Log.logEvent (InterfaceLoaded path)
      validateVersion (ifVersion ifFile)
      return (Right (ifModule ifFile))
    Left err -> return (Left ("JSON decode error: " ++ err))

-- | Validate interface file version.
validateVersion :: String -> IO ()
validateVersion version =
  Monad.unless (version == "1.0.0") $ do
    Log.logEvent (BuildFailed (Text.pack ("Interface version mismatch: " ++ version)))

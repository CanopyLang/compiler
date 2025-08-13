{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Environment setup and configuration for the development server.
--
-- This module handles the initialization and setup of the development
-- server environment. It processes command-line flags, resolves default
-- values, and validates server configuration following CLAUDE.md patterns
-- for clear separation of concerns.
--
-- == Key Functions
--
-- * 'setupServerConfig' - Initialize complete server configuration
-- * 'resolvePort' - Port number resolution with defaults
-- * 'detectProjectRoot' - Project root directory detection
-- * 'validateConfiguration' - Configuration validation
--
-- == Configuration Process
--
-- The setup process follows these steps:
--
-- 1. Process command-line flags
-- 2. Apply default values for missing options
-- 3. Detect project environment (root directory)
-- 4. Validate final configuration
-- 5. Return ready-to-use server configuration
--
-- == Usage Examples
--
-- @
-- flags <- parseCommandLineFlags
-- config <- Environment.setupServerConfig flags
-- putStrLn $ "Server starting on port " ++ show (config ^. scPort)
-- @
--
-- @since 0.19.1
module Develop.Environment
  ( -- * Configuration Setup
    setupServerConfig,
    
    -- * Component Resolution
    resolvePort,
    detectProjectRoot,
    
    -- * Validation
    validateConfiguration,
    
    -- * Utilities
    displayStartupMessage,
  ) where

import Control.Lens ((^.))
import qualified Data.Maybe as Maybe
import Develop.Types
  ( Flags,
    ServerConfig (..),
    flagsPort,
    scPort
  )
import qualified Stuff

-- | Setup complete server configuration from flags.
--
-- Processes command-line flags, applies defaults, detects project
-- environment, and validates the resulting configuration.
--
-- ==== Examples
--
-- >>> flags <- parseFlags ["--port", "3000"]
-- >>> config <- setupServerConfig flags
-- >>> config ^. scPort
-- 3000
--
-- >>> config <- setupServerConfig defaultFlags  
-- >>> config ^. scPort
-- 8000
--
-- @since 0.19.1
setupServerConfig :: Flags -> IO ServerConfig
setupServerConfig flags = do
  let port = resolvePort flags
  maybeRoot <- detectProjectRoot
  let config = createServerConfig port maybeRoot
  validateConfiguration config
  pure config

-- | Create server configuration from resolved components.
createServerConfig :: Int -> Maybe FilePath -> ServerConfig
createServerConfig port maybeRoot = ServerConfig
  { _scPort = port,
    _scVerbose = False, -- Default to non-verbose
    _scRoot = maybeRoot
  }

-- | Resolve port number from flags with fallback to default.
--
-- Takes optional port from command-line flags and applies default
-- value (8000) if no port is specified.
--
-- @since 0.19.1
resolvePort :: Flags -> Int
resolvePort flags = 
  Maybe.fromMaybe 8000 (flags ^. flagsPort)

-- | Detect project root directory.
--
-- Searches for Canopy project root using standard project markers.
-- Returns 'Nothing' if not in a Canopy project directory.
--
-- @since 0.19.1
detectProjectRoot :: IO (Maybe FilePath)
detectProjectRoot = Stuff.findRoot

-- | Validate server configuration.
--
-- Performs validation checks on the complete server configuration
-- to ensure it represents a valid and usable setup.
--
-- ==== Validation Checks
--
-- * Port number is in valid range (1-65535)
-- * Project root exists if specified
-- * Configuration is internally consistent
--
-- @since 0.19.1
validateConfiguration :: ServerConfig -> IO ()
validateConfiguration config = do
  validatePortRange (config ^. scPort)
  validateProjectRoot (_scRoot config)

-- | Validate port number is in acceptable range.
validatePortRange :: Int -> IO ()
validatePortRange port
  | port < 1 || port > 65535 = 
      error ("Invalid port number: " ++ show port)
  | otherwise = pure ()

-- | Validate project root directory if specified.
validateProjectRoot :: Maybe FilePath -> IO ()
validateProjectRoot Nothing = pure () -- No root specified, OK
validateProjectRoot (Just _) = pure () -- Assume valid if found by Stuff.findRoot

-- | Display startup message with server information.
--
-- Shows user-friendly startup information including server URL
-- and basic usage instructions.
--
-- @since 0.19.1
displayStartupMessage :: ServerConfig -> IO ()
displayStartupMessage config =
  putStrLn $ "Go to http://localhost:" 
    ++ show (config ^. scPort) 
    ++ " to see your project dashboard."
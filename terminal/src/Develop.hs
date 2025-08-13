{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Development server for live Canopy code editing and testing.
--
-- This module provides the main development server functionality for Canopy
-- projects. It serves compiled Canopy code, static assets, provides live
-- reloading, and offers a complete development environment following CLAUDE.md
-- patterns for modular architecture and clear separation of concerns.
--
-- == Key Features
--
-- * Live compilation and serving of Canopy source files
-- * Hot reloading with WebSocket-based file watching  
-- * Static asset serving with comprehensive MIME type support
-- * Directory browsing with custom index pages
-- * Error reporting with rich diagnostics
--
-- == Architecture
--
-- The development server is built from specialized sub-modules:
--
-- * 'Develop.Types' - Core types and configuration data structures
-- * 'Develop.Environment' - Environment setup and configuration
-- * 'Develop.Server' - HTTP server and routing logic
-- * 'Develop.Compilation' - Canopy source file compilation
-- * 'Develop.Socket' - WebSocket-based file watching
-- * 'Develop.StaticFiles' - Static asset management
-- * 'Develop.MimeTypes' - MIME type detection and serving
--
-- == Usage Examples
--
-- @
-- -- Start development server on default port (8000)
-- flags <- parseFlags []
-- Develop.run () flags
--
-- -- Start on custom port
-- flags <- parseFlags ["--port", "3000"]  
-- Develop.run () flags
-- @
--
-- == Configuration
--
-- The server accepts configuration through command-line flags:
--
-- * @--port@ - Custom port number (default: 8000)
--
-- @since 0.19.1
module Develop
  ( -- * Types
    Flags (..),
    
    -- * Main Interface
    run,
  ) where

import qualified Develop.Environment as Environment
import qualified Develop.Server as Server
import Develop.Types (Flags (..))

-- | Main entry point for the development server.
--
-- Initializes the complete development environment, starts the HTTP server,
-- and displays user-friendly startup information. Blocks until the server
-- is shut down or encounters an error.
--
-- The startup process:
--
-- 1. Process command-line flags and resolve configuration
-- 2. Display startup message with server URL
-- 3. Initialize and start the HTTP server with full routing
-- 4. Block until shutdown or error
--
-- ==== Examples
--
-- >>> flags <- parseFlags ["--port", "3000"]
-- >>> run () flags
-- Go to http://localhost:3000 to see your project dashboard.
-- -- Server starts and blocks
--
-- >>> run () (Flags Nothing)  
-- Go to http://localhost:8000 to see your project dashboard.
-- -- Server starts on default port
--
-- ==== Error Conditions
--
-- Server startup can fail for:
--   * Invalid port numbers (< 1 or > 65535)
--   * Port already in use by another process
--   * Insufficient system permissions
--   * Network configuration issues
--
-- @since 0.19.1
run :: () -> Flags -> IO ()
run () flags = do
  config <- Environment.setupServerConfig flags
  Environment.displayStartupMessage config
  Server.startServer config

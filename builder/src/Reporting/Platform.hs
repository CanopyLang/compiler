{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Platform - Platform compatibility utilities for Canopy terminal output
--
-- This module provides platform-specific utilities for terminal output,
-- ensuring consistent visual presentation across different operating systems
-- and terminal capabilities. It handles character encoding differences,
-- Unicode support variations, and platform-specific terminal behaviors.
--
-- == Platform Detection
--
-- The module automatically detects the target platform and provides appropriate
-- fallbacks for systems with limited Unicode support, particularly Windows
-- terminals that may not properly render Unicode box-drawing characters.
--
-- == Character Adaptation Strategy
--
-- * **Unix Systems** - Full Unicode support with proper box-drawing characters
-- * **Windows Systems** - ASCII fallbacks for broader terminal compatibility
-- * **Terminal Capabilities** - Graceful degradation for limited terminals
--
-- == Supported Characters
--
-- The module provides platform-appropriate characters for:
--
-- * Success/failure indicators (●/+, ✗/X)
-- * Progress indicators and visual separators
-- * Box drawing for ASCII diagrams
-- * Status markers for build output
--
-- == Usage Examples
--
-- === Success and Failure Indicators
--
-- @
-- -- Show success indicator (● on Unix, + on Windows)
-- putStrLn $ show goodMark <> " Package downloaded successfully"
-- 
-- -- Show failure indicator (✗ on Unix, X on Windows)  
-- putStrLn $ show badMark <> " Package download failed"
-- @
--
-- === Platform-Aware Character Selection
--
-- @
-- -- Choose appropriate characters based on platform
-- let separator = if isWindows then '-' else '─'
-- let junction = if isWindows then '+' else '┬'
-- putStrLn $ replicate 50 separator
-- @
--
-- == Terminal Compatibility
--
-- The fallback characters are selected to work correctly across a wide range
-- of terminal emulators and console implementations, including:
--
-- * Windows Command Prompt
-- * Windows PowerShell
-- * MinGW/MSYS terminals
-- * Legacy terminal emulators
-- * Console applications with limited Unicode support
--
-- @since 0.19.1
module Reporting.Platform
  ( -- * Platform Detection
    isWindows
    -- * Visual Indicators
  , goodMark
  , badMark
    -- * Box Drawing Characters
  , hbar
  , vtop
  , vmiddle
  , vbottom
  ) where

import qualified Reporting.Doc as D
import qualified System.Info as Info

-- | Detect Windows platform for terminal compatibility.
--
-- Determines if the current platform is Windows to enable appropriate
-- fallback characters for terminals that don't support Unicode drawing
-- characters properly.
--
-- ==== Examples
--
-- @
-- char = if isWindows then '-' else '─'  -- Horizontal line
-- symbol = if isWindows then "+" else "●"  -- Success marker
-- @
--
-- @since 0.19.1
isWindows :: Bool
isWindows =
  Info.os == "mingw32"

-- | Success indicator mark for terminal output.
--
-- Displays a green success symbol that adapts to platform capabilities.
-- Uses Unicode bullet (●) on Unix systems and plus (+) on Windows for
-- better terminal compatibility.
--
-- Used to indicate successful operations like package downloads, compilation
-- steps, or dependency resolution.
--
-- @since 0.19.1
goodMark :: D.Doc
goodMark =
  D.green $ if isWindows then "+" else "●"

-- | Failure indicator mark for terminal output.
--
-- Displays a red failure symbol that adapts to platform capabilities.
-- Uses Unicode cross (✗) on Unix systems and X on Windows for
-- better terminal compatibility.
--
-- Used to indicate failed operations like download errors, compilation
-- failures, or dependency conflicts.
--
-- @since 0.19.1
badMark :: D.Doc
badMark =
  D.red $ if isWindows then "X" else "✗"

-- | Horizontal bar character for diagram drawing.
--
-- Uses Unicode box-drawing character (─) on Unix systems and hyphen (-)
-- on Windows for better terminal compatibility.
--
-- @since 0.19.1
hbar :: Char
hbar = if isWindows then '-' else '─'

-- | Top junction character for diagram drawing.
--
-- Uses Unicode box-drawing character (┬) on Unix systems and plus (+)
-- on Windows for better terminal compatibility.
--
-- @since 0.19.1
vtop :: Char
vtop = if isWindows then '+' else '┬'

-- | Middle junction character for diagram drawing.
--
-- Uses Unicode box-drawing character (┤) on Unix systems and plus (+)
-- on Windows for better terminal compatibility.
--
-- @since 0.19.1
vmiddle :: Char
vmiddle = if isWindows then '+' else '┤'

-- | Bottom junction character for diagram drawing.
--
-- Uses Unicode box-drawing character (┘) on Unix systems and plus (+)
-- on Windows for better terminal compatibility.
--
-- @since 0.19.1
vbottom :: Char
vbottom = if isWindows then '+' else '┘'
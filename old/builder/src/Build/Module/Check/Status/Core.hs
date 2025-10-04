{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core status processing functions for module checking.
--
-- This module contains the basic status processing functions for simple
-- status types that don't require complex dependency handling.
-- These are the elementary status processors following CLAUDE.md standards.
--
-- === Core Status Types
--
-- @
-- Simple Status Types:
-- ├── SBadImport   -> processBadImportStatus
-- ├── SBadSyntax   -> processBadSyntaxStatus
-- ├── SForeign     -> processForeignStatus
-- └── SKernel      -> processKernelStatus
-- @
--
-- === Usage Examples
--
-- @
-- -- Process bad import status
-- result <- processBadImportStatus importProblem
--
-- -- Process syntax error status
-- result <- processBadSyntaxStatus moduleName path time source error
--
-- -- Process foreign module status
-- result <- processForeignStatus dependencies packageName moduleName
-- @
--
-- === Error Handling
--
-- Core status processing handles these error types:
--
-- * Import resolution failures
-- * Syntax parsing errors
-- * Foreign module lookup failures
-- * Kernel module identification
--
-- All processors return appropriate 'Result' values.
--
-- @since 0.19.1
module Build.Module.Check.Status.Core
  ( -- * Core Status Processors
    processBadImportStatus,
    processBadSyntaxStatus,
    processForeignStatus,
    processKernelStatus,
  )
where

import Build.Types
  ( Dependencies,
    Result (..),
  )
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString as B
import qualified Data.Map.Strict as Map
import qualified File
import qualified Reporting.Error as Error
import qualified Reporting.Error.Import as Import
import qualified Reporting.Error.Syntax as Syntax

-- | Process bad import status.
--
-- Handles modules with import resolution problems by creating appropriate
-- error results.
--
-- ==== Parameters
--
-- [@importProblem@] The specific import problem encountered
--
-- ==== Returns
--
-- IO action producing a 'RNotFound' result with the import problem
processBadImportStatus :: Import.Problem -> IO Result
processBadImportStatus importProblem = pure (RNotFound importProblem)

-- | Process bad syntax status.
--
-- Handles modules with syntax errors by creating error results with
-- detailed syntax error information.
--
-- ==== Parameters
--
-- [@name@] Module name with syntax error
-- [@path@] File path of the module
-- [@time@] File modification time
-- [@source@] Module source code
-- [@err@] Specific syntax error
--
-- ==== Returns
--
-- IO action producing a 'RProblem' result with syntax error details
processBadSyntaxStatus :: ModuleName.Raw -> FilePath -> File.Time -> B.ByteString -> Syntax.Error -> IO Result
processBadSyntaxStatus name path time source err =
  pure . RProblem $ Error.Module name path time source (Error.BadSyntax err)

-- | Process foreign module status.
--
-- Handles foreign modules by looking up their interfaces in the dependency
-- table and returning appropriate results.
--
-- ==== Parameters
--
-- [@foreigns@] Foreign module dependencies lookup table
-- [@home@] Package name containing the module
-- [@name@] Module name to look up
--
-- ==== Returns
--
-- IO action producing a 'RForeign' result with the module interface
processForeignStatus :: Dependencies -> Pkg.Name -> ModuleName.Raw -> IO Result
processForeignStatus foreigns home name =
  let canonical = ModuleName.Canonical home name
      availableKeys = Map.keys foreigns
      debugInfo =
        "Looking for: " <> show canonical
          <> ", Available: "
          <> show (take 10 availableKeys)
          <> " (showing first 10 of "
          <> show (length availableKeys)
          <> " total)"
   in case foreigns Map.!? canonical of
        Just (I.Public iface) -> pure (RForeign iface)
        Just (I.Private {}) ->
          error ("mistakenly seeing private interface for " <> (Pkg.toChars home) <> " " <> (ModuleName.toChars name) <> " " <> show debugInfo)
        Nothing ->
          error ("couldn't find module in lookup table" <> (Pkg.toChars home) <> " " <> (ModuleName.toChars name) <> " " <> show debugInfo)

-- | Process kernel module status.
--
-- Handles kernel modules by returning a kernel result. Kernel modules
-- require no additional processing.
--
-- ==== Returns
--
-- IO action producing a 'RKernel' result
processKernelStatus :: IO Result
processKernelStatus = pure RKernel

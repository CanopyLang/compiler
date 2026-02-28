{-# LANGUAGE OverloadedStrings #-}

-- | Filesystem path validation for security-sensitive operations.
--
-- This module provides reusable path validation that rejects common
-- filesystem attack vectors: directory traversal via @..@, absolute
-- path escapes, and null byte injection.
--
-- Used by both the HTTP file:\/\/ URL handler and the FFI path
-- validator to enforce consistent security checks across the
-- entire codebase.
--
-- == When to Use
--
-- Apply 'validatePath' whenever a user-supplied or externally-sourced
-- string is used as a filesystem path. This includes:
--
-- * @file:\/\/@ URLs in package references
-- * FFI source file paths in module headers
-- * Any path extracted from untrusted JSON or network responses
--
-- @since 0.19.2
module Canopy.PathValidation
  ( -- * Validation
    validatePath,

    -- * Error Type
    PathError (..),
  )
where

import qualified System.FilePath as FP

-- | Errors detected during filesystem path validation.
--
-- Each variant carries the offending path for inclusion in
-- error messages.
--
-- @since 0.19.2
data PathError
  = -- | The path is absolute (e.g. @\/etc\/passwd@).
    PathAbsolute !FilePath
  | -- | The path contains @..@ components allowing directory traversal.
    PathTraversal !FilePath
  | -- | The path contains a null byte, which can truncate C-level
    -- path operations.
    PathNullByte !FilePath
  deriving (Eq, Show)

-- | Validate a filesystem path for common attack vectors.
--
-- Rejects:
--
-- * Absolute paths (prevents reading arbitrary system files)
-- * Paths containing @..@ (prevents directory traversal)
-- * Paths containing null bytes (prevents C-string truncation)
--
-- On success, returns the normalised path with redundant
-- separators and @.@ components removed.
--
-- @since 0.19.2
validatePath :: FilePath -> Either PathError FilePath
validatePath path
  | FP.isAbsolute path = Left (PathAbsolute path)
  | ".." `elem` FP.splitDirectories path = Left (PathTraversal path)
  | '\0' `elem` path = Left (PathNullByte path)
  | otherwise = Right (FP.normalise path)

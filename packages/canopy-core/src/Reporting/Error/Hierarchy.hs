{-# LANGUAGE OverloadedStrings #-}

-- | Unified error type hierarchy for the Canopy compiler.
--
-- Provides a top-level classification of all errors that can occur
-- during compilation and build operations.  This module does not
-- replace the existing per-phase error types in "Reporting.Error"
-- and "Reporting.Exit"; instead it defines a taxonomy that groups
-- them into coherent categories.
--
-- == Error Categories
--
-- 1. **Compiler errors** -- errors that arise during source
--    compilation (parsing, name resolution, type checking,
--    optimization, code generation).
--
-- 2. **Build errors** -- errors during the build pipeline
--    (dependency resolution, caching, file I/O).
--
-- 3. **CLI errors** -- errors from the terminal interface
--    (argument parsing, configuration).
--
-- 4. **FFI errors** -- errors during foreign function interface
--    validation and resolution.
--
-- == Structured Error Newtypes
--
-- This module also exports error newtypes that replace bare
-- @Either String@ usages throughout the codebase.  Each newtype
-- carries enough context for a helpful error message.
--
-- @since 0.19.2
module Reporting.Error.Hierarchy
  ( -- * Top-Level Error Categories
    CompilerError (..),
    BuildError (..),

    -- * Structured Error Newtypes
    OutlineError (..),
    CacheError (..),
    InterfaceError (..),
    FileIOError (..),
    ParseIOError (..),
  )
where

import qualified Data.Text as Text

-- | Errors arising during source compilation.
--
-- Each constructor wraps the per-phase error type from the
-- corresponding @Reporting.Error.*@ module.  This union type
-- enables functions that need to handle any compiler error
-- uniformly.
--
-- @since 0.19.2
data CompilerError
  = -- | Syntax error during parsing.
    SyntaxPhaseError !Text.Text
  | -- | Error during name resolution and canonicalization.
    CanonicalizePhaseError !Text.Text
  | -- | Error during type checking.
    TypePhaseError !Text.Text
  | -- | Error during optimization.
    OptimizePhaseError !Text.Text
  | -- | Error during code generation.
    GeneratePhaseError !Text.Text
  | -- | Error during FFI validation.
    FFIPhaseError !Text.Text
  deriving (Eq, Show)

-- | Errors arising during the build pipeline.
--
-- Groups dependency, cache, and I/O errors that occur outside
-- the per-module compilation phases.
--
-- @since 0.19.2
data BuildError
  = -- | A compilation error wrapped as a build error.
    CompileError !CompilerError
  | -- | Dependency resolution failure.
    DependencyError !Text.Text
  | -- | Cache read/write failure.
    BuildCacheError !CacheError
  | -- | File system I/O failure during build.
    BuildIOError !FileIOError
  deriving (Eq, Show)

-- | Errors when reading or validating a project outline (@canopy.json@).
--
-- Replaces @Either String Outline@ usages with a structured type
-- that carries the file path and a description of what went wrong.
--
-- @since 0.19.2
data OutlineError
  = -- | The outline file could not be read from disk.
    OutlineReadError !FilePath !Text.Text
  | -- | The outline file contains invalid JSON.
    OutlineDecodeError !FilePath !Text.Text
  | -- | The outline file is structurally valid but contains
    --   invalid field values (e.g., bad version constraints).
    OutlineValidationError !FilePath !Text.Text
  deriving (Eq, Show)

-- | Errors when reading or writing the build cache.
--
-- Replaces @Either String@ usages in cache operations with a
-- type that identifies the cache path and failure mode.
--
-- @since 0.19.2
data CacheError
  = -- | A cached artifact could not be read (corrupted or
    --   incompatible version).
    CacheReadError !FilePath !Text.Text
  | -- | A cached artifact could not be written to disk.
    CacheWriteError !FilePath !Text.Text
  | -- | The cache version does not match the current compiler.
    CacheVersionMismatch !FilePath !Text.Text !Text.Text
  deriving (Eq, Show)

-- | Errors when reading or decoding compiler interface files.
--
-- Replaces @Either String Interface@ usages with a type that
-- identifies the interface file and the decoding failure.
--
-- @since 0.19.2
data InterfaceError
  = -- | The interface file could not be read from disk.
    InterfaceReadError !FilePath !Text.Text
  | -- | The interface file could not be decoded (binary format
    --   mismatch or corruption).
    InterfaceDecodeError !FilePath !Text.Text
  deriving (Eq, Show)

-- | Errors during file I/O operations.
--
-- Replaces @Either String ()@ and @IOException@ catching patterns
-- with a structured type.
--
-- @since 0.19.2
data FileIOError
  = -- | A file could not be read.
    FileReadError !FilePath !Text.Text
  | -- | A file could not be written.
    FileWriteError !FilePath !Text.Text
  | -- | A file copy operation failed.
    FileCopyError !FilePath !FilePath !Text.Text
  deriving (Eq, Show)

-- | Errors during I/O-based parsing operations.
--
-- Replaces @Either String [a]@ patterns where parsing a file from
-- disk can fail due to I/O or parse errors.
--
-- @since 0.19.2
data ParseIOError
  = -- | The source file could not be read from disk.
    ParseFileReadError !FilePath !Text.Text
  | -- | The source file was read but could not be parsed.
    ParseFileParseError !FilePath !Text.Text
  deriving (Eq, Show)

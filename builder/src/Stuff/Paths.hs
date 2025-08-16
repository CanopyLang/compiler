{-# OPTIONS_GHC -Wall #-}

-- | Path construction and manipulation for Canopy compiler artifacts.
--
-- This module provides comprehensive path construction functionality for the
-- Canopy compiler build system. It handles the organization of compiler
-- artifacts, temporary files, and module-specific files with consistent
-- naming conventions and directory structures.
--
-- The path construction system uses version-specific directories to ensure
-- proper isolation between different compiler versions and avoid cache
-- conflicts between vanilla Canopy and Zokka compilers.
--
-- == Key Features
--
-- * **Version-Isolated Paths** - All artifacts stored in version-specific directories
-- * **Consistent Naming** - Standardized file naming and directory structure
-- * **Module Support** - Path construction for module-specific artifacts
-- * **Temporary Files** - Structured temporary file management
-- * **Extension Support** - Flexible file extension handling
--
-- == Path Structure
--
-- All paths follow the pattern:
--
-- @
-- PROJECT_ROOT/canopy-stuff/COMPILER_VERSION-canopy/ARTIFACT
-- @
--
-- Where:
-- * @PROJECT_ROOT@ is the project directory
-- * @COMPILER_VERSION@ is the current compiler version (e.g., "0.19.1")
-- * @ARTIFACT@ is the specific file or directory name
--
-- == Usage Examples
--
-- === Basic Artifact Paths
--
-- @
-- -- Get core compiler artifact paths
-- let detailsPath = details "/home/user/myproject"
--     interfacesPath = interfaces "/home/user/myproject"
--     objectsPath = objects "/home/user/myproject"
-- @
--
-- === Module-Specific Paths
--
-- @
-- -- Get paths for module artifacts
-- let mainInterface = canopyi "/project" (ModuleName.fromChars "Main")
--     mainObject = canopyo "/project" (ModuleName.fromChars "Main")
-- @
--
-- === Temporary Files
--
-- @
-- -- Create temporary file paths
-- let jsTemp = temp "/project" "js"
--     htmlTemp = temp "/project" "html"
-- @
--
-- == Thread Safety
--
-- All path construction functions are pure and thread-safe. They perform
-- simple string operations without file system access or shared state.
--
-- @since 0.19.1
module Stuff.Paths
  ( -- * Base Path Construction
    stuff
  , compilerVersion
    -- * Compiler Artifact Paths
  , details
  , interfaces
  , objects
  , prepublishDir
    -- * Module Artifact Paths
  , canopyi
  , canopyo
  , toArtifactPath
    -- * Temporary File Paths
  , temp
  ) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Version as V
import System.FilePath ((<.>), (</>))

-- | Construct the base compiler artifacts directory path.
--
-- Creates a version-specific directory for storing all compiler artifacts.
-- Uses "canopy-stuff" with a custom version suffix to maintain isolation
-- between different compiler versions and avoid cache conflicts between
-- vanilla Canopy and Zokka compilers.
--
-- The custom version suffix ensures that:
--
-- * Zokka dependency overrides don't corrupt vanilla Canopy caches
-- * Different compiler versions maintain separate artifact storage
-- * Timestamp-based rebuild detection works correctly
-- * Cache invalidation is handled properly across compiler switches
--
-- ==== Examples
--
-- >>> stuff "/home/user/myproject"
-- "/home/user/myproject/canopy-stuff/0.19.1-canopy"
--
-- >>> stuff "."
-- "./canopy-stuff/0.19.1-canopy"
--
-- @since 0.19.1
stuff :: FilePath -> FilePath
stuff root =
  root </> "canopy-stuff" </> customCompilerVersion
  where
    customCompilerVersion = compilerVersion <> "-canopy"

-- | Get the current compiler version as a string.
--
-- Retrieves the version identifier for the current compiler, used in
-- path construction to ensure version isolation. This version comes
-- from the Canopy.Version module and represents the compiler's release version.
--
-- ==== Examples
--
-- >>> compilerVersion
-- "0.19.1"
--
-- @since 0.19.1
compilerVersion :: FilePath
compilerVersion =
  V.toChars V.compiler

-- | Get the path to the project details cache file.
--
-- The details file stores serialized project information including
-- dependency resolution, module discovery results, and build metadata.
-- This file is used to determine if rebuilding is necessary based on
-- changes to project configuration or source files.
--
-- ==== Examples
--
-- >>> details "/home/user/myproject"
-- "/home/user/myproject/canopy-stuff/0.19.1-canopy/d.dat"
--
-- @since 0.19.1
details :: FilePath -> FilePath
details root =
  stuff root </> "d.dat"

-- | Get the path to the compiled interfaces cache file.
--
-- The interfaces file stores serialized module interfaces containing
-- type signatures, exports, and other information needed for compilation
-- of dependent modules. This enables incremental compilation by avoiding
-- re-parsing of unchanged dependencies.
--
-- ==== Examples
--
-- >>> interfaces "/home/user/myproject"
-- "/home/user/myproject/canopy-stuff/0.19.1-canopy/i.dat"
--
-- @since 0.19.1
interfaces :: FilePath -> FilePath
interfaces root =
  stuff root </> "i.dat"

-- | Get the path to the compiled objects cache file.
--
-- The objects file stores serialized compiled code objects that can be
-- linked together during the final code generation phase. This allows
-- for efficient incremental compilation by reusing previously compiled
-- modules.
--
-- ==== Examples
--
-- >>> objects "/home/user/myproject"
-- "/home/user/myproject/canopy-stuff/0.19.1-canopy/o.dat"
--
-- @since 0.19.1
objects :: FilePath -> FilePath
objects root =
  stuff root </> "o.dat"

-- | Get the path to the package prepublishing directory.
--
-- The prepublish directory is used for staging package contents before
-- publishing to a package registry. It contains the processed package
-- files, documentation, and metadata in the format expected by the
-- package registry.
--
-- ==== Examples
--
-- >>> prepublishDir "/home/user/mypackage"
-- "/home/user/mypackage/canopy-stuff/0.19.1-canopy/prepublish"
--
-- @since 0.19.1
prepublishDir :: FilePath -> FilePath
prepublishDir root =
  stuff root </> "prepublish"

-- | Get the path to a module's interface file (.canopyi).
--
-- Interface files contain the public API information for a module,
-- including type signatures, exported values, and other metadata
-- needed for type checking and compilation of importing modules.
-- The file uses a hyphenated path format based on the module name.
--
-- ==== Examples
--
-- >>> canopyi "/project" (ModuleName.fromChars "Main")
-- "/project/canopy-stuff/0.19.1-canopy/Main.canopyi"
--
-- >>> canopyi "/project" (ModuleName.fromChars "App.Utils.String")
-- "/project/canopy-stuff/0.19.1-canopy/App-Utils-String.canopyi"
--
-- @since 0.19.1
canopyi :: FilePath -> ModuleName.Raw -> FilePath
canopyi root name =
  toArtifactPath root name "canopyi"

-- | Get the path to a module's object file (.canopyo).
--
-- Object files contain the compiled representation of a module,
-- including optimized code, dependency information, and metadata
-- needed for linking and code generation. The file uses a hyphenated
-- path format based on the module name.
--
-- ==== Examples
--
-- >>> canopyo "/project" (ModuleName.fromChars "Main")
-- "/project/canopy-stuff/0.19.1-canopy/Main.canopyo"
--
-- >>> canopyo "/project" (ModuleName.fromChars "App.Utils.String")
-- "/project/canopy-stuff/0.19.1-canopy/App-Utils-String.canopyo"
--
-- @since 0.19.1
canopyo :: FilePath -> ModuleName.Raw -> FilePath
canopyo root name =
  toArtifactPath root name "canopyo"

-- | Construct artifact path for a module with given extension.
--
-- Internal helper function that builds standardized paths for module
-- artifacts. Converts module names to hyphenated file paths and adds
-- the specified file extension within the compiler's artifact directory.
--
-- ==== Examples
--
-- >>> toArtifactPath "/project" (ModuleName.fromChars "App.Utils") "canopyi"
-- "/project/canopy-stuff/0.19.1-canopy/App-Utils.canopyi"
--
-- @since 0.19.1
toArtifactPath :: FilePath -> ModuleName.Raw -> String -> FilePath
toArtifactPath root name ext =
  stuff root </> ModuleName.toHyphenPath name <.> ext

-- | Get the path to a temporary file with the given extension.
--
-- Creates a path for temporary files within the compiler's artifact
-- directory. Temporary files are used for intermediate compilation
-- results, temporary downloads, and other transient data that needs
-- to be cleaned up after compilation.
--
-- ==== Examples
--
-- >>> temp "/project" "js"
-- "/project/canopy-stuff/0.19.1-canopy/temp.js"
--
-- >>> temp "/project" "html"
-- "/project/canopy-stuff/0.19.1-canopy/temp.html"
--
-- @since 0.19.1
temp :: FilePath -> String -> FilePath
temp root ext =
  stuff root </> "temp" <.> ext
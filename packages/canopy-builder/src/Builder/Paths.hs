{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- | Type-safe file path newtypes for the Canopy build system.
--
-- Raw @FilePath@ (alias for @String@) is error-prone when multiple paths
-- are passed to the same function — the compiler cannot catch swapped
-- arguments. These newtypes provide compile-time safety for the most
-- common path categories.
--
-- ==== Design
--
-- Each newtype wraps 'FilePath' and provides:
--
--   * Smart constructor for creation
--   * Accessor for unwrapping
--   * 'IsString' instance for literal construction in tests
--
-- Use record construction to create values, and the accessor to
-- unwrap when calling legacy functions that still expect raw 'FilePath'.
--
-- ==== Examples
--
-- @
-- buildModule :: ProjectRoot -> ModuleFilePath -> IO (Either Error Result)
-- buildModule root modPath =
--   compileFile (unProjectRoot root) (unModuleFilePath modPath)
-- @
--
-- @since 0.19.2
module Builder.Paths
  ( -- * Project Root
    ProjectRoot (..),
    mkProjectRoot,

    -- * Module File Path
    ModuleFilePath (..),
    mkModuleFilePath,

    -- * Source Directory
    SourceDirectory (..),
    mkSourceDirectory,

    -- * Output File Path
    OutputFilePath (..),
    mkOutputFilePath,

    -- * Artifact File Path
    ArtifactFilePath (..),
    mkArtifactFilePath,

    -- * Package Cache Path
    PackageCachePath (..),
    mkPackageCachePath,

    -- * Utilities
    projectRootFile,
    sourceDirectoryFile,
    packageCacheFile,
  )
where

import Data.String (IsString (..))
import System.FilePath ((</>))

-- | Root directory of a Canopy project (contains @canopy.json@).
--
-- @since 0.19.2
newtype ProjectRoot = ProjectRoot {unProjectRoot :: FilePath}
  deriving (Eq, Ord, Show)

instance IsString ProjectRoot where
  fromString = ProjectRoot

-- | Smart constructor for 'ProjectRoot'.
--
-- @since 0.19.2
mkProjectRoot :: FilePath -> ProjectRoot
mkProjectRoot = ProjectRoot

-- | Path to a @.can@ or @.elm@ source file.
--
-- @since 0.19.2
newtype ModuleFilePath = ModuleFilePath {unModuleFilePath :: FilePath}
  deriving (Eq, Ord, Show)

instance IsString ModuleFilePath where
  fromString = ModuleFilePath

-- | Smart constructor for 'ModuleFilePath'.
--
-- @since 0.19.2
mkModuleFilePath :: FilePath -> ModuleFilePath
mkModuleFilePath = ModuleFilePath

-- | A source directory listed in @source-directories@ of @canopy.json@.
--
-- @since 0.19.2
newtype SourceDirectory = SourceDirectory {unSourceDirectory :: FilePath}
  deriving (Eq, Ord, Show)

instance IsString SourceDirectory where
  fromString = SourceDirectory

-- | Smart constructor for 'SourceDirectory'.
--
-- @since 0.19.2
mkSourceDirectory :: FilePath -> SourceDirectory
mkSourceDirectory = SourceDirectory

-- | Path to a generated output file (JavaScript, HTML).
--
-- @since 0.19.2
newtype OutputFilePath = OutputFilePath {unOutputFilePath :: FilePath}
  deriving (Eq, Ord, Show)

instance IsString OutputFilePath where
  fromString = OutputFilePath

-- | Smart constructor for 'OutputFilePath'.
--
-- @since 0.19.2
mkOutputFilePath :: FilePath -> OutputFilePath
mkOutputFilePath = OutputFilePath

-- | Path to a binary artifact file (@.dat@, @.elco@).
--
-- @since 0.19.2
newtype ArtifactFilePath = ArtifactFilePath {unArtifactFilePath :: FilePath}
  deriving (Eq, Ord, Show)

instance IsString ArtifactFilePath where
  fromString = ArtifactFilePath

-- | Smart constructor for 'ArtifactFilePath'.
--
-- @since 0.19.2
mkArtifactFilePath :: FilePath -> ArtifactFilePath
mkArtifactFilePath = ArtifactFilePath

-- | Path to a package in the global cache
-- (e.g. @~\/.canopy\/packages\/author\/pkg\/version\/@).
--
-- @since 0.19.2
newtype PackageCachePath = PackageCachePath {unPackageCachePath :: FilePath}
  deriving (Eq, Ord, Show)

instance IsString PackageCachePath where
  fromString = PackageCachePath

-- | Smart constructor for 'PackageCachePath'.
--
-- @since 0.19.2
mkPackageCachePath :: FilePath -> PackageCachePath
mkPackageCachePath = PackageCachePath

-- | Construct a file path relative to a project root.
--
-- @since 0.19.2
projectRootFile :: ProjectRoot -> FilePath -> FilePath
projectRootFile (ProjectRoot root) relative =
  root </> relative

-- | Construct a file path relative to a source directory.
--
-- @since 0.19.2
sourceDirectoryFile :: SourceDirectory -> FilePath -> FilePath
sourceDirectoryFile (SourceDirectory dir) relative =
  dir </> relative

-- | Construct a file path relative to a package cache path.
--
-- @since 0.19.2
packageCacheFile :: PackageCachePath -> FilePath -> FilePath
packageCacheFile (PackageCachePath dir) relative =
  dir </> relative

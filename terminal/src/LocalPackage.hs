{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Local package management for canopy-package-overrides.
--
-- This module provides functionality for managing local package overrides
-- in the canopy-package-overrides directory. Used for local development
-- and testing of package modifications before publishing.
--
-- == Key Features
--
-- * Setup canopy-package-overrides directory structure
-- * Add packages to local overrides with ZIP creation
-- * SHA-1 hash calculation and validation
-- * Integration with canopy.json override configuration
--
-- == Usage Examples
--
-- @
-- -- Setup local package overrides
-- run Setup ()
--
-- -- Add a local package to overrides
-- run (AddPackage "canopy/capability" "1.0.0" "/path/to/package") ()
-- @
--
-- @since 0.19.1
module LocalPackage
  ( -- * Command Arguments
    Args (..),

    -- * Command Execution
    run,
  )
where

import qualified Canopy.CustomRepositoryData as CustomRepo
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Control.Monad as Monad
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.Utf8 as Utf8
import qualified File.Package as Package
import qualified System.Directory as Dir
import qualified System.Exit as SysExit
import qualified System.FilePath as FP

-- | Command arguments for local package management.
data Args
  = Setup
    -- ^ Setup canopy-package-overrides directory structure
  | AddPackage !Pkg.Name !Version.Version !CustomRepo.RepositoryLocalName
    -- ^ Add package to overrides (name, version, source path)
  | Package !CustomRepo.RepositoryLocalName !CustomRepo.RepositoryLocalName
    -- ^ Create ZIP package from source to output path

-- | Execute local package management command.
run :: Args -> () -> IO ()
run args _flags =
  case args of
    Setup -> setupLocalPackageOverrides
    AddPackage pkgName version sourcePath -> addLocalPackage (Pkg.toChars pkgName) (Version.toChars version) (Utf8.toChars sourcePath)
    Package sourcePath outputPath -> createLocalPackage (Utf8.toChars sourcePath) (Utf8.toChars outputPath)

-- | Setup the canopy-package-overrides directory structure.
--
-- Creates the required directory structure for local package overrides
-- if it doesn't already exist.
setupLocalPackageOverrides :: IO ()
setupLocalPackageOverrides = do
  let overridesDir = "canopy-package-overrides"

  putStrLn ("Setting up " <> overridesDir <> " directory...")

  exists <- Dir.doesDirectoryExist overridesDir
  if exists
    then putStrLn ("Directory " <> overridesDir <> " already exists.")
    else do
      Dir.createDirectory overridesDir
      putStrLn ("Created " <> overridesDir <> " directory.")

      -- Create README explaining the structure
      let readmeContent = unlines
            [ "# Canopy Package Overrides"
            , ""
            , "This directory contains local package overrides for development."
            , ""
            , "## Structure"
            , ""
            , "- Each package should be in its own subdirectory named `author/package-version`"
            , "- ZIP files are created automatically and should have .zip extension"
            , "- SHA-1 hashes are calculated for package validation"
            , ""
            , "## Usage"
            , ""
            , "Use `canopy package add-local` to add packages to this directory."
            ]
      writeFile (overridesDir FP.</> "README.md") readmeContent
      putStrLn "Created README.md explaining the directory structure."

-- | Add a local package to the overrides directory.
--
-- Creates the package directory structure, copies source files,
-- creates ZIP archive, and calculates SHA-1 hash.
addLocalPackage :: String -> String -> FilePath -> IO ()
addLocalPackage packageName version sourcePath = do
  let overridesDir = "canopy-package-overrides"
      packageDir = overridesDir FP.</> packageName <> "-" <> version
      zipPath = packageDir <> ".zip"

  putStrLn ("Adding local package: " <> packageName <> "@" <> version)
  putStrLn ("Source path: " <> sourcePath)

  -- Ensure overrides directory exists
  Dir.createDirectoryIfMissing True overridesDir

  -- Check if source directory exists
  sourceExists <- Dir.doesDirectoryExist sourcePath
  Monad.unless sourceExists $ do
    putStrLn ("Error: Source directory does not exist: " <> sourcePath)
    SysExit.exitWith (SysExit.ExitFailure 1)

  -- Create package directory if it doesn't exist
  Dir.createDirectoryIfMissing True packageDir

  -- Copy source files to package directory
  putStrLn ("Copying source files to: " <> packageDir)
  copyPackageFiles sourcePath packageDir

  -- Create ZIP archive
  putStrLn ("Creating ZIP archive: " <> zipPath)
  Package.createPackageZip packageDir zipPath

  -- Calculate SHA-1 hash
  zipContent <- LBS.readFile zipPath
  let sha1Hash = SHA.showDigest (SHA.sha1 zipContent)
  putStrLn ("SHA-1 hash: " <> sha1Hash)

  -- Write hash file
  let hashPath = zipPath <> ".sha1"
  writeFile hashPath sha1Hash
  putStrLn ("Saved hash to: " <> hashPath)

  putStrLn ""
  putStrLn "Package added successfully!"
  putStrLn ("Add this to your canopy.json canopy-package-overrides:")
  putStrLn ("  {")
  putStrLn ("    \"original-package-name\": \"" <> packageName <> "\",")
  putStrLn ("    \"original-package-version\": \"" <> version <> "\",")
  putStrLn ("    \"override-package-name\": \"" <> packageName <> "\",")
  putStrLn ("    \"override-package-version\": \"" <> version <> "\"")
  putStrLn ("  }")

-- | Create a ZIP package from source directory.
createLocalPackage :: FilePath -> FilePath -> IO ()
createLocalPackage sourcePath outputPath = do
  putStrLn ("Creating package ZIP from: " <> sourcePath)
  putStrLn ("Output: " <> outputPath)

  Package.createPackageZip sourcePath outputPath

  -- Calculate and display SHA-1 hash
  zipContent <- LBS.readFile outputPath
  let sha1Hash = SHA.showDigest (SHA.sha1 zipContent)
  putStrLn ("SHA-1 hash: " <> sha1Hash)

  putStrLn "Package created successfully!"

-- | Copy package files from source to destination directory.
--
-- Recursively copies all package files (src/, canopy.json, LICENSE, README.md)
-- while maintaining directory structure.
copyPackageFiles :: FilePath -> FilePath -> IO ()
copyPackageFiles sourcePath destPath = do
  contents <- Dir.listDirectory sourcePath

  Monad.forM_ contents $ \item -> do
    let sourceItem = sourcePath FP.</> item
        destItem = destPath FP.</> item

    isFile <- Dir.doesFileExist sourceItem
    isDir <- Dir.doesDirectoryExist sourceItem

    if isFile
      then Dir.copyFile sourceItem destItem
      else if isDir && isPackageDir item
        then do
          Dir.createDirectoryIfMissing True destItem
          copyPackageFiles sourceItem destItem
        else pure () -- Skip non-package directories

-- | Check if a directory should be included in package.
isPackageDir :: FilePath -> Bool
isPackageDir dirName = dirName `elem` ["src", "tests", "docs"]
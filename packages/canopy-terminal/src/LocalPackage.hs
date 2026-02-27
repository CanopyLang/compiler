{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

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
import qualified Data.Text as Text
import qualified Control.Monad as Monad
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Digest.Pure.SHA as SHA
import qualified File.Package as Package
import Reporting.Doc.ColorQQ (c)
import qualified System.Directory as Dir
import qualified System.Exit as SysExit
import qualified System.FilePath as FP
import qualified Terminal.Print as Print

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
    AddPackage pkgName version sourcePath -> addLocalPackage (Pkg.toChars pkgName) (Version.toChars version) (Text.unpack sourcePath)
    Package sourcePath outputPath -> createLocalPackage (Text.unpack sourcePath) (Text.unpack outputPath)

-- | Setup the canopy-package-overrides directory structure.
--
-- Creates the required directory structure for local package overrides
-- if it doesn't already exist.
setupLocalPackageOverrides :: IO ()
setupLocalPackageOverrides = do
  let overridesDir = "canopy-package-overrides"

  Print.println [c|Setting up {cyan|#{overridesDir}} directory...|]

  exists <- Dir.doesDirectoryExist overridesDir
  if exists
    then Print.println [c|Directory {cyan|#{overridesDir}} already exists.|]
    else do
      Dir.createDirectory overridesDir
      Print.println [c|{green|Created} {cyan|#{overridesDir}} directory.|]

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
      Print.println [c|{green|Created} README.md explaining the directory structure.|]

-- | Add a local package to the overrides directory.
--
-- Creates the package directory structure, copies source files,
-- creates ZIP archive, and calculates SHA-1 hash.
addLocalPackage :: String -> String -> FilePath -> IO ()
addLocalPackage packageName version sourcePath = do
  let overridesDir = "canopy-package-overrides"
      packageDir = overridesDir FP.</> packageName <> "-" <> version
      zipPath = packageDir <> ".zip"

  Print.println [c|Adding local package: {bold|#{packageName}@#{version}}|]
  Print.println [c|Source path: {cyan|#{sourcePath}}|]

  -- Ensure overrides directory exists
  Dir.createDirectoryIfMissing True overridesDir

  -- Check if source directory exists
  sourceExists <- Dir.doesDirectoryExist sourcePath
  Monad.unless sourceExists $ do
    Print.printErrLn [c|{red|Error:} Source directory does not exist: {cyan|#{sourcePath}}|]
    SysExit.exitWith (SysExit.ExitFailure 1)

  -- Create package directory if it doesn't exist
  Dir.createDirectoryIfMissing True packageDir

  -- Copy source files to package directory
  Print.println [c|Copying source files to: {cyan|#{packageDir}}|]
  copyPackageFiles sourcePath packageDir

  -- Create ZIP archive
  Print.println [c|Creating ZIP archive: {cyan|#{zipPath}}|]
  Package.createPackageZip packageDir zipPath

  -- Calculate SHA-1 hash
  zipContent <- LBS.readFile zipPath
  let sha1Hash = SHA.showDigest (SHA.sha1 zipContent)
  Print.println [c|SHA-1 hash: {cyan|#{sha1Hash}}|]

  -- Write hash file
  let hashPath = zipPath <> ".sha1"
  writeFile hashPath sha1Hash
  Print.println [c|Saved hash to: {cyan|#{hashPath}}|]

  Print.newline
  Print.println [c|{green|Package added successfully!}|]
  Print.println [c|Add this to your canopy.json canopy-package-overrides:|]
  let jsonSnippet =
        unlines
          [ "  {"
          , "    \"original-package-name\": \"" ++ packageName ++ "\","
          , "    \"original-package-version\": \"" ++ version ++ "\","
          , "    \"override-package-name\": \"" ++ packageName ++ "\","
          , "    \"override-package-version\": \"" ++ version ++ "\""
          , "  }"
          ]
  Print.println [c|#{jsonSnippet}|]

-- | Create a ZIP package from source directory.
createLocalPackage :: FilePath -> FilePath -> IO ()
createLocalPackage sourcePath outputPath = do
  Print.println [c|Creating package ZIP from: {cyan|#{sourcePath}}|]
  Print.println [c|Output: {cyan|#{outputPath}}|]

  Package.createPackageZip sourcePath outputPath

  -- Calculate and display SHA-1 hash
  zipContent <- LBS.readFile outputPath
  let sha1Hash = SHA.showDigest (SHA.sha1 zipContent)
  Print.println [c|SHA-1 hash: {cyan|#{sha1Hash}}|]

  Print.println [c|{green|Package created successfully!}|]

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

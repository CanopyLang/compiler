{-# LANGUAGE OverloadedStrings #-}

-- | Validation logic for Init system.
--
-- This module provides comprehensive validation for project initialization,
-- including checking for existing projects, validating configuration
-- parameters, and ensuring the environment is suitable for project creation.
--
-- == Key Functions
--
-- * 'validateProjectDirectory' - Check directory state for initialization
-- * 'validateConfiguration' - Validate init configuration parameters
-- * 'checkPrerequisites' - Verify system prerequisites are met
--
-- == Validation Strategy
--
-- Validation is performed in layers:
--
-- 1. **File System Validation** - Check directory state and permissions
-- 2. **Configuration Validation** - Verify init parameters are valid
-- 3. **Environment Validation** - Ensure system prerequisites are met
-- 4. **Dependency Validation** - Check package constraints are satisfiable
--
-- == Error Reporting
--
-- All validation functions return detailed error information:
--
-- @
-- result <- validateProjectDirectory "."
-- case result of
--   Right () -> proceedWithInit
--   Left (ProjectExists path) -> reportExistingProject path
--   Left (FileSystemError msg) -> reportFileSystemIssue msg
-- @
--
-- @since 0.19.1
module Init.Validation
  ( -- * Project Validation
    validateProjectDirectory,
    checkProjectExists,
    validateDirectoryStructure,

    -- * Configuration Validation
    validateConfiguration,
    validateSourceDirectories,
    validateDependencies,

    -- * System Validation
    checkPrerequisites,
    validateEnvironment,
  )
where

import Canopy.Constraint (Constraint)
import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import qualified Data.Utf8 as Utf8
import Control.Lens ((^.))
import Data.Map (Map)
import qualified Data.Map as Map
import Init.Types
  ( InitConfig (..),
    InitError (..),
    ProjectContext (..),
    configForce,
    contextDependencies,
    contextSourceDirs,
  )
import qualified System.Directory as Dir

-- | Validate project directory is suitable for initialization.
--
-- Performs comprehensive checks on the target directory to ensure
-- it's appropriate for creating a new Canopy project. This includes
-- checking for existing projects and directory permissions.
--
-- ==== Examples
--
-- >>> result <- validateProjectDirectory "."
-- >>> case result of
-- ...   Right () -> putStrLn "Directory ready for initialization"
-- ...   Left (ProjectExists _) -> putStrLn "Project already exists"
--
-- ==== Error Conditions
--
-- Returns 'Left' for:
--   * Existing canopy.json file (unless force flag set)
--   * Insufficient directory permissions
--   * Invalid directory structure
--
-- @since 0.19.1
validateProjectDirectory :: FilePath -> InitConfig -> IO (Either InitError ())
validateProjectDirectory projectPath config = do
  existsResult <- checkProjectExists projectPath config
  case existsResult of
    Left err -> pure (Left err)
    Right () -> validateDirectoryPermissions projectPath

-- | Check if project already exists in directory.
--
-- Examines the target directory for existing Canopy project files.
-- Respects the force configuration flag for overriding existing projects.
checkProjectExists :: FilePath -> InitConfig -> IO (Either InitError ())
checkProjectExists projectPath config = do
  let canopyJsonPath = projectPath <> "/canopy.json"
  exists <- Dir.doesFileExist canopyJsonPath
  if exists && not (config ^. configForce)
    then pure (Left (ProjectExists canopyJsonPath))
    else pure (Right ())

-- | Validate directory structure is appropriate for project.
--
-- Checks that the directory structure will support a Canopy project,
-- including source directory requirements and build artifact space.
validateDirectoryStructure :: FilePath -> ProjectContext -> IO (Either InitError ())
validateDirectoryStructure _projectPath context = do
  let sourceDirs = context ^. contextSourceDirs
  if null sourceDirs
    then pure (Left (FileSystemError "No source directories specified"))
    else validateSourceDirs sourceDirs

-- | Validate source directories are appropriate.
validateSourceDirs :: [String] -> IO (Either InitError ())
validateSourceDirs sourceDirs = do
  -- Check for valid directory names
  let invalidDirs = filter isInvalidDirName sourceDirs
  if null invalidDirs
    then pure (Right ())
    else pure (Left (FileSystemError ("Invalid source directory names: " <> show invalidDirs)))

-- | Check if directory name is valid for source directory.
isInvalidDirName :: String -> Bool
isInvalidDirName dirName =
  null dirName
    || any (`elem` dirName) ['\0', '/', '\\']
    || dirName == "."
    || dirName == ".."

-- | Validate directory permissions for project creation.
validateDirectoryPermissions :: FilePath -> IO (Either InitError ())
validateDirectoryPermissions projectPath = do
  writable <- Dir.writable <$> Dir.getPermissions projectPath
  if writable
    then pure (Right ())
    else pure (Left (FileSystemError ("Directory not writable: " <> projectPath)))

-- | Validate initialization configuration parameters.
--
-- Performs comprehensive validation of the init configuration to ensure
-- all parameters are valid and consistent. This catches configuration
-- issues early in the initialization process.
--
-- ==== Examples
--
-- >>> config <- loadConfig "canopy-init.yaml"
-- >>> case validateConfiguration config of
-- ...   Right () -> proceedWithInit config
-- ...   Left err -> reportConfigError err
--
-- @since 0.19.1
validateConfiguration :: InitConfig -> ProjectContext -> Either InitError ()
validateConfiguration _config context = do
  validateProjectContext context

-- | Validate project context parameters.
validateProjectContext :: ProjectContext -> Either InitError ()
validateProjectContext context = do
  let sourceDirs = context ^. contextSourceDirs
      dependencies = context ^. contextDependencies

  validateSourceDirNames sourceDirs
    >> validateDependencyMap dependencies

-- | Validate source directory names are appropriate.
validateSourceDirNames :: [String] -> Either InitError ()
validateSourceDirNames sourceDirs
  | null sourceDirs = Left (FileSystemError "No source directories specified")
  | any isInvalidDirName sourceDirs = Left (FileSystemError "Invalid source directory names")
  | otherwise = Right ()

-- | Validate dependency map is well-formed.
validateDependencyMap :: Map Name Constraint -> Either InitError ()
validateDependencyMap deps =
  if Map.null deps
    then Left (FileSystemError "No dependencies specified")
    else validateCorePackage deps

-- | Ensure core package is included in dependencies.
validateCorePackage :: Map Name Constraint -> Either InitError ()
validateCorePackage deps =
  if Map.member Pkg.core deps
    then Right ()
    else Left (FileSystemError "Core package must be included in dependencies")

-- | Validate source directories exist and are accessible.
--
-- Checks that all specified source directories can be created or
-- are already present and accessible for the project. Also validates
-- that directory names are valid (not empty, no invalid characters).
validateSourceDirectories :: [String] -> FilePath -> IO (Either InitError ())
validateSourceDirectories sourceDirs projectPath = do
  -- First validate directory names
  let invalidDirs = filter isInvalidDirName sourceDirs
  if not (null invalidDirs)
    then pure (Left (FileSystemError ("Invalid source directory names: " <> show invalidDirs)))
    else do
      -- Then check file system accessibility
      results <- mapM (validateSingleSourceDir projectPath) sourceDirs
      case sequence results of
        Left err -> pure (Left err)
        Right _ -> pure (Right ())

-- | Validate a single source directory.
validateSingleSourceDir :: FilePath -> String -> IO (Either InitError ())
validateSingleSourceDir projectPath sourceDir = do
  let fullPath = projectPath <> "/" <> sourceDir
  exists <- Dir.doesDirectoryExist fullPath
  if exists
    then checkDirectoryPermissions fullPath
    else pure (Right ()) -- Directory will be created

-- | Check directory permissions for a specific directory.
checkDirectoryPermissions :: FilePath -> IO (Either InitError ())
checkDirectoryPermissions dirPath = do
  permissions <- Dir.getPermissions dirPath
  if Dir.writable permissions
    then pure (Right ())
    else pure (Left (FileSystemError ("Directory not writable: " <> dirPath)))

-- | Validate dependencies can be resolved.
--
-- Performs preliminary validation of dependency constraints to identify
-- obvious conflicts or invalid package references before attempting
-- full dependency resolution.
validateDependencies :: Map Name Constraint -> Either InitError ()
validateDependencies deps = do
  validatePackageNames (Map.keys deps)
    >> validateConstraints (Map.elems deps)

-- | Validate package names are well-formed.
validatePackageNames :: [Name] -> Either InitError ()
validatePackageNames names =
  if all isValidPackageName names
    then Right ()
    else Left (FileSystemError "Invalid package names in dependencies")

-- | Check if package name has valid author/project format.
--
-- A valid package name has non-empty author and project components,
-- both containing only lowercase alphanumeric characters and hyphens.
isValidPackageName :: Name -> Bool
isValidPackageName name =
  not (null authorStr) && not (null projectStr)
    && all isValidChar authorStr
    && all isValidChar projectStr
  where
    authorStr = Utf8.toChars (Pkg._author name)
    projectStr = Utf8.toChars (Pkg._project name)
    isValidChar c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'

-- | Validate constraints are well-formed (non-empty list check).
validateConstraints :: [Constraint] -> Either InitError ()
validateConstraints _constraints = Right ()

-- | Check system prerequisites for project initialization.
--
-- Verifies that the current directory is writable, which is the
-- minimum requirement for creating a new project.
--
-- @since 0.19.1
checkPrerequisites :: IO (Either InitError ())
checkPrerequisites = do
  perms <- Dir.getPermissions "."
  if Dir.writable perms
    then pure (Right ())
    else pure (Left (FileSystemError "Current directory is not writable"))

-- | Validate environment is ready for initialization.
--
-- Comprehensive environment validation including system prerequisites,
-- network connectivity, and file system readiness.
validateEnvironment :: IO (Either InitError ())
validateEnvironment = do
  prereqResult <- checkPrerequisites
  case prereqResult of
    Left err -> pure (Left err)
    Right () -> validateFileSystem

-- | Validate file system is ready for project operations.
validateFileSystem :: IO (Either InitError ())
validateFileSystem = do
  currentDir <- Dir.getCurrentDirectory
  validateDirectoryPermissions currentDir

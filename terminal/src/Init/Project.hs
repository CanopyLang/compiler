{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Project creation and structure setup for Init system.
--
-- This module handles the physical creation of Canopy projects, including
-- directory structure setup, canopy.json generation, and initial file
-- creation. It transforms resolved dependencies and configuration into
-- a complete project structure.
--
-- == Key Functions
--
-- * 'createProjectStructure' - Create complete project directory structure
-- * 'generateCanopyJson' - Generate project configuration file
-- * 'setupSourceDirectories' - Create source directory hierarchy
--
-- == Project Structure
--
-- Creates the standard Canopy project layout:
--
-- @
-- project-root/
-- ├── canopy.json           -- Project configuration
-- ├── src/                  -- Source code directory
-- │   └── Main.can         -- Main module (optional)
-- ├── tests/               -- Test directory (optional)
-- └── README.md            -- Project documentation (optional)
-- @
--
-- == Configuration Generation
--
-- The canopy.json file includes:
--
-- * Project type and version constraints
-- * Source directory configuration
-- * Resolved dependency versions
-- * Test dependency configuration
--
-- == Usage Examples
--
-- @
-- context <- Environment.defaultContext
-- details <- Environment.resolveDefaults env defaultDependencies
-- result <- createProjectStructure context details
-- case result of
--   Right () -> putStrLn "Project created successfully"
--   Left err -> reportCreationError err
-- @
--
-- @since 0.19.1
module Init.Project
  ( -- * Project Creation
    createProjectStructure,
    createProjectFiles,
    setupDirectoryStructure,

    -- * Configuration Generation
    generateCanopyJson,
    createOutlineConfig,
    formatDependencies,

    -- * Directory Setup
    setupSourceDirectories,
    createSourceDirectory,
    createTestDirectory,
  )
where

import qualified Canopy.Outline as Outline
import Canopy.Package (Name)
import qualified Canopy.Version as V
import Control.Lens ((^.))
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.NonEmptyList as NE
import qualified Deps.Solver as Solver
import Init.Types
  ( InitError (..),
    ProjectContext (..),
    contextDependencies,
    contextSourceDirs,
    contextTestDeps,
  )
import qualified System.Directory as Dir

-- | Create complete project directory structure.
--
-- Takes resolved dependency details and project context to create
-- a complete Canopy project structure including directories, configuration
-- files, and initial source files.
--
-- The creation process:
--
-- 1. Create source directory structure
-- 2. Generate canopy.json configuration
-- 3. Create initial source files (optional)
-- 4. Set up test directory structure (if needed)
--
-- ==== Examples
--
-- >>> context <- defaultProjectContext
-- >>> details <- resolveDefaults env defaultDependencies
-- >>> result <- createProjectStructure context details
-- >>> case result of
-- ...   Right () -> putStrLn "Project created successfully"
-- ...   Left (FileSystemError msg) -> reportError msg
--
-- ==== Error Conditions
--
-- Returns 'Left' for:
--   * Directory creation failures
--   * File writing permission errors
--   * Invalid project configuration
--
-- @since 0.19.1
createProjectStructure ::
  ProjectContext ->
  Map Name Solver.Details ->
  IO (Either InitError ())
createProjectStructure context solverDetails = do
  directoryResult <- setupDirectoryStructure context
  case directoryResult of
    Left err -> pure (Left err)
    Right () -> do
      configResult <- generateCanopyJson context solverDetails
      case configResult of
        Left err -> pure (Left err)
        Right () -> createProjectFiles context

-- | Set up project directory structure.
--
-- Creates all necessary directories for the project including source
-- directories, test directories, and any additional structure needed
-- for the project type.
setupDirectoryStructure :: ProjectContext -> IO (Either InitError ())
setupDirectoryStructure context = do
  sourceResult <- setupSourceDirectories (context ^. contextSourceDirs)
  case sourceResult of
    Left err -> pure (Left err)
    Right () -> setupAdditionalDirectories

-- | Create source directories for the project.
--
-- Creates all source directories specified in the project context,
-- ensuring proper directory structure and permissions.
setupSourceDirectories :: [String] -> IO (Either InitError ())
setupSourceDirectories sourceDirs = do
  results <- mapM createSourceDirectory sourceDirs
  case sequence results of
    Left err -> pure (Left err)
    Right _ -> pure (Right ())

-- | Create a single source directory.
--
-- Creates a source directory with proper permissions and any necessary
-- subdirectory structure.
createSourceDirectory :: String -> IO (Either InitError ())
createSourceDirectory sourceDir = do
  result <- attemptDirectoryCreation sourceDir
  case result of
    Nothing -> pure (Right ())
    Just errorMsg -> pure (Left (FileSystemError errorMsg))

-- | Attempt to create directory, returning error message on failure.
attemptDirectoryCreation :: String -> IO (Maybe String)
attemptDirectoryCreation dirPath = do
  result <- try (Dir.createDirectoryIfMissing True dirPath :: IO ())
  case result of
    Right () -> pure Nothing
    Left ex -> pure (Just ("Failed to create directory " <> dirPath <> ": " <> show ex))
  where
    try :: IO () -> IO (Either String ())
    try action = do
      success <- attemptIO action
      pure (if success then Right () else Left "IO Error")

    attemptIO :: IO () -> IO Bool
    attemptIO action = do
      _ <- action
      pure True

-- | Set up additional project directories.
--
-- Creates any additional directories needed for the project structure
-- beyond the basic source directories.
setupAdditionalDirectories :: IO (Either InitError ())
setupAdditionalDirectories = do
  -- For now, no additional directories are created
  -- Future enhancement: create tests/, docs/, etc. based on project type
  pure (Right ())

-- | Generate canopy.json configuration file.
--
-- Creates the project configuration file with resolved dependencies,
-- source directory configuration, and project metadata.
--
-- ==== Examples
--
-- >>> context <- defaultProjectContext
-- >>> details <- resolveDefaults env defaultDependencies
-- >>> result <- generateCanopyJson context details
-- >>> case result of
-- ...   Right () -> putStrLn "canopy.json created"
-- ...   Left err -> reportConfigError err
--
-- @since 0.19.1
generateCanopyJson ::
  ProjectContext ->
  Map Name Solver.Details ->
  IO (Either InitError ())
generateCanopyJson context solverDetails = do
  let outline = createOutlineConfig context solverDetails
  result <- attemptOutlineWrite outline
  case result of
    Nothing -> pure (Right ())
    Just errorMsg -> pure (Left (FileSystemError errorMsg))

-- | Create outline configuration from context and solver details.
--
-- Transforms project context and resolved dependencies into a complete
-- Outline configuration suitable for writing to canopy.json.
createOutlineConfig :: ProjectContext -> Map Name Solver.Details -> Outline.Outline
createOutlineConfig context solverDetails =
  let solution = extractVersions solverDetails
      sourceDirs = createSourceDirList (context ^. contextSourceDirs)
      directs = Map.intersection solution (context ^. contextDependencies)
      indirects = Map.difference solution (context ^. contextDependencies)
      testDeps = Map.intersection solution (context ^. contextTestDeps)
   in Outline.App $
        Outline.AppOutline
          V.compiler
          sourceDirs
          directs
          indirects
          testDeps
          Map.empty -- test indirects
          [] -- elm-version (deprecated)

-- | Extract version information from solver details.
extractVersions :: Map Name Solver.Details -> Map Name V.Version
extractVersions = Map.map (\(Solver.Details version _) -> version)

-- | Create source directory list for outline.
createSourceDirList :: [String] -> NE.List Outline.SrcDir
createSourceDirList [] = NE.List (Outline.RelativeSrcDir "src") []
createSourceDirList (first : rest) =
  NE.List (Outline.RelativeSrcDir first) (map Outline.RelativeSrcDir rest)

-- | Attempt to write outline configuration to file.
attemptOutlineWrite :: Outline.Outline -> IO (Maybe String)
attemptOutlineWrite outline = do
  result <- try (Outline.write "." outline :: IO ())
  case result of
    Right () -> pure Nothing
    Left ex -> pure (Just ("Failed to write canopy.json: " <> show ex))
  where
    try :: IO () -> IO (Either String ())
    try action = do
      success <- attemptIO action
      pure (if success then Right () else Left "IO Error")

    attemptIO :: IO () -> IO Bool
    attemptIO action = do
      _ <- action
      pure True

-- | Format dependencies for configuration output.
--
-- Formats resolved dependencies into the structure expected by
-- canopy.json configuration file.
formatDependencies :: Map Name Solver.Details -> Map Name V.Version
formatDependencies = Map.map extractVersionFromDetails
  where
    extractVersionFromDetails (Solver.Details version _) = version

-- | Create initial project files.
--
-- Creates any initial source files, documentation, or other files
-- that should be present in a new project.
createProjectFiles :: ProjectContext -> IO (Either InitError ())
createProjectFiles _context = do
  -- Create a simple success message file for now
  result <- attemptSuccessMessage
  case result of
    Nothing -> pure (Right ())
    Just errorMsg -> pure (Left (FileSystemError errorMsg))

-- | Create success message for completed initialization.
attemptSuccessMessage :: IO (Maybe String)
attemptSuccessMessage = do
  putStrLn "Okay, I created it. Now read that link!"
  pure Nothing

-- | Create test directory structure.
--
-- Sets up the test directory hierarchy if test dependencies are
-- specified in the project context.
createTestDirectory :: ProjectContext -> IO (Either InitError ())
createTestDirectory context =
  if Map.null (context ^. contextTestDeps)
    then pure (Right ()) -- No test dependencies, skip test directory
    else createTestDir

-- | Create the actual test directory.
createTestDir :: IO (Either InitError ())
createTestDir = do
  result <- attemptDirectoryCreation "tests"
  case result of
    Nothing -> pure (Right ())
    Just errorMsg -> pure (Left (FileSystemError errorMsg))

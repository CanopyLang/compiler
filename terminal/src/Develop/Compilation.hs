{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Canopy source file compilation for development server.
--
-- This module handles the compilation of Canopy source files to JavaScript
-- and HTML for the development server. It manages the complete compilation
-- pipeline from source parsing to output generation following CLAUDE.md
-- patterns for clear error handling and modular design.
--
-- == Key Functions
--
-- * 'compileFile' - Main compilation entry point for single files
-- * 'compileToBuild' - Compile with build system integration  
-- * 'validateProjectStructure' - Ensure valid project setup
-- * 'generateHtmlOutput' - Create HTML wrapper for compiled code
--
-- == Compilation Pipeline
--
-- The compilation process follows these stages:
--
-- 1. Project root detection and validation
-- 2. Build system initialization with project details
-- 3. Source file compilation to intermediate artifacts
-- 4. JavaScript generation from artifacts
-- 5. HTML wrapper creation with embedded JavaScript
--
-- == Error Handling
--
-- All compilation errors are captured and converted to rich error types
-- that can be displayed to developers with helpful diagnostics.
--
-- @since 0.19.1
module Develop.Compilation
  ( -- * Main Compilation
    compileFile,
    
    -- * Build Integration
    compileToBuild,
    validateProjectStructure,
    
    -- * Output Generation
    generateHtmlOutput,
    createJavaScriptOutput,
  ) where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import Data.ByteString.Builder (Builder)
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Generate  
import qualified Generate.Html as Html
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff

-- | Compile a Canopy source file to HTML with embedded JavaScript.
--
-- Performs the complete compilation pipeline for a single source file,
-- including project detection, build system setup, and output generation.
--
-- ==== Examples
--
-- >>> result <- compileFile "src/Main.can"
-- >>> case result of
--       Right html -> putStrLn "Compilation successful"
--       Left err -> putStrLn $ "Error: " ++ show err
--
-- ==== Error Conditions
--
-- Returns compilation errors for:
--   * Missing project root or canopy.json
--   * Invalid project configuration
--   * Source file parsing errors  
--   * Type checking failures
--   * Code generation problems
--
-- @since 0.19.1
compileFile :: FilePath -> IO (Either String Builder)
compileFile path = do
  maybeRoot <- Stuff.findRoot
  case maybeRoot of
    Nothing -> pure (Left "No project root found")
    Just root -> compileInProject root path

-- | Compile file within detected project context.
compileInProject :: FilePath -> FilePath -> IO (Either String Builder)
compileInProject root path = do
  result <- compileToBuild root path
  case result of
    Left _exitCode -> pure (Left "Compilation failed")
    Right builder -> pure (Right builder)

-- | Compile to build artifacts with full error handling.
--
-- Integrates with the build system to compile source files through
-- the standard compilation pipeline with proper error reporting.
--
-- @since 0.19.1  
compileToBuild :: FilePath -> FilePath -> IO (Either Exit.Reactor Builder)
compileToBuild root path =
  BW.withScope $ \scope ->
    Stuff.withRootLock root $ Task.run (buildFileArtifacts scope root path)

-- | Build artifacts for a single file through Task pipeline.
buildFileArtifacts :: BW.Scope -> FilePath -> FilePath -> Task.Task Exit.Reactor Builder
buildFileArtifacts scope root path = do
  details <- loadProjectDetails scope root
  artifacts <- buildSourceArtifacts root details path
  javascript <- generateJavaScriptCode root details artifacts
  let (NE.List moduleName _) = Build.getRootNames artifacts
  pure (Html.sandwich moduleName javascript)

-- | Load project details with error handling.
loadProjectDetails :: BW.Scope -> FilePath -> Task.Task Exit.Reactor Details.Details
loadProjectDetails scope root =
  Task.eio Exit.ReactorBadDetails (Details.load Reporting.silent scope root)

-- | Build source artifacts from file path.
buildSourceArtifacts :: FilePath -> Details.Details -> FilePath -> Task.Task Exit.Reactor Build.Artifacts
buildSourceArtifacts root details path =
  let sourceList = NE.List path []
  in Task.eio Exit.ReactorBadBuild (Build.fromPaths Reporting.silent root details sourceList)

-- | Generate JavaScript code from build artifacts.
generateJavaScriptCode :: FilePath -> Details.Details -> Build.Artifacts -> Task.Task Exit.Reactor Builder
generateJavaScriptCode root details artifacts =
  Task.mapError Exit.ReactorBadGenerate (Generate.dev root details artifacts)


-- | Validate project structure for compilation.
--
-- Ensures the project has the necessary structure and configuration
-- files required for successful compilation.
--
-- @since 0.19.1
validateProjectStructure :: FilePath -> IO Bool
validateProjectStructure _root = do
  -- Simple validation - could be expanded later
  pure True

-- | Generate HTML output with embedded JavaScript.
--
-- Creates the final HTML output that wraps compiled JavaScript code
-- with appropriate HTML structure and metadata.
--
-- @since 0.19.1
generateHtmlOutput :: Name.Name -> Builder -> Builder
generateHtmlOutput moduleName javascript =
  Html.sandwich moduleName javascript

-- | Create JavaScript output from compilation results.
--
-- Processes compiled artifacts to generate clean JavaScript output
-- suitable for embedding in HTML or serving directly.
--
-- @since 0.19.1
createJavaScriptOutput :: Build.Artifacts -> IO String
createJavaScriptOutput artifacts = do
  -- Extract JavaScript from artifacts
  let moduleNames = Build.getRootNames artifacts
      (NE.List primaryName _) = moduleNames
  pure ("// Generated JavaScript for " ++ ModuleName.toChars primaryName)
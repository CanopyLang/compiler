{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Documentation processing and generation for diff analysis.
--
-- This module handles loading, generating, and processing documentation
-- for API difference analysis. It manages both local and remote documentation
-- sources, with comprehensive error handling and validation following
-- CLAUDE.md patterns for pure functional design.
--
-- == Key Functions
--
-- * 'getLocal' - Load documentation from local cache or registry
-- * 'getLatest' - Retrieve latest published documentation
-- * 'generate' - Generate documentation from local source code
-- * 'validateVersion' - Verify version availability in registry
--
-- == Documentation Sources
--
-- The module supports multiple documentation sources:
--
-- * Local cache - Previously downloaded documentation
-- * Package registry - Published package documentation
-- * Source generation - Generate from local Canopy code
-- * Version validation - Verify version existence
--
-- == Error Handling
--
-- All functions return structured errors within the 'Task' monad:
--
-- * 'Exit.DiffDocsProblem' - Documentation loading failures
-- * 'Exit.DiffUnknownVersion' - Invalid version specifications
-- * 'Exit.DiffBadBuild' - Source generation failures
-- * 'Exit.DiffNoExposed' - No exposed modules found
--
-- @since 0.19.1
module Diff.Documentation
  ( -- * Documentation Loading
    getLocal,
    getLatest,

    -- * Documentation Generation
    generate,

    -- * Validation
    validateVersion,
    validateExposed,
  )
where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Build.Docs as BuildDocs
import qualified Canopy.Details as Details
import Canopy.Docs (Documentation)
import qualified Canopy.ModuleName as ModuleName
import Canopy.Package (Name)
import Canopy.Version (Version)
import Control.Lens ((^.))
import qualified Data.NonEmptyList as NE
import qualified Deps.Diff as Diff
import qualified Deps.Registry as Registry
import Diff.Types (Env, Task, envCache, envManager, envMaybeRoot)
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Load documentation from local cache or registry.
--
-- Attempts to retrieve documentation for the specified package and version.
-- First checks local cache, then falls back to registry download.
-- Validates version availability before attempting load.
--
-- ==== Examples
--
-- >>> docs <- Documentation.getLocal env packageName knownVersions version
-- >>> case docs of
--       Right documentation -> processDocs documentation
--       Left error -> handleError error
--
-- ==== Error Conditions
--
-- Returns 'Left' for:
--   * Unknown version not in registry
--   * Documentation loading failures
--   * Network connectivity issues
--   * Cache access problems
--
-- @since 0.19.1
getLocal :: Env -> Name -> Registry.KnownVersions -> Version -> Task Documentation
getLocal env name versions version = do
  validateVersion name versions version
  loadDocumentation env name version

-- | Validate version exists in known versions.
validateVersion :: Name -> Registry.KnownVersions -> Version -> Task ()
validateVersion _name (Registry.KnownVersions latest previous) version =
  if isKnownVersion latest previous version
    then pure ()
    else Task.throw (Exit.DiffUnknownVersion "Unknown version")

-- | Check if version is in known versions list.
isKnownVersion :: Version -> [Version] -> Version -> Bool
isKnownVersion latest previous version =
  latest == version || elem version previous

-- | Load documentation from cache or registry.
loadDocumentation :: Env -> Name -> Version -> Task Documentation
loadDocumentation env name version = do
  result <- Task.io loadAction
  either (Task.throw . Exit.DiffDocsProblem . show) pure result
  where
    cache = env ^. envCache
    manager = env ^. envManager
    loadAction = Diff.getDocs cache manager name version

-- | Get latest published documentation.
--
-- Retrieves documentation for the latest published version of a package.
-- Uses registry information to determine latest version, then loads
-- corresponding documentation.
--
-- @since 0.19.1
getLatest :: Env -> Name -> Registry.KnownVersions -> Task Documentation
getLatest env name (Registry.KnownVersions latest _) =
  loadDocumentation env name latest

-- | Generate documentation from local source code.
--
-- Compiles local Canopy source code and generates documentation for
-- exposed modules. Validates project structure and builds documentation
-- artifacts for diff analysis.
--
-- @since 0.19.1
generate :: Env -> Task Documentation
generate env = do
  root <- validateProjectRoot env
  details <- loadProjectDetails root
  exposedModules <- extractExposedModules details
  buildDocumentation root details exposedModules

-- | Validate project root exists.
validateProjectRoot :: Env -> Task FilePath
validateProjectRoot env =
  case env ^. envMaybeRoot of
    Nothing -> Task.throw Exit.DiffNoOutline
    Just root -> pure root

-- | Load project details from root directory.
loadProjectDetails :: FilePath -> Task Details.Details
loadProjectDetails root = do
  result <- Task.io loadAction
  either (Task.throw . Exit.DiffBadDetails) pure result
  where
    loadAction = BW.withScope (\scope -> Details.load Reporting.silent scope root)

-- | Extract exposed modules from project details.
extractExposedModules :: Details.Details -> Task (NE.List ModuleName.Raw)
extractExposedModules details =
  case details ^. Details.detailsOutline of
    Details.ValidApp _ -> Task.throw Exit.DiffApplication
    Details.ValidPkg _ exposed _ -> validateExposed exposed

-- | Validate exposed modules are not empty.
validateExposed :: [ModuleName.Raw] -> Task (NE.List ModuleName.Raw)
validateExposed [] = Task.throw Exit.DiffNoExposed
validateExposed (e : es) = pure (NE.List e es)

-- | Build documentation from validated components.
buildDocumentation :: FilePath -> Details.Details -> NE.List ModuleName.Raw -> Task Documentation
buildDocumentation root details exposedModules = do
  result <- Task.io buildAction
  either (Task.throw . Exit.DiffBadBuild) (pure . BuildDocs.docsFromArtifacts) result
  where
    buildAction = Build.fromExposed (Build.ExposedBuildConfig Reporting.silent root details Build.IgnoreDocs) exposedModules

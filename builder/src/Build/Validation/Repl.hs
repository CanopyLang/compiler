{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | REPL artifact management for the Canopy build system.
--
-- This module provides specialized functionality for handling REPL
-- (Read-Eval-Print Loop) artifact generation and dependency management.
-- It coordinates REPL-specific compilation and error handling for
-- interactive development.
--
-- === Primary Functionality
--
-- * REPL artifact finalization ('finalizeReplArtifacts', 'ReplConfig')
-- * Dependency status handling for REPL compilation
-- * REPL-specific error reporting and recovery
-- * Interactive compilation artifact generation
--
-- === Usage Examples
--
-- @
-- -- Configure and finalize REPL artifacts
-- let config = ReplConfig env source modul resultMVars
-- result <- finalizeReplArtifacts config depsStatus results
-- case result of
--   Left replError -> handleReplError replError
--   Right artifacts -> useReplArtifacts artifacts
-- @
--
-- @since 0.19.1
module Build.Validation.Repl
  ( -- * REPL Configuration
    ReplConfig (..)
  , replEnv
  , replSource
  , replModule
  , replResultMVars
    -- * REPL Artifact Management
  , finalizeReplArtifacts
    -- * REPL Processing Helpers
  , compileReplInput
  , createReplArtifacts
  , handleSameDepsForRepl
  , handleBlockedDepsForRepl
  , handleNotFoundDepsForRepl
  ) where

-- Core AST and compilation imports
import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Compile

-- Canopy-specific imports
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg

-- Build system imports
import qualified Build.Artifacts.Management as Artifacts
import qualified Build.Dependencies as Dependencies
import qualified Build.Validation.Details as Details
import qualified Build.Validation.Imports as Imports
import Build.Types
  ( Env (..)
  , Result (..)
  , ResultDict
  , DepsStatus (..)
  , Module (..)
  , ReplArtifacts (..)
  , Dep
  , CDep
  )

-- Parser imports
import qualified Parse.Module as Parse

-- Standard library imports
import Control.Lens (makeLenses, (^.))
import qualified Data.ByteString as B
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Reporting.Error as Error
import qualified Reporting.Error.Import as Import
import qualified Reporting.Exit as Exit
import qualified Reporting.Render.Type.Localizer as L

-- | Configuration for REPL artifact finalization.
--
-- Groups REPL finalization parameters to meet CLAUDE.md requirement of ≤4 parameters
-- per function. Encapsulates all context needed for REPL artifact generation.
--
-- ==== Configuration Components
--
-- * **Environment**: Build environment with project context
-- * **Source**: Raw REPL input source code 
-- * **Module**: Parsed REPL module structure
-- * **Result MVars**: Compilation result dictionary for dependencies
--
-- @since 0.19.1
data ReplConfig = ReplConfig
  { _replEnv :: !Env
  -- ^ Build environment with project configuration and dependencies
  , _replSource :: !B.ByteString
  -- ^ Raw REPL input source code for error reporting
  , _replModule :: !Src.Module
  -- ^ Parsed REPL module structure for compilation
  , _replResultMVars :: !ResultDict
  -- ^ Compilation result dictionary for dependency resolution
  }

-- Generate lenses for ReplConfig
makeLenses ''ReplConfig

-- | Finalize REPL artifacts with dependency resolution.
--
-- Handles REPL finalization including dependency checking, interface loading,
-- and artifact generation with comprehensive error handling.
--
-- @since 0.19.1
finalizeReplArtifacts :: ReplConfig -> DepsStatus -> Map.Map ModuleName.Raw Result -> IO (Either Exit.Repl ReplArtifacts)
finalizeReplArtifacts config depsStatus results =
  case depsStatus of
    DepsChange ifaces -> compileReplInput config ifaces results
    DepsSame same cached -> handleSameDepsForRepl config results same cached
    DepsBlock -> handleBlockedDepsForRepl config results
    DepsNotFound problems -> handleNotFoundDepsForRepl config problems

-- | Compile REPL input with given interfaces.
--
-- Performs REPL module compilation and generates artifacts or errors.
--
-- @since 0.19.1
compileReplInput :: ReplConfig -> Map.Map ModuleName.Raw I.Interface -> Map.Map ModuleName.Raw Result -> IO (Either Exit.Repl ReplArtifacts)
compileReplInput config ifaces results =
  let env = config ^. replEnv
      source = config ^. replSource
      modul = config ^. replModule
      pkg = projectTypeToPkg (getProjectType env)
   in case Compile.compile pkg ifaces modul of
        Right (Compile.Artifacts canonical annotations objects) ->
          createReplArtifacts canonical annotations objects modul results
        Left errors ->
          return . Left $ Exit.ReplBadInput source errors

-- | Create REPL artifacts from compilation results.
--
-- Constructs the final REPL artifact structure from compilation components.
--
-- @since 0.19.1
createReplArtifacts :: Can.Module -> Map.Map Name.Name Can.Annotation -> Opt.LocalGraph -> Src.Module -> Map.Map ModuleName.Raw Result -> IO (Either Exit.Repl ReplArtifacts)
createReplArtifacts canonical annotations objects modul results = do
  let h = Can._name canonical
      m = Fresh (Src.getName modul) (I.fromModule (projectTypeToPkg Parse.Application) canonical annotations) objects
      ms = Map.foldrWithKey Artifacts.addInside [] results
  return . Right $ ReplArtifacts h (m : ms) (L.fromModule modul) annotations

-- | Handle same dependencies for REPL.
--
-- Attempts to load cached interfaces when dependencies haven't changed.
--
-- @since 0.19.1
handleSameDepsForRepl :: ReplConfig -> Map.Map ModuleName.Raw Result -> [Dep] -> [CDep] -> IO (Either Exit.Repl ReplArtifacts)
handleSameDepsForRepl config results same cached = do
  let env = config ^. replEnv
      root = getProjectRoot env
  maybeLoaded <- Dependencies.loadInterfaces root same cached
  case maybeLoaded of
    Just ifaces -> compileReplInput config ifaces results
    Nothing -> return . Left $ Exit.ReplBadCache

-- | Handle blocked dependencies for REPL.
--
-- Collects compilation errors when dependencies are blocked.
--
-- @since 0.19.1
handleBlockedDepsForRepl :: ReplConfig -> Map.Map ModuleName.Raw Result -> IO (Either Exit.Repl ReplArtifacts)
handleBlockedDepsForRepl config results =
  let env = config ^. replEnv
      root = getProjectRoot env
   in case Map.foldr Details.addErrors [] results of
        [] -> return . Left $ Exit.ReplBlocked
        e : es -> return . Left $ Exit.ReplBadLocalDeps root e es

-- | Handle not found dependencies for REPL.
--
-- Generates import error reports when REPL dependencies cannot be resolved.
--
-- @since 0.19.1
handleNotFoundDepsForRepl :: ReplConfig -> NE.List (ModuleName.Raw, Import.Problem) -> IO (Either Exit.Repl ReplArtifacts)
handleNotFoundDepsForRepl config problems =
  let env = config ^. replEnv
      source = config ^. replSource
      modul = config ^. replModule
      resultMVars = config ^. replResultMVars
      (Src.Module _ _ _ imports _ _ _ _ _ _) = modul
      importErrors = Imports.toImportErrors env resultMVars imports problems
   in return . Left $ Exit.ReplBadInput source (Error.BadImports importErrors)

-- | Convert project type to package name.
--
-- Helper function to resolve package names from project types for
-- compilation context setup.
--
-- @since 0.19.1
projectTypeToPkg :: Parse.ProjectType -> Pkg.Name
projectTypeToPkg projectType =
  case projectType of
    Parse.Package pkg -> pkg
    Parse.Application -> Pkg.dummyName

-- | Extract project type from environment.
--
-- Helper function to get project type from build environment.
--
-- @since 0.19.1
getProjectType :: Env -> Parse.ProjectType
getProjectType (Env _ _ projectType _ _ _ _) = projectType

-- | Extract project root from environment.
--
-- Helper function to get project root directory from build environment.
--
-- @since 0.19.1
getProjectRoot :: Env -> FilePath
getProjectRoot (Env _ root _ _ _ _ _) = root
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module compilation workflow for the Build system.
--
-- This module handles the core compilation workflow including module compilation,
-- documentation generation, artifact writing, and result determination.
-- All functions follow CLAUDE.md standards with proper separation of concerns.
--
-- === Compilation Workflow Overview
--
-- @
-- Compilation Pipeline:
-- ├── compile           -> Main compilation entry point
-- ├── compileWithDocs   -> Documentation handling
-- ├── writeModuleArtifacts -> Artifact writing  
-- └── determineResult   -> Result determination
-- @
--
-- === Usage Examples
--
-- @
-- -- Compile a module with interfaces
-- result <- compile env docsNeed localDetails source interfaces module
--
-- -- Compile with documentation handling
-- result <- compileWithDocs compileConfig
--
-- -- Write module artifacts  
-- result <- writeModuleArtifacts artifactConfig
-- @
--
-- === Error Handling
--
-- Compilation workflow can fail due to:
--
-- * Compilation errors in the AST transformation
-- * Documentation generation failures  
-- * File I/O errors during artifact writing
-- * Interface comparison issues
--
-- All workflow functions return 'Result' values with proper error information.
--
-- === Performance Considerations
--
-- The workflow is optimized for:
--
-- * Lazy evaluation of expensive operations
-- * Efficient interface comparison for change detection
-- * Minimal file I/O operations
-- * Proper resource cleanup
--
-- @since 0.19.1
module Build.Module.Check.Workflow
  ( -- * Main Compilation Functions
    compile
  , compileWithDocs
  
  -- * Configuration Types
  , CompileConfig(..)
  
  -- * Re-exported Artifact Management
  , module Build.Module.Check.Artifacts
  
  -- * Configuration Lenses
  , compileKey
  , compileRoot
  , compilePkg
  , compileModule
  , compileCanonical
  , compileAnnotations
  , compileObjects
  , compileDocsNeed
  , compileLocal
  , compileBuildID
  , compileSource
  
  -- * Utility Functions
  , projectTypeToPkg
  , makeDocs
  , recompileCachedModule
  , createCachedResult
  ) where

import qualified Control.Concurrent.STM as STM
import Control.Lens ((^.), makeLenses)
import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.Docs as Docs
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Compile
import qualified Data.ByteString as B
import Data.Map.Strict (Map)
import qualified Data.Name as Name
import qualified File
import qualified Parse.Module as Parse
import qualified Reporting
import qualified Reporting.Error as Error
import qualified Reporting.Error.Docs as EDocs

import Build.Types
  ( Env(..)
  , Result(..)
  , DocsNeed(..)
  , CachedInterface(..)
  )
import Build.Module.Check.Artifacts
  ( ArtifactConfig(..)
  , writeModuleArtifacts
  , artifactKey
  , artifactRoot
  , artifactPkg
  , artifactModule
  , artifactCanonical
  , artifactAnnotations
  , artifactObjects
  , artifactDocs
  , artifactLocal
  , artifactBuildID
  )
import Build.Module.Check.Config (CachedConfig(..), cachedEnv, cachedProjectType, cachedModuleName, cachedLocal)

-- | Configuration for module compilation.
data CompileConfig = CompileConfig
  { _compileKey :: !Reporting.BKey
  , _compileRoot :: !FilePath
  , _compilePkg :: !Pkg.Name
  , _compileModule :: !Src.Module
  , _compileCanonical :: !Can.Module
  , _compileAnnotations :: !(Map Name.Name Can.Annotation)
  , _compileObjects :: !Opt.LocalGraph
  , _compileDocsNeed :: !DocsNeed
  , _compileLocal :: !Details.Local
  , _compileBuildID :: !Details.BuildID
  , _compileSource :: !B.ByteString
  } deriving ()

-- Generate lenses for configuration records
makeLenses ''CompileConfig

-- | Main module compilation function.
--
-- Compiles a source module with the provided interfaces and environment.
-- Handles the complete compilation pipeline from AST compilation through
-- artifact generation and result determination.
--
-- ==== Parameters
--
-- [@env@] Build environment with configuration
-- [@docsNeed@] Documentation requirements
-- [@local@] Local module details
-- [@source@] Module source code
-- [@ifaces@] Available module interfaces
-- [@modul@] Parsed source module
--
-- ==== Returns
--
-- IO action producing compilation result or error
compile :: Env -> DocsNeed -> Details.Local -> B.ByteString -> Map ModuleName.Raw I.Interface -> Src.Module -> IO Result
compile (Env key root projectType _ buildID _ _) docsNeed local source ifaces modul = do
  let pkg = projectTypeToPkg projectType
  compileResult <- Compile.compile pkg ifaces modul
  case compileResult of
    Right (Compile.Artifacts canonical annotations objects _ffiInfo) ->
      createCompileConfig key root pkg modul canonical annotations objects docsNeed local buildID source >>= compileWithDocs
    Left err ->
      pure . RProblem $ Error.Module (Src.getName modul) (local ^. Details.path) (local ^. Details.time) source err
  where
    createCompileConfig k r p m c a o d l b s = pure $ CompileConfig
      { _compileKey = k
      , _compileRoot = r
      , _compilePkg = p
      , _compileModule = m
      , _compileCanonical = c
      , _compileAnnotations = a
      , _compileObjects = o
      , _compileDocsNeed = d
      , _compileLocal = l
      , _compileBuildID = b
      , _compileSource = s
      }

-- | Compile module with documentation handling.
--
-- Handles documentation generation for the compiled module and creates
-- appropriate artifact configurations for further processing.
--
-- ==== Parameters
--
-- [@config@] Compilation configuration with all necessary context
--
-- ==== Returns
--
-- IO action producing compilation result with documentation or error
compileWithDocs :: CompileConfig -> IO Result
compileWithDocs config = do
  docsResult <- makeDocs (config ^. compileDocsNeed) (config ^. compileCanonical)
  case docsResult of
    Left err -> createDocsError config err
    Right docs -> createArtifactConfig config docs >>= writeModuleArtifacts
  where
    createDocsError cfg err =
      let local = cfg ^. compileLocal
          moduleName = Src.getName (cfg ^. compileModule)
          path = local ^. Details.path
          time = local ^. Details.time
          source = cfg ^. compileSource
      in pure . RProblem $ Error.Module moduleName path time source (Error.BadDocs err)
    
    createArtifactConfig cfg docs =
      let local = cfg ^. compileLocal
      in pure $ ArtifactConfig
           { _artifactKey = cfg ^. compileKey
           , _artifactRoot = cfg ^. compileRoot
           , _artifactPkg = cfg ^. compilePkg
           , _artifactModule = cfg ^. compileModule
           , _artifactCanonical = cfg ^. compileCanonical
           , _artifactAnnotations = cfg ^. compileAnnotations
           , _artifactObjects = cfg ^. compileObjects
           , _artifactDocs = docs
           , _artifactLocal = local
           , _artifactBuildID = cfg ^. compileBuildID
           }


-- | Convert project type to package name.
--
-- Maps project types to appropriate package names for compilation context.
-- Applications use a dummy package name while packages use their actual name.
--
-- ==== Parameters
--
-- [@projectType@] Type of project being compiled
--
-- ==== Returns
--
-- Package name for compilation context
projectTypeToPkg :: Parse.ProjectType -> Pkg.Name
projectTypeToPkg projectType =
  case projectType of
    Parse.Package pkg -> pkg
    Parse.Application -> Pkg.dummyName

-- | Create documentation from canonical module.
--
-- Generates documentation for the module if needed, handling both
-- successful generation and error cases appropriately.
--
-- ==== Parameters
--
-- [@docsNeed@] Documentation requirements
-- [@modul@] Canonical module to document
--
-- ==== Returns
--
-- Either documentation error or optional documentation module
makeDocs :: DocsNeed -> Can.Module -> IO (Either EDocs.Error (Maybe Docs.Module))
makeDocs (DocsNeed isNeeded) modul =
  if isNeeded
    then do
      result <- Docs.fromModule modul
      case result of
        Right docs -> pure (Right (Just docs))
        Left err -> pure (Left err)
    else pure (Right Nothing)

-- | Recompile cached module with changed dependencies.
--
-- Recompiles a previously cached module when its dependencies have changed.
-- Reads the source file and performs full compilation with updated interfaces.
--
-- ==== Parameters
--
-- [@config@] Cached module configuration
-- [@path@] Path to the source file
-- [@time@] File modification time
-- [@ifaces@] Updated dependency interfaces
--
-- ==== Returns
--
-- IO action producing compilation result or parse error
recompileCachedModule :: CachedConfig -> FilePath -> File.Time -> Map ModuleName.Raw I.Interface -> IO Result
recompileCachedModule config path time ifaces = do
  source <- File.readUtf8 path
  case Parse.fromByteString (config ^. cachedProjectType) source of
    Right modul -> compile (config ^. cachedEnv) (DocsNeed False) (config ^. cachedLocal) source ifaces modul
    Left err -> pure . RProblem $ Error.Module (config ^. cachedModuleName) path time source (Error.BadSyntax err)

-- | Create cached result without recompilation.
--
-- Creates a result for modules that don't need recompilation based on
-- unchanged dependencies and source code.
--
-- ==== Parameters
--
-- [@hasMain@] Whether the module has a main function
-- [@lastChange@] Build ID of last interface change
--
-- ==== Returns
--
-- IO action producing cached result with appropriate status
createCachedResult :: Bool -> Details.BuildID -> IO Result
createCachedResult hasMain lastChange = do
  tvar <- STM.newTVarIO Unneeded
  pure (RCached hasMain lastChange tvar)

-- Import CachedConfig from Build.Module.Check.Config to avoid duplication
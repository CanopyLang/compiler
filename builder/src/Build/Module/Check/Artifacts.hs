{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Artifact management for module compilation.
--
-- This module handles the writing of compilation artifacts including
-- object files, interface files, and documentation. It also manages
-- result determination based on interface comparison.
--
-- === Artifact Management Overview
--
-- @
-- Artifact Pipeline:
-- ├── writeModuleArtifacts -> Write compiled artifacts to disk
-- ├── determineResult      -> Compare interfaces for change detection
-- ├── createSameResult     -> Handle unchanged interfaces
-- └── createNewResult      -> Handle changed interfaces  
-- @
--
-- === Usage Examples
--
-- @
-- -- Write module artifacts and determine result
-- result <- writeModuleArtifacts artifactConfig
--
-- -- Determine result based on interface comparison
-- result <- determineResult resultConfig
-- @
--
-- === File Operations
--
-- Artifact management performs these file operations:
--
-- * Write object files (.canopyo)
-- * Write interface files (.canopyi)
-- * Read previous interface files for comparison
-- * Report compilation status
--
-- === Error Handling
--
-- Artifact operations can fail due to:
--
-- * File I/O errors during writing
-- * Disk space issues
-- * Permission problems
-- * Interface serialization errors
--
-- @since 0.19.1
module Build.Module.Check.Artifacts
  ( -- * Artifact Management
    writeModuleArtifacts
  , determineResult
  
  -- * Configuration Types
  , ArtifactConfig(..)
  , ResultConfig(..)
  
  -- * Configuration Lenses
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
  , resultKey
  , resultInterface
  , resultMaybeOldInterface
  , resultModuleName
  , resultRoot
  , resultLocal
  , resultDocs
  , resultObjects
  ) where

import Control.Lens ((^.), (&), (.~), makeLenses)
import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.Docs as Docs
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Name as Name
import Data.Map.Strict (Map)
import qualified File
import qualified Reporting
import qualified Stuff

import Build.Types (Result(..))

-- | Configuration for artifact writing.
data ArtifactConfig = ArtifactConfig
  { _artifactKey :: !Reporting.BKey
  , _artifactRoot :: !FilePath
  , _artifactPkg :: !Pkg.Name
  , _artifactModule :: !Src.Module
  , _artifactCanonical :: !Can.Module
  , _artifactAnnotations :: !(Map Name.Name Can.Annotation)
  , _artifactObjects :: !Opt.LocalGraph
  , _artifactDocs :: !(Maybe Docs.Module)
  , _artifactLocal :: !Details.Local
  , _artifactBuildID :: !Details.BuildID
  } deriving ()

-- | Configuration for result determination.
data ResultConfig = ResultConfig
  { _resultKey :: !Reporting.BKey
  , _resultInterface :: !I.Interface
  , _resultMaybeOldInterface :: !(Maybe I.Interface)
  , _resultModuleName :: !ModuleName.Raw
  , _resultRoot :: !FilePath
  , _resultLocal :: !Details.Local
  , _resultDocs :: !(Maybe Docs.Module)
  , _resultObjects :: !Opt.LocalGraph
  } deriving ()

-- Generate lenses for configuration records
makeLenses ''ArtifactConfig
makeLenses ''ResultConfig

-- | Write module artifacts and determine result.
--
-- Writes compiled artifacts to disk and determines the final result
-- based on interface comparison with previous compilation.
--
-- ==== Parameters
--
-- [@config@] Artifact configuration with compiled data
--
-- ==== Returns
--
-- IO action producing final compilation result
writeModuleArtifacts :: ArtifactConfig -> IO Result
writeModuleArtifacts config = do
  let name = Src.getName (config ^. artifactModule)
      iface = I.fromModule (config ^. artifactPkg) (config ^. artifactCanonical) (config ^. artifactAnnotations)
      root = config ^. artifactRoot
      objects = config ^. artifactObjects
  File.writeBinary (Stuff.canopyo root name) objects
  maybeOldi <- File.readBinary (Stuff.canopyi root name)
  createResultConfig config iface maybeOldi name >>= determineResult
  where
    createResultConfig cfg iface maybeOldi moduleName =
      let local = cfg ^. artifactLocal
          root = cfg ^. artifactRoot
      in pure $ ResultConfig
           { _resultKey = cfg ^. artifactKey
           , _resultInterface = iface
           , _resultMaybeOldInterface = maybeOldi
           , _resultModuleName = moduleName
           , _resultRoot = root
           , _resultLocal = local
           , _resultDocs = cfg ^. artifactDocs
           , _resultObjects = cfg ^. artifactObjects
           }

-- | Determine final result based on interface comparison.
--
-- Compares the new interface with the previous interface to determine
-- if the module interface has changed, affecting dependent modules.
--
-- ==== Parameters
--
-- [@config@] Result configuration with interface comparison data
--
-- ==== Returns
--
-- IO action producing final result based on interface comparison
determineResult :: ResultConfig -> IO Result
determineResult config =
  case config ^. resultMaybeOldInterface of
    Just oldi | oldi == iface -> createSameResult config
    _ -> createNewResult config
  where
    iface = config ^. resultInterface
    
    createSameResult cfg = do
      Reporting.report (cfg ^. resultKey) Reporting.BDone
      let local = cfg ^. resultLocal
      pure (RSame local iface (cfg ^. resultObjects) (cfg ^. resultDocs))
    
    createNewResult cfg = do
      File.writeBinary (Stuff.canopyi (cfg ^. resultRoot) (cfg ^. resultModuleName)) iface
      Reporting.report (cfg ^. resultKey) Reporting.BDone
      let local = cfg ^. resultLocal
          newLocal = local & Details.lastChange .~ (local ^. Details.lastCompile)
      pure (RNew newLocal iface (cfg ^. resultObjects) (cfg ^. resultDocs))
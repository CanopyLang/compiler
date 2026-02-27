{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Pure build artifact types for NEW compiler.
--
-- This replaces the OLD Build/Types.hs STM-based types with pure functional
-- equivalents suitable for the NEW query-based compiler.
--
-- @since 0.19.1
module Build.Artifacts
  ( -- * Artifact Types
    Artifacts (..)
  , Module (..)
  , Root (..)
  , DocsGoal (..)

  -- * Lenses
  , artifactsName
  , artifactsDeps
  , artifactsRoots
  , artifactsModules
  , artifactsFFIInfo
  , artifactsGlobalGraph
  , artifactsLazyModules
  )
where

import Control.Lens (makeLenses)
import Data.Map.Strict (Map)
import Data.Set (Set)
import Data.NonEmptyList (List)
import qualified AST.Optimized as Opt
import qualified Canopy.Docs as Docs
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Generate.JavaScript as JS

-- | Root module specification for entry points.
data Root
  = Inside ModuleName.Raw
  | Outside ModuleName.Raw Interface.Interface Opt.LocalGraph
  deriving (Show)

-- | Module compilation result - pure version without STM.
data Module
  = Fresh ModuleName.Raw Interface.Interface Opt.LocalGraph
  deriving (Show)

-- | Documentation goal for build.
data DocsGoal a where
  KeepDocs :: DocsGoal Docs.Documentation
  WriteDocs :: FilePath -> DocsGoal ()
  IgnoreDocs :: DocsGoal ()

-- | Build artifacts containing all compiled modules and dependencies.
data Artifacts = Artifacts
  { _artifactsName :: !Pkg.Name
  , _artifactsDeps :: !(Map ModuleName.Canonical Interface.DependencyInterface)
  , _artifactsRoots :: !(List Root)
  , _artifactsModules :: ![Module]
  , _artifactsFFIInfo :: !(Map String JS.FFIInfo)
  , _artifactsGlobalGraph :: !Opt.GlobalGraph
  , _artifactsLazyModules :: !(Set ModuleName.Canonical)
  }
  deriving (Show)

makeLenses ''Artifacts

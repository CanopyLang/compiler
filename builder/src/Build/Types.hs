{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core types for the Build system.
--
-- This module centralizes all data types used throughout the build system,
-- providing lens support and clear type definitions to improve maintainability.
module Build.Types
  ( -- * Environment Types
    Env (..)
  , AbsoluteSrcDir (..)
  
  -- * Status Types  
  , Status (..)
  , StatusDict
  , DocsNeed (..)
  
  -- * Result Types
  , Result (..)
  , ResultDict
  , CachedInterface (..)
  
  -- * Dependency Types
  , Dependencies
  , Dep
  , CDep
  , DepsStatus (..)
  
  -- * Root Types
  , RootLocation (..)
  , RootInfo (..)
  , RootStatus (..)
  , RootResult (..)
  , Root (..)
  
  -- * Artifact Types
  , Artifacts (..)
  , Module (..)
  , ReplArtifacts (..)
  
  -- * Documentation Types
  , DocsGoal (..)
  
  -- * Configuration Types
  , CheckConfig (..)
  , CrawlConfig (..)
  , CompileConfig (..)
  , DepsConfig (..)
  
  -- * Lenses
  , envKey
  , envRoot
  , envProject
  , envSrcDirs
  , envBuildID
  , envLocals
  , envForeigns
  , artifactsName
  , artifactsDeps
  , artifactsRoots
  , artifactsModules
  , replHome
  , replModules
  , replLocalizer
  , replAnnotations
  , rootInfoAbsolute
  , rootInfoRelative
  , rootInfoLocation
  -- Config lenses
  , checkEnv
  , checkForeigns
  , checkResultsMVar
  , crawlEnv
  , crawlMVar
  , crawlDocsNeed
  , compileEnv
  , compileDocsNeed
  , compileLocal
  , compileSource
  , depsRoot
  , depsResults
  , depsList
  , depsLastCompile
  ) where

import Control.Concurrent.MVar (MVar)
import Control.Lens (makeLenses)
import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.Docs as Docs
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString as B
import Data.Map.Strict (Map)
import qualified Data.Name as Name
import Data.NonEmptyList (List)
import qualified Data.OneOrMore as OneOrMore
import qualified File
import qualified Parse.Module as Parse
import qualified Reporting
import qualified Reporting.Error as Error
import qualified Reporting.Error.Docs as EDocs
import qualified Reporting.Error.Import as Import
import qualified Reporting.Error.Syntax as Syntax
import qualified Reporting.Render.Type.Localizer as L

-- ENVIRONMENT

data Env = Env
  { _envKey :: !Reporting.BKey
  , _envRoot :: !FilePath
  , _envProject :: !Parse.ProjectType
  , _envSrcDirs :: ![AbsoluteSrcDir]
  , _envBuildID :: !Details.BuildID
  , _envLocals :: !(Map ModuleName.Raw Details.Local)
  , _envForeigns :: !(Map ModuleName.Raw Details.Foreign)
  } deriving ()

newtype AbsoluteSrcDir = AbsoluteSrcDir FilePath
  deriving (Eq, Show)

-- STATUS TYPES

data Status
  = SCached Details.Local
  | SChanged Details.Local B.ByteString Src.Module DocsNeed
  | SBadImport Import.Problem
  | SBadSyntax FilePath File.Time B.ByteString Syntax.Error
  | SForeign Pkg.Name
  | SKernel
  deriving ()

type StatusDict = Map ModuleName.Raw (MVar Status)

newtype DocsNeed = DocsNeed {needsDocs :: Bool}
  deriving (Eq, Show)

-- RESULT TYPES

data Result
  = RNew !Details.Local !I.Interface !Opt.LocalGraph !(Maybe Docs.Module)
  | RSame !Details.Local !I.Interface !Opt.LocalGraph !(Maybe Docs.Module)
  | RCached Bool Details.BuildID (MVar CachedInterface)
  | RNotFound Import.Problem
  | RProblem Error.Module
  | RBlocked
  | RForeign I.Interface
  | RKernel
  deriving ()

type ResultDict = Map ModuleName.Raw (MVar Result)

data CachedInterface
  = Unneeded
  | Loaded I.Interface
  | Corrupted
  deriving (Show)

-- DEPENDENCY TYPES

type Dependencies = Map ModuleName.Canonical I.DependencyInterface
type Dep = (ModuleName.Raw, I.Interface)
type CDep = (ModuleName.Raw, MVar CachedInterface)

data DepsStatus
  = DepsChange (Map ModuleName.Raw I.Interface)
  | DepsSame [Dep] [CDep]
  | DepsBlock
  | DepsNotFound (List (ModuleName.Raw, Import.Problem))
  deriving ()

-- ROOT TYPES

data RootLocation
  = LInside ModuleName.Raw
  | LOutside FilePath
  deriving (Show)

data RootInfo = RootInfo
  { _rootInfoAbsolute :: !FilePath
  , _rootInfoRelative :: !FilePath
  , _rootInfoLocation :: !RootLocation
  } deriving ()

data RootStatus
  = SInside ModuleName.Raw
  | SOutsideOk Details.Local B.ByteString Src.Module
  | SOutsideErr Error.Module
  deriving ()

data RootResult
  = RInside ModuleName.Raw
  | ROutsideOk ModuleName.Raw I.Interface Opt.LocalGraph
  | ROutsideErr Error.Module
  | ROutsideBlocked
  deriving ()

data Root
  = Inside ModuleName.Raw
  | Outside ModuleName.Raw I.Interface Opt.LocalGraph
  deriving (Show)

-- ARTIFACT TYPES

data Artifacts = Artifacts
  { _artifactsName :: !Pkg.Name
  , _artifactsDeps :: !Dependencies
  , _artifactsRoots :: !(List Root)
  , _artifactsModules :: ![Module]
  } deriving (Show)

data Module
  = Fresh ModuleName.Raw I.Interface Opt.LocalGraph
  | Cached ModuleName.Raw Bool (MVar CachedInterface)
  deriving ()

instance Show Module where
  show (Fresh name iface objs) = "Fresh " <> show name <> " " <> show iface <> " " <> show objs
  show (Cached name main _) = "Cached " <> show name <> " " <> show main <> " <MVar>"

data ReplArtifacts = ReplArtifacts
  { _replHome :: !ModuleName.Canonical
  , _replModules :: ![Module]
  , _replLocalizer :: !L.Localizer
  , _replAnnotations :: !(Map Name.Name Can.Annotation)
  } deriving ()

-- DOCUMENTATION TYPES

data DocsGoal a where
  KeepDocs :: DocsGoal Docs.Documentation
  WriteDocs :: FilePath -> DocsGoal ()
  IgnoreDocs :: DocsGoal ()

-- CONFIGURATION TYPES

-- | Configuration for module checking operations.
data CheckConfig = CheckConfig
  { _checkEnv :: !Env
  , _checkForeigns :: !Dependencies  
  , _checkResultsMVar :: !(MVar ResultDict)
  }

-- | Configuration for module crawling operations.
data CrawlConfig = CrawlConfig
  { _crawlEnv :: !Env
  , _crawlMVar :: !(MVar StatusDict)
  , _crawlDocsNeed :: !DocsNeed
  }

-- | Configuration for compilation operations.
data CompileConfig = CompileConfig
  { _compileEnv :: !Env
  , _compileDocsNeed :: !DocsNeed
  , _compileLocal :: !Details.Local
  , _compileSource :: !B.ByteString
  }

-- | Configuration for dependency checking operations.
data DepsConfig = DepsConfig
  { _depsRoot :: !FilePath
  , _depsResults :: !ResultDict
  , _depsList :: ![ModuleName.Raw]
  , _depsLastCompile :: !Details.BuildID
  }

-- Generate lenses for all record types
makeLenses ''Env
makeLenses ''Artifacts
makeLenses ''ReplArtifacts
makeLenses ''RootInfo
makeLenses ''CheckConfig
makeLenses ''CrawlConfig
makeLenses ''CompileConfig
makeLenses ''DepsConfig
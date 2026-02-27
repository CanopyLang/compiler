{-# LANGUAGE OverloadedStrings #-}

-- | Build system re-exports for Terminal.
--
-- This module re-exports types from canopy-builder's Build.Artifacts
-- to maintain backward compatibility with Terminal code that expects
-- Build.Module, Build.Root, etc.
--
-- The actual build functionality is provided by Compiler.hs which wraps
-- the NEW query-based Driver.
--
-- @since 0.19.1
module Build
  ( -- * Re-exported from Build.Artifacts
    Module (..)
  , Root (..)
  , Artifacts (..)

  -- * Lenses
  , artifactsName
  , artifactsDeps
  , artifactsRoots
  , artifactsModules
  , artifactsFFIInfo
  , artifactsGlobalGraph
  , artifactsLazyModules

  -- * Build Configuration
  , ExposedBuildConfig (..)

  -- * Build Functions
  , fromPaths
  , fromExposed
  , fromRepl
  , getRootNames
  )
where

import Build.Artifacts
  ( Module (..)
  , Root (..)
  , Artifacts (..)
  , artifactsName
  , artifactsDeps
  , artifactsRoots
  , artifactsModules
  , artifactsFFIInfo
  , artifactsGlobalGraph
  , artifactsLazyModules
  )
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Compiler
import Control.Lens ((^.))
import qualified Data.Name as Name
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NonEmptyList
import qualified Exit as BuildExit
import qualified Reporting

-- | Configuration for building exposed modules.
data ExposedBuildConfig = ExposedBuildConfig
  !Reporting.Style
  !FilePath
  !Details.Details

-- | Build from specific file paths.
fromPaths ::
  Reporting.Style ->
  FilePath ->
  Details.Details ->
  [FilePath] ->
  IO (Either BuildExit.BuildError Artifacts)
fromPaths _style root details paths = do
  let pkg = case details ^. Details.detailsOutline of
        Details.ValidApp _ -> Details.dummyPkgName
        Details.ValidPkg pkgName _ _ -> pkgName
      isApp = case details ^. Details.detailsOutline of
        Details.ValidApp _ -> True
        Details.ValidPkg _ _ _ -> False
      srcDirs = details ^. Details.detailsSrcDirs
  case paths of
    [] -> pure (Left (BuildExit.BuildBadArgs "No paths provided"))
    _ -> Compiler.compileFromPaths pkg isApp root (fmap Compiler.RelativeSrcDir srcDirs) paths

-- | Build from exposed modules.
fromExposed ::
  ExposedBuildConfig ->
  List ModuleName.Raw ->
  IO (Either BuildExit.BuildError Artifacts)
fromExposed (ExposedBuildConfig _style root details) exposedModules = do
  let pkg = case details ^. Details.detailsOutline of
        Details.ValidApp _ -> Details.dummyPkgName
        Details.ValidPkg pkgName _ _ -> pkgName
      isApp = case details ^. Details.detailsOutline of
        Details.ValidApp _ -> True
        Details.ValidPkg _ _ _ -> False
      srcDirs = details ^. Details.detailsSrcDirs
  Compiler.compileFromExposed pkg isApp root (fmap Compiler.AbsoluteSrcDir srcDirs) exposedModules

-- | Build for REPL.
fromRepl ::
  FilePath ->
  Details.Details ->
  IO (Either BuildExit.BuildError Artifacts)
fromRepl root details = do
  let pkg = case details ^. Details.detailsOutline of
        Details.ValidApp _ -> Details.dummyPkgName
        Details.ValidPkg pkgName _ _ -> pkgName
      isApp = case details ^. Details.detailsOutline of
        Details.ValidApp _ -> True
        Details.ValidPkg _ _ _ -> False
      srcDirs = details ^. Details.detailsSrcDirs
  -- For REPL, compile all source directories
  Compiler.compileFromExposed pkg isApp root (fmap Compiler.AbsoluteSrcDir srcDirs) (NonEmptyList.List (Name.fromChars "Main") [])

-- | Extract root module names from artifacts.
getRootNames :: Artifacts -> List ModuleName.Raw
getRootNames artifacts =
  let roots = artifacts ^. artifactsRoots
   in fmap extractRootName roots

-- Helper: Extract name from root.
extractRootName :: Root -> ModuleName.Raw
extractRootName (Inside name) = name
extractRootName (Outside name _ _) = name

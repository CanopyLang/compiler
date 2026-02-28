{-# LANGUAGE OverloadedStrings #-}

-- | Project outline loading and validation.
--
-- This module handles loading and processing project outline files
-- for diff operations. It validates project structure, extracts
-- package information, and ensures compatibility with diff analysis
-- following CLAUDE.md patterns.
--
-- @since 0.19.1
module Diff.Outline
  ( -- * Loading
    load,

    -- * Information Extraction
    extractPackageName,
    extractPackageVersion,
  )
where

import qualified Canopy.Outline as Outline
import Canopy.Package (Name)
import Canopy.Version (Version)
import Control.Lens ((^.))
import Diff.Types (Env, Task, envMaybeRoot)
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Load project outline from environment.
--
-- Reads and validates the project outline file, ensuring it represents
-- a valid package (not an application) suitable for diff analysis.
--
-- @since 0.19.1
load :: Env -> Task Outline.Outline
load env = do
  root <- validateRoot env
  result <- Task.io (Outline.read root)
  processOutlineResult result

-- | Validate project root exists.
validateRoot :: Env -> Task FilePath
validateRoot env =
  case env ^. envMaybeRoot of
    Nothing -> Task.throw Exit.DiffNoOutline
    Just root -> pure root

-- | Process outline loading result.
processOutlineResult :: Either String Outline.Outline -> Task Outline.Outline
processOutlineResult result =
  case result of
    Left _ -> Task.throw Exit.DiffNoOutline
    Right outline -> validateOutlineType outline

-- | Validate outline represents a package, not application.
validateOutlineType :: Outline.Outline -> Task Outline.Outline
validateOutlineType outline =
  case outline of
    Outline.App _ -> Task.throw Exit.DiffApplication
    Outline.Pkg _ -> pure outline

-- | Extract package name from validated outline.
--
-- Retrieves the package name from a validated outline structure.
-- Used for registry lookups and version resolution.
--
-- @since 0.19.1
extractPackageName :: Outline.Outline -> Task Name
extractPackageName outline =
  case outline of
    Outline.App _ -> Task.throw Exit.DiffApplication
    Outline.Pkg (Outline.PkgOutline pkg _ _ _ _ _ _ _) -> pure pkg

-- | Extract package version from validated outline.
--
-- Retrieves the current package version from a validated outline.
-- Used to compute suggested version bumps in diff output.
--
-- @since 0.19.2
extractPackageVersion :: Outline.Outline -> Task Version
extractPackageVersion outline =
  case outline of
    Outline.App _ -> Task.throw Exit.DiffApplication
    Outline.Pkg (Outline.PkgOutline _ _ _ ver _ _ _ _) -> pure ver

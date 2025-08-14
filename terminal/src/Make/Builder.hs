{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Code generation and building functionality.
--
-- This module handles the core compilation pipeline, including building
-- from source files, generating artifacts, and creating output builders.
-- It coordinates between parsing, type checking, optimization, and
-- code generation phases.
--
-- Key functions:
--   * 'buildFromExposed' - Build from exposed package modules
--   * 'buildFromPaths' - Build from specific file paths
--   * 'createBuilder' - Generate output builder from artifacts
--   * 'extractModuleInfo' - Analyze module metadata
--
-- The module follows CLAUDE.md guidelines with functions ≤15 lines,
-- comprehensive error handling, and lens-based record access.
--
-- @since 0.19.1
module Make.Builder
  ( -- * Building Functions
    buildFromExposed,
    buildFromPaths,

    -- * Builder Creation
    createBuilder,

    -- * Module Analysis
    extractMainModules,
    extractNonMainModules,
    hasExactlyOneMain,

    -- * Helper Functions
    isMainModule,
    getModuleMain,
  )
where

import qualified AST.Optimized as Opt
import qualified Build
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import Control.Lens ((^.))
import Data.ByteString.Builder (Builder)
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NonEmptyList
import qualified Generate
import Make.Types
  ( BuildContext,
    DesiredMode (..),
    Task,
    bcDesiredMode,
    bcDetails,
    bcRoot,
    bcStyle,
  )
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Build project from exposed package modules.
--
-- Compiles all modules listed in the package outline's exposed-modules
-- field. Used for package builds where specific modules are exposed
-- to consumers.
--
-- @
-- artifacts <- buildFromExposed ctx exposedModules maybeDocs
-- @
buildFromExposed ::
  BuildContext ->
  List ModuleName.Raw ->
  Maybe FilePath ->
  Task ()
buildFromExposed ctx exposedModules maybeDocs = do
  let style = ctx ^. bcStyle
      root = ctx ^. bcRoot
      details = ctx ^. bcDetails
      docsGoal = maybe Build.IgnoreDocs Build.WriteDocs maybeDocs
  Task.eio Exit.MakeCannotBuild $
    Build.fromExposed style root details docsGoal exposedModules

-- | Build project from specific file paths.
--
-- Compiles modules found at the given file paths. Used for application
-- builds and targeted compilation of specific modules.
--
-- @
-- artifacts <- buildFromPaths ctx [\"src/Main.hs\", \"src/Utils.hs\"]
-- @
buildFromPaths ::
  BuildContext ->
  List FilePath ->
  Task Build.Artifacts
buildFromPaths ctx paths = do
  let style = ctx ^. bcStyle
      root = ctx ^. bcRoot
      details = ctx ^. bcDetails
  Task.eio Exit.MakeCannotBuild $
    Build.fromPaths style root details paths

-- | Create output builder from compiled artifacts.
--
-- Generates the appropriate code builder based on the desired build mode.
-- The builder contains the final JavaScript or other target code.
--
-- Build modes:
--   * 'Debug' - Includes debug information and readable output
--   * 'Dev' - Fast compilation with minimal optimization
--   * 'Prod' - Full optimization for production deployment
createBuilder ::
  BuildContext ->
  Build.Artifacts ->
  Task Builder
createBuilder ctx artifacts = do
  let root = ctx ^. bcRoot
      details = ctx ^. bcDetails
      mode = ctx ^. bcDesiredMode
  generateForMode root details mode artifacts

-- | Generate builder for specific build mode.
--
-- Delegates to the appropriate Generate function based on mode.
-- Each mode has different optimization and output characteristics.
generateForMode ::
  FilePath ->
  Details.Details ->
  DesiredMode ->
  Build.Artifacts ->
  Task Builder
generateForMode root details mode artifacts =
  Task.mapError Exit.MakeBadGenerate $
    case mode of
      Debug -> Generate.debug root details artifacts
      Dev -> Generate.dev root details artifacts
      Prod -> Generate.prod root details artifacts

-- | Extract modules that contain main functions.
--
-- Scans build artifacts to find modules with executable main functions.
-- Used to determine output format and entry points for applications.
--
-- @
-- mains <- extractMainModules artifacts
-- case mains of
--   [] -> generateLibrary artifacts
--   [main] -> generateSingleApp main artifacts
--   mains -> generateMultiApp mains artifacts
-- @
extractMainModules :: Build.Artifacts -> [ModuleName.Raw]
extractMainModules (Build.Artifacts _ _ roots modules) =
  Maybe.mapMaybe (getModuleMain modules) (NonEmptyList.toList roots)

-- | Extract modules that do not contain main functions.
--
-- Finds library modules without executable entry points. Used for
-- JavaScript output validation - ensures no main functions are
-- accidentally included in library builds.
extractNonMainModules :: Build.Artifacts -> [ModuleName.Raw]
extractNonMainModules (Build.Artifacts _ _ roots modules) =
  Maybe.mapMaybe (getNonMainModule modules) (NonEmptyList.toList roots)

-- | Check if artifacts contain exactly one main module.
--
-- Validates that HTML output has exactly one entry point. Returns
-- the main module name or throws an appropriate error.
--
-- Errors:
--   * No main functions found
--   * Multiple main functions found (invalid for HTML)
hasExactlyOneMain :: Build.Artifacts -> Task ModuleName.Raw
hasExactlyOneMain (Build.Artifacts _ _ roots modules) =
  case roots of
    NonEmptyList.List root [] ->
      Task.mio Exit.MakeNoMain (pure $ getModuleMain modules root)
    NonEmptyList.List _ (_ : _) ->
      Task.throw Exit.MakeMultipleFilesIntoHtml

-- | Get main function from specific module.
--
-- Checks if a build root contains a main function. Returns the module
-- name if a main function is found, Nothing otherwise.
getModuleMain :: [Build.Module] -> Build.Root -> Maybe ModuleName.Raw
getModuleMain modules root =
  case root of
    Build.Inside name ->
      if any (isMainModule name) modules
        then Just name
        else Nothing
    Build.Outside name _ (Opt.LocalGraph maybeMain _ _) ->
      case maybeMain of
        Just _ -> Just name
        Nothing -> Nothing

-- | Get non-main module from build root.
--
-- Returns module name if it doesn't contain a main function and
-- isn't named "Main". Used for library module extraction.
getNonMainModule :: [Build.Module] -> Build.Root -> Maybe ModuleName.Raw
getNonMainModule modules root =
  case root of
    Build.Inside name ->
      if any (isMainModule name) modules || Name.toChars name == "Main"
        then Nothing
        else Just name
    Build.Outside name _ (Opt.LocalGraph maybeMain _ _) ->
      case maybeMain of
        Just _ -> Nothing
        Nothing -> Just name

-- | Check if module contains a main function.
--
-- Examines build module to determine if it defines an executable
-- main function. Works with both fresh and cached modules.
isMainModule :: ModuleName.Raw -> Build.Module -> Bool
isMainModule targetName modul =
  case modul of
    Build.Fresh name _ (Opt.LocalGraph maybeMain _ _) ->
      Maybe.isJust maybeMain && name == targetName
    Build.Cached name mainIsDefined _ ->
      mainIsDefined && name == targetName

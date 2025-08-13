{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Output generation and target handling.
--
-- This module manages the generation of final build outputs, including
-- JavaScript files, HTML files, and null output for testing. It handles
-- output format selection, target validation, and file generation.
--
-- Key functions:
--   * 'generateOutput' - Generate output based on target type
--   * 'generateJavaScript' - Create JavaScript output
--   * 'generateHtml' - Create HTML output with wrapper
--   * 'selectOutputFormat' - Choose format based on main functions
--
-- The module follows CLAUDE.md guidelines with functions ≤15 lines,
-- comprehensive error handling, and lens-based record access.
--
-- @since 0.19.1
module Make.Output
  ( -- * Output Generation
    generateOutput,
    generateForTarget,
    selectOutputFormat,

    -- * Specific Generators
    generateJavaScript,
    generateHtml,
    generateDevNull,

    -- * Format Selection
    chooseFormatFromMains,
  )
where

import qualified Build
import qualified Canopy.ModuleName as ModuleName
import Control.Lens ((^.))
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Generate.Html as Html
import Logging.Logger (printLog)
import Make.Builder (createBuilder, extractMainModules, hasExactlyOneMain)
import Make.Generation (writeOutputFile)
import Make.Types
  ( BuildContext,
    Output (..),
    Task,
    bcStyle,
  )
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Generate output based on artifacts and optional target.
--
-- Determines the appropriate output format and generates the final
-- build result. If no target is specified, selects format based on
-- the number of main functions found.
--
-- @
-- generateOutput ctx artifacts Nothing      -- Auto-select format
-- generateOutput ctx artifacts (Just target) -- Use specific target
-- @
generateOutput ::
  BuildContext ->
  Build.Artifacts ->
  Maybe Output ->
  Task ()
generateOutput ctx artifacts maybeTarget =
  case maybeTarget of
    Nothing -> selectOutputFormat ctx artifacts
    Just target -> generateForTarget ctx artifacts target

-- | Select output format based on main function analysis.
--
-- Automatically chooses the appropriate output format:
--   * No mains → No output (library)
--   * One main → HTML output for application
--   * Multiple mains → JavaScript output for multi-entry
chooseFormatFromMains :: BuildContext -> Build.Artifacts -> Task ()
chooseFormatFromMains ctx artifacts =
  case extractMainModules artifacts of
    [] -> generateNoOutput
    [mainName] -> generateSingleAppHtml ctx artifacts mainName
    mainNames -> generateMultiAppJs ctx artifacts mainNames

-- | Generate output for specific target format.
--
-- Creates output according to the specified target type. Validates
-- that the target is compatible with the compiled artifacts.
generateForTarget :: BuildContext -> Build.Artifacts -> Output -> Task ()
generateForTarget _ _ DevNull = generateDevNull
generateForTarget ctx artifacts (JS target) =
  generateJavaScript ctx artifacts target
generateForTarget ctx artifacts (Html target) =
  generateHtml ctx artifacts target

-- | Generate JavaScript output to specified file.
--
-- Creates JavaScript output from artifacts. Validates that no main
-- functions are present (main functions require HTML wrapper).
generateJavaScript ::
  BuildContext ->
  Build.Artifacts ->
  FilePath ->
  Task ()
generateJavaScript ctx artifacts target = do
  validateNoMainsForJs artifacts
  Task.io (printLog ("Generating JavaScript to: " <> target))
  builder <- createBuilder ctx artifacts
  let rootNames = Build.getRootNames artifacts
  writeOutputFile (ctx ^. bcStyle) target builder rootNames

-- | Generate HTML output to specified file.
--
-- Creates HTML output with embedded JavaScript. Requires exactly one
-- main function to serve as the application entry point.
generateHtml ::
  BuildContext ->
  Build.Artifacts ->
  FilePath ->
  Task ()
generateHtml ctx artifacts target = do
  Task.io (printLog ("Generating HTML to: " <> target))
  mainName <- hasExactlyOneMain artifacts
  builder <- createBuilder ctx artifacts
  let htmlBuilder = Html.sandwich mainName builder
  writeOutputFile (ctx ^. bcStyle) target htmlBuilder (NE.List mainName [])

-- | Generate null output (no files created).
--
-- Used for testing and benchmarking builds without creating output files.
-- Simply logs the action and returns without generating anything.
generateDevNull :: Task ()
generateDevNull =
  Task.io (printLog "Output target is /dev/null - generating nothing")

-- | Generate no output for library builds.
--
-- Used when no main functions are found, indicating a library build
-- that doesn't produce executable output.
generateNoOutput :: Task ()
generateNoOutput =
  Task.io (printLog "No main functions found - generating nothing")

-- | Generate HTML for single-application build.
--
-- Creates index.html with the single main function as entry point.
-- Used for simple applications with one executable module.
generateSingleAppHtml ::
  BuildContext ->
  Build.Artifacts ->
  ModuleName.Raw ->
  Task ()
generateSingleAppHtml ctx artifacts mainName = do
  Task.io (printLog ("Found single main function - generating HTML: " <> Name.toChars mainName))
  builder <- createBuilder ctx artifacts
  let htmlBuilder = Html.sandwich mainName builder
      target = "index.html"
  writeOutputFile (ctx ^. bcStyle) target htmlBuilder (NE.List mainName [])

-- | Generate JavaScript for multi-application build.
--
-- Creates canopy.js with multiple entry points. Used for complex
-- applications with multiple executable modules.
generateMultiAppJs ::
  BuildContext ->
  Build.Artifacts ->
  [ModuleName.Raw] ->
  Task ()
generateMultiAppJs ctx artifacts mainNames =
  case mainNames of
    [] -> generateNoOutput
    name : rest -> do
      let nameStrs = fmap Name.toChars mainNames
      Task.io (printLog ("Found multiple main functions - generating JS: " <> show nameStrs))
      builder <- createBuilder ctx artifacts
      let target = "canopy.js"
      writeOutputFile (ctx ^. bcStyle) target builder (NE.List name rest)

-- | Validate that artifacts contain no main functions for JS output.
--
-- JavaScript output should not contain main functions, as they require
-- HTML wrapper for proper execution. Throws error if mains are found.
validateNoMainsForJs :: Build.Artifacts -> Task ()
validateNoMainsForJs artifacts =
  case extractMainModules artifacts of
    [] -> pure ()
    name : names -> Task.throw (Exit.MakeNonMainFilesIntoJavaScript name names)

-- | Select output format automatically based on artifacts.
--
-- Alias for 'chooseFormatFromMains' to maintain consistent naming
-- across the module interface.
selectOutputFormat :: BuildContext -> Build.Artifacts -> Task ()
selectOutputFormat = chooseFormatFromMains

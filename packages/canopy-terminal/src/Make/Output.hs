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

    -- * Utilities
    fixEmbeddedJavaScript,
  )
where

import qualified Build
import qualified Canopy.ModuleName as ModuleName
import Control.Lens ((^.))
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString as ByteString
import Data.Function ((&))
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NonEmptyList
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Generate.Html as Html
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Make.Builder (createBuilder, extractMainModules, hasExactlyOneMain)
import Make.Generation (writeOutputFile)
import Make.Types
  ( BuildContext,
    Output (..),
    Task,
    bcStyle,
  )
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
-- Creates JavaScript output from artifacts. Supports main functions
-- for creating executable JavaScript applications.
generateJavaScript ::
  BuildContext ->
  Build.Artifacts ->
  FilePath ->
  Task ()
generateJavaScript ctx artifacts target = do
  Task.io (Log.logEvent (BuildStarted (Text.pack ("Generating JavaScript to: " <> target))))
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
  Task.io (Log.logEvent (BuildStarted (Text.pack ("Generating HTML to: " <> target))))
  mainName <- hasExactlyOneMain artifacts
  builder <- createBuilder ctx artifacts
  -- Apply JavaScript spacing fixes to embedded JS before HTML wrapping
  let fixedBuilder = fixEmbeddedJavaScript builder
  let htmlBuilder = Html.sandwich mainName fixedBuilder
  writeOutputFile (ctx ^. bcStyle) target htmlBuilder (NonEmptyList.List mainName [])

-- | Generate null output (no files created).
--
-- Used for testing and benchmarking builds without creating output files.
-- Simply logs the action and returns without generating anything.
generateDevNull :: Task ()
generateDevNull =
  Task.io (Log.logEvent (BuildStarted (Text.pack "Output target is /dev/null - generating nothing")))

-- | Generate no output for library builds.
--
-- Used when no main functions are found, indicating a library build
-- that doesn't produce executable output.
generateNoOutput :: Task ()
generateNoOutput =
  Task.io (Log.logEvent (BuildStarted (Text.pack "No main functions found - generating nothing")))

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
  Task.io (Log.logEvent (BuildStarted (Text.pack ("Found single main function - generating HTML: " <> Name.toChars mainName))))
  builder <- createBuilder ctx artifacts
  -- Apply JavaScript spacing fixes to embedded JS before HTML wrapping
  let fixedBuilder = fixEmbeddedJavaScript builder
  let htmlBuilder = Html.sandwich mainName fixedBuilder
      target = "index.html"
  writeOutputFile (ctx ^. bcStyle) target htmlBuilder (NonEmptyList.List mainName [])

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
      Task.io (Log.logEvent (BuildStarted (Text.pack ("Found multiple main functions - generating JS: " <> show nameStrs))))
      builder <- createBuilder ctx artifacts
      let target = "canopy.js"
      writeOutputFile (ctx ^. bcStyle) target builder (NonEmptyList.List name rest)


-- | Select output format automatically based on artifacts.
--
-- Alias for 'chooseFormatFromMains' to maintain consistent naming
-- across the module interface.
selectOutputFormat :: BuildContext -> Build.Artifacts -> Task ()
selectOutputFormat = chooseFormatFromMains

-- | Fix JavaScript spacing issues in embedded JavaScript.
--
-- Applies the same spacing fixes used for standalone JavaScript files
-- to JavaScript code that will be embedded in HTML files.
fixEmbeddedJavaScript :: Builder -> Builder
fixEmbeddedJavaScript builder =
  let content = builderToText builder
      fixedContent = fixJavaScriptSpacing content
  in Builder.stringUtf8 (Text.unpack fixedContent)

-- | Convert Builder to Text for post-processing.
--
-- Efficiently converts a Builder to Text using the underlying ByteString.
builderToText :: Builder -> Text.Text
builderToText = Text.decodeUtf8 . ByteString.toStrict . Builder.toLazyByteString

-- | Fix JavaScript spacing issues.
--
-- Applies regex-based fixes for spacing problems in generated JavaScript.
-- These issues typically arise from optimization passes that concat strings
-- without preserving proper keyword spacing.
fixJavaScriptSpacing :: Text.Text -> Text.Text
fixJavaScriptSpacing content =
  content
    & Text.replace "elseif" "else if"
    & Text.replace "elsereturn" "else return"
    & Text.replace "elsethrow" "else throw"
    & Text.replace "elsevar" "else var"
    & Text.replace "elsefor" "else for"
    & Text.replace "elsewhile" "else while"

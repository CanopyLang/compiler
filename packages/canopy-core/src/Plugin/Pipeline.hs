{-# LANGUAGE OverloadedStrings #-}

-- | Plugin execution pipeline.
--
-- Provides the machinery for running registered plugins at specific
-- compiler phases.  Plugins are executed in registration order, and
-- any failure short-circuits the pipeline with a 'PluginError'.
--
-- The pipeline maintains phase separation: only plugins registered
-- for a given phase are executed when that phase runs.  This ensures
-- that source-level plugins never see optimized AST, and vice versa.
--
-- == Execution Model
--
-- Plugins are composed via left-to-right fold ('foldM'):
--
-- @
-- input  --(plugin1)--> intermediate1 --(plugin2)--> intermediate2 --> ... --> output
-- @
--
-- If any plugin returns 'Left', the pipeline halts immediately and
-- propagates the error.
--
-- == Lint Plugins
--
-- Lint plugins do not transform the AST.  Instead, they receive an
-- immutable view and produce a list of 'PluginWarning' values.  All
-- lint plugins run to completion (they do not short-circuit on
-- warnings), and their warnings are accumulated.
--
-- @since 0.19.2
module Plugin.Pipeline
  ( -- * Pipeline Execution
    runPlugins,
    runLintPlugins,

    -- * Plugin Filtering
    pluginsForPhase,

    -- * Pipeline Results
    PipelineResult (..),
  )
where

import Plugin.Interface
  ( Plugin (..),
    PluginError (..),
    PluginMeta (..),
    PluginPhase (..),
    PluginTransform (..),
    PluginWarning,
  )
import qualified Data.List as List
import qualified Data.Text as Text

-- | Result of running a plugin pipeline.
--
-- Captures the transformed value alongside any warnings produced
-- by lint plugins.
--
-- @since 0.19.2
data PipelineResult a = PipelineResult
  { _pipelineValue :: !a,
    _pipelineWarnings :: ![PluginWarning]
  }
  deriving (Eq, Show)

-- | Run all plugins registered for a specific phase.
--
-- Filters the plugin list to the given phase, then applies each
-- matching plugin's transformation in order.  Returns 'Left' on
-- the first plugin failure, or 'Right' with the final transformed
-- value.
--
-- Lint-phase plugins are skipped by this function; use
-- 'runLintPlugins' for those.
--
-- @since 0.19.2
runPlugins :: PluginPhase -> [Plugin] -> () -> Either PluginError ()
runPlugins phase plugins input =
  List.foldl' applyTransform (Right input) phasePlugins
  where
    phasePlugins = pluginsForPhase phase plugins

    applyTransform (Left err) _ = Left err
    applyTransform (Right val) plugin =
      applyPluginTransform plugin val

-- | Run all lint plugins and accumulate their warnings.
--
-- Unlike 'runPlugins', lint plugins do not short-circuit on
-- warnings.  All lint plugins are run against the (immutable)
-- input, and their warning lists are concatenated.
--
-- A lint plugin that returns 'Left' is treated as a plugin
-- error (not a lint warning) and halts the lint pipeline.
--
-- @since 0.19.2
runLintPlugins :: [Plugin] -> () -> Either PluginError [PluginWarning]
runLintPlugins plugins input =
  List.foldl' accumulateWarnings (Right []) lintPlugins
  where
    lintPlugins = pluginsForPhase CustomLint plugins

    accumulateWarnings (Left err) _ = Left err
    accumulateWarnings (Right acc) plugin =
      addWarnings acc plugin

    addWarnings acc plugin =
      either Left (Right . (acc ++)) (applyLintPlugin plugin input)

-- | Filter plugins to those registered for a specific phase.
--
-- @since 0.19.2
pluginsForPhase :: PluginPhase -> [Plugin] -> [Plugin]
pluginsForPhase phase =
  List.filter (\p -> _pluginPhase p == phase)

-- | Apply a single plugin's transformation to a value.
--
-- Returns 'Left' with an enriched error if the plugin fails,
-- annotating the error with the plugin name for diagnostics.
applyPluginTransform :: Plugin -> () -> Either PluginError ()
applyPluginTransform plugin val =
  annotateError (_pluginMeta plugin) (extractTransform (_pluginTransform plugin) val)

-- | Extract and apply the transformation function from a 'PluginTransform'.
extractTransform :: PluginTransform -> () -> Either PluginError ()
extractTransform (SourceTransform f) val = f val
extractTransform (CanonicalTransform f) val = f val
extractTransform (OptimizedTransform f) val = f val
extractTransform (LintAnalysis _) val = Right val

-- | Apply a lint plugin to produce warnings.
applyLintPlugin :: Plugin -> () -> Either PluginError [PluginWarning]
applyLintPlugin plugin input =
  extractLintAction (_pluginTransform plugin) input

-- | Extract and apply the lint action from a 'PluginTransform'.
--
-- Non-lint transforms produce no warnings.
extractLintAction :: PluginTransform -> () -> Either PluginError [PluginWarning]
extractLintAction (LintAnalysis f) val = f val
extractLintAction _ _ = Right []

-- | Annotate a plugin error with the originating plugin's name.
--
-- If the error already has a plugin name set, it is preserved.
-- Otherwise, the plugin's name from metadata is used.
annotateError :: PluginMeta -> Either PluginError a -> Either PluginError a
annotateError meta (Left err)
  | Text.null (_errorPlugin err) =
      Left (err {_errorPlugin = _pluginName meta})
  | otherwise = Left err
annotateError _ result = result

{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Plugin.Pipeline and Plugin.Interface modules.
--
-- Tests plugin execution, phase filtering, error propagation,
-- lint warning accumulation, and error annotation.
--
-- @since 0.19.2
module Unit.Plugin.PipelineTest (tests) where

import qualified Data.Text as Text
import qualified Plugin.Interface as PI
import qualified Plugin.Pipeline as Pipeline
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Plugin.Pipeline Tests"
    [ testPhaseFiltering,
      testPluginExecution,
      testLintPlugins,
      testErrorPropagation,
      testAnnotation
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Tests: Phase filtering
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testPhaseFiltering :: TestTree
testPhaseFiltering =
  testGroup
    "Phase filtering"
    [ testCase "filters plugins by phase" $
        length (Pipeline.pluginsForPhase PI.AfterParse mixedPlugins) @?= 2,
      testCase "returns empty list when no plugins match" $
        length (Pipeline.pluginsForPhase PI.AfterParse canonOnlyPlugins) @?= 0,
      testCase "empty plugin list returns empty" $
        length (Pipeline.pluginsForPhase PI.AfterParse []) @?= 0,
      testCase "lint phase filtering works" $
        length (Pipeline.pluginsForPhase PI.CustomLint lintPluginList) @?= 2
    ]
  where
    mixedPlugins =
      [ mkParsePlugin "p1",
        mkCanonPlugin "c1",
        mkParsePlugin "p2",
        mkOptPlugin "o1"
      ]
    canonOnlyPlugins =
      [ mkCanonPlugin "c1",
        mkOptPlugin "o1"
      ]
    lintPluginList =
      [ mkLintPlugin "l1" "warn1",
        mkParsePlugin "p1",
        mkLintPlugin "l2" "warn2"
      ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Tests: Plugin execution
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testPluginExecution :: TestTree
testPluginExecution =
  testGroup
    "Plugin execution"
    [ testCase "no plugins returns input unchanged" $
        Pipeline.runPlugins PI.AfterParse [] () @?= Right (),
      testCase "identity plugin returns input unchanged" $
        Pipeline.runPlugins PI.AfterParse [mkParsePlugin "id"] () @?= Right (),
      testCase "multiple identity plugins return input unchanged" $
        Pipeline.runPlugins PI.AfterParse threeIdPlugins () @?= Right (),
      testCase "plugins for wrong phase are not executed" $
        Pipeline.runPlugins PI.AfterCanonicalize [mkFailingParsePlugin "x"] () @?= Right (),
      testCase "canonical transform identity works" $
        Pipeline.runPlugins PI.AfterCanonicalize [canonIdentity] () @?= Right (),
      testCase "optimized transform identity works" $
        Pipeline.runPlugins PI.AfterOptimize [optIdentity] () @?= Right ()
    ]
  where
    threeIdPlugins =
      [ mkParsePlugin "id1",
        mkParsePlugin "id2",
        mkParsePlugin "id3"
      ]
    canonIdentity =
      mkPlugin' "canon" PI.AfterCanonicalize (PI.CanonicalTransform Right)
    optIdentity =
      mkPlugin' "opt" PI.AfterOptimize (PI.OptimizedTransform Right)

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Tests: Lint plugins
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testLintPlugins :: TestTree
testLintPlugins =
  testGroup
    "Lint plugins"
    [ testCase "no lint plugins returns empty warnings" $
        Pipeline.runLintPlugins [] () @?= Right [],
      testCase "single lint plugin produces one warning" $
        assertWarningCount 1 (Pipeline.runLintPlugins [mkLintPlugin "l" "w"] ()),
      testCase "multiple lint plugins accumulate warnings" $
        assertWarningCount 3 (Pipeline.runLintPlugins threeLintPlugins ()),
      testCase "non-lint plugins produce no lint warnings" $
        Pipeline.runLintPlugins [mkParsePlugin "parser"] () @?= Right [],
      testCase "lint plugin error halts pipeline" $
        assertIsLeft (Pipeline.runLintPlugins lintWithFailure ()),
      testCase "warning message is preserved" $
        assertFirstWarningMessage "specific warning" singleLintResult
    ]
  where
    threeLintPlugins =
      [ mkLintPlugin "l1" "a",
        mkLintPlugin "l2" "b",
        mkLintPlugin "l3" "c"
      ]
    lintWithFailure =
      [ mkLintPlugin "ok" "fine",
        mkFailingLintPlugin "broken",
        mkLintPlugin "skip" "never"
      ]
    singleLintResult =
      Pipeline.runLintPlugins [mkLintPlugin "l" "specific warning"] ()

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Tests: Error propagation
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testErrorPropagation :: TestTree
testErrorPropagation =
  testGroup
    "Error propagation"
    [ testCase "failing plugin returns Left" $
        assertIsLeft (Pipeline.runPlugins PI.AfterParse [mkFailingParsePlugin "bad"] ()),
      testCase "failure halts pipeline before later plugins" $
        assertIsLeft (Pipeline.runPlugins PI.AfterParse failThenPass ()),
      testCase "error message is preserved" $
        assertErrorMessage "deliberate failure" failResult,
      testCase "error details are preserved" $
        assertErrorNoDetails failResult
    ]
  where
    failThenPass =
      [ mkFailingParsePlugin "fails",
        mkParsePlugin "never-reached"
      ]
    failResult =
      Pipeline.runPlugins PI.AfterParse [mkFailingParsePlugin "bad"] ()

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Tests: Error annotation
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testAnnotation :: TestTree
testAnnotation =
  testGroup
    "Error annotation"
    [ testCase "error with empty plugin name is annotated from metadata" $
        assertErrorPluginName "annotator" annotatedResult,
      testCase "error with existing plugin name is preserved" $
        assertErrorPluginName "failing-plugin" preservedResult
    ]
  where
    annotatedResult =
      Pipeline.runPlugins PI.AfterParse [emptyNamePlugin] ()
    preservedResult =
      Pipeline.runPlugins PI.AfterParse [mkFailingParsePlugin "ignored"] ()
    emptyNamePlugin =
      mkPlugin' "annotator" PI.AfterParse emptyNameTransform
    emptyNameTransform =
      PI.SourceTransform (\_ -> Left emptyNameError)
    emptyNameError =
      PI.PluginError
        { PI._errorPlugin = "",
          PI._errorMessage = "needs annotation",
          PI._errorDetails = Nothing
        }

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Plugin factories
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- | Build a parse-phase identity plugin.
mkParsePlugin :: Text.Text -> PI.Plugin
mkParsePlugin name =
  mkPlugin' name PI.AfterParse (PI.SourceTransform Right)

-- | Build a canonicalize-phase identity plugin.
mkCanonPlugin :: Text.Text -> PI.Plugin
mkCanonPlugin name =
  mkPlugin' name PI.AfterCanonicalize (PI.CanonicalTransform Right)

-- | Build an optimize-phase identity plugin.
mkOptPlugin :: Text.Text -> PI.Plugin
mkOptPlugin name =
  mkPlugin' name PI.AfterOptimize (PI.OptimizedTransform Right)

-- | Build a parse-phase plugin that always fails.
mkFailingParsePlugin :: Text.Text -> PI.Plugin
mkFailingParsePlugin name =
  mkPlugin' name PI.AfterParse failingTransform
  where
    failingTransform =
      PI.SourceTransform (\_ -> Left failError)

-- | Build a lint plugin that produces a single warning.
mkLintPlugin :: Text.Text -> Text.Text -> PI.Plugin
mkLintPlugin name msg =
  mkPlugin' name PI.CustomLint (lintWarningTransform msg)

-- | Build a lint plugin that always fails.
mkFailingLintPlugin :: Text.Text -> PI.Plugin
mkFailingLintPlugin name =
  mkPlugin' name PI.CustomLint failingLintTransform
  where
    failingLintTransform =
      PI.LintAnalysis (\_ -> Left failError)

-- | Build a plugin with the given name, phase, and transform.
mkPlugin' :: Text.Text -> PI.PluginPhase -> PI.PluginTransform -> PI.Plugin
mkPlugin' name phase transform =
  PI.Plugin
    { PI._pluginMeta =
        PI.PluginMeta
          { PI._pluginName = name,
            PI._pluginVersion = "1.0.0",
            PI._pluginDescription = "test plugin"
          },
      PI._pluginPhase = phase,
      PI._pluginTransform = transform
    }

-- | A known error value for testing failure paths.
failError :: PI.PluginError
failError =
  PI.PluginError
    { PI._errorPlugin = "failing-plugin",
      PI._errorMessage = "deliberate failure",
      PI._errorDetails = Nothing
    }

-- | A lint transform that produces one warning with the given message.
lintWarningTransform :: Text.Text -> PI.PluginTransform
lintWarningTransform msg =
  PI.LintAnalysis
    ( \_ ->
        Right
          [ PI.PluginWarning
              { PI._warningPlugin = "lint",
                PI._warningMessage = msg,
                PI._warningLocation = Nothing
              }
          ]
    )

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Assertion helpers
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- | Assert that a result is 'Left'.
assertIsLeft :: Either PI.PluginError a -> Assertion
assertIsLeft (Left _) = pure ()
assertIsLeft (Right _) = assertFailure "Expected Left, got Right"

-- | Assert the expected warning count.
assertWarningCount :: Int -> Either PI.PluginError [PI.PluginWarning] -> Assertion
assertWarningCount expected (Right ws) = length ws @?= expected
assertWarningCount _ (Left err) =
  assertFailure ("Expected warnings, got error: " ++ show err)

-- | Assert the first warning has the expected message.
assertFirstWarningMessage :: Text.Text -> Either PI.PluginError [PI.PluginWarning] -> Assertion
assertFirstWarningMessage expected (Right (w : _)) =
  PI._warningMessage w @?= expected
assertFirstWarningMessage _ (Right []) =
  assertFailure "Expected at least one warning, got empty list"
assertFirstWarningMessage _ (Left err) =
  assertFailure ("Expected warnings, got error: " ++ show err)

-- | Assert that a plugin error has the expected message.
assertErrorMessage :: Text.Text -> Either PI.PluginError a -> Assertion
assertErrorMessage expected (Left err) =
  PI._errorMessage err @?= expected
assertErrorMessage _ (Right _) =
  assertFailure "Expected Left with error message, got Right"

-- | Assert that a plugin error has no details.
assertErrorNoDetails :: Either PI.PluginError a -> Assertion
assertErrorNoDetails (Left err) =
  PI._errorDetails err @?= Nothing
assertErrorNoDetails (Right _) =
  assertFailure "Expected Left with error, got Right"

-- | Assert that a plugin error has the expected plugin name.
assertErrorPluginName :: Text.Text -> Either PI.PluginError a -> Assertion
assertErrorPluginName expected (Left err) =
  PI._errorPlugin err @?= expected
assertErrorPluginName _ (Right _) =
  assertFailure "Expected Left with plugin name, got Right"

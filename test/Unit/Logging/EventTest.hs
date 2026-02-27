{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the structured logging event system.
--
-- Verifies event level/phase mappings, rendering, and duration formatting.
--
-- @since 0.19.1
module Unit.Logging.EventTest (tests) where

import Logging.Event
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Logging.Event Tests"
    [ levelTests,
      phaseTests,
      durationTests,
      renderTests
    ]

levelTests :: TestTree
levelTests =
  testGroup
    "event level mapping"
    [ testCase "ParseStarted is DEBUG" $
        eventLevel (ParseStarted "/tmp/test.can" 100) @?= DEBUG,
      testCase "ParseFailed is ERROR" $
        eventLevel (ParseFailed "/tmp/test.can" "syntax error") @?= ERROR,
      testCase "CompileStarted is INFO" $
        eventLevel (CompileStarted "/tmp/test.can") @?= INFO,
      testCase "BuildStarted is INFO" $
        eventLevel (BuildStarted "test") @?= INFO,
      testCase "BuildFailed is ERROR" $
        eventLevel (BuildFailed "something broke") @?= ERROR,
      testCase "TypeConstraintSolved is TRACE" $
        eventLevel (TypeConstraintSolved "Mod" CKEqual) @?= TRACE,
      testCase "TypeUnified is TRACE" $
        eventLevel (TypeUnified "Mod" "Int" "Int") @?= TRACE,
      testCase "TypeUnifyFailed is TRACE" $
        eventLevel (TypeUnifyFailed "Mod" "Int" "String") @?= TRACE,
      testCase "CanonVarResolved is TRACE" $
        eventLevel (CanonVarResolved "Mod" "x" ResLocal) @?= TRACE,
      testCase "CacheHit is DEBUG" $
        eventLevel (CacheHit PhaseBuild "key") @?= DEBUG,
      testCase "FFIMissing is WARN" $
        eventLevel (FFIMissing "/tmp/missing.js") @?= WARN,
      testCase "WorkerFailed is ERROR" $
        eventLevel (WorkerFailed 1 "crash") @?= ERROR,
      testCase "level ordering: TRACE < DEBUG" $
        assertBool "TRACE < DEBUG" (TRACE < DEBUG),
      testCase "level ordering: DEBUG < INFO" $
        assertBool "DEBUG < INFO" (DEBUG < INFO),
      testCase "level ordering: INFO < WARN" $
        assertBool "INFO < WARN" (INFO < WARN),
      testCase "level ordering: WARN < ERROR" $
        assertBool "WARN < ERROR" (WARN < ERROR)
    ]

phaseTests :: TestTree
phaseTests =
  testGroup
    "event phase mapping"
    [ testCase "ParseStarted is PhaseParse" $
        eventPhase (ParseStarted "/tmp/test.can" 100) @?= PhaseParse,
      testCase "CanonStarted is PhaseCanon" $
        eventPhase (CanonStarted "Main") @?= PhaseCanon,
      testCase "TypeSolveStarted is PhaseType" $
        eventPhase (TypeSolveStarted "Main" 42) @?= PhaseType,
      testCase "OptimizeStarted is PhaseOptimize" $
        eventPhase (OptimizeStarted "Main") @?= PhaseOptimize,
      testCase "GenerateStarted is PhaseGenerate" $
        eventPhase (GenerateStarted "Main") @?= PhaseGenerate,
      testCase "BuildStarted is PhaseBuild" $
        eventPhase (BuildStarted "test") @?= PhaseBuild,
      testCase "CacheHit is PhaseCache" $
        eventPhase (CacheHit PhaseBuild "key") @?= PhaseCache,
      testCase "FFILoading is PhaseFFI" $
        eventPhase (FFILoading "/tmp/test.js") @?= PhaseFFI,
      testCase "WorkerSpawned is PhaseWorker" $
        eventPhase (WorkerSpawned 1) @?= PhaseWorker,
      testCase "KernelStarted is PhaseKernel" $
        eventPhase (KernelStarted "/tmp/kernel.js") @?= PhaseKernel,
      testCase "PackageOperation is PhasePackage" $
        eventPhase (PackageOperation "create" "test") @?= PhasePackage
    ]

durationTests :: TestTree
durationTests =
  testGroup
    "duration formatting"
    [ testCase "microseconds" $
        formatDuration (Duration 500) @?= "500us",
      testCase "milliseconds" $
        formatDuration (Duration 5000) @?= "5ms",
      testCase "seconds" $
        formatDuration (Duration 2500000) @?= "2s",
      testCase "durationMicros extracts value" $
        durationMicros (Duration 42) @?= 42,
      testCase "durationMillis converts" $
        durationMillis (Duration 1500) @?= 1.5
    ]

renderTests :: TestTree
renderTests =
  testGroup
    "CLI rendering"
    [ testCase "ParseStarted rendering" $
        renderCLI (ParseStarted "/tmp/test.can" 100)
          @?= "Parsing /tmp/test.can (100 bytes)",
      testCase "ParseCompleted rendering" $
        renderCLI (ParseCompleted "/tmp/test.can" (ParseStats 5 3 False))
          @?= "Parsed /tmp/test.can (5 decls, 3 imports)",
      testCase "BuildStarted rendering" $
        renderCLI (BuildStarted "test-build") @?= "Build started: test-build",
      testCase "CacheHit rendering" $
        renderCLI (CacheHit PhaseBuild "my-key") @?= "Cache hit: BUILD my-key",
      testCase "renderPhase PhaseParse" $
        renderPhase PhaseParse @?= "PARSE",
      testCase "renderPhase PhaseType" $
        renderPhase PhaseType @?= "TYPE",
      testCase "renderPhase PhaseBuild" $
        renderPhase PhaseBuild @?= "BUILD",
      testCase "renderLevel TRACE" $
        renderLevel TRACE @?= "TRACE",
      testCase "renderLevel DEBUG" $
        renderLevel DEBUG @?= "DEBUG",
      testCase "renderLevel INFO padded" $
        renderLevel INFO @?= "INFO ",
      testCase "renderLevel ERROR" $
        renderLevel ERROR @?= "ERROR",
      testCase "TypeUnified rendering" $
        renderCLI (TypeUnified "Main" "Int" "String")
          @?= "Unified Int ~ String in Main",
      testCase "WorkerFailed rendering" $
        renderCLI (WorkerFailed 42 "timeout")
          @?= "Worker failed: 42 \8212 timeout",
      testCase "CompileCompleted rendering" $
        renderCLI (CompileCompleted "/tmp/proj" (CompileStats 10 (Duration 5000)))
          @?= "Compiled /tmp/proj (10 modules, 5ms)"
    ]

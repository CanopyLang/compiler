{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Tests for logging configuration parsing and event filtering.
--
-- Verifies that 'shouldEmit' correctly gates events based on level and phase.
--
-- @since 0.19.1
module Unit.Logging.ConfigTest (tests) where

import Logging.Config
import Logging.Event
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Logging.Config Tests"
    [ shouldEmitTests,
      configStructureTests
    ]

shouldEmitTests :: TestTree
shouldEmitTests =
  testGroup
    "shouldEmit filtering"
    [ testCase "disabled config blocks all events" $ do
        let cfg = LogConfig False INFO [] FormatCLI Nothing
        assertBool "should not emit" (not (shouldEmit cfg (BuildStarted "test"))),
      testCase "enabled config passes events at or above level" $ do
        let cfg = LogConfig True DEBUG [] FormatCLI Nothing
        assertBool "DEBUG event passes at DEBUG level" (shouldEmit cfg (BuildStarted "test")),
      testCase "enabled config blocks events below level" $ do
        let cfg = LogConfig True INFO [] FormatCLI Nothing
        assertBool "DEBUG event blocked at INFO level" (not (shouldEmit cfg (ParseStarted "/tmp" 0))),
      testCase "INFO level passes INFO events" $ do
        let cfg = LogConfig True INFO [] FormatCLI Nothing
        assertBool "INFO passes" (shouldEmit cfg (CompileStarted "/tmp")),
      testCase "ERROR events always pass when enabled" $ do
        let cfg = LogConfig True INFO [] FormatCLI Nothing
        assertBool "ERROR passes at INFO" (shouldEmit cfg (BuildFailed "err")),
      testCase "phase filter allows matching phase" $ do
        let cfg = LogConfig True DEBUG [PhaseParse] FormatCLI Nothing
        assertBool "parse event passes" (shouldEmit cfg (ParseStarted "/tmp" 0)),
      testCase "phase filter blocks non-matching phase" $ do
        let cfg = LogConfig True DEBUG [PhaseParse] FormatCLI Nothing
        assertBool "build event blocked" (not (shouldEmit cfg (BuildStarted "test"))),
      testCase "empty phase filter allows all phases" $ do
        let cfg = LogConfig True DEBUG [] FormatCLI Nothing
        assertBool "build passes" (shouldEmit cfg (BuildStarted "test"))
        assertBool "parse passes" (shouldEmit cfg (ParseStarted "/tmp" 0))
        assertBool "type passes" (shouldEmit cfg (TypeSolveStarted "Mod" 0)),
      testCase "TRACE events only pass at TRACE level" $ do
        let cfgTrace = LogConfig True TRACE [] FormatCLI Nothing
        let cfgDebug = LogConfig True DEBUG [] FormatCLI Nothing
        assertBool "passes at TRACE" (shouldEmit cfgTrace (TypeConstraintSolved "Mod" CKEqual))
        assertBool "blocked at DEBUG" (not (shouldEmit cfgDebug (TypeConstraintSolved "Mod" CKEqual))),
      testCase "multiple phases filter correctly" $ do
        let cfg = LogConfig True DEBUG [PhaseParse, PhaseType] FormatCLI Nothing
        assertBool "parse passes" (shouldEmit cfg (ParseStarted "/tmp" 0))
        assertBool "type passes" (shouldEmit cfg (TypeSolveStarted "Mod" 0))
        assertBool "build blocked" (not (shouldEmit cfg (BuildStarted "test")))
    ]

configStructureTests :: TestTree
configStructureTests =
  testGroup
    "config structure"
    [ testCase "FormatCLI show" $
        show FormatCLI @?= "FormatCLI",
      testCase "FormatJSON show" $
        show FormatJSON @?= "FormatJSON",
      testCase "disabled config fields" $ do
        let cfg = LogConfig False INFO [] FormatCLI Nothing
        _configEnabled cfg @?= False
        _configLevel cfg @?= INFO
        _configPhases cfg @?= []
        _configFormat cfg @?= FormatCLI
        _configFile cfg @?= Nothing,
      testCase "full config fields" $ do
        let cfg = LogConfig True TRACE [PhaseParse, PhaseType] FormatJSON (Just "/tmp/log")
        _configEnabled cfg @?= True
        _configLevel cfg @?= TRACE
        _configPhases cfg @?= [PhaseParse, PhaseType]
        _configFormat cfg @?= FormatJSON
        _configFile cfg @?= Just "/tmp/log"
    ]

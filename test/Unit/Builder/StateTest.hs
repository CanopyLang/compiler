
-- | Unit tests for Builder.State module.
--
-- Tests pure state management with IORef including status tracking,
-- result tracking, and statistics.
--
-- @since 0.19.1
module Unit.Builder.StateTest (tests) where

import qualified Builder.State as State
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Builder.State Tests"
    [ testInitBuilder,
      testModuleStatus,
      testModuleResult,
      testStatistics,
      testConcurrentModules,
      testStatusTransitions,
      testResultOverwrite
    ]

-- Helper to create test module names
mkName :: String -> Name.Name
mkName = Name.fromChars

testInitBuilder :: TestTree
testInitBuilder =
  testGroup
    "builder initialization tests"
    [ testCase "init builder creates engine" $ do
        engine <- State.initBuilder
        statuses <- State.getAllStatuses engine
        Map.size statuses @?= 0,
      testCase "init builder has zero completed count" $ do
        engine <- State.initBuilder
        count <- State.getCompletedCount engine
        count @?= 0,
      testCase "init builder has zero pending count" $ do
        engine <- State.initBuilder
        count <- State.getPendingCount engine
        count @?= 0,
      testCase "init builder has zero failed count" $ do
        engine <- State.initBuilder
        count <- State.getFailedCount engine
        count @?= 0
    ]

testModuleStatus :: TestTree
testModuleStatus =
  testGroup
    "module status tests"
    [ testCase "get status for unknown module" $ do
        engine <- State.initBuilder
        status <- State.getModuleStatus engine (mkName "Unknown")
        status @?= Nothing,
      testCase "set and get pending status" $ do
        engine <- State.initBuilder
        State.setModuleStatus engine (mkName "Main") State.StatusPending
        status <- State.getModuleStatus engine (mkName "Main")
        status @?= Just State.StatusPending,
      testCase "set and get in progress status" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleStatus engine (mkName "Main") (State.StatusInProgress time)
            status <- State.getModuleStatus engine (mkName "Main")
            case status of
              Just (State.StatusInProgress t) -> t @?= time
              _ -> assertFailure "Expected StatusInProgress",
      testCase "set and get completed status" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleStatus engine (mkName "Main") (State.StatusCompleted time)
            status <- State.getModuleStatus engine (mkName "Main")
            case status of
              Just (State.StatusCompleted t) -> t @?= time
              _ -> assertFailure "Expected StatusCompleted",
      testCase "set and get failed status" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleStatus engine (mkName "Main") (State.StatusFailed "error" time)
            status <- State.getModuleStatus engine (mkName "Main")
            case status of
              Just (State.StatusFailed msg t) -> do
                msg @?= "error"
                t @?= time
              _ -> assertFailure "Expected StatusFailed",
      testCase "update existing status" $ do
        engine <- State.initBuilder
        State.setModuleStatus engine (mkName "Main") State.StatusPending
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleStatus engine (mkName "Main") (State.StatusCompleted time)
            status <- State.getModuleStatus engine (mkName "Main")
            case status of
              Just (State.StatusCompleted _) -> return ()
              _ -> assertFailure "Expected StatusCompleted",
      testCase "getAllStatuses returns all modules" $ do
        engine <- State.initBuilder
        State.setModuleStatus engine (mkName "Main") State.StatusPending
        State.setModuleStatus engine (mkName "Utils") State.StatusPending
        statuses <- State.getAllStatuses engine
        Map.size statuses @?= 2
    ]

testModuleResult :: TestTree
testModuleResult =
  testGroup
    "module result tests"
    [ testCase "get result for unknown module" $ do
        engine <- State.initBuilder
        result <- State.getModuleResult engine (mkName "Unknown")
        result @?= Nothing,
      testCase "set and get pending result" $ do
        engine <- State.initBuilder
        State.setModuleResult engine (mkName "Main") State.ResultPending
        result <- State.getModuleResult engine (mkName "Main")
        result @?= Just State.ResultPending,
      testCase "set and get success result" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleResult engine (mkName "Main") (State.ResultSuccess "path" time)
            result <- State.getModuleResult engine (mkName "Main")
            case result of
              Just (State.ResultSuccess path t) -> do
                path @?= "path"
                t @?= time
              _ -> assertFailure "Expected ResultSuccess",
      testCase "set and get failure result" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleResult engine (mkName "Main") (State.ResultFailure "error" time)
            result <- State.getModuleResult engine (mkName "Main")
            case result of
              Just (State.ResultFailure msg t) -> do
                msg @?= "error"
                t @?= time
              _ -> assertFailure "Expected ResultFailure",
      testCase "getAllResults returns all modules" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleResult engine (mkName "Main") (State.ResultSuccess "path1" time)
            State.setModuleResult engine (mkName "Utils") (State.ResultSuccess "path2" time)
            results <- State.getAllResults engine
            Map.size results @?= 2
    ]

testStatistics :: TestTree
testStatistics =
  testGroup
    "statistics tests"
    [ testCase "completed count starts at zero" $ do
        engine <- State.initBuilder
        count <- State.getCompletedCount engine
        count @?= 0,
      testCase "completed count increments on success" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleResult engine (mkName "Main") (State.ResultSuccess "path" time)
            count <- State.getCompletedCount engine
            count @?= 1,
      testCase "completed count increments on failure" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleResult engine (mkName "Main") (State.ResultFailure "error" time)
            count <- State.getCompletedCount engine
            count @?= 1,
      testCase "completed count tracks multiple modules" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleResult engine (mkName "Main") (State.ResultSuccess "path1" time)
            State.setModuleResult engine (mkName "Utils") (State.ResultSuccess "path2" time)
            count <- State.getCompletedCount engine
            count @?= 2,
      testCase "pending count starts at zero" $ do
        engine <- State.initBuilder
        count <- State.getPendingCount engine
        count @?= 0,
      testCase "pending count increments on pending status" $ do
        engine <- State.initBuilder
        State.setModuleStatus engine (mkName "Main") State.StatusPending
        count <- State.getPendingCount engine
        count @?= 1,
      testCase "pending count decrements on completion" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleStatus engine (mkName "Main") State.StatusPending
            State.setModuleStatus engine (mkName "Main") (State.StatusCompleted time)
            count <- State.getPendingCount engine
            count @?= 0,
      testCase "failed count starts at zero" $ do
        engine <- State.initBuilder
        count <- State.getFailedCount engine
        count @?= 0,
      testCase "failed count increments on failure" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleResult engine (mkName "Main") (State.ResultFailure "error" time)
            count <- State.getFailedCount engine
            count @?= 1,
      testCase "failed count tracks multiple failures" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        case state of
          State.BuilderState {State.builderStartTime = time} -> do
            State.setModuleResult engine (mkName "Main") (State.ResultFailure "err1" time)
            State.setModuleResult engine (mkName "Utils") (State.ResultFailure "err2" time)
            count <- State.getFailedCount engine
            count @?= 2
    ]

-- Helper function to create empty test state
emptyTestState :: IO State.BuilderState
emptyTestState = State.emptyState

testConcurrentModules :: TestTree
testConcurrentModules =
  testGroup
    "many modules tracking"
    [ testCase "ten modules tracked independently" $ do
        engine <- State.initBuilder
        mapM_ (\i -> State.setModuleStatus engine (mkName ("M" ++ show (i :: Int))) State.StatusPending) [1 .. 10]
        count <- State.getPendingCount engine
        count @?= 10,
      testCase "completing some leaves others pending" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        let time = State.builderStartTime state
        mapM_ (\i -> State.setModuleStatus engine (mkName ("M" ++ show (i :: Int))) State.StatusPending) [1 .. 5]
        mapM_ (\i -> State.setModuleStatus engine (mkName ("M" ++ show (i :: Int))) (State.StatusCompleted time)) [1 .. 3]
        pending <- State.getPendingCount engine
        pending @?= 2,
      testCase "getAllStatuses returns all set modules" $ do
        engine <- State.initBuilder
        mapM_ (\i -> State.setModuleStatus engine (mkName ("X" ++ show (i :: Int))) State.StatusPending) [1 .. 7]
        statuses <- State.getAllStatuses engine
        Map.size statuses @?= 7
    ]

testStatusTransitions :: TestTree
testStatusTransitions =
  testGroup
    "status transition sequences"
    [ testCase "Pending -> InProgress -> Completed" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        let time = State.builderStartTime state
        State.setModuleStatus engine (mkName "M") State.StatusPending
        State.setModuleStatus engine (mkName "M") (State.StatusInProgress time)
        State.setModuleStatus engine (mkName "M") (State.StatusCompleted time)
        status <- State.getModuleStatus engine (mkName "M")
        case status of
          Just (State.StatusCompleted _) -> return ()
          _ -> assertFailure "Expected StatusCompleted",
      testCase "Pending -> Failed" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        let time = State.builderStartTime state
        State.setModuleStatus engine (mkName "M") State.StatusPending
        State.setModuleStatus engine (mkName "M") (State.StatusFailed "compile error" time)
        status <- State.getModuleStatus engine (mkName "M")
        case status of
          Just (State.StatusFailed msg _) -> msg @?= "compile error"
          _ -> assertFailure "Expected StatusFailed"
    ]

testResultOverwrite :: TestTree
testResultOverwrite =
  testGroup
    "result overwrite behaviour"
    [ testCase "result can be updated from Pending to Success" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        let time = State.builderStartTime state
        State.setModuleResult engine (mkName "M") State.ResultPending
        State.setModuleResult engine (mkName "M") (State.ResultSuccess "output.js" time)
        result <- State.getModuleResult engine (mkName "M")
        case result of
          Just (State.ResultSuccess path _) -> path @?= "output.js"
          _ -> assertFailure "Expected ResultSuccess",
      testCase "setting success twice increments completed count twice" $ do
        engine <- State.initBuilder
        state <- emptyTestState
        let time = State.builderStartTime state
        State.setModuleResult engine (mkName "M") (State.ResultSuccess "p1" time)
        count1 <- State.getCompletedCount engine
        State.setModuleResult engine (mkName "M") (State.ResultSuccess "p2" time)
        count2 <- State.getCompletedCount engine
        count1 @?= 1
        count2 @?= 2
    ]

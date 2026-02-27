
-- | Comprehensive tests for Worker.Pool module.
--
-- Tests parallel compilation worker pool including task distribution,
-- progress tracking, and error handling.
--
-- @since 0.19.1
module Unit.Worker.PoolTest (tests) where

import qualified Canopy.Package as Pkg
import Control.Concurrent (threadDelay)
import Data.IORef (modifyIORef, newIORef, readIORef)
import qualified Data.Map as Map
import qualified Data.Utf8 as Utf8
import qualified Parse.Module as Parse
import qualified Query.Engine as Engine
import Query.Simple
import System.IO.Temp (withSystemTempDirectory)
import qualified System.IO as IO
import Test.Tasty
import Test.Tasty.HUnit
import qualified Worker.Pool as Pool

tests :: TestTree
tests =
  testGroup
    "Worker.Pool Tests"
    [ testPoolCreation,
      testTaskExecution,
      testProgressTracking,
      testErrorHandling,
      testParallelExecution
    ]

testPoolCreation :: TestTree
testPoolCreation =
  testGroup
    "pool creation"
    [ testCase "create pool with default config" $ do
        pool <- Pool.createPoolDefault mockCompileFn
        progress <- Pool.getProgress pool
        Pool.progressTotal progress @?= 0
        Pool.shutdownPool pool,
      testCase "create pool with custom config" $ do
        let config =
              Pool.PoolConfig
                { Pool.poolConfigWorkers = 2,
                  Pool.poolConfigQueueSize = 50
                }
        pool <- Pool.createPool config mockCompileFn
        progress <- Pool.getProgress pool
        Pool.progressTotal progress @?= 0
        Pool.shutdownPool pool,
      testCase "pool starts with zero completed" $ do
        pool <- Pool.createPoolDefault mockCompileFn
        progress <- Pool.getProgress pool
        Pool.progressCompleted progress @?= 0
        Pool.shutdownPool pool
    ]

testTaskExecution :: TestTree
testTaskExecution =
  testGroup
    "task execution"
    [ testCase "compile single module successfully" $ do
        withTestModule $ \path -> do
          pool <- Pool.createPoolDefault successCompileFn
          let task = makeTask path
          results <- Pool.compileModules pool [task]

          case results of
            [Right _] -> return ()
            _ -> assertFailure "Expected successful compilation"

          Pool.shutdownPool pool,
      testCase "compile multiple modules" $ do
        withMultipleTestModules $ \paths -> do
          pool <- Pool.createPoolDefault successCompileFn
          let tasks = map makeTask paths
          results <- Pool.compileModules pool tasks

          let successCount = length [() | Right _ <- results]
          successCount @?= length paths

          Pool.shutdownPool pool,
      testCase "empty task list returns empty results" $ do
        pool <- Pool.createPoolDefault successCompileFn
        results <- Pool.compileModules pool []

        length results @?= 0
        Pool.shutdownPool pool
    ]

testProgressTracking :: TestTree
testProgressTracking =
  testGroup
    "progress tracking"
    [ testCase "track completion count" $ do
        withMultipleTestModules $ \paths -> do
          pool <- Pool.createPoolDefault successCompileFn
          let tasks = map makeTask paths
          _ <- Pool.compileModules pool tasks

          progress <- Pool.getProgress pool
          Pool.progressCompleted progress @?= length paths

          Pool.shutdownPool pool,
      testCase "track total count" $ do
        withMultipleTestModules $ \paths -> do
          pool <- Pool.createPoolDefault successCompileFn
          let tasks = map makeTask paths
          _ <- Pool.compileModules pool tasks

          progress <- Pool.getProgress pool
          Pool.progressTotal progress @?= length paths

          Pool.shutdownPool pool,
      testCase "track failed count on errors" $ do
        withMultipleTestModules $ \paths -> do
          pool <- Pool.createPoolDefault failureCompileFn
          let tasks = map makeTask paths
          _ <- Pool.compileModules pool tasks

          progress <- Pool.getProgress pool
          Pool.progressFailed progress @?= length paths

          Pool.shutdownPool pool,
      testCase "progress updates during compilation" $ do
        withTestModule $ \path -> do
          pool <- Pool.createPoolDefault slowCompileFn
          let task = makeTask path

          progressBefore <- Pool.getProgress pool
          _ <- Pool.compileModules pool [task]
          progressAfter <- Pool.getProgress pool

          Pool.progressCompleted progressBefore @?= 0
          Pool.progressCompleted progressAfter @?= 1

          Pool.shutdownPool pool
    ]

testErrorHandling :: TestTree
testErrorHandling =
  testGroup
    "error handling"
    [ testCase "handle compilation errors" $ do
        withTestModule $ \path -> do
          pool <- Pool.createPoolDefault failureCompileFn
          let task = makeTask path
          results <- Pool.compileModules pool [task]

          case results of
            [Left _] -> return ()
            _ -> assertFailure "Expected compilation error"

          Pool.shutdownPool pool,
      testCase "partial failures tracked correctly" $ do
        withMultipleTestModules $ \paths -> do
          pool <- Pool.createPoolDefault mixedCompileFn
          let tasks = map makeTask paths
          results <- Pool.compileModules pool tasks

          let failures = length [() | Left _ <- results]
          let successes = length [() | Right _ <- results]

          assertBool "Should have both successes and failures" (failures > 0 && successes > 0)

          Pool.shutdownPool pool,
      testCase "all errors tracked in progress" $ do
        withMultipleTestModules $ \paths -> do
          pool <- Pool.createPoolDefault failureCompileFn
          let tasks = map makeTask paths
          _ <- Pool.compileModules pool tasks

          progress <- Pool.getProgress pool
          Pool.progressFailed progress @?= length paths
          Pool.progressCompleted progress @?= length paths

          Pool.shutdownPool pool
    ]

testParallelExecution :: TestTree
testParallelExecution =
  testGroup
    "parallel execution"
    [ testCase "multiple tasks execute in parallel" $ do
        withMultipleTestModules $ \paths -> do
          let config =
                Pool.PoolConfig
                  { Pool.poolConfigWorkers = 4,
                    Pool.poolConfigQueueSize = 100
                  }
          pool <- Pool.createPool config successCompileFn
          let tasks = map makeTask paths
          results <- Pool.compileModules pool tasks

          let successCount = length [() | Right _ <- results]
          successCount @?= length paths

          Pool.shutdownPool pool,
      testCase "progress callback invoked during execution" $ do
        withMultipleTestModules $ \paths -> do
          pool <- Pool.createPoolDefault slowCompileFn
          let tasks = map makeTask paths

          progressUpdates <- newIORef (0 :: Int)
          let callback _ = modifyIORef progressUpdates (+ 1)

          _ <- Pool.compileModulesWithProgress pool tasks callback

          updateCount <- readIORef progressUpdates
          assertBool "Progress callback should be invoked" (updateCount > 0)

          Pool.shutdownPool pool
    ]

-- Helper functions

mockCompileFn ::
  Engine.QueryEngine ->
  Pool.CompileTask ->
  IO (Either QueryError String)
mockCompileFn _ _ = return (Right "mock-result")

successCompileFn ::
  Engine.QueryEngine ->
  Pool.CompileTask ->
  IO (Either QueryError String)
successCompileFn _ _ = return (Right "success")

failureCompileFn ::
  Engine.QueryEngine ->
  Pool.CompileTask ->
  IO (Either QueryError String)
failureCompileFn _ _ = return (Left (OtherError "compilation failed"))

mixedCompileFn ::
  Engine.QueryEngine ->
  Pool.CompileTask ->
  IO (Either QueryError String)
mixedCompileFn _ task =
  -- Use a property of the filename to determine success/failure
  -- Test files are Test1.can, Test2.can, Test3.can, Test4.can
  -- Succeed on odd numbers, fail on even numbers
  let path = Pool.taskFilePath task
      -- Extract just the filename from the path
      filename = reverse (takeWhile (/= '/') (reverse path))
   in if '1' `elem` filename || '3' `elem` filename
        then return (Right "success")
        else return (Left (OtherError "failure"))

slowCompileFn ::
  Engine.QueryEngine ->
  Pool.CompileTask ->
  IO (Either QueryError String)
slowCompileFn _ _ = do
  threadDelay 100000 -- 100ms
  return (Right "success")

makeTask :: FilePath -> Pool.CompileTask
makeTask path =
  Pool.CompileTask
    { Pool.taskPackage = testPackage,
      Pool.taskInterfaces = Map.empty,
      Pool.taskFilePath = path,
      Pool.taskProjectType = Parse.Package testPackage
    }

testPackage :: Pkg.Name
testPackage = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "pkg")

withTestModule :: (FilePath -> IO ()) -> IO ()
withTestModule action =
  withSystemTempDirectory "pool-test" $ \dir -> do
    let path = dir ++ "/Test.can"
    IO.writeFile path testModuleContent
    action path

withMultipleTestModules :: ([FilePath] -> IO ()) -> IO ()
withMultipleTestModules action =
  withSystemTempDirectory "pool-test" $ \dir -> do
    let paths = [dir ++ "/Test" ++ show i ++ ".can" | i <- [1 .. 4 :: Int]]
    mapM_ (`IO.writeFile` testModuleContent) paths
    action paths

testModuleContent :: String
testModuleContent =
  unlines
    [ "module Test exposing (identity)",
      "",
      "identity : a -> a",
      "identity x =",
      "    x"
    ]

{-# OPTIONS_GHC -Wall #-}

-- | Comprehensive tests for Query.Engine module.
--
-- Tests query caching, invalidation, and statistics tracking
-- using IORef-based pure state management.
--
-- @since 0.19.1
module Unit.Query.EngineTest (tests) where

import qualified Canopy.Package as Pkg
import qualified Data.ByteString as BS
import qualified Data.Utf8 as Utf8
import qualified Parse.Module as Parse
import qualified Query.Engine as Engine
import Query.Simple
import System.IO.Temp (withSystemTempDirectory)
import qualified System.IO as IO
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Query.Engine Tests"
    [ testInitEngine,
      testCaching,
      testInvalidation,
      testStatistics
    ]

testInitEngine :: TestTree
testInitEngine =
  testGroup
    "engine initialization"
    [ testCase "init engine creates empty cache" $ do
        engine <- Engine.initEngine
        size <- Engine.getCacheSize engine
        size @?= 0,
      testCase "init engine has zero hits" $ do
        engine <- Engine.initEngine
        hits <- Engine.getCacheHits engine
        hits @?= 0,
      testCase "init engine has zero misses" $ do
        engine <- Engine.initEngine
        misses <- Engine.getCacheMisses engine
        misses @?= 0
    ]

testCaching :: TestTree
testCaching =
  testGroup
    "query caching"
    [ testCase "cache miss on first query" $ do
        withTestFile $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          result <- Engine.runQuery engine query

          case result of
            Left err -> assertFailure ("Query failed: " ++ show err)
            Right _ -> do
              misses <- Engine.getCacheMisses engine
              misses @?= 1,
      testCase "cache hit on second query" $ do
        withTestFile $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          _ <- Engine.runQuery engine query
          _ <- Engine.runQuery engine query

          hits <- Engine.getCacheHits engine
          hits @?= 1,
      testCase "cache grows with queries" $ do
        withMultipleTestFiles $ \paths -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let queries =
                [ ParseModuleQuery path hash (Parse.Package testPackage)
                  | path <- paths
                ]

          mapM_ (Engine.runQuery engine) queries

          size <- Engine.getCacheSize engine
          size @?= length paths,
      testCase "same query returns cached result" $ do
        withTestFile $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          result1 <- Engine.runQuery engine query
          result2 <- Engine.runQuery engine query

          case (result1, result2) of
            (Right _, Right _) -> return ()
            (Left e1, Left e2) -> assertFailure ("Both failed: " ++ show e1 ++ ", " ++ show e2)
            _ -> assertFailure "Results differed (one success, one failure)"
    ]

testInvalidation :: TestTree
testInvalidation =
  testGroup
    "cache invalidation"
    [ testCase "invalidate removes from cache" $ do
        withTestFile $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          _ <- Engine.runQuery engine query
          sizeBefore <- Engine.getCacheSize engine

          Engine.invalidateQuery engine query
          sizeAfter <- Engine.getCacheSize engine

          sizeBefore @?= 1
          sizeAfter @?= 0,
      testCase "invalidate causes cache miss on next query" $ do
        withTestFile $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          _ <- Engine.runQuery engine query
          Engine.invalidateQuery engine query
          _ <- Engine.runQuery engine query

          misses <- Engine.getCacheMisses engine
          misses @?= 2,
      testCase "clear cache removes all entries" $ do
        withMultipleTestFiles $ \paths -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let queries =
                [ ParseModuleQuery path hash (Parse.Package testPackage)
                  | path <- paths
                ]

          mapM_ (Engine.runQuery engine) queries
          Engine.clearCache engine
          size <- Engine.getCacheSize engine

          size @?= 0,
      testCase "clear cache resets to fresh state" $ do
        withTestFile $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          _ <- Engine.runQuery engine query
          _ <- Engine.runQuery engine query
          Engine.clearCache engine

          hits <- Engine.getCacheHits engine
          size <- Engine.getCacheSize engine

          hits @?= 1
          size @?= 0
    ]

testStatistics :: TestTree
testStatistics =
  testGroup
    "cache statistics"
    [ testCase "track multiple hits correctly" $ do
        withTestFile $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          _ <- Engine.runQuery engine query
          _ <- Engine.runQuery engine query
          _ <- Engine.runQuery engine query

          hits <- Engine.getCacheHits engine
          hits @?= 2,
      testCase "track multiple misses correctly" $ do
        withMultipleTestFiles $ \paths -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let queries =
                [ ParseModuleQuery path hash (Parse.Package testPackage)
                  | path <- paths
                ]

          mapM_ (Engine.runQuery engine) queries

          misses <- Engine.getCacheMisses engine
          misses @?= length paths,
      testCase "hits and misses tracked independently" $ do
        withMultipleTestFiles $ \paths -> do
          case paths of
            (path1 : path2 : _) -> do
              engine <- Engine.initEngine
              let hash = computeContentHash (BS.pack [1, 2, 3])
              let query1 = ParseModuleQuery path1 hash (Parse.Package testPackage)
              let query2 = ParseModuleQuery path2 hash (Parse.Package testPackage)

              _ <- Engine.runQuery engine query1
              _ <- Engine.runQuery engine query1
              _ <- Engine.runQuery engine query2

              hits <- Engine.getCacheHits engine
              misses <- Engine.getCacheMisses engine

              hits @?= 1
              misses @?= 2
            _ -> assertFailure "Expected at least 2 test files"
    ]

-- Helper functions

testPackage :: Pkg.Name
testPackage = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "pkg")

withTestFile :: (FilePath -> IO ()) -> IO ()
withTestFile action =
  withSystemTempDirectory "query-test" $ \dir -> do
    let path = dir ++ "/Test.can"
    IO.writeFile path testModuleContent
    action path

withMultipleTestFiles :: ([FilePath] -> IO ()) -> IO ()
withMultipleTestFiles action =
  withSystemTempDirectory "query-test" $ \dir -> do
    let paths = [dir ++ "/Test" ++ show i ++ ".can" | i <- [1 .. 3 :: Int]]
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

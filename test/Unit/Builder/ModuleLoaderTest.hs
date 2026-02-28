{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Builder.ModuleLoader module.
--
-- Tests demand-driven module loading, caching behavior,
-- and module path resolution.
--
-- @since 0.19.2
module Unit.Builder.ModuleLoaderTest (tests) where

import qualified Builder.ModuleLoader as Loader
import qualified Canopy.Data.Utf8 as Utf8
import qualified Data.ByteString.Char8 as C8
import qualified Data.Map.Strict as Map
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO.Temp as Temp
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Builder.ModuleLoader Tests"
    [ testNewLoader,
      testLoadModule,
      testCaching,
      testModuleResolution,
      testPreload,
      testLoadErrors
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- New loader
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testNewLoader :: TestTree
testNewLoader =
  testGroup
    "New loader"
    [ testCase "new loader has empty cache" $ do
        loader <- Loader.newLoader ["/tmp/nonexistent"]
        cached <- Loader.cachedModules loader
        Map.size cached @?= 0,
      testCase "new loader with multiple source dirs" $ do
        loader <- Loader.newLoader ["/src", "/lib", "/test"]
        cached <- Loader.cachedModules loader
        Map.size cached @?= 0
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Load module
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testLoadModule :: TestTree
testLoadModule =
  testGroup
    "Load module"
    [ testCase "loads existing .can file" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          writeModuleFile tmpDir "Main" "module Main exposing (..)"
          loader <- Loader.newLoader [tmpDir]
          result <- Loader.loadModule loader (Utf8.fromChars "Main")
          assertRight result,
      testCase "loads existing .canopy file" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          let path = tmpDir FP.</> "App.canopy"
          C8.writeFile path "module App exposing (..)"
          loader <- Loader.newLoader [tmpDir]
          result <- Loader.loadModule loader (Utf8.fromChars "App")
          assertRight result,
      testCase "loaded module has correct source bytes" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          let content = "module Main exposing (..)"
          writeModuleFile tmpDir "Main" content
          loader <- Loader.newLoader [tmpDir]
          result <- Loader.loadModule loader (Utf8.fromChars "Main")
          assertLoadedSource content result,
      testCase "loads module from dotted path" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          Dir.createDirectoryIfMissing True (tmpDir FP.</> "Data")
          C8.writeFile (tmpDir FP.</> "Data" FP.</> "List.can") "module Data.List exposing (..)"
          loader <- Loader.newLoader [tmpDir]
          result <- Loader.loadModule loader (Utf8.fromChars "Data.List")
          assertRight result
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Caching
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testCaching :: TestTree
testCaching =
  testGroup
    "Caching"
    [ testCase "loaded module is cached" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          writeModuleFile tmpDir "Main" "module Main exposing (..)"
          loader <- Loader.newLoader [tmpDir]
          _ <- Loader.loadModule loader (Utf8.fromChars "Main")
          cached <- Loader.cachedModules loader
          Map.size cached @?= 1,
      testCase "second load returns cached value" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          writeModuleFile tmpDir "Main" "module Main exposing (..)"
          loader <- Loader.newLoader [tmpDir]
          result1 <- Loader.loadModule loader (Utf8.fromChars "Main")
          result2 <- Loader.loadModule loader (Utf8.fromChars "Main")
          assertBothRight result1 result2,
      testCase "clear cache empties the cache" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          writeModuleFile tmpDir "Main" "module Main exposing (..)"
          loader <- Loader.newLoader [tmpDir]
          _ <- Loader.loadModule loader (Utf8.fromChars "Main")
          Loader.clearCache loader
          cached <- Loader.cachedModules loader
          Map.size cached @?= 0,
      testCase "multiple modules are cached independently" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          writeModuleFile tmpDir "Main" "module Main exposing (..)"
          writeModuleFile tmpDir "Utils" "module Utils exposing (..)"
          loader <- Loader.newLoader [tmpDir]
          _ <- Loader.loadModule loader (Utf8.fromChars "Main")
          _ <- Loader.loadModule loader (Utf8.fromChars "Utils")
          cached <- Loader.cachedModules loader
          Map.size cached @?= 2
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Module resolution
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testModuleResolution :: TestTree
testModuleResolution =
  testGroup
    "Module resolution"
    [ testCase "resolves .can file" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          writeModuleFile tmpDir "Main" "content"
          result <- Loader.resolveModulePath [tmpDir] (Utf8.fromChars "Main")
          assertJust result,
      testCase "resolves .canopy file" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          C8.writeFile (tmpDir FP.</> "App.canopy") "content"
          result <- Loader.resolveModulePath [tmpDir] (Utf8.fromChars "App")
          assertJust result,
      testCase "returns Nothing for missing module" $ do
          result <- Loader.resolveModulePath ["/tmp/nonexistent"] (Utf8.fromChars "Missing")
          result @?= Nothing,
      testCase "searches multiple source directories" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          let dir1 = tmpDir FP.</> "src1"
              dir2 = tmpDir FP.</> "src2"
          Dir.createDirectoryIfMissing True dir1
          Dir.createDirectoryIfMissing True dir2
          writeModuleFileIn dir2 "Found" "content"
          result <- Loader.resolveModulePath [dir1, dir2] (Utf8.fromChars "Found")
          assertJust result
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Preload
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testPreload :: TestTree
testPreload =
  testGroup
    "Preload"
    [ testCase "preload caches all available modules" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          writeModuleFile tmpDir "A" "module A exposing (..)"
          writeModuleFile tmpDir "B" "module B exposing (..)"
          loader <- Loader.newLoader [tmpDir]
          errors <- Loader.preloadModules loader [Utf8.fromChars "A", Utf8.fromChars "B"]
          length errors @?= 0
          cached <- Loader.cachedModules loader
          Map.size cached @?= 2,
      testCase "preload returns errors for missing modules" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          writeModuleFile tmpDir "A" "module A exposing (..)"
          loader <- Loader.newLoader [tmpDir]
          errors <- Loader.preloadModules loader [Utf8.fromChars "A", Utf8.fromChars "Missing"]
          length errors @?= 1
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Load errors
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testLoadErrors :: TestTree
testLoadErrors =
  testGroup
    "Load errors"
    [ testCase "ModuleNotFound for nonexistent module" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          loader <- Loader.newLoader [tmpDir]
          result <- Loader.loadModule loader (Utf8.fromChars "Missing")
          assertIsModuleNotFound result,
      testCase "ModuleNotFound error contains source dirs" $
        Temp.withSystemTempDirectory "loader-test" $ \tmpDir -> do
          loader <- Loader.newLoader [tmpDir]
          result <- Loader.loadModule loader (Utf8.fromChars "Missing")
          assertNotFoundContainsDir tmpDir result
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Helpers
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- | Write a .can module file in the given directory.
writeModuleFile :: FilePath -> String -> String -> IO ()
writeModuleFile dir modName content =
  C8.writeFile (dir FP.</> modName ++ ".can") (C8.pack content)

-- | Write a .can module file in a specific directory.
writeModuleFileIn :: FilePath -> String -> String -> IO ()
writeModuleFileIn = writeModuleFile

-- | Assert that a result is Right.
assertRight :: Either Loader.LoadError a -> Assertion
assertRight (Right _) = pure ()
assertRight (Left err) = assertFailure ("Expected Right, got Left: " ++ show err)

-- | Assert that a result is Just.
assertJust :: Maybe a -> Assertion
assertJust (Just _) = pure ()
assertJust Nothing = assertFailure "Expected Just, got Nothing"

-- | Assert both results are Right.
assertBothRight :: Either Loader.LoadError a -> Either Loader.LoadError b -> Assertion
assertBothRight (Right _) (Right _) = pure ()
assertBothRight (Left e) _ = assertFailure ("First result is Left: " ++ show e)
assertBothRight _ (Left e) = assertFailure ("Second result is Left: " ++ show e)

-- | Assert that a loaded module has the expected source content.
assertLoadedSource :: String -> Either Loader.LoadError Loader.LoadedModule -> Assertion
assertLoadedSource expected (Right loaded) =
  Loader._lmSource loaded @?= C8.pack expected
assertLoadedSource _ (Left err) =
  assertFailure ("Expected Right, got Left: " ++ show err)

-- | Assert that the result is a ModuleNotFound error.
assertIsModuleNotFound :: Either Loader.LoadError a -> Assertion
assertIsModuleNotFound (Left (Loader.ModuleNotFound _ _)) = pure ()
assertIsModuleNotFound (Left err) = assertFailure ("Expected ModuleNotFound, got: " ++ show err)
assertIsModuleNotFound (Right _) = assertFailure "Expected Left ModuleNotFound, got Right"

-- | Assert that a ModuleNotFound error contains the given directory.
assertNotFoundContainsDir :: FilePath -> Either Loader.LoadError a -> Assertion
assertNotFoundContainsDir dir (Left (Loader.ModuleNotFound _ dirs)) =
  assertBool ("Expected dirs to contain " ++ dir) (dir `elem` dirs)
assertNotFoundContainsDir _ (Left err) =
  assertFailure ("Expected ModuleNotFound, got: " ++ show err)
assertNotFoundContainsDir _ (Right _) =
  assertFailure "Expected Left ModuleNotFound, got Right"

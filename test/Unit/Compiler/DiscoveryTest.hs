{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Compiler.Discovery module.
--
-- Tests module path resolution, import extraction, parallel BFS
-- discovery, and path caching. Integration tests create temporary
-- directory structures with real .can source files to verify
-- end-to-end transitive dependency discovery.
--
-- @since 0.19.2
module Unit.Compiler.DiscoveryTest (tests) where

import Compiler.Discovery
  ( DiscoveryError (..),
    discoverModulePaths,
    discoverTransitiveDeps,
    findModuleInDirs,
    findModulePath,
    moduleNameToBasePath,
    readSourceWithLimit,
    splitOn,
  )
import Compiler.Types (SrcDir (..))
import qualified Canopy.Data.Name as Name
import Canopy.Interface (Interface (..))
import qualified Canopy.Package as Pkg
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Parse.Module as Parse
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Compiler.Discovery Tests"
    [ splitOnTests,
      moduleNameToBasePathTests,
      pathResolutionTests,
      sourceReadingTests,
      transitiveDiscoveryTests
    ]

-- SPLIT ON TESTS

splitOnTests :: TestTree
splitOnTests =
  testGroup
    "splitOn"
    [ testCase "empty string returns empty list" $
        splitOn '.' "" @?= [],
      testCase "single element with no delimiter" $
        splitOn '.' "Main" @?= ["Main"],
      testCase "two parts" $
        splitOn '.' "Data.List" @?= ["Data", "List"],
      testCase "three parts" $
        splitOn '.' "Data.List.Extra" @?= ["Data", "List", "Extra"],
      testCase "different delimiter" $
        splitOn '/' "a/b/c" @?= ["a", "b", "c"],
      testCase "trailing delimiter is consumed without empty element" $
        splitOn '.' "A." @?= ["A"],
      testCase "leading delimiter produces empty first element" $
        splitOn '.' ".A" @?= ["", "A"]
    ]

-- MODULE NAME TO BASE PATH TESTS

moduleNameToBasePathTests :: TestTree
moduleNameToBasePathTests =
  testGroup
    "moduleNameToBasePath"
    [ testCase "simple module name" $
        moduleNameToBasePath (Name.fromChars "Main") @?= "Main",
      testCase "dotted module name" $
        moduleNameToBasePath (Name.fromChars "Data.List") @?= "Data" </> "List",
      testCase "deeply nested module name" $
        moduleNameToBasePath (Name.fromChars "App.View.Components.Button")
          @?= "App" </> "View" </> "Components" </> "Button"
    ]

-- PATH RESOLUTION TESTS

pathResolutionTests :: TestTree
pathResolutionTests =
  testGroup
    "path resolution"
    [ testCase "findModulePath returns Nothing for non-existent module" $
        Temp.withSystemTempDirectory "disc-path" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          result <- findModulePath tmpDir [srcDir] (Name.fromChars "NonExistent")
          result @?= Nothing,
      testCase "findModulePath finds .can file" $
        Temp.withSystemTempDirectory "disc-can" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nx = 1\n"
          result <- findModulePath tmpDir [srcDir] (Name.fromChars "Main")
          case result of
            Just p -> assertBool "path ends with Main.can" (".can" `isSuffixOf` p)
            Nothing -> assertFailure "expected to find Main.can",
      testCase "findModulePath finds .elm file" $
        Temp.withSystemTempDirectory "disc-elm" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.elm") "module Main exposing (..)\nx = 1\n"
          result <- findModulePath tmpDir [srcDir] (Name.fromChars "Main")
          case result of
            Just p -> assertBool "path ends with Main.elm" (".elm" `isSuffixOf` p)
            Nothing -> assertFailure "expected to find Main.elm",
      testCase "findModulePath prefers .can over .elm" $
        Temp.withSystemTempDirectory "disc-prefer" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nx = 1\n"
          BS.writeFile (tmpDir </> "src" </> "Main.elm") "module Main exposing (..)\nx = 2\n"
          result <- findModulePath tmpDir [srcDir] (Name.fromChars "Main")
          case result of
            Just p -> assertBool "path ends with Main.can" (".can" `isSuffixOf` p)
            Nothing -> assertFailure "expected to find Main.can",
      testCase "findModuleInDirs finds dotted module" $
        Temp.withSystemTempDirectory "disc-dotted" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectoryIfMissing True (tmpDir </> "src" </> "Data")
          BS.writeFile (tmpDir </> "src" </> "Data" </> "Utils.can") "module Data.Utils exposing (..)\nx = 1\n"
          result <- findModuleInDirs tmpDir [srcDir] (Name.fromChars "Data.Utils")
          length result @?= 1,
      testCase "findModuleInDirs searches multiple src dirs" $
        Temp.withSystemTempDirectory "disc-multi-src" $ \tmpDir -> do
          let srcDirA = RelativeSrcDir "srcA"
              srcDirB = RelativeSrcDir "srcB"
          Dir.createDirectory (tmpDir </> "srcA")
          Dir.createDirectory (tmpDir </> "srcB")
          BS.writeFile (tmpDir </> "srcB" </> "Lib.can") "module Lib exposing (..)\nx = 1\n"
          result <- findModulePath tmpDir [srcDirA, srcDirB] (Name.fromChars "Lib")
          case result of
            Just p -> assertBool "found in srcB" ("srcB" `isInfixOf` p)
            Nothing -> assertFailure "expected to find Lib.can in srcB",
      testCase "discoverModulePaths finds multiple modules" $
        Temp.withSystemTempDirectory "disc-multi" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "A.can") "module A exposing (..)\nx = 1\n"
          BS.writeFile (tmpDir </> "src" </> "B.can") "module B exposing (..)\ny = 2\n"
          result <- discoverModulePaths tmpDir [srcDir] [Name.fromChars "A", Name.fromChars "B"]
          length result @?= 2
    ]

-- SOURCE READING TESTS

sourceReadingTests :: TestTree
sourceReadingTests =
  testGroup
    "readSourceWithLimit"
    [ testCase "reads small file successfully" $
        Temp.withSystemTempDirectory "disc-read" $ \tmpDir -> do
          let path = tmpDir </> "test.can"
          BS.writeFile path "module Test exposing (..)\n"
          content <- readSourceWithLimit path
          content @?= "module Test exposing (..)\n"
    ]

-- TRANSITIVE DISCOVERY TESTS

transitiveDiscoveryTests :: TestTree
transitiveDiscoveryTests =
  testGroup
    "discoverTransitiveDeps (parallel BFS)"
    [ testCase "discovers single module with no imports" $
        Temp.withSystemTempDirectory "disc-single" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nx = 1\n"
          result <- discoverTransitiveDeps tmpDir [srcDir] [tmpDir </> "src" </> "Main.can"] Map.empty Parse.Application
          case result of
            Right modules -> do
              Map.size modules @?= 1
              assertBool "contains Main" (Map.member (Name.fromChars "Main") modules)
            Left err -> assertFailure ("discovery failed: " ++ show err),
      testCase "discovers transitive imports" $
        Temp.withSystemTempDirectory "disc-trans" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nimport Utils\nx = 1\n"
          BS.writeFile (tmpDir </> "src" </> "Utils.can") "module Utils exposing (..)\ny = 2\n"
          result <- discoverTransitiveDeps tmpDir [srcDir] [tmpDir </> "src" </> "Main.can"] Map.empty Parse.Application
          case result of
            Right modules -> do
              Map.size modules @?= 2
              assertBool "contains Main" (Map.member (Name.fromChars "Main") modules)
              assertBool "contains Utils" (Map.member (Name.fromChars "Utils") modules)
            Left err -> assertFailure ("discovery failed: " ++ show err),
      testCase "discovers deep transitive chain" $
        Temp.withSystemTempDirectory "disc-deep" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nimport A\nx = 1\n"
          BS.writeFile (tmpDir </> "src" </> "A.can") "module A exposing (..)\nimport B\na = 1\n"
          BS.writeFile (tmpDir </> "src" </> "B.can") "module B exposing (..)\nimport C\nb = 1\n"
          BS.writeFile (tmpDir </> "src" </> "C.can") "module C exposing (..)\nc = 1\n"
          result <- discoverTransitiveDeps tmpDir [srcDir] [tmpDir </> "src" </> "Main.can"] Map.empty Parse.Application
          case result of
            Right modules -> do
              Map.size modules @?= 4
              assertBool "contains C" (Map.member (Name.fromChars "C") modules)
            Left err -> assertFailure ("discovery failed: " ++ show err),
      testCase "discovers diamond dependency" $
        Temp.withSystemTempDirectory "disc-diamond" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nimport Left\nimport Right\nx = 1\n"
          BS.writeFile (tmpDir </> "src" </> "Left.can") "module Left exposing (..)\nimport Base\nl = 1\n"
          BS.writeFile (tmpDir </> "src" </> "Right.can") "module Right exposing (..)\nimport Base\nr = 1\n"
          BS.writeFile (tmpDir </> "src" </> "Base.can") "module Base exposing (..)\nb = 1\n"
          result <- discoverTransitiveDeps tmpDir [srcDir] [tmpDir </> "src" </> "Main.can"] Map.empty Parse.Application
          case result of
            Right modules -> do
              Map.size modules @?= 4
              assertBool "contains Base" (Map.member (Name.fromChars "Base") modules)
              assertBool "contains Left" (Map.member (Name.fromChars "Left") modules)
              assertBool "contains Right" (Map.member (Name.fromChars "Right") modules)
            Left err -> assertFailure ("discovery failed: " ++ show err),
      testCase "skips modules already in depInterfaces" $
        Temp.withSystemTempDirectory "disc-skip-dep" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nimport ExternalLib\nx = 1\n"
          let stubInterface = Interface Pkg.core Map.empty Map.empty Map.empty Map.empty Map.empty Map.empty []
              depInterfaces = Map.singleton (Name.fromChars "ExternalLib") stubInterface
          result <- discoverTransitiveDeps tmpDir [srcDir] [tmpDir </> "src" </> "Main.can"] depInterfaces Parse.Application
          case result of
            Right modules -> do
              Map.size modules @?= 1
              assertBool "does not contain ExternalLib" (not (Map.member (Name.fromChars "ExternalLib") modules))
            Left err -> assertFailure ("discovery failed: " ++ show err),
      testCase "returns error for parse failure" $
        Temp.withSystemTempDirectory "disc-parse-err" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nimport Bad\nx = 1\n"
          BS.writeFile (tmpDir </> "src" </> "Bad.can") "this is not valid canopy syntax!!!"
          result <- discoverTransitiveDeps tmpDir [srcDir] [tmpDir </> "src" </> "Main.can"] Map.empty Parse.Application
          case result of
            Left (DiscoveryParseError path _msg) ->
              assertBool "error path contains Bad.can" ("Bad.can" `isSuffixOf` path)
            Right _ -> assertFailure "expected parse error",
      testCase "handles multiple entry points" $
        Temp.withSystemTempDirectory "disc-multi-entry" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "App.can") "module App exposing (..)\nimport Shared\na = 1\n"
          BS.writeFile (tmpDir </> "src" </> "Worker.can") "module Worker exposing (..)\nimport Shared\nw = 1\n"
          BS.writeFile (tmpDir </> "src" </> "Shared.can") "module Shared exposing (..)\ns = 1\n"
          result <- discoverTransitiveDeps tmpDir [srcDir]
            [tmpDir </> "src" </> "App.can", tmpDir </> "src" </> "Worker.can"]
            Map.empty Parse.Application
          case result of
            Right modules -> do
              Map.size modules @?= 3
              assertBool "contains Shared" (Map.member (Name.fromChars "Shared") modules)
            Left err -> assertFailure ("discovery failed: " ++ show err),
      testCase "preserves import lists in results" $
        Temp.withSystemTempDirectory "disc-imports" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nimport A\nimport B\nx = 1\n"
          BS.writeFile (tmpDir </> "src" </> "A.can") "module A exposing (..)\na = 1\n"
          BS.writeFile (tmpDir </> "src" </> "B.can") "module B exposing (..)\nb = 1\n"
          result <- discoverTransitiveDeps tmpDir [srcDir] [tmpDir </> "src" </> "Main.can"] Map.empty Parse.Application
          case result of
            Right modules ->
              case Map.lookup (Name.fromChars "Main") modules of
                Just (_path, imports) -> do
                  let importSet = Set.fromList imports
                  assertBool "Main imports A" (Set.member (Name.fromChars "A") importSet)
                  assertBool "Main imports B" (Set.member (Name.fromChars "B") importSet)
                Nothing -> assertFailure "Main not found in results"
            Left err -> assertFailure ("discovery failed: " ++ show err),
      testCase "handles dotted module names in subdirectories" $
        Temp.withSystemTempDirectory "disc-dotted-mod" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectoryIfMissing True (tmpDir </> "src" </> "Data")
          BS.writeFile (tmpDir </> "src" </> "Main.can") "module Main exposing (..)\nimport Data.Utils\nx = 1\n"
          BS.writeFile (tmpDir </> "src" </> "Data" </> "Utils.can") "module Data.Utils exposing (..)\nu = 1\n"
          result <- discoverTransitiveDeps tmpDir [srcDir] [tmpDir </> "src" </> "Main.can"] Map.empty Parse.Application
          case result of
            Right modules -> do
              Map.size modules @?= 2
              assertBool "contains Data.Utils" (Map.member (Name.fromChars "Data.Utils") modules)
            Left err -> assertFailure ("discovery failed: " ++ show err),
      testCase "no imports yields only entry module" $
        Temp.withSystemTempDirectory "disc-no-imports" $ \tmpDir -> do
          let srcDir = RelativeSrcDir "src"
          Dir.createDirectory (tmpDir </> "src")
          BS.writeFile (tmpDir </> "src" </> "Solo.can") "module Solo exposing (..)\nx = 1\n"
          result <- discoverTransitiveDeps tmpDir [srcDir] [tmpDir </> "src" </> "Solo.can"] Map.empty Parse.Application
          case result of
            Right modules -> Map.size modules @?= 1
            Left err -> assertFailure ("discovery failed: " ++ show err)
    ]

-- HELPERS

-- | Check if a string is a suffix of another string.
isSuffixOf :: String -> String -> Bool
isSuffixOf needle haystack =
  drop (length haystack - length needle) haystack == needle

-- | Check if a string is contained within another string.
isInfixOf :: String -> String -> Bool
isInfixOf [] _ = True
isInfixOf _ [] = False
isInfixOf needle haystack@(_ : rest)
  | take (length needle) haystack == needle = True
  | otherwise = isInfixOf needle rest

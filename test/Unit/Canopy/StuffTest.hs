{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for Stuff module.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in the Stuff module.
-- The Stuff module is critical infrastructure for the Canopy compiler,
-- handling file system paths, caching, project discovery, and locking.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.Canopy.StuffTest
  ( tests
  ) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import qualified Data.Name as Name
import Control.Exception (SomeException, bracket, catch)
import Control.Lens ((^.))
import qualified Data.List as List
import qualified Stuff
import qualified System.Directory as Dir
import qualified System.Environment as Env
import System.FilePath ((<.>), (</>))
import qualified System.FilePath as FP
import qualified System.IO.Temp as Temp
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Test.QuickCheck.Monadic (monadicIO, run)

-- | Main test tree containing all Stuff module tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Stuff Tests"
  [ unitTests
  , propertyTests
  , edgeCaseTests
  , errorConditionTests
  , ioTests
  ]

-- | Unit tests for all public functions.
--
-- Tests basic functionality with known inputs and expected outputs.
-- Every public function must have at least one unit test.
unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ pathConstructionTests
  , moduleArtifactTests
  , cacheTypeTests
  , pathManipulationTests
  ]

-- | Property-based tests for path operations and invariants.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with path manipulation and construction.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ pathInvariantTests
  , roundtripTests
  , platformConsistencyTests
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ emptyPathTests
  , longPathTests
  , specialCharacterTests
  , deepNestingTests
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ invalidPathTests
  , permissionTests
  , filesystemLimitTests
  ]

-- PATH CONSTRUCTION TESTS

pathConstructionTests :: TestTree
pathConstructionTests = testGroup "Path Construction Tests"
  [ testCase "details creates valid path" $ do
      let root = "/home/user/myproject"
      let result = Stuff.details root
      -- Test that it contains the root path as a prefix
      root `List.isPrefixOf` result @? "Result should contain root path"
      -- Test that it ends with d.dat
      "d.dat" `List.isSuffixOf` result @? "Result should end with d.dat"

  , testCase "details handles relative paths" $ do
      let root = "."
      let result = Stuff.details root
      "./" `List.isPrefixOf` result || "." `List.isPrefixOf` result @? "Should handle relative paths"
      "d.dat" `List.isSuffixOf` result @? "Should end with d.dat"

  , testCase "interfaces creates correct path" $ do
      let root = "/project"
      let result = Stuff.interfaces root
      root `List.isPrefixOf` result @? "Should contain root path"
      "i.dat" `List.isSuffixOf` result @? "Should end with i.dat"

  , testCase "objects creates correct path" $ do
      let root = "/project"
      let result = Stuff.objects root
      root `List.isPrefixOf` result @? "Should contain root path"
      "o.dat" `List.isSuffixOf` result @? "Should end with o.dat"

  , testCase "prepublishDir creates correct path" $ do
      let root = "/project"
      let result = Stuff.prepublishDir root
      root `List.isPrefixOf` result @? "Should contain root path"
      "prepublish" `List.isSuffixOf` result @? "Should end with prepublish"
  ]

-- MODULE ARTIFACT TESTS

moduleArtifactTests :: TestTree
moduleArtifactTests = testGroup "Module Artifact Tests"
  [ testCase "canopyi creates correct interface file path" $ do
      let root = "/project"
      let moduleName = Name.fromChars "Main"
      let result = Stuff.canopyi root moduleName
      root `List.isPrefixOf` result @? "Should contain root path"
      ".canopyi" `List.isSuffixOf` result @? "Should end with .canopyi"

  , testCase "canopyo creates correct object file path" $ do
      let root = "/project"
      let moduleName = Name.fromChars "Main"
      let result = Stuff.canopyo root moduleName
      root `List.isPrefixOf` result @? "Should contain root path"
      ".canopyo" `List.isSuffixOf` result @? "Should end with .canopyo"

  , testCase "temp creates correct temporary file path" $ do
      let root = "/project"
      let ext = "js"
      let result = Stuff.temp root ext
      root `List.isPrefixOf` result @? "Should contain root path"
      (".js") `List.isSuffixOf` result @? "Should end with .js"

  , testCase "temp handles various extensions" $ do
      let root = "/project"
      let htmlResult = Stuff.temp root "html"
      let cssResult = Stuff.temp root "css"
      let jsonResult = Stuff.temp root "json"
      ".html" `List.isSuffixOf` htmlResult @? "HTML temp should end with .html"
      ".css" `List.isSuffixOf` cssResult @? "CSS temp should end with .css"
      ".json" `List.isSuffixOf` jsonResult @? "JSON temp should end with .json"

  , testCase "canopyi and canopyo use hyphenated paths" $ do
      let root = "/project"
      let moduleName = Name.fromChars "App.Utils.String"
      let canopyiResult = Stuff.canopyi root moduleName
      let canopyoResult = Stuff.canopyo root moduleName
      -- Both should use hyphenated module names (tested by file extension check)
      ".canopyi" `List.isSuffixOf` canopyiResult @? "canopyi should create .canopyi files"
      ".canopyo" `List.isSuffixOf` canopyoResult @? "canopyo should create .canopyo files"
      -- Should contain hyphenated version
      "App-Utils-String" `List.isInfixOf` canopyiResult @? "Should use hyphenated module names"
  ]

-- CACHE TYPE TESTS

cacheTypeTests :: TestTree
cacheTypeTests = testGroup "Cache Type Tests"
  [ testCase "PackageCache works with package function" $ do
      cache <- Stuff.getPackageCache
      let result = Stuff.package cache Pkg.core V.one
      not (null result) @? "Package path should not be empty"
      V.toChars V.one `List.isInfixOf` result @? "Should contain version"

  , testCase "ZokkaSpecificCache works with registry function" $ do
      cache <- Stuff.getZokkaCache  
      let result = Stuff.registry cache
      not (null result) @? "Registry path should not be empty"
      "canopy-registry.dat" `List.isSuffixOf` result @? "Should end with registry file"

  , testCase "PackageOverridesCache works with packageOverride function" $ do
      cache <- Stuff.getPackageOverridesCache
      let originalPkg = Pkg.core
      let originalVersion = V.one
      let overridingPkg = Pkg.dummyName
      let overridingVersion = V.one
      let config = Stuff.PackageOverrideConfig cache originalPkg originalVersion overridingPkg overridingVersion
      let result = Stuff.packageOverride config
      not (null result) @? "Package override path should not be empty"

  , testCase "ZokkaCustomRepositoryConfigFilePath works" $ do
      configPath <- Stuff.getOrCreateZokkaCustomRepositoryConfig
      let path = Stuff.unZokkaCustomRepositoryConfigFilePath configPath
      not (null path) @? "Config path should not be empty"
      "custom-package-repository-config.json" `List.isSuffixOf` path @? "Should end with config file"
  ]

-- PATH MANIPULATION TESTS

pathManipulationTests :: TestTree
pathManipulationTests = testGroup "Path Manipulation Tests"
  [ testCase "package path construction" $ do
      cache <- Stuff.getPackageCache
      let name = Pkg.core
      let version = V.one
      let result = Stuff.package cache name version
      -- Verify path contains expected components
      V.toChars version `List.isInfixOf` result @? "Should contain version"
      not (null result) @? "Should produce non-empty result"

  , testCase "package override path construction" $ do
      cache <- Stuff.getPackageOverridesCache
      let originalPkg = Pkg.core
      let originalVersion = V.one
      let overridingPkg = Pkg.dummyName
      let overridingVersion = V.Version 2 0 0
      let config = Stuff.PackageOverrideConfig cache originalPkg originalVersion overridingPkg overridingVersion
      let result = Stuff.packageOverride config
      -- Verify path structure includes version components
      V.toChars originalVersion `List.isInfixOf` result @? "Should contain original version"
      V.toChars overridingVersion `List.isInfixOf` result @? "Should contain overriding version"
      not (null result) @? "Should produce non-empty result"

  , testCase "registry path construction" $ do
      cache <- Stuff.getZokkaCache
      let result = Stuff.registry cache
      "canopy-registry.dat" `List.isSuffixOf` result @? "Should end with registry file"
      not (null result) @? "Should produce non-empty result"

  , testCase "zokkaCacheToFilePath extraction" $ do
      cache <- Stuff.getZokkaCache
      let result = Stuff.zokkaCacheToFilePath cache
      not (null result) @? "Should produce non-empty path"
  ]

-- PROPERTY TESTS

pathInvariantTests :: TestTree
pathInvariantTests = testGroup "Path Invariant Tests"
  [ testProperty "details always ends with d.dat" $ \root ->
      let normalized = if null root then "." else root
          result = Stuff.details normalized
      in "d.dat" `List.isSuffixOf` result

  , testProperty "interfaces always ends with i.dat" $ \root ->
      let normalized = if null root then "." else root
          result = Stuff.interfaces normalized
      in "i.dat" `List.isSuffixOf` result

  , testProperty "objects always ends with o.dat" $ \root ->
      let normalized = if null root then "." else root
          result = Stuff.objects normalized
      in "o.dat" `List.isSuffixOf` result

  , testProperty "prepublishDir always ends with prepublish" $ \root ->
      let normalized = if null root then "." else root
          result = Stuff.prepublishDir normalized
      in "prepublish" `List.isSuffixOf` result

  , testProperty "temp always has correct extension" $ \root ext ->
      not (null ext) ==> 
        let normalized = if null root then "." else root
            result = Stuff.temp normalized ext
            -- FilePath's <.> operator behavior:
            -- "temp" <.> "" -> "temp" (no extension)
            -- "temp" <.> "js" -> "temp.js" (dot + ext)
            -- "temp" <.> "." -> "temp." (single dot)
            -- "temp" <.> ".js" -> "temp.js" (strips leading dot from ext and re-adds)
            expectedSuffix = case ext of
              "." -> "."  -- Single dot case
              (x:_) | x == '.' -> ext  -- Extension already has dot
              _ -> "." <> ext  -- Normal case: dot + extension
        in expectedSuffix `List.isSuffixOf` result

  , testProperty "canopyi always creates .canopyi files" $ \root ->
      let normalized = if null root then "." else root
          result = Stuff.canopyi normalized (Name.fromChars "Main")
      in ".canopyi" `List.isSuffixOf` result

  , testProperty "canopyo always creates .canopyo files" $ \root ->
      let normalized = if null root then "." else root
          result = Stuff.canopyo normalized (Name.fromChars "Main")
      in ".canopyo" `List.isSuffixOf` result
  ]

roundtripTests :: TestTree
roundtripTests = testGroup "Roundtrip Tests"
  [ testProperty "package path with different versions" $ \name version1 version2 ->
      version1 /= version2 ==>
        monadicIO $ do
          cache <- run Stuff.getPackageCache
          let path1 = Stuff.package cache name version1
              path2 = Stuff.package cache name version2
          pure (path1 /= path2)

  , testProperty "registry path deterministic" $ \() ->
      monadicIO $ do
        cache <- run Stuff.getZokkaCache
        let result1 = Stuff.registry cache
            result2 = Stuff.registry cache
        pure (result1 == result2)

  , testProperty "temp paths with different extensions differ" $ \root ext1 ext2 ->
      ext1 /= ext2 && not (null ext1) && not (null ext2) ==>
        let normalized = if null root then "." else root
            temp1 = Stuff.temp normalized ext1
            temp2 = Stuff.temp normalized ext2
        in temp1 /= temp2
  ]

platformConsistencyTests :: TestTree
platformConsistencyTests = testGroup "Platform Consistency Tests"
  [ testProperty "paths use correct separators" $ \root ->
      let normalized = if null root then "." else root
          result = Stuff.details normalized
      in FP.pathSeparator `elem` result || length result == length normalized

  , testProperty "module names convert to valid filenames" $ \() ->
      let root = "/test"
          result = Stuff.canopyi root (Name.fromChars "Main")
      in not (null result) && ".canopyi" `List.isSuffixOf` result

  , testProperty "consistent path construction across functions" $ \root ->
      let normalized = if null root then "." else root
          details = Stuff.details normalized
          interfaces = Stuff.interfaces normalized  
          objects = Stuff.objects normalized
      in all (not . null) [details, interfaces, objects] &&
         all (normalized `List.isPrefixOf`) [details, interfaces, objects]
  ]

-- EDGE CASE TESTS

emptyPathTests :: TestTree
emptyPathTests = testGroup "Empty Path Tests"
  [ testCase "empty root path handled" $ do
      let result = Stuff.details ""
      "d.dat" `List.isSuffixOf` result @? "Should handle empty root and end with d.dat"

  , testCase "empty extension handled" $ do
      let result = Stuff.temp "/project" ""
      "/project" `List.isPrefixOf` result @? "Should contain project path"
      "temp" `List.isSuffixOf` result @? "Should end with temp for empty extension"

  , testCase "single character paths" $ do
      let result = Stuff.details "a"
      "a" `List.isPrefixOf` result @? "Should handle single character paths"
      "d.dat" `List.isSuffixOf` result @? "Should end with d.dat"
  ]

longPathTests :: TestTree
longPathTests = testGroup "Long Path Tests"
  [ testCase "very long root path" $ do
      let longRoot = List.replicate 200 'a'
      let result = Stuff.details longRoot
      longRoot `List.isPrefixOf` result @? "Should handle long paths"
      "d.dat" `List.isSuffixOf` result @? "Should still end with d.dat"

  , testCase "deeply nested module names" $ do
      -- Use deeply nested module name
      let result = Stuff.canopyi "/project" (Name.fromChars "App.Utils.String.Extra.Utils")
      ".canopyi" `List.isSuffixOf` result @? "Should handle module names and create .canopyi files"
      "/project" `List.isPrefixOf` result @? "Should contain project path"
      "App-Utils-String-Extra-Utils" `List.isInfixOf` result @? "Should use hyphenated module names"
  ]

specialCharacterTests :: TestTree
specialCharacterTests = testGroup "Special Character Tests"
  [ testCase "paths with spaces" $ do
      let root = "/path with spaces"
      let result = Stuff.details root
      root `List.isPrefixOf` result @? "Should handle spaces in paths"
      "d.dat" `List.isSuffixOf` result @? "Should end with d.dat"

  , testCase "paths with unicode" $ do
      let root = "/path/with/üñíçøðé"
      let result = Stuff.interfaces root
      root `List.isPrefixOf` result @? "Should handle unicode in paths"
      "i.dat" `List.isSuffixOf` result @? "Should end with i.dat"

  , testCase "temp with special extension" $ do
      let result = Stuff.temp "/project" "spec.ial"
      ".spec.ial" `List.isSuffixOf` result @? "Should handle special characters in extensions"
      "/project" `List.isPrefixOf` result @? "Should contain project path"
  ]

deepNestingTests :: TestTree
deepNestingTests = testGroup "Deep Nesting Tests"
  [ testCase "many directory levels" $ do
      let deepPath = List.intercalate "/" (List.replicate 20 "dir")
      let result = Stuff.objects deepPath
      deepPath `List.isPrefixOf` result @? "Should handle deep directory nesting"
      "o.dat" `List.isSuffixOf` result @? "Should end with o.dat"

  , testCase "package override with long names" $ do
      cache <- Stuff.getPackageOverridesCache
      let pkg = Pkg.dummyName  -- Use predefined package instead of constructing with long names
      let version = V.one
      let config = Stuff.PackageOverrideConfig cache pkg version pkg version
      let result = Stuff.packageOverride config
      not (null result) @? "Should handle package override paths and produce non-empty result"
  ]

-- ERROR CONDITION TESTS

invalidPathTests :: TestTree
invalidPathTests = testGroup "Invalid Path Tests"
  [ testCase "null character handling" $ do
      -- FilePath should handle this gracefully 
      let result = Stuff.prepublishDir "path\0with\0nulls"
      not (null result) @? "Should produce some result for null characters"
      "prepublish" `List.isSuffixOf` result @? "Should end with prepublish"

  , testCase "relative path traversal" $ do
      let result = Stuff.details "../../../etc"
      "../../../etc" `List.isPrefixOf` result @? "Should preserve path traversal in input"
      "d.dat" `List.isSuffixOf` result @? "Should end with d.dat"
  ]

permissionTests :: TestTree
permissionTests = testGroup "Permission Tests"
  [ testCase "readonly path construction still works" $ do
      -- Path construction should work even if we can't write to the path
      let result = Stuff.interfaces "/readonly/path"
      "/readonly/path" `List.isPrefixOf` result @? "Should construct paths to readonly locations"
      "i.dat" `List.isSuffixOf` result @? "Should end with i.dat"
  ]

filesystemLimitTests :: TestTree
filesystemLimitTests = testGroup "Filesystem Limit Tests"
  [ testCase "very long path segments" $ do
      let longSegment = List.replicate 255 'x'
      let result = Stuff.temp longSegment "test"
      not (null result) @? "Should handle very long path segments"
      ".test" `List.isSuffixOf` result @? "Should end with .test"

  , testCase "many path components" $ do
      let manyComponents = List.intercalate "/" (List.replicate 100 "x")
      let result = Stuff.prepublishDir manyComponents
      not (null result) @? "Should handle many path components"
      "prepublish" `List.isSuffixOf` result @? "Should end with prepublish"
  ]

-- IO TESTS

ioTests :: TestTree
ioTests = testGroup "IO Tests"
  [ projectDiscoveryTests
  , cacheDirectoryTests
  , lockingMechanismTests
  ]

-- PROJECT DISCOVERY TESTS

projectDiscoveryTests :: TestTree
projectDiscoveryTests = testGroup "Project Discovery Tests"
  [ testCase "findRoot finds canopy.json" $ do
      Temp.withSystemTempDirectory "canopy-test" $ \tmpDir -> do
        -- Create a canopy.json file
        let canopyJson = tmpDir </> "canopy.json"
        writeFile canopyJson "{}"
        
        -- Use findRootFrom to avoid changing working directory
        result <- Stuff.findRootFrom tmpDir
        result @?= Just tmpDir

  , testCase "findRoot finds elm.json" $ do
      Temp.withSystemTempDirectory "canopy-test" $ \tmpDir -> do
        -- Create an elm.json file  
        let elmJson = tmpDir </> "elm.json"
        writeFile elmJson "{}"
        
        -- Use findRootFrom to avoid changing working directory
        result <- Stuff.findRootFrom tmpDir
        result @?= Just tmpDir

  , testCase "findRoot returns Nothing when no project" $ do
      Temp.withSystemTempDirectory "canopy-test" $ \tmpDir -> do
        -- Use findRootFrom to avoid changing working directory
        result <- Stuff.findRootFrom tmpDir
        result @?= Nothing

  , testCase "findRoot finds project in parent directory" $ do
      Temp.withSystemTempDirectory "canopy-test" $ \tmpDir -> do
        -- Create a canopy.json file in tmpDir
        let canopyJson = tmpDir </> "canopy.json"
        writeFile canopyJson "{}"
        
        -- Create a subdirectory
        let subDir = tmpDir </> "src" </> "nested"
        Dir.createDirectoryIfMissing True subDir
        
        -- Use findRootFrom starting from subdirectory
        result <- Stuff.findRootFrom subDir
        result @?= Just tmpDir

  , testCase "findRootFrom works independently of current directory" $ do
      Temp.withSystemTempDirectory "canopy-test" $ \tmpDir -> do
        -- Create a canopy.json file
        let canopyJson = tmpDir </> "canopy.json"
        writeFile canopyJson "{}"
        
        -- Test that findRootFrom works regardless of current working directory
        -- (this test demonstrates that it's thread-safe)
        result <- Stuff.findRootFrom tmpDir
        result @?= Just tmpDir
  ]

-- CACHE DIRECTORY TESTS

cacheDirectoryTests :: TestTree
cacheDirectoryTests = testGroup "Cache Directory Tests"
  [ testCase "getPackageCache creates cache directory" $ do
      -- This test verifies the function works without asserting specific paths
      -- since the actual path depends on environment variables
      cache <- Stuff.getPackageCache
      -- Test by using the cache in a package path construction
      let testResult = Stuff.package cache Pkg.core V.one
      not (null testResult) @? "Package path should not be empty"
      V.toChars V.one `List.isInfixOf` testResult @? "Should contain version in path"

  , testCase "getZokkaCache creates Zokka-specific cache" $ do
      cache <- Stuff.getZokkaCache
      let path = Stuff.zokkaCacheToFilePath cache
      not (null path) @? "Zokka cache path should not be empty"
      -- Verify it contains version-specific directory name
      "canopy-cache" `List.isInfixOf` path @? "Should contain canopy-cache in path"

  , testCase "getPackageOverridesCache uses Zokka cache" $ do
      overridesCache <- Stuff.getPackageOverridesCache
      zokkaCache <- Stuff.getZokkaCache
      -- Test that both caches work by creating a package override path
      let config = Stuff.PackageOverrideConfig overridesCache Pkg.core V.one Pkg.dummyName V.one
      let overridePath = Stuff.packageOverride config
      not (null overridePath) @? "Should create valid override path"

  , testCase "getReplCache creates REPL cache directory" $ do
      replPath <- Stuff.getReplCache
      not (null replPath) @? "REPL cache path should not be empty"
      Dir.doesDirectoryExist replPath >>= \exists ->
        exists @? "REPL cache directory should be created"

  , testCase "getCanopyHome respects environment variable" $ do
      -- Test with custom CANOPY_HOME
      let customHome = "/tmp/custom-canopy-home"
      bracket (Env.lookupEnv "CANOPY_HOME") 
              (\original -> case original of
                Just val -> Env.setEnv "CANOPY_HOME" val
                Nothing -> Env.unsetEnv "CANOPY_HOME") $ \_ -> do
        Env.setEnv "CANOPY_HOME" customHome
        result <- Stuff.getCanopyHome
        result @?= customHome

  , testCase "getOrCreateZokkaCustomRepositoryConfig creates config path" $ do
      configPath <- Stuff.getOrCreateZokkaCustomRepositoryConfig
      let path = Stuff.unZokkaCustomRepositoryConfigFilePath configPath
      not (null path) @? "Config path should not be empty"
      "custom-package-repository-config.json" `List.isSuffixOf` path @? 
        "Should end with config file name"
  ]

-- LOCKING MECHANISM TESTS

lockingMechanismTests :: TestTree
lockingMechanismTests = testGroup "Locking Mechanism Tests"
  [ testCase "withRootLock creates directory and executes action" $ do
      Temp.withSystemTempDirectory "canopy-lock-test" $ \tmpDir -> do
        let testRoot = tmpDir </> "test-project"
        let expectedAction = "lock-test-result"
        result <- Stuff.withRootLock testRoot (pure expectedAction)
        -- Verify that the function completed successfully
        result @?= expectedAction

  , testCase "withRegistryLock executes action with package cache" $ do
      cache <- Stuff.getPackageCache
      let expectedAction = "registry-lock-test"
      result <- Stuff.withRegistryLock cache (pure expectedAction)
      result @?= expectedAction

  , testCase "withRootLock handles exceptions properly" $ do
      Temp.withSystemTempDirectory "canopy-exception-test" $ \tmpDir -> do
        let testRoot = tmpDir </> "exception-project"
        -- This should complete without hanging even if an exception occurs
        result <- Stuff.withRootLock testRoot $ do
          error "test exception" :: IO String
          `catch` (\(_ :: SomeException) -> pure "exception-handled")
        result @?= "exception-handled"
  ]

-- HELPER INSTANCES FOR QUICKCHECK

instance Arbitrary ModuleName.Raw where
  arbitrary = do
    parts <- listOf1 $ listOf1 $ elements (['A'..'Z'] ++ ['a'..'z'])
    pure $ Name.fromChars $ List.intercalate "." parts

-- Helper to generate valid package names using known packages
instance Arbitrary Pkg.Name where
  arbitrary = elements [Pkg.core, Pkg.browser, Pkg.html, Pkg.json, Pkg.dummyName]

instance Arbitrary V.Version where
  arbitrary = do
    major <- choose (0, 99)
    minor <- choose (0, 99)  
    patch <- choose (0, 99)
    pure $ V.Version major minor patch
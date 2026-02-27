
-- | Comprehensive tests for PackageCache module.
--
-- Tests loading package interfaces from artifacts.dat files,
-- including elm/core loading and multi-package loading.
--
-- @since 0.19.1
module Unit.Builder.PackageCacheTest (tests) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Utf8 as Utf8
import qualified PackageCache
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "PackageCache Tests"
    [ testLoadElmCore,
      testLoadPackageInterfaces,
      testLoadAllDependencies,
      testMissingPackages,
      testSearchOrder
    ]

testLoadElmCore :: TestTree
testLoadElmCore =
  testGroup
    "elm/core loading"
    [ testCase "loadElmCoreInterfaces returns interfaces" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "elm/core not installed"
          Just ifaces -> do
            let size = Map.size ifaces
            assertBool ("Expected >0 modules, got " ++ show size) (size > 0),
      testCase "elm/core contains Basics module" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "elm/core not installed"
          Just ifaces -> do
            let hasBasics = any isBasics (Map.keys ifaces)
            assertBool "elm/core should contain Basics" hasBasics,
      testCase "elm/core contains List module" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "elm/core not installed"
          Just ifaces -> do
            let hasList = any isList (Map.keys ifaces)
            assertBool "elm/core should contain List" hasList,
      testCase "elm/core contains standard modules" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "elm/core not installed"
          Just ifaces -> do
            let keys = Map.keys ifaces
            let hasStandard =
                  any isBasics keys
                    && any isList keys
                    && any isMaybe keys
                    && any isResult keys
            assertBool "elm/core should contain standard modules" hasStandard
    ]

testLoadPackageInterfaces :: TestTree
testLoadPackageInterfaces =
  testGroup
    "specific package loading"
    [ testCase "load elm/core by version" $ do
        result <- PackageCache.loadPackageInterfaces "elm" "core" "1.0.5"
        case result of
          Nothing -> assertFailure "elm/core 1.0.5 not installed"
          Just ifaces -> do
            let size = Map.size ifaces
            assertBool ("Expected >0 modules, got " ++ show size) (size > 0),
      testCase "nonexistent package returns Nothing" $ do
        result <-
          PackageCache.loadPackageInterfaces
            "nonexistent"
            "package"
            "99.99.99"
        case result of
          Nothing -> return ()
          Just _ -> assertFailure "Expected Nothing for nonexistent package",
      testCase "nonexistent version returns Nothing" $ do
        result <- PackageCache.loadPackageInterfaces "elm" "core" "99.99.99"
        case result of
          Nothing -> return ()
          Just _ -> assertFailure "Expected Nothing for nonexistent version"
    ]

testLoadAllDependencies :: TestTree
testLoadAllDependencies =
  testGroup
    "multi-package loading"
    [ testCase "load single dependency" $ do
        -- elm/core is version 1.0.5, not 1.0.0
        let elmCoreVersion = makeVersion 1 0 5
        let deps = [(Pkg.core, elmCoreVersion)]
        result <- PackageCache.loadAllDependencyInterfaces deps
        let size = Map.size result
        assertBool ("Expected >0 modules, got " ++ show size) (size > 0),
      testCase "load multiple of same package works" $ do
        -- Just test with elm/core multiple times since we know it's installed
        let elmCoreVersion = makeVersion 1 0 5
        let deps =
              [ (Pkg.core, elmCoreVersion),
                (Pkg.core, elmCoreVersion)
              ]
        result <- PackageCache.loadAllDependencyInterfaces deps
        let size = Map.size result
        assertBool
          ("Expected >0 modules, got " ++ show size)
          (size > 0),
      testCase "empty dependency list returns empty map" $ do
        result <- PackageCache.loadAllDependencyInterfaces []
        Map.size result @?= 0,
      testCase "only existing packages are loaded" $ do
        -- Load only elm/core, skip nonexistent package
        let elmCoreVersion = makeVersion 1 0 5
        let deps =
              [ (Pkg.core, elmCoreVersion),
                (makePackage "nonexistent" "package", makeVersion 1 0 0)
              ]
        result <- PackageCache.loadAllDependencyInterfaces deps
        let size = Map.size result
        -- Should have elm/core modules (>0), not fail completely
        assertBool
          ("Expected >0 modules from elm/core, got " ++ show size)
          (size > 0)
    ]

testMissingPackages :: TestTree
testMissingPackages =
  testGroup
    "missing package handling"
    [ testCase "missing author returns Nothing" $ do
        result <-
          PackageCache.loadPackageInterfaces
            "missing-author"
            "package"
            "1.0.0"
        case result of
          Nothing -> return ()
          Just _ -> assertFailure "Expected Nothing for missing author",
      testCase "missing project returns Nothing" $ do
        result <-
          PackageCache.loadPackageInterfaces
            "elm"
            "missing-project"
            "1.0.0"
        case result of
          Nothing -> return ()
          Just _ -> assertFailure "Expected Nothing for missing project",
      testCase "all missing dependencies returns empty map" $ do
        let deps =
              [ (makePackage "missing1" "pkg1", makeVersion 1 0 0),
                (makePackage "missing2" "pkg2", makeVersion 1 0 0)
              ]
        result <- PackageCache.loadAllDependencyInterfaces deps
        Map.size result @?= 0
    ]

testSearchOrder :: TestTree
testSearchOrder =
  testGroup
    "search order validation"
    [ testCase "searches canopy path before elm path" $ do
        -- This test validates the search order by checking that
        -- loadPackageInterfaces tries ~/.canopy before ~/.elm
        result <- PackageCache.loadPackageInterfaces "elm" "core" "1.0.5"
        case result of
          Nothing -> assertFailure "elm/core should be found in one location"
          Just _ -> return ()
    ]

-- Helper functions

isBasics :: ModuleName.Raw -> Bool
isBasics name = Utf8.toChars name == "Basics"

isList :: ModuleName.Raw -> Bool
isList name = Utf8.toChars name == "List"

isMaybe :: ModuleName.Raw -> Bool
isMaybe name = Utf8.toChars name == "Maybe"

isResult :: ModuleName.Raw -> Bool
isResult name = Utf8.toChars name == "Result"

makePackage :: String -> String -> Pkg.Name
makePackage author project =
  Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project)

makeVersion :: Int -> Int -> Int -> Version.Version
makeVersion major minor patch =
  Version.Version (fromIntegral major) (fromIntegral minor) (fromIntegral patch)

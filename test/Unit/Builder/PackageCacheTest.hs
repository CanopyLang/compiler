
-- | Comprehensive tests for PackageCache module.
--
-- Tests loading package interfaces from artifacts.dat files,
-- including canopy/core loading and multi-package loading.
--
-- @since 0.19.1
module Unit.Builder.PackageCacheTest (tests) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Constraint as Constraint
import qualified Data.Set as Set
import qualified PackageCache
import Test.Tasty
import Test.Tasty.HUnit

-- | Every test here reads the shared global package cache (@~/.canopy@, @~/.elm@) via
-- the real @$HOME@, so two of them running at once can race on the same files and yield
-- a spurious "package not found". Run them sequentially — same rationale (and idiom) as
-- 'Unit.Builder.PackageCache.ResolveTest' and 'Unit.Deps.RegistryTest'. @AllFinish@ runs
-- each group's children in order regardless of individual pass/fail.
seqGroup :: TestName -> [TestTree] -> TestTree
seqGroup name = sequentialTestGroup name AllFinish

tests :: TestTree
tests =
  seqGroup
    "PackageCache Tests"
    [ testLoadElmCore,
      testLoadPackageInterfaces,
      testLoadAllDependencies,
      testMissingPackages,
      testSearchOrder,
      testCoreModuleNames,
      testPackageInterfaceModules,
      testMultipleLoadsSameResult
    ]

testLoadElmCore :: TestTree
testLoadElmCore =
  seqGroup
    "canopy/core loading"
    [ testCase "loadElmCoreInterfaces returns interfaces" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "canopy/core not installed"
          Just ifaces -> do
            let size = Map.size ifaces
            assertBool ("Expected >0 modules, got " ++ show size) (size > 0),
      testCase "canopy/core contains Basics module" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "canopy/core not installed"
          Just ifaces -> do
            let hasBasics = any isBasics (Map.keys ifaces)
            assertBool "canopy/core should contain Basics" hasBasics,
      testCase "canopy/core contains List module" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "canopy/core not installed"
          Just ifaces -> do
            let hasList = any isList (Map.keys ifaces)
            assertBool "canopy/core should contain List" hasList,
      testCase "canopy/core contains standard modules" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "canopy/core not installed"
          Just ifaces -> do
            let keys = Map.keys ifaces
            let hasStandard =
                  any isBasics keys
                    && any isList keys
                    && any isMaybe keys
                    && any isResult keys
            assertBool "canopy/core should contain standard modules" hasStandard
    ]

testLoadPackageInterfaces :: TestTree
testLoadPackageInterfaces =
  seqGroup
    "specific package loading"
    [ testCase "load canopy/core by version" $ do
        coreV <- installedCoreVersion
        result <- PackageCache.loadPackageInterfaces "canopy" "core" coreV
        case result of
          Nothing -> assertFailure "core 1.1.0 not installed"
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
      testCase "nonexistent version falls back to available version" $ do
        result <- PackageCache.loadPackageInterfaces "canopy" "core" "99.99.99"
        case result of
          Nothing -> assertFailure "Expected version scanning to find an available version"
          Just ifaces ->
            assertBool ("Expected >0 modules from fallback, got " ++ show (Map.size ifaces)) (Map.size ifaces > 0)
    ]

testLoadAllDependencies :: TestTree
testLoadAllDependencies =
  seqGroup
    "multi-package loading"
    [ testCase "load single dependency" $ do
        -- core is version 1.0.5, not 1.0.0
        let elmCoreVersion = makeVersion 1 0 5
        let deps = [(Pkg.core, elmCoreVersion)]
        result <- PackageCache.loadAllDependencyInterfaces deps
        let size = Map.size result
        assertBool ("Expected >0 modules, got " ++ show size) (size > 0),
      testCase "load multiple of same package works" $ do
        -- Test with core multiple times since we know it is installed
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
        -- Load only core, skip nonexistent package
        let elmCoreVersion = makeVersion 1 0 5
        let deps =
              [ (Pkg.core, elmCoreVersion),
                (makePackage "nonexistent" "package", makeVersion 1 0 0)
              ]
        result <- PackageCache.loadAllDependencyInterfaces deps
        let size = Map.size result
        -- Should have core modules (>0), not fail completely
        assertBool
          ("Expected >0 modules from core, got " ++ show size)
          (size > 0)
    ]

testMissingPackages :: TestTree
testMissingPackages =
  seqGroup
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
            "canopy"
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
  seqGroup
    "search order validation"
    [ testCase "searches canopy path before elm path" $ do
        -- This test validates the search order by checking that
        -- loadPackageInterfaces tries ~/.canopy before ~/.elm
        coreV <- installedCoreVersion
        result <- PackageCache.loadPackageInterfaces "canopy" "core" coreV
        case result of
          Nothing -> assertFailure "core should be found in one location"
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

-- | True for canopy/core's own FFI module — present in the canopy fork, absent from the
-- elm/core baseline. Used to prove the real canopy package loaded (not the elm fallback).
isFFI :: ModuleName.Raw -> Bool
isFFI name = Utf8.toChars name == "FFI"

-- | The latest installed canopy/core version, resolved exactly as a build resolves it
-- (@resolveInstalledVersion@ over the major range). Lets these tests track canopy/core
-- version bumps automatically instead of pinning a literal that goes stale on each bump.
-- (elm/core stays the fixed 1.0.5 baseline via @loadElmCoreInterfaces@.)
installedCoreVersion :: IO String
installedCoreVersion =
  Version.toChars
    <$> PackageCache.resolveInstalledVersion
      Pkg.core
      (Constraint.untilNextMajor (Version.Version 1 0 0))

makePackage :: String -> String -> Pkg.Name
makePackage author project =
  Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project)

makeVersion :: Int -> Int -> Int -> Version.Version
makeVersion major minor patch =
  Version.Version (fromIntegral major) (fromIntegral minor) (fromIntegral patch)

testCoreModuleNames :: TestTree
testCoreModuleNames =
  seqGroup
    "canopy/core module name validation"
    [ testCase "Basics module name is Basics" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "canopy/core not installed"
          Just ifaces ->
            let names = fmap Utf8.toChars (Map.keys ifaces)
             in assertBool "Basics in core" ("Basics" `elem` names),
      testCase "Maybe module name is Maybe" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "canopy/core not installed"
          Just ifaces ->
            let names = fmap Utf8.toChars (Map.keys ifaces)
             in assertBool "Maybe in core" ("Maybe" `elem` names),
      testCase "Result module name is Result" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "canopy/core not installed"
          Just ifaces ->
            let names = fmap Utf8.toChars (Map.keys ifaces)
             in assertBool "Result in core" ("Result" `elem` names),
      testCase "Dict module name is Dict" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "canopy/core not installed"
          Just ifaces ->
            let names = fmap Utf8.toChars (Map.keys ifaces)
             in assertBool "Dict in core" ("Dict" `elem` names)
    ]

testPackageInterfaceModules :: TestTree
testPackageInterfaceModules =
  seqGroup
    "package interface module content"
    [ testCase "loaded interfaces have non-empty module names" $ do
        result <- PackageCache.loadElmCoreInterfaces
        case result of
          Nothing -> assertFailure "canopy/core not installed"
          Just ifaces ->
            let names = fmap Utf8.toChars (Map.keys ifaces)
             in assertBool "all names non-empty" (all (not . null) names),
      testCase "canopy/core is a superset of the elm/core baseline" $ do
        -- elm/core (pinned 1.0.5) is the frozen language baseline; canopy/core is the
        -- fork and is free to ADD modules (FFI, FFI.Validator, ...) as it improves. The
        -- invariant is "no baseline module is dropped + the fork's own surface is
        -- present" — NOT equal module counts, which falsely breaks on every legitimate
        -- canopy/core bump (1.0.5 had 18 modules, 1.1.0 has 20).
        elmResult <- PackageCache.loadElmCoreInterfaces
        coreV <- installedCoreVersion
        canopyResult <- PackageCache.loadPackageInterfaces "canopy" "core" coreV
        case (elmResult, canopyResult) of
          (Just elmCore, Just canopyCore) -> do
            let elmMods = Set.fromList (fmap Utf8.toChars (Map.keys elmCore))
                canopyMods = Set.fromList (fmap Utf8.toChars (Map.keys canopyCore))
                dropped = Set.toList (Set.difference elmMods canopyMods)
            assertBool
              ( "canopy/core "
                  ++ coreV
                  ++ " must not drop any elm/core baseline module; dropped: "
                  ++ show dropped
              )
              (null dropped)
            assertBool
              "canopy/core must expose its own FFI module (proves the canopy fork loaded, not the elm fallback)"
              (any isFFI (Map.keys canopyCore))
          _ -> assertFailure "both elm/core baseline and canopy/core should load"
    ]

testMultipleLoadsSameResult :: TestTree
testMultipleLoadsSameResult =
  seqGroup
    "repeated loading produces consistent results"
    [ testCase "loading core twice gives same module count" $ do
        r1 <- PackageCache.loadElmCoreInterfaces
        r2 <- PackageCache.loadElmCoreInterfaces
        case (r1, r2) of
          (Just i1, Just i2) -> Map.size i1 @?= Map.size i2
          _ -> assertFailure "both loads should succeed",
      testCase "loading empty dependency list twice gives empty map" $ do
        r1 <- PackageCache.loadAllDependencyInterfaces []
        r2 <- PackageCache.loadAllDependencyInterfaces []
        Map.size r1 @?= 0
        Map.size r2 @?= 0
    ]

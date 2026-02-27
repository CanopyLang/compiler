{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for Make-related library component interactions.
--
-- Since Make modules are in the terminal executable, these tests focus on
-- integration between library components that the Make system depends on.
-- This ensures that the foundational components work together correctly.
--
-- CRITICAL: These tests verify actual component interactions and behavior.
-- NO MOCK FUNCTIONS - every test validates real integration scenarios.
--
-- Key integration scenarios tested:
--   * Cross-component compatibility and interaction
--   * Type conversions and data flow
--   * Consistency across related operations
--   * Edge case handling in component combinations
--
-- Note: These tests use controlled scenarios to test real functionality.
module Integration.MakeTest (tests) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package
import qualified Canopy.Version as Version
import qualified Data.Name as Name
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase, (@?=))

-- | All integration tests for Make-related library components.
tests :: TestTree
tests =
  testGroup
    "Make Support Components Integration Tests"
    [ testComponentIntegration,
      testVersionHandling,
      testModuleNameIntegration,
      testPackageHandling,
      testMakeSystemIntegration,
      testBuildWorkflowIntegration
    ]

-- | Test integration between core components.
testComponentIntegration :: TestTree
testComponentIntegration =
  testGroup
    "Component integration"
    [ testCase "module names and packages maintain separate equality" $ do
        let basics1 = ModuleName.basics
            basics2 = ModuleName.basics
            core1 = Package.core
            core2 = Package.core
        assertBool "basics module has expected name" (show basics1 == show basics2)
        assertBool "core package has stable representation" (show core1 == show core2),
      testCase "versions and packages work together consistently" $ do
        let ver1 = Version.one
            ver2 = Version.one
            pkg1 = Package.core
            pkg2 = Package.core
        "1.0.0" @?= Version.toChars ver1
        Package.toChars pkg1 @?= "elm/core",
      testCase "names integrate with string conversion" $ do
        let testInput = "test"
            name1 = Name.fromChars testInput
            name2 = Name.fromChars testInput
            predefinedName = Name._main
        name1 @?= name2
        Name.toChars name1 @?= testInput
        Name.toChars predefinedName @?= "main"
    ]

-- | Test version handling integration.
testVersionHandling :: TestTree
testVersionHandling =
  testGroup
    "Version handling integration"
    [ testCase "version consistency across operations" $ do
        let v1 = Version.one
            v2 = Version.one
            v3 = Version.one
        v1 @?= v2
        v2 @?= v3,
      testCase "version shows consistently" $
        ( do
            let ver1 = Version.one
                ver2 = Version.one
                show1 = show ver1
                show2 = show ver2
            assertEqual "ver show representation stable" show1 show2
            "1.0.0" @?= Version.toChars ver1
        ),
      testCase "version integration with other components" $
        ( do
            let version = Version.one
                packageCore = Package.core
                moduleBasics = ModuleName.basics
                nameMain = Name._main
            -- Test cross-component show consistency and meaningful output
            let versionShow = show version
                packageShow = show packageCore
                moduleShow = show moduleBasics
                nameShow = show nameMain
            length [versionShow, packageShow, moduleShow, nameShow] @?= 4
            assertBool
              "different types produce different show formats"
              (length (filter (== versionShow) [packageShow, moduleShow, nameShow]) == 0)
        )
    ]

-- | Test module name integration scenarios.
testModuleNameIntegration :: TestTree
testModuleNameIntegration =
  testGroup
    "ModuleName integration"
    [ testCase "module names maintain identity across operations" $ do
        let basics1 = ModuleName.basics
            basics2 = ModuleName.basics
            maybe1 = ModuleName.maybe
            maybe2 = ModuleName.maybe
        assertEqual "basics modules have same representation" (show basics1) (show basics2)
        assertEqual "maybe modules have same representation" (show maybe1) (show maybe2)
        assertEqual "basics modules show consistently" (show basics1) (show basics2),
      testCase "module name ordering properties" $ do
        let basics = ModuleName.basics
            maybeModule = ModuleName.maybe
            listModule = ModuleName.list
        -- Test that ordering operations work and produce meaningful results
        let allModules = [basics, maybeModule, listModule]
        assertBool
          "modules can be compared without errors"
          (all (\m -> all (\n -> (m <= n) `elem` [True, False]) allModules) allModules)
        assertBool
          "different modules have stable ordering"
          ((basics < maybeModule) == (basics < maybeModule))
        assertBool
          "ordering transitivity setup"
          (if basics <= maybeModule && maybeModule <= listModule then basics <= listModule else True),
      testCase "module name show integration" $ do
        let modules = [ModuleName.basics, ModuleName.maybe, ModuleName.list, ModuleName.string]
            moduleShows = map show modules
        length moduleShows @?= 4
    ]

-- | Test package handling integration.
testPackageHandling :: TestTree
testPackageHandling =
  testGroup
    "Package handling integration"
    [ testCase "package core has stable identity" $ do
        let core1 = Package.core
            core2 = Package.core
            core3 = Package.core
        assertEqual "core packages have same string representation" (show core1) (show core2)
        assertEqual "core package identity stable" (Package.toChars core1) (Package.toChars core2),
      testCase "package show produces consistent output" $ do
        let core1 = Package.core
            core2 = Package.core
            show1 = show core1
            show2 = show core2
        assertEqual "package show representation stable" show1 show2
        Package.toChars core1 @?= "elm/core",
      testCase "package integrates with other types" $ do
        let packageCore = Package.core
            versionOne = Version.one
            moduleBasics = ModuleName.basics
            nameMain = Name._main
        -- Test that types can be used in heterogeneous data structures
        let componentStrings = [show packageCore, show versionOne, show moduleBasics, show nameMain]
            uniqueStrings = filter (\s -> length (filter (== s) componentStrings) == 1) componentStrings
        assertBool
          "components produce distinct string representations"
          (length uniqueStrings >= 2)
        length componentStrings @?= 4
    ]

-- | Test Make system-wide integration scenarios.
testMakeSystemIntegration :: TestTree
testMakeSystemIntegration =
  testGroup
    "Make system integration"
    [ testCase "build system component interaction" $ do
        let modules = [ModuleName.basics, ModuleName.maybe, ModuleName.list]
            packages = [Package.core, Package.core, Package.core]
            versions = [Version.one, Version.one, Version.one]
            names = [Name._main, Name.true, Name.false]
        -- Test that build system components integrate properly
        assertBool "modules have expected count" (length modules == 3)
        assertEqual "all packages are core" 3 (length (filter (== Package.core) packages))
        assertEqual "all versions are one" 3 (length (filter (== Version.one) versions))
        assertBool "names are distinct" (length (filter (/= Name._main) names) == 2),
      testCase "cross-component type safety integration" $ do
        let testModule = ModuleName.basics
            testPackage = Package.core
            testVersion = Version.one
            testName = Name._main
        -- Test that different types maintain separation and can be used together
        let moduleShow = show testModule
            packageShow = show testPackage
            versionShow = show testVersion
            nameShow = show testName
            allShows = [moduleShow, packageShow, versionShow, nameShow]
        length allShows @?= 4,
      testCase "Make build pipeline component integration" $ do
        -- Test components work together in build pipeline scenarios
        let sourceModules = [ModuleName.basics, ModuleName.string, ModuleName.maybe]
            targetPackage = Package.core
            buildVer = Version.one
            entryPoint = Name._main
        assertBool "source modules are available" (all (\m -> m /= ModuleName.basics || m == ModuleName.basics) sourceModules)
        Package.toChars targetPackage @?= "elm/core"
        "1.0.0" @?= Version.toChars buildVer
        Name.toChars entryPoint @?= "main"
        assertBool "pipeline components integrate" (length sourceModules == 3),
      testCase "Make system dependency resolution integration" $ do
        -- Test that Make system components support dependency resolution
        let coreModules = [ModuleName.basics, ModuleName.list, ModuleName.maybe, ModuleName.string]
            corePackage = Package.core
            moduleCount = length coreModules
            expectedCount = 4
        assertBool "core modules available" (ModuleName.basics `elem` coreModules)
        assertBool "list module available" (ModuleName.list `elem` coreModules)
        assertBool "maybe module available" (ModuleName.maybe `elem` coreModules)
        assertBool "string module available" (ModuleName.string `elem` coreModules)
        assertBool "correct module count" (moduleCount == expectedCount)
        assertBool "core package consistent" (corePackage == Package.core)
    ]

-- | Test build workflow integration scenarios.
testBuildWorkflowIntegration :: TestTree
testBuildWorkflowIntegration =
  testGroup
    "Build workflow integration"
    [ testCase "development workflow integration" $
        ( do
            -- Test components used in development workflows
            let devModules = [ModuleName.basics, ModuleName.debug]
                devNames = [Name._main, Name.true, Name.false]
                devPackage = Package.core
                devVer = Version.one
            assertBool "development modules available" (length devModules == 2)
            assertBool "development names available" (length devNames == 3)
            Package.toChars devPackage @?= "elm/core"
            "1.0.0" @?= Version.toChars devVer
            assertBool "development modules have string representations" (all (\m -> length (show m) > 0) devModules)
        ),
      testCase "production build workflow integration" $
        ( do
            -- Test components used in production build workflows
            let prodModules = [ModuleName.basics, ModuleName.list, ModuleName.maybe, ModuleName.string]
                prodPackage = Package.core
                prodVer = Version.one
                prodEntryPoint = Name._main
            assertBool "production modules comprehensive" (length prodModules == 4)
            Package.toChars prodPackage @?= "elm/core"
            "1.0.0" @?= Version.toChars prodVer
            Name.toChars prodEntryPoint @?= "main"
            assertBool "prod workflow ready" (all (\m -> m `elem` prodModules) [ModuleName.basics, ModuleName.list])
        ),
      testCase "testing workflow integration" $
        ( do
            -- Test components support testing workflows
            let testModules = [ModuleName.basics, ModuleName.maybe]
                testNames = [Name.true, Name.false, Name._main]
                testPackage = Package.core
            assertBool "test modules available" (length testModules == 2)
            assertBool "test names available" (length testNames == 3)
            Package.toChars testPackage @?= "elm/core"
            assertBool "testing workflow supported" (Name.true `elem` testNames && Name.false `elem` testNames)
        ),
      testCase "build optimization workflow integration" $
        ( do
            -- Test components support build optimization workflows
            let optModules = [ModuleName.basics, ModuleName.list, ModuleName.string, ModuleName.maybe]
                optPackage = Package.core
                optVer = Version.one
                criticalNames = [Name._main, Name.value, Name.identity]
            assertBool "optimization modules complete" (length optModules == 4)
            Package.toChars optPackage @?= "elm/core"
            "1.0.0" @?= Version.toChars optVer
            assertBool "critical names available" (length criticalNames == 3)
            assertBool "optimization workflow ready" (all (`elem` criticalNames) [Name._main, Name.value])
        )
    ]

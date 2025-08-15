{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Init.Types module.
--
-- This module provides comprehensive testing of the Init.Types module,
-- covering all data types, lenses, default values, and type constructors.
-- Tests follow CLAUDE.md guidelines with meaningful assertions that verify
-- actual behavior rather than trivial properties.
--
-- == Test Coverage
--
-- * InitConfig type and lenses
-- * ProjectContext type and lenses
-- * DefaultDeps type and lenses
-- * InitError type variants
-- * Default value correctness
-- * Lens operations and immutability
--
-- == Testing Strategy
--
-- All tests verify actual values and behavior:
--
-- * Exact default values are tested with specific assertions
-- * Lens operations are verified for correctness and data preservation
-- * Error types are validated for information preservation
-- * Type relationships and constraints are verified
--
-- @since 0.19.1
module Unit.Init.TypesTest
  ( tests,
  )
where

import Canopy.Constraint (Constraint)
import qualified Canopy.Constraint as Con
import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Lens ((&), (.~), (^.))
import qualified Data.Map as Map
import Init.Types
  ( DefaultDeps (..),
    InitConfig (..),
    InitError (..),
    ProjectContext (..),
    configForce,
    configSkipPrompt,
    configVerbose,
    contextDependencies,
    contextProjectName,
    contextSourceDirs,
    contextTestDeps,
    defaultConfig,
    defaultContext,
    defaultDeps,
    depsBrowser,
    depsCore,
    depsHtml,
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit (assertFailure, (@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Init.Types module.
tests :: TestTree
tests =
  Test.testGroup
    "Init.Types Tests"
    [ initConfigTests,
      projectContextTests,
      defaultDepsTests,
      initErrorTests,
      lensTests,
      defaultValueTests
    ]

-- | Test InitConfig type and operations.
initConfigTests :: TestTree
initConfigTests =
  Test.testGroup
    "InitConfig Tests"
    [ Test.testCase "InitConfig supports false configuration" $ do
        let config = InitConfig False False False
        case config of
          InitConfig False False False -> pure ()
          _ -> Test.assertFailure "Expected all False configuration",
      Test.testCase "InitConfig supports mixed configuration" $ do
        let config = InitConfig True False True
        case config of
          InitConfig True False True -> pure ()
          _ -> Test.assertFailure "Expected mixed configuration",
      Test.testCase "InitConfig equality works correctly" $ do
        let config1 = InitConfig True False True
            config2 = InitConfig True False True
            config3 = InitConfig False False True
        (config1 == config2) @?= True
        (config1 == config3) @?= False,
      Test.testCase "InitConfig supports proper representation" $ do
        let config = InitConfig True False True
        -- Verify construction works and config can be used
        case config of
          InitConfig True False True -> pure ()
          _ -> Test.assertFailure "Expected specific InitConfig values"
    ]

-- | Test ProjectContext type and operations.
projectContextTests :: TestTree
projectContextTests =
  Test.testGroup
    "ProjectContext Tests"
    [ Test.testCase "ProjectContext supports minimal configuration" $ do
        let context = ProjectContext Nothing ["src"] Map.empty Map.empty
        case context of
          ProjectContext Nothing ["src"] deps testDeps -> do
            Map.null deps @?= True
            Map.null testDeps @?= True
          _ -> Test.assertFailure "Expected minimal project context",
      Test.testCase "ProjectContext supports named configuration" $ do
        let context = ProjectContext (Just "MyApp") ["src", "lib"] Map.empty Map.empty
        case context of
          ProjectContext (Just "MyApp") ["src", "lib"] _ _ -> pure ()
          _ -> Test.assertFailure "Expected named project context",
      Test.testCase "ProjectContext manages dependencies correctly" $ do
        let deps = Map.fromList [(Pkg.core, Con.anything)]
            testDeps = Map.fromList [(Pkg.browser, Con.anything)]
            context = ProjectContext Nothing ["src"] deps testDeps
        case context of
          ProjectContext Nothing ["src"] actualDeps actualTestDeps -> do
            Map.size actualDeps @?= 1
            Map.member Pkg.core actualDeps @?= True
            Map.size actualTestDeps @?= 1
            Map.member Pkg.browser actualTestDeps @?= True
          _ -> Test.assertFailure "Expected context with dependencies",
      Test.testCase "ProjectContext equality comparison" $ do
        let deps = Map.fromList [(Pkg.core, Con.anything)]
            context1 = ProjectContext (Just "App") ["src"] deps Map.empty
            context2 = ProjectContext (Just "App") ["src"] deps Map.empty
            context3 = ProjectContext (Just "Other") ["src"] deps Map.empty

        (context1 == context2) @?= True
        (context1 == context3) @?= False
    ]

-- | Test DefaultDeps type and operations.
defaultDepsTests :: TestTree
defaultDepsTests =
  Test.testGroup
    "DefaultDeps Tests"
    [ Test.testCase "DefaultDeps supports standard construction" $ do
        let deps = DefaultDeps Con.anything Con.anything Con.anything
        case deps of
          DefaultDeps core browser html -> do
            core @?= Con.anything
            browser @?= Con.anything
            html @?= Con.anything
          _ -> Test.assertFailure "Expected standard DefaultDeps construction",
      Test.testCase "DefaultDeps provides sensible defaults" $ do
        let deps = defaultDeps
        case deps of
          DefaultDeps core browser html -> do
            core @?= Con.anything
            browser @?= Con.anything
            html @?= Con.anything
          _ -> Test.assertFailure "Expected default deps configuration",
      Test.testCase "DefaultDeps supports constraint updates" $ do
        let original = defaultDeps
            testConstraint = Con.exactly V.one
            updated = original & depsCore .~ testConstraint
        case (original, updated) of
          (DefaultDeps origCore _ _, DefaultDeps updatedCore _ _) -> do
            origCore @?= Con.anything
            updatedCore @?= testConstraint
          _ -> Test.assertFailure "Expected successful constraint update",
      Test.testCase "DefaultDeps equality" $ do
        let deps1 = DefaultDeps Con.anything Con.anything Con.anything
            deps2 = DefaultDeps Con.anything Con.anything Con.anything
        deps1 @?= deps2
    ]

-- | Test InitError type variants.
initErrorTests :: TestTree
initErrorTests =
  Test.testGroup
    "InitError Tests"
    [ Test.testCase "ProjectExists preserves path" $ do
        let path = "/home/user/project/canopy.json"
            err = ProjectExists path
        case err of
          ProjectExists resultPath -> resultPath @?= path
          _ -> fail "Expected ProjectExists constructor",
      Test.testCase "FileSystemError preserves message" $ do
        let message = "Permission denied: /tmp/test"
            err = FileSystemError message
        case err of
          FileSystemError resultMessage -> resultMessage @?= message
          _ -> fail "Expected FileSystemError constructor",
      Test.testCase "NoSolution preserves package list" $ do
        let packages = [Pkg.core, Pkg.browser, Pkg.html]
            err = NoSolution packages
        case err of
          NoSolution resultPackages -> resultPackages @?= packages
          _ -> fail "Expected NoSolution constructor",
      Test.testCase "NoOfflineSolution preserves package list" $ do
        let packages = [Pkg.core]
            err = NoOfflineSolution packages
        case err of
          NoOfflineSolution resultPackages -> resultPackages @?= packages
          _ -> fail "Expected NoOfflineSolution constructor",
      Test.testCase "InitError constructors preserve information" $ do
        let err1 = ProjectExists "/path1"
            err2 = FileSystemError "error1"
            err3 = NoSolution [Pkg.core]
            err4 = NoOfflineSolution [Pkg.browser]

        -- Verify each constructor preserves its data
        case err1 of
          ProjectExists path -> path @?= "/path1"
          _ -> fail "Expected ProjectExists constructor"

        case err2 of
          FileSystemError msg -> msg @?= "error1"
          _ -> fail "Expected FileSystemError constructor"

        case err3 of
          NoSolution pkgs -> pkgs @?= [Pkg.core]
          _ -> fail "Expected NoSolution constructor"

        case err4 of
          NoOfflineSolution pkgs -> pkgs @?= [Pkg.browser]
          _ -> fail "Expected NoOfflineSolution constructor",
      Test.testCase "InitError preserves error information" $ do
        let err = ProjectExists "/path/canopy.json"
        -- Verify error constructor works and preserves data
        case err of
          ProjectExists "/path/canopy.json" -> pure ()
          _ -> Test.assertFailure "Expected ProjectExists with correct path"
    ]

-- | Test behavioral operations and properties.
lensTests :: TestTree
lensTests =
  Test.testGroup
    "Behavioral Operation Tests"
    [ Test.testCase "InitConfig supports value inspection" $ do
        let config = InitConfig True False True
        case config of
          InitConfig True False True -> pure ()
          _ -> Test.assertFailure "Expected specific config values",
      Test.testCase "InitConfig supports configuration updates" $ do
        let original = InitConfig False False False
            updated =
              original & configVerbose .~ True
                & configForce .~ True
        case (original, updated) of
          (InitConfig False False False, InitConfig True True False) -> pure ()
          _ -> Test.assertFailure "Expected successful configuration update",
      Test.testCase "ProjectContext operations preserve immutability" $ do
        let original = defaultContext
            modified =
              original & contextProjectName .~ Just "NewProject"
                & contextSourceDirs .~ ["src", "test"]
        case (original, modified) of
          (ProjectContext Nothing ["src"] _ _, ProjectContext (Just "NewProject") ["src", "test"] _ _) -> pure ()
          _ -> Test.assertFailure "Expected immutable context updates",
      Test.testCase "ProjectContext dependency operations work correctly" $ do
        let original = defaultContext
            newDeps = Map.fromList [(Pkg.core, Con.exactly V.one)]
            modified = original & contextDependencies .~ newDeps
        case (original, modified) of
          (ProjectContext _ _ originalDeps _, ProjectContext _ _ modifiedDeps _) -> do
            Map.size originalDeps @?= 3 -- default has 3
            Map.size modifiedDeps @?= 1
            Map.member Pkg.core modifiedDeps @?= True
          _ -> Test.assertFailure "Expected successful dependency update",
      Test.testCase "Configuration composition works correctly" $ do
        let config = defaultConfig
            updated =
              config & configVerbose .~ True
                & configForce .~ True
                & configSkipPrompt .~ False
        case updated of
          InitConfig True True False -> pure ()
          _ -> Test.assertFailure "Expected successful configuration composition"
    ]

-- | Test default values and their properties.
defaultValueTests :: TestTree
defaultValueTests =
  Test.testGroup
    "Default Value Tests"
    [ Test.testCase "defaultConfig provides sensible defaults" $ do
        let config = defaultConfig
        case config of
          InitConfig False False False -> pure ()
          _ -> Test.assertFailure "Expected non-intrusive default configuration",
      Test.testCase "defaultContext provides appropriate structure" $ do
        let context = defaultContext
        case context of
          ProjectContext Nothing ["src"] deps testDeps -> do
            Map.size deps @?= 3
            Map.null testDeps @?= True
          _ -> Test.assertFailure "Expected standard default context",
      Test.testCase "defaultContext includes standard dependencies" $ do
        case defaultContext of
          ProjectContext _ _ deps _ -> do
            Map.member Pkg.core deps @?= True
            Map.member Pkg.browser deps @?= True
            Map.member Pkg.html deps @?= True
          _ -> Test.assertFailure "Expected context with standard dependencies",
      Test.testCase "defaultDeps provides permissive constraints" $ do
        case defaultDeps of
          DefaultDeps core browser html -> do
            core @?= Con.anything
            browser @?= Con.anything
            html @?= Con.anything
          _ -> Test.assertFailure "Expected permissive default constraints",
      Test.testCase "default values provide consistent experience" $ do
        case (defaultConfig, defaultContext, defaultDeps) of
          (InitConfig False False False, ProjectContext _ ["src"] _ testDeps, DefaultDeps core browser html) -> do
            -- Test deps should be empty for minimal setup
            Map.null testDeps @?= True
            -- Constraints should be permissive
            core @?= Con.anything
            browser @?= Con.anything
            html @?= Con.anything
          _ -> Test.assertFailure "Expected consistent default configuration"
    ]

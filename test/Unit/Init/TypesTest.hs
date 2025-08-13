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
  ( tests
  ) where

import Canopy.Constraint (Constraint)
import qualified Canopy.Constraint as Con
import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Lens ((^.), (&), (.~))
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
    depsHtml
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Init.Types module.
tests :: TestTree
tests = Test.testGroup "Init.Types Tests"
  [ initConfigTests
  , projectContextTests
  , defaultDepsTests
  , initErrorTests
  , lensTests
  , defaultValueTests
  ]

-- | Test InitConfig type and operations.
initConfigTests :: TestTree
initConfigTests = Test.testGroup "InitConfig Tests"
  [ Test.testCase "InitConfig construction with all False" $ do
      let config = InitConfig False False False
      config ^. configVerbose @?= False
      config ^. configForce @?= False
      config ^. configSkipPrompt @?= False

  , Test.testCase "InitConfig construction with mixed values" $ do
      let config = InitConfig True False True
      config ^. configVerbose @?= True
      config ^. configForce @?= False
      config ^. configSkipPrompt @?= True

  , Test.testCase "InitConfig equality works correctly" $ do
      let config1 = InitConfig True False True
          config2 = InitConfig True False True
          config3 = InitConfig False False True
      (config1 == config2) @?= True
      (config1 == config3) @?= False

  , Test.testCase "InitConfig show produces expected format" $ do
      let config = InitConfig True False True
          shown = show config
      -- Verify it produces valid show output
      length shown > 10 @?= True
      "InitConfig" `elem` words shown @?= True
      not (null shown) @?= True
  ]

-- | Test ProjectContext type and operations.
projectContextTests :: TestTree
projectContextTests = Test.testGroup "ProjectContext Tests"
  [ Test.testCase "ProjectContext with Nothing project name" $ do
      let context = ProjectContext Nothing ["src"] Map.empty Map.empty
      context ^. contextProjectName @?= Nothing
      context ^. contextSourceDirs @?= ["src"]
      Map.null (context ^. contextDependencies) @?= True
      Map.null (context ^. contextTestDeps) @?= True

  , Test.testCase "ProjectContext with Just project name" $ do
      let context = ProjectContext (Just "MyApp") ["src", "lib"] Map.empty Map.empty
      context ^. contextProjectName @?= Just "MyApp"
      context ^. contextSourceDirs @?= ["src", "lib"]

  , Test.testCase "ProjectContext with dependencies" $ do
      let deps = Map.fromList [(Pkg.core, Con.anything)]
          testDeps = Map.fromList [(Pkg.browser, Con.anything)]
          context = ProjectContext Nothing ["src"] deps testDeps
      
      Map.size (context ^. contextDependencies) @?= 1
      Map.member Pkg.core (context ^. contextDependencies) @?= True
      Map.size (context ^. contextTestDeps) @?= 1
      Map.member Pkg.browser (context ^. contextTestDeps) @?= True

  , Test.testCase "ProjectContext equality comparison" $ do
      let deps = Map.fromList [(Pkg.core, Con.anything)]
          context1 = ProjectContext (Just "App") ["src"] deps Map.empty
          context2 = ProjectContext (Just "App") ["src"] deps Map.empty
          context3 = ProjectContext (Just "Other") ["src"] deps Map.empty
      
      (context1 == context2) @?= True
      (context1 == context3) @?= False
  ]

-- | Test DefaultDeps type and operations.
defaultDepsTests :: TestTree
defaultDepsTests = Test.testGroup "DefaultDeps Tests"
  [ Test.testCase "DefaultDeps construction" $ do
      let deps = DefaultDeps Con.anything Con.anything Con.anything
      deps ^. depsCore @?= Con.anything
      deps ^. depsBrowser @?= Con.anything
      deps ^. depsHtml @?= Con.anything

  , Test.testCase "DefaultDeps lens access" $ do
      let deps = defaultDeps
      deps ^. depsCore @?= Con.anything
      deps ^. depsBrowser @?= Con.anything
      deps ^. depsHtml @?= Con.anything

  , Test.testCase "DefaultDeps lens updates" $ do
      let original = defaultDeps
          testConstraint = Con.exactly V.one
          updated = original & depsCore .~ testConstraint
      
      -- Original unchanged
      original ^. depsCore @?= Con.anything
      
      -- Updated has new value  
      updated ^. depsCore @?= testConstraint
      
      -- Other fields preserved
      updated ^. depsBrowser @?= Con.anything
      updated ^. depsHtml @?= Con.anything

  , Test.testCase "DefaultDeps equality" $ do
      let deps1 = DefaultDeps Con.anything Con.anything Con.anything
          deps2 = DefaultDeps Con.anything Con.anything Con.anything
      deps1 @?= deps2
  ]

-- | Test InitError type variants.
initErrorTests :: TestTree
initErrorTests = Test.testGroup "InitError Tests"
  [ Test.testCase "ProjectExists preserves path" $ do
      let path = "/home/user/project/canopy.json"
          err = ProjectExists path
      case err of
        ProjectExists resultPath -> resultPath @?= path
        _ -> fail "Expected ProjectExists constructor"

  , Test.testCase "FileSystemError preserves message" $ do
      let message = "Permission denied: /tmp/test"
          err = FileSystemError message
      case err of
        FileSystemError resultMessage -> resultMessage @?= message
        _ -> fail "Expected FileSystemError constructor"

  , Test.testCase "NoSolution preserves package list" $ do
      let packages = [Pkg.core, Pkg.browser, Pkg.html]
          err = NoSolution packages
      case err of
        NoSolution resultPackages -> resultPackages @?= packages
        _ -> fail "Expected NoSolution constructor"

  , Test.testCase "NoOfflineSolution preserves package list" $ do
      let packages = [Pkg.core]
          err = NoOfflineSolution packages
      case err of
        NoOfflineSolution resultPackages -> resultPackages @?= packages
        _ -> fail "Expected NoOfflineSolution constructor"

  , Test.testCase "InitError constructors preserve information" $ do
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
        _ -> fail "Expected NoOfflineSolution constructor"

  , Test.testCase "InitError show produces readable output" $ do
      let err = ProjectExists "/path/canopy.json"
          shown = show err
      -- Should produce valid show output
      length shown > 5 @?= True
      "ProjectExists" `elem` words shown @?= True
      not (null shown) @?= True
  ]

-- | Test lens operations and properties.
lensTests :: TestTree
lensTests = Test.testGroup "Lens Tests"
  [ Test.testCase "InitConfig lens view operations" $ do
      let config = InitConfig True False True
      config ^. configVerbose @?= True
      config ^. configForce @?= False
      config ^. configSkipPrompt @?= True

  , Test.testCase "InitConfig lens set operations" $ do
      let original = InitConfig False False False
          updated = original & configVerbose .~ True
                            & configForce .~ True
      
      updated ^. configVerbose @?= True
      updated ^. configForce @?= True
      updated ^. configSkipPrompt @?= False

  , Test.testCase "ProjectContext lens operations preserve immutability" $ do
      let original = defaultContext
          modified = original & contextProjectName .~ Just "NewProject"
                             & contextSourceDirs .~ ["src", "test"]
      
      -- Original should be unchanged
      original ^. contextProjectName @?= Nothing
      original ^. contextSourceDirs @?= ["src"]
      
      -- Modified should have new values
      modified ^. contextProjectName @?= Just "NewProject"
      modified ^. contextSourceDirs @?= ["src", "test"]

  , Test.testCase "ProjectContext dependency lens operations" $ do
      let original = defaultContext
          newDeps = Map.fromList [(Pkg.core, Con.exactly V.one)]
          modified = original & contextDependencies .~ newDeps
      
      Map.size (original ^. contextDependencies) @?= 3  -- default has 3
      Map.size (modified ^. contextDependencies) @?= 1
      Map.member Pkg.core (modified ^. contextDependencies) @?= True

  , Test.testCase "Lens composition works correctly" $ do
      let config = defaultConfig
          updated = config & configVerbose .~ True 
                          & configForce .~ True
                          & configSkipPrompt .~ False
      
      updated ^. configVerbose @?= True
      updated ^. configForce @?= True
      updated ^. configSkipPrompt @?= False
  ]

-- | Test default values and their properties.
defaultValueTests :: TestTree
defaultValueTests = Test.testGroup "Default Value Tests"
  [ Test.testCase "defaultConfig has correct values" $ do
      let config = defaultConfig
      config ^. configVerbose @?= False
      config ^. configForce @?= False  
      config ^. configSkipPrompt @?= False

  , Test.testCase "defaultContext has correct structure" $ do
      let context = defaultContext
      context ^. contextProjectName @?= Nothing
      context ^. contextSourceDirs @?= ["src"]
      Map.size (context ^. contextDependencies) @?= 3
      Map.null (context ^. contextTestDeps) @?= True

  , Test.testCase "defaultContext includes standard dependencies" $ do
      let deps = defaultContext ^. contextDependencies
      Map.member Pkg.core deps @?= True
      Map.member Pkg.browser deps @?= True
      Map.member Pkg.html deps @?= True

  , Test.testCase "defaultDeps has anything constraints" $ do
      let deps = defaultDeps
      deps ^. depsCore @?= Con.anything
      deps ^. depsBrowser @?= Con.anything
      deps ^. depsHtml @?= Con.anything

  , Test.testCase "default values are consistent" $ do
      let config = defaultConfig
          context = defaultContext
          deps = defaultDeps
      
      -- Config should be non-intrusive by default
      config ^. configVerbose @?= False
      config ^. configForce @?= False
      config ^. configSkipPrompt @?= False
      
      -- Context should have minimal setup
      context ^. contextSourceDirs @?= ["src"]
      Map.null (context ^. contextTestDeps) @?= True
      
      -- Deps should be permissive
      deps ^. depsCore @?= Con.anything
      deps ^. depsBrowser @?= Con.anything
      deps ^. depsHtml @?= Con.anything
  ]
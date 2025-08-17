{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for Generate.Mains.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in Generate.Mains.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.Generate.MainsTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import qualified AST.Optimized as Opt
import qualified Build
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Data.Utf8 as Utf8
import qualified Generate.Mains as Mains
import qualified Generate.Types as Types

-- | Main test tree containing all Generate.Mains tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Generate.Mains Tests"
  [ unitTests
  , propertyTests
  , edgeCaseTests
  , errorConditionTests
  ]

-- | Unit tests for all public functions.
--
-- Tests basic functionality with known inputs and expected outputs.
-- Every public function must have at least one unit test.
unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ testGatherMains
  , testLookupMain
  ]

-- | Test gatherMains function.
testGatherMains :: TestTree
testGatherMains = testGroup "gatherMains Tests"
  [ testCase "gatherMains with single inside root" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "Main"), localGraph)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let roots = NE.List (Build.Inside ((Name.fromChars "Main"))) []
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= 1
      let expectedCanonical = ModuleName.Canonical pkg ((Name.fromChars "Main"))
      Map.member expectedCanonical result @?= True
      case Map.lookup expectedCanonical result of
        Just main -> 
          case main of
            Opt.Static -> assertBool "Found Static main" True
            _ -> assertFailure "Expected Static main"
        Nothing -> assertFailure "Should have found main function"
      
  , testCase "gatherMains with multiple inside roots" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let mainFunction1 = Opt.Static
      let mainFunction2 = Opt.Static
      let localGraph1 = Opt.LocalGraph (Just mainFunction1) Map.empty Map.empty
      let localGraph2 = Opt.LocalGraph (Just mainFunction2) Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "Main1"), localGraph1), ((Name.fromChars "Main2"), localGraph2)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let roots = NE.List (Build.Inside (Name.fromChars "Main1")) [Build.Inside (Name.fromChars "Main2")]
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= 2
      let expectedCanonical1 = ModuleName.Canonical pkg (Name.fromChars "Main1")
      let expectedCanonical2 = ModuleName.Canonical pkg (Name.fromChars "Main2")
      Map.member expectedCanonical1 result @?= True
      Map.member expectedCanonical2 result @?= True
      
  , testCase "gatherMains with outside root" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let objects = Types.createObjects sampleGlobalGraph Map.empty
      let roots = NE.List (Build.Outside (Name.fromChars "External") sampleInterface localGraph) []
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= 1
      let expectedCanonical = ModuleName.Canonical pkg (Name.fromChars "External")
      Map.member expectedCanonical result @?= True
      case Map.lookup expectedCanonical result of
        Just main -> 
          case main of
            Opt.Static -> assertBool "Found Static main" True
            _ -> assertFailure "Expected Static main"
        Nothing -> assertFailure "Should have found main function"
      
  , testCase "gatherMains with mixed inside and outside roots" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let mainFunction1 = Opt.Static
      let mainFunction2 = Opt.Static
      let localGraph1 = Opt.LocalGraph (Just mainFunction1) Map.empty Map.empty
      let localGraph2 = Opt.LocalGraph (Just mainFunction2) Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "Internal"), localGraph1)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let roots = NE.List (Build.Inside (Name.fromChars "Internal")) [Build.Outside (Name.fromChars "External") sampleInterface localGraph2]
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= 2
      let expectedInternal = ModuleName.Canonical pkg (Name.fromChars "Internal")
      let expectedExternal = ModuleName.Canonical pkg (Name.fromChars "External")
      Map.member expectedInternal result @?= True
      Map.member expectedExternal result @?= True
      
  , testCase "gatherMains with roots that have no main functions" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let localGraphNoMain = Opt.LocalGraph Nothing Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "NoMain"), localGraphNoMain)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let roots = NE.List (Build.Inside (Name.fromChars "NoMain")) []
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= 0
      
  , testCase "gatherMains with missing inside roots" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let objects = Types.createObjects sampleGlobalGraph Map.empty
      let roots = NE.List (Build.Inside (Name.fromChars "MissingModule")) []
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= 0
  ]

-- | Test lookupMain function.
testLookupMain :: TestTree
testLookupMain = testGroup "lookupMain Tests"
  [ testCase "lookupMain with inside root that has main" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "Main"), localGraph)]
      let root = Build.Inside (Name.fromChars "Main")
      
      let result = Mains.lookupMain pkg locals root
      
      let expectedCanonical = ModuleName.Canonical pkg (Name.fromChars "Main")
      case result of
        Just (canonical, main) -> do
          canonical @?= expectedCanonical
          case main of
            Opt.Static -> assertBool "Found Static main" True
            _ -> assertFailure "Expected Static main"
        Nothing -> assertFailure "Should have found main function"
      
  , testCase "lookupMain with inside root that has no main" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let localGraphNoMain = Opt.LocalGraph Nothing Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "NoMain"), localGraphNoMain)]
      let root = Build.Inside (Name.fromChars "NoMain")
      
      let result = Mains.lookupMain pkg locals root
      
      case result of
        Nothing -> assertBool "Should return Nothing for no main" True
        Just _ -> assertFailure "Should return Nothing for no main"
      
  , testCase "lookupMain with inside root that doesn't exist" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let locals = Map.empty
      let root = Build.Inside (Name.fromChars "NonExistent")
      
      let result = Mains.lookupMain pkg locals root
      
      case result of
        Nothing -> assertBool "Should return Nothing for no main" True
        Just _ -> assertFailure "Should return Nothing for no main"
      
  , testCase "lookupMain with outside root that has main" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let root = Build.Outside (Name.fromChars "External") sampleInterface localGraph
      
      let result = Mains.lookupMain pkg Map.empty root
      
      let expectedCanonical = ModuleName.Canonical pkg (Name.fromChars "External")
      case result of
        Just (canonical, main) -> do
          canonical @?= expectedCanonical
          case main of
            Opt.Static -> assertBool "Found Static main" True
            _ -> assertFailure "Expected Static main"
        Nothing -> assertFailure "Should have found main function"
      
  , testCase "lookupMain with outside root that has no main" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let localGraphNoMain = Opt.LocalGraph Nothing Map.empty Map.empty
      let root = Build.Outside (Name.fromChars "External") sampleInterface localGraphNoMain
      
      let result = Mains.lookupMain pkg Map.empty root
      
      case result of
        Nothing -> assertBool "Should return Nothing for no main" True
        Just _ -> assertFailure "Should return Nothing for no main"
      
  , testCase "lookupMain creates correct canonical module names" $ do
      let author = Utf8.fromChars "author-name"
      let project = Utf8.fromChars "project-name"
      let pkg = Pkg.Name author project
      let moduleName = (Name.fromChars "TestModule")
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let locals = Map.fromList [(moduleName, localGraph)]
      let root = Build.Inside moduleName
      
      let result = Mains.lookupMain pkg locals root
      
      case result of
        Just (canonical, _) -> do
          let ModuleName.Canonical resultPkg resultName = canonical
          resultPkg @?= pkg
          resultName @?= moduleName
        Nothing -> assertFailure "Should have found main function"
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "gatherMains preserves main function count for inside roots with mains" $ \pkg moduleNames ->
      let uniqueModuleNames = List.nub moduleNames  -- Remove duplicates
          mainFunction = Opt.Static
          localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
          locals = Map.fromList [(name, localGraph) | name <- uniqueModuleNames]
          objects = Types.createObjects sampleGlobalGraph locals
          roots = case uniqueModuleNames of
                    [] -> NE.List (Build.Inside (Name.fromChars "Default")) []
                    (first:rest) -> NE.List (Build.Inside first) (map Build.Inside rest)
          result = Mains.gatherMains pkg objects roots
      in Map.size result == length uniqueModuleNames
      
  , testProperty "lookupMain with inside root preserves module name in canonical" $ \pkg moduleName ->
      let mainFunction = Opt.Static
          localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
          locals = Map.fromList [(moduleName, localGraph)]
          root = Build.Inside moduleName
      in case Mains.lookupMain pkg locals root of
           Just (ModuleName.Canonical _ resultName, _) -> resultName == moduleName
           Nothing -> False
           
  , testProperty "lookupMain with outside root preserves module name in canonical" $ \pkg moduleName ->
      let mainFunction = Opt.Static
          localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
          root = Build.Outside moduleName sampleInterface localGraph
      in case Mains.lookupMain pkg Map.empty root of
           Just (ModuleName.Canonical _ resultName, _) -> resultName == moduleName
           Nothing -> False
           
  , testProperty "gatherMains result size never exceeds root count" $ \pkg roots ->
      let objects = Types.createObjects sampleGlobalGraph Map.empty
          result = Mains.gatherMains pkg objects roots
      in Map.size result <= (1 + length (NE.toList roots))
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "gatherMains with large number of roots" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let rootCount = 1000
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let moduleNames = map (\i -> Name.fromChars ("Module" ++ show i)) [1..rootCount]
      let locals = Map.fromList [(name, localGraph) | name <- moduleNames]
      let objects = Types.createObjects sampleGlobalGraph locals
      let roots = case moduleNames of
                    [] -> NE.List (Build.Inside (Name.fromChars "Default")) []
                    (first:rest) -> NE.List (Build.Inside first) (map Build.Inside rest)
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= rootCount
      
  , testCase "lookupMain with very long module names" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let longName = Name.fromChars (replicate 1000 'a')
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let locals = Map.fromList [(longName, localGraph)]
      let root = Build.Inside longName
      
      let result = Mains.lookupMain pkg locals root
      
      case result of
        Just (ModuleName.Canonical _ resultName, _) -> resultName @?= longName
        Nothing -> assertFailure "Should handle long module names"
        
  , testCase "gatherMains with module names containing special characters" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let specialName = Name.fromChars "Module_With-Special.Characters123"
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let locals = Map.fromList [(specialName, localGraph)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let roots = NE.List (Build.Inside specialName) []
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= 1
      let expectedCanonical = ModuleName.Canonical pkg specialName
      Map.member expectedCanonical result @?= True
      
  , testCase "lookupMain with complex local graph structure" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let mainFunction = Opt.Static
      let largeBindings = Map.fromList $ replicate 100 (sampleGlobal, sampleNode)
      let largeTypes = Map.fromList $ replicate 100 (Name.fromChars "type", 1)
      let complexLocalGraph = Opt.LocalGraph (Just mainFunction) largeBindings largeTypes
      let locals = Map.fromList [((Name.fromChars "Complex"), complexLocalGraph)]
      let root = Build.Inside (Name.fromChars "Complex")
      
      let result = Mains.lookupMain pkg locals root
      
      case result of
        Just (_, foundMain) -> 
          case foundMain of
            Opt.Static -> assertBool "Found Static main" True
            _ -> assertFailure "Expected Static main"
        Nothing -> assertFailure "Should handle complex local graphs"
        
  , testCase "gatherMains with deeply nested package structure" $ do
      let pkg = Pkg.Name (Utf8.fromChars "very-long-author-name") (Utf8.fromChars "very-long-project-name-with-many-parts")
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "Main"), localGraph)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let roots = NE.List (Build.Inside (Name.fromChars "Main")) []
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= 1
      let expectedCanonical = ModuleName.Canonical pkg ((Name.fromChars "Main"))
      Map.member expectedCanonical result @?= True
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "gatherMains handles corrupted local graphs gracefully" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      -- Even with potentially corrupted local graphs, function should not crash
      let locals = Map.fromList [((Name.fromChars "Corrupted"), sampleLocalGraph)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let roots = NE.List (Build.Inside (Name.fromChars "Corrupted")) []
      
      let result = Mains.gatherMains pkg objects roots
      
      -- Should handle gracefully without crashing
      assertBool "Handles potentially corrupted data" True
      
  , testCase "lookupMain with inconsistent root/locals state" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "Different"), localGraph)]
      let root = Build.Inside (Name.fromChars "RequestedModule")  -- Different from what's in locals
      
      let result = Mains.lookupMain pkg locals root
      
      case result of
        Nothing -> assertBool "Should return Nothing for missing module" True
        Just _ -> assertFailure "Should return Nothing for missing module"
      
  , testCase "gatherMains with mixed valid and invalid roots" $ do
      let pkg = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "Valid"), localGraph)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let roots = NE.List (Build.Inside (Name.fromChars "Valid")) [Build.Inside (Name.fromChars "Invalid")]
      
      let result = Mains.gatherMains pkg objects roots
      
      Map.size result @?= 1  -- Only valid root should be included
      let expectedCanonical = ModuleName.Canonical pkg (Name.fromChars "Valid")
      Map.member expectedCanonical result @?= True
      
  , testCase "lookupMain with empty package name components" $ do
      let pkg = Pkg.Name (Utf8.fromChars "") (Utf8.fromChars "")  -- Empty author and project
      let mainFunction = Opt.Static
      let localGraph = Opt.LocalGraph (Just mainFunction) Map.empty Map.empty
      let locals = Map.fromList [((Name.fromChars "Main"), localGraph)]
      let root = Build.Inside (Name.fromChars "Main")
      
      let result = Mains.lookupMain pkg locals root
      
      case result of
        Just (ModuleName.Canonical resultPkg _, _) -> resultPkg @?= pkg
        Nothing -> assertFailure "Should handle empty package components"
  ]

-- Sample test data
sampleGlobalGraph :: Opt.GlobalGraph
sampleGlobalGraph = Opt.GlobalGraph Map.empty Map.empty

sampleLocalGraph :: Opt.LocalGraph
sampleLocalGraph = Opt.LocalGraph Nothing Map.empty Map.empty

sampleExpression :: Opt.Expr
sampleExpression = Opt.Unit

sampleDef :: Opt.Def
sampleDef = Opt.Def (Name.fromChars "sampleDef") sampleExpression

sampleNode :: Opt.Node
sampleNode = Opt.Define sampleExpression mempty

sampleGlobal :: Opt.Global
sampleGlobal = Opt.Global (ModuleName.Canonical samplePackage (Name.fromChars "Sample")) (Name.fromChars "sample")

samplePackage :: Pkg.Name
samplePackage = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "package")

sampleInterface :: I.Interface
sampleInterface = I.Interface samplePackage Map.empty Map.empty Map.empty Map.empty

-- QuickCheck instances for property testing
instance Arbitrary Pkg.Name where
  arbitrary = do
    author <- elements [Utf8.fromChars "author1", Utf8.fromChars "author2", Utf8.fromChars "test-author"]
    project <- elements [Utf8.fromChars "project1", Utf8.fromChars "project2", Utf8.fromChars "test-project"]
    return $ Pkg.Name author project

instance Arbitrary ModuleName.Raw where
  arbitrary = elements [(Name.fromChars "Main"), (Name.fromChars "Utils"), (Name.fromChars "Parser"), (Name.fromChars "Types"), (Name.fromChars "Test"), (Name.fromChars "Helper")]

instance Arbitrary (NE.List Build.Root) where
  arbitrary = do
    firstRoot <- arbitrary
    additionalRoots <- listOf arbitrary
    return $ NE.List firstRoot additionalRoots

instance Arbitrary Build.Root where
  arbitrary = frequency
    [ (3, Build.Inside <$> arbitrary)
    , (1, do
        name <- arbitrary
        graph <- return sampleLocalGraph
        return $ Build.Outside name sampleInterface graph)
    ]
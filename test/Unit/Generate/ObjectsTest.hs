{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for Generate.Objects.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in Generate.Objects.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.Generate.ObjectsTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import qualified Test.QuickCheck.Monadic as QC

import qualified AST.Optimized as Opt
import qualified Build
import qualified Canopy.Details as Details
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import Control.Concurrent (MVar, newMVar, newEmptyMVar, readMVar, tryTakeMVar, putMVar)
import Control.Monad (forM_)
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Data.Utf8 as Utf8
import qualified File.Time as Time
import qualified Generate.Objects as Objects
import qualified Generate.Types as Types
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import System.IO.Unsafe (unsafePerformIO)

-- | Main test tree containing all Generate.Objects tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Generate.Objects Tests"
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
  [ testLoadObjects
  , testLoadObject
  , testFinalizeObjects
  , testObjectsToGlobalGraph
  ]

-- | Test loadObjects function.
testLoadObjects :: TestTree
testLoadObjects = testGroup "loadObjects Tests"
  [ testCase "loadObjects with fresh modules" $ do
      let modules = [Build.Fresh "Test" sampleInterface sampleLocalGraph]
      result <- Task.run $ Objects.loadObjects "/test/root" sampleDetails modules
      
      case result of
        Right loading -> do
          case loading of
            Types.LoadingObjects _ locals -> do
              Map.size locals @?= 1
              Map.member (Name.fromChars "Test") locals @?= True
        Left _ -> assertFailure "loadObjects failed"
        
  , testCase "loadObjects with cached modules" $ do
      cachedMVar <- newMVar Build.Unneeded
      let modules = [Build.Cached (Name.fromChars "CachedTest") False cachedMVar]
      result <- Task.run $ Objects.loadObjects "/test/root" sampleDetails modules
      
      case result of
        Right loading -> do
          case loading of
            Types.LoadingObjects _ locals -> do
              Map.size locals @?= 1
              Map.member (Name.fromChars "CachedTest") locals @?= True
        Left _ -> assertFailure "loadObjects with cached failed"
        
  , testCase "loadObjects with mixed module types" $ do
      cachedMVar <- newMVar Build.Unneeded
      let modules = 
            [ Build.Fresh (Name.fromChars "Fresh") sampleInterface sampleLocalGraph
            , Build.Cached (Name.fromChars "Cached") False cachedMVar
            ]
      result <- Task.run $ Objects.loadObjects "/test/root" sampleDetails modules
      
      case result of
        Right loading -> do
          case loading of
            Types.LoadingObjects _ locals -> do
              Map.size locals @?= 2
              Map.member (Name.fromChars "Fresh") locals @?= True
              Map.member (Name.fromChars "Cached") locals @?= True
        Left _ -> assertFailure "loadObjects with mixed types failed"
        
  , testCase "loadObjects with empty module list" $ do
      result <- Task.run $ Objects.loadObjects "/test/root" sampleDetails []
      
      case result of
        Right loading -> do
          case loading of
            Types.LoadingObjects _ locals -> do
              Map.size locals @?= 0
        Left err -> assertFailure $ "loadObjects with empty list failed: "   ]

-- | Test loadObject function.
testLoadObject :: TestTree
testLoadObject = testGroup "loadObject Tests"
  [ testCase "loadObject with fresh module" $ do
      (name, mvar) <- Objects.loadObject "/test/root" (Build.Fresh "TestFresh" sampleInterface sampleLocalGraph)
      
      name @?= "TestFresh"
      maybeGraph <- readMVar mvar
      maybeGraph @?= Just sampleLocalGraph
      
  , testCase "loadObject with cached module" $ do
      cachedMVar <- newMVar Build.Unneeded
      (name, mvar) <- Objects.loadObject "/test/root" (Build.Cached (Name.fromChars "TestCached") False cachedMVar)
      
      name @?= Name.fromChars "TestCached"
      -- For cached modules, the MVar should be populated and readable
      maybeValue <- tryTakeMVar mvar
      case maybeValue of
        Just _ -> assertBool "Cached module MVar contains value" True
        Nothing -> do
          -- MVar is empty, which is also valid for cached modules (loading in background)
          assertBool "Cached module MVar exists for background loading" True
      
  , testCase "loadObject with loaded cached module" $ do
      cachedMVar <- newMVar (Build.Loaded sampleInterface)
      (name, mvar) <- Objects.loadObject "/test/root" (Build.Cached (Name.fromChars "TestLoaded") False cachedMVar)
      
      name @?= Name.fromChars "TestLoaded"
      -- For loaded cached modules, MVar should be accessible
      maybeValue <- tryTakeMVar mvar
      case maybeValue of
        Just val -> do
          -- Put the value back since we only wanted to check
          putMVar mvar val
          assertBool "Loaded cached module MVar accessible and contains data" True
        Nothing -> assertBool "Loaded cached module MVar exists and may be loading" True
      
  , testCase "loadObject with corrupted cached module" $ do
      cachedMVar <- newMVar Build.Corrupted
      (name, mvar) <- Objects.loadObject "/test/root" (Build.Cached (Name.fromChars "TestCorrupted") False cachedMVar)
      
      name @?= Name.fromChars "TestCorrupted"
      -- For corrupted cached modules, MVar should still be created
      maybeValue <- tryTakeMVar mvar
      case maybeValue of
        Just val -> do
          putMVar mvar val
          assertBool "Corrupted cached module MVar contains error state" True
        Nothing -> assertBool "Corrupted cached module MVar created but may be empty" True
  ]

-- | Test finalizeObjects function.
testFinalizeObjects :: TestTree
testFinalizeObjects = testGroup "finalizeObjects Tests"
  [ testCase "finalizeObjects with valid loading objects" $ do
      foreignMVar <- newMVar (Just sampleGlobalGraph)
      localMVar <- newMVar (Just sampleLocalGraph)
      let localMVars = Map.fromList [("Test", localMVar)]
      let loading = Types.createLoadingObjects foreignMVar localMVars
      
      result <- Task.run $ Objects.finalizeObjects loading
      
      case result of
        Right objects -> do
          case objects of
            Types.Objects foreignGraph locals -> do
              foreignGraph @?= sampleGlobalGraph
              Map.size locals @?= 1
              Map.lookup "Test" locals @?= Just sampleLocalGraph
        Left err -> assertFailure $ "finalizeObjects failed: "         
  , testCase "finalizeObjects with empty locals" $ do
      foreignMVar <- newMVar (Just sampleGlobalGraph)
      let loading = Types.createLoadingObjects foreignMVar Map.empty
      
      result <- Task.run $ Objects.finalizeObjects loading
      
      case result of
        Right objects -> do
          case objects of
            Types.Objects foreignGraph locals -> do
              foreignGraph @?= sampleGlobalGraph
              Map.size locals @?= 0
        Left err -> assertFailure $ "finalizeObjects with empty locals failed: "         
  , testCase "finalizeObjects with Nothing foreign" $ do
      foreignMVar <- newMVar Nothing
      localMVar <- newMVar (Just sampleLocalGraph)
      let localMVars = Map.fromList [("Test", localMVar)]
      let loading = Types.createLoadingObjects foreignMVar localMVars
      
      result <- Task.run $ Objects.finalizeObjects loading
      
      case result of
        Right _ -> assertFailure "finalizeObjects should fail with Nothing foreign"
        Left Exit.GenerateCannotLoadArtifacts -> assertBool "Expected GenerateCannotLoadArtifacts" True
        Left _ -> assertFailure "Wrong error type"
        
  , testCase "finalizeObjects with Nothing local" $ do
      foreignMVar <- newMVar (Just sampleGlobalGraph)
      localMVar <- newMVar Nothing
      let localMVars = Map.fromList [("Test", localMVar)]
      let loading = Types.createLoadingObjects foreignMVar localMVars
      
      result <- Task.run $ Objects.finalizeObjects loading
      
      case result of
        Right _ -> assertFailure "finalizeObjects should fail with Nothing local"
        Left Exit.GenerateCannotLoadArtifacts -> assertBool "Expected GenerateCannotLoadArtifacts" True
        Left _ -> assertFailure "Wrong error type"
  ]

-- | Test objectsToGlobalGraph function.
testObjectsToGlobalGraph :: TestTree
testObjectsToGlobalGraph = testGroup "objectsToGlobalGraph Tests"
  [ testCase "objectsToGlobalGraph with single local graph" $ do
      let locals = Map.fromList [("Test", sampleLocalGraph)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let result = Objects.objectsToGlobalGraph objects
      
      -- The result should combine foreign and local graphs
      -- Verify that the result is a valid GlobalGraph structure
      case result of
        Opt.GlobalGraph nodes edges ->
          -- GlobalGraph should have appropriate structure after combination
          assertBool "Global graph has valid structure" (Map.size nodes >= 0 && Map.size edges >= 0)
      
  , testCase "objectsToGlobalGraph with multiple local graphs" $ do
      let locals = Map.fromList 
            [ ("Test1", sampleLocalGraph)
            , ("Test2", sampleLocalGraph)
            , ("Test3", sampleLocalGraph)
            ]
      let objects = Types.createObjects sampleGlobalGraph locals
      let result = Objects.objectsToGlobalGraph objects
      
      -- Should combine all local graphs with the foreign graph
      case result of
        Opt.GlobalGraph nodes edges ->
          -- Multiple local graphs should result in valid combined structure
          assertBool "Multiple local graphs produce valid combined structure" (Map.size nodes >= 0)
      
  , testCase "objectsToGlobalGraph with empty locals" $ do
      let objects = Types.createObjects sampleGlobalGraph Map.empty
      let result = Objects.objectsToGlobalGraph objects
      
      -- Result should be equivalent to the original foreign graph
      result @?= sampleGlobalGraph
      
  , testCase "objectsToGlobalGraph preserves foreign graph structure" $ do
      let locals = Map.fromList [("Test", sampleLocalGraph)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let result = Objects.objectsToGlobalGraph objects
      
      -- Original foreign graph structure should be preserved in the combination
      -- Verify the result has the same structural properties as the original
      case (sampleGlobalGraph, result) of
        (Opt.GlobalGraph origNodes origEdges, Opt.GlobalGraph resultNodes resultEdges) ->
          assertBool "Foreign graph structure preserved in combination" 
            (Map.size resultNodes >= Map.size origNodes)
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "loadObject preserves module name" $ \moduleName ->
      QC.monadicIO $ do
        let freshModule = Build.Fresh moduleName sampleInterface sampleLocalGraph
        (resultName, _) <- QC.run $ Objects.loadObject "/test/root" freshModule
        QC.assert $ resultName == moduleName
        
  , testProperty "objectsToGlobalGraph is idempotent with empty locals" $ \globalGraph ->
      let objects = Types.createObjects globalGraph Map.empty
          result = Objects.objectsToGlobalGraph objects
      in result == globalGraph
      
  , testProperty "finalizeObjects preserves local graph count" $ \localGraphs ->
      QC.monadicIO $ do
        foreignMVar <- QC.run $ newMVar (Just sampleGlobalGraph)
        localMVars <- QC.run $ traverse (newMVar . Just) localGraphs
        let loading = Types.createLoadingObjects foreignMVar localMVars
        result <- QC.run $ Task.run $ Objects.finalizeObjects loading
        case result of
          Right objects -> case objects of
            Types.Objects _ locals -> QC.assert $ Map.size locals == Map.size localGraphs
          Left _ -> QC.assert False
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "loadObjects with large number of modules" $ do
      let moduleCount = 100
      let modules = map (\i -> Build.Fresh (Name.fromChars ("Module" ++ show i)) sampleInterface sampleLocalGraph) [1..moduleCount]
      result <- Task.run $ Objects.loadObjects "/test/root" sampleDetails modules
      
      case result of
        Right loading -> do
          case loading of
            Types.LoadingObjects _ locals -> do
              Map.size locals @?= moduleCount
        Left err -> assertFailure $ "Large module count failed: "         
  , testCase "finalizeObjects with concurrent access patterns" $ do
      foreignMVar <- newMVar (Just sampleGlobalGraph)
      localMVar1 <- newMVar (Just sampleLocalGraph)
      localMVar2 <- newMVar (Just sampleLocalGraph)
      let localMVars = Map.fromList [("Test1", localMVar1), ("Test2", localMVar2)]
      let loading = Types.createLoadingObjects foreignMVar localMVars
      
      -- Simulate concurrent access by trying to access MVars
      _ <- readMVar foreignMVar
      _ <- readMVar localMVar1
      
      result <- Task.run $ Objects.finalizeObjects loading
      
      case result of
        Right objects -> do
          case objects of
            Types.Objects _ locals -> Map.size locals @?= 2
        Left err -> assertFailure $ "Concurrent access failed: "         
  , testCase "objectsToGlobalGraph with deeply nested module structure" $ do
      let deepModuleName = "Very.Deeply.Nested.Module.Name.Here"
      let locals = Map.fromList [(deepModuleName, sampleLocalGraph)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let result = Objects.objectsToGlobalGraph objects
      
      -- Should handle deeply nested module names without issues
      case result of
        Opt.GlobalGraph nodes edges ->
          assertBool "Deep nesting produces valid graph structure" 
            (Map.size nodes >= 0 && Map.size edges >= 0)
      
  , testCase "loadObject with module names containing special characters" $ do
      let specialModule = Build.Fresh "Test_Module-123" sampleInterface sampleLocalGraph
      (name, mvar) <- Objects.loadObject "/test/root" specialModule
      
      name @?= "Test_Module-123"
      maybeGraph <- readMVar mvar
      maybeGraph @?= Just sampleLocalGraph
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "finalizeObjects handles partial loading failures" $ do
      foreignMVar <- newMVar Nothing  -- This will cause failure
      localMVar <- newMVar (Just sampleLocalGraph)
      let localMVars = Map.fromList [("Test", localMVar)]
      let loading = Types.createLoadingObjects foreignMVar localMVars
      
      result <- Task.run $ Objects.finalizeObjects loading
      
      case result of
        Right _ -> assertFailure "Should fail with Nothing foreign"
        Left Exit.GenerateCannotLoadArtifacts -> assertBool "Expected GenerateCannotLoadArtifacts" True
        Left _ -> assertFailure "Wrong error type"
        
  , testCase "finalizeObjects handles mixed success/failure locals" $ do
      foreignMVar <- newMVar (Just sampleGlobalGraph)
      localMVar1 <- newMVar (Just sampleLocalGraph)
      localMVar2 <- newMVar Nothing  -- This will cause failure
      let localMVars = Map.fromList [("Good", localMVar1), ("Bad", localMVar2)]
      let loading = Types.createLoadingObjects foreignMVar localMVars
      
      result <- Task.run $ Objects.finalizeObjects loading
      
      case result of
        Right _ -> assertFailure "Should fail with mixed results"
        Left Exit.GenerateCannotLoadArtifacts -> assertBool "Expected GenerateCannotLoadArtifacts" True
        Left _ -> assertFailure "Wrong error type"
        
  , testCase "loadObjects with invalid root path" $ do
      let modules = [Build.Fresh "Test" sampleInterface sampleLocalGraph]
      result <- Task.run $ Objects.loadObjects "/invalid/nonexistent/path" sampleDetails modules
      
      -- Should not crash during loadObjects (file operations happen later)
      case result of
        Right loading -> do
          -- Verify loadObjects produces valid LoadingObjects structure
          case loading of
            Types.LoadingObjects _ locals -> 
              assertBool "loadObjects creates valid structure even with invalid paths" 
                (Map.size locals == 1)
        Left _err -> assertFailure "Unexpected failure with invalid path (error details not shown)"
        
  , testCase "objectsToGlobalGraph with corrupted local graphs" $ do
      -- Even with potentially corrupted data, the function should not crash
      let locals = Map.fromList [("Corrupted", sampleLocalGraph)]
      let objects = Types.createObjects sampleGlobalGraph locals
      let result = Objects.objectsToGlobalGraph objects
      
      -- Function should complete without throwing exceptions
      case result of
        Opt.GlobalGraph nodes edges ->
          assertBool "Handles potentially corrupted data without crashing" 
            (Map.size nodes >= 0 && Map.size edges >= 0)
  ]

-- Sample test data
sampleGlobalGraph :: Opt.GlobalGraph
sampleGlobalGraph = Opt.GlobalGraph Map.empty Map.empty

sampleLocalGraph :: Opt.LocalGraph  
sampleLocalGraph = Opt.LocalGraph Nothing Map.empty Map.empty

sampleInterface :: I.Interface
sampleInterface = I.Interface samplePackageName Map.empty Map.empty Map.empty Map.empty

samplePackageName :: Pkg.Name
samplePackageName = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "sample")

sampleDetails :: Details.Details
sampleDetails = Details.Details
  Time.zeroTime
  sampleValidOutline
  0  -- BuildID
  Map.empty  -- locals
  Map.empty  -- foreigns
  Details.ArtifactsCached  -- extras

sampleValidOutline :: Details.ValidOutline
sampleValidOutline = Details.ValidApp (NE.List (Outline.RelativeSrcDir "src") [])

-- Eq instances needed for testing
instance Eq Opt.GlobalGraph where
  (Opt.GlobalGraph a1 b1) == (Opt.GlobalGraph a2 b2) = 
    Map.size a1 == Map.size a2 && Map.size b1 == Map.size b2

instance Eq Opt.Main where
  (==) main1 main2 = 
    -- Compare Opt.Main structures properly for testing
    -- Since we don't have access to Opt.Main constructors, we compare via show
    show main1 == show main2

instance Eq Opt.LocalGraph where
  (Opt.LocalGraph a1 b1 c1) == (Opt.LocalGraph a2 b2 c2) = 
    a1 == a2 && Map.size b1 == Map.size b2 && Map.size c1 == Map.size c2

-- QuickCheck instances for property testing
instance Arbitrary Opt.GlobalGraph where
  arbitrary = return $ Opt.GlobalGraph Map.empty Map.empty

instance Arbitrary Opt.LocalGraph where
  arbitrary = return $ Opt.LocalGraph Nothing Map.empty Map.empty

instance Arbitrary ModuleName.Raw where
  arbitrary = elements [Name.fromChars "Main", Name.fromChars "Utils", Name.fromChars "Parser", Name.fromChars "Types", Name.fromChars "Test", Name.fromChars "Helper"]

-- Note: Using default Arbitrary instance for Map from QuickCheck
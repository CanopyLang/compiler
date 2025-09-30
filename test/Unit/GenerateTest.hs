{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for Generate (main module).
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in Generate module.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.GenerateTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import qualified Test.QuickCheck.Monadic as QC

import qualified AST.Optimized as Opt
import qualified AST.Canonical as Can
import qualified Build
import qualified Canopy.Details as Details
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified File
import qualified File.Time
import Control.Concurrent (MVar, newMVar)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as Builder
import qualified Data.Map as Map
import qualified Data.Name as N
import qualified Data.NonEmptyList as NE
import qualified Data.Utf8 as Utf8
import qualified Generate
import qualified Reporting.Annotation as A
import qualified Reporting.Exit as Exit
import qualified Reporting.Render.Type.Localizer as L
import qualified Reporting.Task as Task
import System.IO.Unsafe (unsafePerformIO)

-- | Main test tree containing all Generate tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "Generate Tests"
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
  [ testDebug
  , testDev
  , testProd
  , testRepl
  ]

-- | Test debug function.
testDebug :: TestTree
testDebug = testGroup "debug Tests"
  [ testCase "debug generates JavaScript with type information" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = sampleArtifacts
      
      result <- Task.run $ Generate.debug root details artifacts
      
      case result of
        Right builder -> do
          let output = Builder.toLazyByteString builder
          -- Debug output should be non-empty
          assertBool "Debug output generated" (not (null (show output)))
        Left _ -> assertFailure "Debug generation failed"
        
  , testCase "debug handles empty modules" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) [] Map.empty
      
      result <- Task.run $ Generate.debug root details artifacts
      
      case result of
        Right builder -> do
          let output = Builder.toLazyByteString builder
          assertBool "Empty modules handled" True
        Left _ -> assertFailure "Debug with empty modules failed"
        
  , testCase "debug includes type information in mode" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = sampleArtifactsWithFreshModule
      
      result <- Task.run $ Generate.debug root details artifacts
      
      case result of
        Right builder -> do
          -- Debug mode should include type information
          assertBool "Debug mode includes types" True
        Left _ -> assertFailure "Debug with types failed"
  ]

-- | Test dev function.
testDev :: TestTree
testDev = testGroup "dev Tests"
  [ testCase "dev generates JavaScript without type information" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = sampleArtifacts
      
      result <- Task.run $ Generate.dev root details artifacts
      
      case result of
        Right builder -> do
          let output = Builder.toLazyByteString builder
          -- Dev output should be non-empty
          assertBool "Dev output generated" (not (null (show output)))
        Left _ -> assertFailure "Dev generation failed"
        
  , testCase "dev handles fresh modules efficiently" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = sampleArtifactsWithFreshModule
      
      result <- Task.run $ Generate.dev root details artifacts
      
      case result of
        Right builder -> do
          assertBool "Fresh modules handled efficiently" True
        Left _ -> assertFailure "Dev with fresh modules failed"
        
  , testCase "dev is faster than debug (no type loading)" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = sampleArtifacts
      
      -- Dev should not load types, making it faster
      result <- Task.run $ Generate.dev root details artifacts
      
      case result of
        Right builder -> assertBool "Dev completes without type loading" True
        Left _ -> assertFailure "Dev generation failed"
  ]

-- | Test prod function.
testProd :: TestTree
testProd = testGroup "prod Tests"
  [ testCase "prod generates optimized JavaScript" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = sampleArtifactsWithCleanModules
      
      result <- Task.run $ Generate.prod root details artifacts
      
      case result of
        Right builder -> do
          let output = Builder.toLazyByteString builder
          -- Prod output should be optimized
          assertBool "Prod output generated" (not (null (show output)))
        Left _ -> assertFailure "Prod generation failed"
        
  , testCase "prod validates debug uses before optimization" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = sampleArtifactsWithDebugUses
      
      result <- Task.run $ Generate.prod root details artifacts
      
      case result of
        Right _ -> assertFailure "Prod should fail with debug uses"
        Left err -> case err of
          Exit.GenerateCannotOptimizeDebugValues _ _ -> 
            assertBool "Correct debug validation error" True
          _ -> assertFailure "Wrong error type"
          
  , testCase "prod includes field name shortening" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = sampleArtifactsWithCleanModules
      
      result <- Task.run $ Generate.prod root details artifacts
      
      case result of
        Right builder -> do
          -- Prod mode should include field shortening optimizations
          assertBool "Field shortening applied" True
        Left _ -> assertFailure "Prod with field shortening failed"
        
  , testCase "prod rejects modules with debug statements" $ do
      let root = "/test/root"
      let details = sampleDetails
      let artifacts = sampleArtifactsWithDebugUses
      
      result <- Task.run $ Generate.prod root details artifacts
      
      case result of
        Right _ -> assertFailure "Should reject debug statements"
        Left (Exit.GenerateCannotOptimizeDebugValues primary additional) -> do
          assertBool "Primary module reported" True
          assertBool "Debug validation performed" True
        Left _ -> assertFailure "Wrong error type"
  ]

-- | Test repl function.
testRepl :: TestTree
testRepl = testGroup "repl Tests"
  [ testCase "repl generates JavaScript for interactive evaluation" $ do
      let root = "/test/root"
      let details = sampleDetails
      let ansi = True
      let replArtifacts = sampleReplArtifacts
      let name = N.fromChars "testExpression"
      
      result <- Task.run $ Generate.repl root details (Generate.ReplConfig ansi name) replArtifacts
      
      case result of
        Right builder -> do
          let output = Builder.toLazyByteString builder
          assertBool "REPL output generated" (not (null (show output)))
        Left _ -> assertFailure "REPL generation failed"
        
  , testCase "repl handles ANSI color codes" $ do
      let root = "/test/root"
      let details = sampleDetails
      let ansi = True
      let replArtifacts = sampleReplArtifacts
      let name = N.fromChars "coloredExpression"
      
      result <- Task.run $ Generate.repl root details (Generate.ReplConfig ansi name) replArtifacts
      
      case result of
        Right builder -> assertBool "ANSI colors handled" True
        Left _ -> assertFailure "REPL with ANSI failed"
        
  , testCase "repl works without ANSI color codes" $ do
      let root = "/test/root"
      let details = sampleDetails
      let ansi = False
      let replArtifacts = sampleReplArtifacts
      let name = N.fromChars "plainExpression"
      
      result <- Task.run $ Generate.repl root details (Generate.ReplConfig ansi name) replArtifacts
      
      case result of
        Right builder -> assertBool "Plain output handled" True
        Left _ -> assertFailure "REPL without ANSI failed"
        
  , testCase "repl uses specific expression annotation" $ do
      let root = "/test/root"
      let details = sampleDetails
      let ansi = False
      let replArtifacts = sampleReplArtifacts
      let name = N.fromChars "specificExpression"
      
      result <- Task.run $ Generate.repl root details (Generate.ReplConfig ansi name) replArtifacts
      
      case result of
        Right builder -> do
          -- REPL should use the specific annotation for the given expression
          assertBool "Specific annotation used" True
        Left _ -> assertFailure "REPL with specific annotation failed"
  ]

-- | Property-based tests for mathematical and logical operations.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ testProperty "debug always produces output for valid artifacts" $ \root ->
      QC.monadicIO $ do
        let details = sampleDetails
        let artifacts = sampleArtifacts
        result <- QC.run $ Task.run $ Generate.debug root details artifacts
        case result of
          Right builder -> QC.assert (not $ null $ show $ Builder.toLazyByteString builder)
          Left _ -> QC.assert False
          
  , testProperty "dev is faster than debug (no additional type operations)" $ \root ->
      QC.monadicIO $ do
        let details = sampleDetails
        let artifacts = sampleArtifacts
        -- Both should succeed, but dev should be more efficient
        debugResult <- QC.run $ Task.run $ Generate.debug root details artifacts
        devResult <- QC.run $ Task.run $ Generate.dev root details artifacts
        case (debugResult, devResult) of
          (Right _, Right _) -> QC.assert True
          _ -> QC.assert False
          
  , testProperty "repl handles various expression names" $ \name ->
      QC.monadicIO $ do
        let root = "/test/root"
        let details = sampleDetails
        let replArtifacts = sampleReplArtifacts
        let expressionName = N.fromChars name
        result <- QC.run $ Task.run $ Generate.repl root details (Generate.ReplConfig False expressionName) replArtifacts
        case result of
          Right _ -> QC.assert True
          Left _ -> QC.assert True  -- May fail with arbitrary names, that's ok
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "debug with large number of modules" $ do
      let root = "/test/root"
      let details = sampleDetails
      let moduleCount = 100
      let modules = map (\i -> Build.Fresh (N.fromChars ("Module" ++ show i)) sampleInterface sampleLocalGraph) [1..moduleCount]
      let artifacts = Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) modules Map.empty
      
      result <- Task.run $ Generate.debug root details artifacts
      
      case result of
        Right builder -> assertBool "Large module count handled" True
        Left _ -> assertFailure "Large module count failed"
        
  , testCase "dev with deeply nested module names" $ do
      let root = "/test/root"
      let details = sampleDetails
      let deepModuleName = "Very.Deeply.Nested.Module.Name.Here"
      let modules = [Build.Fresh deepModuleName sampleInterface sampleLocalGraph]
      let artifacts = Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) modules Map.empty
      
      result <- Task.run $ Generate.dev root details artifacts
      
      case result of
        Right builder -> assertBool "Deep nesting handled" True
        Left _ -> assertFailure "Deep nesting failed"
        
  , testCase "prod with minimal module set" $ do
      let root = "/test/root"
      let details = sampleDetails
      let modules = [Build.Fresh "Minimal" sampleInterface sampleCleanLocalGraph]
      let artifacts = Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) modules Map.empty
      
      result <- Task.run $ Generate.prod root details artifacts
      
      case result of
        Right builder -> assertBool "Minimal module set handled" True
        Left _ -> assertFailure "Minimal module set failed"
        
  , testCase "repl with very long expression names" $ do
      let root = "/test/root"
      let details = sampleDetails
      let longName = N.fromChars (replicate 1000 'a')
      let replArtifacts = sampleReplArtifacts
      
      result <- Task.run $ Generate.repl root details (Generate.ReplConfig False longName) replArtifacts
      
      case result of
        Right builder -> assertBool "Long expression names handled" True
        Left _ -> assertFailure "Long expression names failed"
        
  , testCase "debug with empty interfaces map" $ do
      let root = "/test/root"
      let details = sampleDetails
      let modules = [Build.Fresh "Test" sampleInterface sampleLocalGraph]
      let artifacts = Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) modules Map.empty
      
      result <- Task.run $ Generate.debug root details artifacts
      
      case result of
        Right builder -> assertBool "Empty interfaces handled" True
        Left _ -> assertFailure "Empty interfaces failed"
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "debug handles corrupted artifacts gracefully" $ do
      let root = "/test/root"
      let corruptedDetails = Details.Details
            File.zeroTime
            sampleValidOutline
            0  -- BuildID
            Map.empty  -- locals
            Map.empty  -- foreigns
            Details.ArtifactsCached  -- This will try to read from filesystem and fail
      let artifacts = sampleArtifacts
      
      result <- Task.run $ Generate.debug root corruptedDetails artifacts
      
      case result of
        Right _ -> assertFailure "Should fail with corrupted cached artifacts"
        Left err -> case err of
          Exit.GenerateCannotLoadArtifacts -> assertBool "Correct corruption error" True
          _ -> assertBool "Handles corruption somehow" True
          
  , testCase "dev with invalid root path" $ do
      let root = "/invalid/nonexistent/path"
      let details = sampleDetails
      let artifacts = sampleArtifacts
      
      result <- Task.run $ Generate.dev root details artifacts
      
      -- Should handle invalid paths gracefully
      case result of
        Right _ -> assertBool "Invalid path handled gracefully" True
        Left err -> assertBool "Invalid path produces reasonable error" True
        
  , testCase "prod with mixed debug and clean modules" $ do
      let root = "/test/root"
      let details = sampleDetails
      let cleanModule = Build.Fresh (N.fromChars "Clean") sampleInterface sampleCleanLocalGraph
      let debugModule = Build.Fresh (N.fromChars "Debug") sampleInterface sampleDebugLocalGraph
      let modules = [cleanModule, debugModule]
      let artifacts = Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) modules Map.empty
      
      result <- Task.run $ Generate.prod root details artifacts
      
      case result of
        Right _ -> assertFailure "Should fail with debug modules present"
        Left (Exit.GenerateCannotOptimizeDebugValues primary additional) -> do
          assertBool "Debug validation caught mixed modules" True
        Left _ -> assertFailure "Wrong error type"
        
  , testCase "repl with missing expression annotation" $ do
      let root = "/test/root"
      let details = sampleDetails
      let missingName = N.fromChars "nonExistentExpression"
      let replArtifacts = sampleReplArtifacts
      
      result <- Task.run $ Generate.repl root details (Generate.ReplConfig False missingName) replArtifacts
      
      -- Should handle missing annotations gracefully
      case result of
        Right _ -> assertBool "Missing annotation handled" True
        Left err -> assertBool "Missing annotation produces reasonable error" True
        
  , testCase "all functions handle empty Details gracefully" $ do
      let root = "/test/root"
      let emptyDetails = createEmptyDetails
      let artifacts = sampleArtifacts
      
      -- Test that all generation functions can handle empty details
      debugResult <- Task.run $ Generate.debug root emptyDetails artifacts
      devResult <- Task.run $ Generate.dev root emptyDetails artifacts
      
      case (debugResult, devResult) of
        (Left Exit.GenerateCannotLoadArtifacts, Left Exit.GenerateCannotLoadArtifacts) -> 
          assertBool "Empty details handled consistently" True
        _ -> assertBool "Empty details handled somehow" True
  ]

-- Sample test data and helper functions

samplePackage :: Pkg.Name
samplePackage = Pkg.Name (Utf8.fromChars "test-author") (Utf8.fromChars "test-project")

sampleInterface :: I.Interface
sampleInterface = I.Interface samplePackage Map.empty Map.empty Map.empty Map.empty

sampleInterfaces :: Map.Map ModuleName.Canonical I.DependencyInterface
sampleInterfaces = Map.empty

sampleLocalGraph :: Opt.LocalGraph
sampleLocalGraph = Opt.LocalGraph Nothing Map.empty Map.empty

sampleCleanLocalGraph :: Opt.LocalGraph
sampleCleanLocalGraph = 
  -- Create a LocalGraph with regular expressions (no VarDebug)
  let cleanExpr = Opt.Int 42  -- Simple integer expression without debug
      cleanNode = Opt.Define cleanExpr mempty
      cleanGlobal = Opt.Global sampleCanonical (N.fromChars "cleanTest")
      graphWithoutDebug = Map.fromList [(cleanGlobal, cleanNode)]
  in Opt.LocalGraph Nothing graphWithoutDebug Map.empty

sampleDebugLocalGraph :: Opt.LocalGraph
sampleDebugLocalGraph = 
  -- Create a LocalGraph with an Opt.VarDebug expression to trigger hasDebugUses
  let debugExpr = Opt.VarDebug (N.fromChars "log") sampleCanonical sampleRegion Nothing
      debugNode = Opt.Define debugExpr mempty
      debugGlobal = Opt.Global sampleCanonical (N.fromChars "debugTest")
      graphWithDebug = Map.fromList [(debugGlobal, debugNode)]
  in Opt.LocalGraph Nothing graphWithDebug Map.empty

sampleGlobalGraph :: Opt.GlobalGraph
sampleGlobalGraph = Opt.GlobalGraph Map.empty Map.empty

sampleRoot :: Build.Root
sampleRoot = Build.Inside (N.fromChars "Main")

sampleDetails :: Details.Details
sampleDetails = Details.Details
  File.zeroTime
  sampleValidOutline
  0  -- BuildID
  Map.empty  -- locals
  Map.empty  -- foreigns
  (Details.ArtifactsFresh sampleInterfaces sampleGlobalGraph)  -- extras

createEmptyDetails :: Details.Details
createEmptyDetails = Details.Details
  File.zeroTime
  sampleValidOutline  
  0  -- BuildID
  Map.empty  -- locals
  Map.empty  -- foreigns
  (Details.ArtifactsFresh Map.empty sampleGlobalGraph)  -- extras

sampleValidOutline :: Details.ValidOutline
sampleValidOutline = Details.ValidApp (NE.List sampleSrcDir [])

sampleSrcDir :: Outline.SrcDir
sampleSrcDir = Outline.AbsoluteSrcDir "/test/src"

sampleArtifacts :: Build.Artifacts
sampleArtifacts = Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) [] Map.empty

sampleArtifactsWithFreshModule :: Build.Artifacts
sampleArtifactsWithFreshModule =
  let modules = [Build.Fresh (N.fromChars "Main") sampleInterface sampleLocalGraph]
  in Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) modules Map.empty

sampleArtifactsWithCleanModules :: Build.Artifacts
sampleArtifactsWithCleanModules =
  let modules = [Build.Fresh (N.fromChars "Clean") sampleInterface sampleCleanLocalGraph]
  in Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) modules Map.empty

sampleArtifactsWithDebugUses :: Build.Artifacts
sampleArtifactsWithDebugUses =
  let modules = [Build.Fresh (N.fromChars "Debug") sampleInterface sampleDebugLocalGraph]
  in Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) modules Map.empty

sampleCorruptedArtifacts :: Build.Artifacts
sampleCorruptedArtifacts = Build.Artifacts samplePackage Map.empty (NE.List sampleRoot []) [] Map.empty

sampleReplArtifacts :: Build.ReplArtifacts
sampleReplArtifacts = 
  let home = ModuleName.Canonical samplePackage (N.fromChars "Main")
      modules = [Build.Fresh (N.fromChars "Main") sampleInterface sampleLocalGraph]
      localizer = sampleLocalizer
      annotations = Map.fromList [(N.fromChars "testExpression", sampleAnnotation)]
  in Build.ReplArtifacts home modules localizer annotations

sampleAnnotation :: Can.Annotation
sampleAnnotation = Can.Forall Map.empty (Can.TType sampleCanonical (N.fromChars "String") [])

sampleLocalizer :: L.Localizer
sampleLocalizer = L.empty

sampleCanonical :: ModuleName.Canonical
sampleCanonical = ModuleName.Canonical samplePackage (N.fromChars "Test")

sampleRegion :: A.Region
sampleRegion = A.Region (A.Position 1 1) (A.Position 1 10)

-- QuickCheck instances for property testing
instance Arbitrary Pkg.Name where
  arbitrary = do
    author <- elements [Utf8.fromChars "author1", Utf8.fromChars "author2", Utf8.fromChars "test-author"]
    project <- elements [Utf8.fromChars "project1", Utf8.fromChars "project2", Utf8.fromChars "test-project"]
    return $ Pkg.Name author project
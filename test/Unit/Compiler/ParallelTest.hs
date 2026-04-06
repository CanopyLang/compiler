{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Compiler.Parallel module.
--
-- Tests the pure helper functions exported by the parallel compilation
-- orchestrator: dependency graph merging, root detection, and compile
-- error extraction. These functions are the pure core of the build
-- pipeline and can be validated without any IO or compiler setup.
--
-- @since 0.19.1
module Unit.Compiler.ParallelTest (tests) where

import qualified AST.Optimized as Opt
import qualified Build.Artifacts as Build
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.NonEmptyList as NE
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Compiler.Parallel
  ( detectRoots,
    extractCompileErrors,
    mergeGraphs,
  )
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Exit
import qualified Reporting.Diagnostic as Diag
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Compiler.Parallel Tests"
    [ testExtractCompileErrors,
      testMergeGraphs,
      testDetectRoots
    ]

-- EXTRACT COMPILE ERRORS

testExtractCompileErrors :: TestTree
testExtractCompileErrors =
  testGroup
    "extractCompileErrors"
    [ testCase "BuildCannotCompile yields exactly one error" $
        length (extractCompileErrors (Exit.BuildCannotCompile singleError)) @?= 1,
      testCase "BuildMultipleErrors with two errors yields two" $
        length (extractCompileErrors (Exit.BuildMultipleErrors [singleError, anotherError])) @?= 2,
      testCase "BuildMultipleErrors with empty list yields empty" $
        length (extractCompileErrors (Exit.BuildMultipleErrors [])) @?= 0,
      testCase "BuildProjectNotFound yields empty list" $
        length (extractCompileErrors (Exit.BuildProjectNotFound "/some/path")) @?= 0,
      testCase "BuildInvalidOutline yields empty list" $
        length (extractCompileErrors (Exit.BuildInvalidOutline "bad outline")) @?= 0,
      testCase "BuildDependencyError yields empty list" $
        length (extractCompileErrors (Exit.BuildDependencyError "dep error")) @?= 0,
      testCase "BuildBadArgs yields empty list" $
        length (extractCompileErrors (Exit.BuildBadArgs "bad args")) @?= 0,
      testCase "BuildFileTooLarge yields empty list" $
        length (extractCompileErrors (Exit.BuildFileTooLarge "/big/file" 2000000 1000000)) @?= 0,
      testCase "BuildMultipleErrors length is preserved for five errors" $
        length (extractCompileErrors (Exit.BuildMultipleErrors (replicate 5 singleError))) @?= 5,
      testCase "BuildCannotCompile wrapping module not found shows correct path" $
        fmap show (Maybe.listToMaybe (extractCompileErrors (Exit.BuildCannotCompile (Exit.CompileModuleNotFound "Missing.can"))))
          @?= Just (show (Exit.CompileModuleNotFound "Missing.can")),
      testCase "BuildCannotCompile wrapping timeout shows correct path" $
        fmap show (Maybe.listToMaybe (extractCompileErrors (Exit.BuildCannotCompile (Exit.CompileTimeoutError "/slow.can"))))
          @?= Just (show (Exit.CompileTimeoutError "/slow.can")),
      testCase "BuildMultipleErrors head matches first error" $
        fmap show (Maybe.listToMaybe (extractCompileErrors (Exit.BuildMultipleErrors [singleError, anotherError])))
          @?= Just (show singleError)
    ]

-- | A parse-phase compile error for Main.can.
singleError :: Exit.CompileError
singleError =
  Exit.CompileError
    "src/Main.can"
    [Diag.stringToDiagnostic Diag.PhaseParse "SYNTAX ERROR" "unexpected token"]

-- | A type-phase compile error for Utils.can.
anotherError :: Exit.CompileError
anotherError =
  Exit.CompileError
    "src/Utils.can"
    [Diag.stringToDiagnostic Diag.PhaseType "TYPE ERROR" "type mismatch"]

-- MERGE GRAPHS

testMergeGraphs :: TestTree
testMergeGraphs =
  testGroup
    "mergeGraphs"
    [ testCase "merging empty local graph list returns empty graph" $
        show (mergeGraphs Opt.empty []) @?= show Opt.empty,
      testCase "merging one empty local graph preserves base graph" $
        show (mergeGraphs Opt.empty [emptyLocalGraph]) @?= show Opt.empty,
      testCase "merging three empty local graphs preserves base graph" $
        show (mergeGraphs Opt.empty (replicate 3 emptyLocalGraph))
          @?= show Opt.empty,
      testCase "merging is associative for empty local graphs" $
        show (mergeGraphs (mergeGraphs Opt.empty [emptyLocalGraph]) [emptyLocalGraph])
          @?= show (mergeGraphs Opt.empty [emptyLocalGraph, emptyLocalGraph])
    ]

-- | An empty local graph with no main, no nodes, no fields, no locations.
emptyLocalGraph :: Opt.LocalGraph
emptyLocalGraph =
  Opt.LocalGraph
    { Opt._l_main = Nothing,
      Opt._l_nodes = Map.empty,
      Opt._l_fields = Map.empty,
      Opt._l_sourceLocations = Map.empty
    }

-- DETECT ROOTS

testDetectRoots :: TestTree
testDetectRoots =
  testGroup
    "detectRoots"
    [ testCase "empty module list produces a non-empty root list of length 1" $
        neLength (detectRoots []) @?= 1,
      testCase "empty module list produces Inside fallback root" $
        isInsideRoot (neHead (detectRoots [])) @?= True,
      testCase "empty module list fallback names Main" $
        insideRootName (neHead (detectRoots [])) @?= Just mainModuleName,
      testCase "single Fresh module without main produces Outside root" $
        isOutsideRoot (neHead (detectRoots [freshModuleNoMain])) @?= True,
      testCase "single Fresh module produces single root" $
        neLength (detectRoots [freshModuleNoMain]) @?= 1,
      testCase "multiple modules without main uses head module as root" $
        isOutsideRoot (neHead (detectRoots [freshModuleNoMain, anotherFreshModule])) @?= True,
      testCase "multiple modules without main produce a single root" $
        neLength (detectRoots [freshModuleNoMain, anotherFreshModule]) @?= 1
    ]

-- | Extract the head element from a NonEmptyList.
neHead :: NE.List a -> a
neHead (NE.List x _) = x

-- | Compute the total length of a NonEmptyList.
neLength :: NE.List a -> Int
neLength (NE.List _ xs) = 1 + length xs

-- | Return True if this is an Inside root.
isInsideRoot :: Build.Root -> Bool
isInsideRoot (Build.Inside _) = True
isInsideRoot _ = False

-- | Return True if this is an Outside root.
isOutsideRoot :: Build.Root -> Bool
isOutsideRoot (Build.Outside _ _ _) = True
isOutsideRoot _ = False

-- | Extract the module name from an Inside root.
insideRootName :: Build.Root -> Maybe ModuleName.Raw
insideRootName (Build.Inside n) = Just n
insideRootName _ = Nothing

-- | The module name "Main".
mainModuleName :: ModuleName.Raw
mainModuleName = Name.fromChars "Main"

-- | The module name "Utils".
utilsModuleName :: ModuleName.Raw
utilsModuleName = Name.fromChars "Utils"

-- | A Fresh module for Main without a main function.
freshModuleNoMain :: Build.Module
freshModuleNoMain =
  Build.Fresh mainModuleName fakeInterface emptyLocalGraph

-- | A Fresh module for Utils without a main function.
anotherFreshModule :: Build.Module
anotherFreshModule =
  Build.Fresh utilsModuleName fakeInterface emptyLocalGraph

-- | Minimal interface placeholder with all empty fields.
--
-- Constructed with Pkg.core as the home package and empty maps for all
-- exported names. Only valid for structural tests that do not inspect
-- interface contents.
fakeInterface :: Interface.Interface
fakeInterface =
  Interface.Interface Pkg.core Map.empty Map.empty Map.empty Map.empty Map.empty Map.empty []

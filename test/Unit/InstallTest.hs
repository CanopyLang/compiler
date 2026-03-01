{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Install module.
--
-- Tests the main package installation command implementation including
-- argument processing, change tracking types, and display formatting.
-- All tests verify exact values or meaningful behavioral properties.
--
-- @since 0.19.1
module Unit.InstallTest (tests) where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Lens ((^.))
import Install (Args (..))
import qualified Install.Types as Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

-- | All unit tests for Install module functionality.
tests :: TestTree
tests =
  testGroup
    "Install Tests"
    [ testArgsConstruction,
      testArgsEquality,
      testArgsParsing,
      testChangeType,
      testWidthsType,
      testChangeDocsType,
      testExistingDepType
    ]

-- | Test Args data type construction and Show output.
testArgsConstruction :: TestTree
testArgsConstruction =
  testGroup
    "Args construction"
    [ testCase "NoArgs show output" $
        show NoArgs @?= "NoArgs",
      testCase "Install show output starts with Install" $
        take 7 (show (Install Pkg.core)) @?= "Install",
      testCase "Install carries exact package reference" $
        extractPackage (Install Pkg.json) @?= Just Pkg.json,
      testCase "NoArgs carries no package" $
        extractPackage NoArgs @?= Nothing
    ]

-- | Test Args equality with distinct packages.
testArgsEquality :: TestTree
testArgsEquality =
  testGroup
    "Args equality"
    [ testCase "Install with different packages are not equal" $
        Install Pkg.core == Install Pkg.json @?= False,
      testCase "NoArgs is not equal to Install" $
        NoArgs == Install Pkg.core @?= False,
      testCase "Install with same package are equal" $
        Install Pkg.core == Install Pkg.core @?= True
    ]

-- | Test Args practical extraction scenarios.
testArgsParsing :: TestTree
testArgsParsing =
  testGroup
    "Args extraction"
    [ testCase "extractPackage returns package from Install" $ do
        let pkg = Pkg.browser
        extractPackage (Install pkg) @?= Just pkg,
      testCase "isNoArgs true for NoArgs" $
        isNoArgs NoArgs @?= True,
      testCase "isNoArgs false for Install" $
        isNoArgs (Install Pkg.core) @?= False
    ]

-- | Test Change type constructor behavior.
testChangeType :: TestTree
testChangeType =
  testGroup
    "Change type"
    [ testCase "Insert carries version" $ do
        let change = Types.Insert Version.one
        case change of
          Types.Insert v -> v @?= Version.one
          _ -> error "unreachable",
      testCase "Change carries old and new versions" $ do
        let v1 = Version.one
            v2 = Version.one
            change = Types.Change v1 v2
        case change of
          Types.Change old new -> do
            old @?= v1
            new @?= v2
          _ -> error "unreachable",
      testCase "Remove carries version" $ do
        let change = Types.Remove Version.one
        case change of
          Types.Remove v -> v @?= Version.one
          _ -> error "unreachable",
      testCase "Insert and Remove are not equal" $
        Types.Insert Version.one == Types.Remove Version.one @?= False
    ]

-- | Test Widths type lens access.
testWidthsType :: TestTree
testWidthsType =
  testGroup
    "Widths type"
    [ testCase "Widths stores exact column values" $ do
        let widths = Types.Widths 10 15 20
        widths ^. Types.nameWidth @?= 10
        widths ^. Types.leftWidth @?= 15
        widths ^. Types.rightWidth @?= 20,
      testCase "Widths equality is structural" $
        Types.Widths 10 15 20 == Types.Widths 10 15 20 @?= True,
      testCase "Widths with different values are not equal" $
        Types.Widths 10 15 20 == Types.Widths 10 15 21 @?= False
    ]

-- | Test ChangeDocs type lens access.
testChangeDocsType :: TestTree
testChangeDocsType =
  testGroup
    "ChangeDocs type"
    [ testCase "empty ChangeDocs has zero-length lists" $ do
        let docs = Types.ChangeDocs [] [] []
        length (docs ^. Types.docInserts) @?= 0
        length (docs ^. Types.docChanges) @?= 0
        length (docs ^. Types.docRemoves) @?= 0
    ]

-- | Test ExistingDep type distinguishes dependency contexts.
testExistingDepType :: TestTree
testExistingDepType =
  testGroup
    "ExistingDep type"
    [ testCase "IndirectDep carries version" $ do
        let dep = Types.IndirectDep Version.one
        case dep of
          Types.IndirectDep v -> v @?= Version.one
          _ -> error "unreachable",
      testCase "TestDirectDep carries version" $ do
        let dep = Types.TestDirectDep Version.one
        case dep of
          Types.TestDirectDep v -> v @?= Version.one
          _ -> error "unreachable",
      testCase "different dep contexts are not equal" $
        Types.IndirectDep Version.one == Types.TestDirectDep Version.one @?= False,
      testCase "ExistingDep show includes constructor name" $ do
        let shown = show (Types.IndirectDep Version.one)
        take 11 shown @?= "IndirectDep"
    ]

-- | Extract package from Args.
extractPackage :: Args -> Maybe Pkg.Name
extractPackage (Install pkg) = Just pkg
extractPackage NoArgs = Nothing

-- | Check if Args is NoArgs.
isNoArgs :: Args -> Bool
isNoArgs NoArgs = True
isNoArgs (Install _) = False

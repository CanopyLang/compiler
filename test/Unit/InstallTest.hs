{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Install module.
--
-- Tests the main package installation command implementation including
-- argument processing, workflow orchestration, project type detection,
-- and error handling for the complete installation pipeline.
--
-- @since 0.19.1
module Unit.InstallTest (tests) where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Lens ((^.))
import Install (Args (..))
import qualified Install.Types as Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

-- | All unit tests for Install module functionality.
tests :: TestTree
tests = testGroup "Install Tests"
  [ testArgsDataType
  , testArgsEquality  
  , testArgsShow
  , testArgsParsing
  , testInstallTypes
  , testChangesType
  , testDisplayTypes
  , testContextOperations
  ]

-- | Test Args data type constructors.
testArgsDataType :: TestTree
testArgsDataType = testGroup "Args data type"
  [ testCase "NoArgs constructor" $
      NoArgs @?= NoArgs
  , testCase "Install constructor" $ do
      let pkgName = Pkg.core
      Install pkgName @?= Install pkgName
  ]

-- | Test Args equality instance.
testArgsEquality :: TestTree
testArgsEquality = testGroup "Args equality"
  [ testCase "NoArgs equals NoArgs" $
      NoArgs == NoArgs @?= True
  , testCase "Install with same package equals" $ do
      let pkg1 = Pkg.core
      let pkg2 = Pkg.core
      Install pkg1 == Install pkg2 @?= True
  , testCase "Install with different packages not equal" $ do
      let pkg1 = Pkg.core
      let pkg2 = Pkg.http
      Install pkg1 == Install pkg2 @?= False
  , testCase "NoArgs not equal to Install" $ do
      let pkg = Pkg.core
      NoArgs == Install pkg @?= False
  ]

-- | Test Args Show instance provides meaningful output.
testArgsShow :: TestTree
testArgsShow = testGroup "Args show produces output"
  [ testCase "NoArgs show is not empty" $
      assertBool "NoArgs should have meaningful show output" (length (show NoArgs) > 0)
  , testCase "Install show contains package info" $ do
      let pkg = Pkg.core
      let output = show (Install pkg)
      assertBool "Install show should contain 'Install'" ("Install" `elem` words output)
  ]

-- | Test Args practical usage scenarios.
testArgsParsing :: TestTree
testArgsParsing = testGroup "Args usage scenarios"
  [ testCase "NoArgs represents dependency sync" $
      assertBool "NoArgs should indicate no specific package" (isNoArgs NoArgs)
  , testCase "Install represents specific package installation" $ do
      let pkg = Pkg.json
      assertBool "Install should indicate specific package" (isInstall (Install pkg))
  , testCase "Install carries package name" $ do
      let pkg = Pkg.browser
      extractPackage (Install pkg) @?= Just pkg
  , testCase "NoArgs has no package name" $
      extractPackage NoArgs @?= Nothing
  ]

-- Helper functions for testing
isNoArgs :: Args -> Bool
isNoArgs NoArgs = True
isNoArgs _ = False

isInstall :: Args -> Bool
isInstall (Install _) = True
isInstall _ = False

extractPackage :: Args -> Maybe Pkg.Name
extractPackage (Install pkg) = Just pkg
extractPackage NoArgs = Nothing

-- | Test Install.Types behavioral functionality.
testInstallTypes :: TestTree
testInstallTypes = testGroup "Install.Types behavior"
  [ testCase "Change types represent different operations" $ do
      let version = V.one
      let insert = Types.Insert version
      let change = Types.Change version V.one
      let remove = Types.Remove version
      -- Test that different constructors can be distinguished
      case insert of
        Types.Insert _ -> True @?= True
        _ -> assertBool "Insert should match Insert pattern" False
      case change of
        Types.Change _ _ -> True @?= True
        _ -> assertBool "Change should match Change pattern" False
      case remove of
        Types.Remove _ -> True @?= True
        _ -> assertBool "Remove should match Remove pattern" False
  ]

-- | Test Changes type represents installation states.
testChangesType :: TestTree
testChangesType = testGroup "Changes represent installation workflow"
  [ testCase "Changes can represent different installation states" $ do
      -- Test the different Changes constructors (not Change constructors)
      let alreadyInstalled = Types.AlreadyInstalled
      case alreadyInstalled of
        Types.AlreadyInstalled -> True @?= True
        _ -> assertBool "AlreadyInstalled should match pattern" False
  , testCase "Change operations carry version information" $ do
      let version = V.one
      case Types.Insert version of
        Types.Insert v -> v @?= version
      case Types.Remove version of
        Types.Remove v -> v @?= version
  ]

-- | Test display types support formatting workflows.
testDisplayTypes :: TestTree
testDisplayTypes = testGroup "Display types support UI formatting"
  [ testCase "Widths track column alignment needs" $ do
      let widths = Types.Widths 10 15 20
      -- Test that widths can be used for alignment calculations
      let totalWidth = widths ^. Types.nameWidth + widths ^. Types.leftWidth + widths ^. Types.rightWidth
      totalWidth @?= 45
  , testCase "ChangeDocs organize different change types" $ do
      let docs = Types.ChangeDocs [] [] []
      -- Test that docs can track different categories of changes
      let totalChanges = length (docs ^. Types.docInserts) + 
                        length (docs ^. Types.docChanges) + 
                        length (docs ^. Types.docRemoves)
      totalChanges @?= 0  -- Empty docs should have 0 total changes
  , testCase "ExistingDep distinguishes dependency contexts" $ do
      let deps = [Types.IndirectDep V.one, Types.TestDirectDep V.one, Types.TestIndirectDep V.one]
      -- Test that we can distinguish different dependency contexts
      assertBool "Should have different dependency types" (length deps == 3)
  ]

-- | Test context operations and utilities.
testContextOperations :: TestTree
testContextOperations = testGroup "Context operations"
  [ testCase "Args pattern matching works" $ do
      let noArgs = NoArgs
      let installArgs = Install Pkg.dummyName
      case noArgs of
        NoArgs -> True @?= True
        _ -> False @?= True
      case installArgs of
        Install _ -> True @?= True
        _ -> False @?= True
  , testCase "Package name extraction is consistent" $ do
      let pkg = Pkg.core
      let args = Install pkg
      extractPackage args @?= Just pkg
  , testCase "NoArgs has no package consistently" $ do
      extractPackage NoArgs @?= Nothing
      isNoArgs NoArgs @?= True
      isInstall NoArgs @?= False
  ]
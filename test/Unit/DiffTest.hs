{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for the Diff system.
--
-- Tests the API difference classification, magnitude computation,
-- version bump suggestion, and output formatting. Uses concrete
-- 'Documentation' values to exercise the actual diff logic rather
-- than testing type-level properties.
--
-- @since 0.19.1
module Unit.DiffTest (tests) where

import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Docs as Docs
import qualified Canopy.Magnitude as Magnitude
import Canopy.Version (Version (..))
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Deps.Diff (Changes (..), ModuleChanges (..), PackageChanges (..))
import qualified Deps.Diff as Diff
import qualified Json.String as Json
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Diff module.
tests :: TestTree
tests =
  Test.testGroup
    "Diff Tests"
    [ magnitudeTests,
      classificationTests,
      versionBumpTests,
      moduleChangesTests
    ]

-- | Tests for magnitude computation from PackageChanges.
magnitudeTests :: TestTree
magnitudeTests =
  Test.testGroup
    "Magnitude"
    [ Test.testCase "no changes yields PATCH" $
        Diff.toMagnitude noChanges @?= Magnitude.PATCH,
      Test.testCase "added module yields MINOR" $
        Diff.toMagnitude addedModuleChanges @?= Magnitude.MINOR,
      Test.testCase "removed module yields MAJOR" $
        Diff.toMagnitude removedModuleChanges @?= Magnitude.MAJOR,
      Test.testCase "added and removed yields MAJOR" $
        Diff.toMagnitude addedAndRemovedChanges @?= Magnitude.MAJOR
    ]

-- | Tests for the diff classification of actual documentation.
classificationTests :: TestTree
classificationTests =
  Test.testGroup
    "Classification"
    [ Test.testCase "identical docs yield no changes" $ do
        let result = Diff.diff singleModuleDocs singleModuleDocs
        _modulesAdded result @?= []
        _modulesRemoved result @?= []
        Map.null (_modulesChanged result) @?= True,
      Test.testCase "adding a module is detected" $ do
        let result = Diff.diff singleModuleDocs twoModuleDocs
        _modulesAdded result @?= [listModuleName],
      Test.testCase "removing a module is detected" $ do
        let result = Diff.diff twoModuleDocs singleModuleDocs
        _modulesRemoved result @?= [listModuleName],
      Test.testCase "adding a value to a module is detected" $ do
        let result = Diff.diff singleModuleDocs singleModuleWithExtraDocs
        -- Changed module should appear
        Map.member basicsModuleName (_modulesChanged result) @?= True
    ]

-- | Tests for version bump computation.
versionBumpTests :: TestTree
versionBumpTests =
  Test.testGroup
    "Version Bump"
    [ Test.testCase "PATCH bump from 1.0.0" $
        Diff.bump noChanges (Version 1 0 0) @?= Version 1 0 1,
      Test.testCase "MINOR bump from 1.0.0" $
        Diff.bump addedModuleChanges (Version 1 0 0) @?= Version 1 1 0,
      Test.testCase "MAJOR bump from 1.0.0" $
        Diff.bump removedModuleChanges (Version 1 0 0) @?= Version 2 0 0,
      Test.testCase "PATCH bump from 2.3.5" $
        Diff.bump noChanges (Version 2 3 5) @?= Version 2 3 6,
      Test.testCase "MINOR bump from 2.3.5" $
        Diff.bump addedModuleChanges (Version 2 3 5) @?= Version 2 4 0,
      Test.testCase "MAJOR bump from 2.3.5" $
        Diff.bump removedModuleChanges (Version 2 3 5) @?= Version 3 0 0
    ]

-- | Tests for module-level change magnitude.
moduleChangesTests :: TestTree
moduleChangesTests =
  Test.testGroup
    "Module Changes"
    [ Test.testCase "empty module changes are PATCH" $
        Diff.moduleChangeMagnitude emptyModuleChanges @?= Magnitude.PATCH,
      Test.testCase "added value is MINOR" $
        Diff.moduleChangeMagnitude addedValueModuleChanges @?= Magnitude.MINOR,
      Test.testCase "removed value is MAJOR" $
        Diff.moduleChangeMagnitude removedValueModuleChanges @?= Magnitude.MAJOR,
      Test.testCase "changed value type is MAJOR" $
        Diff.moduleChangeMagnitude changedValueModuleChanges @?= Magnitude.MAJOR
    ]

-- HELPERS: Test data construction

emptyComment :: Json.String
emptyComment = Json.fromChars ""

basicsModuleName :: Name.Name
basicsModuleName = Name.fromChars "Basics"

listModuleName :: Name.Name
listModuleName = Name.fromChars "List"

intType :: Type.Type
intType = Type.Type (Name.fromChars "Int") []

stringType :: Type.Type
stringType = Type.Type (Name.fromChars "String") []

boolType :: Type.Type
boolType = Type.Type (Name.fromChars "Bool") []

-- | A module with a single value export.
basicsModule :: Docs.Module
basicsModule =
  Docs.Module
    basicsModuleName
    emptyComment
    Map.empty
    Map.empty
    (Map.singleton (Name.fromChars "toFloat") (Docs.Value emptyComment (Type.Lambda intType (Type.Type (Name.fromChars "Float") []))))
    Map.empty

-- | A module with an extra value compared to basicsModule.
basicsModuleWithExtra :: Docs.Module
basicsModuleWithExtra =
  Docs.Module
    basicsModuleName
    emptyComment
    Map.empty
    Map.empty
    ( Map.fromList
        [ (Name.fromChars "toFloat", Docs.Value emptyComment (Type.Lambda intType (Type.Type (Name.fromChars "Float") []))),
          (Name.fromChars "toString", Docs.Value emptyComment (Type.Lambda intType stringType))
        ]
    )
    Map.empty

-- | A simple list module.
listModule :: Docs.Module
listModule =
  Docs.Module
    listModuleName
    emptyComment
    Map.empty
    Map.empty
    (Map.singleton (Name.fromChars "length") (Docs.Value emptyComment (Type.Lambda (Type.Type (Name.fromChars "List") [Type.Var (Name.fromChars "a")]) intType)))
    Map.empty

-- | Documentation with one module.
singleModuleDocs :: Docs.Documentation
singleModuleDocs =
  Map.singleton basicsModuleName basicsModule

-- | Documentation with one module and an extra value.
singleModuleWithExtraDocs :: Docs.Documentation
singleModuleWithExtraDocs =
  Map.singleton basicsModuleName basicsModuleWithExtra

-- | Documentation with two modules.
twoModuleDocs :: Docs.Documentation
twoModuleDocs =
  Map.fromList
    [ (basicsModuleName, basicsModule),
      (listModuleName, listModule)
    ]

-- PackageChanges test fixtures

noChanges :: PackageChanges
noChanges = PackageChanges [] Map.empty []

addedModuleChanges :: PackageChanges
addedModuleChanges = PackageChanges [listModuleName] Map.empty []

removedModuleChanges :: PackageChanges
removedModuleChanges = PackageChanges [] Map.empty [listModuleName]

addedAndRemovedChanges :: PackageChanges
addedAndRemovedChanges = PackageChanges [listModuleName] Map.empty [basicsModuleName]

-- ModuleChanges test fixtures

emptyChanges :: Changes Name.Name a
emptyChanges = Changes Map.empty Map.empty Map.empty

emptyModuleChanges :: ModuleChanges
emptyModuleChanges = ModuleChanges emptyChanges emptyChanges emptyChanges emptyChanges

addedValueModuleChanges :: ModuleChanges
addedValueModuleChanges =
  ModuleChanges
    emptyChanges
    emptyChanges
    (Changes (Map.singleton (Name.fromChars "newFunc") (Docs.Value emptyComment boolType)) Map.empty Map.empty)
    emptyChanges

removedValueModuleChanges :: ModuleChanges
removedValueModuleChanges =
  ModuleChanges
    emptyChanges
    emptyChanges
    (Changes Map.empty Map.empty (Map.singleton (Name.fromChars "oldFunc") (Docs.Value emptyComment boolType)))
    emptyChanges

changedValueModuleChanges :: ModuleChanges
changedValueModuleChanges =
  ModuleChanges
    emptyChanges
    emptyChanges
    (Changes Map.empty (Map.singleton (Name.fromChars "func") (Docs.Value emptyComment intType, Docs.Value emptyComment stringType)) Map.empty)
    emptyChanges

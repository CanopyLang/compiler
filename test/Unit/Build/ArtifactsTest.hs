{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Build.Artifacts module.
--
-- Tests lens get/set for all fields, Show instances for Root, Module, and
-- Artifacts, and constructor creation for the pure artifact types used in
-- the query-based compiler.
--
-- @since 0.19.1
module Unit.Build.ArtifactsTest (tests) where

import qualified AST.Optimized as Opt
import qualified Build.Artifacts as Artifacts
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.NonEmptyList as NEL
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens ((&), (.~), (^.))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Generate.JavaScript as JS
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Build.Artifacts Tests"
    [ testRootConstructors,
      testModuleConstructors,
      testArtifactsConstruction,
      testArtifactsLensGet,
      testArtifactsLensSet
    ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | A minimal empty LocalGraph with no main, nodes, fields, or source locs.
emptyLocalGraph :: Opt.LocalGraph
emptyLocalGraph =
  Opt.LocalGraph Nothing Map.empty Map.empty Map.empty

-- | A minimal empty GlobalGraph.
emptyGlobalGraph :: Opt.GlobalGraph
emptyGlobalGraph = Opt.empty

-- | A minimal Interface for use in Root/Module constructors.
emptyInterface :: Interface.Interface
emptyInterface =
  Interface.Interface
    { Interface._home = Pkg.core,
      Interface._values = Map.empty,
      Interface._unions = Map.empty,
      Interface._aliases = Map.empty,
      Interface._binops = Map.empty,
      Interface._ifaceGuards = Map.empty,
      Interface._ifaceAbilities = Map.empty,
      Interface._ifaceImpls = []
    }

-- | Sample raw module name (ModuleName.Raw = Name.Name).
rawName :: ModuleName.Raw
rawName = Name.fromChars "Main"

-- | Sample canonical module name.
canonicalName :: ModuleName.Canonical
canonicalName = ModuleName.Canonical Pkg.core (Name.fromChars "Main")

-- | A sample FFIInfo for testing the ffiInfo map lens.
sampleFFIInfo :: JS.FFIInfo
sampleFFIInfo =
  JS.FFIInfo
    { JS._ffiFilePath = "src/ffi.js",
      JS._ffiContent = Text.pack "export function foo() {}",
      JS._ffiAlias = Name.fromChars "ffi"
    }

-- | A minimal Artifacts value for testing lenses.
sampleArtifacts :: Artifacts.Artifacts
sampleArtifacts =
  Artifacts.Artifacts
    { Artifacts._artifactsName = Pkg.core,
      Artifacts._artifactsDeps = Map.empty,
      Artifacts._artifactsRoots = NEL.singleton (Artifacts.Inside rawName),
      Artifacts._artifactsModules = [],
      Artifacts._artifactsFFIInfo = Map.empty,
      Artifacts._artifactsGlobalGraph = emptyGlobalGraph,
      Artifacts._artifactsLazyModules = Set.empty
    }

-- ---------------------------------------------------------------------------
-- Root constructor tests
-- ---------------------------------------------------------------------------

testRootConstructors :: TestTree
testRootConstructors =
  testGroup
    "Root constructors"
    [ testCase "Inside show produces exact expected string" $
        show (Artifacts.Inside rawName) @?= "Inside Main",
      testCase "Inside constructed with Utils produces exact show" $
        show (Artifacts.Inside (Name.fromChars "Utils")) @?= "Inside Utils",
      testCase "Outside show includes constructor name" $
        take 7 (show (Artifacts.Outside rawName emptyInterface emptyLocalGraph)) @?= "Outside"
    ]

-- ---------------------------------------------------------------------------
-- Module constructor tests
-- ---------------------------------------------------------------------------

testModuleConstructors :: TestTree
testModuleConstructors =
  testGroup
    "Module constructors"
    [ testCase "Fresh show includes constructor name" $
        take 5 (show (Artifacts.Fresh rawName emptyInterface emptyLocalGraph)) @?= "Fresh"
    ]

-- ---------------------------------------------------------------------------
-- Artifacts construction tests
-- ---------------------------------------------------------------------------

testArtifactsConstruction :: TestTree
testArtifactsConstruction =
  testGroup
    "Artifacts construction"
    [ testCase "constructed name field matches Pkg.core show" $
        show (Artifacts._artifactsName sampleArtifacts) @?= show Pkg.core,
      testCase "constructed deps field is empty" $
        Map.size (Artifacts._artifactsDeps sampleArtifacts) @?= 0,
      testCase "constructed roots field has exactly one element" $
        length (NEL.toList (Artifacts._artifactsRoots sampleArtifacts)) @?= 1,
      testCase "constructed modules field is empty" $
        length (Artifacts._artifactsModules sampleArtifacts) @?= 0,
      testCase "constructed ffi info field is empty" $
        Map.size (Artifacts._artifactsFFIInfo sampleArtifacts) @?= 0,
      testCase "constructed lazy modules field is empty" $
        Set.size (Artifacts._artifactsLazyModules sampleArtifacts) @?= 0
    ]

-- ---------------------------------------------------------------------------
-- Lens get tests
-- ---------------------------------------------------------------------------

testArtifactsLensGet :: TestTree
testArtifactsLensGet =
  testGroup
    "Artifacts lens get"
    [ testCase "artifactsName lens retrieves package name" $
        show (sampleArtifacts ^. Artifacts.artifactsName) @?= show Pkg.core,
      testCase "artifactsDeps lens retrieves empty deps map" $
        Map.size (sampleArtifacts ^. Artifacts.artifactsDeps) @?= 0,
      testCase "artifactsRoots lens retrieves singleton roots list" $
        length (NEL.toList (sampleArtifacts ^. Artifacts.artifactsRoots)) @?= 1,
      testCase "artifactsModules lens retrieves empty modules list" $
        length (sampleArtifacts ^. Artifacts.artifactsModules) @?= 0,
      testCase "artifactsFFIInfo lens retrieves empty ffi info map" $
        Map.size (sampleArtifacts ^. Artifacts.artifactsFFIInfo) @?= 0,
      testCase "artifactsGlobalGraph lens retrieves global graph" $
        show (sampleArtifacts ^. Artifacts.artifactsGlobalGraph)
          @?= show emptyGlobalGraph,
      testCase "artifactsLazyModules lens retrieves empty lazy modules set" $
        Set.size (sampleArtifacts ^. Artifacts.artifactsLazyModules) @?= 0
    ]

-- ---------------------------------------------------------------------------
-- Lens set tests
-- ---------------------------------------------------------------------------

testArtifactsLensSet :: TestTree
testArtifactsLensSet =
  testGroup
    "Artifacts lens set"
    [ testCase "artifactsName set replaces package name with dummyName" $
        let updated = sampleArtifacts & Artifacts.artifactsName .~ Pkg.dummyName
         in show (updated ^. Artifacts.artifactsName) @?= show Pkg.dummyName,
      testCase "artifactsDeps set replaces deps map with singleton" $
        let dep = Interface.Public emptyInterface
            updated = sampleArtifacts & Artifacts.artifactsDeps .~ Map.singleton canonicalName dep
         in Map.size (updated ^. Artifacts.artifactsDeps) @?= 1,
      testCase "artifactsModules set replaces modules list with singleton" $
        let freshMod = Artifacts.Fresh rawName emptyInterface emptyLocalGraph
            updated = sampleArtifacts & Artifacts.artifactsModules .~ [freshMod]
         in length (updated ^. Artifacts.artifactsModules) @?= 1,
      testCase "artifactsFFIInfo set replaces ffi info map with singleton" $
        let updated = sampleArtifacts & Artifacts.artifactsFFIInfo .~ Map.singleton "ffi-module" sampleFFIInfo
         in Map.size (updated ^. Artifacts.artifactsFFIInfo) @?= 1,
      testCase "artifactsLazyModules set replaces lazy modules set with singleton" $
        let updated = sampleArtifacts & Artifacts.artifactsLazyModules .~ Set.singleton canonicalName
         in Set.size (updated ^. Artifacts.artifactsLazyModules) @?= 1,
      testCase "artifactsGlobalGraph set round-trips through empty graph" $
        let updated = sampleArtifacts & Artifacts.artifactsGlobalGraph .~ emptyGlobalGraph
         in show (updated ^. Artifacts.artifactsGlobalGraph) @?= show emptyGlobalGraph
    ]

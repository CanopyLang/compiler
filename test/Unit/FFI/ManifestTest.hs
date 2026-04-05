{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI.Manifest module.
--
-- Tests capability manifest collection and serialization, covering
-- collectCapabilities, collectCapabilitiesWithPackages, collectByPackage,
-- and JSON serialisation.
--
-- @since 0.19.1
module Unit.FFI.ManifestTest (tests) where

import qualified Data.Aeson as Json
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified FFI.Capability as Capability
import qualified FFI.Manifest as Manifest
import FFI.Types (BindingMode (..), JsFunctionName (..), PermissionName (..), ResourceName (..))
import FFI.Types (FFIType (..))
import qualified Foreign.FFI as FFI
import Test.Tasty
import Test.Tasty.HUnit

-- HELPERS

-- | Minimal JSDocFunction with no capabilities.
baseFunc :: FFI.JSDocFunction
baseFunc =
  FFI.JSDocFunction
    { FFI.jsDocFuncName = JsFunctionName "testFunc",
      FFI.jsDocFuncType = FFIInt,
      FFI.jsDocFuncDescription = Nothing,
      FFI.jsDocFuncParams = [],
      FFI.jsDocFuncThrows = [],
      FFI.jsDocFuncCapabilities = Nothing,
      FFI.jsDocFuncFile = "test.js",
      FFI.jsDocFuncBindMode = FunctionCall,
      FFI.jsDocFuncCanopyName = Nothing
    }

-- | Build a JSDocFunction with the given name and capability.
funcWithCap :: Text.Text -> Capability.CapabilityConstraint -> FFI.JSDocFunction
funcWithCap name cap =
  baseFunc
    { FFI.jsDocFuncName = JsFunctionName name,
      FFI.jsDocFuncCapabilities = Just cap
    }

-- | Build a JSDocFunction with the given name and no capability.
funcNamed :: Text.Text -> FFI.JSDocFunction
funcNamed name = baseFunc {FFI.jsDocFuncName = JsFunctionName name}

tests :: TestTree
tests =
  testGroup
    "FFI.Manifest Tests"
    [ testEmptyInput,
      testSingleCapability,
      testMultipleFunctions,
      testDuplicateCapabilities,
      testCapabilityTypes,
      testPackageLevelGrouping,
      testCollectByPackage,
      testJsonRoundTrip,
      testJsonRoundTripModules,
      testJsonRoundTripByPackage,
      testMultiplePackages,
      testNestedMultipleConstraints,
      testAvailabilityInSets,
      testModuleConstraintOrdering,
      testCollectByPackageCapabilityContent
    ]

testEmptyInput :: TestTree
testEmptyInput =
  testGroup
    "empty input"
    [ testCase "empty module list produces empty manifest" $
        let m = Manifest.collectCapabilities []
         in do
              Manifest._manifestUserActivation m @?= False
              Set.size (Manifest._manifestPermissions m) @?= 0
              Set.size (Manifest._manifestInitializations m) @?= 0
              length (Manifest._manifestModules m) @?= 0,
      testCase "module with no FFI functions produces empty modules" $
        length (Manifest._manifestModules (Manifest.collectCapabilities [("MyModule", [])])) @?= 0,
      testCase "module with uncapped functions excluded" $
        length
          (Manifest._manifestModules
            (Manifest.collectCapabilities [("Mod", [funcNamed "foo", funcNamed "bar"])]))
          @?= 0,
      testCase "empty manifest has empty byPackage" $
        length (Manifest._manifestByPackage (Manifest.collectCapabilities [])) @?= 0
    ]

testSingleCapability :: TestTree
testSingleCapability =
  testGroup
    "single capability"
    [ testCase "permission appears in permissions set" $
        let fn = funcWithCap "doIt" (Capability.PermissionRequired (PermissionName "microphone"))
            m = Manifest.collectCapabilities [("Audio", [fn])]
         in Set.member "permission:microphone" (Manifest._manifestPermissions m) @?= True,
      testCase "init appears in initializations set" $
        let fn = funcWithCap "init" (Capability.InitializationRequired (ResourceName "AudioContext"))
            m = Manifest.collectCapabilities [("Audio", [fn])]
         in Set.member "init:AudioContext" (Manifest._manifestInitializations m) @?= True,
      testCase "user-activation sets flag to True" $
        let fn = funcWithCap "gesture" Capability.UserActivationRequired
            m = Manifest.collectCapabilities [("UI", [fn])]
         in Manifest._manifestUserActivation m @?= True,
      testCase "module with capability appears in modules list" $
        let fn = funcWithCap "doIt" (Capability.PermissionRequired (PermissionName "camera"))
            m = Manifest.collectCapabilities [("CamModule", [fn])]
         in length (Manifest._manifestModules m) @?= 1,
      testCase "module capability entry records correct module name" $
        let fn = funcWithCap "doIt" (Capability.PermissionRequired (PermissionName "camera"))
            m = Manifest.collectCapabilities [("CamModule", [fn])]
         in case Manifest._manifestModules m of
              [mc] -> Manifest._mcModuleName mc @?= "CamModule"
              other -> assertFailure ("expected 1 module, got " ++ show (length other)),
      testCase "function capability records function name" $
        let fn = funcWithCap "shoot" (Capability.PermissionRequired (PermissionName "camera"))
            m = Manifest.collectCapabilities [("Cam", [fn])]
         in case Manifest._manifestModules m of
              [mc] -> case Manifest._mcFunctions mc of
                [fc] -> Manifest._fcFunctionName fc @?= "shoot"
                other -> assertFailure ("expected 1 func, got " ++ show (length other))
              other -> assertFailure ("expected 1 module, got " ++ show (length other)),
      testCase "function capability records constraint text" $
        let fn = funcWithCap "doIt" (Capability.PermissionRequired (PermissionName "microphone"))
            m = Manifest.collectCapabilities [("Mod", [fn])]
         in case Manifest._manifestModules m of
              [mc] -> case Manifest._mcFunctions mc of
                [fc] -> Manifest._fcConstraints fc @?= ["permission:microphone"]
                other -> assertFailure ("expected 1 func, got " ++ show (length other))
              other -> assertFailure ("expected 1 module, got " ++ show (length other))
    ]

testMultipleFunctions :: TestTree
testMultipleFunctions =
  testGroup
    "multiple functions"
    [ testCase "two functions with caps produce two FunctionCapability entries" $
        let fn1 = funcWithCap "f1" (Capability.PermissionRequired (PermissionName "microphone"))
            fn2 = funcWithCap "f2" (Capability.PermissionRequired (PermissionName "camera"))
            m = Manifest.collectCapabilities [("Mod", [fn1, fn2])]
         in case Manifest._manifestModules m of
              [mc] -> length (Manifest._mcFunctions mc) @?= 2
              other -> assertFailure ("expected 1 module, got " ++ show (length other)),
      testCase "function without cap not included in module functions" $
        let fn1 = funcWithCap "f1" (Capability.PermissionRequired (PermissionName "microphone"))
            m = Manifest.collectCapabilities [("Mod", [fn1, funcNamed "plain"])]
         in case Manifest._manifestModules m of
              [mc] -> length (Manifest._mcFunctions mc) @?= 1
              other -> assertFailure ("expected 1 module, got " ++ show (length other)),
      testCase "two modules each with caps produce two entries" $
        let fn1 = funcWithCap "a" (Capability.PermissionRequired (PermissionName "microphone"))
            fn2 = funcWithCap "b" (Capability.PermissionRequired (PermissionName "camera"))
            m = Manifest.collectCapabilities [("ModA", [fn1]), ("ModB", [fn2])]
         in length (Manifest._manifestModules m) @?= 2,
      testCase "multiple distinct permissions are all collected" $
        let fn1 = funcWithCap "a" (Capability.PermissionRequired (PermissionName "microphone"))
            fn2 = funcWithCap "b" (Capability.PermissionRequired (PermissionName "camera"))
            m = Manifest.collectCapabilities [("A", [fn1]), ("B", [fn2])]
         in Set.size (Manifest._manifestPermissions m) @?= 2
    ]

testDuplicateCapabilities :: TestTree
testDuplicateCapabilities =
  testGroup
    "duplicate capabilities deduplication"
    [ testCase "same permission in two functions deduplicated in set" $
        let fn1 = funcWithCap "f1" (Capability.PermissionRequired (PermissionName "microphone"))
            fn2 = funcWithCap "f2" (Capability.PermissionRequired (PermissionName "microphone"))
            m = Manifest.collectCapabilities [("Mod", [fn1, fn2])]
         in Set.size (Manifest._manifestPermissions m) @?= 1,
      testCase "same init in two functions deduplicated" $
        let fn1 = funcWithCap "f1" (Capability.InitializationRequired (ResourceName "AudioContext"))
            fn2 = funcWithCap "f2" (Capability.InitializationRequired (ResourceName "AudioContext"))
            m = Manifest.collectCapabilities [("Mod", [fn1, fn2])]
         in Set.size (Manifest._manifestInitializations m) @?= 1
    ]

testCapabilityTypes :: TestTree
testCapabilityTypes =
  testGroup
    "capability type variants"
    [ testCase "AvailabilityRequired produces availability: prefix" $
        let fn = funcWithCap "f" (Capability.AvailabilityRequired "WebBluetooth")
            m = Manifest.collectCapabilities [("BT", [fn])]
         in case Manifest._manifestModules m of
              [mc] -> case Manifest._mcFunctions mc of
                [fc] -> Manifest._fcConstraints fc @?= ["availability:WebBluetooth"]
                other -> assertFailure ("expected 1 func, got " ++ show (length other))
              other -> assertFailure ("expected 1 module, got " ++ show (length other)),
      testCase "MultipleConstraints expands permission and init" $
        let cap =
              Capability.MultipleConstraints
                [ Capability.PermissionRequired (PermissionName "microphone"),
                  Capability.InitializationRequired (ResourceName "AudioContext")
                ]
            fn = funcWithCap "f" cap
            m = Manifest.collectCapabilities [("Mod", [fn])]
         in do
              Set.member "permission:microphone" (Manifest._manifestPermissions m) @?= True
              Set.member "init:AudioContext" (Manifest._manifestInitializations m) @?= True,
      testCase "MultipleConstraints with user-activation sets flag" $
        let cap =
              Capability.MultipleConstraints
                [Capability.UserActivationRequired, Capability.PermissionRequired (PermissionName "camera")]
            fn = funcWithCap "f" cap
            m = Manifest.collectCapabilities [("Mod", [fn])]
         in Manifest._manifestUserActivation m @?= True,
      testCase "MultipleConstraints produces multiple constraint texts" $
        let cap =
              Capability.MultipleConstraints
                [ Capability.PermissionRequired (PermissionName "mic"),
                  Capability.PermissionRequired (PermissionName "cam")
                ]
            fn = funcWithCap "f" cap
            m = Manifest.collectCapabilities [("Mod", [fn])]
         in case Manifest._manifestModules m of
              [mc] -> case Manifest._mcFunctions mc of
                [fc] -> length (Manifest._fcConstraints fc) @?= 2
                other -> assertFailure ("expected 1 func, got " ++ show (length other))
              other -> assertFailure ("expected 1 module, got " ++ show (length other))
    ]

testPackageLevelGrouping :: TestTree
testPackageLevelGrouping =
  testGroup
    "collectCapabilitiesWithPackages"
    [ testCase "empty package map produces no byPackage entries" $
        let fn = funcWithCap "f" (Capability.PermissionRequired (PermissionName "mic"))
            m = Manifest.collectCapabilitiesWithPackages Map.empty [("Mod", [fn])]
         in length (Manifest._manifestByPackage m) @?= 0,
      testCase "mapped file path groups caps under package name" $
        let fn = funcWithCap "f" (Capability.PermissionRequired (PermissionName "mic"))
            pkgMap = Map.singleton "Audio.ffi.js" "audio-lib"
            m = Manifest.collectCapabilitiesWithPackages pkgMap [("Audio.ffi.js", [fn])]
         in case Manifest._manifestByPackage m of
              [pc] -> Manifest._pcPackageName pc @?= "audio-lib"
              other -> assertFailure ("expected 1 pkg, got " ++ show (length other)),
      testCase "mapped package contains the capability" $
        let fn = funcWithCap "f" (Capability.PermissionRequired (PermissionName "mic"))
            pkgMap = Map.singleton "Audio.ffi.js" "audio-lib"
            m = Manifest.collectCapabilitiesWithPackages pkgMap [("Audio.ffi.js", [fn])]
         in case Manifest._manifestByPackage m of
              [pc] ->
                Set.member "permission:mic" (Manifest._pcCapabilities pc) @?= True
              other -> assertFailure ("expected 1 pkg, got " ++ show (length other)),
      testCase "uncapped module excluded from byPackage" $
        let pkgMap = Map.singleton "Mod.ffi.js" "some-lib"
            m = Manifest.collectCapabilitiesWithPackages pkgMap [("Mod.ffi.js", [funcNamed "plain"])]
         in length (Manifest._manifestByPackage m) @?= 0
    ]

testCollectByPackage :: TestTree
testCollectByPackage =
  testGroup
    "collectByPackage"
    [ testCase "empty input produces empty list" $
        length (Manifest.collectByPackage []) @?= 0,
      testCase "single entry becomes single PackageCapabilities" $
        case Manifest.collectByPackage [("pkg-a", Set.fromList ["permission:mic"])] of
          [pc] -> Manifest._pcPackageName pc @?= "pkg-a"
          other -> assertFailure ("expected 1, got " ++ show (length other)),
      testCase "two distinct packages become two entries" $
        let result =
              Manifest.collectByPackage
                [ ("pkg-a", Set.fromList ["permission:mic"]),
                  ("pkg-b", Set.fromList ["permission:camera"])
                ]
         in length result @?= 2,
      testCase "duplicate package names merged via union" $
        case Manifest.collectByPackage
               [ ("pkg", Set.fromList ["permission:mic"]),
                 ("pkg", Set.fromList ["permission:camera"])
               ] of
          [pc] -> Set.size (Manifest._pcCapabilities pc) @?= 2
          other -> assertFailure ("expected 1, got " ++ show (length other))
    ]

testJsonRoundTrip :: TestTree
testJsonRoundTrip =
  testGroup
    "JSON serialisation round-trip"
    [ testCase "empty manifest encodes and decodes" $
        let m = Manifest.collectCapabilities []
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 -> Manifest._manifestUserActivation m2 @?= False
              Nothing -> assertFailure "failed to decode empty manifest",
      testCase "permissions preserved through JSON" $
        let fn = funcWithCap "f" (Capability.PermissionRequired (PermissionName "microphone"))
            m = Manifest.collectCapabilities [("Mod", [fn])]
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 ->
                Set.member "permission:microphone" (Manifest._manifestPermissions m2) @?= True
              Nothing -> assertFailure "failed to decode manifest",
      testCase "userActivation preserved through JSON" $
        let fn = funcWithCap "f" Capability.UserActivationRequired
            m = Manifest.collectCapabilities [("Mod", [fn])]
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 -> Manifest._manifestUserActivation m2 @?= True
              Nothing -> assertFailure "failed to decode manifest",
      testCase "initializations preserved through JSON" $
        let fn = funcWithCap "f" (Capability.InitializationRequired (ResourceName "WebGL"))
            m = Manifest.collectCapabilities [("GL", [fn])]
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 ->
                Set.member "init:WebGL" (Manifest._manifestInitializations m2) @?= True
              Nothing -> assertFailure "failed to decode manifest"
    ]

testJsonRoundTripModules :: TestTree
testJsonRoundTripModules =
  testGroup
    "JSON round-trip preserves module structure"
    [ testCase "module name preserved through JSON" $
        let fn = funcWithCap "doIt" (Capability.PermissionRequired (PermissionName "camera"))
            m = Manifest.collectCapabilities [("CamModule", [fn])]
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 ->
                case Manifest._manifestModules m2 of
                  [mc] -> Manifest._mcModuleName mc @?= "CamModule"
                  other -> assertFailure ("expected 1 module, got " ++ show (length other))
              Nothing -> assertFailure "failed to decode",
      testCase "function name preserved through JSON" $
        let fn = funcWithCap "shoot" (Capability.PermissionRequired (PermissionName "camera"))
            m = Manifest.collectCapabilities [("Cam", [fn])]
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 ->
                case Manifest._manifestModules m2 of
                  [mc] ->
                    case Manifest._mcFunctions mc of
                      [fc] -> Manifest._fcFunctionName fc @?= "shoot"
                      other -> assertFailure ("expected 1 func, got " ++ show (length other))
                  other -> assertFailure ("expected 1 module, got " ++ show (length other))
              Nothing -> assertFailure "failed to decode",
      testCase "constraint text preserved through JSON" $
        let fn = funcWithCap "doIt" (Capability.PermissionRequired (PermissionName "microphone"))
            m = Manifest.collectCapabilities [("Mod", [fn])]
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 ->
                case Manifest._manifestModules m2 of
                  [mc] ->
                    case Manifest._mcFunctions mc of
                      [fc] -> Manifest._fcConstraints fc @?= ["permission:microphone"]
                      other -> assertFailure ("expected 1 func, got " ++ show (length other))
                  other -> assertFailure ("expected 1 module, got " ++ show (length other))
              Nothing -> assertFailure "failed to decode",
      testCase "multiple init caps preserved through JSON" $
        let fn1 = funcWithCap "a" (Capability.InitializationRequired (ResourceName "AudioContext"))
            fn2 = funcWithCap "b" (Capability.InitializationRequired (ResourceName "WebGL"))
            m = Manifest.collectCapabilities [("Mod", [fn1, fn2])]
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 ->
                Set.size (Manifest._manifestInitializations m2) @?= 2
              Nothing -> assertFailure "failed to decode"
    ]

testJsonRoundTripByPackage :: TestTree
testJsonRoundTripByPackage =
  testGroup
    "JSON round-trip preserves by-package"
    [ testCase "by-package preserved through JSON" $
        let fn = funcWithCap "f" (Capability.PermissionRequired (PermissionName "mic"))
            pkgMap = Map.singleton "Audio.ffi.js" "audio-lib"
            m = Manifest.collectCapabilitiesWithPackages pkgMap [("Audio.ffi.js", [fn])]
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 ->
                length (Manifest._manifestByPackage m2) @?= 1
              Nothing -> assertFailure "failed to decode",
      testCase "package name preserved through JSON" $
        let fn = funcWithCap "f" (Capability.PermissionRequired (PermissionName "mic"))
            pkgMap = Map.singleton "Audio.ffi.js" "audio-lib"
            m = Manifest.collectCapabilitiesWithPackages pkgMap [("Audio.ffi.js", [fn])]
         in case (Json.decode (Json.encode m) :: Maybe Manifest.CapabilityManifest) of
              Just m2 ->
                case Manifest._manifestByPackage m2 of
                  [pc] -> Manifest._pcPackageName pc @?= "audio-lib"
                  other -> assertFailure ("expected 1 pkg, got " ++ show (length other))
              Nothing -> assertFailure "failed to decode"
    ]

testMultiplePackages :: TestTree
testMultiplePackages =
  testGroup
    "multiple packages"
    [ testCase "two packages in pkg map produce two byPackage entries" $
        let fn1 = funcWithCap "f1" (Capability.PermissionRequired (PermissionName "mic"))
            fn2 = funcWithCap "f2" (Capability.PermissionRequired (PermissionName "camera"))
            pkgMap =
              Map.fromList
                [ ("Audio.ffi.js", "audio-lib"),
                  ("Cam.ffi.js", "camera-lib")
                ]
            m =
              Manifest.collectCapabilitiesWithPackages
                pkgMap
                [("Audio.ffi.js", [fn1]), ("Cam.ffi.js", [fn2])]
         in length (Manifest._manifestByPackage m) @?= 2,
      testCase "two modules same package merge capabilities" $
        let fn1 = funcWithCap "f1" (Capability.PermissionRequired (PermissionName "mic"))
            fn2 = funcWithCap "f2" (Capability.PermissionRequired (PermissionName "camera"))
            pkgMap =
              Map.fromList
                [ ("Audio.ffi.js", "shared-lib"),
                  ("Cam.ffi.js", "shared-lib")
                ]
            m =
              Manifest.collectCapabilitiesWithPackages
                pkgMap
                [("Audio.ffi.js", [fn1]), ("Cam.ffi.js", [fn2])]
         in case Manifest._manifestByPackage m of
              [pc] -> Set.size (Manifest._pcCapabilities pc) @?= 2
              other -> assertFailure ("expected 1 pkg, got " ++ show (length other)),
      testCase "unmapped module excluded from byPackage even with other mapped" $
        let fn1 = funcWithCap "f1" (Capability.PermissionRequired (PermissionName "mic"))
            fn2 = funcWithCap "f2" (Capability.PermissionRequired (PermissionName "camera"))
            pkgMap = Map.singleton "Audio.ffi.js" "audio-lib"
            m =
              Manifest.collectCapabilitiesWithPackages
                pkgMap
                [("Audio.ffi.js", [fn1]), ("Unmapped.ffi.js", [fn2])]
         in length (Manifest._manifestByPackage m) @?= 1
    ]

testNestedMultipleConstraints :: TestTree
testNestedMultipleConstraints =
  testGroup
    "nested MultipleConstraints"
    [ testCase "nested MultipleConstraints flattens all leaves" $
        let cap =
              Capability.MultipleConstraints
                [ Capability.MultipleConstraints
                    [ Capability.PermissionRequired (PermissionName "mic"),
                      Capability.UserActivationRequired
                    ],
                  Capability.InitializationRequired (ResourceName "AudioContext")
                ]
            fn = funcWithCap "f" cap
            m = Manifest.collectCapabilities [("Mod", [fn])]
         in do
              Set.member "permission:mic" (Manifest._manifestPermissions m) @?= True
              Manifest._manifestUserActivation m @?= True
              Set.member "init:AudioContext" (Manifest._manifestInitializations m) @?= True,
      testCase "MultipleConstraints with only user-activation" $
        let cap = Capability.MultipleConstraints [Capability.UserActivationRequired]
            fn = funcWithCap "gesture" cap
            m = Manifest.collectCapabilities [("UI", [fn])]
         in Manifest._manifestUserActivation m @?= True,
      testCase "MultipleConstraints with two permissions both appear in set" $
        let cap =
              Capability.MultipleConstraints
                [ Capability.PermissionRequired (PermissionName "camera"),
                  Capability.PermissionRequired (PermissionName "geolocation")
                ]
            fn = funcWithCap "f" cap
            m = Manifest.collectCapabilities [("Mod", [fn])]
         in Set.size (Manifest._manifestPermissions m) @?= 2
    ]

testAvailabilityInSets :: TestTree
testAvailabilityInSets =
  testGroup
    "availability constraints in sets"
    [ testCase "availability does not appear in permissions or initializations sets" $
        let fn = funcWithCap "f" (Capability.AvailabilityRequired "WebBluetooth")
            m = Manifest.collectCapabilities [("BT", [fn])]
         in do
              Set.size (Manifest._manifestPermissions m) @?= 0
              Set.size (Manifest._manifestInitializations m) @?= 0,
      testCase "availability function still appears in modules list" $
        let fn = funcWithCap "f" (Capability.AvailabilityRequired "WebBluetooth")
            m = Manifest.collectCapabilities [("BT", [fn])]
         in length (Manifest._manifestModules m) @?= 1,
      testCase "availability does not set userActivation flag" $
        let fn = funcWithCap "f" (Capability.AvailabilityRequired "WebNFC")
            m = Manifest.collectCapabilities [("NFC", [fn])]
         in Manifest._manifestUserActivation m @?= False
    ]

testModuleConstraintOrdering :: TestTree
testModuleConstraintOrdering =
  testGroup
    "module ordering and constraint counts"
    [ testCase "three modules with caps produce three entries" $
        let fn1 = funcWithCap "a" (Capability.PermissionRequired (PermissionName "mic"))
            fn2 = funcWithCap "b" (Capability.PermissionRequired (PermissionName "camera"))
            fn3 = funcWithCap "c" (Capability.UserActivationRequired)
            m =
              Manifest.collectCapabilities
                [("ModA", [fn1]), ("ModB", [fn2]), ("ModC", [fn3])]
         in length (Manifest._manifestModules m) @?= 3,
      testCase "module with mixed capped and uncapped functions counts only capped" $
        let fn1 = funcWithCap "capped" (Capability.PermissionRequired (PermissionName "mic"))
            fn2 = funcNamed "uncapped1"
            fn3 = funcNamed "uncapped2"
            m = Manifest.collectCapabilities [("Mod", [fn1, fn2, fn3])]
         in case Manifest._manifestModules m of
              [mc] -> length (Manifest._mcFunctions mc) @?= 1
              other -> assertFailure ("expected 1 module, got " ++ show (length other)),
      testCase "multiple permissions across functions all gathered" $
        let fn1 = funcWithCap "a" (Capability.PermissionRequired (PermissionName "mic"))
            fn2 = funcWithCap "b" (Capability.PermissionRequired (PermissionName "camera"))
            fn3 = funcWithCap "c" (Capability.PermissionRequired (PermissionName "geolocation"))
            m = Manifest.collectCapabilities [("Mod", [fn1, fn2, fn3])]
         in Set.size (Manifest._manifestPermissions m) @?= 3
    ]

testCollectByPackageCapabilityContent :: TestTree
testCollectByPackageCapabilityContent =
  testGroup
    "collectByPackage capability content"
    [ testCase "single entry preserves capability text" $
        case Manifest.collectByPackage [("pkg-a", Set.fromList ["permission:mic"])] of
          [pc] -> Set.member "permission:mic" (Manifest._pcCapabilities pc) @?= True
          other -> assertFailure ("expected 1, got " ++ show (length other)),
      testCase "merged capabilities contain both originals" $
        case Manifest.collectByPackage
               [ ("pkg", Set.fromList ["permission:mic"]),
                 ("pkg", Set.fromList ["init:AudioContext"])
               ] of
          [pc] ->
            Set.member "init:AudioContext" (Manifest._pcCapabilities pc) @?= True
          other -> assertFailure ("expected 1, got " ++ show (length other)),
      testCase "three entries same package accumulate all caps" $
        case Manifest.collectByPackage
               [ ("pkg", Set.fromList ["permission:mic"]),
                 ("pkg", Set.fromList ["permission:camera"]),
                 ("pkg", Set.fromList ["init:AudioContext"])
               ] of
          [pc] -> Set.size (Manifest._pcCapabilities pc) @?= 3
          other -> assertFailure ("expected 1, got " ++ show (length other)),
      testCase "two distinct packages preserve separate caps" $
        let result =
              Manifest.collectByPackage
                [ ("pkg-a", Set.fromList ["permission:mic"]),
                  ("pkg-b", Set.fromList ["permission:camera"])
                ]
         in length result @?= 2
    ]

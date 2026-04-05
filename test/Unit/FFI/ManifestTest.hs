{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI.Manifest module.
--
-- Tests capability manifest collection covering empty inputs, single modules,
-- multiple modules, capability deduplication, and package-level grouping.
--
-- @since 0.19.1
module Unit.FFI.ManifestTest (tests) where

import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified FFI.Capability as Capability
import qualified FFI.Manifest as Manifest
import FFI.Types (BindingMode (..), FFIType (..), JsFunctionName (..), PermissionName (..), ResourceName (..))
import qualified Foreign.FFI as FFI
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI.Manifest Tests"
    [ testEmptyInputs,
      testSingleModuleNoCapabilities,
      testSingleFunctionWithPermission,
      testSingleFunctionWithInit,
      testSingleFunctionWithUserActivation,
      testMultipleCapabilitiesOnOneFunction,
      testMultipleModules,
      testCapabilityDeduplication,
      testAvailabilityConstraint,
      testMultipleConstraintFlattening,
      testModuleFilteredWhenEmpty,
      testPermissionPrefixFormat,
      testInitPrefixFormat,
      testLensAccessors
    ]

-- | Build a minimal JSDocFunction with no capabilities.
makeFunc :: Text.Text -> FFI.JSDocFunction
makeFunc name =
  FFI.JSDocFunction
    { FFI.jsDocFuncName = JsFunctionName name,
      FFI.jsDocFuncType = FFIUnit,
      FFI.jsDocFuncDescription = Nothing,
      FFI.jsDocFuncParams = [],
      FFI.jsDocFuncThrows = [],
      FFI.jsDocFuncCapabilities = Nothing,
      FFI.jsDocFuncFile = "test.ffi.js",
      FFI.jsDocFuncBindMode = FunctionCall,
      FFI.jsDocFuncCanopyName = Nothing
    }

-- | Build a JSDocFunction with a specific capability constraint.
makeFuncWithCap :: Text.Text -> Capability.CapabilityConstraint -> FFI.JSDocFunction
makeFuncWithCap name cap =
  (makeFunc name) {FFI.jsDocFuncCapabilities = Just cap}

-- EMPTY INPUT TESTS

testEmptyInputs :: TestTree
testEmptyInputs =
  testGroup
    "empty input"
    [ testCase "empty module list produces empty manifest" $ do
        let manifest = Manifest.collectCapabilities []
        Manifest._manifestUserActivation manifest @?= False
        Set.size (Manifest._manifestPermissions manifest) @?= 0
        Set.size (Manifest._manifestInitializations manifest) @?= 0
        length (Manifest._manifestModules manifest) @?= 0,
      testCase "module with no FFI functions produces no module entry" $ do
        let manifest = Manifest.collectCapabilities [("MyModule", [])]
        length (Manifest._manifestModules manifest) @?= 0,
      testCase "module with only no-capability functions produces no entry" $ do
        let funcs = [makeFunc "doThing", makeFunc "doOther"]
            manifest = Manifest.collectCapabilities [("Mod", funcs)]
        length (Manifest._manifestModules manifest) @?= 0
    ]

-- SINGLE MODULE TESTS

testSingleModuleNoCapabilities :: TestTree
testSingleModuleNoCapabilities =
  testGroup
    "single module no capabilities"
    [ testCase "permissions set empty" $ do
        let manifest = Manifest.collectCapabilities [("Audio", [makeFunc "init"])]
        Manifest._manifestPermissions manifest @?= Set.empty,
      testCase "initializations set empty" $ do
        let manifest = Manifest.collectCapabilities [("Audio", [makeFunc "play"])]
        Manifest._manifestInitializations manifest @?= Set.empty,
      testCase "userActivation false" $ do
        let manifest = Manifest.collectCapabilities [("Audio", [makeFunc "stop"])]
        Manifest._manifestUserActivation manifest @?= False
    ]

testSingleFunctionWithPermission :: TestTree
testSingleFunctionWithPermission =
  testGroup
    "single function with permission"
    [ testCase "permission appears in manifestPermissions" $ do
        let cap = Capability.PermissionRequired (PermissionName "microphone")
            funcs = [makeFuncWithCap "record" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
        Manifest._manifestPermissions manifest @?= Set.singleton "permission:microphone",
      testCase "module entry is created" $ do
        let cap = Capability.PermissionRequired (PermissionName "microphone")
            funcs = [makeFuncWithCap "record" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
        length (Manifest._manifestModules manifest) @?= 1,
      testCase "module name is preserved" $ do
        let cap = Capability.PermissionRequired (PermissionName "camera")
            funcs = [makeFuncWithCap "snapshot" cap]
            manifest = Manifest.collectCapabilities [("Camera", funcs)]
            modNames = map Manifest._mcModuleName (Manifest._manifestModules manifest)
        modNames @?= ["Camera"],
      testCase "function name is preserved in module caps" $ do
        let cap = Capability.PermissionRequired (PermissionName "geolocation")
            funcs = [makeFuncWithCap "locate" cap]
            manifest = Manifest.collectCapabilities [("Geo", funcs)]
            mods = Manifest._manifestModules manifest
        case mods of
          [m] -> map Manifest._fcFunctionName (Manifest._mcFunctions m) @?= ["locate"]
          _ -> assertFailure "expected exactly one module"
    ]

testSingleFunctionWithInit :: TestTree
testSingleFunctionWithInit =
  testGroup
    "single function with init requirement"
    [ testCase "init appears in manifestInitializations" $ do
        let cap = Capability.InitializationRequired (ResourceName "AudioContext")
            funcs = [makeFuncWithCap "decode" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
        Manifest._manifestInitializations manifest @?= Set.singleton "init:AudioContext",
      testCase "init does not appear in permissions" $ do
        let cap = Capability.InitializationRequired (ResourceName "AudioContext")
            funcs = [makeFuncWithCap "decode" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
        Set.size (Manifest._manifestPermissions manifest) @?= 0
    ]

testSingleFunctionWithUserActivation :: TestTree
testSingleFunctionWithUserActivation =
  testGroup
    "single function with user activation"
    [ testCase "userActivation is true when present" $ do
        let cap = Capability.UserActivationRequired
            funcs = [makeFuncWithCap "play" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
        Manifest._manifestUserActivation manifest @?= True,
      testCase "userActivation is false when absent" $ do
        let cap = Capability.PermissionRequired (PermissionName "microphone")
            funcs = [makeFuncWithCap "record" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
        Manifest._manifestUserActivation manifest @?= False
    ]

testMultipleCapabilitiesOnOneFunction :: TestTree
testMultipleCapabilitiesOnOneFunction =
  testGroup
    "multiple capabilities on one function"
    [ testCase "MultipleConstraints flattened into permissions and inits" $ do
        let cap =
              Capability.MultipleConstraints
                [ Capability.PermissionRequired (PermissionName "microphone"),
                  Capability.InitializationRequired (ResourceName "AudioContext")
                ]
            funcs = [makeFuncWithCap "record" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
        Manifest._manifestPermissions manifest @?= Set.singleton "permission:microphone"
        Manifest._manifestInitializations manifest @?= Set.singleton "init:AudioContext",
      testCase "nested MultipleConstraints includes user-activation" $ do
        let cap =
              Capability.MultipleConstraints
                [ Capability.UserActivationRequired,
                  Capability.PermissionRequired (PermissionName "camera")
                ]
            funcs = [makeFuncWithCap "snap" cap]
            manifest = Manifest.collectCapabilities [("Cam", funcs)]
        Manifest._manifestUserActivation manifest @?= True
        Manifest._manifestPermissions manifest @?= Set.singleton "permission:camera"
    ]

testMultipleModules :: TestTree
testMultipleModules =
  testGroup
    "multiple modules"
    [ testCase "two modules with caps produce two entries" $ do
        let cap1 = Capability.PermissionRequired (PermissionName "microphone")
            cap2 = Capability.PermissionRequired (PermissionName "camera")
            input =
              [ ("Audio", [makeFuncWithCap "record" cap1]),
                ("Camera", [makeFuncWithCap "snap" cap2])
              ]
            manifest = Manifest.collectCapabilities input
        length (Manifest._manifestModules manifest) @?= 2,
      testCase "permissions aggregated across modules" $ do
        let cap1 = Capability.PermissionRequired (PermissionName "microphone")
            cap2 = Capability.PermissionRequired (PermissionName "camera")
            input =
              [ ("Audio", [makeFuncWithCap "record" cap1]),
                ("Camera", [makeFuncWithCap "snap" cap2])
              ]
            manifest = Manifest.collectCapabilities input
        Manifest._manifestPermissions manifest
          @?= Set.fromList ["permission:microphone", "permission:camera"],
      testCase "module without capabilities excluded, others included" $ do
        let cap = Capability.PermissionRequired (PermissionName "microphone")
            input =
              [ ("Audio", [makeFuncWithCap "record" cap]),
                ("Pure", [makeFunc "add"])
              ]
            manifest = Manifest.collectCapabilities input
        length (Manifest._manifestModules manifest) @?= 1
    ]

testCapabilityDeduplication :: TestTree
testCapabilityDeduplication =
  testGroup
    "capability deduplication"
    [ testCase "same permission from two functions deduplicated in set" $ do
        let cap = Capability.PermissionRequired (PermissionName "microphone")
            funcs = [makeFuncWithCap "record" cap, makeFuncWithCap "stream" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
        Set.size (Manifest._manifestPermissions manifest) @?= 1,
      testCase "same init from two functions deduplicated in set" $ do
        let cap = Capability.InitializationRequired (ResourceName "AudioContext")
            funcs = [makeFuncWithCap "decode" cap, makeFuncWithCap "encode" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
        Set.size (Manifest._manifestInitializations manifest) @?= 1,
      testCase "two distinct permissions both appear" $ do
        let cap1 = Capability.PermissionRequired (PermissionName "microphone")
            cap2 = Capability.PermissionRequired (PermissionName "camera")
            funcs = [makeFuncWithCap "record" cap1, makeFuncWithCap "snap" cap2]
            manifest = Manifest.collectCapabilities [("Media", funcs)]
        Set.size (Manifest._manifestPermissions manifest) @?= 2
    ]

testAvailabilityConstraint :: TestTree
testAvailabilityConstraint =
  testGroup
    "availability constraint"
    [ testCase "availability constraint causes module entry" $ do
        let cap = Capability.AvailabilityRequired "WebGL"
            funcs = [makeFuncWithCap "draw" cap]
            manifest = Manifest.collectCapabilities [("Graphics", funcs)]
        length (Manifest._manifestModules manifest) @?= 1,
      testCase "availability does not appear in permissions" $ do
        let cap = Capability.AvailabilityRequired "Bluetooth"
            funcs = [makeFuncWithCap "connect" cap]
            manifest = Manifest.collectCapabilities [("BLE", funcs)]
        Set.size (Manifest._manifestPermissions manifest) @?= 0
    ]

testMultipleConstraintFlattening :: TestTree
testMultipleConstraintFlattening =
  testGroup
    "MultipleConstraints flattening"
    [ testCase "deeply nested MultipleConstraints flattened" $ do
        let inner =
              Capability.MultipleConstraints
                [ Capability.PermissionRequired (PermissionName "microphone"),
                  Capability.PermissionRequired (PermissionName "camera")
                ]
            outer = Capability.MultipleConstraints [inner, Capability.UserActivationRequired]
            funcs = [makeFuncWithCap "mediaCapture" outer]
            manifest = Manifest.collectCapabilities [("Media", funcs)]
        Manifest._manifestUserActivation manifest @?= True
        Set.size (Manifest._manifestPermissions manifest) @?= 2
    ]

testModuleFilteredWhenEmpty :: TestTree
testModuleFilteredWhenEmpty =
  testGroup
    "module filtering"
    [ testCase "only capability-bearing functions included in entry" $ do
        let cap = Capability.PermissionRequired (PermissionName "microphone")
            funcs = [makeFunc "helper", makeFuncWithCap "record" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
            mods = Manifest._manifestModules manifest
        case mods of
          [m] -> length (Manifest._mcFunctions m) @?= 1
          _ -> assertFailure "expected exactly one module entry"
    ]

testPermissionPrefixFormat :: TestTree
testPermissionPrefixFormat =
  testGroup
    "permission label format"
    [ testCase "permission label has permission: prefix" $ do
        let cap = Capability.PermissionRequired (PermissionName "geolocation")
            funcs = [makeFuncWithCap "locate" cap]
            manifest = Manifest.collectCapabilities [("Geo", funcs)]
        Set.toList (Manifest._manifestPermissions manifest) @?= ["permission:geolocation"]
    ]

testInitPrefixFormat :: TestTree
testInitPrefixFormat =
  testGroup
    "init label format"
    [ testCase "init label has init: prefix" $ do
        let cap = Capability.InitializationRequired (ResourceName "WebGLRenderingContext")
            funcs = [makeFuncWithCap "initGL" cap]
            manifest = Manifest.collectCapabilities [("GL", funcs)]
        Set.toList (Manifest._manifestInitializations manifest) @?= ["init:WebGLRenderingContext"]
    ]

testLensAccessors :: TestTree
testLensAccessors =
  testGroup
    "lens field accessors"
    [ testCase "FunctionCapability fields accessible" $ do
        let cap = Capability.PermissionRequired (PermissionName "microphone")
            funcs = [makeFuncWithCap "record" cap]
            manifest = Manifest.collectCapabilities [("Audio", funcs)]
            mods = Manifest._manifestModules manifest
        case mods of
          [m] ->
            case Manifest._mcFunctions m of
              [fc] -> do
                Manifest._fcFunctionName fc @?= "record"
                Manifest._fcConstraints fc @?= ["permission:microphone"]
              _ -> assertFailure "expected one function capability"
          _ -> assertFailure "expected one module"
    ]

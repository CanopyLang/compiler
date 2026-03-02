{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI.CapabilityEnforcement module.
--
-- Tests compile-time capability validation, runtime registry generation,
-- and per-function capability guard generation.
--
-- @since 0.20.0
module Unit.FFI.CapabilityEnforcementTest (tests) where

import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as Lazy
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified FFI.CapabilityEnforcement as CapEnforce
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI.CapabilityEnforcement Tests"
    [ validationTests,
      unusedCapabilityTests,
      registryGenerationTests,
      guardGenerationTests,
      integrationTests
    ]

-- VALIDATION TESTS

validationTests :: TestTree
validationTests =
  testGroup
    "validateCapabilities"
    [ testCase "no requirements produces no errors" $ do
        let errors = CapEnforce.validateCapabilities (Set.fromList ["geo"]) []
        errors @?= [],
      testCase "all requirements satisfied produces no errors" $ do
        let declared = Set.fromList ["geolocation", "camera"]
            reqs = [("getLocation", "ffi/geo.js", Set.singleton "geolocation")]
            errors = CapEnforce.validateCapabilities declared reqs
        errors @?= [],
      testCase "missing capability produces error" $ do
        let declared = Set.empty
            reqs = [("getLocation", "ffi/geo.js", Set.singleton "geolocation")]
            errors = CapEnforce.validateCapabilities declared reqs
        length errors @?= 1
        case errors of
          [err] -> do
            CapEnforce._ceFunctionName err @?= "getLocation"
            CapEnforce._ceFilePath err @?= "ffi/geo.js"
            CapEnforce._ceMissingCapability err @?= "geolocation"
          _ -> assertFailure "expected exactly one error",
      testCase "multiple missing capabilities produce multiple errors" $ do
        let declared = Set.empty
            reqs = [("getMedia", "ffi/media.js", Set.fromList ["camera", "microphone"])]
            errors = CapEnforce.validateCapabilities declared reqs
        length errors @?= 2,
      testCase "partially satisfied requirements produce errors for missing only" $ do
        let declared = Set.singleton "camera"
            reqs = [("getMedia", "ffi/media.js", Set.fromList ["camera", "microphone"])]
            errors = CapEnforce.validateCapabilities declared reqs
        length errors @?= 1
        case errors of
          [err] -> CapEnforce._ceMissingCapability err @?= "microphone"
          _ -> assertFailure "expected exactly one error",
      testCase "multiple functions validated independently" $ do
        let declared = Set.singleton "geolocation"
            reqs =
              [ ("getLocation", "ffi/geo.js", Set.singleton "geolocation"),
                ("takePhoto", "ffi/camera.js", Set.singleton "camera")
              ]
            errors = CapEnforce.validateCapabilities declared reqs
        length errors @?= 1
        case errors of
          [err] -> CapEnforce._ceFunctionName err @?= "takePhoto"
          _ -> assertFailure "expected exactly one error",
      testCase "empty declared set with empty requirements is valid" $ do
        let errors = CapEnforce.validateCapabilities Set.empty []
        errors @?= [],
      testCase "error contains correct file path" $ do
        let declared = Set.empty
            reqs = [("fn", "src/ffi/deep/path.js", Set.singleton "cap")]
            errors = CapEnforce.validateCapabilities declared reqs
        case errors of
          [err] -> CapEnforce._ceFilePath err @?= "src/ffi/deep/path.js"
          _ -> assertFailure "expected exactly one error"
    ]

-- UNUSED CAPABILITY TESTS

unusedCapabilityTests :: TestTree
unusedCapabilityTests =
  testGroup
    "findUnusedCapabilities"
    [ testCase "no declared capabilities returns empty" $ do
        let unused = CapEnforce.findUnusedCapabilities Set.empty []
        unused @?= Set.empty,
      testCase "all declared capabilities used returns empty" $ do
        let declared = Set.fromList ["geo", "camera"]
            reqs =
              [ ("getLocation", "a.js", Set.singleton "geo"),
                ("takePhoto", "b.js", Set.singleton "camera")
              ]
            unused = CapEnforce.findUnusedCapabilities declared reqs
        unused @?= Set.empty,
      testCase "unused capability detected" $ do
        let declared = Set.fromList ["geo", "camera"]
            reqs = [("getLocation", "a.js", Set.singleton "geo")]
            unused = CapEnforce.findUnusedCapabilities declared reqs
        unused @?= Set.singleton "camera",
      testCase "multiple unused capabilities detected" $ do
        let declared = Set.fromList ["geo", "camera", "notifications"]
            reqs = [("getLocation", "a.js", Set.singleton "geo")]
            unused = CapEnforce.findUnusedCapabilities declared reqs
        unused @?= Set.fromList ["camera", "notifications"],
      testCase "declared with no requirements yields all unused" $ do
        let declared = Set.fromList ["geo", "camera"]
            unused = CapEnforce.findUnusedCapabilities declared []
        unused @?= declared
    ]

-- REGISTRY GENERATION TESTS

registryGenerationTests :: TestTree
registryGenerationTests =
  testGroup
    "generateCapabilityRegistry"
    [ testCase "empty set produces empty output" $ do
        let output = builderToText (CapEnforce.generateCapabilityRegistry Set.empty)
        output @?= "",
      testCase "single capability produces registry and check function" $ do
        let output = builderToText (CapEnforce.generateCapabilityRegistry (Set.singleton "geolocation"))
        assertBool "registry contains _Canopy_capabilities" (Text.isInfixOf "_Canopy_capabilities" output)
        assertBool "registry contains geolocation entry" (Text.isInfixOf "\"geolocation\": true" output)
        assertBool "registry contains check function" (Text.isInfixOf "_Canopy_checkCapability" output),
      testCase "multiple capabilities all present in registry" $ do
        let caps = Set.fromList ["camera", "geolocation", "notifications"]
            output = builderToText (CapEnforce.generateCapabilityRegistry caps)
        assertBool "contains camera" (Text.isInfixOf "\"camera\": true" output)
        assertBool "contains geolocation" (Text.isInfixOf "\"geolocation\": true" output)
        assertBool "contains notifications" (Text.isInfixOf "\"notifications\": true" output),
      testCase "registry is valid JavaScript structure" $ do
        let output = builderToText (CapEnforce.generateCapabilityRegistry (Set.singleton "geo"))
        assertBool "starts with var" (Text.isPrefixOf "var _Canopy_capabilities" output)
        assertBool "has check function" (Text.isInfixOf "function _Canopy_checkCapability" output),
      testCase "check function throws on missing capability" $ do
        let output = builderToText (CapEnforce.generateCapabilityRegistry (Set.singleton "geo"))
        assertBool "throws Error" (Text.isInfixOf "throw new Error" output)
        assertBool "mentions capability in message" (Text.isInfixOf "Capability" output)
    ]

-- GUARD GENERATION TESTS

guardGenerationTests :: TestTree
guardGenerationTests =
  testGroup
    "generateCapabilityGuard"
    [ testCase "empty capabilities produces empty guard" $ do
        let output = builderToText (CapEnforce.generateCapabilityGuard "myFunc" Set.empty)
        output @?= "",
      testCase "single capability produces one check call" $ do
        let output = builderToText (CapEnforce.generateCapabilityGuard "getLocation" (Set.singleton "geolocation"))
        assertBool "calls _Canopy_checkCapability" (Text.isInfixOf "_Canopy_checkCapability" output)
        assertBool "passes capability name" (Text.isInfixOf "\"geolocation\"" output)
        assertBool "passes function name" (Text.isInfixOf "\"getLocation\"" output),
      testCase "multiple capabilities produce multiple check calls" $ do
        let caps = Set.fromList ["camera", "microphone"]
            output = builderToText (CapEnforce.generateCapabilityGuard "getMedia" caps)
        let checkCount = length (Text.splitOn "_Canopy_checkCapability" output) - 1
        checkCount @?= 2,
      testCase "guard uses correct function name in all checks" $ do
        let caps = Set.fromList ["a", "b"]
            output = builderToText (CapEnforce.generateCapabilityGuard "myFunc" caps)
        let funcRefCount = length (Text.splitOn "\"myFunc\"" output) - 1
        funcRefCount @?= 2
    ]

-- INTEGRATION TESTS

integrationTests :: TestTree
integrationTests =
  testGroup
    "integration scenarios"
    [ testCase "validation plus registry generation for typical app" $ do
        let declared = Set.fromList ["geolocation", "notifications"]
            reqs =
              [ ("getLocation", "ffi/geo.js", Set.singleton "geolocation"),
                ("showNotification", "ffi/notify.js", Set.singleton "notifications")
              ]
            errors = CapEnforce.validateCapabilities declared reqs
            unused = CapEnforce.findUnusedCapabilities declared reqs
            registry = builderToText (CapEnforce.generateCapabilityRegistry declared)
        errors @?= []
        unused @?= Set.empty
        assertBool "registry has geolocation" (Text.isInfixOf "\"geolocation\": true" registry)
        assertBool "registry has notifications" (Text.isInfixOf "\"notifications\": true" registry),
      testCase "library project with no capabilities" $ do
        let declared = Set.empty
            errors = CapEnforce.validateCapabilities declared []
            unused = CapEnforce.findUnusedCapabilities declared []
            registry = builderToText (CapEnforce.generateCapabilityRegistry declared)
        errors @?= []
        unused @?= Set.empty
        registry @?= "",
      testCase "CapabilityError Show instance" $ do
        let err =
              CapEnforce.CapabilityError
                { CapEnforce._ceFunctionName = "getLocation",
                  CapEnforce._ceFilePath = "ffi/geo.js",
                  CapEnforce._ceMissingCapability = "geolocation"
                }
        let shown = show err
        assertBool "show contains function name" (isInfixOf "getLocation" shown)
        assertBool "show contains file path" (isInfixOf "ffi/geo.js" shown)
        assertBool "show contains capability" (isInfixOf "geolocation" shown),
      testCase "CapabilityError Eq instance" $ do
        let err1 =
              CapEnforce.CapabilityError
                { CapEnforce._ceFunctionName = "fn",
                  CapEnforce._ceFilePath = "a.js",
                  CapEnforce._ceMissingCapability = "cap"
                }
            err2 =
              CapEnforce.CapabilityError
                { CapEnforce._ceFunctionName = "fn",
                  CapEnforce._ceFilePath = "a.js",
                  CapEnforce._ceMissingCapability = "cap"
                }
            err3 =
              CapEnforce.CapabilityError
                { CapEnforce._ceFunctionName = "other",
                  CapEnforce._ceFilePath = "a.js",
                  CapEnforce._ceMissingCapability = "cap"
                }
        err1 @?= err2
        assertBool "different errors are not equal" (err1 /= err3)
    ]

-- HELPERS

-- | Convert a Builder to Text for assertions.
builderToText :: Builder.Builder -> Text.Text
builderToText = Text.decodeUtf8 . Lazy.toStrict . Builder.toLazyByteString

-- | Check if a substring is present in a String.
isInfixOf :: String -> String -> Bool
isInfixOf needle haystack = Text.isInfixOf (Text.pack needle) (Text.pack haystack)

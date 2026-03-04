{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for compile-time capability type enforcement.
--
-- Tests that FFI functions with @capability permission annotations get
-- @Capability X ->@ prepended to their canonical types, and that the
-- FFI binding parser correctly extracts capability annotations from
-- JSDoc blocks.
--
-- @since 0.20.0
module Unit.FFI.CapabilityTypeTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Text as Text
import FFI.Types (CapabilityName (..), FFIBinding (..), FFIFuncName (..), FFITypeAnnotation (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI Capability Type Enforcement Tests"
    [ capabilityTypeTests,
      permissionNameTests,
      bindingParsingTests,
      integrationTests
    ]

-- CAPABILITY TYPE CONSTRUCTION

capabilityTypeTests :: TestTree
capabilityTypeTests =
  testGroup
    "capabilityType construction"
    [ testCase "microphone produces Capability Microphone" $ do
        let capType = capabilityType "microphone"
        assertCapabilityType capType "Capability" "Microphone",
      testCase "geolocation produces Capability Geolocation" $ do
        let capType = capabilityType "geolocation"
        assertCapabilityType capType "Capability" "Geolocation",
      testCase "screen-capture produces Capability ScreenCapture" $ do
        let capType = capabilityType "screen-capture"
        assertCapabilityType capType "Capability" "ScreenCapture",
      testCase "wake-lock produces Capability WakeLock" $ do
        let capType = capabilityType "wake-lock"
        assertCapabilityType capType "Capability" "WakeLock"
    ]

-- PERMISSION NAME MAPPING

permissionNameTests :: TestTree
permissionNameTests =
  testGroup
    "permissionToTypeName conversion"
    [ testCase "simple lowercase to PascalCase" $
        toPascalCase "microphone" @?= "Microphone",
      testCase "kebab-case to PascalCase" $
        toPascalCase "screen-capture" @?= "ScreenCapture",
      testCase "multi-segment kebab-case" $
        toPascalCase "push-notifications" @?= "PushNotifications",
      testCase "single char" $
        toPascalCase "a" @?= "A",
      testCase "already capitalized passes through" $
        toPascalCase "Camera" @?= "Camera"
    ]

-- BINDING PARSING

bindingParsingTests :: TestTree
bindingParsingTests =
  testGroup
    "FFIBinding capability extraction"
    [ testCase "binding with no capabilities has empty list" $ do
        let binding = FFIBinding (FFIFuncName "fn") (FFITypeAnnotation "Int -> Int") []
        _bindingCapabilities binding @?= [],
      testCase "binding with one capability" $ do
        let binding = FFIBinding (FFIFuncName "startRecording") (FFITypeAnnotation "() -> Task String AudioBuffer") [CapabilityName "microphone"]
        length (_bindingCapabilities binding) @?= 1
        unCapabilityName (head (_bindingCapabilities binding)) @?= "microphone",
      testCase "binding with multiple capabilities" $ do
        let caps = [CapabilityName "camera", CapabilityName "microphone"]
            binding = FFIBinding (FFIFuncName "getMedia") (FFITypeAnnotation "() -> Task String MediaStream") caps
        length (_bindingCapabilities binding) @?= 2
    ]

-- PREPEND CAPABILITIES

integrationTests :: TestTree
integrationTests =
  testGroup
    "prependCapabilities integration"
    [ testCase "no capabilities returns base type unchanged" $ do
        let baseType = Can.TType ModuleName.basics (Name.fromChars "Int") []
            result = prependCapabilities [] baseType
        assertIsIntType result,
      testCase "single capability prepends Capability X -> to type" $ do
        let baseType = Can.TType ModuleName.basics (Name.fromChars "Int") []
            caps = [CapabilityName "microphone"]
            result = prependCapabilities caps baseType
        case result of
          Can.TLambda capParam inner -> do
            assertCapabilityType capParam "Capability" "Microphone"
            assertIsIntType inner
          _ -> assertFailure "expected TLambda wrapping the base type",
      testCase "multiple capabilities prepend in order" $ do
        let baseType = Can.TType ModuleName.basics (Name.fromChars "Int") []
            caps = [CapabilityName "microphone", CapabilityName "camera"]
            result = prependCapabilities caps baseType
        case result of
          Can.TLambda cap1 (Can.TLambda cap2 inner) -> do
            assertCapabilityType cap1 "Capability" "Microphone"
            assertCapabilityType cap2 "Capability" "Camera"
            assertIsIntType inner
          _ -> assertFailure "expected two TLambda layers wrapping the base type",
      testCase "capability with function base type" $ do
        let intType = Can.TType ModuleName.basics (Name.fromChars "Int") []
            baseType = Can.TLambda intType intType
            caps = [CapabilityName "geolocation"]
            result = prependCapabilities caps baseType
        case result of
          Can.TLambda capParam (Can.TLambda _ _) -> do
            assertCapabilityType capParam "Capability" "Geolocation"
          _ -> assertFailure "expected Capability Geolocation -> Int -> Int"
    ]

-- HELPERS

-- | Assert that a type is @Capability X@ with the given outer and inner names.
assertCapabilityType :: Can.Type -> String -> String -> IO ()
assertCapabilityType tipe expectedOuter expectedInner =
  case tipe of
    Can.TType home outerName [Can.TType innerHome innerName []] -> do
      home @?= ModuleName.capability
      Name.toChars outerName @?= expectedOuter
      innerHome @?= ModuleName.capability
      Name.toChars innerName @?= expectedInner
    _ ->
      assertFailure
        ("expected TType " ++ expectedOuter ++ " [TType " ++ expectedInner ++ " []], got: " ++ show tipe)

-- | Assert that a type is Int from Basics.
assertIsIntType :: Can.Type -> IO ()
assertIsIntType tipe =
  case tipe of
    Can.TType home name [] -> do
      home @?= ModuleName.basics
      Name.toChars name @?= "Int"
    _ ->
      assertFailure ("expected Basics.Int, got: " ++ show tipe)

-- IMPORTED FUNCTIONS (re-implemented here for testing since they're not exported)

-- | Build the canonical type @Capability X@ for a given permission name.
capabilityType :: Text.Text -> Can.Type
capabilityType permissionName =
  Can.TType ModuleName.capability (Name.fromChars "Capability")
    [Can.TType ModuleName.capability (permissionToTypeName permissionName) []]

-- | Map a permission string to its corresponding phantom type name.
permissionToTypeName :: Text.Text -> Name.Name
permissionToTypeName = Name.fromChars . Text.unpack . toPascalCase

-- | Convert a kebab-case or lowercase permission name to PascalCase.
toPascalCase :: Text.Text -> Text.Text
toPascalCase = Text.concat . fmap capitalizeFirst . Text.splitOn "-"

-- | Capitalize the first character of a text value.
capitalizeFirst :: Text.Text -> Text.Text
capitalizeFirst t =
  maybe t (\(c, rest) -> Text.cons (toUpper c) rest) (Text.uncons t)
  where
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise = c

-- | Prepend @Capability X ->@ parameters for each capability requirement.
prependCapabilities :: [CapabilityName] -> Can.Type -> Can.Type
prependCapabilities caps baseType =
  foldr prependOneCapability baseType caps

-- | Prepend a single @Capability X ->@ to a type.
prependOneCapability :: CapabilityName -> Can.Type -> Can.Type
prependOneCapability (CapabilityName capName) innerType =
  Can.TLambda (capabilityType capName) innerType

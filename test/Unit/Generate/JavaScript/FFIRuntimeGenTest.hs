{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Generate.JavaScript.FFIRuntimeGenTest - Tests for FFI Runtime generation
--
-- This module verifies the pure functions exported by
-- "Generate.JavaScript.FFIRuntime". The embedded runtime snippets are entirely
-- pure (they are compile-time string literals wrapped in 'BB.Builder'), so
-- every test runs without IO and can make precise claims about the generated
-- JavaScript text.
--
-- == Test Coverage
--
-- * 'embeddedRuntime': non-empty, starts with the runtime header, ends with
--   the runtime footer.
-- * 'embeddedMarshal': non-empty, starts with the expected @$canopy@ block.
-- * 'embeddedValidate': non-empty, starts with the expected @$validate@ block.
-- * 'embeddedSmart': non-empty, starts with the expected @$smart@ block.
-- * 'embeddedEnvironment': non-empty, starts with the expected @$env@ block.
-- * 'embeddedValidateMinimal': non-empty, contains only minimal validators.
-- * 'embeddedRuntimeForMode': Dev (safe) == full runtime; Dev (unsafe) omits
--   smart validators; Prod (safe) == full runtime; Prod (unsafe) omits
--   smart validators and environment.
-- * 'scanAndEmitRuntime': only includes modules whose marker symbols appear in
--   the provided content.
--
-- @since 0.20.0
module Unit.Generate.JavaScript.FFIRuntimeGenTest
  ( tests
  ) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generate.JavaScript.FFIRuntime as FFIRuntime
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Test.Tasty
import Test.Tasty.HUnit

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Render a 'BB.Builder' to a strict 'BS.ByteString'.
render :: BB.Builder -> BS.ByteString
render = LBS.toStrict . BB.toLazyByteString

-- | A 'Mode.Dev' value with all flags disabled (safe mode, no debug types).
devSafe :: Mode.Mode
devSafe = Mode.Dev Nothing False False False Set.empty False

-- | A 'Mode.Dev' value with ffi-unsafe enabled (third Bool field = True).
devUnsafe :: Mode.Mode
devUnsafe = Mode.Dev Nothing False True False Set.empty False

-- | A 'Mode.Prod' value with all flags disabled (safe mode).
prodSafe :: Mode.Mode
prodSafe = Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty Map.empty

-- | A 'Mode.Prod' value with ffi-unsafe enabled (third Bool field = True).
prodUnsafe :: Mode.Mode
prodUnsafe = Mode.Prod Map.empty False True False StringPool.emptyPool Set.empty Map.empty

-- ---------------------------------------------------------------------------
-- Root test tree
-- ---------------------------------------------------------------------------

-- | Root test tree for Generate.JavaScript.FFIRuntime.
tests :: TestTree
tests = testGroup "Generate.JavaScript.FFIRuntime Tests"
  [ embeddedRuntimeTests
  , embeddedMarshalTests
  , embeddedValidateTests
  , embeddedSmartTests
  , embeddedEnvironmentTests
  , embeddedValidateMinimalTests
  , embeddedRuntimeForModeTests
  , scanAndEmitRuntimeTests
  ]

-- ---------------------------------------------------------------------------
-- embeddedRuntime
-- ---------------------------------------------------------------------------

-- | Tests for 'FFIRuntime.embeddedRuntime'.
embeddedRuntimeTests :: TestTree
embeddedRuntimeTests = testGroup "embeddedRuntime"
  [ testCase "is non-empty" $
      (BS.length (render FFIRuntime.embeddedRuntime) > 0) @?= True

  , testCase "contains the runtime header comment" $
      BS.isInfixOf "Canopy FFI Runtime" (render FFIRuntime.embeddedRuntime) @?= True

  , testCase "contains the runtime footer comment" $
      BS.isInfixOf "End Canopy FFI Runtime" (render FFIRuntime.embeddedRuntime) @?= True

  , testCase "is larger than any single embedded module" $
      let fullSize  = BS.length (render FFIRuntime.embeddedRuntime)
          marshalSz = BS.length (render FFIRuntime.embeddedMarshal)
      in (fullSize > marshalSz) @?= True

  , testCase "contains all four module markers" $
      let bs = render FFIRuntime.embeddedRuntime
          hasCanopy   = BS.isInfixOf "$canopy" bs
          hasValidate = BS.isInfixOf "$validate" bs
          hasSmart    = BS.isInfixOf "$smart" bs
          hasEnv      = BS.isInfixOf "$env" bs
      in (hasCanopy && hasValidate && hasSmart && hasEnv) @?= True
  ]

-- ---------------------------------------------------------------------------
-- embeddedMarshal
-- ---------------------------------------------------------------------------

-- | Tests for 'FFIRuntime.embeddedMarshal'.
embeddedMarshalTests :: TestTree
embeddedMarshalTests = testGroup "embeddedMarshal"
  [ testCase "is non-empty" $
      (BS.length (render FFIRuntime.embeddedMarshal) > 0) @?= True

  , testCase "declares the $canopy variable" $
      BS.isInfixOf "var $canopy" (render FFIRuntime.embeddedMarshal) @?= True

  , testCase "defines Ok constructor" $
      BS.isInfixOf "Ok:" (render FFIRuntime.embeddedMarshal) @?= True

  , testCase "defines Err constructor" $
      BS.isInfixOf "Err:" (render FFIRuntime.embeddedMarshal) @?= True

  , testCase "defines Just constructor" $
      BS.isInfixOf "Just:" (render FFIRuntime.embeddedMarshal) @?= True

  , testCase "defines Nothing value" $
      BS.isInfixOf "Nothing" (render FFIRuntime.embeddedMarshal) @?= True

  , testCase "defines toList conversion" $
      BS.isInfixOf "toList:" (render FFIRuntime.embeddedMarshal) @?= True

  , testCase "defines fromList conversion" $
      BS.isInfixOf "fromList:" (render FFIRuntime.embeddedMarshal) @?= True

  , testCase "block comment identifies module" $
      BS.isInfixOf "// $canopy" (render FFIRuntime.embeddedMarshal) @?= True
  ]

-- ---------------------------------------------------------------------------
-- embeddedValidate
-- ---------------------------------------------------------------------------

-- | Tests for 'FFIRuntime.embeddedValidate'.
embeddedValidateTests :: TestTree
embeddedValidateTests = testGroup "embeddedValidate"
  [ testCase "is non-empty" $
      (BS.length (render FFIRuntime.embeddedValidate) > 0) @?= True

  , testCase "declares the $validate variable" $
      BS.isInfixOf "var $validate" (render FFIRuntime.embeddedValidate) @?= True

  , testCase "block comment identifies module" $
      BS.isInfixOf "// $validate" (render FFIRuntime.embeddedValidate) @?= True

  , testCase "defines Int validator" $
      BS.isInfixOf "Int:" (render FFIRuntime.embeddedValidate) @?= True

  , testCase "defines Float validator" $
      BS.isInfixOf "Float:" (render FFIRuntime.embeddedValidate) @?= True

  , testCase "defines String validator" $
      BS.isInfixOf "String:" (render FFIRuntime.embeddedValidate) @?= True

  , testCase "defines Bool validator" $
      BS.isInfixOf "Bool:" (render FFIRuntime.embeddedValidate) @?= True

  , testCase "defines List validator" $
      BS.isInfixOf "List:" (render FFIRuntime.embeddedValidate) @?= True

  , testCase "defines Maybe validator" $
      BS.isInfixOf "Maybe:" (render FFIRuntime.embeddedValidate) @?= True

  , testCase "defines Result validator" $
      BS.isInfixOf "Result:" (render FFIRuntime.embeddedValidate) @?= True

  , testCase "full $validate is larger than minimal $validate" $
      let fullSz    = BS.length (render FFIRuntime.embeddedValidate)
          minimalSz = BS.length (render FFIRuntime.embeddedValidateMinimal)
      in (fullSz > minimalSz) @?= True
  ]

-- ---------------------------------------------------------------------------
-- embeddedSmart
-- ---------------------------------------------------------------------------

-- | Tests for 'FFIRuntime.embeddedSmart'.
embeddedSmartTests :: TestTree
embeddedSmartTests = testGroup "embeddedSmart"
  [ testCase "is non-empty" $
      (BS.length (render FFIRuntime.embeddedSmart) > 0) @?= True

  , testCase "declares the $smart variable" $
      BS.isInfixOf "var $smart" (render FFIRuntime.embeddedSmart) @?= True

  , testCase "block comment identifies module" $
      BS.isInfixOf "// $smart" (render FFIRuntime.embeddedSmart) @?= True

  , testCase "defines a validation level field" $
      BS.isInfixOf "level:" (render FFIRuntime.embeddedSmart) @?= True

  , testCase "default validation level is 'smart'" $
      BS.isInfixOf "'smart'" (render FFIRuntime.embeddedSmart) @?= True

  , testCase "defines Int smart validator" $
      BS.isInfixOf "Int:" (render FFIRuntime.embeddedSmart) @?= True

  , testCase "defines detectCoercion helper" $
      BS.isInfixOf "detectCoercion:" (render FFIRuntime.embeddedSmart) @?= True
  ]

-- ---------------------------------------------------------------------------
-- embeddedEnvironment
-- ---------------------------------------------------------------------------

-- | Tests for 'FFIRuntime.embeddedEnvironment'.
embeddedEnvironmentTests :: TestTree
embeddedEnvironmentTests = testGroup "embeddedEnvironment"
  [ testCase "is non-empty" $
      (BS.length (render FFIRuntime.embeddedEnvironment) > 0) @?= True

  , testCase "declares the $env variable" $
      BS.isInfixOf "var $env" (render FFIRuntime.embeddedEnvironment) @?= True

  , testCase "block comment identifies module" $
      BS.isInfixOf "// $env" (render FFIRuntime.embeddedEnvironment) @?= True

  , testCase "declares isBrowser field" $
      BS.isInfixOf "isBrowser:" (render FFIRuntime.embeddedEnvironment) @?= True

  , testCase "declares isNode field" $
      BS.isInfixOf "isNode:" (render FFIRuntime.embeddedEnvironment) @?= True

  , testCase "declares isDeno field" $
      BS.isInfixOf "isDeno:" (render FFIRuntime.embeddedEnvironment) @?= True

  , testCase "defines getRuntime function" $
      BS.isInfixOf "getRuntime:" (render FFIRuntime.embeddedEnvironment) @?= True

  , testCase "defines hasAudioContext function" $
      BS.isInfixOf "hasAudioContext:" (render FFIRuntime.embeddedEnvironment) @?= True
  ]

-- ---------------------------------------------------------------------------
-- embeddedValidateMinimal
-- ---------------------------------------------------------------------------

-- | Tests for 'FFIRuntime.embeddedValidateMinimal'.
embeddedValidateMinimalTests :: TestTree
embeddedValidateMinimalTests = testGroup "embeddedValidateMinimal"
  [ testCase "is non-empty" $
      (BS.length (render FFIRuntime.embeddedValidateMinimal) > 0) @?= True

  , testCase "declares the $validate variable" $
      BS.isInfixOf "var $validate" (render FFIRuntime.embeddedValidateMinimal) @?= True

  , testCase "header comment mentions --ffi-unsafe mode" $
      BS.isInfixOf "--ffi-unsafe" (render FFIRuntime.embeddedValidateMinimal) @?= True

  , testCase "defines Int validator" $
      BS.isInfixOf "Int:" (render FFIRuntime.embeddedValidateMinimal) @?= True

  , testCase "defines Float validator" $
      BS.isInfixOf "Float:" (render FFIRuntime.embeddedValidateMinimal) @?= True

  , testCase "defines String validator" $
      BS.isInfixOf "String:" (render FFIRuntime.embeddedValidateMinimal) @?= True

  , testCase "defines Bool validator" $
      BS.isInfixOf "Bool:" (render FFIRuntime.embeddedValidateMinimal) @?= True

  , testCase "defines Unit passthrough" $
      BS.isInfixOf "Unit:" (render FFIRuntime.embeddedValidateMinimal) @?= True

  , testCase "is strictly smaller than the full $validate" $
      let fullSz    = BS.length (render FFIRuntime.embeddedValidate)
          minimalSz = BS.length (render FFIRuntime.embeddedValidateMinimal)
      in (minimalSz < fullSz) @?= True
  ]

-- ---------------------------------------------------------------------------
-- embeddedRuntimeForMode
-- ---------------------------------------------------------------------------

-- | Tests for 'FFIRuntime.embeddedRuntimeForMode'.
embeddedRuntimeForModeTests :: TestTree
embeddedRuntimeForModeTests = testGroup "embeddedRuntimeForMode"
  [ testCase "Dev safe mode equals full embeddedRuntime" $
      render (FFIRuntime.embeddedRuntimeForMode devSafe)
        @?= render FFIRuntime.embeddedRuntime

  , testCase "Prod safe mode equals full embeddedRuntime" $
      render (FFIRuntime.embeddedRuntimeForMode prodSafe)
        @?= render FFIRuntime.embeddedRuntime

  , testCase "Dev unsafe mode contains $canopy" $
      BS.isInfixOf "var $canopy" (render (FFIRuntime.embeddedRuntimeForMode devUnsafe)) @?= True

  , testCase "Dev unsafe mode contains minimal $validate" $
      BS.isInfixOf "var $validate" (render (FFIRuntime.embeddedRuntimeForMode devUnsafe)) @?= True

  , testCase "Dev unsafe mode omits full $smart block" $
      BS.isInfixOf "var $smart" (render (FFIRuntime.embeddedRuntimeForMode devUnsafe)) @?= False

  , testCase "Dev unsafe mode retains $env" $
      BS.isInfixOf "var $env" (render (FFIRuntime.embeddedRuntimeForMode devUnsafe)) @?= True

  , testCase "Prod unsafe mode contains $canopy" $
      BS.isInfixOf "var $canopy" (render (FFIRuntime.embeddedRuntimeForMode prodUnsafe)) @?= True

  , testCase "Prod unsafe mode contains minimal $validate" $
      BS.isInfixOf "var $validate" (render (FFIRuntime.embeddedRuntimeForMode prodUnsafe)) @?= True

  , testCase "Prod unsafe mode omits full $smart block" $
      BS.isInfixOf "var $smart" (render (FFIRuntime.embeddedRuntimeForMode prodUnsafe)) @?= False

  , testCase "Prod unsafe mode omits $env" $
      BS.isInfixOf "var $env" (render (FFIRuntime.embeddedRuntimeForMode prodUnsafe)) @?= False

  , testCase "Dev unsafe output is smaller than Dev safe output" $
      let safeSize   = BS.length (render (FFIRuntime.embeddedRuntimeForMode devSafe))
          unsafeSize = BS.length (render (FFIRuntime.embeddedRuntimeForMode devUnsafe))
      in (unsafeSize < safeSize) @?= True

  , testCase "Prod unsafe output is smaller than Prod safe output" $
      let safeSize   = BS.length (render (FFIRuntime.embeddedRuntimeForMode prodSafe))
          unsafeSize = BS.length (render (FFIRuntime.embeddedRuntimeForMode prodUnsafe))
      in (unsafeSize < safeSize) @?= True

  , testCase "Prod unsafe output is smaller than Dev unsafe output (no $env)" $
      let devUnsafeSz  = BS.length (render (FFIRuntime.embeddedRuntimeForMode devUnsafe))
          prodUnsafeSz = BS.length (render (FFIRuntime.embeddedRuntimeForMode prodUnsafe))
      in (prodUnsafeSz < devUnsafeSz) @?= True
  ]

-- ---------------------------------------------------------------------------
-- scanAndEmitRuntime
-- ---------------------------------------------------------------------------

-- | Tests for 'FFIRuntime.scanAndEmitRuntime'.
scanAndEmitRuntimeTests :: TestTree
scanAndEmitRuntimeTests = testGroup "scanAndEmitRuntime"
  [ testCase "empty content emits only header and footer" $
      let result = render (FFIRuntime.scanAndEmitRuntime devSafe (BB.byteString ""))
          hasHeader = BS.isInfixOf "Canopy FFI Runtime" result
          hasFooter = BS.isInfixOf "End Canopy FFI Runtime" result
      in (hasHeader && hasFooter) @?= True

  , testCase "empty content does not emit $canopy when symbol absent" $
      let result = render (FFIRuntime.scanAndEmitRuntime devSafe (BB.byteString ""))
      in BS.isInfixOf "var $canopy" result @?= False

  , testCase "content with $canopy. triggers marshal module" $
      let content = BB.byteString "var x = $canopy.Ok(1);"
          result  = render (FFIRuntime.scanAndEmitRuntime devSafe content)
      in BS.isInfixOf "var $canopy" result @?= True

  , testCase "content without $canopy. omits marshal module" $
      let content = BB.byteString "var x = 42;"
          result  = render (FFIRuntime.scanAndEmitRuntime devSafe content)
      in BS.isInfixOf "var $canopy" result @?= False

  , testCase "content with $validate. triggers validate module in Dev safe mode" $
      let content = BB.byteString "$validate.Int(x, 'p');"
          result  = render (FFIRuntime.scanAndEmitRuntime devSafe content)
      in BS.isInfixOf "var $validate" result @?= True

  , testCase "content with $validate. omits full validate in Dev unsafe mode" $
      let content = BB.byteString "$validate.Int(x, 'p');"
          result  = render (FFIRuntime.scanAndEmitRuntime devUnsafe content)
      in BS.isInfixOf "var $validate" result @?= False

  , testCase "content with $smart. triggers smart module in Dev safe mode" $
      let content = BB.byteString "$smart.Int(x, 'p');"
          result  = render (FFIRuntime.scanAndEmitRuntime devSafe content)
      in BS.isInfixOf "var $smart" result @?= True

  , testCase "content with $smart. omits smart module in Dev unsafe mode" $
      let content = BB.byteString "$smart.Int(x, 'p');"
          result  = render (FFIRuntime.scanAndEmitRuntime devUnsafe content)
      in BS.isInfixOf "var $smart" result @?= False

  , testCase "content with $env. triggers env module in Dev mode" $
      let content = BB.byteString "if ($env.isBrowser) { }"
          result  = render (FFIRuntime.scanAndEmitRuntime devSafe content)
      in BS.isInfixOf "var $env" result @?= True

  , testCase "content with $env. omits env module in Prod mode" $
      let content = BB.byteString "if ($env.isBrowser) { }"
          result  = render (FFIRuntime.scanAndEmitRuntime prodSafe content)
      in BS.isInfixOf "var $env" result @?= False

  , testCase "scanning does not include content builder in output" $
      let marker  = "UNIQUE_MARKER_12345"
          content = BB.byteString marker
          result  = render (FFIRuntime.scanAndEmitRuntime devSafe content)
      in BS.isInfixOf marker result @?= False

  , testCase "all-symbols content in Dev safe mode includes all four modules" $
      let content = BB.byteString "$canopy.Ok($validate.Int($smart.Int($env.isBrowser)));"
          result  = render (FFIRuntime.scanAndEmitRuntime devSafe content)
          hasCanopy   = BS.isInfixOf "var $canopy" result
          hasValidate = BS.isInfixOf "var $validate" result
          hasSmart    = BS.isInfixOf "var $smart" result
          hasEnv      = BS.isInfixOf "var $env" result
      in (hasCanopy && hasValidate && hasSmart && hasEnv) @?= True
  ]

{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI.Resolve module.
--
-- Tests unified FFI resolution covering kernel module detection, kernel
-- resolution for all trusted authors, user FFI path conversion, trust
-- boundary enforcement, and error type verification.
--
-- @since 0.19.2
module Unit.FFI.ResolveTest (tests) where

import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Package as Pkg
import qualified FFI.Resolve as Resolve
import qualified FFI.Types as FFI
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI.Resolve Tests"
    [ testKernelDetection,
      testKernelResolution,
      testUserFFIResolution,
      testTrustBoundary,
      testTrustedAuthors,
      testPathConversion,
      testErrorTypes,
      testFunctionNamePreservation
    ]

-- KERNEL DETECTION TESTS

testKernelDetection :: TestTree
testKernelDetection =
  testGroup
    "Kernel module detection"
    [ testCase "Kernel.Utils is a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "Kernel.Utils") @?= True,
      testCase "Kernel.Scheduler is a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "Kernel.Scheduler") @?= True,
      testCase "Kernel.Platform is a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "Kernel.Platform") @?= True,
      testCase "Kernel.Browser.Dom is a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "Kernel.Browser.Dom") @?= True,
      testCase "List is not a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "List") @?= False,
      testCase "Platform.Cmd is not a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "Platform.Cmd") @?= False,
      testCase "empty module name is not a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "") @?= False,
      testCase "Kernelx is not a kernel module (no dot)" $
        Resolve.isKernelModule (Utf8.fromChars "Kernelx") @?= False,
      testCase "kernel (lowercase) is not a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "kernel.Utils") @?= False,
      testCase "MyKernel.Utils is not a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "MyKernel.Utils") @?= False,
      testCase "KernelUtils is not a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "KernelUtils") @?= False
    ]

-- KERNEL RESOLUTION TESTS

testKernelResolution :: TestTree
testKernelResolution =
  testGroup
    "Kernel FFI resolution"
    [ testCase "trusted package resolves to KernelOrigin" $ do
        let result = Resolve.resolveFFIReference Pkg.core (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.KernelOrigin modName _ -> modName @?= "Utils"
              _ -> assertFailure "Expected KernelOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "kernel resolution strips Kernel. prefix" $ do
        let result = Resolve.resolveFFIReference Pkg.core (Utf8.fromChars "Kernel.Scheduler") "rawSpawn"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.KernelOrigin modName _ -> modName @?= "Scheduler"
              _ -> assertFailure "Expected KernelOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "kernel resolution preserves function name in origin" $ do
        let result = Resolve.resolveFFIReference Pkg.core (Utf8.fromChars "Kernel.Utils") "compare"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.KernelOrigin _ funcName -> funcName @?= "compare"
              _ -> assertFailure "Expected KernelOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "kernel resolution sets _resolvedName to funcName" $ do
        let result = Resolve.resolveFFIReference Pkg.core (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Right resolved -> Resolve._resolvedName resolved @?= "eq"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "multi-segment kernel module strips Kernel. prefix only" $ do
        let result = Resolve.resolveFFIReference Pkg.core (Utf8.fromChars "Kernel.Browser.Dom") "focus"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.KernelOrigin modName _ -> modName @?= "Browser.Dom"
              _ -> assertFailure "Expected KernelOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err)
    ]

-- USER FFI RESOLUTION TESTS

testUserFFIResolution :: TestTree
testUserFFIResolution =
  testGroup
    "User FFI resolution"
    [ testCase "non-kernel module resolves to UserFFIOrigin" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "MyModule") "fetchData"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin _ _ -> pure ()
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "simple module name produces flat path" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "MyModule") "fetchData"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin (FFI.JsSourcePath path) _ -> path @?= "MyModule.ffi.js"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "dotted module name replaces dots with slashes" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Data.Json") "parse"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin (FFI.JsSourcePath path) _ -> path @?= "Data/Json.ffi.js"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "three-segment module name produces nested path" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Data.Decode.Json") "run"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin (FFI.JsSourcePath path) _ -> path @?= "Data/Decode/Json.ffi.js"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "user FFI function name preserved in origin" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "MyModule") "doWork"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin _ (FFI.FFIFuncName fname) -> fname @?= "doWork"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "user FFI sets _resolvedName to funcName" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "MyModule") "compute"
        case result of
          Right resolved -> Resolve._resolvedName resolved @?= "compute"
          Left err -> assertFailure ("Expected success, got: " ++ show err)
    ]

-- TRUST BOUNDARY TESTS

testTrustBoundary :: TestTree
testTrustBoundary =
  testGroup
    "Trust boundary enforcement"
    [ testCase "untrusted package cannot use kernel modules" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Left (Resolve.KernelNotAllowed _ _) -> pure ()
          Left err -> assertFailure ("Expected KernelNotAllowed, got: " ++ show err)
          Right _ -> assertFailure "Expected failure for untrusted kernel access",
      testCase "KernelNotAllowed carries module name" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Left (Resolve.KernelNotAllowed modName _) -> modName @?= "Kernel.Utils"
          _ -> assertFailure "Expected KernelNotAllowed with module name",
      testCase "KernelNotAllowed carries function name" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Kernel.Utils") "badCall"
        case result of
          Left (Resolve.KernelNotAllowed _ funcName) -> funcName @?= "badCall"
          _ -> assertFailure "Expected KernelNotAllowed with function name"
    ]

-- TRUSTED AUTHOR TESTS

testTrustedAuthors :: TestTree
testTrustedAuthors =
  testGroup
    "Trusted authors allowed to use kernel modules"
    [ testCase "elm-authored packages are trusted" $ do
        let elmPkg = Pkg.Name (Utf8.fromChars "elm") (Utf8.fromChars "browser")
            result = Resolve.resolveFFIReference elmPkg (Utf8.fromChars "Kernel.Browser") "call"
        case result of
          Right _ -> pure ()
          Left err -> assertFailure ("Expected success for elm package, got: " ++ show err),
      testCase "canopy-authored packages are trusted" $ do
        let canopyPkg = Pkg.Name (Utf8.fromChars "canopy") (Utf8.fromChars "core")
            result = Resolve.resolveFFIReference canopyPkg (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Right _ -> pure ()
          Left err -> assertFailure ("Expected success for canopy package, got: " ++ show err),
      testCase "elm-explorations packages are trusted" $ do
        let explorationsPkg = Pkg.Name (Utf8.fromChars "elm-explorations") (Utf8.fromChars "webgl")
            result = Resolve.resolveFFIReference explorationsPkg (Utf8.fromChars "Kernel.WebGL") "render"
        case result of
          Right _ -> pure ()
          Left err -> assertFailure ("Expected success for elm-explorations, got: " ++ show err),
      testCase "canopy-explorations packages are trusted" $ do
        let explorationsPkg = Pkg.Name (Utf8.fromChars "canopy-explorations") (Utf8.fromChars "audio")
            result = Resolve.resolveFFIReference explorationsPkg (Utf8.fromChars "Kernel.Audio") "play"
        case result of
          Right _ -> pure ()
          Left err -> assertFailure ("Expected success for canopy-explorations, got: " ++ show err)
    ]

-- PATH CONVERSION TESTS

testPathConversion :: TestTree
testPathConversion =
  testGroup
    "Path conversion"
    [ testCase "single-word module maps to ModuleName.ffi.js" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Audio") "play"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin (FFI.JsSourcePath p) _ -> p @?= "Audio.ffi.js"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Unexpected error: " ++ show err),
      testCase "path extension is always .ffi.js" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Data.List") "map"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin (FFI.JsSourcePath p) _ ->
                p @?= "Data/List.ffi.js"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Unexpected error: " ++ show err)
    ]

-- ERROR TYPE TESTS

testErrorTypes :: TestTree
testErrorTypes =
  testGroup
    "Error type structure"
    [ testCase "FFINotFound is not produced by resolveFFIReference" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Missing") "func"
        case result of
          Left (Resolve.FFINotFound _ _) -> assertFailure "Unexpected FFINotFound"
          Left (Resolve.KernelNotAllowed _ _) -> assertFailure "Unexpected KernelNotAllowed"
          Right _ -> pure ()
    ]

-- FUNCTION NAME PRESERVATION TESTS

testFunctionNamePreservation :: TestTree
testFunctionNamePreservation =
  testGroup
    "Function name preservation"
    [ testCase "hyphenated function name preserved in user FFI" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Dom") "get-element-by-id"
        case result of
          Right resolved -> Resolve._resolvedName resolved @?= "get-element-by-id"
          Left err -> assertFailure ("Unexpected error: " ++ show err),
      testCase "camelCase function name preserved" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Dom") "getElementById"
        case result of
          Right resolved -> Resolve._resolvedName resolved @?= "getElementById"
          Left err -> assertFailure ("Unexpected error: " ++ show err)
    ]

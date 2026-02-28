{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI.Resolve module.
--
-- Tests unified FFI resolution covering both kernel module and
-- user FFI binding paths.
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
      testTrustBoundary
    ]

testKernelDetection :: TestTree
testKernelDetection =
  testGroup
    "Kernel module detection"
    [ testCase "Kernel.Utils is a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "Kernel.Utils") @?= True,
      testCase "Kernel.Scheduler is a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "Kernel.Scheduler") @?= True,
      testCase "List is not a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "List") @?= False,
      testCase "Platform.Cmd is not a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "Platform.Cmd") @?= False,
      testCase "empty module name is not a kernel module" $
        Resolve.isKernelModule (Utf8.fromChars "") @?= False
    ]

testKernelResolution :: TestTree
testKernelResolution =
  testGroup
    "Kernel FFI resolution"
    [ testCase "trusted package can use kernel modules" $ do
        let result = Resolve.resolveFFIReference Pkg.core (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Right resolved -> do
            Resolve._resolvedName resolved @?= "eq"
            case Resolve._resolvedOrigin resolved of
              Resolve.KernelOrigin modName funcName -> do
                modName @?= "Utils"
                funcName @?= "eq"
              _ -> assertFailure "Expected KernelOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "kernel resolution preserves function name" $ do
        let result = Resolve.resolveFFIReference Pkg.core (Utf8.fromChars "Kernel.Scheduler") "rawSpawn"
        case result of
          Right resolved ->
            Resolve._resolvedName resolved @?= "rawSpawn"
          Left err -> assertFailure ("Expected success, got: " ++ show err)
    ]

testUserFFIResolution :: TestTree
testUserFFIResolution =
  testGroup
    "User FFI resolution"
    [ testCase "non-kernel module resolves to user FFI" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "MyModule") "fetchData"
        case result of
          Right resolved -> do
            Resolve._resolvedName resolved @?= "fetchData"
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin (FFI.JsSourcePath path) (FFI.FFIFuncName fname) -> do
                path @?= "MyModule.ffi.js"
                fname @?= "fetchData"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "dotted module name produces correct path" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Data.Json") "parse"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin (FFI.JsSourcePath path) _ ->
                path @?= "Data/Json.ffi.js"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err)
    ]

testTrustBoundary :: TestTree
testTrustBoundary =
  testGroup
    "Trust boundary enforcement"
    [ testCase "non-elm package cannot use kernel modules" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Left (Resolve.KernelNotAllowed _ _) -> pure ()
          Left err -> assertFailure ("Expected KernelNotAllowed, got: " ++ show err)
          Right _ -> assertFailure "Expected failure for untrusted kernel access",
      testCase "elm-authored packages are trusted" $ do
        let elmPkg = Pkg.Name (Utf8.fromChars "elm") (Utf8.fromChars "browser")
            result = Resolve.resolveFFIReference elmPkg (Utf8.fromChars "Kernel.Browser") "call"
        case result of
          Right _ -> pure ()
          Left err -> assertFailure ("Expected success for elm package, got: " ++ show err)
    ]

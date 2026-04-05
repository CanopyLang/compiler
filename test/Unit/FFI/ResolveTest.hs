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
      testTrustBoundary,
      testModuleToJsPath,
      testModuleToDtsPath,
      testAllTrustedAuthors,
      testKernelModuleNameExtraction,
      testUserFFIPathVariants
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

testModuleToJsPath :: TestTree
testModuleToJsPath =
  testGroup
    "moduleToJsPath"
    [ testCase "simple module name" $
        Resolve.moduleToJsPath (Utf8.fromChars "Main") @?= "Main.ffi.js",
      testCase "dotted module name replaces dots with slashes" $
        Resolve.moduleToJsPath (Utf8.fromChars "Foo.Bar") @?= "Foo/Bar.ffi.js",
      testCase "three-segment module name" $
        Resolve.moduleToJsPath (Utf8.fromChars "Data.Json.Decode") @?= "Data/Json/Decode.ffi.js",
      testCase "single-letter module name" $
        Resolve.moduleToJsPath (Utf8.fromChars "A") @?= "A.ffi.js",
      testCase "preserves non-dot characters" $
        Resolve.moduleToJsPath (Utf8.fromChars "My_Module") @?= "My_Module.ffi.js"
    ]

testModuleToDtsPath :: TestTree
testModuleToDtsPath =
  testGroup
    "moduleToDtsPath"
    [ testCase "simple module name gets .ffi.d.ts" $
        Resolve.moduleToDtsPath (Utf8.fromChars "Main") @?= "Main.ffi.d.ts",
      testCase "dotted module name replaces dots with slashes" $
        Resolve.moduleToDtsPath (Utf8.fromChars "Foo.Bar") @?= "Foo/Bar.ffi.d.ts",
      testCase "three-segment module name" $
        Resolve.moduleToDtsPath (Utf8.fromChars "Data.Json.Decode") @?= "Data/Json/Decode.ffi.d.ts",
      testCase "js and dts paths share the same base" $
        let modName = Utf8.fromChars "Audio.Context"
            jsPath = Resolve.moduleToJsPath modName
            dtsPath = Resolve.moduleToDtsPath modName
         in take 13 jsPath @?= take 13 dtsPath
    ]

testAllTrustedAuthors :: TestTree
testAllTrustedAuthors =
  testGroup
    "all trusted authors"
    [ testCase "canopy-authored packages are trusted" $ do
        let canopyPkg = Pkg.Name (Utf8.fromChars "canopy") (Utf8.fromChars "core")
            result = Resolve.resolveFFIReference canopyPkg (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Right _ -> pure ()
          Left err -> assertFailure ("Expected success for canopy pkg, got: " ++ show err),
      testCase "elm-explorations packages are trusted" $ do
        let elmExpPkg = Pkg.Name (Utf8.fromChars "elm-explorations") (Utf8.fromChars "webgl")
            result = Resolve.resolveFFIReference elmExpPkg (Utf8.fromChars "Kernel.WebGL") "render"
        case result of
          Right _ -> pure ()
          Left err -> assertFailure ("Expected success for elm-explorations, got: " ++ show err),
      testCase "canopy-explorations packages are trusted" $ do
        let canopyExpPkg = Pkg.Name (Utf8.fromChars "canopy-explorations") (Utf8.fromChars "audio")
            result = Resolve.resolveFFIReference canopyExpPkg (Utf8.fromChars "Kernel.Audio") "decode"
        case result of
          Right _ -> pure ()
          Left err -> assertFailure ("Expected success for canopy-explorations, got: " ++ show err),
      testCase "zokka packages are not trusted" $ do
        let zokkaPkg = Pkg.Name (Utf8.fromChars "zokka") (Utf8.fromChars "core")
            result = Resolve.resolveFFIReference zokkaPkg (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Left (Resolve.KernelNotAllowed _ _) -> pure ()
          Left err -> assertFailure ("Expected KernelNotAllowed, got: " ++ show err)
          Right _ -> assertFailure "Expected failure for zokka package"
    ]

testKernelModuleNameExtraction :: TestTree
testKernelModuleNameExtraction =
  testGroup
    "kernel module name extraction"
    [ testCase "strips Kernel. prefix to get module name" $ do
        let result = Resolve.resolveFFIReference Pkg.core (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.KernelOrigin modName _ -> modName @?= "Utils"
              _ -> assertFailure "Expected KernelOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "preserves deeply nested kernel module name" $ do
        let result = Resolve.resolveFFIReference Pkg.core (Utf8.fromChars "Kernel.Platform") "sendToSelf"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.KernelOrigin modName fname -> do
                modName @?= "Platform"
                fname @?= "sendToSelf"
              _ -> assertFailure "Expected KernelOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "KernelNotAllowed error contains module name" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Kernel.Utils") "eq"
        case result of
          Left (Resolve.KernelNotAllowed modName _) ->
            modName @?= "Kernel.Utils"
          Left err -> assertFailure ("Expected KernelNotAllowed, got: " ++ show err)
          Right _ -> assertFailure "Expected failure"
    ]

testUserFFIPathVariants :: TestTree
testUserFFIPathVariants =
  testGroup
    "user FFI path variants"
    [ testCase "deeply nested module produces correct path" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "A.B.C.D") "fn"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin (FFI.JsSourcePath path) _ ->
                path @?= "A/B/C/D.ffi.js"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "user FFI function name preserved in origin" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "MyModule") "processData"
        case result of
          Right resolved ->
            case Resolve._resolvedOrigin resolved of
              Resolve.UserFFIOrigin _ (FFI.FFIFuncName fname) ->
                fname @?= "processData"
              _ -> assertFailure "Expected UserFFIOrigin"
          Left err -> assertFailure ("Expected success, got: " ++ show err),
      testCase "user FFI resolved name matches function name" $ do
        let userPkg = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "app")
            result = Resolve.resolveFFIReference userPkg (Utf8.fromChars "Mod") "myFunc"
        case result of
          Right resolved -> Resolve._resolvedName resolved @?= "myFunc"
          Left err -> assertFailure ("Expected success, got: " ++ show err)
    ]

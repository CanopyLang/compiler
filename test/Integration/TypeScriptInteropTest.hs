{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for the TypeScript interop pipeline.
--
-- Tests the end-to-end flow of:
--   1. Converting Canopy types to TypeScript declarations
--   2. Rendering .d.ts output from those declarations
--   3. NpmPipeline type mapping and wrapper generation
--
-- These tests verify that the full TypeScript generation pipeline
-- produces correct output without relying on golden files.
--
-- @since 0.20.1
module Integration.TypeScriptInteropTest (tests) where

import qualified Canopy.Data.Name as Name
import Canopy.Data.Name (Name)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BSL
import FFI.NpmPipeline (tsTypeToParamConversion, tsTypeToReturnConversion)
import Generate.JavaScript.NpmWrapper (ParamConversion (..), ReturnConversion (..))
import Generate.TypeScript.Render (renderDecl, renderDecls, renderWebComponentTagMap)
import Generate.TypeScript.Types (DtsDecl (..), TsType (..))
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup
    "TypeScript Interop Integration"
    [ dtsRenderPipelineTests,
      npmTypeMapTests,
      webComponentDtsTests
    ]

-- | Test the full .d.ts rendering pipeline from declarations to text.
dtsRenderPipelineTests :: TestTree
dtsRenderPipelineTests =
  Test.testGroup
    "DTS render pipeline"
    [ dtsValueRoundtripTest,
      dtsUnionRoundtripTest,
      dtsRecordAliasRoundtripTest,
      dtsBrandedRoundtripTest,
      dtsMultiDeclRoundtripTest
    ]

dtsValueRoundtripTest :: TestTree
dtsValueRoundtripTest =
  HUnit.testCase "value export renders to correct .d.ts" $
    renderToStr (DtsValue (n "greet") (TsFunction [TsString] TsString))
      @?= "export const greet: (p0: string) => string;\n"

dtsUnionRoundtripTest :: TestTree
dtsUnionRoundtripTest =
  HUnit.testCase "union type renders with discriminated tags" $
    renderToStr
      ( DtsUnionType
          (n "Color")
          []
          ( TsUnion
              [ TsTaggedVariant (n "Red") [],
                TsTaggedVariant (n "Green") [],
                TsTaggedVariant (n "Blue") []
              ]
          )
      )
      @?= "export type Color = { readonly $: 'Red' } | { readonly $: 'Green' } | { readonly $: 'Blue' };\n"

dtsRecordAliasRoundtripTest :: TestTree
dtsRecordAliasRoundtripTest =
  HUnit.testCase "record alias renders with readonly fields" $
    renderToStr
      ( DtsTypeAlias
          (n "Point")
          []
          (TsObject [(n "x", TsNumber), (n "y", TsNumber)])
      )
      @?= "export type Point = { readonly x: number; readonly y: number };\n"

dtsBrandedRoundtripTest :: TestTree
dtsBrandedRoundtripTest =
  HUnit.testCase "branded type renders with unique symbol" $
    renderToStr (DtsBrandedType (n "UserId") [])
      @?= "export type UserId = { readonly __brand: unique symbol };\n"

dtsMultiDeclRoundtripTest :: TestTree
dtsMultiDeclRoundtripTest =
  HUnit.testCase "multiple declarations separated by blank lines" $
    let decls =
          [ DtsValue (n "x") TsNumber,
            DtsValue (n "y") TsString
          ]
        output = BSL.unpack (BB.toLazyByteString (renderDecls decls))
     in output @?= "export const x: number;\n\nexport const y: string;\n\n"

-- | Test NpmPipeline type mapping from TypeScript types to FFI conversions.
npmTypeMapTests :: TestTree
npmTypeMapTests =
  Test.testGroup
    "NpmPipeline type mapping"
    [ npmParamPassThroughTest,
      npmParamUnwrapMaybeTest,
      npmParamUnwrapNewtypeTest,
      npmParamConvertCallbackTest,
      npmReturnDirectTest,
      npmReturnPromiseTest,
      npmReturnCmdTest,
      npmReturnNullableTest
    ]

npmParamPassThroughTest :: TestTree
npmParamPassThroughTest =
  HUnit.testCase "string param maps to PassThrough" $
    tsTypeToParamConversion TsString @?= PassThrough

npmParamUnwrapMaybeTest :: TestTree
npmParamUnwrapMaybeTest =
  HUnit.testCase "union param maps to UnwrapMaybe" $
    tsTypeToParamConversion (TsUnion []) @?= UnwrapMaybe

npmParamUnwrapNewtypeTest :: TestTree
npmParamUnwrapNewtypeTest =
  HUnit.testCase "object param maps to UnwrapNewtype" $
    tsTypeToParamConversion (TsObject []) @?= UnwrapNewtype

npmParamConvertCallbackTest :: TestTree
npmParamConvertCallbackTest =
  HUnit.testCase "function param maps to ConvertCallback" $
    tsTypeToParamConversion (TsFunction [TsString] TsVoid) @?= ConvertCallback

npmReturnDirectTest :: TestTree
npmReturnDirectTest =
  HUnit.testCase "number return maps to ReturnDirect" $
    tsTypeToReturnConversion TsNumber @?= ReturnDirect

npmReturnPromiseTest :: TestTree
npmReturnPromiseTest =
  HUnit.testCase "Promise return maps to WrapPromise" $
    tsTypeToReturnConversion (TsNamed (n "Promise") [TsString]) @?= WrapPromise

npmReturnCmdTest :: TestTree
npmReturnCmdTest =
  HUnit.testCase "void return maps to ReturnCmd" $
    tsTypeToReturnConversion TsVoid @?= ReturnCmd

npmReturnNullableTest :: TestTree
npmReturnNullableTest =
  HUnit.testCase "union return maps to WrapNullable" $
    tsTypeToReturnConversion (TsUnion []) @?= WrapNullable

-- | Test Web Component tag map .d.ts generation.
webComponentDtsTests :: TestTree
webComponentDtsTests =
  Test.testGroup
    "WebComponent .d.ts tag map"
    [ tagMapSingleModuleTest,
      tagMapMultiModuleTest
    ]

tagMapSingleModuleTest :: TestTree
tagMapSingleModuleTest =
  HUnit.testCase "single module generates correct tag map entry" $
    let output = BSL.unpack (BB.toLazyByteString (renderWebComponentTagMap [Name.fromChars "MyApp.Counter"]))
     in do
          HUnit.assertBool "contains HTMLElementTagNameMap"
            (isIn "HTMLElementTagNameMap" output)
          HUnit.assertBool "maps tag to HTMLElement"
            (isIn "\"my-app-counter\": HTMLElement" output)

tagMapMultiModuleTest :: TestTree
tagMapMultiModuleTest =
  HUnit.testCase "multiple modules generate correct tag map entries" $
    let mods = [Name.fromChars "App.Header", Name.fromChars "App.Footer"]
        output = BSL.unpack (BB.toLazyByteString (renderWebComponentTagMap mods))
     in do
          HUnit.assertBool "contains app-header entry"
            (isIn "\"app-header\": HTMLElement" output)
          HUnit.assertBool "contains app-footer entry"
            (isIn "\"app-footer\": HTMLElement" output)


-- Helpers

n :: String -> Name
n = Name.fromChars

renderToStr :: DtsDecl -> String
renderToStr = BSL.unpack . BB.toLazyByteString . renderDecl

isIn :: String -> String -> Bool
isIn needle haystack = any (startsWith needle) (tails haystack)
  where
    startsWith [] _ = True
    startsWith _ [] = False
    startsWith (a : as') (b : bs) = a == b && startsWith as' bs
    tails [] = [[]]
    tails s@(_ : rest) = s : tails rest

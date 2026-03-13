{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for the TypeScript interop pipeline.
--
-- Tests the end-to-end flow of:
--   1. Converting Canopy types to TypeScript declarations
--   2. Rendering .d.ts output from those declarations
--   3. NpmPipeline type mapping and wrapper generation
--   4. Verification of generated .d.ts files via @tsc --noEmit@
--
-- These tests verify that the full TypeScript generation pipeline
-- produces correct output without relying on golden files.
--
-- @since 0.20.1
module Integration.TypeScriptInteropTest (tests) where

import qualified Canopy.Data.Name as Name
import Canopy.Data.Name (Name)
import qualified Control.Exception as Exception
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BSL
import FFI.NpmPipeline (tsTypeToParamConversion, tsTypeToReturnConversion)
import Generate.JavaScript.NpmWrapper (ParamConversion (..), ReturnConversion (..))
import Generate.TypeScript.Render (renderDecl, renderDecls, renderWebComponentTagMap)
import Generate.TypeScript.Types (DtsDecl (..), TsType (..))
import qualified System.Directory as Dir
import System.Exit (ExitCode (..))
import qualified System.IO as IO
import System.IO.Temp (withSystemTempDirectory)
import qualified System.Process as Process
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
      webComponentDtsTests,
      tscVerificationTests
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
--
-- Asserts the exact rendered output of 'renderWebComponentTagMap' rather than
-- using weak substring checks, since the output is fully deterministic.
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
    BSL.unpack (BB.toLazyByteString (renderWebComponentTagMap [Name.fromChars "MyApp.Counter"]))
      @?= expectedSingleTagMap
  where
    expectedSingleTagMap =
      "declare global {\n"
        ++ "  interface HTMLElementTagNameMap {\n"
        ++ "    \"my-app-counter\": HTMLElement;\n"
        ++ "  }\n"
        ++ "}\n"

tagMapMultiModuleTest :: TestTree
tagMapMultiModuleTest =
  HUnit.testCase "multiple modules generate correct tag map entries" $
    BSL.unpack (BB.toLazyByteString (renderWebComponentTagMap mods))
      @?= expectedMultiTagMap
  where
    mods = [Name.fromChars "App.Header", Name.fromChars "App.Footer"]
    expectedMultiTagMap =
      "declare global {\n"
        ++ "  interface HTMLElementTagNameMap {\n"
        ++ "    \"app-header\": HTMLElement;\n"
        ++ "    \"app-footer\": HTMLElement;\n"
        ++ "  }\n"
        ++ "}\n"

-- | Tests that run @tsc --noEmit@ against generated @.d.ts@ files.
--
-- Each test generates a complete @.d.ts@ from a set of declarations, writes
-- it to a temporary directory alongside a consumer @.ts@ file and a minimal
-- @tsconfig.json@, then asserts that @tsc --noEmit@ exits with code 0.
--
-- When @tsc@ is not available on @PATH@, all tests in this group are skipped
-- gracefully: the IO action exits without failing.
tscVerificationTests :: TestTree
tscVerificationTests =
  Test.testGroup
    "tsc --noEmit verification"
    [ tscValueExportsTest,
      tscUnionPatternMatchTest,
      tscWebComponentTagMapTest
    ]

-- | Verify that generated value declarations are accepted by @tsc@.
--
-- Generates a @.d.ts@ with two value exports — a plain number and a
-- string-returning function — then writes a @.ts@ consumer that references
-- both.  Asserts @tsc --noEmit@ succeeds.
tscValueExportsTest :: TestTree
tscValueExportsTest =
  HUnit.testCase "value exports accepted by tsc" $
    withTscOrSkip $ \tscPath ->
      withSystemTempDirectory "can-tsc-values" $ \tmp ->
        Exception.finally
          (runTscTest tscPath tmp valuesDts valuesTs)
          (pure ())
  where
    valuesDts = BSL.unpack (BB.toLazyByteString (renderDecls valueDecls))
    valueDecls =
      [ DtsValue (n "count") TsNumber,
        DtsValue (n "greet") (TsFunction [TsString] TsString)
      ]
    valuesTs =
      "import { count, greet } from './types';\n"
        ++ "const _c: number = count;\n"
        ++ "const _g: string = greet('hello');\n"
        ++ "export { _c, _g };\n"

-- | Verify that a discriminated union generated from Canopy is accepted by @tsc@.
--
-- Generates a @.d.ts@ with a tagged union type then writes a @.ts@ consumer
-- that narrows on the @$@ discriminant.  Asserts @tsc --noEmit@ succeeds.
tscUnionPatternMatchTest :: TestTree
tscUnionPatternMatchTest =
  HUnit.testCase "tagged union pattern match accepted by tsc" $
    withTscOrSkip $ \tscPath ->
      withSystemTempDirectory "can-tsc-union" $ \tmp ->
        Exception.finally
          (runTscTest tscPath tmp unionDts unionTs)
          (pure ())
  where
    unionDts = renderToStr colorUnionDecl
    colorUnionDecl =
      DtsUnionType
        (n "Color")
        []
        ( TsUnion
            [ TsTaggedVariant (n "Red") [],
              TsTaggedVariant (n "Green") [],
              TsTaggedVariant (n "Blue") []
            ]
        )
    unionTs =
      "import { Color } from './types';\n"
        ++ "function label(c: Color): string {\n"
        ++ "  if (c.$ === 'Red') return 'red';\n"
        ++ "  if (c.$ === 'Green') return 'green';\n"
        ++ "  return 'blue';\n"
        ++ "}\n"
        ++ "export { label };\n"

-- | Verify that an @HTMLElementTagNameMap@ augmentation is accepted by @tsc@.
--
-- Generates a @.d.ts@ with a web-component tag map augmentation then writes
-- a @.tsx@ consumer that calls @document.createElement@ with the custom tag.
-- Asserts @tsc --noEmit@ succeeds.
tscWebComponentTagMapTest :: TestTree
tscWebComponentTagMapTest =
  HUnit.testCase "web component tag map accepted by tsc" $
    withTscOrSkip $ \tscPath ->
      withSystemTempDirectory "can-tsc-wc" $ \tmp ->
        Exception.finally
          (runTscTest tscPath tmp tagMapDts tagMapTs)
          (pure ())
  where
    tagMapDts =
      BSL.unpack (BB.toLazyByteString (renderWebComponentTagMap [Name.fromChars "My.Widget"]))
    tagMapTs =
      "/// <reference path=\"./types.d.ts\" />\n"
        ++ "const el: HTMLElement = document.createElement('my-widget');\n"
        ++ "export { el };\n"

-- INTERNAL HELPERS

-- | Write temp files and invoke @tsc --noEmit@, asserting exit code 0.
runTscTest :: FilePath -> FilePath -> String -> String -> IO ()
runTscTest tscPath tmp dtsContent tsContent = do
  writeFileUtf8 (tmp ++ "/types.d.ts") dtsContent
  writeFileUtf8 (tmp ++ "/consumer.ts") tsContent
  writeFileUtf8 (tmp ++ "/tsconfig.json") tsconfigJson
  (code, _out, err) <- Process.readProcessWithExitCode tscPath tscArgs ""
  HUnit.assertEqual ("tsc exited non-zero:\n" ++ err) ExitSuccess code
  where
    tscArgs = ["--noEmit", "--project", tmp ++ "/tsconfig.json"]
    tsconfigJson =
      "{ \"compilerOptions\": { \"strict\": true, \"target\": \"ES2020\","
        ++ " \"moduleResolution\": \"node\", \"allowJs\": false },"
        ++ " \"include\": [\"" ++ tmp ++ "/consumer.ts\"] }"

-- | Run an IO action with the path to @tsc@, or skip the test if unavailable.
withTscOrSkip :: (FilePath -> IO ()) -> IO ()
withTscOrSkip action = do
  mPath <- Dir.findExecutable "tsc"
  maybe (IO.hPutStrLn IO.stderr "tsc not found — skipping") action mPath

-- | Write a 'String' to a file in UTF-8.
writeFileUtf8 :: FilePath -> String -> IO ()
writeFileUtf8 path content =
  IO.withFile path IO.WriteMode $ \h -> do
    IO.hSetEncoding h IO.utf8
    IO.hPutStr h content

-- Helpers

n :: String -> Name
n = Name.fromChars

renderToStr :: DtsDecl -> String
renderToStr = BSL.unpack . BB.toLazyByteString . renderDecl

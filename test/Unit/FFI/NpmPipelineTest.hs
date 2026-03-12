{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for the npm FFI pipeline type mapping and wrapper generation.
--
-- Tests 'tsTypeToParamConversion', 'tsTypeToReturnConversion' for correct
-- TypeScript-to-Canopy type mapping, and 'generateNpmWrapper' for correct
-- JavaScript wrapper output.
--
-- @since 0.20.1
module Unit.FFI.NpmPipelineTest
  ( tests
  ) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BSL
import FFI.NpmPipeline (tsTypeToParamConversion, tsTypeToReturnConversion)
import Generate.JavaScript.NpmWrapper (ParamConversion (..), ReturnConversion (..), WrapperConfig (..), generateNpmWrapper)
import Generate.TypeScript.Types (TsType (..))
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

builderToString :: BB.Builder -> String
builderToString = BSL.unpack . BB.toLazyByteString

tests :: TestTree
tests =
  Test.testGroup
    "FFI.NpmPipeline"
    [ paramConversionTests,
      returnConversionTests,
      wrapperGenerationTests
    ]

paramConversionTests :: TestTree
paramConversionTests =
  Test.testGroup
    "tsTypeToParamConversion"
    [ HUnit.testCase "TsString maps to PassThrough" $
        tsTypeToParamConversion TsString @?= PassThrough,
      HUnit.testCase "TsNumber maps to PassThrough" $
        tsTypeToParamConversion TsNumber @?= PassThrough,
      HUnit.testCase "TsBoolean maps to PassThrough" $
        tsTypeToParamConversion TsBoolean @?= PassThrough,
      HUnit.testCase "TsVoid maps to PassThrough" $
        tsTypeToParamConversion TsVoid @?= PassThrough,
      HUnit.testCase "TsUnion maps to UnwrapMaybe" $
        tsTypeToParamConversion (TsUnion [TsString, TsVoid]) @?= UnwrapMaybe,
      HUnit.testCase "TsUnion with multiple types maps to UnwrapMaybe" $
        tsTypeToParamConversion (TsUnion [TsNumber, TsString, TsVoid]) @?= UnwrapMaybe,
      HUnit.testCase "TsObject maps to UnwrapNewtype" $
        tsTypeToParamConversion (TsObject []) @?= UnwrapNewtype,
      HUnit.testCase "TsUnknown maps to PassThrough" $
        tsTypeToParamConversion TsUnknown @?= PassThrough,
      HUnit.testCase "TsFunction maps to ConvertCallback" $
        tsTypeToParamConversion (TsFunction [TsString] TsVoid) @?= ConvertCallback
    ]

returnConversionTests :: TestTree
returnConversionTests =
  Test.testGroup
    "tsTypeToReturnConversion"
    [ HUnit.testCase "TsString maps to ReturnDirect" $
        tsTypeToReturnConversion TsString @?= ReturnDirect,
      HUnit.testCase "TsNumber maps to ReturnDirect" $
        tsTypeToReturnConversion TsNumber @?= ReturnDirect,
      HUnit.testCase "TsVoid maps to ReturnCmd" $
        tsTypeToReturnConversion TsVoid @?= ReturnCmd,
      HUnit.testCase "TsUnion maps to WrapNullable" $
        tsTypeToReturnConversion (TsUnion [TsString, TsVoid]) @?= WrapNullable,
      HUnit.testCase "TsBoolean maps to ReturnDirect" $
        tsTypeToReturnConversion TsBoolean @?= ReturnDirect,
      HUnit.testCase "TsUnknown maps to ReturnDirect" $
        tsTypeToReturnConversion TsUnknown @?= ReturnDirect
    ]

wrapperGenerationTests :: TestTree
wrapperGenerationTests =
  Test.testGroup
    "generateNpmWrapper"
    [ passThroughWrapperTest,
      unwrapMaybeWrapperTest,
      wrapPromiseWrapperTest,
      wrapCallbackWrapperTest
    ]

passThroughWrapperTest :: TestTree
passThroughWrapperTest =
  HUnit.testCase "PassThrough config generates import and direct return" $
    let config = WrapperConfig
          { _wcPackageName = "lodash"
          , _wcFunctionName = "capitalize"
          , _wcCanopyName = "capitalize_"
          , _wcParams = [PassThrough]
          , _wcReturn = ReturnDirect
          }
        output = builderToString (generateNpmWrapper config)
     in output
          @?= "import { capitalize } from 'lodash';\n\n\n"
          ++ "/**\n * @canopy-ffi capitalize_\n */\n"
          ++ "function capitalize_(p0) {\n"
          ++ "  return capitalize(p0);\n"
          ++ "}\n"

unwrapMaybeWrapperTest :: TestTree
unwrapMaybeWrapperTest =
  HUnit.testCase "UnwrapMaybe generates 'a' in p0 ternary" $
    let config = WrapperConfig
          { _wcPackageName = "utils"
          , _wcFunctionName = "lookup"
          , _wcCanopyName = "lookup_"
          , _wcParams = [PassThrough, UnwrapMaybe]
          , _wcReturn = ReturnDirect
          }
        output = builderToString (generateNpmWrapper config)
     in output
          @?= "import { lookup } from 'utils';\n\n\n"
          ++ "/**\n * @canopy-ffi lookup_\n */\n"
          ++ "function lookup_(p0, p1) {\n"
          ++ "  return lookup(p0, 'a' in p1 ? p1.a : null);\n"
          ++ "}\n"

wrapPromiseWrapperTest :: TestTree
wrapPromiseWrapperTest =
  HUnit.testCase "WrapPromise generates _Scheduler_binding" $
    let config = WrapperConfig
          { _wcPackageName = "node-fetch"
          , _wcFunctionName = "fetch"
          , _wcCanopyName = "fetch_"
          , _wcParams = [PassThrough]
          , _wcReturn = WrapPromise
          }
        output = builderToString (generateNpmWrapper config)
     in output
          @?= "import { fetch } from 'node-fetch';\n\n\n"
          ++ "/**\n * @canopy-ffi fetch_\n */\n"
          ++ "function fetch_(p0) {\n"
          ++ "  return _Scheduler_binding(function(callback) {\n"
          ++ "    fetch(p0).then(\n"
          ++ "      function(value) { callback(_Scheduler_succeed(value)); },\n"
          ++ "      function(error) { callback(_Scheduler_fail(error.message || String(error))); }\n"
          ++ "    );\n"
          ++ "  });\n"
          ++ "}\n"

wrapCallbackWrapperTest :: TestTree
wrapCallbackWrapperTest =
  HUnit.testCase "ConvertCallback generates callback conversion" $
    let config = WrapperConfig
          { _wcPackageName = "events"
          , _wcFunctionName = "on"
          , _wcCanopyName = "on_"
          , _wcParams = [PassThrough, ConvertCallback]
          , _wcReturn = ReturnDirect
          }
        output = builderToString (generateNpmWrapper config)
     in output
          @?= "import { on } from 'events';\n\n\n"
          ++ "/**\n * @canopy-ffi on_\n */\n"
          ++ "function on_(p0, p1) {\n"
          ++ "  return on(p0, function() { return p1(Array.prototype.slice.call(arguments)); });\n"
          ++ "}\n"

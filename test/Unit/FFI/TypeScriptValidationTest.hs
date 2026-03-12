{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI.TypeScriptValidation module.
--
-- Tests compile-time validation of Canopy FFI types against @.d.ts@ declarations.
--
-- @since 0.20.1
module Unit.FFI.TypeScriptValidationTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified FFI.TypeScriptValidation as TsVal
import Generate.TypeScript.Parser (DtsExport (..))
import Generate.TypeScript.Types (TsType (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI.TypeScriptValidation"
    [ compatibilityTests,
      validationTests,
      renderTests
    ]

compatibilityTests :: TestTree
compatibilityTests =
  testGroup
    "type compatibility"
    [ testCase "matching primitives are compatible" $ do
        let canopyTypes = [("greet", TsFunction [TsString] TsString)]
            dtsExports = [DtsExportFunction (Name.fromChars "greet") [TsString] TsString]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        errors @?= [],
      testCase "number parameters match" $ do
        let canopyTypes = [("add", TsFunction [TsNumber, TsNumber] TsNumber)]
            dtsExports = [DtsExportFunction (Name.fromChars "add") [TsNumber, TsNumber] TsNumber]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        errors @?= [],
      testCase "mismatched return type produces error" $ do
        let canopyTypes = [("fn", TsFunction [TsString] TsNumber)]
            dtsExports = [DtsExportFunction (Name.fromChars "fn") [TsString] TsString]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        length errors @?= 1
        TsVal.veFunctionName (head errors) @?= "fn",
      testCase "mismatched parameter count produces error" $ do
        let canopyTypes = [("fn", TsFunction [TsString] TsNumber)]
            dtsExports = [DtsExportFunction (Name.fromChars "fn") [TsString, TsNumber] TsNumber]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        length errors @?= 1,
      testCase "unknown type is compatible with anything" $ do
        let canopyTypes = [("fn", TsFunction [TsUnknown] TsUnknown)]
            dtsExports = [DtsExportFunction (Name.fromChars "fn") [TsString] TsNumber]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        errors @?= [],
      testCase "ReadonlyArray compatibility" $ do
        let canopyTypes = [("fn", TsFunction [TsReadonlyArray TsNumber] TsVoid)]
            dtsExports = [DtsExportFunction (Name.fromChars "fn") [TsReadonlyArray TsNumber] TsVoid]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        errors @?= [],
      testCase "nested ReadonlyArray mismatch" $ do
        let canopyTypes = [("fn", TsFunction [TsReadonlyArray TsString] TsVoid)]
            dtsExports = [DtsExportFunction (Name.fromChars "fn") [TsReadonlyArray TsNumber] TsVoid]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        length errors @?= 1
    ]

validationTests :: TestTree
validationTests =
  testGroup
    "validateFFIAgainstDts"
    [ testCase "function not in dts is skipped" $ do
        let canopyTypes = [("myFn", TsFunction [TsString] TsVoid)]
            dtsExports = []
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        errors @?= [],
      testCase "const export validated" $ do
        let canopyTypes = [("value", TsNumber)]
            dtsExports = [DtsExportConst (Name.fromChars "value") TsNumber]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        errors @?= [],
      testCase "const type mismatch" $ do
        let canopyTypes = [("value", TsString)]
            dtsExports = [DtsExportConst (Name.fromChars "value") TsNumber]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        length errors @?= 1,
      testCase "multiple functions validated independently" $ do
        let canopyTypes =
              [ ("good", TsFunction [TsString] TsString),
                ("bad", TsFunction [TsNumber] TsString)
              ]
            dtsExports =
              [ DtsExportFunction (Name.fromChars "good") [TsString] TsString,
                DtsExportFunction (Name.fromChars "bad") [TsNumber] TsNumber
              ]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        length errors @?= 1
        TsVal.veFunctionName (head errors) @?= "bad",
      testCase "type export is ignored for function validation" $ do
        let canopyTypes = [("MyType", TsNumber)]
            dtsExports = [DtsExportType (Name.fromChars "MyType") [] TsNumber]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        errors @?= []
    ]

renderTests :: TestTree
renderTests =
  testGroup
    "error message rendering"
    [ testCase "error message contains function name" $ do
        let canopyTypes = [("broken", TsFunction [TsString] TsNumber)]
            dtsExports = [DtsExportFunction (Name.fromChars "broken") [TsString] TsString]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        case errors of
          [err] -> do
            TsVal.veFunctionName err @?= "broken"
            TsVal.veMessage err @?= "Type mismatch for broken: Canopy declares (string) => number but .d.ts declares (string) => string"
          _ -> assertFailure "expected exactly one error",
      testCase "error shows expected and actual types" $ do
        let canopyTypes = [("fn", TsFunction [] TsNumber)]
            dtsExports = [DtsExportFunction (Name.fromChars "fn") [] TsString]
            errors = TsVal.validateFFIAgainstDts canopyTypes dtsExports
        case errors of
          [err] -> do
            TsVal.veExpected err @?= "() => number"
            TsVal.veActual err @?= "() => string"
          _ -> assertFailure "expected exactly one error"
    ]

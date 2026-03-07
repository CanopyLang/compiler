module Unit.FFI.ValidatorTest (tests) where

import qualified FFI.Validator as Validator
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI.Validator Tests"
    [ parseFFITypeTests,
      parseReturnTypeTests,
      generateValidatorNameTests,
      generateValidatorTests,
      generateAllValidatorsTests
    ]

parseFFITypeTests :: TestTree
parseFFITypeTests =
  testGroup
    "parseFFIType"
    [ testCase "parses Int" $
        Validator.parseFFIType "Int" @?= Just Validator.FFIInt,
      testCase "parses Float" $
        Validator.parseFFIType "Float" @?= Just Validator.FFIFloat,
      testCase "parses String" $
        Validator.parseFFIType "String" @?= Just Validator.FFIString,
      testCase "parses Bool" $
        Validator.parseFFIType "Bool" @?= Just Validator.FFIBool,
      testCase "parses Unit" $
        Validator.parseFFIType "()" @?= Just Validator.FFIUnit,
      testCase "parses opaque type" $
        Validator.parseFFIType "AudioContext" @?= Just (Validator.FFIOpaque "AudioContext" []),
      testCase "parses List Int" $
        Validator.parseFFIType "List Int" @?= Just (Validator.FFIList Validator.FFIInt),
      testCase "parses List Float" $
        Validator.parseFFIType "List Float" @?= Just (Validator.FFIList Validator.FFIFloat),
      testCase "parses Maybe Int" $
        Validator.parseFFIType "Maybe Int" @?= Just (Validator.FFIMaybe Validator.FFIInt),
      testCase "parses Maybe String" $
        Validator.parseFFIType "Maybe String" @?= Just (Validator.FFIMaybe Validator.FFIString),
      testCase "parses Result String Int" $
        Validator.parseFFIType "Result String Int" @?= Just (Validator.FFIResult Validator.FFIString Validator.FFIInt),
      testCase "parses Result Error Value" $
        Validator.parseFFIType "Result Error Value" @?= Just (Validator.FFIResult (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])),
      testCase "parses Task String Int" $
        Validator.parseFFIType "Task String Int" @?= Just (Validator.FFITask Validator.FFIString Validator.FFIInt),
      testCase "parses Task Error Value" $
        Validator.parseFFIType "Task Error Value" @?= Just (Validator.FFITask (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])),
      testCase "parses nested List Maybe Int" $
        Validator.parseFFIType "List (Maybe Int)" @?= Just (Validator.FFIList (Validator.FFIMaybe Validator.FFIInt)),
      testCase "parses nested Maybe (List String)" $
        Validator.parseFFIType "Maybe (List String)" @?= Just (Validator.FFIMaybe (Validator.FFIList Validator.FFIString)),
      testCase "parses tuple (Int, String)" $
        Validator.parseFFIType "(Int, String)" @?= Just (Validator.FFITuple [Validator.FFIInt, Validator.FFIString]),
      testCase "parses tuple (Int, String, Bool)" $
        Validator.parseFFIType "(Int, String, Bool)" @?= Just (Validator.FFITuple [Validator.FFIInt, Validator.FFIString, Validator.FFIBool]),
      testCase "parses function Int -> String" $
        Validator.parseFFIType "Int -> String" @?= Just (Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString),
      testCase "parses function Int -> String -> Bool" $
        Validator.parseFFIType "Int -> String -> Bool" @?= Just (Validator.FFIFunctionType [Validator.FFIInt, Validator.FFIString] Validator.FFIBool),
      testCase "parses function with complex return" $
        Validator.parseFFIType "Int -> Result String Bool" @?= Just (Validator.FFIFunctionType [Validator.FFIInt] (Validator.FFIResult Validator.FFIString Validator.FFIBool)),
      testCase "handles whitespace" $
        Validator.parseFFIType "  Int  " @?= Just Validator.FFIInt,
      testCase "handles whitespace in List" $
        Validator.parseFFIType "List   Int" @?= Just (Validator.FFIList Validator.FFIInt),
      testCase "returns Nothing for empty string" $
        Validator.parseFFIType "" @?= Nothing
    ]

parseReturnTypeTests :: TestTree
parseReturnTypeTests =
  testGroup
    "parseReturnType"
    [ testCase "extracts return type from simple function" $
        Validator.parseReturnType "Int -> String" @?= Just Validator.FFIString,
      testCase "extracts return type from multi-arg function" $
        Validator.parseReturnType "Int -> String -> Bool" @?= Just Validator.FFIBool,
      testCase "extracts Result return type" $
        Validator.parseReturnType "Int -> Result Error Value" @?= Just (Validator.FFIResult (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])),
      testCase "extracts Task return type" $
        Validator.parseReturnType "String -> Task Error Value" @?= Just (Validator.FFITask (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])),
      testCase "returns Nothing for empty string" $
        Validator.parseReturnType "" @?= Nothing,
      testCase "returns type for non-function" $
        Validator.parseReturnType "Int" @?= Just Validator.FFIInt
    ]

generateValidatorNameTests :: TestTree
generateValidatorNameTests =
  testGroup
    "generateValidatorName"
    [ testCase "generates name for Int" $
        Validator.generateValidatorName Validator.FFIInt @?= "_validate_Int",
      testCase "generates name for Float" $
        Validator.generateValidatorName Validator.FFIFloat @?= "_validate_Float",
      testCase "generates name for String" $
        Validator.generateValidatorName Validator.FFIString @?= "_validate_String",
      testCase "generates name for Bool" $
        Validator.generateValidatorName Validator.FFIBool @?= "_validate_Bool",
      testCase "generates name for Unit" $
        Validator.generateValidatorName Validator.FFIUnit @?= "_validate_Unit",
      testCase "generates name for List Int" $
        Validator.generateValidatorName (Validator.FFIList Validator.FFIInt) @?= "_validate_List_Int",
      testCase "generates name for Maybe String" $
        Validator.generateValidatorName (Validator.FFIMaybe Validator.FFIString) @?= "_validate_Maybe_String",
      testCase "generates name for Result String Int" $
        Validator.generateValidatorName (Validator.FFIResult Validator.FFIString Validator.FFIInt) @?= "_validate_Result_String_Int",
      testCase "generates name for Task Error Value" $
        Validator.generateValidatorName (Validator.FFITask (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])) @?= "_validate_Task_Opaque_Error_Opaque_Value",
      testCase "generates name for Tuple" $
        Validator.generateValidatorName (Validator.FFITuple [Validator.FFIInt, Validator.FFIString]) @?= "_validate_Tuple_Int_String",
      testCase "generates name for Opaque type" $
        Validator.generateValidatorName (Validator.FFIOpaque "AudioContext" []) @?= "_validate_Opaque_AudioContext",
      testCase "generates name for Function" $
        Validator.generateValidatorName (Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString) @?= "_validate_Fn_String"
    ]

generateValidatorTests :: TestTree
generateValidatorTests =
  testGroup
    "generateValidator"
    [ testCase "generates exact Int validator" $
        Validator.generateValidator Validator.defaultConfig Validator.FFIInt
          @?= "function _validate_Int(v, ctx) {\n  if (!Number.isInteger(v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected Int, got ' + typeof v);\n  }\n  return v;\n}\n",
      testCase "generates exact Float validator" $
        Validator.generateValidator Validator.defaultConfig Validator.FFIFloat
          @?= "function _validate_Float(v, ctx) {\n  if (typeof v !== 'number') {\n    throw new Error('FFI type error at ' + ctx + ': expected Float, got ' + typeof v);\n  }\n  return v;\n}\n",
      testCase "generates exact String validator" $
        Validator.generateValidator Validator.defaultConfig Validator.FFIString
          @?= "function _validate_String(v, ctx) {\n  if (typeof v !== 'string') {\n    throw new Error('FFI type error at ' + ctx + ': expected String, got ' + typeof v);\n  }\n  return v;\n}\n",
      testCase "generates exact Bool validator" $
        Validator.generateValidator Validator.defaultConfig Validator.FFIBool
          @?= "function _validate_Bool(v, ctx) {\n  if (typeof v !== 'boolean') {\n    throw new Error('FFI type error at ' + ctx + ': expected Bool, got ' + typeof v);\n  }\n  return v;\n}\n",
      testCase "generates exact Unit validator" $
        Validator.generateValidator Validator.defaultConfig Validator.FFIUnit
          @?= "function _validate_Unit(v, ctx) {\n  return v;\n}\n",
      testCase "generates exact List Int validator" $
        Validator.generateValidator Validator.defaultConfig (Validator.FFIList Validator.FFIInt)
          @?= "function _validate_List_Int(v, ctx) {\n  if (!Array.isArray(v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected List, got ' + typeof v);\n  }\n  return v.map(function(el, i) { return _validate_Int(el, ctx + '[' + i + ']'); });\n}\n",
      testCase "generates exact Maybe Int validator" $
        Validator.generateValidator Validator.defaultConfig (Validator.FFIMaybe Validator.FFIInt)
          @?= "function _validate_Maybe_Int(v, ctx) {\n  if (v == null) { return { $: 'Nothing' }; }\n  return { $: 'Just', a: _validate_Int(v, ctx) };\n}\n",
      testCase "generates exact Result String Int validator" $
        Validator.generateValidator Validator.defaultConfig (Validator.FFIResult Validator.FFIString Validator.FFIInt)
          @?= "function _validate_Result_String_Int(v, ctx) {\n  if (typeof v !== 'object' || v === null || !('$' in v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected Result, got ' + typeof v);\n  }\n  if (v.$ === 'Ok') {\n    return { $: 'Ok', a: _validate_Int(v.a, ctx + '.Ok') };\n  } else if (v.$ === 'Err') {\n    return { $: 'Err', a: _validate_String(v.a, ctx + '.Err') };\n  }\n  throw new Error('FFI type error at ' + ctx + ': expected Result (invalid $), got ' + typeof v);\n}\n",
      testCase "generates exact Task String Int validator" $
        Validator.generateValidator Validator.defaultConfig (Validator.FFITask Validator.FFIString Validator.FFIInt)
          @?= "function _validate_Task_String_Int(v, ctx) {\n  if (typeof v !== 'object' || v === null || typeof v.then !== 'function') {\n    throw new Error('FFI type error at ' + ctx + ': expected Task (expected Promise), got ' + typeof v);\n  }\n  return v.then(\n    function(ok) { return { $: 'Ok', a: _validate_Int(ok, ctx + '.then') }; },\n    function(err) { return { $: 'Err', a: _validate_String(err, ctx + '.catch') }; }\n  );\n}\n",
      testCase "generates exact Tuple Int String validator" $
        Validator.generateValidator Validator.defaultConfig (Validator.FFITuple [Validator.FFIInt, Validator.FFIString])
          @?= "function _validate_Tuple_Int_String(v, ctx) {\n  if (!Array.isArray(v) || v.length !== 2) {\n    throw new Error('FFI type error at ' + ctx + ': expected Tuple2, got ' + typeof v);\n  }\n  return [_validate_Int(v[0], ctx + '[0]'), _validate_String(v[1], ctx + '[1]')];\n}\n",
      testCase "generates exact Function Int->String validator" $
        Validator.generateValidator Validator.defaultConfig (Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString)
          @?= "function _validate_Fn_String(v, ctx) {\n  if (typeof v !== 'function') {\n    throw new Error('FFI type error at ' + ctx + ': expected Function, got ' + typeof v);\n  }\n  return v;\n}\n",
      testCase "strict mode generates throw new Error" $
        let config = Validator.defaultConfig {Validator._configStrictMode = True}
         in Validator.generateValidator config Validator.FFIInt
              @?= "function _validate_Int(v, ctx) {\n  if (!Number.isInteger(v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected Int, got ' + typeof v);\n  }\n  return v;\n}\n",
      testCase "non-strict mode generates console.warn" $
        let config = Validator.defaultConfig {Validator._configStrictMode = False}
         in Validator.generateValidator config Validator.FFIInt
              @?= "function _validate_Int(v, ctx) {\n  if (!Number.isInteger(v)) {\n    console.warn('FFI type warning at ' + ctx + ': expected Int, got ' + typeof v);\n  }\n  return v;\n}\n",
      testCase "debug mode generates JSON.stringify in error message" $
        let config = Validator.defaultConfig {Validator._configDebugMode = True}
         in Validator.generateValidator config Validator.FFIInt
              @?= "function _validate_Int(v, ctx) {\n  if (!Number.isInteger(v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected Int, got ' + typeof v + ': ' + JSON.stringify(v));\n  }\n  return v;\n}\n",
      testCase "validates opaque types with instanceof when configured" $
        let config = Validator.defaultConfig {Validator._configValidateOpaque = True}
         in Validator.generateValidator config (Validator.FFIOpaque "AudioContext" [])
              @?= "function _validate_Opaque_AudioContext(v, ctx) {\n  if (!(v instanceof AudioContext)) {\n    throw new Error('FFI type error at ' + ctx + ': expected AudioContext, got ' + typeof v);\n  }\n  return v;\n}\n",
      testCase "skips instanceof check for opaque when not configured" $
        let config = Validator.defaultConfig {Validator._configValidateOpaque = False}
         in Validator.generateValidator config (Validator.FFIOpaque "AudioContext" [])
              @?= "function _validate_Opaque_AudioContext(v, ctx) {\n  return v; // Opaque type: AudioContext\n}\n"
    ]

generateAllValidatorsTests :: TestTree
generateAllValidatorsTests =
  testGroup
    "generateAllValidators"
    [ testCase "generates validator for List Int and nested Int" $
        Validator.generateAllValidators Validator.defaultConfig (Validator.FFIList Validator.FFIInt)
          @?= "function _validate_List_Int(v, ctx) {\n  if (!Array.isArray(v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected List, got ' + typeof v);\n  }\n  return v.map(function(el, i) { return _validate_Int(el, ctx + '[' + i + ']'); });\n}\n\nfunction _validate_Int(v, ctx) {\n  if (!Number.isInteger(v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected Int, got ' + typeof v);\n  }\n  return v;\n}\n\n",
      testCase "generates validators for Result String Int" $
        Validator.generateAllValidators Validator.defaultConfig (Validator.FFIResult Validator.FFIString Validator.FFIInt)
          @?= "function _validate_Result_String_Int(v, ctx) {\n  if (typeof v !== 'object' || v === null || !('$' in v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected Result, got ' + typeof v);\n  }\n  if (v.$ === 'Ok') {\n    return { $: 'Ok', a: _validate_Int(v.a, ctx + '.Ok') };\n  } else if (v.$ === 'Err') {\n    return { $: 'Err', a: _validate_String(v.a, ctx + '.Err') };\n  }\n  throw new Error('FFI type error at ' + ctx + ': expected Result (invalid $), got ' + typeof v);\n}\n\nfunction _validate_String(v, ctx) {\n  if (typeof v !== 'string') {\n    throw new Error('FFI type error at ' + ctx + ': expected String, got ' + typeof v);\n  }\n  return v;\n}\n\nfunction _validate_Int(v, ctx) {\n  if (!Number.isInteger(v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected Int, got ' + typeof v);\n  }\n  return v;\n}\n\n",
      testCase "generates validators for Maybe (List Int)" $
        Validator.generateAllValidators Validator.defaultConfig (Validator.FFIMaybe (Validator.FFIList Validator.FFIInt))
          @?= "function _validate_Maybe_List_Int(v, ctx) {\n  if (v == null) { return { $: 'Nothing' }; }\n  return { $: 'Just', a: _validate_List_Int(v, ctx) };\n}\n\nfunction _validate_List_Int(v, ctx) {\n  if (!Array.isArray(v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected List, got ' + typeof v);\n  }\n  return v.map(function(el, i) { return _validate_Int(el, ctx + '[' + i + ']'); });\n}\n\nfunction _validate_Int(v, ctx) {\n  if (!Number.isInteger(v)) {\n    throw new Error('FFI type error at ' + ctx + ': expected Int, got ' + typeof v);\n  }\n  return v;\n}\n\n"
    ]

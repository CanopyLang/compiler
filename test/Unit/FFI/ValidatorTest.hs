module Unit.FFI.ValidatorTest (tests) where

import qualified Data.Text as Text
import qualified FFI.Validator as V
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
        V.parseFFIType "Int" @?= Just V.FFIInt,
      testCase "parses Float" $
        V.parseFFIType "Float" @?= Just V.FFIFloat,
      testCase "parses String" $
        V.parseFFIType "String" @?= Just V.FFIString,
      testCase "parses Bool" $
        V.parseFFIType "Bool" @?= Just V.FFIBool,
      testCase "parses Unit" $
        V.parseFFIType "()" @?= Just V.FFIUnit,
      testCase "parses opaque type" $
        V.parseFFIType "AudioContext" @?= Just (V.FFIOpaque "AudioContext"),
      testCase "parses List Int" $
        V.parseFFIType "List Int" @?= Just (V.FFIList V.FFIInt),
      testCase "parses List Float" $
        V.parseFFIType "List Float" @?= Just (V.FFIList V.FFIFloat),
      testCase "parses Maybe Int" $
        V.parseFFIType "Maybe Int" @?= Just (V.FFIMaybe V.FFIInt),
      testCase "parses Maybe String" $
        V.parseFFIType "Maybe String" @?= Just (V.FFIMaybe V.FFIString),
      testCase "parses Result String Int" $
        V.parseFFIType "Result String Int" @?= Just (V.FFIResult V.FFIString V.FFIInt),
      testCase "parses Result Error Value" $
        V.parseFFIType "Result Error Value" @?= Just (V.FFIResult (V.FFIOpaque "Error") (V.FFIOpaque "Value")),
      testCase "parses Task String Int" $
        V.parseFFIType "Task String Int" @?= Just (V.FFITask V.FFIString V.FFIInt),
      testCase "parses Task Error Value" $
        V.parseFFIType "Task Error Value" @?= Just (V.FFITask (V.FFIOpaque "Error") (V.FFIOpaque "Value")),
      testCase "parses nested List Maybe Int" $
        V.parseFFIType "List (Maybe Int)" @?= Just (V.FFIList (V.FFIMaybe V.FFIInt)),
      testCase "parses nested Maybe (List String)" $
        V.parseFFIType "Maybe (List String)" @?= Just (V.FFIMaybe (V.FFIList V.FFIString)),
      testCase "parses tuple (Int, String)" $
        V.parseFFIType "(Int, String)" @?= Just (V.FFITuple [V.FFIInt, V.FFIString]),
      testCase "parses tuple (Int, String, Bool)" $
        V.parseFFIType "(Int, String, Bool)" @?= Just (V.FFITuple [V.FFIInt, V.FFIString, V.FFIBool]),
      testCase "parses function Int -> String" $
        V.parseFFIType "Int -> String" @?= Just (V.FFIFunction [V.FFIInt] V.FFIString),
      testCase "parses function Int -> String -> Bool" $
        V.parseFFIType "Int -> String -> Bool" @?= Just (V.FFIFunction [V.FFIInt, V.FFIString] V.FFIBool),
      testCase "parses function with complex return" $
        V.parseFFIType "Int -> Result String Bool" @?= Just (V.FFIFunction [V.FFIInt] (V.FFIResult V.FFIString V.FFIBool)),
      testCase "handles whitespace" $
        V.parseFFIType "  Int  " @?= Just V.FFIInt,
      testCase "handles whitespace in List" $
        V.parseFFIType "List   Int" @?= Just (V.FFIList V.FFIInt),
      testCase "returns Nothing for empty string" $
        V.parseFFIType "" @?= Nothing
    ]

parseReturnTypeTests :: TestTree
parseReturnTypeTests =
  testGroup
    "parseReturnType"
    [ testCase "extracts return type from simple function" $
        V.parseReturnType "Int -> String" @?= Just V.FFIString,
      testCase "extracts return type from multi-arg function" $
        V.parseReturnType "Int -> String -> Bool" @?= Just V.FFIBool,
      testCase "extracts Result return type" $
        V.parseReturnType "Int -> Result Error Value" @?= Just (V.FFIResult (V.FFIOpaque "Error") (V.FFIOpaque "Value")),
      testCase "extracts Task return type" $
        V.parseReturnType "String -> Task Error Value" @?= Just (V.FFITask (V.FFIOpaque "Error") (V.FFIOpaque "Value")),
      testCase "returns Nothing for empty string" $
        V.parseReturnType "" @?= Nothing,
      testCase "returns type for non-function" $
        V.parseReturnType "Int" @?= Just V.FFIInt
    ]

generateValidatorNameTests :: TestTree
generateValidatorNameTests =
  testGroup
    "generateValidatorName"
    [ testCase "generates name for Int" $
        V.generateValidatorName V.FFIInt @?= "_validate_Int",
      testCase "generates name for Float" $
        V.generateValidatorName V.FFIFloat @?= "_validate_Float",
      testCase "generates name for String" $
        V.generateValidatorName V.FFIString @?= "_validate_String",
      testCase "generates name for Bool" $
        V.generateValidatorName V.FFIBool @?= "_validate_Bool",
      testCase "generates name for Unit" $
        V.generateValidatorName V.FFIUnit @?= "_validate_Unit",
      testCase "generates name for List Int" $
        V.generateValidatorName (V.FFIList V.FFIInt) @?= "_validate_List_Int",
      testCase "generates name for Maybe String" $
        V.generateValidatorName (V.FFIMaybe V.FFIString) @?= "_validate_Maybe_String",
      testCase "generates name for Result String Int" $
        V.generateValidatorName (V.FFIResult V.FFIString V.FFIInt) @?= "_validate_Result_String_Int",
      testCase "generates name for Task Error Value" $
        V.generateValidatorName (V.FFITask (V.FFIOpaque "Error") (V.FFIOpaque "Value")) @?= "_validate_Task_Opaque_Error_Opaque_Value",
      testCase "generates name for Tuple" $
        V.generateValidatorName (V.FFITuple [V.FFIInt, V.FFIString]) @?= "_validate_Tuple_Int_String",
      testCase "generates name for Opaque type" $
        V.generateValidatorName (V.FFIOpaque "AudioContext") @?= "_validate_Opaque_AudioContext",
      testCase "generates name for Function" $
        V.generateValidatorName (V.FFIFunction [V.FFIInt] V.FFIString) @?= "_validate_Fn_String"
    ]

generateValidatorTests :: TestTree
generateValidatorTests =
  testGroup
    "generateValidator"
    [ testCase "generates Int validator with Number.isInteger check" $
        let validator = V.generateValidator V.defaultConfig V.FFIInt
         in Text.isInfixOf "Number.isInteger" validator @?= True,
      testCase "generates Float validator with typeof check" $
        let validator = V.generateValidator V.defaultConfig V.FFIFloat
         in Text.isInfixOf "typeof v !== 'number'" validator @?= True,
      testCase "generates String validator with typeof check" $
        let validator = V.generateValidator V.defaultConfig V.FFIString
         in Text.isInfixOf "typeof v !== 'string'" validator @?= True,
      testCase "generates Bool validator with typeof check" $
        let validator = V.generateValidator V.defaultConfig V.FFIBool
         in Text.isInfixOf "typeof v !== 'boolean'" validator @?= True,
      testCase "generates Unit validator that returns v" $
        let validator = V.generateValidator V.defaultConfig V.FFIUnit
         in Text.isInfixOf "return v;" validator @?= True,
      testCase "generates List validator with Array.isArray check" $
        let validator = V.generateValidator V.defaultConfig (V.FFIList V.FFIInt)
         in Text.isInfixOf "Array.isArray" validator @?= True,
      testCase "generates Maybe validator with null check" $
        let validator = V.generateValidator V.defaultConfig (V.FFIMaybe V.FFIInt)
         in (Text.isInfixOf "v == null" validator && Text.isInfixOf "'Nothing'" validator) @?= True,
      testCase "generates Maybe validator with Just construction" $
        let validator = V.generateValidator V.defaultConfig (V.FFIMaybe V.FFIInt)
         in Text.isInfixOf "'Just'" validator @?= True,
      testCase "generates Result validator with string tags" $
        let validator = V.generateValidator V.defaultConfig (V.FFIResult V.FFIString V.FFIInt)
         in (Text.isInfixOf "'Ok'" validator && Text.isInfixOf "'Err'" validator) @?= True,
      testCase "generates Task validator with Promise check" $
        let validator = V.generateValidator V.defaultConfig (V.FFITask V.FFIString V.FFIInt)
         in (Text.isInfixOf "typeof v.then !== 'function'" validator) @?= True,
      testCase "generates Tuple validator with length check" $
        let validator = V.generateValidator V.defaultConfig (V.FFITuple [V.FFIInt, V.FFIString])
         in Text.isInfixOf "v.length !== 2" validator @?= True,
      testCase "generates Function validator with typeof check" $
        let validator = V.generateValidator V.defaultConfig (V.FFIFunction [V.FFIInt] V.FFIString)
         in Text.isInfixOf "typeof v !== 'function'" validator @?= True,
      testCase "generates validator that throws in strict mode" $
        let config = V.defaultConfig {V._configStrictMode = True}
            validator = V.generateValidator config V.FFIInt
         in Text.isInfixOf "throw new Error" validator @?= True,
      testCase "generates validator that warns in non-strict mode" $
        let config = V.defaultConfig {V._configStrictMode = False}
            validator = V.generateValidator config V.FFIInt
         in Text.isInfixOf "console.warn" validator @?= True,
      testCase "includes debug info in debug mode" $
        let config = V.defaultConfig {V._configDebugMode = True}
            validator = V.generateValidator config V.FFIInt
         in Text.isInfixOf "JSON.stringify" validator @?= True,
      testCase "validates opaque types when configured" $
        let config = V.defaultConfig {V._configValidateOpaque = True}
            validator = V.generateValidator config (V.FFIOpaque "AudioContext")
         in Text.isInfixOf "instanceof AudioContext" validator @?= True,
      testCase "skips opaque validation when not configured" $
        let config = V.defaultConfig {V._configValidateOpaque = False}
            validator = V.generateValidator config (V.FFIOpaque "AudioContext")
         in Text.isInfixOf "instanceof" validator @?= False
    ]

generateAllValidatorsTests :: TestTree
generateAllValidatorsTests =
  testGroup
    "generateAllValidators"
    [ testCase "generates validator for type and nested types" $
        let validators = V.generateAllValidators V.defaultConfig (V.FFIList V.FFIInt)
         in (Text.isInfixOf "_validate_List_Int" validators && Text.isInfixOf "_validate_Int" validators) @?= True,
      testCase "generates validators for Result type" $
        let validators = V.generateAllValidators V.defaultConfig (V.FFIResult V.FFIString V.FFIInt)
         in (Text.isInfixOf "_validate_Result_String_Int" validators
               && Text.isInfixOf "_validate_String" validators
               && Text.isInfixOf "_validate_Int" validators)
              @?= True,
      testCase "generates validators for deeply nested types" $
        let validators = V.generateAllValidators V.defaultConfig (V.FFIMaybe (V.FFIList V.FFIInt))
         in (Text.isInfixOf "_validate_Maybe_List_Int" validators
               && Text.isInfixOf "_validate_List_Int" validators
               && Text.isInfixOf "_validate_Int" validators)
              @?= True
    ]

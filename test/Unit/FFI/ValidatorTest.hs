module Unit.FFI.ValidatorTest (tests) where

import qualified Data.Text as Text
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
        Validator.parseFFIType "AudioContext" @?= Just (Validator.FFIOpaque "AudioContext"),
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
        Validator.parseFFIType "Result Error Value" @?= Just (Validator.FFIResult (Validator.FFIOpaque "Error") (Validator.FFIOpaque "Value")),
      testCase "parses Task String Int" $
        Validator.parseFFIType "Task String Int" @?= Just (Validator.FFITask Validator.FFIString Validator.FFIInt),
      testCase "parses Task Error Value" $
        Validator.parseFFIType "Task Error Value" @?= Just (Validator.FFITask (Validator.FFIOpaque "Error") (Validator.FFIOpaque "Value")),
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
        Validator.parseReturnType "Int -> Result Error Value" @?= Just (Validator.FFIResult (Validator.FFIOpaque "Error") (Validator.FFIOpaque "Value")),
      testCase "extracts Task return type" $
        Validator.parseReturnType "String -> Task Error Value" @?= Just (Validator.FFITask (Validator.FFIOpaque "Error") (Validator.FFIOpaque "Value")),
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
        Validator.generateValidatorName (Validator.FFITask (Validator.FFIOpaque "Error") (Validator.FFIOpaque "Value")) @?= "_validate_Task_Opaque_Error_Opaque_Value",
      testCase "generates name for Tuple" $
        Validator.generateValidatorName (Validator.FFITuple [Validator.FFIInt, Validator.FFIString]) @?= "_validate_Tuple_Int_String",
      testCase "generates name for Opaque type" $
        Validator.generateValidatorName (Validator.FFIOpaque "AudioContext") @?= "_validate_Opaque_AudioContext",
      testCase "generates name for Function" $
        Validator.generateValidatorName (Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString) @?= "_validate_Fn_String"
    ]

generateValidatorTests :: TestTree
generateValidatorTests =
  testGroup
    "generateValidator"
    [ testCase "generates Int validator with Number.isInteger check" $
        let validator = Validator.generateValidator Validator.defaultConfig Validator.FFIInt
         in Text.isInfixOf "Number.isInteger" validator @?= True,
      testCase "generates Float validator with typeof check" $
        let validator = Validator.generateValidator Validator.defaultConfig Validator.FFIFloat
         in Text.isInfixOf "typeof v !== 'number'" validator @?= True,
      testCase "generates String validator with typeof check" $
        let validator = Validator.generateValidator Validator.defaultConfig Validator.FFIString
         in Text.isInfixOf "typeof v !== 'string'" validator @?= True,
      testCase "generates Bool validator with typeof check" $
        let validator = Validator.generateValidator Validator.defaultConfig Validator.FFIBool
         in Text.isInfixOf "typeof v !== 'boolean'" validator @?= True,
      testCase "generates Unit validator that returns v" $
        let validator = Validator.generateValidator Validator.defaultConfig Validator.FFIUnit
         in Text.isInfixOf "return v;" validator @?= True,
      testCase "generates List validator with Array.isArray check" $
        let validator = Validator.generateValidator Validator.defaultConfig (Validator.FFIList Validator.FFIInt)
         in Text.isInfixOf "Array.isArray" validator @?= True,
      testCase "generates Maybe validator with null check" $
        let validator = Validator.generateValidator Validator.defaultConfig (Validator.FFIMaybe Validator.FFIInt)
         in (Text.isInfixOf "v == null" validator && Text.isInfixOf "'Nothing'" validator) @?= True,
      testCase "generates Maybe validator with Just construction" $
        let validator = Validator.generateValidator Validator.defaultConfig (Validator.FFIMaybe Validator.FFIInt)
         in Text.isInfixOf "'Just'" validator @?= True,
      testCase "generates Result validator with string tags" $
        let validator = Validator.generateValidator Validator.defaultConfig (Validator.FFIResult Validator.FFIString Validator.FFIInt)
         in (Text.isInfixOf "'Ok'" validator && Text.isInfixOf "'Err'" validator) @?= True,
      testCase "generates Task validator with Promise check" $
        let validator = Validator.generateValidator Validator.defaultConfig (Validator.FFITask Validator.FFIString Validator.FFIInt)
         in (Text.isInfixOf "typeof v.then !== 'function'" validator) @?= True,
      testCase "generates Tuple validator with length check" $
        let validator = Validator.generateValidator Validator.defaultConfig (Validator.FFITuple [Validator.FFIInt, Validator.FFIString])
         in Text.isInfixOf "v.length !== 2" validator @?= True,
      testCase "generates Function validator with typeof check" $
        let validator = Validator.generateValidator Validator.defaultConfig (Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString)
         in Text.isInfixOf "typeof v !== 'function'" validator @?= True,
      testCase "generates validator that throws in strict mode" $
        let config = Validator.defaultConfig {Validator._configStrictMode = True}
            validator = Validator.generateValidator config Validator.FFIInt
         in Text.isInfixOf "throw new Error" validator @?= True,
      testCase "generates validator that warns in non-strict mode" $
        let config = Validator.defaultConfig {Validator._configStrictMode = False}
            validator = Validator.generateValidator config Validator.FFIInt
         in Text.isInfixOf "console.warn" validator @?= True,
      testCase "includes debug info in debug mode" $
        let config = Validator.defaultConfig {Validator._configDebugMode = True}
            validator = Validator.generateValidator config Validator.FFIInt
         in Text.isInfixOf "JSON.stringify" validator @?= True,
      testCase "validates opaque types when configured" $
        let config = Validator.defaultConfig {Validator._configValidateOpaque = True}
            validator = Validator.generateValidator config (Validator.FFIOpaque "AudioContext")
         in Text.isInfixOf "instanceof AudioContext" validator @?= True,
      testCase "skips opaque validation when not configured" $
        let config = Validator.defaultConfig {Validator._configValidateOpaque = False}
            validator = Validator.generateValidator config (Validator.FFIOpaque "AudioContext")
         in Text.isInfixOf "instanceof" validator @?= False
    ]

generateAllValidatorsTests :: TestTree
generateAllValidatorsTests =
  testGroup
    "generateAllValidators"
    [ testCase "generates validator for type and nested types" $
        let validators = Validator.generateAllValidators Validator.defaultConfig (Validator.FFIList Validator.FFIInt)
         in (Text.isInfixOf "_validate_List_Int" validators && Text.isInfixOf "_validate_Int" validators) @?= True,
      testCase "generates validators for Result type" $
        let validators = Validator.generateAllValidators Validator.defaultConfig (Validator.FFIResult Validator.FFIString Validator.FFIInt)
         in (Text.isInfixOf "_validate_Result_String_Int" validators
               && Text.isInfixOf "_validate_String" validators
               && Text.isInfixOf "_validate_Int" validators)
              @?= True,
      testCase "generates validators for deeply nested types" $
        let validators = Validator.generateAllValidators Validator.defaultConfig (Validator.FFIMaybe (Validator.FFIList Validator.FFIInt))
         in (Text.isInfixOf "_validate_Maybe_List_Int" validators
               && Text.isInfixOf "_validate_List_Int" validators
               && Text.isInfixOf "_validate_Int" validators)
              @?= True
    ]

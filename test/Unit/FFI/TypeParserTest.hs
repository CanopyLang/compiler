{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI type parsing behaviour.
--
-- 'FFI.TypeParser' is an internal module not directly accessible from the
-- test suite. Its behaviour is fully observable through the re-exported
-- functions in 'FFI.Validator': 'parseFFIType' and 'parseReturnType'.
--
-- We test all observable type-parsing patterns:
--   * Primitive types (Int, Float, String, Bool, Unit)
--   * Container types (List, Maybe, Result, Task)
--   * Nested containers
--   * Function types (single-arg, multi-arg, parenthesised)
--   * Tuple types
--   * Record types (including duplicate-field rejection)
--   * Type variables
--   * Opaque types (qualified and parameterised)
--   * Return-type extraction
--   * Error cases (empty string, bare arrow, unclosed paren)
--
-- @since 0.19.2
module Unit.FFI.TypeParserTest (tests) where

import FFI.Types (FFIType (..))
import qualified FFI.Validator as Validator
import Test.Tasty
import Test.Tasty.HUnit

-- | Top-level test tree for FFI type parsing.
tests :: TestTree
tests =
  testGroup
    "FFI.TypeParser Tests"
    [ primitiveTypeTests,
      containerTypeTests,
      nestedContainerTests,
      functionTypeTests,
      tupleTypeTests,
      recordTypeTests,
      typeVariableTests,
      opaqueTypeTests,
      parseReturnTypeTests,
      whitespaceTests,
      errorCaseTests,
      tokenizeTests,
      countArityTests,
      additionalRecordTests,
      additionalFunctionTests
    ]

-- PRIMITIVE TYPE TESTS

primitiveTypeTests :: TestTree
primitiveTypeTests =
  testGroup
    "primitive types"
    [ testCase "parses Int" $
        Validator.parseFFIType "Int" @?= Just FFIInt,
      testCase "parses Float" $
        Validator.parseFFIType "Float" @?= Just FFIFloat,
      testCase "parses String" $
        Validator.parseFFIType "String" @?= Just FFIString,
      testCase "parses Bool" $
        Validator.parseFFIType "Bool" @?= Just FFIBool,
      testCase "parses Unit keyword" $
        Validator.parseFFIType "Unit" @?= Just FFIUnit,
      testCase "parses () as Unit" $
        Validator.parseFFIType "()" @?= Just FFIUnit,
      testCase "lowercase int is type variable, not Int" $
        Validator.parseFFIType "int" @?= Just (FFITypeVar "int"),
      testCase "lowercase float is type variable, not Float" $
        Validator.parseFFIType "float" @?= Just (FFITypeVar "float")
    ]

-- CONTAINER TYPE TESTS

containerTypeTests :: TestTree
containerTypeTests =
  testGroup
    "container types"
    [ testCase "parses List Int" $
        Validator.parseFFIType "List Int" @?= Just (FFIList FFIInt),
      testCase "parses List String" $
        Validator.parseFFIType "List String" @?= Just (FFIList FFIString),
      testCase "parses List Bool" $
        Validator.parseFFIType "List Bool" @?= Just (FFIList FFIBool),
      testCase "parses List Float" $
        Validator.parseFFIType "List Float" @?= Just (FFIList FFIFloat),
      testCase "parses Maybe Int" $
        Validator.parseFFIType "Maybe Int" @?= Just (FFIMaybe FFIInt),
      testCase "parses Maybe String" $
        Validator.parseFFIType "Maybe String" @?= Just (FFIMaybe FFIString),
      testCase "parses Maybe Bool" $
        Validator.parseFFIType "Maybe Bool" @?= Just (FFIMaybe FFIBool),
      testCase "parses Result String Int" $
        Validator.parseFFIType "Result String Int"
          @?= Just (FFIResult FFIString FFIInt),
      testCase "parses Result with opaque error and value types" $
        Validator.parseFFIType "Result Error Value"
          @?= Just (FFIResult (FFIOpaque "Error" []) (FFIOpaque "Value" [])),
      testCase "parses Task String Int" $
        Validator.parseFFIType "Task String Int"
          @?= Just (FFITask FFIString FFIInt),
      testCase "parses Task with opaque types" $
        Validator.parseFFIType "Task Error Value"
          @?= Just (FFITask (FFIOpaque "Error" []) (FFIOpaque "Value" []))
    ]

-- NESTED CONTAINER TESTS

nestedContainerTests :: TestTree
nestedContainerTests =
  testGroup
    "nested container types"
    [ testCase "parses List (Maybe Int)" $
        Validator.parseFFIType "List (Maybe Int)"
          @?= Just (FFIList (FFIMaybe FFIInt)),
      testCase "parses Maybe (List String)" $
        Validator.parseFFIType "Maybe (List String)"
          @?= Just (FFIMaybe (FFIList FFIString)),
      testCase "parses List (List Int)" $
        Validator.parseFFIType "List (List Int)"
          @?= Just (FFIList (FFIList FFIInt)),
      testCase "parses Maybe (Maybe Bool)" $
        Validator.parseFFIType "Maybe (Maybe Bool)"
          @?= Just (FFIMaybe (FFIMaybe FFIBool)),
      testCase "parses Result (Maybe String) Int" $
        Validator.parseFFIType "Result (Maybe String) Int"
          @?= Just (FFIResult (FFIMaybe FFIString) FFIInt),
      testCase "parses Task (List String) (Maybe Int)" $
        Validator.parseFFIType "Task (List String) (Maybe Int)"
          @?= Just (FFITask (FFIList FFIString) (FFIMaybe FFIInt)),
      testCase "parses List (List (Maybe Int))" $
        Validator.parseFFIType "List (List (Maybe Int))"
          @?= Just (FFIList (FFIList (FFIMaybe FFIInt)))
    ]

-- FUNCTION TYPE TESTS

functionTypeTests :: TestTree
functionTypeTests =
  testGroup
    "function types"
    [ testCase "parses single-arg function Int -> String" $
        Validator.parseFFIType "Int -> String"
          @?= Just (FFIFunctionType [FFIInt] FFIString),
      testCase "parses two-arg function Int -> String -> Bool" $
        Validator.parseFFIType "Int -> String -> Bool"
          @?= Just (FFIFunctionType [FFIInt, FFIString] FFIBool),
      testCase "parses three-arg function" $
        Validator.parseFFIType "Int -> Float -> String -> Bool"
          @?= Just (FFIFunctionType [FFIInt, FFIFloat, FFIString] FFIBool),
      testCase "parses function returning List" $
        Validator.parseFFIType "Int -> List String"
          @?= Just (FFIFunctionType [FFIInt] (FFIList FFIString)),
      testCase "parses function returning Maybe" $
        Validator.parseFFIType "String -> Maybe Int"
          @?= Just (FFIFunctionType [FFIString] (FFIMaybe FFIInt)),
      testCase "parses function returning Result" $
        Validator.parseFFIType "String -> Result String Int"
          @?= Just (FFIFunctionType [FFIString] (FFIResult FFIString FFIInt)),
      testCase "parses function returning Task" $
        Validator.parseFFIType "String -> Task String Int"
          @?= Just (FFIFunctionType [FFIString] (FFITask FFIString FFIInt)),
      testCase "parses function with parenthesised tuple return" $
        Validator.parseFFIType "Int -> (String, Bool)"
          @?= Just (FFIFunctionType [FFIInt] (FFITuple [FFIString, FFIBool])),
      testCase "parenthesised arrow arg produces higher-order function type" $
        Validator.parseFFIType "(Int -> String) -> Bool"
          @?= Just (FFIFunctionType [FFIFunctionType [FFIInt] FFIString] FFIBool)
    ]

-- TUPLE TYPE TESTS

tupleTypeTests :: TestTree
tupleTypeTests =
  testGroup
    "tuple types"
    [ testCase "parses 2-tuple (Int, String)" $
        Validator.parseFFIType "(Int, String)"
          @?= Just (FFITuple [FFIInt, FFIString]),
      testCase "parses 3-tuple (Int, String, Bool)" $
        Validator.parseFFIType "(Int, String, Bool)"
          @?= Just (FFITuple [FFIInt, FFIString, FFIBool]),
      testCase "parses 2-tuple with identical element types" $
        Validator.parseFFIType "(Int, Int)"
          @?= Just (FFITuple [FFIInt, FFIInt]),
      testCase "parses nested tuple (Int, (String, Bool))" $
        Validator.parseFFIType "(Int, (String, Bool))"
          @?= Just (FFITuple [FFIInt, FFITuple [FFIString, FFIBool]]),
      testCase "parses tuple with List element" $
        Validator.parseFFIType "(List Int, String)"
          @?= Just (FFITuple [FFIList FFIInt, FFIString]),
      testCase "parses tuple with Maybe element" $
        Validator.parseFFIType "(Maybe Int, Bool)"
          @?= Just (FFITuple [FFIMaybe FFIInt, FFIBool]),
      testCase "parses 4-tuple" $
        Validator.parseFFIType "(Int, Float, String, Bool)"
          @?= Just (FFITuple [FFIInt, FFIFloat, FFIString, FFIBool])
    ]

-- RECORD TYPE TESTS

recordTypeTests :: TestTree
recordTypeTests =
  testGroup
    "record types"
    [ testCase "parses empty record {}" $
        Validator.parseFFIType "{}"
          @?= Just (FFIRecord []),
      testCase "parses single-field record { x : Int }" $
        Validator.parseFFIType "{ x : Int }"
          @?= Just (FFIRecord [("x", FFIInt)]),
      testCase "parses two-field record { name : String, age : Int }" $
        Validator.parseFFIType "{ name : String, age : Int }"
          @?= Just (FFIRecord [("name", FFIString), ("age", FFIInt)]),
      testCase "parses record with List field" $
        Validator.parseFFIType "{ items : List String }"
          @?= Just (FFIRecord [("items", FFIList FFIString)]),
      testCase "parses record with Maybe field" $
        Validator.parseFFIType "{ value : Maybe Int }"
          @?= Just (FFIRecord [("value", FFIMaybe FFIInt)]),
      testCase "parses three-field record" $
        Validator.parseFFIType "{ x : Int, y : Float, z : Bool }"
          @?= Just (FFIRecord [("x", FFIInt), ("y", FFIFloat), ("z", FFIBool)]),
      testCase "duplicate field names returns Nothing" $
        Validator.parseFFIType "{ x : Int, x : String }"
          @?= Nothing
    ]

-- TYPE VARIABLE TESTS

typeVariableTests :: TestTree
typeVariableTests =
  testGroup
    "type variables"
    [ testCase "lowercase name is type variable" $
        Validator.parseFFIType "a" @?= Just (FFITypeVar "a"),
      testCase "lowercase msg is type variable" $
        Validator.parseFFIType "msg" @?= Just (FFITypeVar "msg"),
      testCase "lowercase comparable is type variable" $
        Validator.parseFFIType "comparable" @?= Just (FFITypeVar "comparable"),
      testCase "type variable in List" $
        Validator.parseFFIType "List a"
          @?= Just (FFIList (FFITypeVar "a")),
      testCase "type variable in Maybe" $
        Validator.parseFFIType "Maybe msg"
          @?= Just (FFIMaybe (FFITypeVar "msg")),
      testCase "type variable in function return" $
        Validator.parseFFIType "Int -> a"
          @?= Just (FFIFunctionType [FFIInt] (FFITypeVar "a"))
    ]

-- OPAQUE TYPE TESTS

opaqueTypeTests :: TestTree
opaqueTypeTests =
  testGroup
    "opaque types"
    [ testCase "uppercase single name is opaque" $
        Validator.parseFFIType "AudioContext"
          @?= Just (FFIOpaque "AudioContext" []),
      testCase "qualified name is opaque" $
        Validator.parseFFIType "Json.Decode.Value"
          @?= Just (FFIOpaque "Json.Decode.Value" []),
      testCase "opaque with one type param" $
        Validator.parseFFIType "Cmd msg"
          @?= Just (FFIOpaque "Cmd" [FFITypeVar "msg"]),
      testCase "opaque with two type params" $
        Validator.parseFFIType "Dict String Int"
          @?= Just (FFIOpaque "Dict" [FFIString, FFIInt]),
      testCase "opaque with multiple type variable params" $
        Validator.parseFFIType "Program flags model msg"
          @?= Just (FFIOpaque "Program" [FFITypeVar "flags", FFITypeVar "model", FFITypeVar "msg"]),
      testCase "DOMElement is opaque with no params" $
        Validator.parseFFIType "DOMElement"
          @?= Just (FFIOpaque "DOMElement" []),
      testCase "opaque in function return" $
        Validator.parseFFIType "String -> AudioContext"
          @?= Just (FFIFunctionType [FFIString] (FFIOpaque "AudioContext" []))
    ]

-- PARSE RETURN TYPE TESTS

parseReturnTypeTests :: TestTree
parseReturnTypeTests =
  testGroup
    "parseReturnType"
    [ testCase "extracts last part of single-arg function" $
        Validator.parseReturnType "Int -> String" @?= Just FFIString,
      testCase "extracts last part of two-arg function" $
        Validator.parseReturnType "Int -> String -> Bool" @?= Just FFIBool,
      testCase "extracts last part of three-arg function" $
        Validator.parseReturnType "Int -> Float -> String -> Bool" @?= Just FFIBool,
      testCase "extracts Task from function return" $
        Validator.parseReturnType "String -> Task String Int"
          @?= Just (FFITask FFIString FFIInt),
      testCase "extracts Result from function return" $
        Validator.parseReturnType "String -> Result Error Value"
          @?= Just (FFIResult (FFIOpaque "Error" []) (FFIOpaque "Value" [])),
      testCase "returns whole type for non-function" $
        Validator.parseReturnType "Int" @?= Just FFIInt,
      testCase "returns whole type for Maybe" $
        Validator.parseReturnType "Maybe Int" @?= Just (FFIMaybe FFIInt),
      testCase "returns Nothing for empty string" $
        Validator.parseReturnType "" @?= Nothing
    ]

-- WHITESPACE TESTS

whitespaceTests :: TestTree
whitespaceTests =
  testGroup
    "whitespace handling"
    [ testCase "leading whitespace is stripped" $
        Validator.parseFFIType "  Int" @?= Just FFIInt,
      testCase "trailing whitespace is stripped" $
        Validator.parseFFIType "Int  " @?= Just FFIInt,
      testCase "surrounding whitespace stripped" $
        Validator.parseFFIType "  Int  " @?= Just FFIInt,
      testCase "extra whitespace between words" $
        Validator.parseFFIType "List   Int" @?= Just (FFIList FFIInt),
      testCase "whitespace around arrow" $
        Validator.parseFFIType "Int  ->  String"
          @?= Just (FFIFunctionType [FFIInt] FFIString)
    ]

-- ERROR CASE TESTS

errorCaseTests :: TestTree
errorCaseTests =
  testGroup
    "error cases"
    [ testCase "empty string returns Nothing" $
        Validator.parseFFIType "" @?= Nothing,
      testCase "whitespace-only returns Nothing" $
        Validator.parseFFIType "   " @?= Nothing,
      testCase "bare arrow returns Nothing" $
        Validator.parseFFIType "->" @?= Nothing,
      testCase "unclosed paren returns Nothing" $
        Validator.parseFFIType "(Int" @?= Nothing,
      testCase "duplicate record fields returns Nothing" $
        Validator.parseFFIType "{ a : Int, a : String }" @?= Nothing,
      testCase "triple nested containers parse correctly" $
        Validator.parseFFIType "Maybe (List (Maybe Int))"
          @?= Just (FFIMaybe (FFIList (FFIMaybe FFIInt)))
    ]

-- TOKENIZE BEHAVIOR TESTS (tested via parseFFIType observable behavior)

tokenizeTests :: TestTree
tokenizeTests =
  testGroup
    "tokenization behavior (via parseFFIType)"
    [ testCase "arrow in type string is parsed correctly" $
        Validator.parseFFIType "Int -> String"
          @?= Just (FFIFunctionType [FFIInt] FFIString),
      testCase "parentheses group a type argument" $
        Validator.parseFFIType "List (Maybe Int)"
          @?= Just (FFIList (FFIMaybe FFIInt)),
      testCase "comma separates tuple elements" $
        Validator.parseFFIType "(Int, String, Bool)"
          @?= Just (FFITuple [FFIInt, FFIString, FFIBool]),
      testCase "colon separates record field name and type" $
        Validator.parseFFIType "{ x : Int }"
          @?= Just (FFIRecord [("x", FFIInt)]),
      testCase "leading and trailing whitespace is stripped" $
        Validator.parseFFIType "  Bool  " @?= Just FFIBool,
      testCase "underscore-prefixed name is treated as opaque type" $
        Validator.parseFFIType "_msg" @?= Just (FFIOpaque "_msg" []),
      testCase "dot is valid in a word token (qualified name)" $
        Validator.parseFFIType "Json.Decode.Value"
          @?= Just (FFIOpaque "Json.Decode.Value" []),
      testCase "bare arrow with no types returns Nothing" $
        Validator.parseFFIType "->" @?= Nothing,
      testCase "whitespace-only returns Nothing" $
        Validator.parseFFIType "   " @?= Nothing,
      testCase "unclosed paren returns Nothing" $
        Validator.parseFFIType "(Int" @?= Nothing
    ]

-- ARITY BEHAVIOR TESTS (via parseFFIType structure inspection)

countArityTests :: TestTree
countArityTests =
  testGroup
    "function arity via parsed type structure"
    [ testCase "primitive type has no function params" $
        Validator.parseFFIType "Int" @?= Just FFIInt,
      testCase "single-arg function type has one param" $
        Validator.parseFFIType "Int -> String"
          @?= Just (FFIFunctionType [FFIInt] FFIString),
      testCase "two-arg function has two params" $
        Validator.parseFFIType "Int -> String -> Bool"
          @?= Just (FFIFunctionType [FFIInt, FFIString] FFIBool),
      testCase "three-arg function has three params" $
        Validator.parseFFIType "Int -> Float -> String -> Bool"
          @?= Just (FFIFunctionType [FFIInt, FFIFloat, FFIString] FFIBool),
      testCase "Maybe is not a function type" $
        Validator.parseFFIType "Maybe Int" @?= Just (FFIMaybe FFIInt),
      testCase "List is not a function type" $
        Validator.parseFFIType "List String" @?= Just (FFIList FFIString),
      testCase "Result is not a function type" $
        Validator.parseFFIType "Result String Int"
          @?= Just (FFIResult FFIString FFIInt),
      testCase "Task is not a function type" $
        Validator.parseFFIType "Task String Int"
          @?= Just (FFITask FFIString FFIInt),
      testCase "Tuple is not a function type" $
        Validator.parseFFIType "(Int, String)"
          @?= Just (FFITuple [FFIInt, FFIString]),
      testCase "TypeVar is not a function type" $
        Validator.parseFFIType "a" @?= Just (FFITypeVar "a"),
      testCase "Opaque is not a function type" $
        Validator.parseFFIType "AudioContext"
          @?= Just (FFIOpaque "AudioContext" [])
    ]

-- ADDITIONAL RECORD TESTS

additionalRecordTests :: TestTree
additionalRecordTests =
  testGroup
    "additional record tests"
    [ testCase "record with nested List field" $
        Validator.parseFFIType "{ items : List Int, name : String }"
          @?= Just (FFIRecord [("items", FFIList FFIInt), ("name", FFIString)]),
      testCase "record with Result field" $
        Validator.parseFFIType "{ result : Result String Int }"
          @?= Just (FFIRecord [("result", FFIResult FFIString FFIInt)]),
      testCase "record with Maybe field preserves inner type" $
        Validator.parseFFIType "{ value : Maybe Bool }"
          @?= Just (FFIRecord [("value", FFIMaybe FFIBool)]),
      testCase "three-field record ordering preserved" $
        Validator.parseFFIType "{ a : Int, b : String, c : Bool }"
          @?= Just (FFIRecord [("a", FFIInt), ("b", FFIString), ("c", FFIBool)]),
      testCase "triple duplicate field returns Nothing" $
        Validator.parseFFIType "{ x : Int, x : String, x : Bool }" @?= Nothing
    ]

-- ADDITIONAL FUNCTION TESTS

additionalFunctionTests :: TestTree
additionalFunctionTests =
  testGroup
    "additional function type tests"
    [ testCase "four-arg function type" $
        Validator.parseFFIType "Int -> Float -> String -> Bool -> ()"
          @?= Just (FFIFunctionType [FFIInt, FFIFloat, FFIString, FFIBool] FFIUnit),
      testCase "function returning opaque type" $
        Validator.parseFFIType "String -> AudioContext"
          @?= Just (FFIFunctionType [FFIString] (FFIOpaque "AudioContext" [])),
      testCase "function with Maybe argument" $
        Validator.parseFFIType "Maybe Int -> String"
          @?= Just (FFIFunctionType [FFIMaybe FFIInt] FFIString),
      testCase "function with List argument" $
        Validator.parseFFIType "List String -> Int"
          @?= Just (FFIFunctionType [FFIList FFIString] FFIInt),
      testCase "function with Result return type" $
        Validator.parseFFIType "String -> Int -> Result String Bool"
          @?= Just (FFIFunctionType [FFIString, FFIInt] (FFIResult FFIString FFIBool)),
      testCase "higher-order function in return" $
        Validator.parseFFIType "Int -> (String -> Bool)"
          @?= Just (FFIFunctionType [FFIInt] (FFIFunctionType [FFIString] FFIBool))
    ]

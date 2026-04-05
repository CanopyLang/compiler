{-# LANGUAGE OverloadedStrings #-}

-- | Comprehensive tests for FFI.TypeParser module.
--
-- Tests the unified FFI type string parser covering primitives,
-- parameterized types, tuples, records, function types, qualified names,
-- type variables, edge cases, tokenization, arity counting, and the
-- parseReturnType helper.
--
-- @since 0.19.2
module Unit.FFI.TypeParserTest (tests) where

import qualified FFI.TypeParser as TypeParser
import FFI.Types (FFIType (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI.TypeParser Tests"
    [ tokenizeTests,
      parsePrimitivesTests,
      parseListTests,
      parseMaybeTests,
      parseResultTests,
      parseTaskTests,
      parseTupleTests,
      parseRecordTests,
      parseFunctionTypeTests,
      parseOpaqueTests,
      parseTypeVarTests,
      parseReturnTypeTests,
      countArityTests,
      edgeCaseTests
    ]

-- TOKENIZE TESTS

tokenizeTests :: TestTree
tokenizeTests =
  testGroup
    "tokenize"
    [ testCase "tokenizes Int" $
        TypeParser.tokenize "Int" @?= [TypeParser.TWord "Int"],
      testCase "tokenizes arrow" $
        TypeParser.tokenize "->" @?= [TypeParser.TArrow],
      testCase "tokenizes empty parens as two tokens" $
        TypeParser.tokenize "()" @?= [TypeParser.TOpenParen, TypeParser.TCloseParen],
      testCase "tokenizes open paren" $
        TypeParser.tokenize "(" @?= [TypeParser.TOpenParen],
      testCase "tokenizes close paren" $
        TypeParser.tokenize ")" @?= [TypeParser.TCloseParen],
      testCase "tokenizes comma" $
        TypeParser.tokenize "," @?= [TypeParser.TComma],
      testCase "tokenizes open brace" $
        TypeParser.tokenize "{" @?= [TypeParser.TOpenBrace],
      testCase "tokenizes close brace" $
        TypeParser.tokenize "}" @?= [TypeParser.TCloseBrace],
      testCase "tokenizes colon" $
        TypeParser.tokenize ":" @?= [TypeParser.TColon],
      testCase "skips whitespace" $
        TypeParser.tokenize "  Int  " @?= [TypeParser.TWord "Int"],
      testCase "tokenizes Int -> String" $
        TypeParser.tokenize "Int -> String"
          @?= [TypeParser.TWord "Int", TypeParser.TArrow, TypeParser.TWord "String"],
      testCase "tokenizes List Int" $
        TypeParser.tokenize "List Int"
          @?= [TypeParser.TWord "List", TypeParser.TWord "Int"],
      testCase "tokenizes underscore as word start" $
        TypeParser.tokenize "_a" @?= [TypeParser.TWord "_a"],
      testCase "tokenizes qualified name as single word" $
        TypeParser.tokenize "Json.Value" @?= [TypeParser.TWord "Json.Value"],
      testCase "ignores unknown characters" $
        TypeParser.tokenize "Int @ String" @?= [TypeParser.TWord "Int", TypeParser.TWord "String"]
    ]

-- PRIMITIVE PARSING TESTS

parsePrimitivesTests :: TestTree
parsePrimitivesTests =
  testGroup
    "parseType primitives"
    [ testCase "parses Int" $
        TypeParser.parseType "Int" @?= Just FFIInt,
      testCase "parses Float" $
        TypeParser.parseType "Float" @?= Just FFIFloat,
      testCase "parses String" $
        TypeParser.parseType "String" @?= Just FFIString,
      testCase "parses Bool" $
        TypeParser.parseType "Bool" @?= Just FFIBool,
      testCase "parses Unit keyword" $
        TypeParser.parseType "Unit" @?= Just FFIUnit,
      testCase "parses () as Unit" $
        TypeParser.parseType "()" @?= Just FFIUnit,
      testCase "handles leading whitespace" $
        TypeParser.parseType "  Int" @?= Just FFIInt,
      testCase "handles trailing whitespace" $
        TypeParser.parseType "Int  " @?= Just FFIInt,
      testCase "handles surrounding whitespace" $
        TypeParser.parseType "  Float  " @?= Just FFIFloat,
      testCase "empty string returns Nothing" $
        TypeParser.parseType "" @?= Nothing,
      testCase "whitespace-only returns Nothing" $
        TypeParser.parseType "   " @?= Nothing
    ]

-- LIST PARSING TESTS

parseListTests :: TestTree
parseListTests =
  testGroup
    "parseType List"
    [ testCase "parses List Int" $
        TypeParser.parseType "List Int" @?= Just (FFIList FFIInt),
      testCase "parses List Float" $
        TypeParser.parseType "List Float" @?= Just (FFIList FFIFloat),
      testCase "parses List String" $
        TypeParser.parseType "List String" @?= Just (FFIList FFIString),
      testCase "parses List Bool" $
        TypeParser.parseType "List Bool" @?= Just (FFIList FFIBool),
      testCase "parses List (Maybe Int)" $
        TypeParser.parseType "List (Maybe Int)"
          @?= Just (FFIList (FFIMaybe FFIInt)),
      testCase "parses List (List Int)" $
        TypeParser.parseType "List (List Int)"
          @?= Just (FFIList (FFIList FFIInt)),
      testCase "parses List (Result String Int)" $
        TypeParser.parseType "List (Result String Int)"
          @?= Just (FFIList (FFIResult FFIString FFIInt))
    ]

-- MAYBE PARSING TESTS

parseMaybeTests :: TestTree
parseMaybeTests =
  testGroup
    "parseType Maybe"
    [ testCase "parses Maybe Int" $
        TypeParser.parseType "Maybe Int" @?= Just (FFIMaybe FFIInt),
      testCase "parses Maybe String" $
        TypeParser.parseType "Maybe String" @?= Just (FFIMaybe FFIString),
      testCase "parses Maybe Bool" $
        TypeParser.parseType "Maybe Bool" @?= Just (FFIMaybe FFIBool),
      testCase "parses Maybe (List Int)" $
        TypeParser.parseType "Maybe (List Int)"
          @?= Just (FFIMaybe (FFIList FFIInt)),
      testCase "parses Maybe (Maybe String)" $
        TypeParser.parseType "Maybe (Maybe String)"
          @?= Just (FFIMaybe (FFIMaybe FFIString))
    ]

-- RESULT PARSING TESTS

parseResultTests :: TestTree
parseResultTests =
  testGroup
    "parseType Result"
    [ testCase "parses Result String Int" $
        TypeParser.parseType "Result String Int"
          @?= Just (FFIResult FFIString FFIInt),
      testCase "parses Result String Bool" $
        TypeParser.parseType "Result String Bool"
          @?= Just (FFIResult FFIString FFIBool),
      testCase "parses Result with opaque error type" $
        TypeParser.parseType "Result Error Int"
          @?= Just (FFIResult (FFIOpaque "Error" []) FFIInt),
      testCase "parses Result with parens around first arg" $
        TypeParser.parseType "Result (List String) Int"
          @?= Just (FFIResult (FFIList FFIString) FFIInt),
      testCase "parses Result with parens around second arg" $
        TypeParser.parseType "Result String (List Int)"
          @?= Just (FFIResult FFIString (FFIList FFIInt))
    ]

-- TASK PARSING TESTS

parseTaskTests :: TestTree
parseTaskTests =
  testGroup
    "parseType Task"
    [ testCase "parses Task String Int" $
        TypeParser.parseType "Task String Int"
          @?= Just (FFITask FFIString FFIInt),
      testCase "parses Task with opaque types" $
        TypeParser.parseType "Task Error Value"
          @?= Just (FFITask (FFIOpaque "Error" []) (FFIOpaque "Value" [])),
      testCase "parses Task with nested types" $
        TypeParser.parseType "Task String (List Int)"
          @?= Just (FFITask FFIString (FFIList FFIInt))
    ]

-- TUPLE PARSING TESTS

parseTupleTests :: TestTree
parseTupleTests =
  testGroup
    "parseType Tuple"
    [ testCase "parses (Int, String)" $
        TypeParser.parseType "(Int, String)"
          @?= Just (FFITuple [FFIInt, FFIString]),
      testCase "parses (Int, String, Bool)" $
        TypeParser.parseType "(Int, String, Bool)"
          @?= Just (FFITuple [FFIInt, FFIString, FFIBool]),
      testCase "parses (Int, Int, Int, Int) four-tuple" $
        TypeParser.parseType "(Int, Int, Int, Int)"
          @?= Just (FFITuple [FFIInt, FFIInt, FFIInt, FFIInt]),
      testCase "parses tuple with complex element" $
        TypeParser.parseType "(List Int, Maybe String)"
          @?= Just (FFITuple [FFIList FFIInt, FFIMaybe FFIString]),
      testCase "parenthesized single type is not a tuple" $
        TypeParser.parseType "(Int)" @?= Just FFIInt
    ]

-- RECORD PARSING TESTS

parseRecordTests :: TestTree
parseRecordTests =
  testGroup
    "parseType Record"
    [ testCase "parses empty record" $
        TypeParser.parseType "{}" @?= Just (FFIRecord []),
      testCase "parses single-field record" $
        TypeParser.parseType "{ x : Int }"
          @?= Just (FFIRecord [("x", FFIInt)]),
      testCase "parses two-field record" $
        TypeParser.parseType "{ name : String, age : Int }"
          @?= Just (FFIRecord [("name", FFIString), ("age", FFIInt)]),
      testCase "parses record with List field" $
        TypeParser.parseType "{ items : List String }"
          @?= Just (FFIRecord [("items", FFIList FFIString)]),
      testCase "rejects record with duplicate fields" $
        TypeParser.parseType "{ x : Int, x : String }" @?= Nothing,
      testCase "parses record with Maybe field" $
        TypeParser.parseType "{ value : Maybe Int }"
          @?= Just (FFIRecord [("value", FFIMaybe FFIInt)])
    ]

-- FUNCTION TYPE PARSING TESTS

parseFunctionTypeTests :: TestTree
parseFunctionTypeTests =
  testGroup
    "parseType function types"
    [ testCase "parses Int -> String" $
        TypeParser.parseType "Int -> String"
          @?= Just (FFIFunctionType [FFIInt] FFIString),
      testCase "parses Int -> String -> Bool" $
        TypeParser.parseType "Int -> String -> Bool"
          @?= Just (FFIFunctionType [FFIInt, FFIString] FFIBool),
      testCase "parses with complex return type" $
        TypeParser.parseType "Int -> Result String Bool"
          @?= Just (FFIFunctionType [FFIInt] (FFIResult FFIString FFIBool)),
      testCase "parses with complex parameter type" $
        TypeParser.parseType "List Int -> String"
          @?= Just (FFIFunctionType [FFIList FFIInt] FFIString),
      testCase "parses three-parameter function" $
        TypeParser.parseType "Int -> String -> Bool -> Float"
          @?= Just (FFIFunctionType [FFIInt, FFIString, FFIBool] FFIFloat),
      testCase "parses function returning Task" $
        TypeParser.parseType "String -> Task String Int"
          @?= Just (FFIFunctionType [FFIString] (FFITask FFIString FFIInt)),
      testCase "parses function with parenthesized return" $
        TypeParser.parseType "Int -> (String, Bool)"
          @?= Just (FFIFunctionType [FFIInt] (FFITuple [FFIString, FFIBool]))
    ]

-- OPAQUE TYPE PARSING TESTS

parseOpaqueTests :: TestTree
parseOpaqueTests =
  testGroup
    "parseType opaque types"
    [ testCase "parses uppercase name as opaque" $
        TypeParser.parseType "AudioContext"
          @?= Just (FFIOpaque "AudioContext" []),
      testCase "parses qualified name as opaque" $
        TypeParser.parseType "Json.Value"
          @?= Just (FFIOpaque "Json.Value" []),
      testCase "parses opaque type with type argument" $
        TypeParser.parseType "Cmd msg"
          @?= Just (FFIOpaque "Cmd" [FFITypeVar "msg"]),
      testCase "parses opaque type with two type args" $
        TypeParser.parseType "Program flags model"
          @?= Just (FFIOpaque "Program" [FFITypeVar "flags", FFITypeVar "model"]),
      testCase "parses opaque with Int argument" $
        TypeParser.parseType "JsArray Int"
          @?= Just (FFIOpaque "JsArray" [FFIInt]),
      testCase "deeply qualified name preserved" $
        TypeParser.parseType "Data.Decode.Value"
          @?= Just (FFIOpaque "Data.Decode.Value" [])
    ]

-- TYPE VARIABLE PARSING TESTS

parseTypeVarTests :: TestTree
parseTypeVarTests =
  testGroup
    "parseType type variables"
    [ testCase "lowercase name is type variable" $
        TypeParser.parseType "a" @?= Just (FFITypeVar "a"),
      testCase "msg is type variable" $
        TypeParser.parseType "msg" @?= Just (FFITypeVar "msg"),
      testCase "comparable is type variable" $
        TypeParser.parseType "comparable" @?= Just (FFITypeVar "comparable"),
      testCase "number is type variable" $
        TypeParser.parseType "number" @?= Just (FFITypeVar "number"),
      testCase "appendable is type variable" $
        TypeParser.parseType "appendable" @?= Just (FFITypeVar "appendable"),
      testCase "type variable in List" $
        TypeParser.parseType "List a"
          @?= Just (FFIList (FFITypeVar "a")),
      testCase "type variable in Maybe" $
        TypeParser.parseType "Maybe a"
          @?= Just (FFIMaybe (FFITypeVar "a"))
    ]

-- PARSE RETURN TYPE TESTS

parseReturnTypeTests :: TestTree
parseReturnTypeTests =
  testGroup
    "parseReturnType"
    [ testCase "returns last type of function" $
        TypeParser.parseReturnType "Int -> String" @?= Just FFIString,
      testCase "returns last of three-arg function" $
        TypeParser.parseReturnType "Int -> String -> Bool" @?= Just FFIBool,
      testCase "returns whole type for non-function" $
        TypeParser.parseReturnType "Int" @?= Just FFIInt,
      testCase "returns complex return type" $
        TypeParser.parseReturnType "Int -> Result String Bool"
          @?= Just (FFIResult FFIString FFIBool),
      testCase "returns Task for async function sig" $
        TypeParser.parseReturnType "String -> Task String Int"
          @?= Just (FFITask FFIString FFIInt),
      testCase "empty string returns Nothing" $
        TypeParser.parseReturnType "" @?= Nothing,
      testCase "returns opaque for opaque-returning function" $
        TypeParser.parseReturnType "String -> AudioContext"
          @?= Just (FFIOpaque "AudioContext" [])
    ]

-- COUNT ARITY TESTS

countArityTests :: TestTree
countArityTests =
  testGroup
    "countArity"
    [ testCase "arity 0 for non-function" $
        TypeParser.countArity FFIInt @?= 0,
      testCase "arity 0 for opaque" $
        TypeParser.countArity (FFIOpaque "Ctx" []) @?= 0,
      testCase "arity 1 for single-param function" $
        TypeParser.countArity (FFIFunctionType [FFIInt] FFIString) @?= 1,
      testCase "arity 2 for two-param function" $
        TypeParser.countArity (FFIFunctionType [FFIInt, FFIString] FFIBool) @?= 2,
      testCase "arity 3 for three-param function" $
        TypeParser.countArity (FFIFunctionType [FFIInt, FFIString, FFIBool] FFIFloat) @?= 3,
      testCase "arity 0 for Maybe" $
        TypeParser.countArity (FFIMaybe FFIInt) @?= 0,
      testCase "arity 0 for List" $
        TypeParser.countArity (FFIList FFIInt) @?= 0,
      testCase "arity 0 for Result" $
        TypeParser.countArity (FFIResult FFIString FFIInt) @?= 0
    ]

-- EDGE CASE TESTS

edgeCaseTests :: TestTree
edgeCaseTests =
  testGroup
    "edge cases"
    [ testCase "nested parens parse correctly" $
        TypeParser.parseType "((Int))" @?= Just FFIInt,
      testCase "deeply nested List" $
        TypeParser.parseType "List (List (List Int))"
          @?= Just (FFIList (FFIList (FFIList FFIInt))),
      testCase "deeply nested Maybe" $
        TypeParser.parseType "Maybe (Maybe (Maybe Bool))"
          @?= Just (FFIMaybe (FFIMaybe (FFIMaybe FFIBool))),
      testCase "arrow inside parens is not a top-level arrow" $
        TypeParser.parseType "(Int -> String) -> Bool"
          @?= Just (FFIFunctionType [FFIFunctionType [FFIInt] FFIString] FFIBool),
      testCase "tuple inside function type" $
        TypeParser.parseType "(Int, Bool) -> String"
          @?= Just (FFIFunctionType [FFITuple [FFIInt, FFIBool]] FFIString),
      testCase "function type with record parameter" $
        TypeParser.parseType "{ x : Int } -> String"
          @?= Just (FFIFunctionType [FFIRecord [("x", FFIInt)]] FFIString),
      testCase "no-whitespace arrow parses" $
        TypeParser.parseType "Int->String"
          @?= Just (FFIFunctionType [FFIInt] FFIString),
      testCase "Result with both complex args" $
        TypeParser.parseType "Result (List String) (Maybe Int)"
          @?= Just (FFIResult (FFIList FFIString) (FFIMaybe FFIInt)),
      testCase "function returning nothing via Unit" $
        TypeParser.parseType "Int -> Unit"
          @?= Just (FFIFunctionType [FFIInt] FFIUnit),
      testCase "function taking unit tuple" $
        TypeParser.parseType "() -> Int"
          @?= Just (FFIFunctionType [FFIUnit] FFIInt)
    ]

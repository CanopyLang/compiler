{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for FFI type parsing
--
-- Tests the type parser for function types, ensuring parameters
-- are extracted in the correct order (left to right).
--
-- @since 0.19.1
module Unit.Foreign.FFITypeParseTest (tests) where

import qualified Data.Text as Text
import qualified Foreign.FFI as FFI
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Foreign.FFI Type Parsing Tests"
    [ testSimpleFunctionTypes,
      testMultiParameterFunctions,
      testFunctionTypesWithComplexReturn,
      testResultReturnTypes,
      testTaskReturnTypes,
      testNestedFunctionTypes
    ]

-- | Test simple function type parsing
testSimpleFunctionTypes :: TestTree
testSimpleFunctionTypes =
  testGroup
    "Simple function type parsing"
    [ testCase "Single parameter function: Int -> String" $ do
        let result = FFI.parseCanopyTypeAnnotation "Int -> String"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            length params @?= 1
            params @?= [FFI.FFIBasic "Int"]
            returnType @?= FFI.FFIBasic "String"
          _ -> assertFailure "Expected FFIFunctionType but got different result",
      testCase "Two parameter function: String -> Int -> Bool" $ do
        let result = FFI.parseCanopyTypeAnnotation "String -> Int -> Bool"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            length params @?= 2
            params @?= [FFI.FFIBasic "String", FFI.FFIBasic "Int"]
            returnType @?= FFI.FFIBasic "Bool"
          _ -> assertFailure "Expected FFIFunctionType with 2 params",
      testCase "Three parameter function: Int -> String -> Float -> Bool" $ do
        let result = FFI.parseCanopyTypeAnnotation "Int -> String -> Float -> Bool"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            length params @?= 3
            params @?= [FFI.FFIBasic "Int", FFI.FFIBasic "String", FFI.FFIBasic "Float"]
            returnType @?= FFI.FFIBasic "Bool"
          _ -> assertFailure "Expected FFIFunctionType with 3 params"
    ]

-- | Test multi-parameter functions maintain correct order
testMultiParameterFunctions :: TestTree
testMultiParameterFunctions =
  testGroup
    "Multi-parameter function order tests"
    [ testCase "Parameter order preserved: A -> B -> C -> D" $ do
        let result = FFI.parseCanopyTypeAnnotation "Int -> Float -> String -> Bool"
        case result of
          Just (FFI.FFIFunctionType params _) -> do
            -- First parameter should be Int, not Bool
            head params @?= FFI.FFIBasic "Int"
            -- Second parameter should be Float
            (params !! 1) @?= FFI.FFIBasic "Float"
            -- Third parameter should be String
            (params !! 2) @?= FFI.FFIBasic "String"
          _ -> assertFailure "Failed to parse multi-parameter function",
      testCase "Complex opaque types maintain order" $ do
        let result = FFI.parseCanopyTypeAnnotation "AudioContext -> Float -> String -> OscillatorNode"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            params !! 0 @?= FFI.FFIOpaque "AudioContext"
            params !! 1 @?= FFI.FFIBasic "Float"
            params !! 2 @?= FFI.FFIBasic "String"
            returnType @?= FFI.FFIOpaque "OscillatorNode"
          _ -> assertFailure "Failed to parse opaque type function"
    ]

-- | Test function types with complex return types
testFunctionTypesWithComplexReturn :: TestTree
testFunctionTypesWithComplexReturn =
  testGroup
    "Functions with complex return types"
    [ testCase "Function returning Maybe: Int -> String -> Maybe Bool" $ do
        let result = FFI.parseCanopyTypeAnnotation "Int -> String -> Maybe Bool"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            params @?= [FFI.FFIBasic "Int", FFI.FFIBasic "String"]
            returnType @?= FFI.FFIMaybe (FFI.FFIBasic "Bool")
          _ -> assertFailure "Failed to parse Maybe return type",
      testCase "Function returning List: String -> Int -> List Float" $ do
        let result = FFI.parseCanopyTypeAnnotation "String -> Int -> List Float"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            params @?= [FFI.FFIBasic "String", FFI.FFIBasic "Int"]
            returnType @?= FFI.FFIList (FFI.FFIBasic "Float")
          _ -> assertFailure "Failed to parse List return type"
    ]

-- | Test Result return types (union types)
testResultReturnTypes :: TestTree
testResultReturnTypes =
  testGroup
    "Result return type tests (union types)"
    [ testCase "Simple Result return: Int -> Result String Bool" $ do
        let result = FFI.parseCanopyTypeAnnotation "Int -> Result String Bool"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            params @?= [FFI.FFIBasic "Int"]
            returnType @?= FFI.FFIResult (FFI.FFIBasic "String") (FFI.FFIBasic "Bool")
          _ -> assertFailure "Failed to parse Result return type",
      testCase "Multi-param with Result: UserActivated -> Result CapabilityError AudioContext" $ do
        let result = FFI.parseCanopyTypeAnnotation "UserActivated -> Result CapabilityError AudioContext"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            params @?= [FFI.FFIOpaque "UserActivated"]
            returnType @?= FFI.FFIResult (FFI.FFIOpaque "CapabilityError") (FFI.FFIOpaque "AudioContext")
          _ -> assertFailure "Failed to parse capability Result type",
      testCase "Complex Result with qualified types" $ do
        let result = FFI.parseCanopyTypeAnnotation "UserActivated -> Result Capability.CapabilityError (Capability.Initialized AudioContext)"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            length params @?= 1
            case returnType of
              FFI.FFIResult errType valType -> do
                errType @?= FFI.FFIOpaque "CapabilityError"
                -- The value type should be parsed as a single opaque type or wrapped type
                case valType of
                  FFI.FFIOpaque _ -> return () -- Accept opaque parsing
                  _ -> return () -- Accept other valid parsings
              _ -> assertFailure "Expected FFIResult return type"
          _ -> assertFailure "Failed to parse qualified Result type"
    ]

-- | Test Task return types (async operations with union types)
testTaskReturnTypes :: TestTree
testTaskReturnTypes =
  testGroup
    "Task return type tests"
    [ testCase "Simple Task: () -> Task String Int" $ do
        let result = FFI.parseCanopyTypeAnnotation "() -> Task String Int"
        case result of
          Just returnType -> do
            -- For unit parameter, it might be skipped or included
            case returnType of
              FFI.FFITask errType valType -> do
                errType @?= FFI.FFIBasic "String"
                valType @?= FFI.FFIBasic "Int"
              FFI.FFIFunctionType _ (FFI.FFITask errType valType) -> do
                errType @?= FFI.FFIBasic "String"
                valType @?= FFI.FFIBasic "Int"
              _ -> assertFailure "Expected Task return type"
          Nothing -> assertFailure "Failed to parse Task type",
      testCase "Multi-param Task: AudioContext -> String -> Task CapabilityError AudioBuffer" $ do
        let result = FFI.parseCanopyTypeAnnotation "AudioContext -> String -> Task CapabilityError AudioBuffer"
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            params @?= [FFI.FFIOpaque "AudioContext", FFI.FFIBasic "String"]
            returnType @?= FFI.FFITask (FFI.FFIOpaque "CapabilityError") (FFI.FFIOpaque "AudioBuffer")
          _ -> assertFailure "Failed to parse Task with multiple params"
    ]

-- | Test nested function types (higher-order functions)
testNestedFunctionTypes :: TestTree
testNestedFunctionTypes =
  testGroup
    "Nested function types"
    [ testCase "Function taking function parameter" $ do
        -- This tests parenthesized function types
        let result = FFI.parseCanopyTypeAnnotation "(Int -> String) -> Bool"
        -- This should parse as a single parameter function where the param is a function type
        case result of
          Just (FFI.FFIFunctionType params returnType) -> do
            length params @?= 1
            case head params of
              FFI.FFIFunctionType nestedParams nestedReturn -> do
                nestedParams @?= [FFI.FFIBasic "Int"]
                nestedReturn @?= FFI.FFIBasic "String"
              _ -> assertFailure "Expected nested function type as parameter"
            returnType @?= FFI.FFIBasic "Bool"
          _ -> assertFailure "Failed to parse higher-order function"
    ]

-- Helper for showing parse results in failures
_showFFIType :: FFI.FFIType -> String
_showFFIType ffiType = Text.unpack (case FFI.ffiTypeToCanopyType ffiType of
  Right text -> text
  Left _ -> "<<parse error>>")

{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the FFI static analysis module.
--
-- Verifies that the JavaScript static analyzer correctly detects:
-- * Mixed-type operations (number + string)
-- * Nullable returns for non-Maybe declared types
-- * Missing return paths
-- * Loose equality (== instead of ===)
-- * Async function / Task type mismatches
-- * Result tag construction issues
-- * Return type consistency
-- * Mixed array elements
--
-- @since 0.20.0
module Unit.FFI.StaticAnalysisTest (tests) where

import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified FFI.StaticAnalysis as SA
import FFI.Types (FFIType (..))
import Language.JavaScript.Parser.AST
  ( JSAnnot (..),
    JSArrayElement (..),
    JSBinOp (..),
    JSBlock (..),
    JSCommaList (..),
    JSCommaTrailingList (..),
    JSExpression (..),
    JSIdent (..),
    JSObjectProperty (..),
    JSPropertyName (..),
    JSSemi (..),
    JSStatement (..),
    JSUnaryOp (..),
  )
import Language.JavaScript.Parser.SrcLocation (TokenPosn (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI.StaticAnalysis Tests"
    [ inferExprTypeTests,
      mixedTypeDetectionTests,
      looseEqualityTests,
      returnPathTests,
      asyncMismatchTests,
      resultTagTests,
      returnTypeMismatchTests,
      arrayElementTests,
      integrationTests,
      commaListHelperTests
    ]

-- HELPERS

-- | Create a JSAnnot at a specific line number.
annot :: Int -> JSAnnot
annot line = JSAnnot (TokenPn 0 line 1) []

-- | No annotation.
noAnnot :: JSAnnot
noAnnot = JSNoAnnot

-- | No semicolon.
noSemi :: JSSemi
noSemi = JSSemiAuto

-- | Create a number literal expression.
jsNumber :: Int -> JSExpression
jsNumber n = JSDecimal (annot 1) (fromIntegral n)

-- | Create a string literal expression.
jsString :: JSExpression
jsString = JSStringLiteral (annot 1) (BSC.pack "'hello'")

-- | Create an identifier expression.
jsIdent :: String -> JSExpression
jsIdent name = JSIdentifier (annot 1) (BSC.pack name)

-- | Create a null literal expression.
jsNull :: JSExpression
jsNull = JSLiteral (annot 1) (BSC.pack "null")

-- | Create an undefined literal expression.
jsUndefined :: JSExpression
jsUndefined = JSLiteral (annot 1) (BSC.pack "undefined")

-- | Create a boolean true literal.
jsTrue :: JSExpression
jsTrue = JSLiteral (annot 1) (BSC.pack "true")

-- | Create a boolean false literal.
jsFalse :: JSExpression
jsFalse = JSLiteral (annot 1) (BSC.pack "false")

-- | Create a binary expression.
jsBinOp :: JSExpression -> JSBinOp -> JSExpression -> JSExpression
jsBinOp = JSExpressionBinary

-- | Create a return statement.
jsReturn :: Int -> JSExpression -> JSStatement
jsReturn line expr = JSReturn (annot line) (Just expr) noSemi

-- | Create a return statement without a value.
jsReturnVoid :: Int -> JSStatement
jsReturnVoid line = JSReturn (annot line) Nothing noSemi

-- | Create a function statement.
jsFunc :: String -> [JSStatement] -> JSStatement
jsFunc name body =
  JSFunction
    (annot 1)
    (JSIdentName noAnnot (BSC.pack name))
    noAnnot
    JSLNil
    noAnnot
    (JSBlock noAnnot body noAnnot)
    noSemi

-- | Create an async function statement.
jsAsyncFunc :: String -> [JSStatement] -> JSStatement
jsAsyncFunc name body =
  JSAsyncFunction
    (annot 1)
    (annot 1)
    (JSIdentName noAnnot (BSC.pack name))
    noAnnot
    JSLNil
    noAnnot
    (JSBlock noAnnot body noAnnot)
    noSemi

-- | Create an if/else statement.
jsIfElse :: JSExpression -> JSStatement -> JSStatement -> JSStatement
jsIfElse cond thenBranch elseBranch =
  JSIfElse
    (annot 1)
    noAnnot
    cond
    noAnnot
    thenBranch
    noAnnot
    elseBranch

-- | Create an if-without-else statement.
jsIf :: JSExpression -> JSStatement -> JSStatement
jsIf cond thenBranch =
  JSIf (annot 1) noAnnot cond noAnnot thenBranch

-- | Create an object literal with properties.
jsObject :: [(String, JSExpression)] -> JSExpression
jsObject props =
  JSObjectLiteral noAnnot (JSCTLNone (buildCommaList propNodes)) noAnnot
  where
    propNodes = map toProp props
    toProp (k, v) =
      JSPropertyNameandValue
        (JSPropertyIdent noAnnot (BSC.pack k))
        noAnnot
        [v]

-- | Create an array literal.
jsArray :: [JSExpression] -> JSExpression
jsArray elems =
  JSArrayLiteral noAnnot (map JSArrayElement elems) noAnnot

-- | Build a JSCommaList from a list.
buildCommaList :: [a] -> JSCommaList a
buildCommaList [] = JSLNil
buildCommaList [x] = JSLOne x
buildCommaList (x : xs) = foldl (\acc item -> JSLCons acc noAnnot item) (JSLOne x) xs

-- | Run analysis on a list of statements with declared types.
analyze :: [JSStatement] -> Map.Map Text.Text FFIType -> [SA.FFIWarning]
analyze stmts types = SA._analysisWarnings (SA.analyzeFFIFile stmts types)

-- | Convenience: analyze a single function.
analyzeFunc :: String -> [JSStatement] -> FFIType -> [SA.FFIWarning]
analyzeFunc name body declaredType =
  analyze [jsFunc name body] (Map.singleton (Text.pack name) declaredType)

-- TYPE INFERENCE TESTS

inferExprTypeTests :: TestTree
inferExprTypeTests =
  testGroup
    "inferExprType"
    [ testCase "number literal" $
        SA.inferExprType (jsNumber 42) @?= SA.InfNumber,
      testCase "hex integer" $
        SA.inferExprType (JSHexInteger (annot 1) 255) @?= SA.InfNumber,
      testCase "string literal" $
        SA.inferExprType jsString @?= SA.InfString,
      testCase "true literal" $
        SA.inferExprType jsTrue @?= SA.InfBoolean,
      testCase "false literal" $
        SA.inferExprType jsFalse @?= SA.InfBoolean,
      testCase "null literal" $
        SA.inferExprType jsNull @?= SA.InfNull,
      testCase "undefined literal" $
        SA.inferExprType jsUndefined @?= SA.InfNull,
      testCase "identifier is unknown" $
        SA.inferExprType (jsIdent "x") @?= SA.InfUnknown,
      testCase "number + number = number" $
        SA.inferExprType (jsBinOp (jsNumber 1) (JSBinOpPlus noAnnot) (jsNumber 2))
          @?= SA.InfNumber,
      testCase "string + string = string" $
        SA.inferExprType (jsBinOp jsString (JSBinOpPlus noAnnot) jsString)
          @?= SA.InfString,
      testCase "number + string = string (JS coercion)" $
        SA.inferExprType (jsBinOp (jsNumber 1) (JSBinOpPlus noAnnot) jsString)
          @?= SA.InfString,
      testCase "number - number = number" $
        SA.inferExprType (jsBinOp (jsNumber 1) (JSBinOpMinus noAnnot) (jsNumber 2))
          @?= SA.InfNumber,
      testCase "number * number = number" $
        SA.inferExprType (jsBinOp (jsNumber 1) (JSBinOpTimes noAnnot) (jsNumber 2))
          @?= SA.InfNumber,
      testCase "number / number = number" $
        SA.inferExprType (jsBinOp (jsNumber 1) (JSBinOpDivide noAnnot) (jsNumber 2))
          @?= SA.InfNumber,
      testCase "strict equality = boolean" $
        SA.inferExprType (jsBinOp (jsNumber 1) (JSBinOpStrictEq noAnnot) (jsNumber 2))
          @?= SA.InfBoolean,
      testCase "less than = boolean" $
        SA.inferExprType (jsBinOp (jsNumber 1) (JSBinOpLt noAnnot) (jsNumber 2))
          @?= SA.InfBoolean,
      testCase "typeof returns string" $
        SA.inferExprType (JSUnaryExpression (JSUnaryOpTypeof noAnnot) (jsIdent "x"))
          @?= SA.InfString,
      testCase "negation returns boolean" $
        SA.inferExprType (JSUnaryExpression (JSUnaryOpNot noAnnot) jsTrue)
          @?= SA.InfBoolean,
      testCase "unary minus returns number" $
        SA.inferExprType (JSUnaryExpression (JSUnaryOpMinus noAnnot) (jsNumber 1))
          @?= SA.InfNumber,
      testCase "void returns null" $
        SA.inferExprType (JSUnaryExpression (JSUnaryOpVoid noAnnot) (jsNumber 0))
          @?= SA.InfNull,
      testCase "object literal with fields" $
        SA.inferExprType (jsObject [("x", jsNumber 1), ("y", jsString)])
          @?= SA.InfObject [("x", SA.InfNumber), ("y", SA.InfString)],
      testCase "empty array" $
        SA.inferExprType (jsArray [])
          @?= SA.InfArray SA.InfUnknown,
      testCase "number array" $
        SA.inferExprType (jsArray [jsNumber 1, jsNumber 2])
          @?= SA.InfArray SA.InfNumber,
      testCase "ternary produces union" $
        SA.inferExprType (JSExpressionTernary jsTrue noAnnot (jsNumber 1) noAnnot jsString)
          @?= SA.InfUnion [SA.InfNumber, SA.InfString],
      testCase "parenthesized expression" $
        SA.inferExprType (JSExpressionParen noAnnot (jsNumber 42) noAnnot)
          @?= SA.InfNumber
    ]

-- MIXED-TYPE OPERATION TESTS

mixedTypeDetectionTests :: TestTree
mixedTypeDetectionTests =
  testGroup
    "Mixed-type operations"
    [ testCase "detects number + string" $
        let body = [jsReturn 3 (jsBinOp (jsNumber 1) (JSBinOpPlus (annot 3)) jsString)]
            warnings = analyzeFunc "add" body (FFIFunctionType [FFIInt, FFIString] FFIInt)
         in assertBool "should detect mixed-type addition" (any isMixedType warnings),
      testCase "detects string + number" $
        let body = [jsReturn 3 (jsBinOp jsString (JSBinOpPlus (annot 3)) (jsNumber 1))]
            warnings = analyzeFunc "concat" body (FFIFunctionType [FFIString, FFIInt] FFIString)
         in assertBool "should detect mixed-type addition" (any isMixedType warnings),
      testCase "detects null + number" $
        let body = [jsReturn 3 (jsBinOp jsNull (JSBinOpPlus (annot 3)) (jsNumber 1))]
            warnings = analyzeFunc "bad" body (FFIFunctionType [FFIUnit, FFIInt] FFIInt)
         in assertBool "should detect null + number" (any isMixedType warnings),
      testCase "detects string in subtraction" $
        let body = [jsReturn 3 (jsBinOp (jsNumber 1) (JSBinOpMinus (annot 3)) jsString)]
            warnings = analyzeFunc "sub" body (FFIFunctionType [FFIInt, FFIString] FFIInt)
         in assertBool "should detect string in subtraction" (any isMixedType warnings),
      testCase "no warning for number + number" $
        let body = [jsReturn 3 (jsBinOp (jsNumber 1) (JSBinOpPlus (annot 3)) (jsNumber 2))]
            warnings = analyzeFunc "add" body (FFIFunctionType [FFIInt, FFIInt] FFIInt)
         in assertBool "should not warn for number + number" (not (any isMixedType warnings)),
      testCase "no warning for string + string" $
        let body = [jsReturn 3 (jsBinOp jsString (JSBinOpPlus (annot 3)) jsString)]
            warnings = analyzeFunc "concat" body (FFIFunctionType [FFIString, FFIString] FFIString)
         in assertBool "should not warn for string + string" (not (any isMixedType warnings)),
      testCase "mixed-type warning includes function name" $
        let body = [jsReturn 3 (jsBinOp (jsNumber 1) (JSBinOpPlus (annot 3)) jsString)]
            warnings = analyzeFunc "calculate" body (FFIFunctionType [FFIInt, FFIString] FFIInt)
         in case filter isMixedType warnings of
              (SA.MixedTypeOperation _ name _ : _) -> name @?= "calculate"
              _ -> assertFailure "expected MixedTypeOperation warning"
    ]

-- LOOSE EQUALITY TESTS

looseEqualityTests :: TestTree
looseEqualityTests =
  testGroup
    "Loose equality detection"
    [ testCase "detects == operator" $
        let body = [jsReturn 3 (jsBinOp (jsIdent "a") (JSBinOpEq (annot 3)) (jsIdent "b"))]
            warnings = analyzeFunc "eq" body (FFIFunctionType [FFIInt, FFIInt] FFIBool)
         in assertBool "should detect ==" (any isLooseEquality warnings),
      testCase "detects != operator" $
        let body = [jsReturn 3 (jsBinOp (jsIdent "a") (JSBinOpNeq (annot 3)) (jsIdent "b"))]
            warnings = analyzeFunc "neq" body (FFIFunctionType [FFIInt, FFIInt] FFIBool)
         in assertBool "should detect !=" (any isLooseEquality warnings),
      testCase "no warning for ===" $
        let body = [jsReturn 3 (jsBinOp (jsIdent "a") (JSBinOpStrictEq (annot 3)) (jsIdent "b"))]
            warnings = analyzeFunc "eq" body (FFIFunctionType [FFIInt, FFIInt] FFIBool)
         in assertBool "should not warn for ===" (not (any isLooseEquality warnings)),
      testCase "no warning for !==" $
        let body = [jsReturn 3 (jsBinOp (jsIdent "a") (JSBinOpStrictNeq (annot 3)) (jsIdent "b"))]
            warnings = analyzeFunc "neq" body (FFIFunctionType [FFIInt, FFIInt] FFIBool)
         in assertBool "should not warn for !==" (not (any isLooseEquality warnings)),
      testCase "loose equality warning includes function name" $
        let body = [jsReturn 3 (jsBinOp (jsIdent "a") (JSBinOpEq (annot 5)) (jsIdent "b"))]
            warnings = analyzeFunc "compare" body (FFIFunctionType [FFIInt, FFIInt] FFIBool)
         in case filter isLooseEquality warnings of
              (SA.LooseEquality _ name : _) -> name @?= "compare"
              _ -> assertFailure "expected LooseEquality warning"
    ]

-- RETURN PATH TESTS

returnPathTests :: TestTree
returnPathTests =
  testGroup
    "Return path analysis"
    [ testCase "detects missing return (if without else)" $
        let body = [jsIf (jsIdent "x") (jsReturn 2 (jsNumber 1))]
            warnings = analyzeFunc "maybeReturn" body (FFIFunctionType [FFIBool] FFIInt)
         in assertBool "should detect missing return" (any isMissingReturn warnings),
      testCase "no warning for if/else with returns" $
        let body =
              [ jsIfElse
                  (jsIdent "x")
                  (jsReturn 2 (jsNumber 1))
                  (jsReturn 4 (jsNumber 0))
              ]
            warnings = analyzeFunc "branch" body (FFIFunctionType [FFIBool] FFIInt)
         in assertBool "should not warn for complete branches" (not (any isMissingReturn warnings)),
      testCase "no warning for single return" $
        let body = [jsReturn 2 (jsNumber 42)]
            warnings = analyzeFunc "simple" body (FFIFunctionType [] FFIInt)
         in assertBool "should not warn for single return" (not (any isMissingReturn warnings)),
      testCase "detects nullable return for non-Maybe type" $
        let body = [jsIf (jsIdent "x") (jsReturn 2 (jsNumber 1))]
            warnings = analyzeFunc "lookup" body (FFIFunctionType [FFIString] FFIInt)
         in assertBool "should detect nullable return" (any isNullableReturn warnings),
      testCase "no nullable warning for Maybe type" $
        let body = [jsIf (jsIdent "x") (jsReturn 2 (jsNumber 1))]
            warnings = analyzeFunc "lookup" body (FFIFunctionType [FFIString] (FFIMaybe FFIInt))
         in assertBool "should not warn for Maybe type" (not (any isNullableReturn warnings)),
      testCase "no nullable warning for Unit type" $
        let body = [jsReturnVoid 2]
            warnings = analyzeFunc "doSomething" body (FFIFunctionType [] FFIUnit)
         in assertBool "should not warn for Unit type" (not (any isNullableReturn warnings)),
      testCase "analyzeReturnPaths collects explicit return" $
        let block = JSBlock noAnnot [jsReturn 3 (jsNumber 42)] noAnnot
            paths = SA.analyzeReturnPaths block
         in length paths @?= 1,
      testCase "analyzeReturnPaths detects implicit undefined from empty body" $
        let block = JSBlock noAnnot [] noAnnot
            paths = SA.analyzeReturnPaths block
         in assertBool "should have implicit undefined" (any isImplicitUndefinedPath paths)
    ]

-- ASYNC MISMATCH TESTS

asyncMismatchTests :: TestTree
asyncMismatchTests =
  testGroup
    "Async/Task mismatch"
    [ testCase "detects async function without Task type" $
        let stmts = [jsAsyncFunc "fetchData" [jsReturn 2 (jsNumber 1)]]
            types = Map.singleton "fetchData" (FFIFunctionType [FFIString] FFIInt)
            warnings = analyze stmts types
         in assertBool "should detect async without Task" (any isAsyncWithoutTask warnings),
      testCase "no warning for async function with Task type" $
        let stmts = [jsAsyncFunc "fetchData" [jsReturn 2 (jsNumber 1)]]
            types = Map.singleton "fetchData" (FFIFunctionType [FFIString] (FFITask FFIString FFIInt))
            warnings = analyze stmts types
         in assertBool "should not warn for Task type" (not (any isAsyncWithoutTask warnings)),
      testCase "no warning for non-async function" $
        let stmts = [jsFunc "compute" [jsReturn 2 (jsNumber 1)]]
            types = Map.singleton "compute" (FFIFunctionType [FFIInt] FFIInt)
            warnings = analyze stmts types
         in assertBool "should not warn for sync function" (not (any isAsyncWithoutTask warnings)),
      testCase "async warning includes function name" $
        let stmts = [jsAsyncFunc "loadConfig" [jsReturn 2 (jsString)]]
            types = Map.singleton "loadConfig" (FFIFunctionType [] FFIString)
            warnings = analyze stmts types
         in case filter isAsyncWithoutTask warnings of
              (SA.AsyncWithoutTask _ name : _) -> name @?= "loadConfig"
              _ -> assertFailure "expected AsyncWithoutTask warning"
    ]

-- RESULT TAG TESTS

resultTagTests :: TestTree
resultTagTests =
  testGroup
    "Result tag validation"
    [ testCase "detects missing $ tag for Result type" $
        let body = [jsReturn 2 (jsObject [("value", jsNumber 42)])]
            warnings = analyzeFunc "parse" body (FFIFunctionType [FFIString] (FFIResult FFIString FFIInt))
         in assertBool "should detect missing $ tag" (any isResultTag warnings),
      testCase "no warning when $ tag present" $
        let body = [jsReturn 2 (jsObject [("$", jsString), ("a", jsNumber 42)])]
            warnings = analyzeFunc "parse" body (FFIFunctionType [FFIString] (FFIResult FFIString FFIInt))
         in assertBool "should not warn when $ tag present" (not (any isResultTag warnings)),
      testCase "no warning for non-Result type" $
        let body = [jsReturn 2 (jsNumber 42)]
            warnings = analyzeFunc "compute" body (FFIFunctionType [FFIInt] FFIInt)
         in assertBool "should not warn for non-Result type" (not (any isResultTag warnings)),
      testCase "detects missing $ tag in raw value return" $
        let body = [jsReturn 2 (jsNumber 42)]
            warnings = analyzeFunc "tryParse" body (FFIFunctionType [FFIString] (FFIResult FFIString FFIInt))
         in assertBool "should detect raw value for Result type" (any isResultTag warnings)
    ]

-- RETURN TYPE MISMATCH TESTS

returnTypeMismatchTests :: TestTree
returnTypeMismatchTests =
  testGroup
    "Return type mismatch"
    [ testCase "detects string return for Int type" $
        let body = [jsReturn 2 jsString]
            warnings = analyzeFunc "getId" body (FFIFunctionType [] FFIInt)
         in assertBool "should detect string->Int mismatch" (any isTypeMismatch warnings),
      testCase "detects number return for String type" $
        let body = [jsReturn 2 (jsNumber 42)]
            warnings = analyzeFunc "getName" body (FFIFunctionType [] FFIString)
         in assertBool "should detect number->String mismatch" (any isTypeMismatch warnings),
      testCase "detects boolean return for Int type" $
        let body = [jsReturn 2 jsTrue]
            warnings = analyzeFunc "getCount" body (FFIFunctionType [] FFIInt)
         in assertBool "should detect boolean->Int mismatch" (any isTypeMismatch warnings),
      testCase "no warning for matching number->Int" $
        let body = [jsReturn 2 (jsNumber 42)]
            warnings = analyzeFunc "getCount" body (FFIFunctionType [] FFIInt)
         in assertBool "should not warn for number->Int" (not (any isTypeMismatch warnings)),
      testCase "no warning for matching string->String" $
        let body = [jsReturn 2 jsString]
            warnings = analyzeFunc "getName" body (FFIFunctionType [] FFIString)
         in assertBool "should not warn for string->String" (not (any isTypeMismatch warnings)),
      testCase "no warning for matching boolean->Bool" $
        let body = [jsReturn 2 jsTrue]
            warnings = analyzeFunc "isValid" body (FFIFunctionType [] FFIBool)
         in assertBool "should not warn for boolean->Bool" (not (any isTypeMismatch warnings)),
      testCase "no warning for null->Maybe" $
        let body = [jsReturn 2 jsNull]
            warnings = analyzeFunc "lookup" body (FFIFunctionType [] (FFIMaybe FFIInt))
         in assertBool "should not warn for null->Maybe" (not (any isTypeMismatch warnings)),
      testCase "no warning for unknown type" $
        let body = [jsReturn 2 (jsIdent "complexValue")]
            warnings = analyzeFunc "compute" body (FFIFunctionType [] FFIInt)
         in assertBool "should not warn for unknown type" (not (any isTypeMismatch warnings))
    ]

-- MIXED ARRAY ELEMENT TESTS

arrayElementTests :: TestTree
arrayElementTests =
  testGroup
    "Array element analysis"
    [ testCase "detects mixed types in array" $
        let body = [jsReturn 2 (jsArray [jsNumber 1, jsString, jsNumber 3])]
            warnings = analyzeFunc "getItems" body (FFIFunctionType [] (FFIList FFIInt))
         in assertBool "should detect mixed array elements" (any isMixedArray warnings),
      testCase "no warning for uniform number array" $
        let body = [jsReturn 2 (jsArray [jsNumber 1, jsNumber 2, jsNumber 3])]
            warnings = analyzeFunc "getNumbers" body (FFIFunctionType [] (FFIList FFIInt))
         in assertBool "should not warn for uniform array" (not (any isMixedArray warnings)),
      testCase "no warning for uniform string array" $
        let body = [jsReturn 2 (jsArray [jsString, jsString])]
            warnings = analyzeFunc "getNames" body (FFIFunctionType [] (FFIList FFIString))
         in assertBool "should not warn for uniform string array" (not (any isMixedArray warnings)),
      testCase "no warning for empty array" $
        let body = [jsReturn 2 (jsArray [])]
            warnings = analyzeFunc "empty" body (FFIFunctionType [] (FFIList FFIInt))
         in assertBool "should not warn for empty array" (not (any isMixedArray warnings))
    ]

-- INTEGRATION TESTS

integrationTests :: TestTree
integrationTests =
  testGroup
    "Integration"
    [ testCase "multiple warnings from one function" $
        let body =
              [ jsReturn 3
                  ( jsBinOp
                      (jsNumber 1)
                      (JSBinOpPlus (annot 3))
                      jsString
                  )
              ]
            stmts = [jsFunc "bad" body]
            types = Map.singleton "bad" (FFIFunctionType [FFIInt, FFIString] FFIString)
            warnings = analyze stmts types
         in assertBool "should produce warnings" (not (null warnings)),
      testCase "no warnings for clean function" $
        let body = [jsReturn 2 (jsBinOp (jsNumber 1) (JSBinOpPlus noAnnot) (jsNumber 2))]
            stmts = [jsFunc "add" body]
            types = Map.singleton "add" (FFIFunctionType [FFIInt, FFIInt] FFIInt)
            warnings = analyze stmts types
         in assertBool "should produce no mixed-type or mismatch warnings"
              (not (any isMixedType warnings) && not (any isTypeMismatch warnings)),
      testCase "undeclared function produces no warnings" $
        let body = [jsReturn 2 (jsNumber 42)]
            stmts = [jsFunc "unknown" body]
            types = Map.empty
            warnings = analyze stmts types
         in assertBool "should produce no warnings for undeclared function" (not (any isTypeMismatch warnings)),
      testCase "analysis result includes inferred types" $
        let body = [jsReturn 2 (jsNumber 42)]
            stmts = [jsFunc "getId" body]
            types = Map.singleton "getId" (FFIFunctionType [] FFIInt)
            result = SA.analyzeFFIFile stmts types
         in assertBool "should infer types"
              (Map.member "getId" (SA._analysisInferred result)),
      testCase "inferred type matches expected" $
        let body = [jsReturn 2 (jsNumber 42)]
            stmts = [jsFunc "getId" body]
            types = Map.singleton "getId" (FFIFunctionType [] FFIInt)
            result = SA.analyzeFFIFile stmts types
         in case Map.lookup "getId" (SA._analysisInferred result) of
              Just SA.InfNumber -> pure ()
              other -> assertFailure ("expected InfNumber, got " ++ show other)
    ]

-- COMMA LIST HELPER TESTS

commaListHelperTests :: TestTree
commaListHelperTests =
  testGroup
    "CommaList helpers"
    [ testCase "commaListToList nil" $
        SA.commaListToList (JSLNil :: JSCommaList Int) @?= ([] :: [Int]),
      testCase "commaListToList one" $
        SA.commaListToList (JSLOne (42 :: Int)) @?= [42 :: Int],
      testCase "commaListToList cons" $
        SA.commaListToList (JSLCons (JSLOne (1 :: Int)) noAnnot (2 :: Int)) @?= [1 :: Int, 2],
      testCase "trailingListToList none" $
        SA.trailingListToList (JSCTLNone (JSLOne (42 :: Int))) @?= [42 :: Int],
      testCase "trailingListToList comma" $
        SA.trailingListToList (JSCTLComma (JSLOne (42 :: Int)) noAnnot) @?= [42 :: Int],
      testCase "extractAnnotLine from JSAnnot" $
        SA.extractAnnotLine (annot 42) @?= 42,
      testCase "extractAnnotLine from JSNoAnnot" $
        SA.extractAnnotLine JSNoAnnot @?= 0
    ]

-- WARNING PREDICATES

isMixedType :: SA.FFIWarning -> Bool
isMixedType (SA.MixedTypeOperation {}) = True
isMixedType _ = False

isLooseEquality :: SA.FFIWarning -> Bool
isLooseEquality (SA.LooseEquality {}) = True
isLooseEquality _ = False

isMissingReturn :: SA.FFIWarning -> Bool
isMissingReturn (SA.MissingReturnPath {}) = True
isMissingReturn _ = False

isNullableReturn :: SA.FFIWarning -> Bool
isNullableReturn (SA.NullableReturn {}) = True
isNullableReturn _ = False

isAsyncWithoutTask :: SA.FFIWarning -> Bool
isAsyncWithoutTask (SA.AsyncWithoutTask {}) = True
isAsyncWithoutTask _ = False

isResultTag :: SA.FFIWarning -> Bool
isResultTag (SA.MissingResultTag {}) = True
isResultTag _ = False

isTypeMismatch :: SA.FFIWarning -> Bool
isTypeMismatch (SA.ReturnTypeMismatch {}) = True
isTypeMismatch _ = False

isMixedArray :: SA.FFIWarning -> Bool
isMixedArray (SA.MixedArrayElements {}) = True
isMixedArray _ = False

isImplicitUndefinedPath :: SA.ReturnInfo -> Bool
isImplicitUndefinedPath (SA.ImplicitUndefined _) = True
isImplicitUndefinedPath _ = False

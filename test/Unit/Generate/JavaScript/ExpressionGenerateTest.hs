{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Generate.JavaScript.ExpressionGenerateTest - JS codegen tests for non-arithmetic expressions
--
-- This module provides test coverage for JavaScript code generation of
-- expression variants not covered by ExpressionArithmeticTest.  It
-- exercises the 'generate', 'generateFunction', 'generateField',
-- 'codeToExpr', and 'codeToStmtList' functions from
-- "Generate.JavaScript.Expression".
--
-- Because 'JS.Expr' and 'JS.Stmt' derive only 'Show' (not 'Eq'), all
-- assertions use pattern matching or 'show'-based comparisons.
--
-- == Test Coverage
--
-- * Bool literal generation in Dev and Prod mode
-- * Unit expression: Dev → @_Utils_Tuple0@ ref, Prod → @JS.Int 0@
-- * Chr expression: Dev → @_Utils_chr(s)@ call, Prod → @JS.String@
-- * Str expression: @JS.String@ (no pool entry)
-- * generateFunction arity 1: plain @JS.Function@ (no Fn helper)
-- * generateFunction arity 2–9: @F\<n\>@ helper call
-- * generateFunction arity >9: nested single-arg functions
-- * codeToExpr: JsExpr passes through, JsStmt/JsBlock wrap in IIFE
-- * codeToStmtList: JsExpr wraps in Return, block unwraps
-- * generateField Dev: identity (original name), Prod: uses shortener map
--
-- @since 0.19.1
module Unit.Generate.JavaScript.ExpressionGenerateTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.ByteString.Builder as BB
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Gen
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode

-- | Main test tree for Generate.JavaScript.Expression non-arithmetic tests.
tests :: TestTree
tests = testGroup "Generate.JavaScript.Expression Tests"
  [ boolTests
  , unitTests
  , chrTests
  , strTests
  , generateFunctionTests
  , codeToExprTests
  , codeToStmtListTests
  , generateFieldTests
  ]

-- HELPERS

-- | Render a 'JsName.Name' as a Haskell 'String' for assertions.
nameToString :: JsName.Name -> String
nameToString = LChar8.unpack . BB.toLazyByteString . JsName.toBuilder

-- | Development mode with all flags disabled.
devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

-- | Production mode with an empty field map, empty string pool, and all flags disabled.
prodMode :: Mode.Mode
prodMode = Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty

-- | Production mode with a single field entry mapping @field@ to @short@.
prodModeWithField :: Name.Name -> JsName.Name -> Mode.Mode
prodModeWithField field short =
  Mode.Prod (Map.singleton field short) False False False StringPool.emptyPool Set.empty

-- | Build an 'Opt.Str' from a Haskell 'String'.
mkStr :: String -> Opt.Expr
mkStr s = Opt.Str (Utf8.fromChars s)

-- | Build an 'Opt.Chr' from a single 'Char'.
mkChr :: Char -> Opt.Expr
mkChr c = Opt.Chr (Utf8.fromChars [c])

-- | Convert a 'Gen.Code' to a 'JS.Expr'.
toExpr :: Gen.Code -> JS.Expr
toExpr = Gen.codeToExpr

-- | Convert a 'Gen.Code' to a list of 'JS.Stmt'.
toStmts :: Gen.Code -> [JS.Stmt]
toStmts = Gen.codeToStmtList

-- BOOL TESTS

-- | Test Bool literal generation.
--
-- Both 'Mode.Dev' and 'Mode.Prod' must produce @JS.Bool@; booleans
-- have no mode-specific representation.
boolTests :: TestTree
boolTests = testGroup "Bool Literal Generation"
  [ testCase "Opt.Bool True generates JS.Bool True in Dev mode" $
      case toExpr (Gen.generate devMode (Opt.Bool True)) of
        JS.Bool b -> b @?= True
        other -> assertFailure ("Expected JS.Bool True, got: " ++ show other)

  , testCase "Opt.Bool False generates JS.Bool False in Dev mode" $
      case toExpr (Gen.generate devMode (Opt.Bool False)) of
        JS.Bool b -> b @?= False
        other -> assertFailure ("Expected JS.Bool False, got: " ++ show other)

  , testCase "Opt.Bool True generates JS.Bool True in Prod mode" $
      case toExpr (Gen.generate prodMode (Opt.Bool True)) of
        JS.Bool b -> b @?= True
        other -> assertFailure ("Expected JS.Bool True in Prod, got: " ++ show other)

  , testCase "Opt.Bool False generates JS.Bool False in Prod mode" $
      case toExpr (Gen.generate prodMode (Opt.Bool False)) of
        JS.Bool b -> b @?= False
        other -> assertFailure ("Expected JS.Bool False in Prod, got: " ++ show other)
  ]

-- UNIT TESTS

-- | Test Unit expression generation.
--
-- In Dev mode @Opt.Unit@ becomes a reference to @_Utils_Tuple0@.
-- In Prod mode it collapses to @JS.Int 0@.
unitTests :: TestTree
unitTests = testGroup "Unit Expression Generation"
  [ testCase "Opt.Unit in Dev mode generates JS.Ref to _Utils_Tuple0" $
      case toExpr (Gen.generate devMode Opt.Unit) of
        JS.Ref name -> nameToString name @?= "_Utils_Tuple0"
        other -> assertFailure ("Expected JS.Ref(_Utils_Tuple0), got: " ++ show other)

  , testCase "Opt.Unit in Prod mode generates JS.Int 0" $
      case toExpr (Gen.generate prodMode Opt.Unit) of
        JS.Int n -> n @?= 0
        other -> assertFailure ("Expected JS.Int 0, got: " ++ show other)
  ]

-- CHR TESTS

-- | Test Chr expression generation.
--
-- In Dev mode a character is wrapped in a @_Utils_chr(…)@ call.
-- In Prod mode it is a bare @JS.String@.
chrTests :: TestTree
chrTests = testGroup "Chr Expression Generation"
  [ testCase "Opt.Chr in Dev mode produces a JS.Call" $
      case toExpr (Gen.generate devMode (mkChr 'A')) of
        JS.Call _ _ -> pure ()
        other -> assertFailure ("Expected JS.Call for chr in Dev, got: " ++ show other)

  , testCase "Opt.Chr call in Dev mode targets _Utils_chr" $
      case toExpr (Gen.generate devMode (mkChr 'A')) of
        JS.Call (JS.Ref name) _ -> nameToString name @?= "_Utils_chr"
        other -> assertFailure ("Expected JS.Call(JS.Ref _Utils_chr), got: " ++ show other)

  , testCase "Opt.Chr in Prod mode produces JS.String (no call wrapper)" $
      case toExpr (Gen.generate prodMode (mkChr 'Z')) of
        JS.String _ -> pure ()
        other -> assertFailure ("Expected JS.String in Prod mode, got: " ++ show other)
  ]

-- STR TESTS

-- | Test Str expression generation.
--
-- When the string is not present in the pool, the result must be @JS.String@.
strTests :: TestTree
strTests = testGroup "Str Expression Generation"
  [ testCase "Opt.Str without pool entry generates JS.String in Dev mode" $
      case toExpr (Gen.generate devMode (mkStr "hello")) of
        JS.String _ -> pure ()
        other -> assertFailure ("Expected JS.String in Dev, got: " ++ show other)

  , testCase "Opt.Str without pool entry generates JS.String in Prod mode" $
      case toExpr (Gen.generate prodMode (mkStr "world")) of
        JS.String _ -> pure ()
        other -> assertFailure ("Expected JS.String in Prod, got: " ++ show other)
  ]

-- GENERATE FUNCTION TESTS

-- | Test 'generateFunction' arity behaviour.
--
-- * Arity 1: plain @JS.Function@ with one parameter, no @Fn@ helper.
-- * Arities 2–9: wrapped in @F\<n\>@ helper call.
-- * Arity 10: outermost node is a plain @JS.Function@ (chunked, no @F10@).
generateFunctionTests :: TestTree
generateFunctionTests = testGroup "generateFunction Arity Tests"
  [ testCase "arity 1 produces JS.Function (no Fn helper)" $
      let arg = JsName.fromLocal (Name.fromChars "x")
          body = Gen.JsExpr (JS.Int 42)
          result = toExpr (Gen.generateFunction [arg] body)
      in case result of
           JS.Function Nothing [_] _ -> pure ()
           other -> assertFailure ("Expected bare JS.Function for arity 1, got: " ++ show other)

  , testCase "arity 2 produces F2 helper call" $
      let args = fmap (\c -> JsName.fromLocal (Name.fromChars [c])) "ab"
          body = Gen.JsExpr (JS.Int 0)
          result = toExpr (Gen.generateFunction args body)
      in case result of
           JS.Call (JS.Ref name) _ -> nameToString name @?= "F2"
           other -> assertFailure ("Expected JS.Call F2 for arity 2, got: " ++ show other)

  , testCase "arity 5 produces F5 helper call" $
      let args = fmap (\c -> JsName.fromLocal (Name.fromChars [c])) "abcde"
          body = Gen.JsExpr (JS.Int 0)
          result = toExpr (Gen.generateFunction args body)
      in case result of
           JS.Call (JS.Ref name) _ -> nameToString name @?= "F5"
           other -> assertFailure ("Expected JS.Call F5 for arity 5, got: " ++ show other)

  , testCase "arity 9 produces F9 helper call" $
      let args = fmap (\c -> JsName.fromLocal (Name.fromChars [c])) "abcdefghi"
          body = Gen.JsExpr (JS.Int 0)
          result = toExpr (Gen.generateFunction args body)
      in case result of
           JS.Call (JS.Ref name) _ -> nameToString name @?= "F9"
           other -> assertFailure ("Expected JS.Call F9 for arity 9, got: " ++ show other)

  , testCase "arity 10 produces outermost JS.Function (chunked, no F10)" $
      let args = fmap (\i -> JsName.fromLocal (Name.fromChars ("x" ++ show (i :: Int)))) [1..10]
          body = Gen.JsExpr (JS.Int 0)
          result = toExpr (Gen.generateFunction args body)
      in case result of
           JS.Function Nothing _ _ -> pure ()
           other -> assertFailure ("Expected outermost JS.Function for arity 10, got: " ++ show other)
  ]

-- CODE TO EXPR TESTS

-- | Test 'codeToExpr' normalisation.
--
-- * 'JsExpr' is returned directly.
-- * 'JsStmt' wrapping a 'JS.Return' unwraps the returned expression.
-- * 'JsStmt' wrapping a non-return statement becomes an IIFE.
-- * 'JsBlock' with a single 'JS.Return' unwraps the expression.
-- * 'JsBlock' with multiple statements becomes an IIFE.
codeToExprTests :: TestTree
codeToExprTests = testGroup "codeToExpr Conversions"
  [ testCase "JsExpr passes through as the same expression" $
      case toExpr (Gen.JsExpr (JS.Int 7)) of
        JS.Int n -> n @?= 7
        other -> assertFailure ("Expected JS.Int 7, got: " ++ show other)

  , testCase "JsStmt(Return e) unwraps to e" $
      case toExpr (Gen.JsStmt (JS.Return (JS.Int 3))) of
        JS.Int n -> n @?= 3
        other -> assertFailure ("Expected JS.Int 3 after Return unwrap, got: " ++ show other)

  , testCase "JsStmt(non-return stmt) wraps in IIFE" $
      case toExpr (Gen.JsStmt (JS.Break Nothing)) of
        JS.Call (JS.Function Nothing [] _) [] -> pure ()
        other -> assertFailure ("Expected IIFE for non-return JsStmt, got: " ++ show other)

  , testCase "JsBlock [Return e] unwraps to e" $
      case toExpr (Gen.JsBlock [JS.Return (JS.Bool True)]) of
        JS.Bool b -> b @?= True
        other -> assertFailure ("Expected JS.Bool True after Return unwrap, got: " ++ show other)

  , testCase "JsBlock with multiple stmts wraps in IIFE" $
      case toExpr (Gen.JsBlock [JS.Return (JS.Int 1), JS.Return (JS.Int 2)]) of
        JS.Call (JS.Function Nothing [] _) [] -> pure ()
        other -> assertFailure ("Expected IIFE for multi-stmt JsBlock, got: " ++ show other)
  ]

-- CODE TO STMT LIST TESTS

-- | Test 'codeToStmtList' normalisation.
--
-- * 'JsExpr' wraps the expression in a 'JS.Return'.
-- * 'JsStmt' becomes a single-element list.
-- * 'JsBlock' flattens to its statement list.
-- * An IIFE 'JsExpr' is unwrapped to its inner statements.
codeToStmtListTests :: TestTree
codeToStmtListTests = testGroup "codeToStmtList Conversions"
  [ testCase "JsExpr produces a single Return statement" $
      case toStmts (Gen.JsExpr (JS.Int 5)) of
        [JS.Return (JS.Int n)] -> n @?= 5
        other -> assertFailure ("Expected [Return (Int 5)], got: " ++ show other)

  , testCase "JsStmt produces a singleton list with that statement" $
      case toStmts (Gen.JsStmt (JS.Return (JS.Int 9))) of
        [JS.Return (JS.Int n)] -> n @?= 9
        other -> assertFailure ("Expected [Return (Int 9)], got: " ++ show other)

  , testCase "JsBlock with two statements produces both" $
      case toStmts (Gen.JsBlock [JS.Return (JS.Int 1), JS.Return (JS.Int 2)]) of
        [JS.Return (JS.Int a), JS.Return (JS.Int b)] -> (a, b) @?= (1, 2)
        other -> assertFailure ("Expected [Return 1, Return 2], got: " ++ show other)

  , testCase "IIFE JsExpr is unwrapped to inner statements" $
      let innerStmts = [JS.Return (JS.Bool False)]
          iife = Gen.JsExpr (JS.Call (JS.Function Nothing [] innerStmts) [])
      in case toStmts iife of
           [JS.Return (JS.Bool b)] -> b @?= False
           other -> assertFailure ("Expected inner [Return False] after IIFE unwrap, got: " ++ show other)
  ]

-- GENERATE FIELD TESTS

-- | Test 'generateField' mode behaviour.
--
-- In Dev mode the original field name is emitted verbatim.
-- In Prod mode the minified name from the shortener map is used.
generateFieldTests :: TestTree
generateFieldTests = testGroup "generateField Mode Tests"
  [ testCase "Dev mode preserves original field name" $
      let fieldName = Name.fromChars "myField"
          result = Gen.generateField devMode fieldName
      in nameToString result @?= "myField"

  , testCase "Prod mode returns the minified name from the shortener map" $
      let fieldName = Name.fromChars "myField"
          shortName = JsName.fromInt 0
          mode = prodModeWithField fieldName shortName
          result = Gen.generateField mode fieldName
      in nameToString result @?= nameToString shortName
  ]

module Unit.Parse.ExpressionTest (tests) where

import qualified AST.Source as Src
import qualified Canopy.String as ES
import qualified Data.ByteString.Char8 as C8
import qualified Canopy.Data.Name as Name
import qualified Parse.Expression as Expr
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError
import Test.Tasty
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, testCaseSteps, (@?=))

parseExpr :: String -> Either SyntaxError.Expr Src.Expr
parseExpr s = fst <$> Parse.fromByteString Expr.expression SyntaxError.Start (C8.pack s)

tests :: TestTree
tests =
  testGroup
    "Parse.Expression"
    [ testLiterals,
      testLists,
      testTuples,
      testRecords,
      testAccess,
      testVariablesAndCalls,
      testOperators,
      testOperatorAssociativity,
      testNegation,
      testPrecedenceChain,
      testNestedLambdaLet,
      testIf,
      testLambda,
      testLet,
      caseOfTest,
      caseOfComplex,
      testsNegatives,
      testTemplateLiterals,
      testHoles,
      testAccessorFunctions,
      testNegativeNumbers,
      testChainedFieldAccess,
      testComplexLetBindings,
      testCaseExpressions,
      testMultilineExpressions
    ]

testLiterals :: TestTree
testLiterals =
  testGroup
    "literals"
    [ testCase "int" $ case parseExpr "42" of
        Right (Ann.At _ (Src.Int 42)) -> return ()
        other -> assertFailure ("unexpected: " <> show other),
      testCase "float" $ case parseExpr "3.14" of
        Right (Ann.At _ (Src.Float _)) -> return ()
        _ -> assertFailure "expected Float",
      testCase "string" $ case parseExpr "\"hi\"" of
        Right (Ann.At _ (Src.Str _)) -> return ()
        _ -> assertFailure "expected Str",
      testCase "char" $ case parseExpr "'x'" of
        Right (Ann.At _ (Src.Chr _)) -> return ()
        _ -> assertFailure "expected Chr"
    ]

testLists :: TestTree
testLists = testCase "lists" $ case parseExpr "[1,2,3]" of
  Right (Ann.At _ (Src.List [_, _, _])) -> return ()
  _ -> assertFailure "expected 3-element list"

testTuples :: TestTree
testTuples =
  testGroup
    "tuples"
    [ testCase "unit" $ case parseExpr "()" of
        Right (Ann.At _ Src.Unit) -> return ()
        _ -> assertFailure "expected Unit",
      testCase "pair" $ case parseExpr "(1,2)" of
        Right (Ann.At _ (Src.Tuple _ _ [])) -> return ()
        _ -> assertFailure "expected 2-tuple",
      testCase "triple" $ case parseExpr "(1,2,3)" of
        Right (Ann.At _ (Src.Tuple _ _ [_])) -> return ()
        _ -> assertFailure "expected 3-tuple"
    ]

testPrecedenceChain :: TestTree
testPrecedenceChain = testCase "longer precedence chain" $ case parseExpr "1 + 2 * 3 + 4" of
  Right (Ann.At _ (Src.Binops _ _)) -> return ()
  _ -> assertFailure "expected Binops"

testNestedLambdaLet :: TestTree
testNestedLambdaLet = testCase "nested lambdas and let" $ do
  let src = "let x = \\y -> y in x 2"
  case parseExpr src of
    Right (Ann.At _ (Src.Let _ _)) -> return ()
    other -> assertFailure ("expected Let, got: " <> show other)

testRecords :: TestTree
testRecords =
  testGroup
    "records"
    [ testCase "empty" $ case parseExpr "{}" of
        Right (Ann.At _ (Src.Record [])) -> return ()
        _ -> assertFailure "expected empty record",
      testCase "fields" $ case parseExpr "{ a = 1, b = 2 }" of
        Right (Ann.At _ (Src.Record [(Ann.At _ a, _), (Ann.At _ b, _)])) -> do
          a @?= Name.fromChars "a"
          b @?= Name.fromChars "b"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "update" $ case parseExpr "{ r | a = 1 }" of
        Right (Ann.At _ (Src.Update (Ann.At _ r) [(Ann.At _ field, Src.FieldValue _)])) -> do
          r @?= Name.fromChars "r"
          field @?= Name.fromChars "a"
        _ -> assertFailure "expected record update",
      testCase "nested update" $ case parseExpr "{ r | user { name = 1 } }" of
        Right (Ann.At _ (Src.Update (Ann.At _ r) [(Ann.At _ field, Src.FieldNested [(Ann.At _ sub, Src.FieldValue _)])])) -> do
          r @?= Name.fromChars "r"
          field @?= Name.fromChars "user"
          sub @?= Name.fromChars "name"
        other -> assertFailure ("expected nested record update, got: " <> show other),
      testCase "deeply nested update" $ case parseExpr "{ r | a { b { c = 1 } } }" of
        Right (Ann.At _ (Src.Update _ [(_, Src.FieldNested [(_, Src.FieldNested [(Ann.At _ c, Src.FieldValue _)])])])) ->
          c @?= Name.fromChars "c"
        other -> assertFailure ("expected deeply nested update, got: " <> show other),
      testCase "mixed flat and nested update" $ case parseExpr "{ r | x = 1, y { z = 2 } }" of
        Right (Ann.At _ (Src.Update _ [(Ann.At _ x, Src.FieldValue _), (Ann.At _ y, Src.FieldNested _)])) -> do
          x @?= Name.fromChars "x"
          y @?= Name.fromChars "y"
        other -> assertFailure ("expected mixed update, got: " <> show other)
    ]

testVariablesAndCalls :: TestTree
testVariablesAndCalls = testCase "variables and calls" $ case parseExpr "f x y" of
  Right (Ann.At _ (Src.Call (Ann.At _ (Src.Call (Ann.At _ (Src.Var Src.LowVar _)) [_, _])) [])) -> return ()
  Right (Ann.At _ (Src.Call (Ann.At _ (Src.Var _ _)) [_, _])) -> return ()
  Right (Ann.At _ (Src.Call _ [_, _])) -> return ()
  other -> assertFailure ("unexpected: " <> show other)

testOperators :: TestTree
testOperators = testCase "binops precedence and grouping" $ case parseExpr "1 + 2 * 3" of
  Right (Ann.At _ (Src.Binops _ _)) -> return ()
  _ -> assertFailure "expected Binops"

testAccess :: TestTree
testAccess =
  testGroup
    "access and accessor"
    [ testCase "chained access" $ case parseExpr "obj.a.b" of
        Right (Ann.At _ (Src.Access (Ann.At _ (Src.Access _ (Ann.At _ _))) (Ann.At _ _))) -> return ()
        _ -> assertFailure "expected chained Access",
      testCase "accessor function" $ case parseExpr ".field" of
        Right (Ann.At _ (Src.Accessor _)) -> return ()
        _ -> assertFailure "expected Accessor"
    ]

testOperatorAssociativity :: TestTree
testOperatorAssociativity =
  testGroup
    "associativity"
    [ testCase "left assoc for -" $ case parseExpr "1 - 2 - 3" of
        Right (Ann.At _ (Src.Binops _ _)) -> return ()
        _ -> assertFailure "expected Binops",
      testCase "parentheses override" $ case parseExpr "(1 - 2) - 3" of
        Right (Ann.At _ (Src.Binops _ _)) -> return ()
        _ -> assertFailure "expected Binops"
    ]

testNegation :: TestTree
testNegation =
  testGroup
    "negation"
    [ testCase "unary negation" $ case parseExpr "-x" of
        Right (Ann.At _ (Src.Negate _)) -> return ()
        _ -> assertFailure "expected Negate",
      testCase "negative numbers in ops" $ case parseExpr "-3 * -2" of
        Right (Ann.At _ (Src.Binops _ _)) -> return ()
        _ -> assertFailure "expected Binops"
    ]

testIf :: TestTree
testIf = testCase "if/then/else" $ case parseExpr "if x then 1 else 2" of
  Right (Ann.At _ (Src.If [(_, _)] _)) -> return ()
  _ -> assertFailure "expected If"

testLambda :: TestTree
testLambda = testCase "lambda" $ case parseExpr "\\n -> n" of
  Right (Ann.At _ (Src.Lambda [Ann.At _ (Src.PVar _)] _)) -> return ()
  _ -> assertFailure "expected Lambda"

testLet :: TestTree
testLet = testCase "let/in" $ case parseExpr "let x = 1 in x" of
  Right (Ann.At _ (Src.Let _ _)) -> return ()
  _ -> assertFailure "expected Let"

caseOfTest :: TestTree
caseOfTest = testCaseSteps "case/of" $ \step -> do
  step "parse"
  let src =
        unlines
          [ "case x of",
            "  Just n -> n",
            "  Nothing -> 0"
          ]
  case parseExpr src of
    Right (Ann.At _ (Src.Case _ [(_, _), (_, _)])) -> return ()
    other -> assertFailure ("unexpected: " <> show other)

-- Negative cases
-- Unterminated string should produce a string-related error
-- We only assert that it is a Left value (specific constructor varies by location)
testsNegatives :: TestTree
testsNegatives =
  testGroup
    "errors"
    [ testCase "unterminated string" $ case parseExpr "\"hi" of
        Left (SyntaxError.String {}) -> return ()
        other -> assertFailure ("expected string error, got: " <> show other)
    ]

caseOfComplex :: TestTree
caseOfComplex = testCase "case/of with record pattern" $ do
  let src =
        unlines
          [ "case { a = 1 } of",
            "  { a } -> a",
            "  _ -> 0"
          ]
  case parseExpr src of
    Right (Ann.At _ (Src.Case _ [(_, _), (_, _)])) -> return ()
    other -> assertFailure ("unexpected: " <> show other)

testTemplateLiterals :: TestTree
testTemplateLiterals =
  testGroup
    "template literals"
    [ testCase "simple interpolation" $ case parseExpr "`Hello ${name}!`" of
        Right (Ann.At _ (Src.Interpolation [Src.IStr s1, Src.IExpr _, Src.IStr s2])) -> do
          ES.toChars s1 @?= "Hello "
          ES.toChars s2 @?= "!"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "multiple interpolations" $ case parseExpr "`${a} and ${b}`" of
        Right (Ann.At _ (Src.Interpolation [Src.IExpr _, Src.IStr s, Src.IExpr _])) ->
          ES.toChars s @?= " and "
        other -> assertFailure ("unexpected: " <> show other),
      testCase "plain text only" $ case parseExpr "`just text`" of
        Right (Ann.At _ (Src.Interpolation [Src.IStr s])) ->
          ES.toChars s @?= "just text"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "empty template literal" $ case parseExpr "``" of
        Right (Ann.At _ (Src.Interpolation [])) -> return ()
        other -> assertFailure ("unexpected: " <> show other),
      testCase "escaped dollar sign" $ case parseExpr "`price is \\$100`" of
        Right (Ann.At _ (Src.Interpolation [Src.IStr s])) ->
          ES.toChars s @?= "price is $100"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "escaped backtick" $ case parseExpr "`use \\` for templates`" of
        Right (Ann.At _ (Src.Interpolation [Src.IStr s])) ->
          ES.toChars s @?= "use ` for templates"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "dollar without brace is literal" $ case parseExpr "`costs $5`" of
        Right (Ann.At _ (Src.Interpolation [Src.IStr s])) ->
          ES.toChars s @?= "costs $5"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "expression with function call" $ case parseExpr "`${String.fromInt count} items`" of
        Right (Ann.At _ (Src.Interpolation [Src.IExpr _, Src.IStr s])) ->
          ES.toChars s @?= " items"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "adjacent interpolations" $ case parseExpr "`${a}${b}`" of
        Right (Ann.At _ (Src.Interpolation [Src.IExpr _, Src.IExpr _])) -> return ()
        other -> assertFailure ("unexpected: " <> show other),
      testCase "interpolation only" $ case parseExpr "`${x}`" of
        Right (Ann.At _ (Src.Interpolation [Src.IExpr _])) -> return ()
        other -> assertFailure ("unexpected: " <> show other),
      testCase "old [i| syntax no longer parses as interpolation" $ case parseExpr "[i|hello|]" of
        Right (Ann.At _ (Src.Interpolation _)) ->
          assertFailure "old [i| syntax should not parse as interpolation"
        _ -> return (),
      testCase "escaped backslash" $ case parseExpr "`a\\\\b`" of
        Right (Ann.At _ (Src.Interpolation [Src.IStr s])) ->
          ES.toChars s @?= "a\\b"
        other -> assertFailure ("unexpected: " <> show other),
      testCase "nested template literal" $ case parseExpr "`outer ${`inner`}`" of
        Right (Ann.At _ (Src.Interpolation [Src.IStr s1, Src.IExpr inner])) -> do
          ES.toChars s1 @?= "outer "
          case inner of
            Ann.At _ (Src.Interpolation [Src.IStr s2]) ->
              ES.toChars s2 @?= "inner"
            other -> assertFailure ("expected inner template, got: " <> show other)
        other -> assertFailure ("unexpected: " <> show other),
      testCase "expression with parens" $ case parseExpr "`${(a)}`" of
        Right (Ann.At _ (Src.Interpolation [Src.IExpr _])) -> return ()
        other -> assertFailure ("unexpected: " <> show other),
      testCase "unclosed template literal fails" $ case parseExpr "`hello" of
        Left _ -> return ()
        Right _ -> assertFailure "expected parse error for unclosed template",
      testCase "unclosed interpolation expression fails" $ case parseExpr "`${x`" of
        Left _ -> return ()
        Right _ -> assertFailure "expected parse error for unclosed ${",
      testCase "many segments" $ case parseExpr "`${a}-${b}-${c}`" of
        Right (Ann.At _ (Src.Interpolation segs)) ->
          length segs @?= 5
        other -> assertFailure ("unexpected: " <> show other),
      testCase "if expression inside interpolation" $ case parseExpr "`${if True then x else y}`" of
        Right (Ann.At _ (Src.Interpolation [Src.IExpr (Ann.At _ (Src.If _ _))])) -> return ()
        other -> assertFailure ("unexpected: " <> show other),
      testCase "special chars in literal parts" $ case parseExpr "`<div class=\"foo\">`" of
        Right (Ann.At _ (Src.Interpolation [Src.IStr s])) ->
          assertBool "contains HTML" (not (null (ES.toChars s)))
        other -> assertFailure ("unexpected: " <> show other)
    ]

testHoles :: TestTree
testHoles =
  testGroup
    "holes"
    [ testCase "anonymous hole _ parses to Hole with name _" $ case parseExpr "_" of
        Right (Ann.At _ (Src.Hole n)) -> n @?= Name.fromChars "_"
        other -> assertFailure ("expected Hole, got: " <> show other),
      testCase "named hole _foo parses to Hole with name _foo" $ case parseExpr "_foo" of
        Right (Ann.At _ (Src.Hole n)) -> n @?= Name.fromChars "_foo"
        other -> assertFailure ("expected Hole with name _foo, got: " <> show other),
      testCase "named hole _bar parses to Hole with name _bar" $ case parseExpr "_bar" of
        Right (Ann.At _ (Src.Hole n)) -> n @?= Name.fromChars "_bar"
        other -> assertFailure ("expected Hole with name _bar, got: " <> show other)
    ]

testAccessorFunctions :: TestTree
testAccessorFunctions =
  testGroup
    "accessor functions"
    [ testCase ".name parses to Accessor" $ case parseExpr ".name" of
        Right (Ann.At _ (Src.Accessor n)) -> n @?= Name.fromChars "name"
        other -> assertFailure ("expected Accessor name, got: " <> show other),
      testCase ".age parses to Accessor" $ case parseExpr ".age" of
        Right (Ann.At _ (Src.Accessor n)) -> n @?= Name.fromChars "age"
        other -> assertFailure ("expected Accessor age, got: " <> show other),
      testCase ".x parses to Accessor" $ case parseExpr ".x" of
        Right (Ann.At _ (Src.Accessor n)) -> n @?= Name.fromChars "x"
        other -> assertFailure ("expected Accessor x, got: " <> show other)
    ]

testNegativeNumbers :: TestTree
testNegativeNumbers =
  testGroup
    "negative numbers"
    [ testCase "-42 is Negate wrapping Int 42" $ case parseExpr "-42" of
        Right (Ann.At _ (Src.Negate (Ann.At _ (Src.Int 42)))) -> return ()
        other -> assertFailure ("expected Negate(Int 42), got: " <> show other),
      testCase "-3.14 is Negate wrapping Float" $ case parseExpr "-3.14" of
        Right (Ann.At _ (Src.Negate (Ann.At _ (Src.Float _)))) -> return ()
        other -> assertFailure ("expected Negate(Float), got: " <> show other),
      testCase "-0 is Negate wrapping Int 0" $ case parseExpr "-0" of
        Right (Ann.At _ (Src.Negate (Ann.At _ (Src.Int 0)))) -> return ()
        other -> assertFailure ("expected Negate(Int 0), got: " <> show other)
    ]

testChainedFieldAccess :: TestTree
testChainedFieldAccess =
  testGroup
    "chained field access"
    [ testCase "a.b produces Access" $ case parseExpr "a.b" of
        Right (Ann.At _ (Src.Access _ (Ann.At _ n))) -> n @?= Name.fromChars "b"
        other -> assertFailure ("expected Access .b, got: " <> show other),
      testCase "a.b.c produces nested Access" $ case parseExpr "a.b.c" of
        Right (Ann.At _ (Src.Access (Ann.At _ (Src.Access _ _)) (Ann.At _ n))) ->
          n @?= Name.fromChars "c"
        other -> assertFailure ("expected nested Access .c, got: " <> show other),
      testCase "a.b.c.d produces three-level nested Access" $ case parseExpr "a.b.c.d" of
        Right (Ann.At _ (Src.Access (Ann.At _ (Src.Access (Ann.At _ (Src.Access _ _)) _)) (Ann.At _ n))) ->
          n @?= Name.fromChars "d"
        other -> assertFailure ("expected three-level Access .d, got: " <> show other)
    ]

testComplexLetBindings :: TestTree
testComplexLetBindings =
  testGroup
    "complex let bindings"
    [ testCase "let with multiple bindings" $ case parseExpr multiLet of
        Right (Ann.At _ (Src.Let _ _)) -> return ()
        other -> assertFailure ("expected Let, got: " <> show other),
      testCase "nested let" $ case parseExpr nestedLet of
        Right (Ann.At _ (Src.Let _ _)) -> return ()
        other -> assertFailure ("expected outer Let, got: " <> show other)
    ]
  where
    multiLet = "let\n    x = 1\n    y = 2\n in\n x"
    nestedLet = "let x = let y = 1 in y in x"

testCaseExpressions :: TestTree
testCaseExpressions =
  testGroup
    "case expressions"
    [ testCase "case with three branches" $ case parseExpr threeWayCase of
        Right (Ann.At _ (Src.Case _ [(_, _), (_, _), (_, _)])) -> return ()
        other -> assertFailure ("expected Case with 3 branches, got: " <> show other),
      testCase "case with constructor pattern" $ case parseExpr ctorCase of
        Right (Ann.At _ (Src.Case _ [(_, _), (_, _)])) -> return ()
        other -> assertFailure ("expected Case with 2 branches, got: " <> show other)
    ]
  where
    threeWayCase =
      unlines
        [ "case x of",
          "  1 -> \"one\"",
          "  2 -> \"two\"",
          "  _ -> \"other\""
        ]
    ctorCase =
      unlines
        [ "case mx of",
          "  Just v -> v",
          "  Nothing -> 0"
        ]

testMultilineExpressions :: TestTree
testMultilineExpressions =
  testGroup
    "multiline expressions"
    [ testCase "if/then/else across lines" $ case parseExpr "if True\n then 1\n else 2" of
        Right (Ann.At _ (Src.If [(_, _)] _)) -> return ()
        other -> assertFailure ("expected If, got: " <> show other),
      testCase "inline list with multiple elements" $ case parseExpr "[1, 2, 3, 4]" of
        Right (Ann.At _ (Src.List [_, _, _, _])) -> return ()
        other -> assertFailure ("expected 4-element list, got: " <> show other),
      testCase "inline record with multiple fields" $ case parseExpr "{ a = 1, b = 2, c = 3 }" of
        Right (Ann.At _ (Src.Record [(_, _), (_, _), (_, _)])) -> return ()
        other -> assertFailure ("expected 3-field record, got: " <> show other)
    ]

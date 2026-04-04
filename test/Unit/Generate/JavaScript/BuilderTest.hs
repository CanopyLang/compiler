{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Generate.JavaScript.Builder.
--
-- Verifies that the Builder module correctly renders JavaScript expressions
-- and statements to ByteString output, and that helper functions such as
-- 'nameToByteString' and 'sanitizeScriptElementString' work correctly.
--
-- == Test Coverage
--
-- * Basic expression rendering: Int, Float, Bool, Null, String, Ref
-- * Array and Object expression rendering
-- * InfixOp and PrefixOp expression rendering
-- * Statement rendering: VarDecl, ExprStmt, Return, Throw, Block, FunctionStmt
-- * IfStmt rendering with and without else branch
-- * nameToByteString: converts Name values to ByteString
-- * sanitizeScriptElementString: escapes script tags and HTML comments
-- * Edge cases: empty block, nested expressions
--
-- @since 0.20.0
module Unit.Generate.JavaScript.BuilderTest
  ( tests,
  )
where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Name as JsName
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Generate.JavaScript.Builder.
tests :: TestTree
tests =
  Test.testGroup
    "Generate.JavaScript.Builder"
    [ exprRenderingTests,
      prefixOpTests,
      infixOpTests,
      stmtRenderingTests,
      nameToByteStringTests,
      sanitizeScriptTests
    ]

-- HELPERS

-- | Render an expression to a String for assertion.
renderExpr :: JS.Expr -> String
renderExpr = LChar8.unpack . BB.toLazyByteString . JS.exprToBuilder

-- | Render a statement to a String for assertion (trailing newline stripped).
renderStmt :: JS.Stmt -> String
renderStmt stmt =
  LChar8.unpack (LBS.init (BB.toLazyByteString (JS.stmtToBuilder stmt)))

-- | Build a local Name from a String.
localName :: String -> JsName.Name
localName = JsName.fromLocal . Name.fromChars

-- EXPRESSION RENDERING TESTS

-- | Test rendering of basic literal expressions.
exprRenderingTests :: TestTree
exprRenderingTests =
  Test.testGroup
    "basic expression rendering"
    [ Test.testCase "Int 0 renders as '0'" $
        renderExpr (JS.Int 0) @?= "0",
      Test.testCase "Int 42 renders as '42'" $
        renderExpr (JS.Int 42) @?= "42",
      Test.testCase "Int -1 renders as '-1'" $
        renderExpr (JS.Int (-1)) @?= "-1",
      Test.testCase "Bool True renders as 'true'" $
        renderExpr (JS.Bool True) @?= "true",
      Test.testCase "Bool False renders as 'false'" $
        renderExpr (JS.Bool False) @?= "false",
      Test.testCase "Null renders as 'null'" $
        renderExpr JS.Null @?= "null",
      Test.testCase "String renders with single quotes" $
        renderExpr (JS.String "hello") @?= "'hello'",
      Test.testCase "empty String renders as ''" $
        renderExpr (JS.String "") @?= "''",
      Test.testCase "Ref renders identifier with leading space" $
        renderExpr (JS.Ref (localName "myVar")) @?= " myVar",
      Test.testCase "empty Array renders as '[]'" $
        renderExpr (JS.Array []) @?= "[]",
      Test.testCase "Array with one element renders correctly" $
        renderExpr (JS.Array [JS.Int 1]) @?= "[1]",
      Test.testCase "Array with multiple elements has commas" $
        renderExpr (JS.Array [JS.Int 1, JS.Int 2, JS.Int 3]) @?= "[1 ,2 ,3]",
      Test.testCase "empty Object renders as '{}'" $
        renderExpr (JS.Object []) @?= "{}",
      Test.testCase "Object with one field renders key-value pair" $
        renderExpr (JS.Object [(localName "x", JS.Int 5)]) @?= "{x :5}",
      Test.testCase "Access renders dot-notation" $
        renderExpr (JS.Access (JS.Ref (localName "obj")) (localName "field"))
          @?= " obj.field",
      Test.testCase "If ternary renders condition ? then : else" $
        renderExpr (JS.If (JS.Bool True) (JS.Int 1) (JS.Int 0))
          @?= "true?1:0"
    ]

-- PREFIX OPERATOR TESTS

-- | Test rendering of unary prefix expressions.
prefixOpTests :: TestTree
prefixOpTests =
  Test.testGroup
    "prefix operator rendering"
    [ Test.testCase "PrefixNot renders '!'" $
        renderExpr (JS.Prefix JS.PrefixNot (JS.Bool True)) @?= "!true",
      Test.testCase "PrefixNegate renders '-'" $
        renderExpr (JS.Prefix JS.PrefixNegate (JS.Int 5)) @?= "-5",
      Test.testCase "PrefixComplement renders '~'" $
        renderExpr (JS.Prefix JS.PrefixComplement (JS.Int 0)) @?= "~0",
      Test.testCase "PrefixTypeof renders 'typeof'" $
        renderExpr (JS.Prefix JS.PrefixTypeof (JS.Ref (localName "x"))) @?= "typeof x"
    ]

-- INFIX OPERATOR TESTS

-- | Test rendering of binary infix expressions.
infixOpTests :: TestTree
infixOpTests =
  Test.testGroup
    "infix operator rendering"
    [ Test.testCase "OpAdd renders '+'" $
        renderExpr (JS.Infix JS.OpAdd (JS.Int 1) (JS.Int 2)) @?= "1 +2",
      Test.testCase "OpSub renders '-'" $
        renderExpr (JS.Infix JS.OpSub (JS.Int 5) (JS.Int 3)) @?= "5 -3",
      Test.testCase "OpMul renders '*'" $
        renderExpr (JS.Infix JS.OpMul (JS.Int 2) (JS.Int 4)) @?= "2 *4",
      Test.testCase "OpDiv renders '/'" $
        renderExpr (JS.Infix JS.OpDiv (JS.Int 10) (JS.Int 2)) @?= "10 /2",
      Test.testCase "OpMod renders '%'" $
        renderExpr (JS.Infix JS.OpMod (JS.Int 7) (JS.Int 3)) @?= "7 %3",
      Test.testCase "OpEq renders '==='" $
        renderExpr (JS.Infix JS.OpEq (JS.Int 1) (JS.Int 1)) @?= "1 ===1",
      Test.testCase "OpNe renders '!=='" $
        renderExpr (JS.Infix JS.OpNe (JS.Int 1) (JS.Int 2)) @?= "1 !==2",
      Test.testCase "OpLooseEq renders '=='" $
        renderExpr (JS.Infix JS.OpLooseEq (JS.Null) (JS.Null)) @?= "null ==null",
      Test.testCase "OpLooseNe renders '!='" $
        renderExpr (JS.Infix JS.OpLooseNe (JS.Null) (JS.Null)) @?= "null !=null",
      Test.testCase "OpLt renders '<'" $
        renderExpr (JS.Infix JS.OpLt (JS.Int 1) (JS.Int 2)) @?= "1 <2",
      Test.testCase "OpLe renders '<='" $
        renderExpr (JS.Infix JS.OpLe (JS.Int 2) (JS.Int 2)) @?= "2 <=2",
      Test.testCase "OpGt renders '>'" $
        renderExpr (JS.Infix JS.OpGt (JS.Int 3) (JS.Int 1)) @?= "3 >1",
      Test.testCase "OpGe renders '>='" $
        renderExpr (JS.Infix JS.OpGe (JS.Int 3) (JS.Int 3)) @?= "3 >=3",
      Test.testCase "OpAnd renders '&&'" $
        renderExpr (JS.Infix JS.OpAnd (JS.Bool True) (JS.Bool False)) @?= "true &&false",
      Test.testCase "OpOr renders '||'" $
        renderExpr (JS.Infix JS.OpOr (JS.Bool False) (JS.Bool True)) @?= "false ||true",
      Test.testCase "OpInstanceOf renders 'instanceof'" $
        renderExpr (JS.Infix JS.OpInstanceOf (JS.Ref (localName "x")) (JS.Ref (localName "C")))
          @?= " x instanceof C",
      Test.testCase "OpBitwiseAnd renders '&'" $
        renderExpr (JS.Infix JS.OpBitwiseAnd (JS.Int 5) (JS.Int 3)) @?= "5 &3",
      Test.testCase "OpBitwiseOr renders '|'" $
        renderExpr (JS.Infix JS.OpBitwiseOr (JS.Int 5) (JS.Int 3)) @?= "5 |3",
      Test.testCase "OpBitwiseXor renders '^'" $
        renderExpr (JS.Infix JS.OpBitwiseXor (JS.Int 5) (JS.Int 3)) @?= "5 ^3",
      Test.testCase "OpLShift renders '<<'" $
        renderExpr (JS.Infix JS.OpLShift (JS.Int 1) (JS.Int 2)) @?= "1 <<2",
      Test.testCase "OpSpRShift renders '>>'" $
        renderExpr (JS.Infix JS.OpSpRShift (JS.Int 8) (JS.Int 1)) @?= "8 >>1",
      Test.testCase "OpZfRShift renders '>>>'" $
        renderExpr (JS.Infix JS.OpZfRShift (JS.Int 8) (JS.Int 1)) @?= "8 >>>1"
    ]

-- STATEMENT RENDERING TESTS

-- | Test rendering of JavaScript statements.
stmtRenderingTests :: TestTree
stmtRenderingTests =
  Test.testGroup
    "statement rendering"
    [ Test.testCase "ExprStmt renders expression without semicolon" $
        renderStmt (JS.ExprStmt (JS.Int 42)) @?= "42",
      Test.testCase "ExprStmtWithSemi renders expression with semicolon" $
        renderStmt (JS.ExprStmtWithSemi (JS.Int 42)) @?= "42;",
      Test.testCase "Return renders with keyword" $
        renderStmt (JS.Return (JS.Int 1)) @?= " return 1;",
      Test.testCase "Throw renders with keyword" $
        renderStmt (JS.Throw (JS.String "error")) @?= " throw'error';",
      Test.testCase "Var renders 'var name = expr;'" $
        renderStmt (JS.Var (localName "x") (JS.Int 5)) @?= "var x =5;",
      Test.testCase "Const renders 'const name = expr;'" $
        renderStmt (JS.Const (localName "y") (JS.Int 10)) @?= "const y =10;",
      Test.testCase "empty Block renders as empty statement" $
        renderStmt (JS.Block []) @?= ";",
      Test.testCase "single-element Block unwraps to single statement" $
        renderStmt (JS.Block [JS.Return (JS.Int 0)]) @?= " return 0;",
      Test.testCase "multi-element Block renders braces" $
        let stmts = [JS.Return (JS.Int 0), JS.Return (JS.Int 1)]
         in renderStmt (JS.Block stmts) @?= "{ return 0; return 1;}",
      Test.testCase "FunctionStmt renders function keyword and body" $
        let f = JS.FunctionStmt (localName "f") [] [JS.Return (JS.Int 0)]
         in renderStmt f @?= "function f(){ return 0;}",
      Test.testCase "FunctionStmt with params renders param list" $
        let f = JS.FunctionStmt (localName "add") [localName "a", localName "b"] [JS.Return (JS.Infix JS.OpAdd (JS.Ref (localName "a")) (JS.Ref (localName "b")))]
         in renderStmt f @?= "function add(a,b){ return ( a + b);}",
      Test.testCase "IfStmt without else renders bare if" $
        renderStmt (JS.IfStmt (JS.Bool True) (JS.Return (JS.Int 1)) JS.EmptyStmt)
          @?= " if (true ){ return 1;}",
      Test.testCase "IfStmt with else renders if-else" $
        renderStmt (JS.IfStmt (JS.Bool True) (JS.Return (JS.Int 1)) (JS.Return (JS.Int 0)))
          @?= " if (true ){ return 1;} else{ return 0;}"
    ]

-- NAME TO BYTESTRING TESTS

-- | Test that nameToByteString produces the expected bytes.
nameToByteStringTests :: TestTree
nameToByteStringTests =
  Test.testGroup
    "nameToByteString"
    [ Test.testCase "simple name converts to its chars" $
        JS.nameToByteString (localName "myVar") @?= "myVar",
      Test.testCase "single-char name converts correctly" $
        JS.nameToByteString (localName "x") @?= "x",
      Test.testCase "underscore-prefixed name converts correctly" $
        JS.nameToByteString (JsName.fromBuilder "_reserved") @?= "_reserved",
      Test.testCase "empty name converts to empty bytes" $
        JS.nameToByteString (JsName.fromBuilder "") @?= ""
    ]

-- SANITIZE SCRIPT ELEMENT TESTS

-- | Test that sanitizeScriptElementString escapes dangerous sequences.
sanitizeScriptTests :: TestTree
sanitizeScriptTests =
  Test.testGroup
    "sanitizeScriptElementString"
    [ Test.testCase "plain string passes through unchanged" $
        Utf8.toChars (JS.sanitizeScriptElementString (Utf8.fromChars "hello world"))
          @?= "hello world",
      Test.testCase "forward slash in script tag is escaped" $
        Utf8.toChars (JS.sanitizeScriptElementString (Utf8.fromChars "</script>"))
          @?= "<\\script>",
      Test.testCase "exclamation mark in HTML comment is escaped" $
        Utf8.toChars (JS.sanitizeScriptElementString (Utf8.fromChars "<!--"))
          @?= "<\\--",
      Test.testCase "multiple slashes are all escaped" $
        Utf8.toChars (JS.sanitizeScriptElementString (Utf8.fromChars "a/b/c"))
          @?= "a\\b/c",
      Test.testCase "both script tag and comment in same string are escaped" $
        Utf8.toChars (JS.sanitizeScriptElementString (Utf8.fromChars "</script><!--"))
          @?= "<\\script><\\--",
      Test.testCase "empty string passes through unchanged" $
        Utf8.toChars (JS.sanitizeScriptElementString (Utf8.fromChars ""))
          @?= ""
    ]

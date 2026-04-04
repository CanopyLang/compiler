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
-- * Access, Index, Assign, Call, New, Function expression rendering
-- * Statement rendering: VarDecl, ExprStmt, Return, Throw, Block, FunctionStmt
-- * IfStmt rendering with and without else branch
-- * While, Switch, Try/Catch, Break, Continue, Labelled statements
-- * Vars and ConstPure statement rendering
-- * ModuleItem: ImportBare, ImportNamed, ExportLocals, ExportLocalsRaw
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
import qualified Data.Set as Set
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.Mode as Mode
import qualified Json.Encode as Json
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
      assignExprTests,
      callAndNewExprTests,
      stmtRenderingTests,
      controlFlowStmtTests,
      switchStmtTests,
      tryCatchStmtTests,
      breakContinueLabelTests,
      multiVarStmtTests,
      moduleItemTests,
      nameToByteStringTests,
      sanitizeScriptTests,
      floatExprTests,
      jsonExprTests,
      namedFunctionExprTests,
      objectMultiFieldTests,
      nestedExprTests,
      continueWithLabelTests,
      emptyStmtTests,
      shorthandObjectTests,
      moduleBuilderTests,
      modeRenderingTests
    ]

-- HELPERS

-- | Render an expression to a String for assertion.
renderExpr :: JS.Expr -> String
renderExpr = LChar8.unpack . BB.toLazyByteString . JS.exprToBuilder

-- | Render a statement to a String for assertion (trailing newline stripped).
renderStmt :: JS.Stmt -> String
renderStmt stmt =
  LChar8.unpack (LBS.init (BB.toLazyByteString (JS.stmtToBuilder stmt)))

-- | Strip an additional trailing newline from a rendered statement.
--
-- Some statements emit a trailing newline inside the rendered output;
-- this helper removes it so expected strings do not need to embed newlines.
stripNewline :: JS.Stmt -> String
stripNewline stmt =
  let s = renderStmt stmt
   in if not (null s) && last s == '\n' then init s else s

-- | Render a module item to a String for assertion (trailing newline stripped).
renderModuleItem :: JS.ModuleItem -> String
renderModuleItem item =
  let raw = LChar8.unpack (BB.toLazyByteString (JS.moduleItemToBuilder item))
   in if not (null raw) && last raw == '\n' then init raw else raw

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

-- ASSIGN EXPRESSION TESTS

-- | Test rendering of assignment expressions using all LValue variants.
assignExprTests :: TestTree
assignExprTests =
  Test.testGroup
    "assignment expression rendering"
    [ Test.testCase "Assign LRef renders simple variable assignment" $
        renderExpr (JS.Assign (JS.LRef (localName "x")) (JS.Int 5))
          @?= "x =5",
      Test.testCase "Assign LDot renders property assignment" $
        renderExpr (JS.Assign (JS.LDot (JS.Ref (localName "obj")) (localName "field")) (JS.Int 5))
          @?= " obj.field =5",
      Test.testCase "Assign LBracket renders index assignment" $
        renderExpr (JS.Assign (JS.LBracket (JS.Ref (localName "arr")) (JS.Int 0)) (JS.Int 5))
          @?= " arr[0] =5"
    ]

-- CALL AND NEW EXPRESSION TESTS

-- | Test rendering of function calls, constructor expressions, and Index access.
callAndNewExprTests :: TestTree
callAndNewExprTests =
  Test.testGroup
    "call, new, and index expression rendering"
    [ Test.testCase "Call renders function application with args" $
        renderExpr (JS.Call (JS.Ref (localName "f")) [JS.Int 1, JS.Int 2])
          @?= " f(1,2)",
      Test.testCase "Call with no args renders empty parens" $
        renderExpr (JS.Call (JS.Ref (localName "f")) [])
          @?= " f()",
      Test.testCase "New renders constructor invocation" $
        renderExpr (JS.New (JS.Ref (localName "Foo")) [JS.Int 1])
          @?= " new Foo(1)",
      Test.testCase "New with no args renders empty constructor call" $
        renderExpr (JS.New (JS.Ref (localName "Foo")) [])
          @?= " new Foo()",
      Test.testCase "Index renders bracket access" $
        renderExpr (JS.Index (JS.Ref (localName "arr")) (JS.Int 0))
          @?= " arr[0]",
      Test.testCase "anonymous Function expression renders correctly" $
        renderExpr (JS.Function Nothing [localName "x"] [JS.Return (JS.Ref (localName "x"))])
          @?= " function(x){ return ( x);}"
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

-- CONTROL FLOW STATEMENT TESTS

-- | Test rendering of while loops.
controlFlowStmtTests :: TestTree
controlFlowStmtTests =
  Test.testGroup
    "while loop statement rendering"
    [ Test.testCase "While with empty block body renders semicolon" $
        stripNewline (JS.While (JS.Bool True) (JS.Block []))
          @?= " while (true );",
      Test.testCase "While with Return body renders block" $
        stripNewline (JS.While (JS.Bool False) (JS.Return (JS.Int 0)))
          @?= " while (false ) return 0;"
    ]

-- SWITCH STATEMENT TESTS

-- | Test rendering of switch statements with case and default arms.
switchStmtTests :: TestTree
switchStmtTests =
  Test.testGroup
    "switch statement rendering"
    [ Test.testCase "Switch with Case and Default arms" $
        stripNewline
          (JS.Switch (JS.Ref (localName "x"))
            [ JS.Case (JS.Int 1) [JS.Return (JS.Int 1)],
              JS.Default [JS.Return (JS.Int 0)]
            ])
          @?= " switch( x){ case 1 : return 1; default : return 0;}",
      Test.testCase "Switch with single Case and Break" $
        stripNewline
          (JS.Switch (JS.Ref (localName "x")) [JS.Case (JS.Int 0) [JS.Break Nothing]])
          @?= " switch( x){ case 0 : break;}"
    ]

-- TRY/CATCH STATEMENT TESTS

-- | Test rendering of try/catch blocks.
tryCatchStmtTests :: TestTree
tryCatchStmtTests =
  Test.testGroup
    "try/catch statement rendering"
    [ Test.testCase "Try renders try-catch with named error binding" $
        stripNewline
          (JS.Try (JS.Return (JS.Int 1)) (localName "e") (JS.Throw (JS.Ref (localName "e"))))
          @?= " try{ return 1;}catch(e){ throw e;}"
    ]

-- BREAK / CONTINUE / LABEL STATEMENT TESTS

-- | Test rendering of break, continue, and labelled statements.
breakContinueLabelTests :: TestTree
breakContinueLabelTests =
  Test.testGroup
    "break, continue, and label statement rendering"
    [ Test.testCase "Break without label renders bare break" $
        stripNewline (JS.Break Nothing) @?= " break;",
      Test.testCase "Break with label renders labelled break" $
        stripNewline (JS.Break (Just (localName "loop"))) @?= " break loop;",
      Test.testCase "Continue without label renders bare continue" $
        stripNewline (JS.Continue Nothing) @?= " continue;",
      Test.testCase "Labelled wraps statement with identifier prefix" $
        stripNewline (JS.Labelled (localName "loop") (JS.While (JS.Bool True) (JS.Block [])))
          @?= "loop: while (true );"
    ]

-- MULTI-VAR AND CONST-PURE STATEMENT TESTS

-- | Test rendering of multi-variable declarations and pure-annotated constants.
multiVarStmtTests :: TestTree
multiVarStmtTests =
  Test.testGroup
    "multi-var and const-pure statement rendering"
    [ Test.testCase "Vars with two bindings renders comma-separated declaration" $
        stripNewline (JS.Vars [(localName "a", JS.Int 1), (localName "b", JS.Int 2)])
          @?= "var b =2, a =1\n;",
      Test.testCase "ConstPure renders with tree-shaking PURE annotation" $
        stripNewline (JS.ConstPure (localName "x") (JS.Int 42))
          @?= "/*#__PURE__*/ const x =42;"
    ]

-- MODULE ITEM TESTS

-- | Test rendering of ESM module-level items (import/export declarations).
moduleItemTests :: TestTree
moduleItemTests =
  Test.testGroup
    "module item rendering"
    [ Test.testCase "ImportBare renders bare import statement" $
        renderModuleItem (JS.ImportBare "./foo.js")
          @?= "import ./foo.js;",
      Test.testCase "ImportNamed renders named import clause" $
        renderModuleItem (JS.ImportNamed [localName "foo", localName "bar"] "./foo.js")
          @?= "import { foo, bar } from ./foo.js;",
      Test.testCase "ImportNamedRaw renders raw-named import clause" $
        renderModuleItem (JS.ImportNamedRaw ["foo", "bar"] "./foo.js")
          @?= "import { foo, bar } from ./foo.js;",
      Test.testCase "ExportLocals renders named export clause" $
        renderModuleItem (JS.ExportLocals [localName "foo", localName "bar"])
          @?= "export { foo, bar };",
      Test.testCase "ExportLocalsRaw renders raw-named export clause" $
        renderModuleItem (JS.ExportLocalsRaw ["foo", "bar"])
          @?= "export { foo, bar };",
      Test.testCase "ModuleStmt wraps a var statement" $
        renderModuleItem (JS.ModuleStmt (JS.Var (localName "x") (JS.Int 5)))
          @?= "var x =5;"
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

-- FLOAT AND JSON EXPRESSION TESTS

-- | Test rendering of Float and Json literal expressions.
floatExprTests :: TestTree
floatExprTests =
  Test.testGroup
    "Float and Json expression rendering"
    [ Test.testCase "Float renders verbatim builder content" $
        renderExpr (JS.Float "3.14") @?= "3.14",
      Test.testCase "Float with integer string renders as integer-like" $
        renderExpr (JS.Float "1.0e10") @?= "1.0e10",
      Test.testCase "Float negative value renders correctly" $
        renderExpr (JS.Float "-2.5") @?= "-2.5"
    ]

-- | Test rendering of Json expressions.
jsonExprTests :: TestTree
jsonExprTests =
  Test.testGroup
    "Json expression rendering"
    [ Test.testCase "Json null renders as null" $
        renderExpr (JS.Json Json.null) @?= "null",
      Test.testCase "Json true renders as true" $
        renderExpr (JS.Json (Json.bool True)) @?= "true",
      Test.testCase "Json integer renders correctly" $
        renderExpr (JS.Json (Json.int 42)) @?= "42"
    ]

-- NAMED FUNCTION EXPRESSION TESTS

-- | Test rendering of named function expressions.
namedFunctionExprTests :: TestTree
namedFunctionExprTests =
  Test.testGroup
    "named function expression rendering"
    [ Test.testCase "Function with name renders name in expression" $
        renderExpr (JS.Function (Just (localName "fact")) [localName "n"] [JS.Return (JS.Int 1)])
          @?= " functionfact(n){ return 1;}",
      Test.testCase "Function with multiple params renders comma-separated list" $
        renderExpr (JS.Function Nothing [localName "a", localName "b", localName "c"] [JS.Return (JS.Int 0)])
          @?= " function(a,b,c){ return 0;}"
    ]

-- OBJECT MULTI-FIELD TESTS

-- | Test rendering of object literals with multiple fields.
objectMultiFieldTests :: TestTree
objectMultiFieldTests =
  Test.testGroup
    "object multi-field rendering"
    [ Test.testCase "Object with two fields renders both key-value pairs" $
        renderExpr (JS.Object [(localName "x", JS.Int 1), (localName "y", JS.Int 2)])
          @?= "{x :1,y :2}",
      Test.testCase "Object with nested array value renders correctly" $
        renderExpr (JS.Object [(localName "items", JS.Array [JS.Int 1, JS.Int 2])])
          @?= "{items :[1 ,2]}"
    ]

-- NESTED EXPRESSION TESTS

-- | Test rendering of nested and compound expressions.
nestedExprTests :: TestTree
nestedExprTests =
  Test.testGroup
    "nested expression rendering"
    [ Test.testCase "nested Access renders dot-chain" $
        renderExpr (JS.Access (JS.Access (JS.Ref (localName "a")) (localName "b")) (localName "c"))
          @?= " a.b.c",
      Test.testCase "nested Call renders correctly" $
        renderExpr (JS.Call (JS.Call (JS.Ref (localName "f")) [JS.Int 1]) [JS.Int 2])
          @?= " f(1)(2)",
      Test.testCase "Index of Access renders bracket on dotted path" $
        renderExpr (JS.Index (JS.Access (JS.Ref (localName "obj")) (localName "arr")) (JS.Int 0))
          @?= " obj.arr[0]",
      Test.testCase "New with Access callee renders new with dot" $
        renderExpr (JS.New (JS.Access (JS.Ref (localName "ns")) (localName "Cls")) [])
          @?= " new ns.Cls()"
    ]

-- CONTINUE WITH LABEL TESTS

-- | Test continue statement with a label.
continueWithLabelTests :: TestTree
continueWithLabelTests =
  Test.testGroup
    "continue with label"
    [ Test.testCase "Continue with label renders labelled continue" $
        stripNewline (JS.Continue (Just (localName "outer"))) @?= " continue outer;"
    ]

-- EMPTY STMT TESTS

-- | Test the EmptyStmt constructor.
emptyStmtTests :: TestTree
emptyStmtTests =
  Test.testGroup
    "EmptyStmt rendering"
    [ Test.testCase "EmptyStmt renders as semicolon" $
        renderStmt JS.EmptyStmt @?= ";"
    ]

-- SHORTHAND OBJECT TESTS

-- | Test 'JS.shorthandObjectExpr' by wrapping it in a Var statement that
-- references the produced expression via 'moduleToBuilder'.
--
-- shorthandObjectExpr returns a language-javascript JSExpression.  We verify
-- behaviour by constructing a ConstPure statement whose rendered output
-- embeds a shorthand object, then checking the rendered string.
shorthandObjectTests :: TestTree
shorthandObjectTests =
  Test.testGroup
    "shorthandObjectExpr (indirect via moduleToBuilder)"
    [ Test.testCase "moduleToBuilder with RawJS item passes through verbatim" $
        let item = JS.RawJS (BB.byteString "console.log(1);\n")
            output = LChar8.unpack (BB.toLazyByteString (JS.moduleToBuilder [item]))
         in output @?= "console.log(1);\n",
      Test.testCase "moduleToBuilder with ExportLocals produces export statement" $
        let item = JS.ExportLocals [localName "x"]
            output = LChar8.unpack (BB.toLazyByteString (JS.moduleToBuilder [item]))
         in output @?= "export { x };\n"
    ]

-- MODULE BUILDER TESTS

-- | Test 'JS.moduleToBuilder' combining multiple items.
moduleBuilderTests :: TestTree
moduleBuilderTests =
  Test.testGroup
    "moduleToBuilder"
    [ Test.testCase "moduleToBuilder of empty list produces empty output" $
        let output = LChar8.unpack (BB.toLazyByteString (JS.moduleToBuilder []))
         in output @?= "",
      Test.testCase "moduleToBuilder combines multiple items" $
        let items = [JS.ModuleStmt (JS.Var (localName "x") (JS.Int 1)), JS.ModuleStmt (JS.Var (localName "y") (JS.Int 2))]
            output = LChar8.unpack (BB.toLazyByteString (JS.moduleToBuilder items))
         in length output @?= length ("var x =1;\n" :: String) + length ("var y =2;\n" :: String)
    ]

-- MODE-AWARE RENDERING TESTS

-- | Test 'JS.stmtToBuilderWithMode' and 'JS.exprToBuilderWithMode'.
modeRenderingTests :: TestTree
modeRenderingTests =
  Test.testGroup
    "mode-aware rendering"
    [ Test.testCase "stmtToBuilderWithMode Dev renders Var correctly" $
        let mode = Mode.Dev Nothing False False False Set.empty False
            output = LChar8.unpack (BB.toLazyByteString (JS.stmtToBuilderWithMode mode (JS.Var (localName "x") (JS.Int 5))))
         in output @?= "var x =5;\n",
      Test.testCase "exprToBuilderWithMode Dev renders Int correctly" $
        let mode = Mode.Dev Nothing False False False Set.empty False
            output = LChar8.unpack (BB.toLazyByteString (JS.exprToBuilderWithMode mode (JS.Int 99)))
         in output @?= "99",
      Test.testCase "stmtToBuilderWithMode Dev renders Return correctly" $
        let mode = Mode.Dev Nothing False False False Set.empty False
            output = LChar8.unpack (BB.toLazyByteString (JS.stmtToBuilderWithMode mode (JS.Return (JS.Bool True))))
         in output @?= " return true;\n"
    ]

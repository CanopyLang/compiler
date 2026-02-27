
-- | Tests for JavaScript expression generation.
--
-- Validates that the Expression module correctly converts optimized AST
-- expressions into JavaScript AST nodes. Tests cover literal generation,
-- Code chunk conversions (codeToExpr, codeToStmtList), function wrapping
-- with F-helpers, constructor generation, and field generation in Dev mode.
--
-- @since 0.19.2
module Unit.Generate.ExpressionTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Canopy.Data.Index as Index
import Canopy.Data.Name (Name)
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import qualified Canopy.Data.Utf8 as Utf8
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.Mode as Mode
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Expression"
    [ codeToExprTests,
      codeToStmtListTests,
      generateLiteralTests,
      generateVarLocalTests,
      generateFunctionTests,
      generateFieldTests,
      generateCtorTests
    ]

-- HELPERS

devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False Set.empty

nameStr :: String -> Name
nameStr = Name.fromChars

jsNameToString :: JsName.Name -> String
jsNameToString = LChar8.unpack . BB.toLazyByteString . JsName.toBuilder

showExpr :: JS.Expr -> String
showExpr = show

showStmt :: JS.Stmt -> String
showStmt = show

-- CODE TO EXPR TESTS

codeToExprTests :: TestTree
codeToExprTests =
  testGroup
    "codeToExpr"
    [ testCase "JsExpr wrapping passes expression through" $
        showExpr (Expr.codeToExpr (Expr.JsExpr (JS.Int 42)))
          @?= showExpr (JS.Int 42),
      testCase "JsStmt with Return unwraps the expression" $
        showExpr (Expr.codeToExpr (Expr.JsStmt (JS.Return (JS.Int 7))))
          @?= showExpr (JS.Int 7),
      testCase "JsStmt with non-Return wraps in IIFE" $
        let stmt = JS.Var (JsName.fromLocal (nameStr "x")) (JS.Int 1)
            result = Expr.codeToExpr (Expr.JsStmt stmt)
        in showExpr result
             @?= "Call (Function Nothing [] [Var (Name {toBuilder = \"x\"}) (Int 1)]) []",
      testCase "JsBlock with single Return unwraps the expression" $
        showExpr (Expr.codeToExpr (Expr.JsBlock [JS.Return (JS.Bool True)]))
          @?= showExpr (JS.Bool True),
      testCase "JsBlock with multiple stmts wraps in IIFE" $
        let stmts = [JS.Var (JsName.fromLocal (nameStr "a")) (JS.Int 1), JS.Return (JS.Int 2)]
            result = Expr.codeToExpr (Expr.JsBlock stmts)
        in showExpr result
             @?= "Call (Function Nothing [] [Var (Name {toBuilder = \"a\"}) (Int 1),Return (Int 2)]) []"
    ]

-- CODE TO STMT LIST TESTS

codeToStmtListTests :: TestTree
codeToStmtListTests =
  testGroup
    "codeToStmtList"
    [ testCase "JsExpr with simple value becomes Return statement" $
        let result = Expr.codeToStmtList (Expr.JsExpr (JS.Int 5))
        in do
          length result @?= 1
          showStmt (head result) @?= "Return (Int 5)",
      testCase "JsStmt passes through as single-element list" $
        let stmt = JS.Return (JS.Bool False)
            result = Expr.codeToStmtList (Expr.JsStmt stmt)
        in [showStmt stmt] @?= fmap showStmt result,
      testCase "JsBlock flattens nested blocks" $
        let stmts = [JS.Block [JS.Return (JS.Int 1)]]
            result = Expr.codeToStmtList (Expr.JsBlock stmts)
        in length result @?= 1
    ]

-- GENERATE LITERAL TESTS

generateLiteralTests :: TestTree
generateLiteralTests =
  testGroup
    "generate literals"
    [ testCase "Bool True generates JS.Bool True" $
        showExpr (Expr.codeToExpr (Expr.generate devMode (Opt.Bool True)))
          @?= showExpr (JS.Bool True),
      testCase "Bool False generates JS.Bool False" $
        showExpr (Expr.codeToExpr (Expr.generate devMode (Opt.Bool False)))
          @?= showExpr (JS.Bool False),
      testCase "Int 42 generates JS.Int 42" $
        showExpr (Expr.codeToExpr (Expr.generate devMode (Opt.Int 42)))
          @?= showExpr (JS.Int 42),
      testCase "Int 0 generates JS.Int 0" $
        showExpr (Expr.codeToExpr (Expr.generate devMode (Opt.Int 0)))
          @?= showExpr (JS.Int 0),
      testCase "Int -1 generates JS.Int -1" $
        showExpr (Expr.codeToExpr (Expr.generate devMode (Opt.Int (-1))))
          @?= showExpr (JS.Int (-1)),
      testCase "Str generates JS.String with correct content" $
        let strExpr = Expr.codeToExpr (Expr.generate devMode (Opt.Str (Utf8.fromChars "hello")))
        in showExpr strExpr @?= "String \"hello\""
    ]

-- GENERATE VAR LOCAL TESTS

generateVarLocalTests :: TestTree
generateVarLocalTests =
  testGroup
    "generate VarLocal"
    [ testCase "VarLocal generates JS.Ref with local name" $
        let result = Expr.codeToExpr (Expr.generate devMode (Opt.VarLocal (nameStr "myVar")))
        in showExpr result @?= "Ref (Name {toBuilder = \"myVar\"})",
      testCase "VarLocal with reserved word gets escaped" $
        let result = Expr.codeToExpr (Expr.generate devMode (Opt.VarLocal (nameStr "var")))
            rendered = LChar8.unpack (BB.toLazyByteString (JS.exprToBuilder result))
        in rendered @?= " _var"
    ]

-- GENERATE FUNCTION TESTS

generateFunctionTests :: TestTree
generateFunctionTests =
  testGroup
    "generateFunction"
    [ testCase "single-arg function produces plain JS function" $
        let args = [JsName.fromLocal (nameStr "x")]
            body = Expr.JsExpr (JS.Ref (JsName.fromLocal (nameStr "x")))
            result = Expr.codeToExpr (Expr.generateFunction args body)
        in showExpr result
             @?= "Function Nothing [Name {toBuilder = \"x\"}] [Return (Ref (Name {toBuilder = \"x\"}))]",
      testCase "two-arg function uses F2 helper" $
        let args = [JsName.fromLocal (nameStr "a"), JsName.fromLocal (nameStr "b")]
            body = Expr.JsExpr (JS.Ref (JsName.fromLocal (nameStr "a")))
            result = Expr.codeToExpr (Expr.generateFunction args body)
            rendered = LChar8.unpack (BB.toLazyByteString (JS.exprToBuilder result))
        in rendered @?= " F2( function(a,b){ return ( a);})",
      testCase "nine-arg function uses F9 helper" $
        let argNames = fmap (\c -> JsName.fromLocal (nameStr [c])) ['a' .. 'i']
            body = Expr.JsExpr (JS.Int 0)
            result = Expr.codeToExpr (Expr.generateFunction argNames body)
            rendered = LChar8.unpack (BB.toLazyByteString (JS.exprToBuilder result))
        in rendered @?= " F9( function(a,b,c,d,e,f,g,h,i){ return 0;})"
    ]

-- GENERATE FIELD TESTS

generateFieldTests :: TestTree
generateFieldTests =
  testGroup
    "generateField"
    [ testCase "Dev mode field uses original name" $
        jsNameToString (Expr.generateField devMode (nameStr "name"))
          @?= "name",
      testCase "Dev mode field with multi-word name" $
        jsNameToString (Expr.generateField devMode (nameStr "firstName"))
          @?= "firstName"
    ]

-- GENERATE CTOR TESTS

generateCtorTests :: TestTree
generateCtorTests =
  testGroup
    "generateCtor"
    [ testCase "zero-arity ctor in Dev mode produces object with tag" $
        let home = ModuleName.Canonical Pkg.core (nameStr "Maybe")
            global = Opt.Global home (nameStr "Nothing")
            result = Expr.codeToExpr (Expr.generateCtor devMode global Index.first 0)
            rendered = LChar8.unpack (BB.toLazyByteString (JS.exprToBuilder result))
        in rendered @?= "{$ :'Nothing'}",
      testCase "arity-1 ctor in Dev mode produces function returning tagged object" $
        let home = ModuleName.Canonical Pkg.core (nameStr "Maybe")
            global = Opt.Global home (nameStr "Just")
            result = Expr.codeToExpr (Expr.generateCtor devMode global Index.first 1)
            rendered = LChar8.unpack (BB.toLazyByteString (JS.exprToBuilder result))
        in rendered @?= " function(a){ return ({a : a,$ :'Just'});}"
    ]

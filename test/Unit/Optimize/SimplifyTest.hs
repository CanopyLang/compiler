{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for the Optimize.Simplify module.
--
-- This module provides comprehensive tests for the post-optimization
-- simplification passes, covering boolean simplification, identity
-- elimination, string concatenation folding, and dead binding removal.
--
-- == Test Coverage
--
-- * Boolean constant propagation in @if@ expressions
-- * Boolean operator short-circuit simplification (@&&@, @||@)
-- * Double negation elimination (@not (not x)@)
-- * Identity function elimination (@identity x@)
-- * String literal concatenation folding
-- * Empty string append elimination
-- * Dead let-binding elimination for pure expressions
-- * Preservation of non-simplifiable expressions
--
-- @since 0.19.2
module Unit.Optimize.SimplifyTest
  ( tests,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package
import qualified Optimize.Simplify as Simplify
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Optimize.Simplify.
tests :: TestTree
tests =
  Test.testGroup
    "Optimize.Simplify Tests"
    [ booleanIfTests,
      booleanOperatorTests,
      identityTests,
      doubleNegationTests,
      stringFoldingTests,
      deadBindingTests,
      caseRootBindingTests,
      preservationTests,
      nestedSimplificationTests
    ]

-- BOOLEAN IF SIMPLIFICATION

-- | Test boolean constant propagation in if-expressions.
booleanIfTests :: TestTree
booleanIfTests =
  Test.testGroup
    "Boolean If Simplification"
    [ Test.testCase "if True then a else b => a" $
        assertExprEq
          (varLocal "a")
          (Simplify.simplify (Opt.If [(Opt.Bool True, varLocal "a")] (varLocal "b"))),
      Test.testCase "if False then a else b => b" $
        assertExprEq
          (varLocal "b")
          (Simplify.simplify (Opt.If [(Opt.Bool False, varLocal "a")] (varLocal "b"))),
      Test.testCase "if c then True else False => c" $
        assertExprEq
          (varLocal "c")
          (Simplify.simplify (Opt.If [(varLocal "c", Opt.Bool True)] (Opt.Bool False))),
      Test.testCase "if c then False else True => not c" $
        let result = Simplify.simplify (Opt.If [(varLocal "c", Opt.Bool False)] (Opt.Bool True))
         in assertExprEq (mkNotCall (varLocal "c")) result,
      Test.testCase "multi-branch if not simplified" $
        let input =
              Opt.If
                [ (varLocal "a", Opt.Int 1),
                  (varLocal "b", Opt.Int 2)
                ]
                (Opt.Int 3)
         in assertExprEq input (Simplify.simplify input)
    ]

-- BOOLEAN OPERATOR SIMPLIFICATION

-- | Test boolean operator short-circuit evaluation.
booleanOperatorTests :: TestTree
booleanOperatorTests =
  Test.testGroup
    "Boolean Operator Simplification"
    [ Test.testCase "True && x => x" $
        assertExprEq
          (varLocal "x")
          (Simplify.simplify (mkAndCall (Opt.Bool True) (varLocal "x"))),
      Test.testCase "x && True => x" $
        assertExprEq
          (varLocal "x")
          (Simplify.simplify (mkAndCall (varLocal "x") (Opt.Bool True))),
      Test.testCase "False && x => False" $
        assertExprEq
          (Opt.Bool False)
          (Simplify.simplify (mkAndCall (Opt.Bool False) (varLocal "x"))),
      Test.testCase "x && False => False" $
        assertExprEq
          (Opt.Bool False)
          (Simplify.simplify (mkAndCall (varLocal "x") (Opt.Bool False))),
      Test.testCase "True || x => True" $
        assertExprEq
          (Opt.Bool True)
          (Simplify.simplify (mkOrCall (Opt.Bool True) (varLocal "x"))),
      Test.testCase "x || True => True" $
        assertExprEq
          (Opt.Bool True)
          (Simplify.simplify (mkOrCall (varLocal "x") (Opt.Bool True))),
      Test.testCase "False || x => x" $
        assertExprEq
          (varLocal "x")
          (Simplify.simplify (mkOrCall (Opt.Bool False) (varLocal "x"))),
      Test.testCase "x || False => x" $
        assertExprEq
          (varLocal "x")
          (Simplify.simplify (mkOrCall (varLocal "x") (Opt.Bool False)))
    ]

-- IDENTITY ELIMINATION

-- | Test identity function removal.
identityTests :: TestTree
identityTests =
  Test.testGroup
    "Identity Elimination"
    [ Test.testCase "identity x => x" $
        assertExprEq
          (varLocal "x")
          (Simplify.simplify (mkIdentityCall (varLocal "x"))),
      Test.testCase "identity (Int 42) => Int 42" $
        assertExprEq
          (Opt.Int 42)
          (Simplify.simplify (mkIdentityCall (Opt.Int 42))),
      Test.testCase "identity (Str hello) => Str hello" $
        assertExprEq
          (Opt.Str (Utf8.fromChars "hello"))
          (Simplify.simplify (mkIdentityCall (Opt.Str (Utf8.fromChars "hello"))))
    ]

-- DOUBLE NEGATION ELIMINATION

-- | Test not (not x) => x simplification.
doubleNegationTests :: TestTree
doubleNegationTests =
  Test.testGroup
    "Double Negation Elimination"
    [ Test.testCase "not (not x) => x" $
        assertExprEq
          (varLocal "x")
          (Simplify.simplify (mkNotCall (mkNotCall (varLocal "x")))),
      Test.testCase "not (not True) => True" $
        assertExprEq
          (Opt.Bool True)
          (Simplify.simplify (mkNotCall (mkNotCall (Opt.Bool True)))),
      Test.testCase "single not is preserved" $
        assertExprEq
          (mkNotCall (varLocal "x"))
          (Simplify.simplify (mkNotCall (varLocal "x")))
    ]

-- STRING FOLDING

-- | Test string concatenation folding.
stringFoldingTests :: TestTree
stringFoldingTests =
  Test.testGroup
    "String Concatenation Folding"
    [ Test.testCase "\"a\" ++ \"b\" => \"ab\"" $
        assertExprEq
          (Opt.Str (Utf8.fromChars "ab"))
          (Simplify.simplify (mkAppendCall (Opt.Str (Utf8.fromChars "a")) (Opt.Str (Utf8.fromChars "b")))),
      Test.testCase "\"\" ++ x => x" $
        assertExprEq
          (varLocal "x")
          (Simplify.simplify (mkAppendCall (Opt.Str Utf8.empty) (varLocal "x"))),
      Test.testCase "x ++ \"\" => x" $
        assertExprEq
          (varLocal "x")
          (Simplify.simplify (mkAppendCall (varLocal "x") (Opt.Str Utf8.empty))),
      Test.testCase "\"hello\" ++ \" \" ++ \"world\" folds stepwise" $
        let step1 = Simplify.simplify (mkAppendCall (Opt.Str (Utf8.fromChars "hello")) (Opt.Str (Utf8.fromChars " ")))
            step2 = Simplify.simplify (mkAppendCall step1 (Opt.Str (Utf8.fromChars "world")))
         in assertExprEq (Opt.Str (Utf8.fromChars "hello world")) step2,
      Test.testCase "non-literal append preserved" $
        let input = mkAppendCall (varLocal "x") (varLocal "y")
         in assertExprEq input (Simplify.simplify input)
    ]

-- DEAD BINDING ELIMINATION

-- | Test removal of unused pure let-bindings.
deadBindingTests :: TestTree
deadBindingTests =
  Test.testGroup
    "Dead Binding Elimination"
    [ Test.testCase "unused pure Int binding eliminated" $
        let unused = Name.fromChars "unused"
            body = varLocal "result"
         in assertExprEq
              body
              (Simplify.simplify (Opt.Let (Opt.Def unused (Opt.Int 42)) body)),
      Test.testCase "unused pure Str binding eliminated" $
        let unused = Name.fromChars "unused"
            body = Opt.Int 1
         in assertExprEq
              body
              (Simplify.simplify (Opt.Let (Opt.Def unused (Opt.Str (Utf8.fromChars "hello"))) body)),
      Test.testCase "used binding preserved" $
        let varName = Name.fromChars "x"
            binding = Opt.Def varName (Opt.Int 42)
            body = Opt.VarLocal varName
            input = Opt.Let binding body
         in assertExprEq input (Simplify.simplify input),
      Test.testCase "binding with side-effect preserved" $
        let unused = Name.fromChars "unused"
            effectful = Opt.Call (varLocal "sideEffect") [Opt.Int 1]
            body = Opt.Int 0
            input = Opt.Let (Opt.Def unused effectful) body
         in assertExprEq input (Simplify.simplify input),
      Test.testCase "TailDef binding preserved" $
        let defName = Name.fromChars "loop"
            body = varLocal "result"
            input = Opt.Let (Opt.TailDef defName [Name.fromChars "n"] (varLocal "n")) body
         in assertExprEq input (Simplify.simplify input)
    ]

-- CASE ROOT/LABEL BINDING TESTS

-- | Test that let-bindings referenced by Case root/label fields are preserved.
--
-- Regression tests for the bug where @nameUsedIn@ did not inspect the
-- @root@ and @label@ 'Name' fields of 'Opt.Case', causing dead-binding
-- elimination to incorrectly remove bindings used as Case roots (e.g.
-- tuple case expressions).
caseRootBindingTests :: TestTree
caseRootBindingTests =
  Test.testGroup
    "Case Root Binding Preservation"
    [ Test.testCase "let-binding used as Case root is preserved" $
        let x = Name.fromChars "x"
            lbl = Name.fromChars "lbl"
            binding = Opt.Def x (Opt.Tuple (varLocal "a") (varLocal "b") Nothing)
            body = Opt.Case lbl x (Opt.Leaf (Opt.Inline (varLocal "a"))) []
            input = Opt.Let binding body
         in assertExprEq input (Simplify.simplify input),
      Test.testCase "let-binding used as Case label is preserved" $
        let lbl = Name.fromChars "lbl"
            root = Name.fromChars "root"
            binding = Opt.Def lbl (Opt.Tuple (varLocal "a") (varLocal "b") Nothing)
            body = Opt.Case lbl root (Opt.Leaf (Opt.Inline (varLocal "a"))) []
            input = Opt.Let binding body
         in assertExprEq input (Simplify.simplify input),
      Test.testCase "let-binding unused by Case is eliminated" $
        let unused = Name.fromChars "unused"
            lbl = Name.fromChars "lbl"
            root = Name.fromChars "root"
            binding = Opt.Def unused (Opt.Int 42)
            body = Opt.Case lbl root (Opt.Leaf (Opt.Inline (varLocal "a"))) []
         in assertExprEq body (Simplify.simplify (Opt.Let binding body)),
      Test.testCase "pure tuple let-binding used as Case root is preserved" $
        let v0 = Name.fromChars "_v0"
            binding = Opt.Def v0 (Opt.Tuple (varLocal "a") (varLocal "b") Nothing)
            body = Opt.Case v0 v0 (Opt.Leaf (Opt.Inline (varLocal "a"))) []
            input = Opt.Let binding body
         in assertExprEq input (Simplify.simplify input)
    ]

-- PRESERVATION TESTS

-- | Test that non-simplifiable expressions pass through unchanged.
preservationTests :: TestTree
preservationTests =
  Test.testGroup
    "Expression Preservation"
    [ Test.testCase "Int literal preserved" $
        assertExprEq (Opt.Int 42) (Simplify.simplify (Opt.Int 42)),
      Test.testCase "Bool literal preserved" $
        assertExprEq (Opt.Bool True) (Simplify.simplify (Opt.Bool True)),
      Test.testCase "Str literal preserved" $
        let s = Opt.Str (Utf8.fromChars "test")
         in assertExprEq s (Simplify.simplify s),
      Test.testCase "VarLocal preserved" $
        assertExprEq (varLocal "x") (Simplify.simplify (varLocal "x")),
      Test.testCase "arbitrary Call preserved" $
        let input = Opt.Call (varLocal "f") [Opt.Int 1, Opt.Int 2]
         in assertExprEq input (Simplify.simplify input),
      Test.testCase "Unit preserved" $
        assertExprEq Opt.Unit (Simplify.simplify Opt.Unit)
    ]

-- NESTED SIMPLIFICATION

-- | Test that simplification propagates through nested structures.
nestedSimplificationTests :: TestTree
nestedSimplificationTests =
  Test.testGroup
    "Nested Simplification"
    [ Test.testCase "simplifies inside Function body" $
        let body = Opt.If [(Opt.Bool True, Opt.Int 1)] (Opt.Int 2)
            input = Opt.Function [Name.fromChars "x"] body
         in assertExprEq
              (Opt.Function [Name.fromChars "x"] (Opt.Int 1))
              (Simplify.simplify input),
      Test.testCase "simplifies inside Let body" $
        let binding = Opt.Def (Name.fromChars "x") (Opt.Int 1)
            body = Opt.If [(Opt.Bool True, varLocal "x")] (Opt.Int 0)
            input = Opt.Let binding body
         in assertExprEq
              (Opt.Let binding (varLocal "x"))
              (Simplify.simplify input),
      Test.testCase "simplifies inside Let definition" $
        let binding = Opt.Def (Name.fromChars "x") (Opt.If [(Opt.Bool True, Opt.Int 42)] (Opt.Int 0))
            body = varLocal "x"
            input = Opt.Let binding body
         in assertExprEq
              (Opt.Let (Opt.Def (Name.fromChars "x") (Opt.Int 42)) body)
              (Simplify.simplify input),
      Test.testCase "simplifies inside Call arguments" $
        let arg = Opt.If [(Opt.Bool True, Opt.Int 1)] (Opt.Int 2)
            input = Opt.Call (varLocal "f") [arg]
         in assertExprEq
              (Opt.Call (varLocal "f") [Opt.Int 1])
              (Simplify.simplify input),
      Test.testCase "chain: identity applied to if-simplified expr" $
        let ifExpr = Opt.If [(Opt.Bool True, Opt.Int 42)] (Opt.Int 0)
            input = mkIdentityCall ifExpr
         in assertExprEq (Opt.Int 42) (Simplify.simplify input)
    ]

-- HELPERS

-- | Create a local variable reference.
varLocal :: [Char] -> Opt.Expr
varLocal name = Opt.VarLocal (Name.fromChars name)

-- | Create a Basics.and call.
mkAndCall :: Opt.Expr -> Opt.Expr -> Opt.Expr
mkAndCall l r =
  Opt.Call (Opt.VarGlobal (Opt.Global ModuleName.basics Name.and_)) [l, r]

-- | Create a Basics.or call.
mkOrCall :: Opt.Expr -> Opt.Expr -> Opt.Expr
mkOrCall l r =
  Opt.Call (Opt.VarGlobal (Opt.Global ModuleName.basics Name.or_)) [l, r]

-- | Create a Basics.not call.
mkNotCall :: Opt.Expr -> Opt.Expr
mkNotCall x =
  Opt.Call (Opt.VarGlobal (Opt.Global ModuleName.basics Name.not_)) [x]

-- | Create a Basics.identity call.
mkIdentityCall :: Opt.Expr -> Opt.Expr
mkIdentityCall x =
  Opt.Call (Opt.VarGlobal (Opt.Global ModuleName.basics Name.identity)) [x]

-- | Create a Basics.append call.
mkAppendCall :: Opt.Expr -> Opt.Expr -> Opt.Expr
mkAppendCall l r =
  Opt.Call (Opt.VarGlobal (Opt.Global ModuleName.basics Name.append)) [l, r]

-- | Basics module name.
-- (Re-exported from ModuleName for convenience.)

-- | Assert equality of two Opt.Expr values via Show.
--
-- Opt.Expr does not derive Eq, so we compare string representations
-- to verify structural equality.
assertExprEq :: Opt.Expr -> Opt.Expr -> Test.Assertion
assertExprEq expected actual =
  Test.assertEqual "expression equality" (show expected) (show actual)

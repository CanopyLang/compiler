{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Tests for JavaScript expression code generation — coverage-instrumented
-- and tail-recursive paths plus the main entry-point generator.
--
-- This module focuses on the functions not covered by
-- "Unit.Generate.ExpressionTest" or "Unit.Generate.CoverageTest":
--
--   * 'Generate.JavaScript.Expression.generateMain' — all four 'Opt.Main'
--     variants (Static, Dynamic, TestMain, BrowserTestMain)
--   * 'Generate.JavaScript.Expression.generateTailDefExpr' — JS structure
--     with labeled while-loops and F-helper selection
--   * 'Generate.JavaScript.Expression.generateCovTailDefExpr' — tail def
--     with coverage instrumentation injected into the body
--   * 'Generate.JavaScript.Expression.generateCov' — rendered JS code
--     output for leaf, function, and if-branch expressions
--
-- "Unit.Generate.CoverageTest" already tests the counter-increment semantics
-- of 'generateCov'; this module tests the actual @rendered@ JavaScript text.
--
-- @since 0.19.2
module Unit.Generate.JavaScript.ExpressionGenTest (tests) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import Canopy.Data.Name (Name)
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Test.Tasty
import Test.Tasty.HUnit

-- | Root test tree.
tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Expression (gen)"
    [ generateMainTests
    , generateTailDefExprTests
    , generateCovTailDefExprTests
    , generateCovCodeTests
    ]

-- HELPERS

devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

devModeWithCoverage :: Mode.Mode
devModeWithCoverage = Mode.Dev Nothing False False False Set.empty True

prodMode :: Mode.Mode
prodMode =
  Mode.Prod
    Map.empty
    False
    False
    False
    StringPool.emptyPool
    Set.empty
    Map.empty

nameStr :: String -> Name
nameStr = Name.fromChars

-- | Render a 'JS.Expr' to its final JavaScript text.
renderExpr :: JS.Expr -> String
renderExpr = LChar8.unpack . BB.toLazyByteString . JS.exprToBuilder

-- | Show the Haskell constructor tree for a 'JS.Expr'.
showExpr :: JS.Expr -> String
showExpr = show

-- | Module home used throughout.
mainHome :: ModuleName.Canonical
mainHome = ModuleName.Canonical Pkg.core (nameStr "Main")

-- | A simple leaf expression for use as function bodies.
leafExpr :: Opt.Expr
leafExpr = Opt.Int 1

-- | A single-argument function expression.
funcExpr :: Opt.Expr
funcExpr = Opt.Function [nameStr "x"] leafExpr

-- GENERATE MAIN TESTS

-- 'generateMain' dispatches on each 'Opt.Main' variant to produce the
-- appropriate runtime bootstrap call.  Rendered JS output is verified
-- because these are pure, fully-specified transformations.

generateMainTests :: TestTree
generateMainTests =
  testGroup
    "generateMain"
    [ testCase "Static produces _VirtualDom_init call chain with four calls" $
        renderExpr (Expr.generateMain devMode mainHome Opt.Static)
          @?= " _VirtualDom_init($canopy$core$Main$main)(0)(0)",
      testCase "TestMain produces IIFE returning _testMain field" $
        renderExpr (Expr.generateMain devMode mainHome Opt.TestMain)
          @?= " function(){ return ({_testMain : $canopy$core$Main$main});}",
      testCase "BrowserTestMain produces IIFE returning _browserTestMain field" $
        renderExpr (Expr.generateMain devMode mainHome Opt.BrowserTestMain)
          @?= " function(){ return ({_browserTestMain : $canopy$core$Main$main});}",
      testCase "Dynamic in dev mode with no interfaces uses JS Int 0 as metadata" $
        let main = Opt.Dynamic Can.TUnit Can.TUnit (Opt.Int 0)
         in renderExpr (Expr.generateMain devMode mainHome main)
              @?= " $canopy$core$Main$main(0)(0)",
      testCase "Dynamic in prod mode uses JS Int 0 as metadata" $
        let main = Opt.Dynamic Can.TUnit Can.TUnit (Opt.Int 0)
         in renderExpr (Expr.generateMain prodMode mainHome main)
              @?= " $canopy$core$Main$main(0)(0)"
    ]

-- GENERATE TAIL DEF EXPR TESTS

-- 'generateTailDefExpr' builds the JS for a tail-recursive function
-- definition.  Functions with 1 arg get a plain JS function with a labeled
-- while loop.  Functions with 2..9 args get an F2..F9 helper wrapper.
-- Zero-arg functions produce just the labelled while statement.
--
-- The Haskell Show representation of 'JS.Expr' is used here instead of
-- rendered JS because the exact whitespace from the language-javascript
-- pretty-printer for nested blocks is complex to predict without execution,
-- while the Show output is deterministic from the AST.

generateTailDefExprTests :: TestTree
generateTailDefExprTests =
  testGroup
    "generateTailDefExpr"
    [ testCase "one-arg tail def produces plain function with labeled while (no F-helper)" $
        showExpr
          (Expr.generateTailDefExpr devMode (nameStr "loop") [nameStr "x"] leafExpr)
          @?= "Function Nothing [Name {toBuilder = \"x\"}]"
            <> " [Labelled (Name {toBuilder = \"loop\"})"
            <> " (While (Bool True)"
            <> " (Block [Return (Int 1),EmptyStmt]))]",
      testCase "zero-arg tail def passes through body unchanged (no label wrapper)" $
        showExpr
          (Expr.generateTailDefExpr devMode (nameStr "run") [] leafExpr)
          @?= "Int 1",
      testCase "two-arg tail def uses F2 helper (funcHelpers covers 2..9)" $
        showExpr
          (Expr.generateTailDefExpr
            devMode
            (nameStr "go")
            [nameStr "acc", nameStr "xs"]
            leafExpr)
          @?= "Call (Ref (Name {toBuilder = \"F2\"}))"
            <> " [Function Nothing"
            <> " [Name {toBuilder = \"acc\"},Name {toBuilder = \"xs\"}]"
            <> " [Labelled (Name {toBuilder = \"go\"})"
            <> " (While (Bool True)"
            <> " (Block [Return (Int 1),EmptyStmt]))]]"
    ]

-- GENERATE COV TAIL DEF EXPR TESTS

-- 'generateCovTailDefExpr' is like 'generateTailDefExpr' but threads a
-- coverage counter through the body.  For a leaf body (no coverage points)
-- the output is identical to the plain tail def.  For a function body, the
-- coverage counter is embedded into the generated __cov() call inside the
-- function.

generateCovTailDefExprTests :: TestTree
generateCovTailDefExprTests =
  testGroup
    "generateCovTailDefExpr"
    [ testCase "leaf body with counter 0 matches plain tail def" $
        showExpr
          (Expr.generateCovTailDefExpr
            devModeWithCoverage
            0
            (nameStr "loop")
            [nameStr "x"]
            leafExpr)
          @?= showExpr
            (Expr.generateTailDefExpr devMode (nameStr "loop") [nameStr "x"] leafExpr),
      testCase "two-arg leaf body uses F2 helper (same as plain tail def)" $
        showExpr
          (Expr.generateCovTailDefExpr
            devModeWithCoverage
            0
            (nameStr "go")
            [nameStr "acc", nameStr "xs"]
            leafExpr)
          @?= showExpr
            (Expr.generateTailDefExpr
              devMode
              (nameStr "go")
              [nameStr "acc", nameStr "xs"]
              leafExpr),
      testCase "function body counter 0 inserts ExprStmtWithSemi __cov(0) in inner function" $
        showExpr
          (Expr.generateCovTailDefExpr
            devModeWithCoverage
            0
            (nameStr "f")
            [nameStr "n"]
            funcExpr)
          @?= "Function Nothing [Name {toBuilder = \"n\"}]"
            <> " [Labelled (Name {toBuilder = \"f\"})"
            <> " (While (Bool True)"
            <> " (Block [Return"
            <> " (Function Nothing [Name {toBuilder = \"x\"}]"
            <> " [ExprStmtWithSemi (Call (Ref (Name {toBuilder = \"__cov\"}))"
            <> " [Int 0]),Return (Int 1)]),EmptyStmt]))]"
    ]

-- GENERATE COV CODE TESTS

-- 'generateCov' with coverage mode enabled inserts @__cov(N)@ calls at
-- function entry points and branch sites.  This group tests the rendered
-- JavaScript text rather than the counter value (which is tested in
-- "Unit.Generate.CoverageTest").

generateCovCodeTests :: TestTree
generateCovCodeTests =
  testGroup
    "generateCov (code output)"
    [ testCase "leaf expr renders identically with and without coverage" $
        let (covCode, _) = Expr.generateCov devModeWithCoverage 0 leafExpr
            plainCode = Expr.generate devMode leafExpr
         in renderExpr (Expr.codeToExpr covCode)
              @?= renderExpr (Expr.codeToExpr plainCode),
      testCase "function expr inserts __cov(0) at start of body" $
        let (covCode, _) = Expr.generateCov devModeWithCoverage 0 funcExpr
         in renderExpr (Expr.codeToExpr covCode)
              @?= " function(x){ __cov(0); return 1;}",
      testCase "function expr with base counter 5 inserts __cov(5)" $
        let (covCode, _) = Expr.generateCov devModeWithCoverage 5 funcExpr
         in renderExpr (Expr.codeToExpr covCode)
              @?= " function(x){ __cov(5); return 1;}",
      testCase "two-arg function wraps in F2 with __cov(0) in body" $
        let twoArgFunc = Opt.Function [nameStr "a", nameStr "b"] leafExpr
            (covCode, _) = Expr.generateCov devModeWithCoverage 0 twoArgFunc
         in renderExpr (Expr.codeToExpr covCode)
              @?= " F2( function(a,b){ __cov(0); return 1;})",
      testCase "leaf expr with counter 99 renders identically to counter 0" $
        let (covCode99, _) = Expr.generateCov devModeWithCoverage 99 leafExpr
            (covCode0, _) = Expr.generateCov devModeWithCoverage 0 leafExpr
         in renderExpr (Expr.codeToExpr covCode99)
              @?= renderExpr (Expr.codeToExpr covCode0)
    ]

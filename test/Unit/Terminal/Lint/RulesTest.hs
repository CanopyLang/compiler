{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the lint rule implementations in 'Lint.Rules'.
--
-- Each test constructs a synthetic 'Src.Module' that triggers (or does not
-- trigger) a specific lint rule, then asserts on the number and content
-- of the resulting 'LintWarning' list.
--
-- @since 0.19.2
module Unit.Terminal.Lint.RulesTest (tests) where

import qualified AST.Source as Src
import qualified Canopy.Data.Name as Name
import qualified Data.List as List
import Lint.Rules
  ( checkMissingTypeAnnotation,
    checkShadowedVariable,
    checkUnusedLetVariable,
  )
import Lint.Types
  ( LintRule (..),
    LintWarning (..),
  )
import qualified Reporting.Annotation as Ann
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Lint.Rules"
    [ shadowedVariableTests,
      unusedLetVariableTests,
      missingAnnotationTests
    ]

-- SHADOWED VARIABLE TESTS

shadowedVariableTests :: TestTree
shadowedVariableTests =
  Test.testGroup
    "ShadowedVariable"
    [ Test.testCase "no shadow in simple let" $
        length (checkShadowedVariable noShadowModule) @?= 0,
      Test.testCase "let shadows function parameter" $
        length (checkShadowedVariable letShadowsParamModule) @?= 1,
      Test.testCase "shadow warning references correct rule" $
        _warnRule (oneWarning (checkShadowedVariable letShadowsParamModule))
          @?= ShadowedVariable,
      Test.testCase "shadow warning message mentions variable name" $
        List.isInfixOf "x" (_warnMessage (oneWarning (checkShadowedVariable letShadowsParamModule)))
          @?= True,
      Test.testCase "nested let shadows outer let" $
        length (checkShadowedVariable nestedLetShadowModule) @?= 1,
      Test.testCase "case branch shadows function parameter" $
        length (checkShadowedVariable caseShadowsParamModule) @?= 1,
      Test.testCase "lambda shadows function parameter" $
        length (checkShadowedVariable lambdaShadowsParamModule) @?= 1,
      Test.testCase "multiple shadows produce multiple warnings" $
        length (checkShadowedVariable multipleShadowsModule) @?= 2,
      Test.testCase "different names do not shadow" $
        length (checkShadowedVariable differentNamesModule) @?= 0
    ]

-- UNUSED LET VARIABLE TESTS

unusedLetVariableTests :: TestTree
unusedLetVariableTests =
  Test.testGroup
    "UnusedLetVariable"
    [ Test.testCase "used let variable produces no warning" $
        length (checkUnusedLetVariable usedLetModule) @?= 0,
      Test.testCase "unused let variable produces warning" $
        length (checkUnusedLetVariable unusedLetModule) @?= 1,
      Test.testCase "unused let warning references correct rule" $
        _warnRule (oneWarning (checkUnusedLetVariable unusedLetModule))
          @?= UnusedLetVariable,
      Test.testCase "unused let warning message mentions variable name" $
        List.isInfixOf "unused" (_warnMessage (oneWarning (checkUnusedLetVariable unusedLetModule)))
          @?= True,
      Test.testCase "multiple unused lets produce multiple warnings" $
        length (checkUnusedLetVariable multiUnusedLetModule) @?= 2,
      Test.testCase "nested let unused is detected" $
        length (checkUnusedLetVariable nestedUnusedLetModule) @?= 1,
      Test.testCase "let used in subsequent def is not flagged" $
        length (checkUnusedLetVariable letUsedInSubsequentDefModule) @?= 0
    ]

-- MISSING TYPE ANNOTATION TESTS (existing rule, verify still works)

missingAnnotationTests :: TestTree
missingAnnotationTests =
  Test.testGroup
    "MissingTypeAnnotation"
    [ Test.testCase "value with annotation produces no warning" $
        length (checkMissingTypeAnnotation annotatedModule) @?= 0,
      Test.testCase "value without annotation produces warning" $
        length (checkMissingTypeAnnotation unannotatedModule) @?= 1,
      Test.testCase "warning mentions function name" $
        List.isInfixOf "myFunc" (_warnMessage (oneWarning (checkMissingTypeAnnotation unannotatedModule)))
          @?= True
    ]

-- HELPERS

-- | Extract the single warning from a list, failing if the list is not a singleton.
oneWarning :: [LintWarning] -> LintWarning
oneWarning [w] = w
oneWarning ws = error ("expected exactly one warning, got " ++ show (length ws))

-- | A minimal empty module for constructing test cases.
emptyModule :: Src.Module
emptyModule =
  Src.Module
    { Src._name = Nothing,
      Src._exports = Ann.At Ann.one Src.Open,
      Src._docs = Src.NoDocs Ann.one,
      Src._imports = [],
      Src._foreignImports = [],
      Src._values = [],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects,
      Src._comments = []
    }

-- | Helper to make a located expression at region one.
loc :: a -> Ann.Located a
loc = Ann.At Ann.one

-- | Helper to create a PVar pattern.
pvar :: String -> Src.Pattern
pvar s = loc (Src.PVar (Name.fromChars s))

-- | Helper to create a variable expression.
var :: String -> Src.Expr
var s = loc (Src.Var Src.LowVar (Name.fromChars s))

-- | Helper to create an integer expression.
int :: Int -> Src.Expr
int n = loc (Src.Int n)

-- | Helper to create a named definition.
mkDef :: String -> [Src.Pattern] -> Src.Expr -> Src.Def
mkDef name pats body =
  Src.Define (loc (Name.fromChars name)) pats body Nothing

-- | Helper to wrap a value in a module.
moduleWithValue :: Src.Value -> Src.Module
moduleWithValue v = emptyModule {Src._values = [loc v]}

-- | Helper to create a Value from a name, patterns, and body.
mkValue :: String -> [Src.Pattern] -> Src.Expr -> Src.Value
mkValue name pats body =
  Src.Value (loc (Name.fromChars name)) pats body Nothing Nothing

-- | Helper to create a Value with a type annotation.
mkAnnotatedValue :: String -> [Src.Pattern] -> Src.Expr -> Src.Value
mkAnnotatedValue name pats body =
  Src.Value (loc (Name.fromChars name)) pats body (Just (loc Src.TUnit)) Nothing

-- SHADOWED VARIABLE TEST MODULES

-- | No shadow: function param "x", let defines "y", body uses both.
noShadowModule :: Src.Module
noShadowModule =
  moduleWithValue (mkValue "f" [pvar "x"] letExpr)
  where
    letExpr = loc (Src.Let [loc (mkDef "y" [] (int 1))] (var "x"))

-- | Let shadows function parameter "x".
letShadowsParamModule :: Src.Module
letShadowsParamModule =
  moduleWithValue (mkValue "f" [pvar "x"] letExpr)
  where
    letExpr = loc (Src.Let [loc (mkDef "x" [] (int 1))] (var "x"))

-- | Nested let: outer let "y", inner let "y" shadows it.
nestedLetShadowModule :: Src.Module
nestedLetShadowModule =
  moduleWithValue (mkValue "f" [] outerLet)
  where
    innerLet = loc (Src.Let [loc (mkDef "y" [] (int 2))] (var "y"))
    outerLet = loc (Src.Let [loc (mkDef "y" [] (int 1))] innerLet)

-- | Case branch pattern "x" shadows function parameter "x".
caseShadowsParamModule :: Src.Module
caseShadowsParamModule =
  moduleWithValue (mkValue "f" [pvar "x"] caseExpr)
  where
    caseExpr = loc (Src.Case (var "x") [(pvar "x", int 1)])

-- | Lambda parameter "x" shadows function parameter "x".
lambdaShadowsParamModule :: Src.Module
lambdaShadowsParamModule =
  moduleWithValue (mkValue "f" [pvar "x"] lambdaExpr)
  where
    lambdaExpr = loc (Src.Lambda [pvar "x"] (var "x"))

-- | Two shadows: let "x" and let "y" both shadow function params.
multipleShadowsModule :: Src.Module
multipleShadowsModule =
  moduleWithValue (mkValue "f" [pvar "x", pvar "y"] letExpr)
  where
    letExpr =
      loc
        ( Src.Let
            [ loc (mkDef "x" [] (int 1)),
              loc (mkDef "y" [] (int 2))
            ]
            (var "x")
        )

-- | Let "y" and "z" do not shadow function param "x".
differentNamesModule :: Src.Module
differentNamesModule =
  moduleWithValue (mkValue "f" [pvar "x"] letExpr)
  where
    letExpr =
      loc
        ( Src.Let
            [ loc (mkDef "y" [] (int 1)),
              loc (mkDef "z" [] (int 2))
            ]
            (var "x")
        )

-- UNUSED LET VARIABLE TEST MODULES

-- | Let "y" is used in body: no warning.
usedLetModule :: Src.Module
usedLetModule =
  moduleWithValue (mkValue "f" [] letExpr)
  where
    letExpr = loc (Src.Let [loc (mkDef "y" [] (int 1))] (var "y"))

-- | Let "unused" is not referenced in body: warning.
unusedLetModule :: Src.Module
unusedLetModule =
  moduleWithValue (mkValue "f" [] letExpr)
  where
    letExpr = loc (Src.Let [loc (mkDef "unused" [] (int 1))] (int 42))

-- | Two unused lets "a" and "b": two warnings.
multiUnusedLetModule :: Src.Module
multiUnusedLetModule =
  moduleWithValue (mkValue "f" [] letExpr)
  where
    letExpr =
      loc
        ( Src.Let
            [ loc (mkDef "a" [] (int 1)),
              loc (mkDef "b" [] (int 2))
            ]
            (int 42)
        )

-- | Outer let used, inner let "dead" unused.
nestedUnusedLetModule :: Src.Module
nestedUnusedLetModule =
  moduleWithValue (mkValue "f" [] outerLet)
  where
    innerLet = loc (Src.Let [loc (mkDef "dead" [] (int 2))] (var "y"))
    outerLet = loc (Src.Let [loc (mkDef "y" [] (int 1))] innerLet)

-- | Let "helper" used by subsequent def "main_": no warning.
letUsedInSubsequentDefModule :: Src.Module
letUsedInSubsequentDefModule =
  moduleWithValue (mkValue "f" [] letExpr)
  where
    letExpr =
      loc
        ( Src.Let
            [ loc (mkDef "helper" [] (int 1)),
              loc (mkDef "result" [] (var "helper"))
            ]
            (var "result")
        )

-- MISSING TYPE ANNOTATION TEST MODULES

-- | Value with type annotation: no warning.
annotatedModule :: Src.Module
annotatedModule =
  moduleWithValue (mkAnnotatedValue "myFunc" [] (int 42))

-- | Value without type annotation: warning.
unannotatedModule :: Src.Module
unannotatedModule =
  moduleWithValue (mkValue "myFunc" [] (int 42))

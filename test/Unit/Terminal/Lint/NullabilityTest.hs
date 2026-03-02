{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the nullability lint rules in 'Lint.Rules.Nullability'.
--
-- Each test constructs a synthetic 'Src.Module' that triggers (or does not
-- trigger) a specific lint rule, then asserts on the number and content
-- of the resulting 'LintWarning' list.
--
-- @since 0.19.2
module Unit.Terminal.Lint.NullabilityTest (tests) where

import qualified AST.Source as Src
import qualified Canopy.Data.Name as Name
import qualified Data.List as List
import Lint.Rules
  ( checkAlwaysFalseComparison,
    checkRedundantMaybeWrap,
    checkSilentFallback,
    checkSketchyMaybe,
    checkUnnecessaryPatternMatch,
    checkUnreachableCode,
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
    "Lint.Rules.Nullability"
    [ sketchyMaybeTests,
      redundantMaybeWrapTests,
      unnecessaryPatternMatchTests,
      silentFallbackTests,
      alwaysFalseComparisonTests,
      unreachableCodeTests
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

-- | Helper to make a located value at region one.
loc :: a -> Ann.Located a
loc = Ann.At Ann.one

-- | Helper to create a PVar pattern.
pvar :: String -> Src.Pattern
pvar s = loc (Src.PVar (Name.fromChars s))

-- | Helper to create a variable expression.
var :: String -> Src.Expr
var s = loc (Src.Var Src.LowVar (Name.fromChars s))

-- | Helper to create an uppercase variable (constructor) expression.
ctor :: String -> Src.Expr
ctor s = loc (Src.Var Src.CapVar (Name.fromChars s))

-- | Helper to create an integer expression.
int :: Int -> Src.Expr
int n = loc (Src.Int n)

-- | Helper to create a function call expression.
call :: Src.Expr -> [Src.Expr] -> Src.Expr
call f args = loc (Src.Call f args)

-- | Helper to wrap a value in a module.
moduleWithValue :: Src.Value -> Src.Module
moduleWithValue v = emptyModule {Src._values = [loc v]}

-- | Helper to create a Value from a name, patterns, and body.
mkValue :: String -> [Src.Pattern] -> Src.Expr -> Src.Value
mkValue name pats body =
  Src.Value (loc (Name.fromChars name)) pats body Nothing Nothing

-- | Create a PCtor pattern (constructor with sub-patterns).
pctor :: String -> [Src.Pattern] -> Src.Pattern
pctor name subPats = loc (Src.PCtor Ann.one (Name.fromChars name) subPats)

-- | Create a case expression.
caseExpr :: Src.Expr -> [(Src.Pattern, Src.Expr)] -> Src.Expr
caseExpr scrutinee branches = loc (Src.Case scrutinee branches)

-- | Create a binops expression with a single operator.
binop :: Src.Expr -> String -> Src.Expr -> Src.Expr
binop left opName right =
  loc (Src.Binops [(left, loc (Name.fromChars opName))] right)

-- | Create a let expression.
letExpr :: [Src.Def] -> Src.Expr -> Src.Expr
letExpr defs body = loc (Src.Let (map loc defs) body)

-- | Create a named definition.
mkDef :: String -> [Src.Pattern] -> Src.Expr -> Src.Def
mkDef name pats body =
  Src.Define (loc (Name.fromChars name)) pats body Nothing

-- SKETCHY MAYBE TESTS

sketchyMaybeTests :: TestTree
sketchyMaybeTests =
  Test.testGroup
    "SketchyMaybeCheck"
    [ Test.testCase "case with Just zero-comparison triggers warning" $
        length (checkSketchyMaybe sketchyMaybeModule) @?= 1,
      Test.testCase "warning uses correct rule" $
        _warnRule (oneWarning (checkSketchyMaybe sketchyMaybeModule))
          @?= SketchyMaybeCheck,
      Test.testCase "warning message mentions zero" $
        List.isInfixOf "zero" (_warnMessage (oneWarning (checkSketchyMaybe sketchyMaybeModule)))
          @?= True,
      Test.testCase "case with Just non-zero-comparison does not trigger" $
        length (checkSketchyMaybe nonSketchyMaybeModule) @?= 0,
      Test.testCase "non-maybe case does not trigger" $
        length (checkSketchyMaybe plainCaseModule) @?= 0,
      Test.testCase "maybe case without zero check does not trigger" $
        length (checkSketchyMaybe maybeCaseNoZeroModule) @?= 0,
      Test.testCase "nested sketchy maybe triggers" $
        length (checkSketchyMaybe nestedSketchyModule) @?= 1
    ]

-- | case maybeCount of Just n -> n /= 0; Nothing -> False
sketchyMaybeModule :: Src.Module
sketchyMaybeModule =
  moduleWithValue (mkValue "isActive" [pvar "count"] body)
  where
    body =
      caseExpr
        (var "count")
        [ (pctor "Just" [pvar "n"], binop (var "n") "/=" (int 0)),
          (pctor "Nothing" [], ctor "False")
        ]

-- | case maybeCount of Just n -> n > 5; Nothing -> False (no zero comparison)
nonSketchyMaybeModule :: Src.Module
nonSketchyMaybeModule =
  moduleWithValue (mkValue "f" [pvar "count"] body)
  where
    body =
      caseExpr
        (var "count")
        [ (pctor "Just" [pvar "n"], binop (var "n") ">" (int 5)),
          (pctor "Nothing" [], ctor "False")
        ]

-- | case color of Red -> 1; Blue -> 2 (not a Maybe case)
plainCaseModule :: Src.Module
plainCaseModule =
  moduleWithValue (mkValue "f" [pvar "color"] body)
  where
    body =
      caseExpr
        (var "color")
        [ (pctor "Red" [], int 1),
          (pctor "Blue" [], int 2)
        ]

-- | case mx of Just n -> n; Nothing -> False (Just returns var, no zero check)
maybeCaseNoZeroModule :: Src.Module
maybeCaseNoZeroModule =
  moduleWithValue (mkValue "f" [pvar "mx"] body)
  where
    body =
      caseExpr
        (var "mx")
        [ (pctor "Just" [pvar "n"], var "n"),
          (pctor "Nothing" [], ctor "False")
        ]

-- | Nested: let x = case ... of Just n -> n /= 0 ... in x
nestedSketchyModule :: Src.Module
nestedSketchyModule =
  moduleWithValue (mkValue "f" [pvar "mx"] body)
  where
    innerCase =
      caseExpr
        (var "mx")
        [ (pctor "Just" [pvar "n"], binop (var "n") "==" (int 0)),
          (pctor "Nothing" [], ctor "True")
        ]
    body = letExpr [mkDef "result" [] innerCase] (var "result")

-- REDUNDANT MAYBE WRAP TESTS

redundantMaybeWrapTests :: TestTree
redundantMaybeWrapTests =
  Test.testGroup
    "RedundantMaybeWrap"
    [ Test.testCase "always-Just function triggers warning" $
        length (checkRedundantMaybeWrap alwaysJustModule) @?= 1,
      Test.testCase "warning uses correct rule" $
        _warnRule (oneWarning (checkRedundantMaybeWrap alwaysJustModule))
          @?= RedundantMaybeWrap,
      Test.testCase "warning message mentions function name" $
        List.isInfixOf "alwaysJust" (_warnMessage (oneWarning (checkRedundantMaybeWrap alwaysJustModule)))
          @?= True,
      Test.testCase "function returning variable does not trigger" $
        length (checkRedundantMaybeWrap normalFuncModule) @?= 0,
      Test.testCase "function returning case on Maybe does not trigger" $
        length (checkRedundantMaybeWrap maybeCaseReturnModule) @?= 0,
      Test.testCase "function returning integer does not trigger" $
        length (checkRedundantMaybeWrap intReturnModule) @?= 0
    ]

-- | alwaysJust x = Just x
alwaysJustModule :: Src.Module
alwaysJustModule =
  moduleWithValue (mkValue "alwaysJust" [pvar "x"] body)
  where
    body = call (ctor "Just") [var "x"]

-- | f x = x (not always Just)
normalFuncModule :: Src.Module
normalFuncModule =
  moduleWithValue (mkValue "f" [pvar "x"] (var "x"))

-- | f mx = case mx of Just x -> x; Nothing -> 0
maybeCaseReturnModule :: Src.Module
maybeCaseReturnModule =
  moduleWithValue (mkValue "f" [pvar "mx"] body)
  where
    body =
      caseExpr
        (var "mx")
        [ (pctor "Just" [pvar "x"], var "x"),
          (pctor "Nothing" [], int 0)
        ]

-- | f = 42
intReturnModule :: Src.Module
intReturnModule =
  moduleWithValue (mkValue "f" [] (int 42))

-- UNNECESSARY PATTERN MATCH TESTS

unnecessaryPatternMatchTests :: TestTree
unnecessaryPatternMatchTests =
  Test.testGroup
    "UnnecessaryPatternMatch"
    [ Test.testCase "case on unit triggers warning" $
        length (checkUnnecessaryPatternMatch unitCaseModule) @?= 1,
      Test.testCase "warning uses correct rule" $
        _warnRule (oneWarning (checkUnnecessaryPatternMatch unitCaseModule))
          @?= UnnecessaryPatternMatch,
      Test.testCase "warning message mentions unit" $
        List.isInfixOf "unit" (_warnMessage (oneWarning (checkUnnecessaryPatternMatch unitCaseModule)))
          @?= True,
      Test.testCase "case on Maybe does not trigger" $
        length (checkUnnecessaryPatternMatch maybeCaseNoZeroModule) @?= 0,
      Test.testCase "case with multiple branches does not trigger" $
        length (checkUnnecessaryPatternMatch plainCaseModule) @?= 0,
      Test.testCase "nested unit case triggers" $
        length (checkUnnecessaryPatternMatch nestedUnitCaseModule) @?= 1
    ]

-- | case () of () -> doSomething
unitCaseModule :: Src.Module
unitCaseModule =
  moduleWithValue (mkValue "f" [] body)
  where
    body = caseExpr (loc Src.Unit) [(loc Src.PUnit, int 42)]

-- | let x = case () of () -> 1 in x
nestedUnitCaseModule :: Src.Module
nestedUnitCaseModule =
  moduleWithValue (mkValue "f" [] body)
  where
    innerCase = caseExpr (loc Src.Unit) [(loc Src.PUnit, int 1)]
    body = letExpr [mkDef "x" [] innerCase] (var "x")

-- SILENT FALLBACK TESTS

silentFallbackTests :: TestTree
silentFallbackTests =
  Test.testGroup
    "SilentFallback"
    [ Test.testCase "Nothing branch with literal default triggers warning" $
        length (checkSilentFallback silentFallbackModule) @?= 1,
      Test.testCase "warning uses correct rule" $
        _warnRule (oneWarning (checkSilentFallback silentFallbackModule))
          @?= SilentFallback,
      Test.testCase "warning message mentions silent" $
        List.isInfixOf "silent" (_warnMessage (oneWarning (checkSilentFallback silentFallbackModule)))
          @?= True,
      Test.testCase "Nothing branch with variable does not trigger" $
        length (checkSilentFallback nothingVarModule) @?= 0,
      Test.testCase "Nothing branch with function call does not trigger" $
        length (checkSilentFallback nothingCallModule) @?= 0,
      Test.testCase "Nothing branch with empty list triggers" $
        length (checkSilentFallback nothingEmptyListModule) @?= 1,
      Test.testCase "non-Maybe case does not trigger" $
        length (checkSilentFallback plainCaseModule) @?= 0
    ]

-- | case String.toInt input of Just n -> n; Nothing -> 0
silentFallbackModule :: Src.Module
silentFallbackModule =
  moduleWithValue (mkValue "parse" [pvar "input"] body)
  where
    body =
      caseExpr
        (var "input")
        [ (pctor "Just" [pvar "n"], var "n"),
          (pctor "Nothing" [], int 0)
        ]

-- | case mx of Just n -> n; Nothing -> defaultVal
nothingVarModule :: Src.Module
nothingVarModule =
  moduleWithValue (mkValue "f" [pvar "mx"] body)
  where
    body =
      caseExpr
        (var "mx")
        [ (pctor "Just" [pvar "n"], var "n"),
          (pctor "Nothing" [], var "defaultVal")
        ]

-- | case mx of Just n -> n; Nothing -> computeDefault ()
nothingCallModule :: Src.Module
nothingCallModule =
  moduleWithValue (mkValue "f" [pvar "mx"] body)
  where
    body =
      caseExpr
        (var "mx")
        [ (pctor "Just" [pvar "n"], var "n"),
          (pctor "Nothing" [], call (var "computeDefault") [loc Src.Unit])
        ]

-- | case mx of Just xs -> xs; Nothing -> []
nothingEmptyListModule :: Src.Module
nothingEmptyListModule =
  moduleWithValue (mkValue "f" [pvar "mx"] body)
  where
    body =
      caseExpr
        (var "mx")
        [ (pctor "Just" [pvar "xs"], var "xs"),
          (pctor "Nothing" [], loc (Src.List []))
        ]

-- ALWAYS FALSE COMPARISON TESTS

alwaysFalseComparisonTests :: TestTree
alwaysFalseComparisonTests =
  Test.testGroup
    "AlwaysFalseComparison"
    [ Test.testCase "comparing different constructors triggers warning" $
        length (checkAlwaysFalseComparison diffCtorComparisonModule) @?= 1,
      Test.testCase "warning uses correct rule" $
        _warnRule (oneWarning (checkAlwaysFalseComparison diffCtorComparisonModule))
          @?= AlwaysFalseComparison,
      Test.testCase "warning message mentions both constructors" $
        let msg = _warnMessage (oneWarning (checkAlwaysFalseComparison diffCtorComparisonModule))
         in List.isInfixOf "Red" msg && List.isInfixOf "Small" msg @?= True,
      Test.testCase "comparing same constructor does not trigger" $
        length (checkAlwaysFalseComparison sameCtorComparisonModule) @?= 0,
      Test.testCase "comparing variables does not trigger" $
        length (checkAlwaysFalseComparison varComparisonModule) @?= 0,
      Test.testCase "comparing constructor and variable does not trigger" $
        length (checkAlwaysFalseComparison mixedComparisonModule) @?= 0
    ]

-- | Red == Small
diffCtorComparisonModule :: Src.Module
diffCtorComparisonModule =
  moduleWithValue (mkValue "isSame" [] body)
  where
    body = binop (ctor "Red") "==" (ctor "Small")

-- | Red == Red
sameCtorComparisonModule :: Src.Module
sameCtorComparisonModule =
  moduleWithValue (mkValue "isSame" [] body)
  where
    body = binop (ctor "Red") "==" (ctor "Red")

-- | x == y
varComparisonModule :: Src.Module
varComparisonModule =
  moduleWithValue (mkValue "isSame" [pvar "x", pvar "y"] body)
  where
    body = binop (var "x") "==" (var "y")

-- | Red == x
mixedComparisonModule :: Src.Module
mixedComparisonModule =
  moduleWithValue (mkValue "isSame" [pvar "x"] body)
  where
    body = binop (ctor "Red") "==" (var "x")

-- UNREACHABLE CODE TESTS

unreachableCodeTests :: TestTree
unreachableCodeTests =
  Test.testGroup
    "UnreachableCode"
    [ Test.testCase "let with exhaustive case before more defs triggers" $
        length (checkUnreachableCode unreachableLetModule) @?= 1,
      Test.testCase "warning uses correct rule" $
        _warnRule (oneWarning (checkUnreachableCode unreachableLetModule))
          @?= UnreachableCode,
      Test.testCase "warning message mentions unreachable" $
        List.isInfixOf "unreachable" (_warnMessage (oneWarning (checkUnreachableCode unreachableLetModule)))
          @?= True,
      Test.testCase "let with single def does not trigger" $
        length (checkUnreachableCode singleDefLetModule) @?= 0,
      Test.testCase "let with non-case def does not trigger" $
        length (checkUnreachableCode nonCaseLetModule) @?= 0,
      Test.testCase "let with non-exhaustive case does not trigger" $
        length (checkUnreachableCode nonExhaustiveLetModule) @?= 0
    ]

-- | let result = case x of A -> 1; B -> 2
--       dead = 42
--   in dead
unreachableLetModule :: Src.Module
unreachableLetModule =
  moduleWithValue (mkValue "f" [pvar "x"] body)
  where
    exhaustiveCase =
      caseExpr
        (var "x")
        [ (pctor "A" [], int 1),
          (pctor "B" [], int 2)
        ]
    body =
      letExpr
        [ mkDef "result" [] exhaustiveCase,
          mkDef "dead" [] (int 42)
        ]
        (var "dead")

-- | let x = 42 in x (single def, no case)
singleDefLetModule :: Src.Module
singleDefLetModule =
  moduleWithValue (mkValue "f" [] body)
  where
    body = letExpr [mkDef "x" [] (int 42)] (var "x")

-- | let x = 1; y = 2 in x + y (no case)
nonCaseLetModule :: Src.Module
nonCaseLetModule =
  moduleWithValue (mkValue "f" [] body)
  where
    body =
      letExpr
        [ mkDef "x" [] (int 1),
          mkDef "y" [] (int 2)
        ]
        (binop (var "x") "+" (var "y"))

-- | let result = case x of A -> someFunc x in result
-- (single branch, not exhaustive)
nonExhaustiveLetModule :: Src.Module
nonExhaustiveLetModule =
  moduleWithValue (mkValue "f" [pvar "x"] body)
  where
    singleBranchCase =
      caseExpr
        (var "x")
        [(pctor "A" [], call (var "someFunc") [var "x"])]
    body = letExpr [mkDef "result" [] singleBranchCase] (var "result")

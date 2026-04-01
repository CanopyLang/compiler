{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.JavaScript.FFI.JSAnalysis'.
--
-- Covers:
--   * 'parseBlockGroups' / 'parseAllGroups' — group detection and parse errors
--   * 'freeVarsInGroup' — scope-aware free-variable analysis (including the
--     canonical string-literal bug regression)
--   * 'allFreeVarsInGroup' — unfiltered free-variable collection
--   * 'aritiesInGroup' — F\/A arity detection
--   * 'groupDeclNames' — comma-separated var declaration name extraction
--
-- @since 0.20.3
module Unit.Generate.JavaScript.JSAnalysisTest (tests) where

import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Generate.JavaScript.FFI.JSAnalysis as JSAnalysis
import Language.JavaScript.Parser.AST (JSStatement)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.FFI.JSAnalysis"
    [ parseTests,
      freeVarsTests,
      allFreeVarsTests,
      aritiesTests,
      groupDeclNamesTests
    ]


-- PARSE TESTS

parseTests :: TestTree
parseTests =
  testGroup
    "parseBlockGroups / parseAllGroups"
    [ testCase "var declaration produces one group with correct name" $
        let groups = parseGroups "var foo = 1;"
         in length groups @?= 1
            <> (JSAnalysis._bgName (head groups) @?= "foo"),
      testCase "function declaration produces one group with correct name" $
        let groups = parseGroups "function bar() {}"
         in length groups @?= 1
            <> (JSAnalysis._bgName (head groups) @?= "bar"),
      testCase "invalid JavaScript returns Nothing" $
        JSAnalysis.parseBlockGroups (Text.pack "this is not $$$ JS!!!") @?= Nothing,
      testCase "two var declarations produce two groups" $
        let groups = parseGroups "var alpha = 1;\nvar beta = 2;"
         in length groups @?= 2,
      testCase "two group names are alpha and beta" $
        let groups = parseGroups "var alpha = 1;\nvar beta = 2;"
            names = map JSAnalysis._bgName groups
         in names @?= ["alpha", "beta"],
      testCase "empty input produces zero groups" $
        let groups = parseGroups ""
         in length groups @?= 0,
      testCase "parseAllGroups returns statements and groups on success" $
        case JSAnalysis.parseAllGroups (Text.pack "var x = 1;") of
          Nothing -> assertFailure "Expected successful parse"
          Just (stmts, groups) ->
            (length stmts >= 1 && length groups == 1) @?= True,
      testCase "parseAllGroups returns Nothing on invalid JS" $
        JSAnalysis.parseAllGroups (Text.pack "<<< invalid >>>") @?= Nothing,
      testCase "function before var produces correct ordering" $
        let groups = parseGroups "function f() {}\nvar g = 1;"
            names = map JSAnalysis._bgName groups
         in names @?= ["f", "g"],
      testCase "var with multi-name comma list: primary name is first declared" $
        let groups = parseGroups "var A = 0, B = 1;"
         in case groups of
              [g] -> JSAnalysis._bgName g @?= "A"
              _ -> assertFailure ("Expected 1 group, got " ++ show (length groups))
    ]


-- FREE VARS TESTS

freeVarsTests :: TestTree
freeVarsTests =
  testGroup
    "freeVarsInGroup"
    [ testCase "basic: y and z referenced in var initializer appear as free" $
        let stmts = stmtsOf "var x = y + z;"
            allNames = Set.fromList ["y", "z"]
         in JSAnalysis.freeVarsInGroup allNames stmts @?= Set.fromList ["y", "z"],
      testCase "self-reference is excluded from deps (var x = x does not self-dep)" $
        let stmts = stmtsOf "var x = y;"
            allNames = Set.fromList ["x", "y"]
         in JSAnalysis.freeVarsInGroup allNames stmts @?= Set.fromList ["y"],
      testCase "function parameter hides outer name: param y is not free" $
        let stmts = stmtsOf "function f(y) { return y + z; }"
            allNames = Set.fromList ["y", "z"]
         in JSAnalysis.freeVarsInGroup allNames stmts @?= Set.singleton "z",
      testCase "string literals do not produce deps (canonical bug regression)" $
        -- 'args[\"node\"]' previously caused a false dep on var 'node'
        let stmts = stmtsOf "var f = function(args) { return args['node']; };"
            allNames = Set.fromList ["node"]
         in JSAnalysis.freeVarsInGroup allNames stmts @?= Set.empty,
      testCase "bracket access with string key does not create spurious dep" $
        let stmts = stmtsOf "var f = function(obj) { return obj['list']; };"
            allNames = Set.fromList ["list", "obj"]
         in JSAnalysis.freeVarsInGroup allNames stmts @?= Set.empty,
      testCase "var-hoisted local does not appear as free dep" $
        let stmts = stmtsOf "function f() { var x = 1; return x + y; }"
            allNames = Set.fromList ["x", "y"]
         in JSAnalysis.freeVarsInGroup allNames stmts @?= Set.singleton "y",
      testCase "nested function var-hoisting stops at function boundary" $
        -- inner var 'inner' is local to inner function, outer 'outer' stays free
        let stmts = stmtsOf "function f() { var outer = 1; function g() { var inner = 2; return inner + dep; } }"
            allNames = Set.fromList ["outer", "inner", "dep"]
         in JSAnalysis.freeVarsInGroup allNames stmts @?= Set.singleton "dep",
      testCase "identifier in object value is free" $
        let stmts = stmtsOf "var o = { key: dep };"
            allNames = Set.fromList ["dep"]
         in JSAnalysis.freeVarsInGroup allNames stmts @?= Set.singleton "dep",
      testCase "only names in allNames set are returned" $
        let stmts = stmtsOf "var x = alpha + beta + gamma;"
            allNames = Set.fromList ["alpha", "beta"]
         in JSAnalysis.freeVarsInGroup allNames stmts @?= Set.fromList ["alpha", "beta"],
      testCase "empty allNames produces empty result even with references" $
        let stmts = stmtsOf "var x = alpha + beta;"
         in JSAnalysis.freeVarsInGroup Set.empty stmts @?= Set.empty
    ]


-- ALL FREE VARS TESTS

allFreeVarsTests :: TestTree
allFreeVarsTests =
  testGroup
    "allFreeVarsInGroup"
    [ testCase "returns identifiers not in allNames (cross-file refs)" $
        let stmts = stmtsOf "var x = externalFn(y);"
         in Set.member "externalFn" (JSAnalysis.allFreeVarsInGroup stmts) @?= True,
      testCase "same scope rules apply: params are not free" $
        let stmts = stmtsOf "function f(param) { return param; }"
         in Set.member "param" (JSAnalysis.allFreeVarsInGroup stmts) @?= False,
      testCase "string literals produce no free vars" $
        let stmts = stmtsOf "var x = obj['stringKey'];"
         in Set.member "stringKey" (JSAnalysis.allFreeVarsInGroup stmts) @?= False,
      testCase "empty block produces empty free vars" $
        JSAnalysis.allFreeVarsInGroup [] @?= Set.empty
    ]


-- ARITIES TESTS

aritiesTests :: TestTree
aritiesTests =
  testGroup
    "aritiesInGroup"
    [ testCase "F2 call produces arity 2" $
        let stmts = stmtsOf "var f = F2(function(a, b) { return a + b; });"
         in JSAnalysis.aritiesInGroup stmts @?= Set.singleton 2,
      testCase "A3 call produces arity 3" $
        let stmts = stmtsOf "var r = A3(myFn, x, y, z);"
         in JSAnalysis.aritiesInGroup stmts @?= Set.singleton 3,
      testCase "var declaration of F2 is not a call, produces no arity" $
        -- 'var F2 = 1' declares F2 as a variable, does not CALL it
        let stmts = stmtsOf "var F2 = 1;"
         in JSAnalysis.aritiesInGroup stmts @?= Set.empty,
      testCase "multiple arities in one group are collected" $
        let stmts = stmtsOf "var f = F2(g); var h = A3(f, x, y, z);"
         in JSAnalysis.aritiesInGroup stmts @?= Set.fromList [2, 3],
      testCase "F9 produces arity 9" $
        let stmts = stmtsOf "var f = F9(function(a,b,c,d,e,ff,g,h,i) { return a; });"
         in JSAnalysis.aritiesInGroup stmts @?= Set.singleton 9,
      testCase "no F/A calls produces empty arities" $
        let stmts = stmtsOf "var x = 1 + 2;"
         in JSAnalysis.aritiesInGroup stmts @?= Set.empty,
      testCase "arity inside function body is captured" $
        let stmts = stmtsOf "function wrapper() { return F2(function(a, b) { return a; }); }"
         in JSAnalysis.aritiesInGroup stmts @?= Set.singleton 2,
      testCase "empty input produces empty arities" $
        JSAnalysis.aritiesInGroup [] @?= Set.empty
    ]


-- GROUP DECL NAMES TESTS

groupDeclNamesTests :: TestTree
groupDeclNamesTests =
  testGroup
    "groupDeclNames"
    [ testCase "var A = 0, B = 1 produces [A, B]" $
        let groups = parseGroups "var A = 0, B = 1;"
         in case groups of
              [g] -> JSAnalysis.groupDeclNames g @?= ["A", "B"]
              _ -> assertFailure ("Expected 1 group, got " ++ show (length groups)),
      testCase "function F() {} produces [F]" $
        let groups = parseGroups "function F() {}"
         in case groups of
              [g] -> JSAnalysis.groupDeclNames g @?= ["F"]
              _ -> assertFailure ("Expected 1 group, got " ++ show (length groups)),
      testCase "single var x produces [x]" $
        let groups = parseGroups "var x = 42;"
         in case groups of
              [g] -> JSAnalysis.groupDeclNames g @?= ["x"]
              _ -> assertFailure ("Expected 1 group, got " ++ show (length groups)),
      testCase "var A = 0, B = 1, C = 2 produces [A, B, C]" $
        let groups = parseGroups "var A = 0, B = 1, C = 2;"
         in case groups of
              [g] -> JSAnalysis.groupDeclNames g @?= ["A", "B", "C"]
              _ -> assertFailure ("Expected 1 group, got " ++ show (length groups))
    ]


-- HELPERS

-- | Parse JS text into block groups, failing-safe (returns empty list on error).
parseGroups :: String -> [JSAnalysis.BlockGroup]
parseGroups src =
  maybe [] id (JSAnalysis.parseBlockGroups (Text.pack src))

-- | Parse JS text and extract the top-level statements.
-- Returns empty list on parse failure.
stmtsOf :: String -> [JSStatement]
stmtsOf src =
  case JSAnalysis.parseAllGroups (Text.pack src) of
    Nothing -> []
    Just (stmts, _) -> stmts

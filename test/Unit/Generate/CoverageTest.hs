{-# LANGUAGE OverloadedStrings #-}

-- | Tests for coverage instrumentation in the compiler.
--
-- Validates that 'countExprPoints', 'countNodePoints', 'countDefPoints',
-- 'computeBaseIds', 'covCall', and 'coverageRuntimePreamble' produce
-- correct results for various AST shapes.
--
-- @since 0.19.2
module Unit.Generate.CoverageTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import Canopy.Data.Name (Name)
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Generate.JavaScript.Coverage as Coverage
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.Mode as Mode
import qualified Json.Encode as Encode
import qualified Reporting.Annotation as Ann
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Coverage"
    [ countExprPointsTests,
      countNodePointsTests,
      countDefPointsTests,
      computeBaseIdsTests,
      covCallTests,
      preambleTests,
      coverageMapBuildTests,
      coveragePointTypeTests,
      lcovFormatTests,
      istanbulJsonTests,
      modeCoverageTests,
      generateCovTests,
      caseInstrumentationTests,
      letDefInstrumentationTests,
      counterConsistencyTests,
      lcovStructureTests,
      istanbulStructureTests
    ]

-- HELPERS

renderBuilder :: BB.Builder -> String
renderBuilder = LChar8.unpack . BB.toLazyByteString

nameStr :: String -> Name
nameStr = Name.fromChars

dummyCanonical :: ModuleName.Canonical
dummyCanonical = ModuleName.Canonical Pkg.dummyName (nameStr "Test")

mkGlobal :: String -> String -> Opt.Global
mkGlobal modName defName =
  Opt.Global (ModuleName.Canonical Pkg.dummyName (nameStr modName)) (nameStr defName)

mkRegion :: Int -> Int -> Int -> Int -> Ann.Region
mkRegion sl sc el ec =
  Ann.Region (Ann.Position (fromIntegral sl) (fromIntegral sc)) (Ann.Position (fromIntegral el) (fromIntegral ec))

-- Simple leaf expression (no coverage points)
leafExpr :: Opt.Expr
leafExpr = Opt.Int 42

-- A function wrapping a leaf
funcExpr :: Opt.Expr
funcExpr = Opt.Function [nameStr "x"] leafExpr

-- An if with 2 branches + else
ifExpr :: Opt.Expr
ifExpr =
  Opt.If
    [(Opt.Bool True, leafExpr), (Opt.Bool False, leafExpr)]
    leafExpr

-- COUNT EXPR POINTS TESTS

countExprPointsTests :: TestTree
countExprPointsTests =
  testGroup
    "countExprPoints"
    [ testCase "leaf expression has 0 points" $
        Coverage.countExprPoints leafExpr @?= 0,
      testCase "Bool literal has 0 points" $
        Coverage.countExprPoints (Opt.Bool True) @?= 0,
      testCase "VarLocal has 0 points" $
        Coverage.countExprPoints (Opt.VarLocal (nameStr "x")) @?= 0,
      testCase "Function adds 1 point for entry" $
        Coverage.countExprPoints funcExpr @?= 1,
      testCase "nested Function adds 2 points" $
        Coverage.countExprPoints (Opt.Function [nameStr "x"] funcExpr) @?= 2,
      testCase "If with 2 branches has 3 points (2 + else)" $
        Coverage.countExprPoints ifExpr @?= 3,
      testCase "If with 0 branches has 1 point (just else)" $
        Coverage.countExprPoints (Opt.If [] leafExpr) @?= 1,
      testCase "If with 1 branch has 2 points" $
        Coverage.countExprPoints (Opt.If [(Opt.Bool True, leafExpr)] leafExpr) @?= 2,
      testCase "Case with 2 jumps has 2 points" $
        let caseExpr = Opt.Case (nameStr "l") (nameStr "r") (Opt.Leaf (Opt.Inline leafExpr)) [(0, leafExpr), (1, leafExpr)]
         in Coverage.countExprPoints caseExpr @?= 2,
      testCase "Case with 0 jumps has 0 points" $
        let caseExpr = Opt.Case (nameStr "l") (nameStr "r") (Opt.Leaf (Opt.Inline leafExpr)) []
         in Coverage.countExprPoints caseExpr @?= 0,
      testCase "Let with leaf def and leaf body has 0 points" $
        let letExpr = Opt.Let (Opt.Def (nameStr "x") leafExpr) leafExpr
         in Coverage.countExprPoints letExpr @?= 0,
      testCase "Let with function def adds function's points" $
        let letExpr = Opt.Let (Opt.Def (nameStr "f") funcExpr) leafExpr
         in Coverage.countExprPoints letExpr @?= 1,
      testCase "Call recurses into func and args" $
        let callExpr = Opt.Call funcExpr [funcExpr]
         in Coverage.countExprPoints callExpr @?= 2,
      testCase "Function containing If accumulates points" $
        let expr = Opt.Function [nameStr "x"] ifExpr
         in Coverage.countExprPoints expr @?= 4,
      testCase "Destruct recurses into body" $
        let expr = Opt.Destruct (Opt.Destructor (nameStr "x") (Opt.Root (nameStr "y"))) funcExpr
         in Coverage.countExprPoints expr @?= 1,
      testCase "List has 0 points" $
        Coverage.countExprPoints (Opt.List [leafExpr, leafExpr]) @?= 0
    ]

-- COUNT NODE POINTS TESTS

countNodePointsTests :: TestTree
countNodePointsTests =
  testGroup
    "countNodePoints"
    [ testCase "Define with leaf has 0 points" $
        Coverage.countNodePoints (Opt.Define leafExpr Set.empty) @?= 0,
      testCase "Define with function has 1 point" $
        Coverage.countNodePoints (Opt.Define funcExpr Set.empty) @?= 1,
      testCase "DefineTailFunc with leaf has 0 points" $
        Coverage.countNodePoints (Opt.DefineTailFunc [nameStr "x"] leafExpr Set.empty) @?= 0,
      testCase "DefineTailFunc with function has 1 point" $
        Coverage.countNodePoints (Opt.DefineTailFunc [nameStr "x"] funcExpr Set.empty) @?= 1,
      testCase "Cycle returns 0 points" $
        Coverage.countNodePoints (Opt.Cycle [nameStr "x"] [(nameStr "a", leafExpr)] [Opt.Def (nameStr "b") leafExpr] Set.empty) @?= 0,
      testCase "PortIncoming returns 0 points" $
        Coverage.countNodePoints (Opt.PortIncoming leafExpr Set.empty) @?= 0
    ]

-- COUNT DEF POINTS TESTS

countDefPointsTests :: TestTree
countDefPointsTests =
  testGroup
    "countDefPoints"
    [ testCase "Def with leaf has 0 points" $
        Coverage.countDefPoints (Opt.Def (nameStr "x") leafExpr) @?= 0,
      testCase "Def with function has 1 point" $
        Coverage.countDefPoints (Opt.Def (nameStr "x") funcExpr) @?= 1,
      testCase "TailDef with leaf has 0 points" $
        Coverage.countDefPoints (Opt.TailDef (nameStr "x") [nameStr "a"] leafExpr) @?= 0,
      testCase "TailDef with function has 1 point" $
        Coverage.countDefPoints (Opt.TailDef (nameStr "x") [nameStr "a"] funcExpr) @?= 1
    ]

-- COMPUTE BASE IDS TESTS

computeBaseIdsTests :: TestTree
computeBaseIdsTests =
  testGroup
    "computeBaseIds"
    [ testCase "empty graph yields empty base IDs" $
        Coverage.computeBaseIds Map.empty @?= Map.empty,
      testCase "single global with leaf starts at 0" $
        let g = mkGlobal "Main" "foo"
            graph = Map.singleton g (Opt.Define leafExpr Set.empty)
         in Coverage.computeBaseIds graph @?= Map.singleton g 0,
      testCase "single global with function starts at 0" $
        let g = mkGlobal "Main" "bar"
            graph = Map.singleton g (Opt.Define funcExpr Set.empty)
         in Coverage.computeBaseIds graph @?= Map.singleton g 0,
      testCase "two globals: second starts after first's points" $
        let g1 = mkGlobal "Main" "aaa"
            g2 = mkGlobal "Main" "zzz"
            graph =
              Map.fromList
                [ (g1, Opt.Define funcExpr Set.empty),
                  (g2, Opt.Define leafExpr Set.empty)
                ]
            baseIds = Coverage.computeBaseIds graph
            sorted = Map.toAscList baseIds
         in do
              length sorted @?= 2
              -- g1 has 1 point (funcExpr), so g2 should start at 1
              -- Exact ordering depends on Ord Global, but g1 < g2 alphabetically
              snd (head sorted) @?= 0
              snd (sorted !! 1) @?= 1,
      testCase "globals with zero-point nodes still get sequential IDs at same offset" $
        let g1 = mkGlobal "Main" "aaa"
            g2 = mkGlobal "Main" "bbb"
            graph =
              Map.fromList
                [ (g1, Opt.Define leafExpr Set.empty),
                  (g2, Opt.Define leafExpr Set.empty)
                ]
            baseIds = Coverage.computeBaseIds graph
         in do
              Map.lookup g1 baseIds @?= Just 0
              Map.lookup g2 baseIds @?= Just 0
    ]

-- COV CALL TESTS

covCallTests :: TestTree
covCallTests =
  testGroup
    "covCall"
    [ testCase "covCall 0 produces __cov(0);\\n" $
        renderBuilder (Coverage.covCall 0) @?= "__cov(0);\n",
      testCase "covCall 42 produces __cov(42);\\n" $
        renderBuilder (Coverage.covCall 42) @?= "__cov(42);\n",
      testCase "covCall 100 produces __cov(100);\\n" $
        renderBuilder (Coverage.covCall 100) @?= "__cov(100);\n"
    ]

-- PREAMBLE TESTS

preambleTests :: TestTree
preambleTests =
  testGroup
    "coverageRuntimePreamble"
    [ testCase "preamble contains __canopy_cov declaration" $
        let p = renderBuilder Coverage.coverageRuntimePreamble
         in assertBool "__canopy_cov not found" ("__canopy_cov" `isInfixOf` p),
      testCase "preamble contains __cov function" $
        let p = renderBuilder Coverage.coverageRuntimePreamble
         in assertBool "__cov function not found" ("function __cov" `isInfixOf` p),
      testCase "preamble ends with newline" $
        let p = renderBuilder Coverage.coverageRuntimePreamble
         in assertBool "should end with newline" (last p == '\n'),
      testCase "preamble exact content" $
        renderBuilder Coverage.coverageRuntimePreamble
          @?= "var __canopy_cov = {}; function __cov(id) { __canopy_cov[id] = (__canopy_cov[id] || 0) + 1; } (typeof globalThis !== 'undefined' ? globalThis : (typeof global !== 'undefined' ? global : self)).__canopy_cov = __canopy_cov;\n"
    ]

-- For assertBool with isInfixOf
isInfixOf :: String -> String -> Bool
isInfixOf needle haystack = any (isPrefixOf needle) (tails haystack)
  where
    tails [] = [[]]
    tails xs@(_ : rest) = xs : tails rest
    isPrefixOf [] _ = True
    isPrefixOf _ [] = False
    isPrefixOf (a : as) (b : bs) = a == b && isPrefixOf as bs

-- COVERAGE MAP BUILD TESTS

coverageMapBuildTests :: TestTree
coverageMapBuildTests =
  testGroup
    "buildCoverageMap"
    [ testCase "empty graph yields empty map" $
        Coverage.buildCoverageMap Map.empty Map.empty @?= Coverage.CoverageMap Map.empty,
      testCase "Define with function creates a FunctionEntry point" $
        let g = mkGlobal "Main" "foo"
            graph = Map.singleton g (Opt.Define funcExpr Set.empty)
            locs = Map.singleton g (mkRegion 1 1 5 10)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph locs
         in do
              Map.size points @?= 1
              case Map.lookup 0 points of
                Just pt -> Coverage._covType pt @?= Coverage.FunctionEntry
                Nothing -> assertFailure "expected point at ID 0",
      testCase "Define with If creates branch points" $
        let g = mkGlobal "Main" "bar"
            graph = Map.singleton g (Opt.Define ifExpr Set.empty)
            locs = Map.singleton g (mkRegion 1 1 10 1)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph locs
         in Map.size points @?= 3,
      testCase "coverage point IDs are sequential" $
        let g = mkGlobal "Main" "baz"
            expr = Opt.Function [nameStr "x"] (Opt.If [(Opt.Bool True, leafExpr)] leafExpr)
            graph = Map.singleton g (Opt.Define expr Set.empty)
            locs = Map.singleton g (mkRegion 1 1 10 1)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph locs
         in do
              -- 1 FunctionEntry + 2 branch points (1 branch + else)
              Map.size points @?= 3
              assertBool "IDs should be 0,1,2" (Map.keys points == [0, 1, 2]),
      testCase "missing region uses default (1,1)-(1,1)" $
        let g = mkGlobal "Main" "noregion"
            graph = Map.singleton g (Opt.Define funcExpr Set.empty)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph Map.empty
         in do
              Map.size points @?= 1
              case Map.lookup 0 points of
                Just pt -> Coverage._covRegion pt @?= mkRegion 1 1 1 1
                Nothing -> assertFailure "expected point at ID 0",
      testCase "non-Define/DefineTailFunc nodes produce no points" $
        let g = mkGlobal "Main" "port"
            graph = Map.singleton g (Opt.PortIncoming leafExpr Set.empty)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph Map.empty
         in Map.size points @?= 0
    ]

-- COVERAGE POINT TYPE TESTS

coveragePointTypeTests :: TestTree
coveragePointTypeTests =
  testGroup
    "CoveragePointType"
    [ testCase "FunctionEntry show" $
        show Coverage.FunctionEntry @?= "FunctionEntry",
      testCase "BranchArm show" $
        show (Coverage.BranchArm 0 3) @?= "BranchArm 0 3",
      testCase "TopLevelDef show" $
        show Coverage.TopLevelDef @?= "TopLevelDef",
      testCase "FunctionEntry equality" $
        Coverage.FunctionEntry @?= Coverage.FunctionEntry,
      testCase "BranchArm equality with same indices" $
        Coverage.BranchArm 1 2 @?= Coverage.BranchArm 1 2,
      testCase "BranchArm inequality with different indices" $
        assertBool "different branch arms" (Coverage.BranchArm 0 2 /= Coverage.BranchArm 1 2)
    ]

-- LCOV FORMAT TESTS

lcovFormatTests :: TestTree
lcovFormatTests =
  testGroup
    "toLCOV"
    [ testCase "empty map produces empty output" $
        renderBuilder (Coverage.toLCOV (Coverage.CoverageMap Map.empty) Map.empty) @?= "",
      testCase "FunctionEntry produces FN and FNDA lines" $
        let pt = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "foo") (mkRegion 5 1 10 1) Coverage.FunctionEntry dummyCanonical
            covMap = Coverage.CoverageMap (Map.singleton 0 pt)
            hits = Map.singleton 0 3
            result = renderBuilder (Coverage.toLCOV covMap hits)
         in do
              assertBool "contains FN:" ("FN:" `isInfixOf` result)
              assertBool "contains FNDA:" ("FNDA:" `isInfixOf` result)
              assertBool "contains hit count 3" ("FNDA:3," `isInfixOf` result),
      testCase "BranchArm produces BRDA line" $
        let pt = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "bar") (mkRegion 7 1 12 1) (Coverage.BranchArm 0 2) dummyCanonical
            covMap = Coverage.CoverageMap (Map.singleton 0 pt)
            hits = Map.singleton 0 5
            result = renderBuilder (Coverage.toLCOV covMap hits)
         in assertBool "contains BRDA:" ("BRDA:" `isInfixOf` result),
      testCase "TopLevelDef produces DA line" $
        let pt = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "x") (mkRegion 3 1 3 10) Coverage.TopLevelDef dummyCanonical
            covMap = Coverage.CoverageMap (Map.singleton 0 pt)
            hits = Map.singleton 0 1
            result = renderBuilder (Coverage.toLCOV covMap hits)
         in assertBool "contains DA:" ("DA:" `isInfixOf` result),
      testCase "missing hit defaults to 0" $
        let pt = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "foo") (mkRegion 5 1 10 1) Coverage.FunctionEntry dummyCanonical
            covMap = Coverage.CoverageMap (Map.singleton 0 pt)
            result = renderBuilder (Coverage.toLCOV covMap Map.empty)
         in assertBool "contains FNDA:0" ("FNDA:0," `isInfixOf` result)
    ]

-- ISTANBUL JSON TESTS

istanbulJsonTests :: TestTree
istanbulJsonTests =
  testGroup
    "toIstanbulJson"
    [ testCase "empty map produces JSON with empty submaps" $
        let json = Coverage.toIstanbulJson (Coverage.CoverageMap Map.empty) Map.empty
            rendered = renderBuilder (Encode.encode json)
         in do
              assertBool "contains fnMap" ("fnMap" `isInfixOf` rendered)
              assertBool "contains branchMap" ("branchMap" `isInfixOf` rendered)
              assertBool "contains statementMap" ("statementMap" `isInfixOf` rendered),
      testCase "FunctionEntry appears in fnMap and f" $
        let pt = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "foo") (mkRegion 5 1 10 1) Coverage.FunctionEntry dummyCanonical
            covMap = Coverage.CoverageMap (Map.singleton 0 pt)
            hits = Map.singleton 0 7
            rendered = renderBuilder (Encode.encode (Coverage.toIstanbulJson covMap hits))
         in do
              assertBool "fnMap has entry" ("fnMap" `isInfixOf` rendered)
              assertBool "qualified name Main.foo" ("Main.foo" `isInfixOf` rendered),
      testCase "BranchArm appears in branchMap and b" $
        let pt = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "bar") (mkRegion 7 1 12 1) (Coverage.BranchArm 0 2) dummyCanonical
            covMap = Coverage.CoverageMap (Map.singleton 0 pt)
            hits = Map.singleton 0 2
            rendered = renderBuilder (Encode.encode (Coverage.toIstanbulJson covMap hits))
         in assertBool "branchMap has entry" ("branchMap" `isInfixOf` rendered)
    ]

-- MODE COVERAGE ACCESSOR TESTS

devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

devModeWithCoverage :: Mode.Mode
devModeWithCoverage = Mode.Dev Nothing False False False Set.empty True

modeCoverageTests :: TestTree
modeCoverageTests =
  testGroup
    "Mode.isCoverage"
    [ testCase "Dev without coverage returns False" $
        Mode.isCoverage devMode @?= False,
      testCase "Dev with coverage returns True" $
        Mode.isCoverage devModeWithCoverage @?= True,
      testCase "coverage flag does not affect isDebug" $
        Mode.isDebug devModeWithCoverage @?= False,
      testCase "coverage flag does not affect isElmCompatible" $
        Mode.isElmCompatible devModeWithCoverage @?= False,
      testCase "coverage flag does not affect isFFIStrict" $
        Mode.isFFIStrict devModeWithCoverage @?= True,
      testCase "coverage flag does not affect isFFIDebug" $
        Mode.isFFIDebug devModeWithCoverage @?= False,
      testCase "Dev with FFI-unsafe and coverage" $
        let mode = Mode.Dev Nothing False True False Set.empty True
         in do
              Mode.isCoverage mode @?= True
              Mode.isFFIStrict mode @?= False,
      testCase "Dev with all flags set" $
        let mode = Mode.Dev Nothing True True True Set.empty True
         in do
              Mode.isCoverage mode @?= True
              Mode.isElmCompatible mode @?= True
              Mode.isFFIStrict mode @?= False
              Mode.isFFIDebug mode @?= True
    ]

-- GENERATE COV TESTS

generateCovTests :: TestTree
generateCovTests =
  testGroup
    "generateCov"
    [ testCase "generateCov on leaf does not increment counter" $
        let (_code, nextId) = Expr.generateCov devModeWithCoverage 0 leafExpr
         in nextId @?= 0,
      testCase "generateCov on Function increments counter by 1" $
        let (_, nextId) = Expr.generateCov devModeWithCoverage 0 funcExpr
         in nextId @?= 1,
      testCase "generateCov on nested Function increments counter by 2" $
        let nestedFunc = Opt.Function [nameStr "x"] funcExpr
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 nestedFunc
         in nextId @?= 2,
      testCase "generateCov on If with 2 branches increments counter by 3" $
        let (_, nextId) = Expr.generateCov devModeWithCoverage 0 ifExpr
         in nextId @?= 3,
      testCase "generateCov on If with 0 branches increments counter by 1" $
        let expr = Opt.If [] leafExpr
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 expr
         in nextId @?= 1,
      testCase "generateCov counter starts at given base" $
        let (_, nextId) = Expr.generateCov devModeWithCoverage 10 funcExpr
         in nextId @?= 11,
      testCase "generateCov on Let with function def counts def points" $
        let letExpr = Opt.Let (Opt.Def (nameStr "f") funcExpr) leafExpr
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 letExpr
         in nextId @?= 1,
      testCase "generateCov on Call recurses into func and args" $
        let callExpr = Opt.Call funcExpr [funcExpr]
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 callExpr
         in nextId @?= 2,
      testCase "generateCov on Function(If) accumulates all points" $
        let expr = Opt.Function [nameStr "x"] ifExpr
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 expr
         in nextId @?= 4
    ]

-- CASE INSTRUMENTATION TESTS

caseExpr2Jumps :: Opt.Expr
caseExpr2Jumps =
  Opt.Case (nameStr "l") (nameStr "r") (Opt.Leaf (Opt.Jump 0)) [(0, leafExpr), (1, leafExpr)]

caseInstrumentationTests :: TestTree
caseInstrumentationTests =
  testGroup
    "Case instrumentation"
    [ testCase "generateCov on Case with 2 jumps increments by 2" $
        let (_, nextId) = Expr.generateCov devModeWithCoverage 0 caseExpr2Jumps
         in nextId @?= 2,
      testCase "generateCov on Case with 0 jumps returns same counter" $
        let expr = Opt.Case (nameStr "l") (nameStr "r") (Opt.Leaf (Opt.Inline leafExpr)) []
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 expr
         in nextId @?= 0,
      testCase "generateCov on Case with function in jump accumulates points" $
        let expr = Opt.Case (nameStr "l") (nameStr "r") (Opt.Leaf (Opt.Jump 0)) [(0, funcExpr)]
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 expr
         in nextId @?= 2,
      testCase "Case counter IDs match buildCoverageMap" $
        let g = mkGlobal "Main" "caseFunc"
            expr = Opt.Function [nameStr "x"] caseExpr2Jumps
            graph = Map.singleton g (Opt.Define expr Set.empty)
            locs = Map.singleton g (mkRegion 1 1 10 1)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph locs
            (_, genCounter) = Expr.generateCov devModeWithCoverage 0 expr
         in do
              Map.size points @?= genCounter
              assertBool "IDs are sequential" (Map.keys points == [0 .. genCounter - 1])
    ]

-- LET DEF INSTRUMENTATION TESTS

letDefInstrumentationTests :: TestTree
letDefInstrumentationTests =
  testGroup
    "Let def instrumentation"
    [ testCase "Let with Def containing function includes function point" $
        let letExpr = Opt.Let (Opt.Def (nameStr "f") funcExpr) leafExpr
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 letExpr
         in nextId @?= 1,
      testCase "Let with TailDef containing function includes function point" $
        let letExpr = Opt.Let (Opt.TailDef (nameStr "f") [nameStr "a"] funcExpr) leafExpr
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 letExpr
         in nextId @?= 1,
      testCase "Let with nested if in def body counts all branch points" $
        let letExpr = Opt.Let (Opt.Def (nameStr "f") (Opt.Function [nameStr "x"] ifExpr)) leafExpr
            (_, nextId) = Expr.generateCov devModeWithCoverage 0 letExpr
         in nextId @?= 4
    ]

-- COUNTER ID CONSISTENCY TESTS

counterConsistencyTests :: TestTree
counterConsistencyTests =
  testGroup
    "Counter ID consistency"
    [ testCase "If with 3 branches: IDs 0,1,2,3 (3 branches + else)" $
        let expr = Opt.If [(Opt.Bool True, leafExpr), (Opt.Bool False, leafExpr), (Opt.Bool True, leafExpr)] leafExpr
            g = mkGlobal "Main" "ifFunc"
            graph = Map.singleton g (Opt.Define expr Set.empty)
            locs = Map.singleton g (mkRegion 1 1 10 1)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph locs
            (_, genCounter) = Expr.generateCov devModeWithCoverage 0 expr
         in do
              Map.size points @?= 4
              genCounter @?= 4
              Map.keys points @?= [0, 1, 2, 3],
      testCase "Case with 3 jumps: IDs 0,1,2" $
        let expr = Opt.Case (nameStr "l") (nameStr "r") (Opt.Leaf (Opt.Jump 0)) [(0, leafExpr), (1, leafExpr), (2, leafExpr)]
            g = mkGlobal "Main" "caseFunc"
            graph = Map.singleton g (Opt.Define expr Set.empty)
            locs = Map.singleton g (mkRegion 1 1 10 1)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph locs
            (_, genCounter) = Expr.generateCov devModeWithCoverage 0 expr
         in do
              Map.size points @?= 3
              genCounter @?= 3
              Map.keys points @?= [0, 1, 2],
      testCase "Function(If(Case)) all IDs sequential" $
        let innerCase = Opt.Case (nameStr "l") (nameStr "r") (Opt.Leaf (Opt.Jump 0)) [(0, leafExpr)]
            expr = Opt.Function [nameStr "x"] (Opt.If [(Opt.Bool True, innerCase)] leafExpr)
            g = mkGlobal "Main" "nested"
            graph = Map.singleton g (Opt.Define expr Set.empty)
            locs = Map.singleton g (mkRegion 1 1 10 1)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph locs
            (_, genCounter) = Expr.generateCov devModeWithCoverage 0 expr
         in do
              Map.size points @?= genCounter
              assertBool "no gaps in IDs" (Map.keys points == [0 .. genCounter - 1]),
      testCase "countExprPoints matches map size" $
        let expr = Opt.Function [nameStr "x"] (Opt.If [(Opt.Bool True, funcExpr)] leafExpr)
            g = mkGlobal "Main" "cep"
            graph = Map.singleton g (Opt.Define expr Set.empty)
            locs = Map.singleton g (mkRegion 1 1 10 1)
            Coverage.CoverageMap points = Coverage.buildCoverageMap graph locs
         in Coverage.countExprPoints expr @?= Map.size points
    ]

-- LCOV STRUCTURE TESTS

lcovStructureTests :: TestTree
lcovStructureTests =
  testGroup
    "LCOV structure"
    [ testCase "output contains TN: header" $
        let result = renderLcovWithFunction
         in assertBool "TN: line" ("TN:" `isInfixOf` result),
      testCase "output contains SF: with module name" $
        let result = renderLcovWithFunction
         in assertBool "SF:Main.can" ("SF:Main.can" `isInfixOf` result),
      testCase "output contains end_of_record" $
        let result = renderLcovWithFunction
         in assertBool "end_of_record" ("end_of_record" `isInfixOf` result),
      testCase "output contains FNF and FNH" $
        let result = renderLcovWithFunction
         in do
              assertBool "FNF:" ("FNF:" `isInfixOf` result)
              assertBool "FNH:" ("FNH:" `isInfixOf` result),
      testCase "output contains BRF and BRH" $
        let result = renderLcovWithBranch
         in do
              assertBool "BRF:" ("BRF:" `isInfixOf` result)
              assertBool "BRH:" ("BRH:" `isInfixOf` result),
      testCase "output contains LF and LH" $
        let result = renderLcovWithFunction
         in do
              assertBool "LF:" ("LF:" `isInfixOf` result)
              assertBool "LH:" ("LH:" `isInfixOf` result),
      testCase "multi-module output has separate records" $
        let pt1 = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "foo") (mkRegion 1 1 5 1) Coverage.FunctionEntry dummyCanonical
            pt2 = Coverage.CoveragePoint 1 (nameStr "Utils") (nameStr "bar") (mkRegion 2 1 8 1) Coverage.FunctionEntry dummyCanonical
            covMap = Coverage.CoverageMap (Map.fromList [(0, pt1), (1, pt2)])
            result = renderBuilder (Coverage.toLCOV covMap Map.empty)
         in do
              assertBool "SF:Main.can" ("SF:Main.can" `isInfixOf` result)
              assertBool "SF:Utils.can" ("SF:Utils.can" `isInfixOf` result)
              let recordCount = length (filter (== "end_of_record") (lines result))
              recordCount @?= 2
    ]
  where
    renderLcovWithFunction =
      let pt = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "foo") (mkRegion 5 1 10 1) Coverage.FunctionEntry dummyCanonical
          covMap = Coverage.CoverageMap (Map.singleton 0 pt)
       in renderBuilder (Coverage.toLCOV covMap (Map.singleton 0 3))
    renderLcovWithBranch =
      let pt = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "bar") (mkRegion 7 1 12 1) (Coverage.BranchArm 0 2) dummyCanonical
          covMap = Coverage.CoverageMap (Map.singleton 0 pt)
       in renderBuilder (Coverage.toLCOV covMap (Map.singleton 0 5))

-- ISTANBUL STRUCTURE TESTS

istanbulStructureTests :: TestTree
istanbulStructureTests =
  testGroup
    "Istanbul structure"
    [ testCase "all 6 required keys present" $
        let rendered = renderIstanbul
         in do
              assertBool "fnMap" ("fnMap" `isInfixOf` rendered)
              assertBool "f" ("\"f\"" `isInfixOf` rendered)
              assertBool "branchMap" ("branchMap" `isInfixOf` rendered)
              assertBool "b" ("\"b\"" `isInfixOf` rendered)
              assertBool "s" ("\"s\"" `isInfixOf` rendered)
              assertBool "statementMap" ("statementMap" `isInfixOf` rendered),
      testCase "function names are module-qualified" $
        let pt = Coverage.CoveragePoint 0 (nameStr "Utils") (nameStr "helper") (mkRegion 3 1 8 1) Coverage.FunctionEntry dummyCanonical
            covMap = Coverage.CoverageMap (Map.singleton 0 pt)
            rendered = renderBuilder (Encode.encode (Coverage.toIstanbulJson covMap Map.empty))
         in assertBool "Utils.helper" ("Utils.helper" `isInfixOf` rendered),
      testCase "loc objects have start/end with line/column" $
        let rendered = renderIstanbul
         in do
              assertBool "start" ("start" `isInfixOf` rendered)
              assertBool "end" ("end" `isInfixOf` rendered)
              assertBool "line" ("line" `isInfixOf` rendered)
              assertBool "column" ("column" `isInfixOf` rendered)
    ]
  where
    renderIstanbul =
      let pt = Coverage.CoveragePoint 0 (nameStr "Main") (nameStr "foo") (mkRegion 5 1 10 1) Coverage.FunctionEntry dummyCanonical
          covMap = Coverage.CoverageMap (Map.singleton 0 pt)
       in renderBuilder (Encode.encode (Coverage.toIstanbulJson covMap (Map.singleton 0 1)))

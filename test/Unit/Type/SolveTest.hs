{-# LANGUAGE OverloadedStrings #-}

-- | Comprehensive test suite for the Type.Solve module.
--
-- Tests the constraint solver's @run@ function, which takes a 'Constraint' and
-- produces either a list of type errors or a map of solved type annotations.
-- Each test constructs constraints from the Type.Type DSL (CTrue, CEqual, CAnd,
-- CLet, CPattern, etc.) and verifies that the solver correctly accepts valid
-- constraints and rejects invalid ones.
--
-- @since 0.19.2
module Unit.Type.SolveTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Type as Error
import Test.Tasty
import Test.Tasty.HUnit
import qualified Type.Solve as Solve
import Type.Type (Constraint (..), Type (..))
import qualified Type.Type as Type

-- HELPERS

-- | A standard region for test constraints, using row 1 col 1.
testRegion :: A.Region
testRegion =
  A.Region (A.Position 1 1) (A.Position 1 1)

-- | Build a CEqual constraint asserting two types should unify.
-- Uses 'Error.Number' as the category and 'Error.NoExpectation' wrapping
-- the expected type, which is the simplest form of equality constraint.
mkCEqual :: Type -> Type -> Constraint
mkCEqual actual expected =
  CEqual testRegion Error.Number actual (Error.NoExpectation expected)

-- | Build a CPattern constraint asserting two types should match in a pattern context.
mkCPattern :: Type -> Type -> Constraint
mkCPattern actual expected =
  CPattern testRegion Error.PInt actual (Error.PNoExpectation expected)

-- | Assert that a solve result is Right (success), ignoring the annotation map.
assertSolveSuccess :: Either a b -> IO ()
assertSolveSuccess result =
  assertBool "expected solver to succeed (Right)" (isRight result)

-- | Assert that a solve result is Left (failure), ignoring the error details.
assertSolveFailure :: Either a b -> IO ()
assertSolveFailure result =
  assertBool "expected solver to fail (Left)" (isLeft result)

-- | Assert that the solver produced a Right with an empty annotation map.
assertEmptyAnnotations :: Either a (Map Name.Name Can.Annotation) -> IO ()
assertEmptyAnnotations result =
  either
    (const (assertFailure "expected Right but got Left"))
    (\m -> Map.null m @?= True)
    result

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False

isLeft :: Either a b -> Bool
isLeft = not . isRight

-- TESTS

tests :: TestTree
tests =
  testGroup
    "Type.Solve Tests"
    [ cTrueTests,
      cSaveTheEnvironmentTests,
      cAndTests,
      cEqualTests,
      cCaseBranchesIsolatedTests,
      cLetTests,
      cPatternTests,
      compositeConstraintTests
    ]

-- CTRUE TESTS

cTrueTests :: TestTree
cTrueTests =
  testGroup
    "CTrue constraint"
    [ testCase "CTrue produces Right with empty annotations" $ do
        result <- Solve.run CTrue
        assertEmptyAnnotations result
    ]

-- CSAVETHEENVIRONMENT TESTS

cSaveTheEnvironmentTests :: TestTree
cSaveTheEnvironmentTests =
  testGroup
    "CSaveTheEnvironment constraint"
    [ testCase "CSaveTheEnvironment with empty env produces Right with empty annotations" $ do
        result <- Solve.run CSaveTheEnvironment
        assertEmptyAnnotations result
    ]

-- CAND TESTS

cAndTests :: TestTree
cAndTests =
  testGroup
    "CAnd constraint"
    [ testCase "CAnd [] produces Right" $ do
        result <- Solve.run (CAnd [])
        assertSolveSuccess result,
      testCase "CAnd [CTrue, CTrue] produces Right" $ do
        result <- Solve.run (CAnd [CTrue, CTrue])
        assertEmptyAnnotations result,
      testCase "CAnd with first constraint failing produces Left" $ do
        let mismatch = mkCEqual Type.int Type.string
        result <- Solve.run (CAnd [mismatch, CTrue])
        assertSolveFailure result
    ]

-- CEQUAL TESTS

cEqualTests :: TestTree
cEqualTests =
  testGroup
    "CEqual constraint"
    [ testCase "CEqual Int Int produces Right" $ do
        result <- Solve.run (mkCEqual Type.int Type.int)
        assertSolveSuccess result,
      testCase "CEqual Int String produces Left" $ do
        result <- Solve.run (mkCEqual Type.int Type.string)
        assertSolveFailure result,
      testCase "CEqual Unit Unit produces Right" $ do
        result <- Solve.run (mkCEqual UnitN UnitN)
        assertSolveSuccess result,
      testCase "CEqual (Int -> String) (Int -> String) produces Right" $ do
        let funType = FunN Type.int Type.string
        result <- Solve.run (mkCEqual funType funType)
        assertSolveSuccess result,
      testCase "CEqual (Int -> String) (Int -> Bool) produces Left" $ do
        let fun1 = FunN Type.int Type.string
        let fun2 = FunN Type.int Type.bool
        result <- Solve.run (mkCEqual fun1 fun2)
        assertSolveFailure result,
      testCase "multiple CEqual all matching produces Right" $ do
        let c1 = mkCEqual Type.int Type.int
        let c2 = mkCEqual Type.string Type.string
        let c3 = mkCEqual Type.bool Type.bool
        result <- Solve.run (CAnd [c1, c2, c3])
        assertSolveSuccess result,
      testCase "CEqual Float Float produces Right" $ do
        result <- Solve.run (mkCEqual Type.float Type.float)
        assertSolveSuccess result,
      testCase "CEqual Char Char produces Right" $ do
        result <- Solve.run (mkCEqual Type.char Type.char)
        assertSolveSuccess result,
      testCase "CEqual EmptyRecordN EmptyRecordN produces Right" $ do
        result <- Solve.run (mkCEqual EmptyRecordN EmptyRecordN)
        assertSolveSuccess result,
      testCase "CEqual (Tuple Int String) (Tuple Int String) produces Right" $ do
        let tup = TupleN Type.int Type.string Nothing
        result <- Solve.run (mkCEqual tup tup)
        assertSolveSuccess result,
      testCase "CEqual (Tuple Int String) (Tuple Int Bool) produces Left" $ do
        let tup1 = TupleN Type.int Type.string Nothing
        let tup2 = TupleN Type.int Type.bool Nothing
        result <- Solve.run (mkCEqual tup1 tup2)
        assertSolveFailure result
    ]

-- CCASEBRANCHESISOLATED TESTS

cCaseBranchesIsolatedTests :: TestTree
cCaseBranchesIsolatedTests =
  testGroup
    "CCaseBranchesIsolated constraint"
    [ testCase "CCaseBranchesIsolated [CTrue] produces Right" $ do
        result <- Solve.run (CCaseBranchesIsolated [CTrue])
        assertSolveSuccess result,
      testCase "CCaseBranchesIsolated [] produces Right" $ do
        result <- Solve.run (CCaseBranchesIsolated [])
        assertSolveSuccess result,
      testCase "CCaseBranchesIsolated with failing branch produces Left" $ do
        let bad = mkCEqual Type.int Type.string
        result <- Solve.run (CCaseBranchesIsolated [CTrue, bad])
        assertSolveFailure result
    ]

-- CLET TESTS

cLetTests :: TestTree
cLetTests =
  testGroup
    "CLet constraint"
    [ testCase "CLet with empty rigids/flexs and CTrue body produces Right" $ do
        let constraint = CLet
              { _rigidVars = []
              , _flexVars = []
              , _header = Map.empty
              , _headerCon = CTrue
              , _bodyCon = CTrue
              , _expectedType = Nothing
              }
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "CLet with flex var and CTrue header produces Right" $ do
        flexVar <- Type.mkFlexVar
        let constraint = CLet
              { _rigidVars = []
              , _flexVars = [flexVar]
              , _header = Map.empty
              , _headerCon = CTrue
              , _bodyCon = CTrue
              , _expectedType = Nothing
              }
        result <- Solve.run constraint
        assertSolveSuccess result
    ]

-- CPATTERN TESTS

cPatternTests :: TestTree
cPatternTests =
  testGroup
    "CPattern constraint"
    [ testCase "CPattern with matching types produces Right" $ do
        result <- Solve.run (mkCPattern Type.int Type.int)
        assertSolveSuccess result,
      testCase "CPattern with mismatched types produces Left" $ do
        result <- Solve.run (mkCPattern Type.int Type.string)
        assertSolveFailure result
    ]

-- COMPOSITE CONSTRAINT TESTS

compositeConstraintTests :: TestTree
compositeConstraintTests =
  testGroup
    "composite constraints"
    [ testCase "nested CAnd with all CTrue produces Right" $ do
        result <- Solve.run (CAnd [CAnd [CTrue, CTrue], CTrue])
        assertSolveSuccess result,
      testCase "CAnd with CEqual and CPattern both matching produces Right" $ do
        let eq = mkCEqual Type.int Type.int
        let pat = mkCPattern Type.string Type.string
        result <- Solve.run (CAnd [eq, pat])
        assertSolveSuccess result,
      testCase "CAnd with one mismatch among many produces Left" $ do
        let good1 = mkCEqual Type.int Type.int
        let good2 = mkCEqual Type.string Type.string
        let bad = mkCEqual Type.int Type.bool
        result <- Solve.run (CAnd [good1, good2, bad])
        assertSolveFailure result
    ]

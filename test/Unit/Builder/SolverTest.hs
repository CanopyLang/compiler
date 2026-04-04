
-- | Unit tests for Builder.Solver module.
--
-- Tests version parsing and constraint solving functionality.
--
-- @since 0.19.1
module Unit.Builder.SolverTest (tests) where

import qualified Builder.Solver as Solver
import qualified Canopy.Version as Version
import Test.Tasty
import Test.Tasty.HUnit

import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map

tests :: TestTree
tests =
  testGroup
    "Builder.Solver Tests"
    [ testVersionParsing,
      testConstraintParsing,
      testVersionComparison,
      testSatisfiesConstraint,
      testSolveConstraints,
      testVerifySolution
    ]

testVersionParsing :: TestTree
testVersionParsing =
  testGroup
    "version parsing via constraint tests"
    [ testCase "parse simple version via exact constraint" $
        case Solver.parseConstraint "==1.0.0" of
          Just (Solver.ExactVersion v) -> v @?= Version.Version 1 0 0
          _ -> assertFailure "Failed to parse ==1.0.0",
      testCase "parse multi-digit version" $
        case Solver.parseConstraint "==12.34.56" of
          Just (Solver.ExactVersion v) -> v @?= Version.Version 12 34 56
          _ -> assertFailure "Failed to parse ==12.34.56",
      testCase "parse zero version" $
        case Solver.parseConstraint "==0.0.0" of
          Just (Solver.ExactVersion v) -> v @?= Version.Version 0 0 0
          _ -> assertFailure "Failed to parse ==0.0.0",
      testCase "parse large version" $
        case Solver.parseConstraint "==999.888.777" of
          Just (Solver.ExactVersion v) -> v @?= Version.Version 999 888 777
          _ -> assertFailure "Failed to parse ==999.888.777",
      testCase "parse single digit version" $
        case Solver.parseConstraint ">=2.5.0" of
          Just (Solver.MinVersion v) -> v @?= Version.Version 2 5 0
          _ -> assertFailure "Failed to parse >=2.5.0",
      testCase "reject empty string" $
        Solver.parseConstraint "" @?= Nothing,
      testCase "reject invalid version format" $
        Solver.parseConstraint "==a.b.c" @?= Nothing,
      testCase "reject negative version" $
        Solver.parseConstraint "==-1.0.0" @?= Nothing
    ]

testConstraintParsing :: TestTree
testConstraintParsing =
  testGroup
    "constraint parsing tests"
    [ testCase "parse exact version constraint" $
        case Solver.parseConstraint "==2.5.0" of
          Just (Solver.ExactVersion v) -> v @?= Version.Version 2 5 0
          _ -> assertFailure "Expected ExactVersion constraint",
      testCase "parse minimum version constraint" $
        case Solver.parseConstraint ">=1.2.3" of
          Just (Solver.MinVersion v) -> v @?= Version.Version 1 2 3
          _ -> assertFailure "Expected MinVersion constraint",
      testCase "parse maximum version constraint" $
        case Solver.parseConstraint "<=3.4.5" of
          Just (Solver.MaxVersion v) -> v @?= Version.Version 3 4 5
          _ -> assertFailure "Expected MaxVersion constraint",
      testCase "parse range constraint" $
        case Solver.parseConstraint ">=1.0.0,<=2.0.0" of
          Just (Solver.RangeVersion minV maxV) -> do
            minV @?= Version.Version 1 0 0
            maxV @?= Version.Version 2 0 0
          _ -> assertFailure "Expected RangeVersion constraint",
      testCase "reject invalid constraint format" $
        Solver.parseConstraint "invalid" @?= Nothing,
      testCase "parse version without operator as exact" $
        case Solver.parseConstraint "1.0.0" of
          Just (Solver.ExactVersion v) -> v @?= Version.Version 1 0 0
          _ -> assertFailure "Expected ExactVersion for version without operator"
    ]

testVersionComparison :: TestTree
testVersionComparison =
  testGroup
    "version comparison tests"
    [ testCase "exact versions are equal" $ do
        let v1 = Version.Version 2 5 0
        let v2 = Version.Version 2 5 0
        v1 == v2 @? "Versions 2.5.0 and 2.5.0 should be equal",
      testCase "different versions not equal" $ do
        let v1 = Version.Version 2 5 0
        let v2 = Version.Version 2 5 1
        v1 /= v2 @? "Versions 2.5.0 and 2.5.1 should not be equal",
      testCase "version ordering - patch" $ do
        let v1 = Version.Version 1 0 0
        let v2 = Version.Version 1 0 1
        v1 < v2 @? "Version 1.0.0 should be less than 1.0.1",
      testCase "version ordering - minor" $ do
        let v1 = Version.Version 1 0 5
        let v2 = Version.Version 1 1 0
        v1 < v2 @? "Version 1.0.5 should be less than 1.1.0",
      testCase "version ordering - major" $ do
        let v1 = Version.Version 1 9 9
        let v2 = Version.Version 2 0 0
        v1 < v2 @? "Version 1.9.9 should be less than 2.0.0"
    ]

testSatisfiesConstraint :: TestTree
testSatisfiesConstraint =
  testGroup
    "satisfiesConstraint tests"
    [ testCase "AnyVersion is satisfied by any version" $
        Solver.satisfiesConstraint (Version.Version 3 2 1) Solver.AnyVersion @?= True,
      testCase "ExactVersion satisfied only by equal version" $
        Solver.satisfiesConstraint (Version.Version 1 0 0) (Solver.ExactVersion (Version.Version 1 0 0)) @?= True,
      testCase "ExactVersion not satisfied by different version" $
        Solver.satisfiesConstraint (Version.Version 1 0 1) (Solver.ExactVersion (Version.Version 1 0 0)) @?= False,
      testCase "MinVersion satisfied when version is greater" $
        Solver.satisfiesConstraint (Version.Version 2 0 0) (Solver.MinVersion (Version.Version 1 0 0)) @?= True,
      testCase "MinVersion satisfied by the minimum itself" $
        Solver.satisfiesConstraint (Version.Version 1 0 0) (Solver.MinVersion (Version.Version 1 0 0)) @?= True,
      testCase "MinVersion not satisfied when version is less" $
        Solver.satisfiesConstraint (Version.Version 0 9 9) (Solver.MinVersion (Version.Version 1 0 0)) @?= False,
      testCase "MaxVersion satisfied when version is less" $
        Solver.satisfiesConstraint (Version.Version 0 9 0) (Solver.MaxVersion (Version.Version 1 0 0)) @?= True,
      testCase "MaxVersion satisfied by the maximum itself" $
        Solver.satisfiesConstraint (Version.Version 1 0 0) (Solver.MaxVersion (Version.Version 1 0 0)) @?= True,
      testCase "MaxVersion not satisfied when version exceeds max" $
        Solver.satisfiesConstraint (Version.Version 1 0 1) (Solver.MaxVersion (Version.Version 1 0 0)) @?= False,
      testCase "RangeVersion satisfied by version within range" $
        Solver.satisfiesConstraint (Version.Version 1 5 0)
          (Solver.RangeVersion (Version.Version 1 0 0) (Version.Version 2 0 0)) @?= True,
      testCase "RangeVersion not satisfied below minimum" $
        Solver.satisfiesConstraint (Version.Version 0 9 0)
          (Solver.RangeVersion (Version.Version 1 0 0) (Version.Version 2 0 0)) @?= False,
      testCase "RangeVersion not satisfied above maximum" $
        Solver.satisfiesConstraint (Version.Version 2 0 1)
          (Solver.RangeVersion (Version.Version 1 0 0) (Version.Version 2 0 0)) @?= False
    ]

testSolveConstraints :: TestTree
testSolveConstraints =
  testGroup
    "solve constraint tests"
    [ testCase "empty constraints produce empty solution" $
        Solver.solve [] @?= Solver.SolverSuccess Map.empty,
      testCase "single exact version constraint resolves" $
        case Solver.solve [(Pkg.dummyName, [Solver.ExactVersion (Version.Version 1 2 3)])] of
          Solver.SolverSuccess sol ->
            Map.lookup Pkg.dummyName sol @?= Just (Version.Version 1 2 3)
          Solver.SolverFailure err ->
            assertFailure ("Expected success, got: " ++ show err),
      testCase "conflicting exact versions produce failure" $
        case Solver.solve
          [ (Pkg.dummyName,
              [ Solver.ExactVersion (Version.Version 1 0 0)
              , Solver.ExactVersion (Version.Version 2 0 0)
              ]) ] of
          Solver.SolverFailure _ -> return ()
          Solver.SolverSuccess sol ->
            assertFailure ("Expected failure, got: " ++ show sol),
      testCase "AnyVersion constraint resolves to a version" $
        case Solver.solve [(Pkg.dummyName, [Solver.AnyVersion])] of
          Solver.SolverSuccess sol ->
            Map.member Pkg.dummyName sol @?= True
          Solver.SolverFailure err ->
            assertFailure ("Expected success, got: " ++ show err)
    ]

testVerifySolution :: TestTree
testVerifySolution =
  testGroup
    "verifySolution tests"
    [ testCase "empty solution satisfies empty constraints" $
        Solver.verifySolution Map.empty [] @?= True,
      testCase "solution with correct version satisfies exact constraint" $
        let sol = Map.singleton Pkg.dummyName (Version.Version 1 0 0)
            constraints = [(Pkg.dummyName, [Solver.ExactVersion (Version.Version 1 0 0)])]
        in Solver.verifySolution sol constraints @?= True,
      testCase "solution with wrong version fails exact constraint" $
        let sol = Map.singleton Pkg.dummyName (Version.Version 2 0 0)
            constraints = [(Pkg.dummyName, [Solver.ExactVersion (Version.Version 1 0 0)])]
        in Solver.verifySolution sol constraints @?= False,
      testCase "solution missing a required package fails" $
        let sol = Map.empty
            constraints = [(Pkg.dummyName, [Solver.ExactVersion (Version.Version 1 0 0)])]
        in Solver.verifySolution sol constraints @?= False,
      testCase "solution satisfies AnyVersion constraint" $
        let sol = Map.singleton Pkg.dummyName (Version.Version 5 0 0)
            constraints = [(Pkg.dummyName, [Solver.AnyVersion])]
        in Solver.verifySolution sol constraints @?= True
    ]

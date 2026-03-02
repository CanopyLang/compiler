{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the Type.Variance module.
--
-- Verifies that variance annotations are correctly parsed, stored, and
-- checked during canonicalization. Covariant parameters must only appear
-- in positive (output) positions; contravariant parameters must only
-- appear in negative (input) positions.
--
-- @since 0.20.0
module Unit.Type.VarianceTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Type.Variance as Variance
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup "Type.Variance Tests"
    [ testGroup "Covariant parameter checks"
        [ testCovariantInPositive,
          testCovariantInNegative,
          testCovariantInReturnType,
          testCovariantInRecord
        ],
      testGroup "Contravariant parameter checks"
        [ testContravariantInPositive,
          testContravariantInNegative,
          testContravariantInFunctionArg
        ],
      testGroup "Invariant parameter checks"
        [ testInvariantInPositive,
          testInvariantInNegative
        ],
      testGroup "Nested function polarity"
        [ testDoubleNegation,
          testTripleNegation
        ],
      testGroup "Type constructors"
        [ testCovariantInTypeArg,
          testCovariantInTuple
        ],
      testGroup "Multiple parameters"
        [ testMixedVariance,
          testNoVarianceAnnotations
        ],
      testGroup "Union variance"
        [ testUnionCovariantValid,
          testUnionCovariantInvalid
        ],
      testGroup "Polarity type"
        [ testPolarityEq,
          testPolarityFlipViaDoubleNeg
        ],
      testGroup "AST Variance type"
        [ testVarianceEquality,
          testVarianceShow
        ],
      testGroup "Error position types"
        [ testVariancePositionShow
        ],
      testGroup "Edge cases"
        [ testCovariantInRecordWithFunction,
          testMixedVarianceWrongUsage,
          testContravariantInReturnType,
          testUnusedVarianceParam
        ]
    ]

-- | Test region used for all test cases.
testRegion :: Ann.Region
testRegion = Ann.Region (Ann.Position 1 1) (Ann.Position 1 20)

-- | A simple type variable reference.
tvar :: String -> Can.Type
tvar s = Can.TVar (Name.fromChars s)

-- | A function type: arg -> result.
tfun :: Can.Type -> Can.Type -> Can.Type
tfun = Can.TLambda

-- | A record type with a single field.
trecord :: String -> Can.Type -> Can.Type
trecord fieldName fieldType =
  Can.TRecord
    (Map.singleton (Name.fromChars fieldName) (Can.FieldType 0 fieldType))
    Nothing

-- HELPERS

-- | Run variance check and return whether it succeeded.
checkSucceeds :: [Name.Name] -> [Can.Variance] -> Can.Type -> Bool
checkSucceeds vars variances tipe =
  succeeded (Result.run (Variance.checkAliasVariance testRegion (Name.fromChars "Test") vars variances tipe))
  where
    succeeded (_, Right _) = True
    succeeded (_, Left _) = False

-- | Run variance check and return whether it produced errors.
checkFails :: [Name.Name] -> [Can.Variance] -> Can.Type -> Bool
checkFails vars variances tipe = not (checkSucceeds vars variances tipe)

-- COVARIANT TESTS

-- | Covariant parameter in a positive position (return type) is valid.
testCovariantInPositive :: TestTree
testCovariantInPositive = testCase "covariant in positive position succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Covariant]
      (tvar "a")

-- | Covariant parameter in a negative position (function argument) is invalid.
testCovariantInNegative :: TestTree
testCovariantInNegative = testCase "covariant in negative position fails" $
  assertBool "expected failure" $
    checkFails
      [Name.fromChars "a"]
      [Can.Covariant]
      (tfun (tvar "a") Can.TUnit)

-- | Covariant parameter in a function return type is valid.
testCovariantInReturnType :: TestTree
testCovariantInReturnType = testCase "covariant in function return type succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Covariant]
      (tfun Can.TUnit (tvar "a"))

-- | Covariant parameter in a record field is valid (positive position).
testCovariantInRecord :: TestTree
testCovariantInRecord = testCase "covariant in record field succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Covariant]
      (trecord "value" (tvar "a"))

-- CONTRAVARIANT TESTS

-- | Contravariant parameter in a positive position (return type) is invalid.
testContravariantInPositive :: TestTree
testContravariantInPositive = testCase "contravariant in positive position fails" $
  assertBool "expected failure" $
    checkFails
      [Name.fromChars "a"]
      [Can.Contravariant]
      (tvar "a")

-- | Contravariant parameter in a negative position (function argument) is valid.
testContravariantInNegative :: TestTree
testContravariantInNegative = testCase "contravariant in negative position succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Contravariant]
      (tfun (tvar "a") Can.TUnit)

-- | Contravariant parameter only in a function argument is valid.
testContravariantInFunctionArg :: TestTree
testContravariantInFunctionArg = testCase "contravariant only in function arg succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Contravariant]
      (tfun (tvar "a") (Can.TType ModuleName.basics (Name.fromChars "Int") []))

-- INVARIANT TESTS

-- | Invariant parameter in positive position is always valid.
testInvariantInPositive :: TestTree
testInvariantInPositive = testCase "invariant in positive position succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Invariant]
      (tvar "a")

-- | Invariant parameter in negative position is always valid.
testInvariantInNegative :: TestTree
testInvariantInNegative = testCase "invariant in negative position succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Invariant]
      (tfun (tvar "a") Can.TUnit)

-- NESTED FUNCTION POLARITY TESTS

-- | Double negation: argument of argument is positive.
-- In @(a -> ()) -> ()@, @a@ is in the argument of the outer argument,
-- which means polarity flips twice (negative then negative = positive).
-- So a covariant parameter should be valid here.
testDoubleNegation :: TestTree
testDoubleNegation = testCase "double negation makes positive (covariant valid)" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Covariant]
      (tfun (tfun (tvar "a") Can.TUnit) Can.TUnit)

-- | Triple negation: argument of argument of argument is negative.
-- So a covariant parameter should fail here.
testTripleNegation :: TestTree
testTripleNegation = testCase "triple negation makes negative (covariant invalid)" $
  assertBool "expected failure" $
    checkFails
      [Name.fromChars "a"]
      [Can.Covariant]
      (tfun (tfun (tfun (tvar "a") Can.TUnit) Can.TUnit) Can.TUnit)

-- TYPE CONSTRUCTOR TESTS

-- | Covariant parameter inside a type constructor argument is valid.
testCovariantInTypeArg :: TestTree
testCovariantInTypeArg = testCase "covariant in type constructor arg succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Covariant]
      (Can.TType ModuleName.list (Name.fromChars "List") [tvar "a"])

-- | Covariant parameter in a tuple is valid (positive position).
testCovariantInTuple :: TestTree
testCovariantInTuple = testCase "covariant in tuple succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Covariant]
      (Can.TTuple (tvar "a") Can.TUnit Nothing)

-- MULTIPLE PARAMETER TESTS

-- | Mixed variance: one covariant, one contravariant, used correctly.
testMixedVariance :: TestTree
testMixedVariance = testCase "mixed variance (covariant output, contravariant input) succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a", Name.fromChars "b"]
      [Can.Covariant, Can.Contravariant]
      (tfun (tvar "b") (tvar "a"))

-- | No variance annotations (all invariant) should always succeed.
testNoVarianceAnnotations :: TestTree
testNoVarianceAnnotations = testCase "no variance annotations always succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      []
      (tfun (tvar "a") (tvar "a"))

-- UNION VARIANCE TESTS

-- | Union with covariant param only in constructor output positions is valid.
testUnionCovariantValid :: TestTree
testUnionCovariantValid = testCase "union covariant param in output position succeeds" $
  assertUnionSucceeds typeName vars variances ctors
  where
    typeName = Name.fromChars "Box"
    vars = [Name.fromChars "a"]
    variances = [Can.Covariant]
    ctors = [Can.Ctor (Name.fromChars "Box") Index.first 1 [tvar "a"]]

-- | Union with covariant param in a function argument position is invalid.
testUnionCovariantInvalid :: TestTree
testUnionCovariantInvalid = testCase "union covariant param in input position fails" $
  assertUnionFails typeName vars variances ctors
  where
    typeName = Name.fromChars "Handler"
    vars = [Name.fromChars "a"]
    variances = [Can.Covariant]
    ctors = [Can.Ctor (Name.fromChars "Handler") Index.first 1 [tfun (tvar "a") Can.TUnit]]

-- POLARITY TESTS

-- | Polarity equality.
testPolarityEq :: TestTree
testPolarityEq = testCase "Polarity Eq instance" $ do
  Variance.Positive @?= Variance.Positive
  Variance.Negative @?= Variance.Negative
  assertBool "Positive /= Negative" (Variance.Positive /= Variance.Negative)

-- | Double negation confirms flip works: a contravariant param in
-- the argument of an argument (double flip = positive) should fail,
-- because contravariant requires negative position.
testPolarityFlipViaDoubleNeg :: TestTree
testPolarityFlipViaDoubleNeg = testCase "contravariant in double-negated position fails" $
  assertBool "expected failure (double flip = positive, contravariant needs negative)" $
    checkFails
      [Name.fromChars "a"]
      [Can.Contravariant]
      (tfun (tfun (tvar "a") Can.TUnit) Can.TUnit)

-- VARIANCE TYPE TESTS

-- | Variance Eq instance.
testVarianceEquality :: TestTree
testVarianceEquality = testCase "Variance Eq instance" $ do
  Can.Covariant @?= Can.Covariant
  Can.Contravariant @?= Can.Contravariant
  Can.Invariant @?= Can.Invariant
  assertBool "Covariant /= Contravariant" (Can.Covariant /= Can.Contravariant)
  assertBool "Covariant /= Invariant" (Can.Covariant /= Can.Invariant)

-- | Variance Show instance.
testVarianceShow :: TestTree
testVarianceShow = testCase "Variance Show instance" $ do
  show Can.Covariant @?= "Covariant"
  show Can.Contravariant @?= "Contravariant"
  show Can.Invariant @?= "Invariant"

-- ERROR POSITION TYPE TESTS

-- | VariancePosition Show instance.
testVariancePositionShow :: TestTree
testVariancePositionShow = testCase "VariancePosition Show instance" $ do
  show Error.NegativePosition @?= "NegativePosition"
  show Error.PositivePosition @?= "PositivePosition"

-- HELPERS

-- EDGE CASE TESTS

-- | Covariant param in a record where a field is a function returning the param.
-- The param is in a positive position (return of a function inside a record field).
testCovariantInRecordWithFunction :: TestTree
testCovariantInRecordWithFunction = testCase "covariant in record function return succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Covariant]
      (trecord "getter" (tfun Can.TUnit (tvar "a")))

-- | Mixed variance where covariant param incorrectly appears in input position.
testMixedVarianceWrongUsage :: TestTree
testMixedVarianceWrongUsage = testCase "mixed variance with covariant in input fails" $
  assertBool "expected failure" $
    checkFails
      [Name.fromChars "a", Name.fromChars "b"]
      [Can.Covariant, Can.Contravariant]
      (tfun (tvar "a") (tvar "b"))

-- | Contravariant param in return type (positive position) should fail.
testContravariantInReturnType :: TestTree
testContravariantInReturnType = testCase "contravariant in function return type fails" $
  assertBool "expected failure" $
    checkFails
      [Name.fromChars "a"]
      [Can.Contravariant]
      (tfun Can.TUnit (tvar "a"))

-- | A declared variance param that is not used in the body should pass
-- (no positions to violate).
testUnusedVarianceParam :: TestTree
testUnusedVarianceParam = testCase "unused covariant param succeeds" $
  assertBool "expected success" $
    checkSucceeds
      [Name.fromChars "a"]
      [Can.Covariant]
      Can.TUnit

-- | Assert that a union variance check succeeds.
assertUnionSucceeds :: Name.Name -> [Name.Name] -> [Can.Variance] -> [Can.Ctor] -> Assertion
assertUnionSucceeds typeName vars variances ctors =
  assertUnionResult True typeName vars variances ctors

-- | Assert that a union variance check fails.
assertUnionFails :: Name.Name -> [Name.Name] -> [Can.Variance] -> [Can.Ctor] -> Assertion
assertUnionFails typeName vars variances ctors =
  assertUnionResult False typeName vars variances ctors

-- | Run a union variance check and assert whether it should succeed or fail.
assertUnionResult :: Bool -> Name.Name -> [Name.Name] -> [Can.Variance] -> [Can.Ctor] -> Assertion
assertUnionResult expectSuccess typeName vars variances ctors =
  assertBool msg (isRight == expectSuccess)
  where
    (_, result) = Result.run (Variance.checkUnionVariance testRegion typeName vars variances ctors)
    isRight = either (const False) (const True) result
    msg
      | expectSuccess = "expected variance check to succeed"
      | otherwise = "expected variance check to fail"

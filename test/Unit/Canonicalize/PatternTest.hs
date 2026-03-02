{-# LANGUAGE OverloadedStrings #-}

{-|
Module: Unit.Canonicalize.PatternTest
Description: Tests for Canonicalize.Pattern duplicate variable detection
Copyright: (c) 2024 Canopy Contributors
License: BSD-3-Clause

Tests the pattern verification subsystem used during canonicalization.
The 'verify' function wraps a Result computation that accumulates pattern
variable bindings in a DupsDict, then checks for duplicates at the end.
This test suite exercises verify with hand-built Result values to confirm
that unique bindings succeed and duplicate bindings produce errors.

Coverage Target: >= 80% line coverage
Test Categories: Unit, Edge Case

@since 0.19.1
-}
module Unit.Canonicalize.PatternTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Canonicalize.Environment.Dups as Dups
import qualified Canonicalize.Pattern as Pattern
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result

-- | Top-level test tree for the Pattern module.
tests :: TestTree
tests = testGroup "Canonicalize.Pattern Tests"
  [ verifyNoBindingsTests
  , verifySingleBindingTests
  , verifyMultipleBindingsTests
  , verifyDuplicateTests
  , verifyErrorPropagationTests
  ]

-- | Extract a successful Right value from a Result run, or fail the test.
expectRight :: ([w], Either (OneOrMore.OneOrMore Error.Error) a) -> IO a
expectRight (_, Right val) = return val
expectRight (_, Left _) = assertFailure "Expected Right, got Left" >> error "unreachable"

-- | Extract an error Left value from a Result run, or fail the test.
expectLeft :: ([w], Either (OneOrMore.OneOrMore Error.Error) a) -> IO (OneOrMore.OneOrMore Error.Error)
expectLeft (_, Left errs) = return errs
expectLeft (_, Right _) = assertFailure "Expected Left, got Right" >> error "unreachable"

-- | Convenience region constructors for test data.
region1 :: Ann.Region
region1 = Ann.Region (Ann.Position 1 1) (Ann.Position 1 5)

region2 :: Ann.Region
region2 = Ann.Region (Ann.Position 2 1) (Ann.Position 2 5)

region3 :: Ann.Region
region3 = Ann.Region (Ann.Position 3 1) (Ann.Position 3 5)

-- | Build a Result that logs a single variable binding into the DupsDict.
--
-- This simulates what Pattern.canonicalize does internally when it encounters
-- a PVar pattern: it logs the variable name and region into the accumulated
-- DupsDict, then returns the given value.
logVar :: Name.Name -> Ann.Region -> a -> Result.Result Pattern.DupsDict w Error.Error a
logVar name region value =
  Result.Result (\bindings warnings _bad ok ->
    ok (Dups.insert name region region bindings) warnings value)

-- | Build a Result that logs multiple variable bindings and returns the final value.
logVars :: [(Name.Name, Ann.Region)] -> a -> Result.Result Pattern.DupsDict w Error.Error a
logVars [] value = Result.ok value
logVars ((name, region) : rest) value =
  logVar name region () *> logVars rest value

-- VERIFY WITH NO BINDINGS

verifyNoBindingsTests :: TestTree
verifyNoBindingsTests = testGroup "verify with no bindings"
  [ testCase "verify ok with no bindings returns value and empty map" $ do
      let inner = Result.ok "hello" :: Result.Result Pattern.DupsDict [Error.Error] Error.Error String
      (val, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch inner))
      val @?= "hello"
      bindings @?= Map.empty
  , testCase "verify ok with unit value and no bindings" $ do
      let inner = Result.ok () :: Result.Result Pattern.DupsDict [Error.Error] Error.Error ()
      (val, bindings) <- expectRight (Result.run (Pattern.verify Error.DPLambdaArgs inner))
      val @?= ()
      bindings @?= Map.empty
  ]

-- VERIFY WITH SINGLE BINDING

verifySingleBindingTests :: TestTree
verifySingleBindingTests = testGroup "verify with single binding"
  [ testCase "single variable binding succeeds with correct value" $ do
      let inner = logVar (Name.fromChars "x") region1 ("matched" :: String)
      (val, _) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch inner))
      val @?= ("matched" :: String)
  , testCase "single binding produces correct bindings map entry" $ do
      let name = Name.fromChars "myVar"
          inner = logVar name region1 (42 :: Int)
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch inner))
      Map.lookup name bindings @?= Just region1
  , testCase "single binding map has size 1" $ do
      let inner = logVar (Name.fromChars "a") region1 ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch inner))
      Map.size bindings @?= 1
  ]

-- VERIFY WITH MULTIPLE DISTINCT BINDINGS

verifyMultipleBindingsTests :: TestTree
verifyMultipleBindingsTests = testGroup "verify with multiple distinct bindings"
  [ testCase "two distinct variables succeed" $ do
      let inner = logVar (Name.fromChars "x") region1 ()
                    *> logVar (Name.fromChars "y") region2 "result"
      (val, _) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch inner))
      val @?= ("result" :: String)
  , testCase "two distinct variables produce bindings with size 2" $ do
      let inner = logVar (Name.fromChars "a") region1 ()
                    *> logVar (Name.fromChars "b") region2 ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch inner))
      Map.size bindings @?= 2
  , testCase "three distinct variables all appear in bindings" $ do
      let nameX = Name.fromChars "x"
          nameY = Name.fromChars "y"
          nameZ = Name.fromChars "z"
          inner = logVars [(nameX, region1), (nameY, region2), (nameZ, region3)] ("done" :: String)
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch inner))
      Map.member nameX bindings @?= True
      Map.member nameY bindings @?= True
      Map.member nameZ bindings @?= True
  , testCase "bindings map keys match logged variable names" $ do
      let names = map Name.fromChars ["alpha", "beta", "gamma"]
          regions = [region1, region2, region3]
          inner = logVars (zip names regions) ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch inner))
      Map.keys bindings @?= names
  ]

-- VERIFY WITH DUPLICATE BINDINGS

verifyDuplicateTests :: TestTree
verifyDuplicateTests = testGroup "verify detects duplicate bindings"
  [ testCase "duplicate variable name produces error" $ do
      let name = Name.fromChars "x"
          inner = logVar name region1 () *> logVar name region2 ("val" :: String)
      _ <- expectLeft (Result.run (Pattern.verify Error.DPCaseBranch inner))
      return ()
  , testCase "duplicate error is DuplicatePattern with correct name" $ do
      let name = Name.fromChars "dup"
          inner = logVar name region1 () *> logVar name region2 ()
      errs <- expectLeft (Result.run (Pattern.verify Error.DPCaseBranch inner))
      verifyDuplicatePatternError errs name
  , testCase "duplicate with DPFuncArgs context includes function name" $ do
      let funcName = Name.fromChars "myFunc"
          varName = Name.fromChars "arg"
          inner = logVar varName region1 () *> logVar varName region2 ()
      errs <- expectLeft (Result.run (Pattern.verify (Error.DPFuncArgs funcName) inner))
      verifyDuplicatePatternErrorWithContext errs varName (Error.DPFuncArgs funcName)
  , testCase "duplicate with DPLambdaArgs context" $ do
      let name = Name.fromChars "p"
          inner = logVar name region1 () *> logVar name region2 ()
      errs <- expectLeft (Result.run (Pattern.verify Error.DPLambdaArgs inner))
      verifyDuplicatePatternErrorWithContext errs name Error.DPLambdaArgs
  , testCase "duplicate among three bindings where first and third collide" $ do
      let nameA = Name.fromChars "a"
          nameB = Name.fromChars "b"
          inner = logVar nameA region1 ()
                    *> logVar nameB region2 ()
                    *> logVar nameA region3 ("val" :: String)
      _ <- expectLeft (Result.run (Pattern.verify Error.DPDestruct inner))
      return ()
  , testCase "DPLetBinding context on duplicate" $ do
      let name = Name.fromChars "binding"
          inner = logVar name region1 () *> logVar name region2 ()
      errs <- expectLeft (Result.run (Pattern.verify Error.DPLetBinding inner))
      verifyDuplicatePatternErrorWithContext errs name Error.DPLetBinding
  ]

-- VERIFY ERROR PROPAGATION

verifyErrorPropagationTests :: TestTree
verifyErrorPropagationTests = testGroup "verify propagates inner errors"
  [ testCase "inner error is propagated through verify" $ do
      let inner = Result.throw (Error.TupleLargerThanThree region1) :: Result.Result Pattern.DupsDict [Error.Error] Error.Error String
      errs <- expectLeft (Result.run (Pattern.verify Error.DPCaseBranch inner))
      verifyTupleTooLargeError errs
  , testCase "inner error takes precedence over bindings" $ do
      let inner = logVar (Name.fromChars "x") region1 ()
                    *> (Result.throw (Error.TupleLargerThanThree region2) :: Result.Result Pattern.DupsDict [Error.Error] Error.Error ())
      _ <- expectLeft (Result.run (Pattern.verify Error.DPCaseBranch inner))
      return ()
  ]

-- HELPERS

-- | Verify that an error collection contains a DuplicatePattern error with the expected name.
verifyDuplicatePatternError :: OneOrMore.OneOrMore Error.Error -> Name.Name -> Assertion
verifyDuplicatePatternError errs expectedName =
  let errList = OneOrMore.destruct (:) errs
  in case errList of
       (Error.DuplicatePattern _ name _ _ : _) ->
         name @?= expectedName
       other ->
         assertFailure ("Expected DuplicatePattern error, got: " ++ show other)

-- | Verify that an error collection contains a DuplicatePattern error with the expected name and context.
verifyDuplicatePatternErrorWithContext :: OneOrMore.OneOrMore Error.Error -> Name.Name -> Error.DuplicatePatternContext -> Assertion
verifyDuplicatePatternErrorWithContext errs expectedName expectedContext =
  let errList = OneOrMore.destruct (:) errs
  in case errList of
       (Error.DuplicatePattern ctx name _ _ : _) -> do
         name @?= expectedName
         show ctx @?= show expectedContext
       other ->
         assertFailure ("Expected DuplicatePattern error, got: " ++ show other)

-- | Verify that an error collection contains a TupleLargerThanThree error.
verifyTupleTooLargeError :: OneOrMore.OneOrMore Error.Error -> Assertion
verifyTupleTooLargeError errs =
  let errList = OneOrMore.destruct (:) errs
  in case errList of
       (Error.TupleLargerThanThree _ : _) -> return ()
       other ->
         assertFailure ("Expected TupleLargerThanThree error, got: " ++ show other)

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
import qualified Canonicalize.Module as Module
import qualified Canonicalize.Pattern as Pattern
import qualified Data.ByteString.Char8 as C8
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Canopy.Package as Pkg
import qualified Parse.Module as ParseModule
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning

-- | Top-level test tree for the Pattern module.
tests :: TestTree
tests = testGroup "Canonicalize.Pattern Tests"
  [ verifyNoBindingsTests
  , verifySingleBindingTests
  , verifyMultipleBindingsTests
  , verifyDuplicateTests
  , verifyErrorPropagationTests
  , verifyAsPatternTests
  , verifyNestedConstructorTests
  , verifyWildcardPositionTests
  , patternCanonicalizationTests
  , patternErrorTests
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

-- AS-PATTERN BINDING TESTS
--
-- An as-pattern @p@x@ binds both the outer alias name @x@ and any variables
-- inside the sub-pattern @p@.  We simulate this by logging both names.

verifyAsPatternTests :: TestTree
verifyAsPatternTests = testGroup "as-pattern (alias) bindings"
  [ testCase "as-pattern alias and inner variable are both bound" $ do
      let alias = Name.fromChars "whole"
          inner = Name.fromChars "part"
          computation = logVar inner region1 () *> logVar alias region2 ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch computation))
      Map.member alias bindings @?= True
      Map.member inner bindings @?= True
  , testCase "as-pattern alias duplicate with inner name produces error" $ do
      let name = Name.fromChars "x"
          computation = logVar name region1 () *> logVar name region2 ()
      _ <- expectLeft (Result.run (Pattern.verify Error.DPDestruct computation))
      return ()
  , testCase "as-pattern binding map has size 2 for distinct alias and inner" $ do
      let computation = logVar (Name.fromChars "all") region1 ()
                          *> logVar (Name.fromChars "head") region2 ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch computation))
      Map.size bindings @?= 2
  ]

-- NESTED CONSTRUCTOR PATTERN TESTS
--
-- Nested constructor patterns flatten into a single binding scope. All
-- sub-variables must be distinct within that scope.

verifyNestedConstructorTests :: TestTree
verifyNestedConstructorTests = testGroup "nested constructor patterns"
  [ testCase "two nested levels with unique names succeed" $ do
      let computation = logVars
            [(Name.fromChars "a", region1), (Name.fromChars "b", region2), (Name.fromChars "c", region3)]
            ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch computation))
      Map.size bindings @?= 3
  , testCase "nested collision between inner and outer produces error" $ do
      let name = Name.fromChars "val"
          computation = logVar name region1 () *> logVar name region3 ()
      _ <- expectLeft (Result.run (Pattern.verify Error.DPCaseBranch computation))
      return ()
  , testCase "three distinct nested names all appear in bindings" $ do
      let names = map Name.fromChars ["outer", "middle", "inner"]
          computation = logVars (zip names [region1, region2, region3]) ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch computation))
      all (`Map.member` bindings) names @?= True
  ]

-- WILDCARD PATTERN TESTS
--
-- Wildcard (@_@) patterns bind no names, so they produce no entries in the
-- DupsDict.  We verify this by running @verify@ with no variable logs.

verifyWildcardPositionTests :: TestTree
verifyWildcardPositionTests = testGroup "wildcard patterns in different positions"
  [ testCase "wildcard as sole pattern binds no names" $ do
      let computation = Result.ok () :: Result.Result Pattern.DupsDict [Error.Error] Error.Error ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch computation))
      Map.null bindings @?= True
  , testCase "wildcard alongside real variable leaves only real variable bound" $ do
      let name = Name.fromChars "x"
          computation = logVar name region1 ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPCaseBranch computation))
      Map.keys bindings @?= [name]
  , testCase "multiple wildcards with one real variable binds exactly one name" $ do
      let name = Name.fromChars "kept"
          computation = logVar name region2 ()
      (_, bindings) <- expectRight (Result.run (Pattern.verify Error.DPLambdaArgs computation))
      Map.size bindings @?= 1
      Map.member name bindings @?= True
  ]

-- PATTERN CANONICALIZATION TESTS (full pipeline)
--
-- These tests verify that specific pattern forms canonicalize without error
-- through the full source-to-canonical module pipeline, exercising
-- 'Pattern.canonicalize' in its natural context.

-- | Full-pipeline pattern canonicalization tests.
patternCanonicalizationTests :: TestTree
patternCanonicalizationTests = testGroup "pattern canonicalization via full pipeline"
  [ testCase "record pattern { x, y } canonicalizes" $
      expectSuccess (withHeader ["getX { x, y } = x"])

  , testCase "2-tuple pattern (a, b) canonicalizes" $
      expectSuccess (withHeader ["fst (a, _) = a"])

  , testCase "nested tuple pattern ((a, b), c) canonicalizes" $
      expectSuccess (withHeader ["extract ((a, _), _) = a"])

  , testCase "constructor pattern with arg canonicalizes" $
      expectSuccess (withHeader
        [ "type Wrapper a = Wrap a"
        , ""
        , "unwrap (Wrap n) = n"
        ])

  , testCase "list pattern [a, b] canonicalizes" $
      expectSuccess (withHeader
        [ "firstTwo xs ="
        , "  case xs of"
        , "    [a, b] -> a"
        , "    _ -> xs"
        ])

  , testCase "cons pattern x :: xs canonicalizes" $
      expectSuccess (withHeader
        [ "safeHead xs ="
        , "  case xs of"
        , "    x :: _ -> x"
        , "    [] -> 0"
        ])

  , testCase "Int literal pattern 42 canonicalizes" $
      expectSuccess (withHeader
        [ "isFortyTwo n ="
        , "  case n of"
        , "    42 -> 1"
        , "    _ -> 0"
        ])

  , testCase "wildcard pattern _ canonicalizes" $
      expectSuccess (withHeader ["ignore _ = 0"])

  , testCase "string literal pattern canonicalizes" $
      expectSuccess (withHeader
        [ "isHello s ="
        , "  case s of"
        , "    \"hello\" -> 1"
        , "    _ -> 0"
        ])
  ]

-- PATTERN ERROR TESTS

-- | Tests for pattern-related error conditions.
patternErrorTests :: TestTree
patternErrorTests = testGroup "pattern canonicalization error cases"
  [ testCase "duplicate var names in lambda args produces error" $ do
      let inner = logVar (Name.fromChars "x") region1 ()
                    *> logVar (Name.fromChars "x") region2 ("v" :: String)
      _ <- expectLeft (Result.run (Pattern.verify Error.DPLambdaArgs inner))
      return ()

  , testCase "duplicate var names in case branch produces error" $ do
      let inner = logVar (Name.fromChars "y") region1 ()
                    *> logVar (Name.fromChars "y") region2 ("v" :: String)
      _ <- expectLeft (Result.run (Pattern.verify Error.DPCaseBranch inner))
      return ()

  , testCase "constructor pattern with wrong arity produces error" $ do
      let src = withHeader
            [ "type Color = Red | Green | Blue"
            , ""
            , "check x ="
            , "  case x of"
            , "    Red _ -> True"
            , "    _ -> False"
            ]
      errs <- canonicalizeErrors src
      assertBool ("expected BadArity error, got: " ++ show errs) (not (null errs))

  , testCase "4-element tuple pattern produces TupleLargerThanThree error" $ do
      let inner = Result.throw (Error.TupleLargerThanThree region1)
                    :: Result.Result Pattern.DupsDict [Error.Error] Error.Error String
      errs <- expectLeft (Result.run (Pattern.verify Error.DPCaseBranch inner))
      verifyTupleTooLargeError errs
  ]

-- HELPERS

-- | Minimal module header for full-pipeline tests.
withHeader :: [String] -> String
withHeader bodyLines = unlines ("module M exposing (..)" : "" : bodyLines)

-- | Canonicalize source and return errors.
canonicalizeErrors :: String -> IO [Error.Error]
canonicalizeErrors src =
  case ParseModule.fromByteString (ParseModule.Package Pkg.core) (C8.pack src) of
    Left err -> assertFailure ("parse failed: " ++ show err) >> error "unreachable"
    Right m ->
      pure (extractErrors (Result.run (Module.canonicalize config Map.empty m)))
  where
    config = Module.CanonConfig Pkg.core (ParseModule.Package Pkg.core) Map.empty

-- | Canonicalize source expecting no errors.
expectSuccess :: String -> IO ()
expectSuccess src = do
  errs <- canonicalizeErrors src
  assertBool ("expected success, got: " ++ show errs) (null errs)

extractErrors :: ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) a) -> [Error.Error]
extractErrors (_, Left errs) = OneOrMore.destruct (:) errs
extractErrors (_, Right _) = []

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

{-# LANGUAGE OverloadedStrings #-}

{-|
Module: Unit.Canonicalize.DupsTest
Description: Tests for Canonicalize.Environment.Dups duplicate detection
Copyright: (c) 2024 Canopy Contributors
License: BSD-3-Clause

Tests the duplicate detection subsystem used during canonicalization to
detect duplicate names in declarations, patterns, record fields, and exports.
The Dups module provides a dictionary type that accumulates entries and can
detect when the same name has been registered multiple times.

Coverage Target: >= 80% line coverage
Test Categories: Unit, Edge Case

@since 0.19.1
-}
module Unit.Canonicalize.DupsTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Canonicalize.Environment.Dups as Dups
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Data.OneOrMore as OneOrMore
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result

-- | Top-level test tree for the Dups module.
tests :: TestTree
tests = testGroup "Canonicalize.Environment.Dups Tests"
  [ noneTests
  , oneTests
  , insertTests
  , unionTests
  , unionsTests
  , detectTests
  , checkFieldsTests
  ]

-- | Run a Result and extract the outcome, discarding warnings.
runResult :: Result.Result () [w] Error.Error a -> ([w], Either (OneOrMore.OneOrMore Error.Error) a)
runResult = Result.run

-- | Extract only the Right value from a successful Result run, or fail the test.
expectRight :: (Show a) => ([w], Either (OneOrMore.OneOrMore Error.Error) a) -> IO a
expectRight (_, Right val) = return val
expectRight (_, Left _) = assertFailure "Expected Right, got Left" >> error "unreachable"

-- | Assert that a Result run produced a Left (error).
expectLeft :: ([w], Either (OneOrMore.OneOrMore Error.Error) a) -> IO (OneOrMore.OneOrMore Error.Error)
expectLeft (_, Left errs) = return errs
expectLeft (_, Right _) = assertFailure "Expected Left, got Right" >> error "unreachable"

-- | A toError function that produces DuplicateDecl errors for detect.
toError :: Name.Name -> Ann.Region -> Ann.Region -> Error.Error
toError = Error.DuplicateDecl

-- | Convenience region constructors for test data.
region1 :: Ann.Region
region1 = Ann.Region (Ann.Position 1 1) (Ann.Position 1 5)

region2 :: Ann.Region
region2 = Ann.Region (Ann.Position 2 1) (Ann.Position 2 5)

region3 :: Ann.Region
region3 = Ann.Region (Ann.Position 3 1) (Ann.Position 3 5)

-- NONE TESTS

noneTests :: TestTree
noneTests = testGroup "none"
  [ testCase "none produces empty dictionary" $
      Map.null (Dups.none :: Dups.Dict Int) @?= True
  , testCase "detect on none returns empty map" $ do
      result <- expectRight (runResult (Dups.detect toError (Dups.none :: Dups.Dict Int)))
      result @?= Map.empty
  ]

-- ONE TESTS

oneTests :: TestTree
oneTests = testGroup "one"
  [ testCase "one creates singleton dict with correct key" $ do
      let dict = Dups.one (Name.fromChars "x") region1 (42 :: Int)
      Map.size dict @?= 1
      Map.member (Name.fromChars "x") dict @?= True
  , testCase "one value is recoverable through detect" $ do
      let dict = Dups.one (Name.fromChars "foo") region1 ("hello" :: String)
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.singleton (Name.fromChars "foo") "hello"
  , testCase "one preserves the given value exactly" $ do
      let dict = Dups.one (Name.fromChars "val") region1 (999 :: Int)
      result <- expectRight (runResult (Dups.detect toError dict))
      Map.lookup (Name.fromChars "val") result @?= Just 999
  ]

-- INSERT TESTS

insertTests :: TestTree
insertTests = testGroup "insert"
  [ testCase "insert into none creates single entry" $ do
      let dict = Dups.insert (Name.fromChars "a") region1 (1 :: Int) Dups.none
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.singleton (Name.fromChars "a") 1
  , testCase "insert different names creates distinct entries" $ do
      let dict = Dups.insert (Name.fromChars "b") region2 (2 :: Int)
                   (Dups.insert (Name.fromChars "a") region1 1 Dups.none)
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.fromList [(Name.fromChars "a", 1), (Name.fromChars "b", 2)]
  , testCase "insert same name twice causes duplicate detection" $ do
      let dict = Dups.insert (Name.fromChars "x") region2 (2 :: Int)
                   (Dups.insert (Name.fromChars "x") region1 1 Dups.none)
      _ <- expectLeft (runResult (Dups.detect toError dict))
      return ()
  , testCase "insert preserves existing entries when adding new name" $ do
      let base = Dups.one (Name.fromChars "existing") region1 (10 :: Int)
          dict = Dups.insert (Name.fromChars "new") region2 20 base
      result <- expectRight (runResult (Dups.detect toError dict))
      Map.size result @?= 2
  ]

-- UNION TESTS

unionTests :: TestTree
unionTests = testGroup "union"
  [ testCase "union of none with none is empty" $ do
      let dict = Dups.union (Dups.none :: Dups.Dict Int) Dups.none
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.empty
  , testCase "union of dict with none preserves dict" $ do
      let dict1 = Dups.one (Name.fromChars "a") region1 (1 :: Int)
          dict = Dups.union dict1 Dups.none
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.singleton (Name.fromChars "a") 1
  , testCase "union of disjoint dicts merges all entries" $ do
      let dict1 = Dups.one (Name.fromChars "a") region1 (1 :: Int)
          dict2 = Dups.one (Name.fromChars "b") region2 2
          dict = Dups.union dict1 dict2
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.fromList [(Name.fromChars "a", 1), (Name.fromChars "b", 2)]
  , testCase "union of overlapping dicts detects duplicates" $ do
      let dict1 = Dups.one (Name.fromChars "x") region1 (1 :: Int)
          dict2 = Dups.one (Name.fromChars "x") region2 2
          dict = Dups.union dict1 dict2
      _ <- expectLeft (runResult (Dups.detect toError dict))
      return ()
  ]

-- UNIONS TESTS

unionsTests :: TestTree
unionsTests = testGroup "unions"
  [ testCase "unions of empty list is empty" $ do
      let dict = Dups.unions ([] :: [Dups.Dict Int])
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.empty
  , testCase "unions of single dict returns that dict" $ do
      let dict1 = Dups.one (Name.fromChars "a") region1 (1 :: Int)
          dict = Dups.unions [dict1]
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.singleton (Name.fromChars "a") 1
  , testCase "unions merges three disjoint dicts" $ do
      let dict1 = Dups.one (Name.fromChars "a") region1 (1 :: Int)
          dict2 = Dups.one (Name.fromChars "b") region2 2
          dict3 = Dups.one (Name.fromChars "c") region3 3
          dict = Dups.unions [dict1, dict2, dict3]
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.fromList [(Name.fromChars "a", 1), (Name.fromChars "b", 2), (Name.fromChars "c", 3)]
  , testCase "unions detects duplicate across multiple dicts" $ do
      let dict1 = Dups.one (Name.fromChars "x") region1 (1 :: Int)
          dict2 = Dups.one (Name.fromChars "y") region2 2
          dict3 = Dups.one (Name.fromChars "x") region3 3
          dict = Dups.unions [dict1, dict2, dict3]
      _ <- expectLeft (runResult (Dups.detect toError dict))
      return ()
  ]

-- DETECT TESTS

detectTests :: TestTree
detectTests = testGroup "detect"
  [ testCase "detect with no duplicates returns all values" $ do
      let dict = Dups.insert (Name.fromChars "b") region2 ("two" :: String)
                   (Dups.one (Name.fromChars "a") region1 "one")
      result <- expectRight (runResult (Dups.detect toError dict))
      result @?= Map.fromList [(Name.fromChars "a", "one"), (Name.fromChars "b", "two")]
  , testCase "detect with duplicate returns error" $ do
      let dict = Dups.insert (Name.fromChars "dup") region2 ("second" :: String)
                   (Dups.one (Name.fromChars "dup") region1 "first")
      _ <- expectLeft (runResult (Dups.detect toError dict))
      return ()
  , testCase "detect error contains DuplicateDecl for the duplicate name" $ do
      let name = Name.fromChars "x"
          dict = Dups.insert name region2 (2 :: Int)
                   (Dups.one name region1 1)
      errs <- expectLeft (runResult (Dups.detect Error.DuplicateDecl dict))
      verifyDuplicateDeclError errs name
  , testCase "detect preserves key ordering in result map" $ do
      let dict = Dups.insert (Name.fromChars "c") region3 (3 :: Int)
                   (Dups.insert (Name.fromChars "a") region1 1
                     (Dups.one (Name.fromChars "b") region2 2))
      result <- expectRight (runResult (Dups.detect toError dict))
      Map.keys result @?= map Name.fromChars ["a", "b", "c"]
  , testCase "detect with five unique entries returns all five" $ do
      let names = map Name.fromChars ["a", "b", "c", "d", "e"]
          regions = map mkRegion [1..5]
          dict = foldr (\(n, r, v) acc -> Dups.insert n r v acc) Dups.none
                   (zip3 names regions [(1 :: Int)..5])
      result <- expectRight (runResult (Dups.detect toError dict))
      Map.size result @?= 5
  ]

-- CHECK FIELDS TESTS

checkFieldsTests :: TestTree
checkFieldsTests = testGroup "checkFields"
  [ testCase "checkFields with no fields returns empty map" $ do
      result <- expectRight (runResult (Dups.checkFields ([] :: [(Ann.Located Name.Name, Int)])))
      result @?= Map.empty
  , testCase "checkFields with unique fields returns all values" $ do
      let fields =
            [ (Ann.At region1 (Name.fromChars "name"), 1 :: Int)
            , (Ann.At region2 (Name.fromChars "age"), 2)
            ]
      result <- expectRight (runResult (Dups.checkFields fields))
      result @?= Map.fromList [(Name.fromChars "name", 1), (Name.fromChars "age", 2)]
  , testCase "checkFields with duplicate field names returns error" $ do
      let fields =
            [ (Ann.At region1 (Name.fromChars "name"), 1 :: Int)
            , (Ann.At region2 (Name.fromChars "name"), 2)
            ]
      _ <- expectLeft (runResult (Dups.checkFields fields))
      return ()
  , testCase "checkFields duplicate error is DuplicateField" $ do
      let name = Name.fromChars "x"
          fields =
            [ (Ann.At region1 name, 1 :: Int)
            , (Ann.At region2 name, 2)
            ]
      errs <- expectLeft (runResult (Dups.checkFields fields))
      verifyDuplicateFieldError errs name
  , testCase "checkFields with single field returns singleton map" $ do
      let fields = [(Ann.At region1 (Name.fromChars "only"), 42 :: Int)]
      result <- expectRight (runResult (Dups.checkFields fields))
      result @?= Map.singleton (Name.fromChars "only") 42
  , testCase "checkFields with three unique fields returns all" $ do
      let fields =
            [ (Ann.At region1 (Name.fromChars "x"), 10 :: Int)
            , (Ann.At region2 (Name.fromChars "y"), 20)
            , (Ann.At region3 (Name.fromChars "z"), 30)
            ]
      result <- expectRight (runResult (Dups.checkFields fields))
      Map.size result @?= 3
  ]

-- HELPERS

-- | Create a region at a given line number.
mkRegion :: Int -> Ann.Region
mkRegion n = Ann.Region (Ann.Position (fromIntegral n) 1) (Ann.Position (fromIntegral n) 5)

-- | Verify that an error collection contains a DuplicateDecl error for the given name.
verifyDuplicateDeclError :: OneOrMore.OneOrMore Error.Error -> Name.Name -> Assertion
verifyDuplicateDeclError errs expectedName =
  let errList = OneOrMore.destruct (:) errs
  in case errList of
       (Error.DuplicateDecl name _ _ : _) ->
         name @?= expectedName
       other ->
         assertFailure ("Expected DuplicateDecl error, got: " ++ show other)

-- | Verify that an error collection contains a DuplicateField error for the given name.
verifyDuplicateFieldError :: OneOrMore.OneOrMore Error.Error -> Name.Name -> Assertion
verifyDuplicateFieldError errs expectedName =
  let errList = OneOrMore.destruct (:) errs
  in case errList of
       (Error.DuplicateField name _ _ : _) ->
         name @?= expectedName
       other ->
         assertFailure ("Expected DuplicateField error, got: " ++ show other)

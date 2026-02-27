{-# LANGUAGE OverloadedStrings #-}

-- | Property.Data.NameProperties - Property-based tests for Data.Name
--
-- This module provides property-based tests for the Name module, verifying
-- that fundamental operations maintain their invariants:
--
-- * fromChars/toChars roundtrip: converting to a Name and back recovers the original string
-- * hasDot correctly detects the presence of '.' characters
-- * Names without dots report hasDot as False
-- * splitDots produces correct number of segments
-- * splitDots segments rejoin to the original name
--
-- These properties ensure that the Name type, which underpins all identifier
-- handling in the compiler, behaves correctly for arbitrary inputs.
--
-- @since 0.19.1
module Property.Data.NameProperties
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Data.List as List
import qualified Data.Name as Name

-- | Main test tree containing all Name property tests.
tests :: TestTree
tests = testGroup "Name Property Tests"
  [ roundtripProperties
  , hasDotProperties
  , splitDotsProperties
  , constantsProperties
  , fromCharsProperties
  ]

-- | Verifies that fromChars and toChars are inverse operations.
--
-- This is the most fundamental property of the Name type: any string
-- that is converted to a Name and back must yield the original string.
-- This property is tested across a variety of string shapes.
roundtripProperties :: TestTree
roundtripProperties = testGroup "fromChars/toChars Roundtrip"
  [ testProperty "roundtrip preserves ASCII strings" $
      forAll genAsciiIdentifier $ \s ->
        Name.toChars (Name.fromChars s) === s

  , testProperty "roundtrip preserves empty string" $
      Name.toChars (Name.fromChars "") === ""

  , testProperty "roundtrip preserves single character" $
      forAll (elements ['a'..'z']) $ \c ->
        Name.toChars (Name.fromChars [c]) === [c]

  , testProperty "roundtrip preserves dotted names" $
      forAll genDottedName $ \s ->
        Name.toChars (Name.fromChars s) === s

  , testProperty "roundtrip preserves alphanumeric strings" $
      forAll genAlphaNumString $ \s ->
        Name.toChars (Name.fromChars s) === s
  ]

-- | Verifies that hasDot correctly detects '.' in names.
--
-- A name has a dot if and only if the underlying string contains the
-- character '.'. This property cross-checks hasDot against the standard
-- library elem function.
hasDotProperties :: TestTree
hasDotProperties = testGroup "hasDot Detection"
  [ testProperty "hasDot True when string contains dot" $
      forAll genDottedName $ \s ->
        Name.hasDot (Name.fromChars s) === True

  , testProperty "hasDot False when no dot present" $
      forAll genNoDotString $ \s ->
        Name.hasDot (Name.fromChars s) === False

  , testProperty "hasDot agrees with elem check" $
      forAll genAsciiIdentifier $ \s ->
        Name.hasDot (Name.fromChars s) === ('.' `elem` s)

  , testProperty "single dot name has dot" $
      Name.hasDot (Name.fromChars ".") === True

  , testProperty "hasDot detects dot at any position" $
      forAll genDotAtPosition $ \s ->
        Name.hasDot (Name.fromChars s) === True
  ]

-- | Verifies that splitDots produces correct segments for dotted names.
--
-- The number of segments from splitDots should be one more than the
-- number of dots in the original string, and joining them back with
-- dots should recover the original.
splitDotsProperties :: TestTree
splitDotsProperties = testGroup "splitDots Properties"
  [ testProperty "splitDots count matches dot count plus one" $
      forAll genDottedName $ \s ->
        let parts = Name.splitDots (Name.fromChars s)
            dotCount = length (filter (== '.') s)
        in length parts === dotCount + 1

  , testProperty "splitDots of no-dot name is singleton" $
      forAll genNoDotString $ \s ->
        not (null s) ==>
          length (Name.splitDots (Name.fromChars s)) === 1

  , testProperty "splitDots segments rejoin to original" $
      forAll genDottedName $ \s ->
        let parts = Name.splitDots (Name.fromChars s)
            rejoined = List.intercalate "." (fmap Name.toChars parts)
        in rejoined === s

  , testProperty "splitDots of Module.Name gives two parts" $
      forAll genTwoPartName $ \s ->
        length (Name.splitDots (Name.fromChars s)) === 2

  , testProperty "splitDots of A.B.C gives three parts" $
      forAll genThreePartName $ \s ->
        length (Name.splitDots (Name.fromChars s)) === 3
  ]

-- | Verifies properties of predefined name constants.
--
-- The constants module provides well-known names used throughout the
-- compiler. These tests verify their string representations are correct
-- and consistent.
constantsProperties :: TestTree
constantsProperties = testGroup "Constants Properties"
  [ testProperty "int constant roundtrips" $
      Name.toChars Name.int === "Int"

  , testProperty "float constant roundtrips" $
      Name.toChars Name.float === "Float"

  , testProperty "bool constant roundtrips" $
      Name.toChars Name.bool === "Bool"

  , testProperty "string constant roundtrips" $
      Name.toChars Name.string === "String"

  , testProperty "true constant roundtrips" $
      Name.toChars Name.true === "True"

  , testProperty "false constant roundtrips" $
      Name.toChars Name.false === "False"

  , testProperty "_main constant roundtrips" $
      Name.toChars Name._main === "main"
  ]

-- | Verifies properties of the fromChars function for various inputs.
--
-- This group tests that fromChars handles a variety of input patterns
-- correctly, including edge cases.
fromCharsProperties :: TestTree
fromCharsProperties = testGroup "fromChars Properties"
  [ testProperty "fromChars produces consistent equality" $
      forAll genAsciiIdentifier $ \s ->
        Name.fromChars s == Name.fromChars s

  , testProperty "different strings produce different names" $
      forAll genDistinctPair $ \(s1, s2) ->
        Name.fromChars s1 /= Name.fromChars s2

  , testProperty "fromChars preserves string length via toChars" $
      forAll genAsciiIdentifier $ \s ->
        length (Name.toChars (Name.fromChars s)) === length s

  , testProperty "consecutive fromChars calls are independent" $
      forAll genAsciiIdentifier $ \s ->
        let n1 = Name.fromChars s
            n2 = Name.fromChars s
        in Name.toChars n1 === Name.toChars n2

  , testProperty "empty fromChars produces empty toChars" $
      Name.toChars (Name.fromChars "") === ""
  ]

-- GENERATORS

-- | Generate ASCII identifier strings (letters, digits, underscores, dots).
genAsciiIdentifier :: Gen String
genAsciiIdentifier =
  listOf1 (elements identChars)
  where
    identChars = ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '.']

-- | Generate a dotted name like "Foo.Bar" or "A.B.C".
genDottedName :: Gen String
genDottedName = do
  n <- choose (2, 4 :: Int)
  parts <- vectorOf n genSegment
  pure (List.intercalate "." parts)

-- | Generate a string that contains no dots.
genNoDotString :: Gen String
genNoDotString =
  listOf1 (elements noDotChars)
  where
    noDotChars = ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_']

-- | Generate an alphanumeric string.
genAlphaNumString :: Gen String
genAlphaNumString =
  listOf1 (elements (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9']))

-- | Generate a string with a dot at some position, surrounded by letters.
genDotAtPosition :: Gen String
genDotAtPosition = do
  before <- listOf1 (elements ['a'..'z'])
  after <- listOf1 (elements ['a'..'z'])
  pure (before ++ "." ++ after)

-- | Generate a two-part dotted name like "Module.Name".
genTwoPartName :: Gen String
genTwoPartName = do
  p1 <- genSegment
  p2 <- genSegment
  pure (p1 ++ "." ++ p2)

-- | Generate a three-part dotted name like "A.B.C".
genThreePartName :: Gen String
genThreePartName = do
  p1 <- genSegment
  p2 <- genSegment
  p3 <- genSegment
  pure (p1 ++ "." ++ p2 ++ "." ++ p3)

-- | Generate a pair of distinct non-empty ASCII strings.
genDistinctPair :: Gen (String, String)
genDistinctPair = do
  s1 <- listOf1 (elements ['a'..'z'])
  s2 <- listOf1 (elements ['a'..'z'])
  if s1 == s2
    then pure (s1, s1 ++ "x")
    else pure (s1, s2)

-- | Generate a single identifier segment (no dots).
genSegment :: Gen String
genSegment = do
  first <- elements ['A'..'Z']
  rest <- listOf (elements (['a'..'z'] ++ ['0'..'9']))
  pure (first : rest)

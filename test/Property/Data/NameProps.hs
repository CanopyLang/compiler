module Property.Data.NameProps (tests) where

import qualified Data.Name as Name
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "Data.Name Property Tests"
    [ testFromCharsToCharsRoundtrip,
      testHasDotConsistency,
      testSplitDotsProperties
    ]

-- Generator for valid identifier strings
genValidIdentifier :: Gen String
genValidIdentifier = do
  first <- elements ['a' .. 'z']
  rest <- listOf (elements (['a' .. 'z'] ++ ['A' .. 'Z'] ++ ['0' .. '9'] ++ "_"))
  return (first : rest)

-- Generator for module-qualified names
genQualifiedName :: Gen String
genQualifiedName = do
  modules <- listOf1 genValidIdentifier
  return $ concat $ zipWith (++) modules (repeat ".")

testFromCharsToCharsRoundtrip :: TestTree
testFromCharsToCharsRoundtrip = testProperty "fromChars/toChars roundtrip" $
  forAll genValidIdentifier $ \str ->
    let name = Name.fromChars str
     in Name.toChars name == str

testHasDotConsistency :: TestTree
testHasDotConsistency =
  testGroup
    "hasDot consistency properties"
    [ testProperty "hasDot true iff contains dot" $
        forAll (arbitrary :: Gen String) $ \str ->
          let name = Name.fromChars str
              hasDot = Name.hasDot name
              containsDot = '.' `elem` str
           in hasDot == containsDot,
      testProperty "qualified names have dots" $
        forAll genQualifiedName $ \str ->
          let name = Name.fromChars str
           in Name.hasDot name
    ]

testSplitDotsProperties :: TestTree
testSplitDotsProperties =
  testGroup
    "splitDots properties"
    [ testProperty "splitDots never returns empty list" $
        forAll (arbitrary :: Gen String) $ \str ->
          let name = Name.fromChars str
              parts = Name.splitDots name
           in not (null parts),
      testProperty "single names split to singleton" $
        forAll genValidIdentifier $ \str ->
          let name = Name.fromChars str
              parts = Name.splitDots name
              singleName = Name.fromChars str
           in if Name.hasDot name
                then length parts > 1
                else parts == [singleName]
    ]

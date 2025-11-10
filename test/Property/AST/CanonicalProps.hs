module Property.AST.CanonicalProps (tests) where

import qualified AST.Canonical as Can
import qualified Data.Map as Map
import qualified Data.Name as Name
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "AST.Canonical Property Tests"
    [ testFieldsToListSorted,
      testFieldsToListStableNames
    ]

-- Generators

genName :: Gen Name.Name
genName = do
  first <- elements ['a' .. 'z']
  rest <- listOf (elements (['a' .. 'z'] <> (['A' .. 'Z'] <> ['0' .. '9'])))
  pure (Name.fromChars (first : rest))

genUniqueNames :: Gen [Name.Name]
genUniqueNames = do
  names <- listOf1 genName
  pure (take 10 (nubByEq names))

nubByEq :: [Name.Name] -> [Name.Name]
nubByEq = go []
  where
    go acc [] = reverse acc
    go acc (x : xs)
      | any (\y -> Name.toChars y == Name.toChars x) acc = go acc xs
      | otherwise = go (x : acc) xs

genFieldMap :: Gen (Map.Map Name.Name Can.FieldType)
genFieldMap = do
  ns <- genUniqueNames
  idxs <- vectorOf (length ns) (choose (0, 20))
  let toField i = Can.FieldType (fromIntegral (i :: Int)) Can.TUnit
  pure $ Map.fromList (zip ns (fmap toField idxs))

-- Properties

testFieldsToListSorted :: TestTree
testFieldsToListSorted =
  testProperty "fieldsToList outputs ascending by index" . forAll genFieldMap $
    ( \m ->
        let idxs = fmap (\(n, _) -> let Can.FieldType i _ = m Map.! n in i) (Can.fieldsToList m)
         in idxs == sort idxs
    )

testFieldsToListStableNames :: TestTree
testFieldsToListStableNames =
  testProperty "fieldsToList preserves key set" . forAll genFieldMap $
    ( \m ->
        let namesOut = fmap fst (Can.fieldsToList m)
            namesIn = Map.keys m
            toS = fmap Name.toChars
         in sort (toS namesOut) == sort (toS namesIn)
    )

-- Local helpers
sort :: Ord a => [a] -> [a]
sort = qsort
  where
    qsort [] = []
    qsort (p : xs) = (qsort [x | x <- xs, x <= p]) <> ([p] <> qsort [x | x <- xs, x > p])

module Property.Canopy.VersionProps (tests) where

import qualified Canopy.Version as V
import Test.QuickCheck
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "Canopy.Version Property Tests"
    [ testVersionOrdering,
      testVersionBumpingProperties,
      testToCharsProperties
    ]

-- Generator for valid versions
genVersion :: Gen V.Version
genVersion = do
  major <- choose (0, 999)
  minor <- choose (0, 999)
  patch <- choose (0, 999)
  return $ V.Version major minor patch

instance Arbitrary V.Version where
  arbitrary = genVersion

testVersionOrdering :: TestTree
testVersionOrdering =
  testGroup
    "version ordering properties"
    [ testProperty "version ordering is transitive" $
        \v1 v2 v3 -> (v1 <= v2 && v2 <= v3) ==> (v1 <= (v3 :: V.Version)),
      testProperty "version ordering is reflexive" $
        \v -> v <= (v :: V.Version),
      testProperty "version ordering is antisymmetric" $
        \v -> v <= (v :: V.Version) && (v :: V.Version) <= v ==> v == (v :: V.Version)
    ]

testVersionBumpingProperties :: TestTree
testVersionBumpingProperties =
  testGroup
    "version bumping properties"
    [ testProperty "bumpPatch increases patch by 1" $
        \v ->
          let V.Version maj min pat = v
              V.Version maj' min' pat' = V.bumpPatch v
           in maj == maj' && min == min' && pat' == pat + 1,
      testProperty "bumpMinor increases minor by 1 and resets patch" $
        \v ->
          let V.Version maj min _pat = v
              V.Version maj' min' pat' = V.bumpMinor v
           in maj == maj' && min' == min + 1 && pat' == 0,
      testProperty "bumpMajor increases major by 1 and resets others" $
        \v ->
          let V.Version maj _min _pat = v
              V.Version maj' min' pat' = V.bumpMajor v
           in maj' == maj + 1 && min' == 0 && pat' == 0,
      testProperty "bumping always increases version" $
        \v ->
          let patched = V.bumpPatch v
              minored = V.bumpMinor v
              majored = V.bumpMajor v
           in v < patched && v < minored && v < majored
    ]

testToCharsProperties :: TestTree
testToCharsProperties =
  testGroup
    "toChars properties"
    [ testProperty "toChars always contains two dots" $
        \v ->
          let chars = V.toChars v
              dotCount = length $ filter (== '.') chars
           in dotCount == 2,
      testProperty "toChars never starts or ends with dot" $
        \v ->
          let chars = V.toChars v
           in not (null chars)
                ==> case (chars, reverse chars) of
                  (first : _, last : _) -> first /= '.' && last /= '.'
                  _ -> True,
      testProperty "toChars contains only digits and dots" $
        \v ->
          let chars = V.toChars v
              validChars = ['0' .. '9'] ++ "."
           in all (`elem` validChars) chars,
      testProperty "toChars format is X.Y.Z" $
        \v ->
          let chars = V.toChars v
              parts = splitOn '.' chars
           in length parts == 3 && all (not . null) parts
    ]

-- Helper function to split on character
splitOn :: Char -> String -> [String]
splitOn _ [] = [""]
splitOn c (x : xs)
  | x == c = "" : splitOn c xs
  | otherwise = let (y : ys) = splitOn c xs in (x : y) : ys

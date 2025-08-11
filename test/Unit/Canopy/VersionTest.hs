module Unit.Canopy.VersionTest (tests) where

import qualified Canopy.Version as V
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Canopy.Version Tests"
    [ testVersionCreation,
      testVersionComparison,
      testVersionBumping,
      testVersionToChars
    ]

testVersionCreation :: TestTree
testVersionCreation =
  testGroup
    "version creation tests"
    [ testCase "version one" $ do
        let v = V.one
        V.toChars v @?= "1.0.0",
      testCase "version max" $ do
        let v = V.max
        -- Check that max version has reasonable values
        let chars = V.toChars v
        length chars > 5 @? "Max version should have a reasonable string representation"
    ]

testVersionComparison :: TestTree
testVersionComparison =
  testGroup
    "version comparison tests"
    [ testCase "version equality" $ do
        let v1 = V.Version 1 0 0
        let v2 = V.Version 1 0 0
        v1 == v2 @? "Same versions should be equal",
      testCase "version ordering" $ do
        let v1 = V.Version 1 0 0
        let v2 = V.Version 1 0 1
        let v3 = V.Version 1 1 0
        let v4 = V.Version 2 0 0

        v1 < v2 @? "Patch version ordering"
        v1 < v3 @? "Minor version ordering"
        v1 < v4 @? "Major version ordering"
        v2 < v3 @? "Mixed version ordering"
    ]

testVersionBumping :: TestTree
testVersionBumping =
  testGroup
    "version bumping tests"
    [ testCase "bump patch" $ do
        let v = V.Version 1 2 3
        let bumped = V.bumpPatch v
        bumped @?= V.Version 1 2 4,
      testCase "bump minor" $ do
        let v = V.Version 1 2 3
        let bumped = V.bumpMinor v
        bumped @?= V.Version 1 3 0,
      testCase "bump major" $ do
        let v = V.Version 1 2 3
        let bumped = V.bumpMajor v
        bumped @?= V.Version 2 0 0
    ]

testVersionToChars :: TestTree
testVersionToChars =
  testGroup
    "version to string tests"
    [ testCase "simple version" $ do
        let v = V.Version 1 2 3
        V.toChars v @?= "1.2.3",
      testCase "zero version" $ do
        let v = V.Version 0 0 0
        V.toChars v @?= "0.0.0",
      testCase "large numbers" $ do
        let v = V.Version 10 20 30
        V.toChars v @?= "10.20.30"
    ]

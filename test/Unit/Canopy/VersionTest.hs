module Unit.Canopy.VersionTest (tests) where

import qualified Canopy.Version as Version
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
        let v = Version.one
        Version.toChars v @?= "1.0.0",
      testCase "version max" $ do
        let v = Version.max
        -- Check that max version has reasonable values
        let chars = Version.toChars v
        length chars > 5 @? "Max version should have a reasonable string representation"
    ]

testVersionComparison :: TestTree
testVersionComparison =
  testGroup
    "version comparison tests"
    [ testCase "version equality" $ do
        let v1 = Version.Version 1 0 0
        let v2 = Version.Version 1 0 0
        v1 == v2 @? "Same versions should be equal",
      testCase "version ordering" $ do
        let v1 = Version.Version 1 0 0
        let v2 = Version.Version 1 0 1
        let v3 = Version.Version 1 1 0
        let v4 = Version.Version 2 0 0

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
        let v = Version.Version 1 2 3
        let bumped = Version.bumpPatch v
        bumped @?= Version.Version 1 2 4,
      testCase "bump minor" $ do
        let v = Version.Version 1 2 3
        let bumped = Version.bumpMinor v
        bumped @?= Version.Version 1 3 0,
      testCase "bump major" $ do
        let v = Version.Version 1 2 3
        let bumped = Version.bumpMajor v
        bumped @?= Version.Version 2 0 0
    ]

testVersionToChars :: TestTree
testVersionToChars =
  testGroup
    "version to string tests"
    [ testCase "simple version" $ do
        let v = Version.Version 1 2 3
        Version.toChars v @?= "1.2.3",
      testCase "zero version" $ do
        let v = Version.Version 0 0 0
        Version.toChars v @?= "0.0.0",
      testCase "large numbers" $ do
        let v = Version.Version 10 20 30
        Version.toChars v @?= "10.20.30"
    ]

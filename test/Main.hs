module Main (main) where

-- Import test modules

import qualified Property.Canopy.VersionProps as VersionProps
import qualified Property.Data.NameProps as NameProps
import Test.Tasty
import Test.Tasty.Runners
import qualified Unit.Canopy.VersionTest as VersionTest
import qualified Unit.Data.NameTest as NameTest
import qualified Unit.Json.DecodeTest as JsonDecodeTest

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "Canopy Tests"
    [ unitTests,
      propertyTests
      -- , integrationTests  -- TODO: Add when we have integration tests
      -- , goldenTests       -- TODO: Add when we have golden tests
    ]

unitTests :: TestTree
unitTests =
  testGroup
    "Unit Tests"
    [ NameTest.tests,
      VersionTest.tests,
      JsonDecodeTest.tests
    ]

propertyTests :: TestTree
propertyTests =
  testGroup
    "Property Tests"
    [ NameProps.tests,
      VersionProps.tests
    ]

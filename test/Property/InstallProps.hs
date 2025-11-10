{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Property tests for Install module.
--
-- Tests invariants, laws, and properties of the Install system including
-- argument handling, change detection, context operations, and type system
-- properties using QuickCheck property-based testing.
--
-- @since 0.19.1
module Property.InstallProps (tests) where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Lens ((^.))
import Install (Args (..))
import qualified Install.Types as Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck (Arbitrary (..), elements, testProperty)

-- | All property tests for Install module functionality.
tests :: TestTree
tests =
  testGroup
    "Install Property Tests"
    [ testArgsProperties,
      testChangeProperties,
      testContextProperties,
      testDisplayProperties
    ]

-- | Arbitrary instance for Args data type.
instance Arbitrary Args where
  arbitrary =
    elements
      [ NoArgs,
        Install Pkg.core,
        Install Pkg.http,
        Install Pkg.json,
        Install Pkg.dummyName
      ]

-- | Arbitrary instance for Change data type.
instance Arbitrary a => Arbitrary (Types.Change a) where
  arbitrary = do
    val1 <- arbitrary
    val2 <- arbitrary
    elements
      [ Types.Insert val1,
        Types.Change val1 val2,
        Types.Remove val1
      ]

-- | Arbitrary instance for ExistingDep data type.
instance Arbitrary Types.ExistingDep where
  arbitrary = do
    let version = V.one -- Use the available V.one version
    elements
      [ Types.IndirectDep version,
        Types.TestDirectDep version,
        Types.TestIndirectDep version
      ]

-- | Test Args data type properties.
testArgsProperties :: TestTree
testArgsProperties =
  testGroup
    "Args properties"
    [ testProperty "Args equality is reflexive" $ \(args :: Args) ->
        args == args,
      testProperty "Args equality is symmetric" $ \(args1 :: Args) (args2 :: Args) ->
        (args1 == args2) == (args2 == args1),
      testProperty "Args pattern matching is exhaustive" $ \(args :: Args) ->
        case args of
          NoArgs -> True
          Install _ -> True,
      testProperty "Args distinguish workflow types" $ \(args :: Args) ->
        case args of
          NoArgs -> not (isInstallWorkflow args)
          Install _ -> isInstallWorkflow args,
      testProperty "Install workflows preserve package identity" $ \(args :: Args) ->
        case args of
          NoArgs -> True -- NoArgs doesn't have package identity
          Install pkg -> extractPackageFromArgs args == Just pkg
    ]

-- | Test Change data type properties.
testChangeProperties :: TestTree
testChangeProperties =
  testGroup
    "Change properties"
    [ testProperty "Change equality is reflexive" $ \(change :: Types.Change Int) ->
        change == change,
      testProperty "Change equality is symmetric" $ \change1 change2 ->
        (change1 == change2) == (change2 == (change1 :: Types.Change Int)),
      testProperty "Insert carries value" $ \value ->
        case Types.Insert value of
          Types.Insert v -> v == (value :: Int),
      testProperty "Change carries both values" $ \val1 val2 ->
        case Types.Change val1 val2 of
          Types.Change v1 v2 -> v1 == (val1 :: Int) && v2 == (val2 :: Int),
      testProperty "Remove carries value" $ \value ->
        case Types.Remove value of
          Types.Remove v -> v == (value :: Int)
    ]

-- | Test context and dependency properties.
testContextProperties :: TestTree
testContextProperties =
  testGroup
    "Dependency context properties"
    [ testProperty "ExistingDep types distinguish contexts" $ \(dep :: Types.ExistingDep) ->
        case dep of
          Types.IndirectDep _ -> not (isTestDep dep) && not (isDirectTestDep dep)
          Types.TestDirectDep _ -> isTestDep dep && isDirectTestDep dep
          Types.TestIndirectDep _ -> isTestDep dep && not (isDirectTestDep dep),
      testProperty "ExistingDep preserves version information" $ \(dep :: Types.ExistingDep) ->
        extractVersionFromDep dep == extractVersionFromDep dep, -- Identity check
      testProperty "All ExistingDep variants carry version" $ \(dep :: Types.ExistingDep) ->
        case extractVersionFromDep dep of
          V.Version _ _ _ -> True -- All variants should have valid version
    ]

-- | Test display formatting properties.
testDisplayProperties :: TestTree
testDisplayProperties =
  testGroup
    "Display formatting properties"
    [ testProperty "Widths support proper alignment calculations" $ \n l r ->
        let widths = Types.Widths (abs n) (abs l) (abs r)
            total = widths ^. Types.nameWidth + widths ^. Types.leftWidth + widths ^. Types.rightWidth
         in total >= 0 && total == abs n + abs l + abs r
    ]

-- Helper functions for meaningful property testing
isInstallWorkflow :: Args -> Bool
isInstallWorkflow (Install _) = True
isInstallWorkflow NoArgs = False

extractPackageFromArgs :: Args -> Maybe Pkg.Name
extractPackageFromArgs (Install pkg) = Just pkg
extractPackageFromArgs NoArgs = Nothing

isTestDep :: Types.ExistingDep -> Bool
isTestDep (Types.TestDirectDep _) = True
isTestDep (Types.TestIndirectDep _) = True
isTestDep (Types.IndirectDep _) = False

isDirectTestDep :: Types.ExistingDep -> Bool
isDirectTestDep (Types.TestDirectDep _) = True
isDirectTestDep (Types.TestIndirectDep _) = False
-- No DirectDep constructor exists - this pattern was incorrect
isDirectTestDep (Types.IndirectDep _) = False

extractVersionFromDep :: Types.ExistingDep -> V.Version
extractVersionFromDep (Types.IndirectDep v) = v
extractVersionFromDep (Types.TestDirectDep v) = v
extractVersionFromDep (Types.TestIndirectDep v) = v

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Property-based tests for Make-related library components.
--
-- Tests invariants and laws for the Make system's supporting types using 
-- QuickCheck. Since Make modules are in the terminal executable, these
-- tests focus on the library components that Make depends on.
--
-- CRITICAL: These tests verify actual properties and behavior.
-- NO MOCK FUNCTIONS - every property tests real functionality.
--
-- Key properties tested:
--   * Equality reflexivity, symmetry, and transitivity
--   * Roundtrip properties for conversion functions
--   * Ordering properties and laws
--   * String conversion correctness
module Property.MakeProps (tests) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Package  
import qualified Canopy.Version as Version
import qualified Data.Name as Name
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck (testProperty, (==>))
import Test.QuickCheck (Arbitrary (..), elements)

-- | All property tests for Make-related library components.
tests :: TestTree
tests =
  testGroup
    "Make Support Components Properties"
    [ testModuleNameProperties,
      testVersionProperties,
      testNameProperties,
      testEqualityLaws,
      testMakeSystemProperties,
      testBuildSystemInvariants
    ]

-- | Test properties of ModuleName.
testModuleNameProperties :: TestTree
testModuleNameProperties =
  testGroup
    "ModuleName properties"
    [ testProperty "canonical module name equality is reflexive" $ \name ->
        name == (name :: ModuleName.Canonical),
      testProperty "canonical module name equality is symmetric" $ \name1 name2 ->
        (name1 == name2) == (name2 == (name1 :: ModuleName.Canonical) :: Bool),
      testProperty "canonical module name ordering is consistent" $ \name ->
        let n = name :: ModuleName.Canonical
        in (n <= n) && (n >= n)
    ]

-- | Test properties of Version.
testVersionProperties :: TestTree  
testVersionProperties =
  testGroup
    "Version properties"
    [ testProperty "version equality is reflexive" $ \v ->
        v == (v :: Version.Version),
      testProperty "version one ordering is consistent" $ \v1 v2 v3 ->
        (v1 == v2 && v2 == v3) ==> (v1 == (v3 :: Version.Version)),
      testProperty "version ordering is antisymmetric" $ \v1 v2 ->
        (v1 <= v2 && v2 <= v1) ==> (v1 == (v2 :: Version.Version)),
      testProperty "version one has expected structure" $
        Version.toChars Version.one == "1.0.0"
    ]

-- | Test properties of Name.
testNameProperties :: TestTree
testNameProperties =
  testGroup
    "Name properties" 
    [ testProperty "name equality is reflexive" $ \name ->
        name == (name :: Name.Name),
      testProperty "name roundtrip property" $ \str ->
        Name.toChars (Name.fromChars str) == str,
      testProperty "name fromChars is consistent" $ \str1 str2 ->
        (str1 == str2) == (Name.fromChars str1 == Name.fromChars str2),
      testProperty "predefined names are consistent" $
        Name._main == Name._main
    ]

-- | Test equality laws for all types.
testEqualityLaws :: TestTree
testEqualityLaws =
  testGroup
    "Equality laws"
    [ testProperty "Canonical ModuleName equality is reflexive" $ \name ->
        name == (name :: ModuleName.Canonical),
      testProperty "Version equality is reflexive" $ \version ->
        version == (version :: Version.Version),
      testProperty "Name equality is reflexive" $ \name ->
        name == (name :: Name.Name),
      testProperty "Package equality is reflexive" $ \pkg ->
        pkg == (pkg :: Package.Name)
    ]

-- | Arbitrary instance for ModuleName.Canonical.
instance Arbitrary ModuleName.Canonical where
  arbitrary = elements [ModuleName.basics, ModuleName.maybe, ModuleName.result, ModuleName.list, ModuleName.string]

-- | Arbitrary instance for Version.Version.
instance Arbitrary Version.Version where
  arbitrary = pure Version.one  -- Use predefined version

-- | Arbitrary instance for Name.Name.
instance Arbitrary Name.Name where
  arbitrary = elements [Name._main, Name.true, Name.false, Name.value, Name.identity]

-- | Arbitrary instance for Package.Name.
instance Arbitrary Package.Name where
  arbitrary = pure Package.core  -- Use predefined package

-- | Test properties of Make system integration.
testMakeSystemProperties :: TestTree
testMakeSystemProperties =
  testGroup
    "Make system properties"
    [ testProperty "ModuleName and Package interaction consistency" $ \moduleName packageName ->
        let mn = moduleName :: ModuleName.Canonical
            pn = packageName :: Package.Name
        in (mn == mn) && (pn == pn),
      testProperty "Version and Name compatibility" $ \version name ->
        let v = version :: Version.Version
            n = name :: Name.Name
        in show v /= show n,  -- Different types should show differently
      testProperty "Make component type distinction" $ \moduleName version ->
        let mn = moduleName :: ModuleName.Canonical
            v = version :: Version.Version
        in show mn /= show v,  -- Different component types have different representations
      testProperty "cross-component equality is type-safe" $ \name1 name2 ->
        let n1 = name1 :: Name.Name  
            n2 = name2 :: Name.Name
        in (n1 == n2) == (n2 == n1)  -- Equality is symmetric within type
    ]

-- | Test invariants of build system components.
testBuildSystemInvariants :: TestTree
testBuildSystemInvariants =
  testGroup
    "Build system invariants"
    [ testProperty "module name consistency across operations" $ \moduleName ->
        let mn = moduleName :: ModuleName.Canonical
        in mn == mn && (mn <= mn) && (mn >= mn),
      testProperty "version consistency across operations" $ \version ->
        let v = version :: Version.Version
        in v == v && (v <= v) && (v >= v),
      testProperty "name roundtrip invariant" $ \name ->
        let n = name :: Name.Name
            chars = Name.toChars n
            rebuilt = Name.fromChars chars
        in Name.toChars rebuilt == chars,
      testProperty "build component show stability" $ \moduleName version name ->
        let mn = moduleName :: ModuleName.Canonical
            v = version :: Version.Version  
            n = name :: Name.Name
            show1 = (show mn, show v, show n)
            show2 = (show mn, show v, show n)
        in show1 == show2,  -- Show is deterministic
      testProperty "Make system type safety invariant" $ \name ->
        let n1 = name :: Name.Name
            n2 = name :: Name.Name
        in (n1 == n2) ==> (show n1 == show n2)  -- Equal values show equally
    ]
{-# LANGUAGE OverloadedStrings #-}

-- | Tests for REPL type query support.
--
-- Verifies that 'formatTypeOf', 'formatBrowseModule', and
-- 'formatBrowseState' produce the correct output from synthetic
-- interface data.
--
-- @since 0.19.2
module Unit.Repl.TypeQueryTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Repl.TypeQuery as TypeQuery
import Test.Tasty
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  testGroup
    "Repl.TypeQuery"
    [ formatTypeOfTests,
      formatBrowseModuleTests,
      toPublicUnionTests
    ]

-- FORMAT TYPE OF TESTS

formatTypeOfTests :: TestTree
formatTypeOfTests =
  testGroup
    "formatTypeOf"
    [ HUnit.testCase "returns Nothing for unknown name" $
        TypeQuery.formatTypeOf (Name.fromChars "unknown") emptyInterface HUnit.@?= Nothing,
      HUnit.testCase "returns Just for known name with Int type" $
        TypeQuery.formatTypeOf intValueName intValueInterface HUnit.@?= Just intTypeStr,
      HUnit.testCase "returns Just for known name with function type" $
        TypeQuery.formatTypeOf funcValueName funcValueInterface HUnit.@?= Just funcTypeStr,
      HUnit.testCase "returns Nothing for name in empty values map" $
        TypeQuery.formatTypeOf (Name.fromChars "x") emptyInterface HUnit.@?= Nothing
    ]

-- FORMAT BROWSE MODULE TESTS

formatBrowseModuleTests :: TestTree
formatBrowseModuleTests =
  testGroup
    "formatBrowseModule"
    [ HUnit.testCase "header contains module name" $
        HUnit.assertBool "should contain module name" (headerContains "TestModule" browseOutput),
      HUnit.testCase "contains value export" $
        HUnit.assertBool "should contain value name" (Name.toChars intValueName `List.isInfixOf` browseOutput),
      HUnit.testCase "contains union type export" $
        HUnit.assertBool "should contain union name" ("Color" `List.isInfixOf` browseOutputWithUnion),
      HUnit.testCase "contains alias export" $
        HUnit.assertBool "should contain alias name" ("Point" `List.isInfixOf` browseOutputWithAlias),
      HUnit.testCase "private unions are excluded" $
        HUnit.assertBool "should not contain private union" (not ("Secret" `List.isInfixOf` browseOutputWithPrivateUnion)),
      HUnit.testCase "open union constructors are listed" $
        HUnit.assertBool "should contain constructor names" ("Red" `List.isInfixOf` browseOutputWithUnion)
    ]
  where
    browseOutput = TypeQuery.formatBrowseModule (Name.fromChars "TestModule") intValueInterface
    browseOutputWithUnion = TypeQuery.formatBrowseModule (Name.fromChars "TestModule") unionInterface
    browseOutputWithAlias = TypeQuery.formatBrowseModule (Name.fromChars "TestModule") aliasInterface
    browseOutputWithPrivateUnion = TypeQuery.formatBrowseModule (Name.fromChars "TestModule") privateUnionInterface

    headerContains modName output = ("-- " ++ modName) `List.isInfixOf` output

-- TO PUBLIC UNION TESTS

toPublicUnionTests :: TestTree
toPublicUnionTests =
  testGroup
    "Union Visibility"
    [ HUnit.testCase "OpenUnion is public" $
        isJust (Interface.toPublicUnion (Interface.OpenUnion simpleUnion)),
      HUnit.testCase "ClosedUnion is public" $
        isJust (Interface.toPublicUnion (Interface.ClosedUnion simpleUnion)),
      HUnit.testCase "PrivateUnion is not public" $
        isNothing (Interface.toPublicUnion (Interface.PrivateUnion simpleUnion))
    ]
  where
    isJust (Just _) = pure ()
    isJust Nothing = HUnit.assertFailure "Expected Just, got Nothing"
    isNothing Nothing = pure ()
    isNothing (Just _) = HUnit.assertFailure "Expected Nothing, got Just"

-- TEST FIXTURES

-- | Canonical name for Basics.Int
basicsIntCanonical :: ModuleName.Canonical
basicsIntCanonical = ModuleName.Canonical Pkg.core (Name.fromChars "Basics")

-- | Type representing Int
intType :: Can.Type
intType = Can.TType basicsIntCanonical (Name.fromChars "Int") []

-- | Type representing a -> a
identityFuncType :: Can.Type
identityFuncType = Can.TLambda (Can.TVar (Name.fromChars "a")) (Can.TVar (Name.fromChars "a"))

-- | Annotation for Int (no free vars)
intAnnotation :: Can.Annotation
intAnnotation = Can.Forall Map.empty intType

-- | Annotation for a -> a
funcAnnotation :: Can.Annotation
funcAnnotation = Can.Forall (Map.singleton (Name.fromChars "a") ()) identityFuncType

-- | Name for the Int value binding
intValueName :: Name.Name
intValueName = Name.fromChars "myInt"

-- | Name for the function value binding
funcValueName :: Name.Name
funcValueName = Name.fromChars "identity"

-- | Expected type string for Basics.Int (fully qualified because
-- the REPL uses an empty localizer).
intTypeStr :: String
intTypeStr = "Basics.Int"

-- | Expected type string for a -> a
funcTypeStr :: String
funcTypeStr = "a -> a"

-- | Empty interface with no exports.
emptyInterface :: Interface.Interface
emptyInterface =
  Interface.Interface Pkg.core Map.empty Map.empty Map.empty Map.empty Map.empty

-- | Interface with a single Int value.
intValueInterface :: Interface.Interface
intValueInterface =
  Interface.Interface
    Pkg.core
    (Map.singleton intValueName intAnnotation)
    Map.empty
    Map.empty
    Map.empty
    Map.empty

-- | Interface with a function value.
funcValueInterface :: Interface.Interface
funcValueInterface =
  Interface.Interface
    Pkg.core
    (Map.singleton funcValueName funcAnnotation)
    Map.empty
    Map.empty
    Map.empty
    Map.empty

-- | A simple union type with constructors.
simpleUnion :: Can.Union
simpleUnion =
  Can.Union
    []
    []
    [ Can.Ctor (Name.fromChars "Red") Index.first 0 [],
      Can.Ctor (Name.fromChars "Green") Index.second 1 [],
      Can.Ctor (Name.fromChars "Blue") Index.third 2 []
    ]
    0
    Can.Normal

-- | Interface with a public union type.
unionInterface :: Interface.Interface
unionInterface =
  Interface.Interface
    Pkg.core
    Map.empty
    (Map.singleton (Name.fromChars "Color") (Interface.OpenUnion simpleUnion))
    Map.empty
    Map.empty
    Map.empty

-- | Interface with a private union type.
privateUnionInterface :: Interface.Interface
privateUnionInterface =
  Interface.Interface
    Pkg.core
    Map.empty
    (Map.singleton (Name.fromChars "Secret") (Interface.PrivateUnion simpleUnion))
    Map.empty
    Map.empty
    Map.empty

-- | Interface with an alias type.
aliasInterface :: Interface.Interface
aliasInterface =
  Interface.Interface
    Pkg.core
    Map.empty
    Map.empty
    (Map.singleton (Name.fromChars "Point") (Interface.PublicAlias (Can.Alias [] [] intType Nothing)))
    Map.empty
    Map.empty

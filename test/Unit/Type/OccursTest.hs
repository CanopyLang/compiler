{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the 'Type.Occurs' module.
--
-- The occurs check detects infinite (cyclic) types by traversing the type
-- graph through UnionFind points. A cycle means a variable appears in its
-- own structure, which would produce an infinite type during unification.
--
-- @since 0.19.2
module Unit.Type.OccursTest (tests) where

import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Test.Tasty
import Test.Tasty.HUnit
import qualified Type.Occurs as Occurs
import Type.Type (Content (..), Descriptor (Descriptor), FlatType (..), SuperType (..), Variable, noMark, noRank)
import qualified Type.UnionFind as UF

tests :: TestTree
tests =
  testGroup
    "Type.Occurs Tests"
    [ testNonRecursive,
      testSelfReferencing,
      testDeepNesting
    ]

-- HELPER

-- | Create a fresh variable with the given content and default rank/mark/copy.
mkVar :: Content -> IO Variable
mkVar content =
  UF.fresh (Descriptor content noRank noMark Nothing)

-- NON-RECURSIVE TESTS

testNonRecursive :: TestTree
testNonRecursive =
  testGroup
    "non-recursive types return False"
    [ testCase "fresh flex var" $ do
        var <- mkVar (FlexVar Nothing)
        result <- Occurs.occurs var
        result @?= False,
      testCase "fresh rigid var" $ do
        var <- mkVar (RigidVar "a")
        result <- Occurs.occurs var
        result @?= False,
      testCase "flex super var (Number)" $ do
        var <- mkVar (FlexSuper Number (Just "number"))
        result <- Occurs.occurs var
        result @?= False,
      testCase "App1 not containing itself" $ do
        inner <- mkVar (FlexVar (Just "a"))
        var <- mkVar (Structure (App1 ModuleName.basics "List" [inner]))
        result <- Occurs.occurs var
        result @?= False,
      testCase "Fun1 not self-referencing" $ do
        argVar <- mkVar (FlexVar (Just "a"))
        retVar <- mkVar (FlexVar (Just "b"))
        var <- mkVar (Structure (Fun1 argVar retVar))
        result <- Occurs.occurs var
        result @?= False,
      testCase "EmptyRecord1" $ do
        var <- mkVar (Structure EmptyRecord1)
        result <- Occurs.occurs var
        result @?= False,
      testCase "Unit1" $ do
        var <- mkVar (Structure Unit1)
        result <- Occurs.occurs var
        result @?= False
    ]

-- SELF-REFERENCING TESTS

testSelfReferencing :: TestTree
testSelfReferencing =
  testGroup
    "self-referencing types return True"
    [ testCase "self-reference in App1 args" $ do
        var <- mkVar (FlexVar Nothing)
        UF.set var (Descriptor (Structure (App1 ModuleName.basics "List" [var])) noRank noMark Nothing)
        result <- Occurs.occurs var
        result @?= True,
      testCase "self-reference in Fun1" $ do
        retVar <- mkVar (FlexVar (Just "b"))
        var <- mkVar (FlexVar Nothing)
        UF.set var (Descriptor (Structure (Fun1 var retVar)) noRank noMark Nothing)
        result <- Occurs.occurs var
        result @?= True,
      testCase "self-reference in Record1 fields" $ do
        var <- mkVar (FlexVar Nothing)
        extVar <- mkVar (Structure EmptyRecord1)
        let fields = Map.singleton (Name.fromChars "self") var
        UF.set var (Descriptor (Structure (Record1 fields extVar)) noRank noMark Nothing)
        result <- Occurs.occurs var
        result @?= True,
      testCase "self-reference in Record1 extension" $ do
        var <- mkVar (FlexVar Nothing)
        UF.set var (Descriptor (Structure (Record1 Map.empty var)) noRank noMark Nothing)
        result <- Occurs.occurs var
        result @?= True
    ]

-- DEEPLY NESTED TESTS

testDeepNesting :: TestTree
testDeepNesting =
  testGroup
    "deeply nested self-reference"
    [ testCase "cycle through multiple structure layers" $ do
        var <- mkVar (FlexVar Nothing)
        mid <- mkVar (FlexVar Nothing)
        UF.set mid (Descriptor (Structure (App1 ModuleName.list "List" [var])) noRank noMark Nothing)
        UF.set var (Descriptor (Structure (Fun1 mid mid)) noRank noMark Nothing)
        result <- Occurs.occurs var
        result @?= True
    ]

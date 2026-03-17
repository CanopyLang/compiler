{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the recursion detection module.
--
-- Verifies that the nitpick phase correctly detects:
--
-- * Obviously infinite recursion (@f x = f x@)
-- * Non-recursive functions produce no warning
-- * Recursive functions with a base case produce no warning
--
-- @since 0.20.1
module Unit.Nitpick.RecursionTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import Data.Text (Text)
import qualified Nitpick.Recursion as Recursion
import qualified Reporting.Annotation as Ann
import qualified Reporting.Warning as Warning
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Nitpick.Recursion Tests"
    [ infiniteRecursionTests,
      safeRecursionTests
    ]

-- HELPERS

-- | Create a pattern that matches any value.
anyPattern :: Can.Pattern
anyPattern = Ann.At Ann.zero Can.PAnything

-- | Create a located expression.
loc :: Can.Expr_ -> Can.Expr
loc = Ann.At Ann.zero

-- | Create a local variable reference expression.
varLocal :: Name.Name -> Can.Expr
varLocal n = loc (Can.VarLocal n)

-- | Extract function name from a PotentialInfiniteRecursion warning.
recursionName :: Warning.Warning -> Maybe Text
recursionName (Warning.PotentialInfiniteRecursion n) = Just n
recursionName _ = Nothing

-- | Check if a warning is PotentialInfiniteRecursion.
isInfiniteRecursion :: Warning.Warning -> Bool
isInfiniteRecursion (Warning.PotentialInfiniteRecursion _) = True
isInfiniteRecursion _ = False

-- INFINITE RECURSION TESTS

infiniteRecursionTests :: TestTree
infiniteRecursionTests =
  testGroup
    "obviously infinite recursion"
    [ testCase "f x = f x is detected" $
        let name = Name.fromChars "f"
            body = loc (Can.Call (varLocal name) [varLocal (Name.fromChars "x")])
            def = Can.Def (Ann.At Ann.zero name) [anyPattern] body
            warnings = Recursion.checkRecursion [def]
         in case filter isInfiniteRecursion warnings of
              [w] -> recursionName w @?= Just "f"
              _ -> assertFailure "expected exactly one PotentialInfiniteRecursion warning for f",
      testCase "g = g (no args, self-call) is detected" $
        let name = Name.fromChars "g"
            body = loc (Can.Call (varLocal name) [])
            def = Can.Def (Ann.At Ann.zero name) [] body
            warnings = Recursion.checkRecursion [def]
         in case filter isInfiniteRecursion warnings of
              [w] -> recursionName w @?= Just "g"
              _ -> assertFailure "expected exactly one PotentialInfiniteRecursion warning for g"
    ]

-- SAFE RECURSION TESTS

safeRecursionTests :: TestTree
safeRecursionTests =
  testGroup
    "safe functions"
    [ testCase "non-recursive function produces no warning" $
        let name = Name.fromChars "f"
            body = loc (Can.Int 42)
            def = Can.Def (Ann.At Ann.zero name) [anyPattern] body
            warnings = Recursion.checkRecursion [def]
         in assertBool "expected no warnings" (null warnings),
      testCase "recursive function with base case produces no warning" $
        let name = Name.fromChars "fact"
            xName = Name.fromChars "x"
            baseBranch = (loc (Can.Int 0), loc (Can.Int 1))
            recBranch = (varLocal xName, loc (Can.Call (varLocal name) [varLocal xName]))
            body = loc (Can.If [baseBranch, recBranch] (loc (Can.Int 1)))
            def = Can.Def (Ann.At Ann.zero name) [anyPattern] body
            warnings = Recursion.checkRecursion [def]
         in assertBool "expected no warnings for function with base case" (null warnings),
      testCase "empty def list produces no warnings" $
        assertBool "expected no warnings" (null (Recursion.checkRecursion []))
    ]

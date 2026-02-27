{-# LANGUAGE OverloadedStrings #-}

-- | Unit.NameReversalTest - Tests for correct character ordering in Name
--
-- This module verifies that 'Data.Name.toChars' produces characters in the
-- correct (forward) order, not reversed. Each test checks the exact string
-- produced for a known identifier.
--
-- @since 0.19.1
module Unit.NameReversalTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Canopy.Data.Name as Name

-- | All name character-order tests.
tests :: TestTree
tests = testGroup "Name Character Order Tests"
  [ testCase "Name.fromChars \"String\" round-trips to \"String\"" $
      Name.toChars (Name.fromChars "String") @?= "String"

  , testCase "Name.fromChars \"Bool\" round-trips to \"Bool\"" $
      Name.toChars (Name.fromChars "Bool") @?= "Bool"

  , testCase "Name.fromChars \"Int\" round-trips to \"Int\"" $
      Name.toChars (Name.fromChars "Int") @?= "Int"
  ]

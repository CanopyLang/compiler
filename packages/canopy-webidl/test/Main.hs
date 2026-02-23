{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | WebIDL Test Suite
--
-- Comprehensive tests for the WebIDL parser and code generator.
--
-- @since 0.20.0
module Main where

import Test.Tasty

import qualified Unit.WebIDL.CodegenTest as CodegenTest
import qualified Unit.WebIDL.ParserTest as ParserTest
import qualified Unit.WebIDL.SourcesTest as SourcesTest
import qualified Unit.WebIDL.TransformTest as TransformTest
import qualified Unit.WebIDL.TypesTest as TypesTest


main :: IO ()
main = defaultMain tests


tests :: TestTree
tests = testGroup "WebIDL Tests"
  [ TypesTest.tests
  , SourcesTest.tests
  , ParserTest.tests
  , TransformTest.tests
  , CodegenTest.tests
  ]

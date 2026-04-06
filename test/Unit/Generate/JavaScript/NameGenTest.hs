{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Tests for JavaScript name generation — gaps not covered by NameTest.
--
-- Covers 'fromBuilder', 'fromIndex', extended 'fromInt' edge cases
-- (boundary values, sequential distinctness), additional reserved words
-- across multiple JS keyword categories, and the Canopy-reserved F3-F8 /
-- A2-A8 identifiers.
--
-- @since 0.19.2
module Unit.Generate.JavaScript.NameGenTest (tests) where

import qualified Canopy.Data.Index as Index
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import Canopy.Data.Name (Name)
import qualified Canopy.Data.Name as Name
import qualified Generate.JavaScript.Name as JsName
import Test.Tasty
import Test.Tasty.HUnit

-- | Render a 'JsName.Name' to a plain 'String' for assertion.
nameToString :: JsName.Name -> String
nameToString = LChar8.unpack . BB.toLazyByteString . JsName.toBuilder

-- | Convenience wrapper for 'Name.fromChars'.
name :: String -> Name
name = Name.fromChars

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.NameGen"
    [ fromBuilderTests,
      fromIndexTests,
      fromIntBoundaryTests,
      fromIntDistinctTests,
      fromLocalReservedExtendedTests
    ]

-- FROM BUILDER TESTS

fromBuilderTests :: TestTree
fromBuilderTests =
  testGroup
    "fromBuilder"
    [ testCase "wraps a literal string builder unchanged" $
        nameToString (JsName.fromBuilder (BB.string7 "__canopy_debug")) @?= "__canopy_debug",
      testCase "wraps an integer builder" $
        nameToString (JsName.fromBuilder (BB.intDec 42)) @?= "42",
      testCase "wraps empty builder producing empty string" $
        nameToString (JsName.fromBuilder mempty) @?= "",
      testCase "wraps concatenated builders" $
        nameToString (JsName.fromBuilder (BB.string7 "foo" <> BB.string7 "$" <> BB.string7 "bar")) @?= "foo$bar",
      testCase "round-trips through toBuilder" $
        let original = BB.string7 "runtime$helper"
            result = JsName.toBuilder (JsName.fromBuilder original)
        in LChar8.unpack (BB.toLazyByteString result) @?= "runtime$helper"
    ]

-- FROM INDEX TESTS

fromIndexTests :: TestTree
fromIndexTests =
  testGroup
    "fromIndex"
    [ testCase "first index (0) produces 'a'" $
        nameToString (JsName.fromIndex Index.first) @?= "a",
      testCase "second index (1) produces 'b'" $
        nameToString (JsName.fromIndex Index.second) @?= "b",
      testCase "third index (2) produces 'c'" $
        nameToString (JsName.fromIndex Index.third) @?= "c",
      testCase "next of first index produces same as fromInt 1" $
        nameToString (JsName.fromIndex (Index.next Index.first))
          @?= nameToString (JsName.fromInt 1),
      testCase "fromIndex delegates to fromInt — consistent output" $
        nameToString (JsName.fromIndex Index.second)
          @?= nameToString (JsName.fromInt 1)
    ]

-- FROM INT BOUNDARY TESTS

fromIntBoundaryTests :: TestTree
fromIntBoundaryTests =
  testGroup
    "fromInt boundary values"
    [ testCase "index 26 is 'A' (first uppercase)" $
        nameToString (JsName.fromInt 26) @?= "A",
      testCase "index 51 is 'Z' (last uppercase)" $
        nameToString (JsName.fromInt 51) @?= "Z",
      testCase "index 52 is '_' (underscore byte)" $
        nameToString (JsName.fromInt 52) @?= "_",
      testCase "index 53 starts two-character names (skips $ standalone)" $
        let result = nameToString (JsName.fromInt 53)
        in length result @?= 2,
      testCase "index 54 also produces a two-character name" $
        let result = nameToString (JsName.fromInt 54)
        in length result @?= 2,
      testCase "large value 1000 produces a multi-character name" $
        let result = nameToString (JsName.fromInt 1000)
        in length result >= 2 @?= True,
      testCase "index 52 differs from index 51" $
        nameToString (JsName.fromInt 52) @?= "_"
    ]

-- FROM INT SEQUENTIAL DISTINCTNESS

fromIntDistinctTests :: TestTree
fromIntDistinctTests =
  testGroup
    "fromInt sequential distinctness"
    [ testCase "indices 0..9 are all distinct" $
        let results = fmap (nameToString . JsName.fromInt) [0 .. 9]
        in length results @?= length (deduplicate results),
      testCase "indices 0..52 are all distinct" $
        let results = fmap (nameToString . JsName.fromInt) [0 .. 52]
        in length results @?= length (deduplicate results),
      testCase "indices 53..62 are all distinct two-char names" $
        let results = fmap (nameToString . JsName.fromInt) [53 .. 62]
        in length results @?= length (deduplicate results),
      testCase "no overlap between single-char range and two-char range" $
        let singles = fmap (nameToString . JsName.fromInt) [0 .. 52]
            doubles = fmap (nameToString . JsName.fromInt) [53 .. 62]
            overlap = filter (`elem` singles) doubles
        in length overlap @?= 0
    ]

-- EXTENDED RESERVED WORD TESTS

fromLocalReservedExtendedTests :: TestTree
fromLocalReservedExtendedTests =
  testGroup
    "fromLocal escapes additional reserved words"
    [ testCase "do is escaped" $
        nameToString (JsName.fromLocal (name "do")) @?= "_do",
      testCase "in is escaped" $
        nameToString (JsName.fromLocal (name "in")) @?= "_in",
      testCase "for is escaped" $
        nameToString (JsName.fromLocal (name "for")) @?= "_for",
      testCase "new is escaped" $
        nameToString (JsName.fromLocal (name "new")) @?= "_new",
      testCase "try is escaped" $
        nameToString (JsName.fromLocal (name "try")) @?= "_try",
      testCase "this is escaped" $
        nameToString (JsName.fromLocal (name "this")) @?= "_this",
      testCase "void is escaped" $
        nameToString (JsName.fromLocal (name "void")) @?= "_void",
      testCase "with is escaped" $
        nameToString (JsName.fromLocal (name "with")) @?= "_with",
      testCase "enum is escaped" $
        nameToString (JsName.fromLocal (name "enum")) @?= "_enum",
      testCase "yield is escaped" $
        nameToString (JsName.fromLocal (name "yield")) @?= "_yield",
      testCase "const is escaped" $
        nameToString (JsName.fromLocal (name "const")) @?= "_const",
      testCase "delete is escaped" $
        nameToString (JsName.fromLocal (name "delete")) @?= "_delete",
      testCase "switch is escaped" $
        nameToString (JsName.fromLocal (name "switch")) @?= "_switch",
      testCase "typeof is escaped" $
        nameToString (JsName.fromLocal (name "typeof")) @?= "_typeof",
      testCase "import is escaped" $
        nameToString (JsName.fromLocal (name "import")) @?= "_import",
      testCase "export is escaped" $
        nameToString (JsName.fromLocal (name "export")) @?= "_export",
      testCase "instanceof is escaped" $
        nameToString (JsName.fromLocal (name "instanceof")) @?= "_instanceof",
      testCase "debugger is escaped" $
        nameToString (JsName.fromLocal (name "debugger")) @?= "_debugger",
      testCase "canopy reserved F3 is escaped" $
        nameToString (JsName.fromLocal (name "F3")) @?= "_F3",
      testCase "canopy reserved F9 is escaped" $
        nameToString (JsName.fromLocal (name "F9")) @?= "_F9",
      testCase "canopy reserved A2 is escaped" $
        nameToString (JsName.fromLocal (name "A2")) @?= "_A2",
      testCase "canopy reserved A8 is escaped" $
        nameToString (JsName.fromLocal (name "A8")) @?= "_A8",
      testCase "non-reserved word similar to reserved passes through" $
        nameToString (JsName.fromLocal (name "ford")) @?= "ford",
      testCase "non-reserved word 'done' passes through" $
        nameToString (JsName.fromLocal (name "done")) @?= "done"
    ]

-- HELPERS

-- | Remove duplicate strings from a list, preserving order.
--
-- Used to count distinct elements without importing Data.Set or Data.List.nub.
deduplicate :: [String] -> [String]
deduplicate = foldr insertIfAbsent []
  where
    insertIfAbsent x acc
      | x `elem` acc = acc
      | otherwise = x : acc

{-# OPTIONS_GHC -Wall #-}

-- | Tests for JavaScript name generation.
--
-- Validates that the Name module correctly converts Canopy identifiers into
-- valid JavaScript identifiers, including escaping reserved words, generating
-- qualified global names, kernel references, and temporary names used by the
-- code generator.
--
-- @since 0.19.2
module Unit.Generate.NameTest (tests) where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy.Char8 as LChar8
import Data.Name (Name)
import qualified Data.Name as Name
import qualified Generate.JavaScript.Name as JsName
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Name"
    [ fromLocalTests,
      fromLocalReservedTests,
      fromGlobalTests,
      fromKernelTests,
      fromCycleTests,
      fromIntTests,
      makeFTests,
      makeATests,
      makeLabelTests,
      makeTempTests,
      tailCallNameTests,
      dollarTests
    ]

-- HELPERS

nameToString :: JsName.Name -> String
nameToString = LChar8.unpack . B.toLazyByteString . JsName.toBuilder

name :: String -> Name
name = Name.fromChars

-- FROM LOCAL TESTS

fromLocalTests :: TestTree
fromLocalTests =
  testGroup
    "fromLocal"
    [ testCase "simple identifier passes through unchanged" $
        nameToString (JsName.fromLocal (name "myVar")) @?= "myVar",
      testCase "single character identifier" $
        nameToString (JsName.fromLocal (name "x")) @?= "x",
      testCase "identifier with underscore" $
        nameToString (JsName.fromLocal (name "my_var")) @?= "my_var",
      testCase "identifier starting with uppercase" $
        nameToString (JsName.fromLocal (name "MyType")) @?= "MyType",
      testCase "multi-word camelCase identifier" $
        nameToString (JsName.fromLocal (name "getUserName")) @?= "getUserName"
    ]

-- FROM LOCAL RESERVED WORD TESTS

fromLocalReservedTests :: TestTree
fromLocalReservedTests =
  testGroup
    "fromLocal escapes reserved words"
    [ testCase "var is escaped with underscore prefix" $
        nameToString (JsName.fromLocal (name "var")) @?= "_var",
      testCase "if is escaped with underscore prefix" $
        nameToString (JsName.fromLocal (name "if")) @?= "_if",
      testCase "return is escaped with underscore prefix" $
        nameToString (JsName.fromLocal (name "return")) @?= "_return",
      testCase "function is escaped with underscore prefix" $
        nameToString (JsName.fromLocal (name "function")) @?= "_function",
      testCase "class is escaped with underscore prefix" $
        nameToString (JsName.fromLocal (name "class")) @?= "_class",
      testCase "null is escaped with underscore prefix" $
        nameToString (JsName.fromLocal (name "null")) @?= "_null",
      testCase "undefined is escaped with underscore prefix" $
        nameToString (JsName.fromLocal (name "undefined")) @?= "_undefined",
      testCase "let is escaped with underscore prefix" $
        nameToString (JsName.fromLocal (name "let")) @?= "_let",
      testCase "canopy reserved F2 is escaped" $
        nameToString (JsName.fromLocal (name "F2")) @?= "_F2",
      testCase "canopy reserved A9 is escaped" $
        nameToString (JsName.fromLocal (name "A9")) @?= "_A9",
      testCase "non-reserved word starting with reserved prefix passes through" $
        nameToString (JsName.fromLocal (name "variable")) @?= "variable"
    ]

-- FROM GLOBAL TESTS

fromGlobalTests :: TestTree
fromGlobalTests =
  testGroup
    "fromGlobal"
    [ testCase "global name contains module path and function name" $
        let home = ModuleName.Canonical Pkg.core (name "List")
            result = nameToString (JsName.fromGlobal home (name "map"))
        in assertBool "should contain map" ("map" `isInfixOfString` result),
      testCase "global name for elm/core List.map has correct structure" $
        let home = ModuleName.Canonical Pkg.core (name "List")
            result = nameToString (JsName.fromGlobal home (name "map"))
        in do
          assertBool "starts with $" (isPrefixOfString "$" result)
          assertBool "contains elm" ("elm" `isInfixOfString` result)
          assertBool "contains core" ("core" `isInfixOfString` result)
          assertBool "ends with map" ("map" `isSuffixOfString` result),
      testCase "global name for dotted module escapes dots to dollar signs" $
        let home = ModuleName.Canonical Pkg.core (name "Dict.Helper")
            result = nameToString (JsName.fromGlobal home (name "get"))
        in assertBool "module dots become dollar signs" ("Dict$Helper" `isInfixOfString` result),
      testCase "global name for package with dashes escapes to underscores" $
        let home = ModuleName.Canonical Pkg.virtualDom (name "VirtualDom")
            result = nameToString (JsName.fromGlobal home (name "node"))
        in assertBool "package dashes become underscores" ("virtual_dom" `isInfixOfString` result)
    ]

-- FROM KERNEL TESTS

fromKernelTests :: TestTree
fromKernelTests =
  testGroup
    "fromKernel"
    [ testCase "kernel name has underscore-separated format" $
        nameToString (JsName.fromKernel (name "utils") (name "eq"))
          @?= "_utils_eq",
      testCase "kernel name for List.Nil" $
        nameToString (JsName.fromKernel Name.list (name "Nil"))
          @?= "_List_Nil",
      testCase "kernel name for Utils.update" $
        nameToString (JsName.fromKernel Name.utils (name "update"))
          @?= "_Utils_update",
      testCase "kernel name for Utils.chr" $
        nameToString (JsName.fromKernel Name.utils (name "chr"))
          @?= "_Utils_chr"
    ]

-- FROM CYCLE TESTS

fromCycleTests :: TestTree
fromCycleTests =
  testGroup
    "fromCycle"
    [ testCase "cycle name contains cyclic marker" $
        let home = ModuleName.Canonical Pkg.core (name "Main")
            result = nameToString (JsName.fromCycle home (name "myVal"))
        in assertBool "contains $cyclic$" ("$cyclic$" `isInfixOfString` result),
      testCase "cycle name ends with the value name" $
        let home = ModuleName.Canonical Pkg.core (name "Main")
            result = nameToString (JsName.fromCycle home (name "myVal"))
        in assertBool "ends with myVal" ("myVal" `isSuffixOfString` result)
    ]

-- FROM INT TESTS

fromIntTests :: TestTree
fromIntTests =
  testGroup
    "fromInt"
    [ testCase "index 0 produces single lowercase letter" $
        let result = nameToString (JsName.fromInt 0)
        in assertEqual "first index is 'a'" "a" result,
      testCase "index 1 produces 'b'" $
        nameToString (JsName.fromInt 1) @?= "b",
      testCase "index 25 produces 'z'" $
        nameToString (JsName.fromInt 25) @?= "z",
      testCase "index 26 produces 'A'" $
        nameToString (JsName.fromInt 26) @?= "A"
    ]

-- MAKE F TESTS

makeFTests :: TestTree
makeFTests =
  testGroup
    "makeF"
    [ testCase "makeF 2 produces F2" $
        nameToString (JsName.makeF 2) @?= "F2",
      testCase "makeF 9 produces F9" $
        nameToString (JsName.makeF 9) @?= "F9"
    ]

-- MAKE A TESTS

makeATests :: TestTree
makeATests =
  testGroup
    "makeA"
    [ testCase "makeA 2 produces A2" $
        nameToString (JsName.makeA 2) @?= "A2",
      testCase "makeA 5 produces A5" $
        nameToString (JsName.makeA 5) @?= "A5"
    ]

-- MAKE LABEL TESTS

makeLabelTests :: TestTree
makeLabelTests =
  testGroup
    "makeLabel"
    [ testCase "label combines name with dollar and index" $
        let result = nameToString (JsName.makeLabel (name "branch") 0)
        in assertBool "contains branch" ("branch" `isInfixOfString` result),
      testCase "label index 3 contains 3" $
        let result = nameToString (JsName.makeLabel (name "x") 3)
        in assertBool "contains 3" ("3" `isInfixOfString` result)
    ]

-- MAKE TEMP TESTS

makeTempTests :: TestTree
makeTempTests =
  testGroup
    "makeTemp"
    [ testCase "temp name has $temp$ prefix" $
        let result = nameToString (JsName.makeTemp (name "value"))
        in assertEqual "temp prefix" "$temp$value" result,
      testCase "temp name preserves original name" $
        let result = nameToString (JsName.makeTemp (name "counter"))
        in assertEqual "temp with counter" "$temp$counter" result
    ]

-- TAIL CALL NAME TESTS

tailCallNameTests :: TestTree
tailCallNameTests =
  testGroup
    "tail call names"
    [ testCase "loop sentinel has $sentinel$ prefix" $
        nameToString (JsName.makeLoopSentinelName (name "fn"))
          @?= "$sentinel$fn",
      testCase "tail call loop hoist has correct prefix" $
        nameToString (JsName.makeTailCallLoopHoistName (name "fn"))
          @?= "$tailcallloophoist$fn",
      testCase "tail call loop return has correct prefix" $
        nameToString (JsName.makeTailCallLoopReturnName (name "fn"))
          @?= "$tailcallloopreturn$fn",
      testCase "tail call function param has correct prefix" $
        nameToString (JsName.makeTailCallFunctionParamName (name "arg"))
          @?= "$tailcallfunctionparam$arg"
    ]

-- DOLLAR TESTS

dollarTests :: TestTree
dollarTests =
  testGroup
    "dollar"
    [ testCase "dollar produces $ character" $
        nameToString JsName.dollar @?= "$"
    ]

-- STRING HELPERS

isInfixOfString :: String -> String -> Bool
isInfixOfString needle haystack =
  any (isPrefixOfString needle) (tails haystack)

isSuffixOfString :: String -> String -> Bool
isSuffixOfString needle haystack =
  isPrefixOfString (reverse needle) (reverse haystack)

isPrefixOfString :: String -> String -> Bool
isPrefixOfString [] _ = True
isPrefixOfString _ [] = False
isPrefixOfString (x : xs) (y : ys) = x == y && isPrefixOfString xs ys

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_ : rest) = xs : tails rest

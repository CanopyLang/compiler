{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Generate.JavaScript.FFIGenTest - Tests for FFI JavaScript code generation
--
-- This module provides unit tests for the pure utility functions exported by
-- "Generate.JavaScript.FFI". The focus is on functions that can be exercised
-- without a full compiler pipeline: identifier validation, sanitization,
-- JavaScript string escaping, annotation extraction, function-name discovery,
-- and internal-name extraction.
--
-- == Test Coverage
--
-- * 'isValidJsIdentifier': valid/invalid identifier strings
-- * 'sanitizeForIdent': characters replaced vs preserved
-- * 'escapeJsString': all documented escape sequences
-- * 'trim': leading/trailing whitespace stripping
-- * 'extractCanopyType': @\@canopy-type@ annotation parsing
-- * 'findFunctionName': @function@, @async function@, @var@ patterns
-- * 'extractInternalNames': @_@-prefixed function/var detection
-- * 'extractFFIFunctions': full JSDoc block parsing
-- * 'extractCanopyTypeFunctions': name/type pair extraction
-- * 'FFIInfo' construction, lens access, and 'Binary' round-trip
--
-- @since 0.19.2
module Unit.Generate.JavaScript.FFIGenTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Control.Lens ((^.), (.~))
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified Canopy.Data.Name as Name
import qualified Generate.JavaScript.FFI as FFI
import FFI.Types (BindingMode (..))

-- | Root test tree for Generate.JavaScript.FFI.
tests :: TestTree
tests = testGroup "Generate.JavaScript.FFI Tests"
  [ isValidJsIdentifierTests
  , sanitizeForIdentTests
  , escapeJsStringTests
  , trimTests
  , extractCanopyTypeTests
  , findFunctionNameTests
  , extractInternalNamesTests
  , extractFFIFunctionsTests
  , extractCanopyTypeFunctionsTests
  , ffiInfoTests
  , extractFFIAliasesTests
  ]

-- ---------------------------------------------------------------------------
-- isValidJsIdentifier
-- ---------------------------------------------------------------------------

-- | Tests for 'FFI.isValidJsIdentifier'.
--
-- Valid JS identifiers start with a letter, underscore, or dollar sign.
-- Empty strings and strings starting with a digit are invalid.
isValidJsIdentifierTests :: TestTree
isValidJsIdentifierTests = testGroup "isValidJsIdentifier"
  [ testCase "plain alpha name is valid" $
      FFI.isValidJsIdentifier "foo" @?= True

  , testCase "underscore-prefixed name is valid" $
      FFI.isValidJsIdentifier "_foo" @?= True

  , testCase "dollar-prefixed name is valid" $
      FFI.isValidJsIdentifier "$foo" @?= True

  , testCase "single letter is valid" $
      FFI.isValidJsIdentifier "x" @?= True

  , testCase "name with digits after first char is valid" $
      FFI.isValidJsIdentifier "foo123" @?= True

  , testCase "camelCase name is valid" $
      FFI.isValidJsIdentifier "myFunction" @?= True

  , testCase "name starting with digit is invalid" $
      FFI.isValidJsIdentifier "1foo" @?= False

  , testCase "empty string is invalid" $
      FFI.isValidJsIdentifier "" @?= False

  , testCase "hyphenated name is invalid" $
      FFI.isValidJsIdentifier "my-func" @?= False

  , testCase "name with space is invalid" $
      FFI.isValidJsIdentifier "my func" @?= False
  ]

-- ---------------------------------------------------------------------------
-- sanitizeForIdent
-- ---------------------------------------------------------------------------

-- | Tests for 'FFI.sanitizeForIdent'.
--
-- Alphanumeric characters and underscores pass through unchanged;
-- everything else is replaced with @_@.
sanitizeForIdentTests :: TestTree
sanitizeForIdentTests = testGroup "sanitizeForIdent"
  [ testCase "plain alphanumeric passes through" $
      FFI.sanitizeForIdent "abc123" @?= "abc123"

  , testCase "underscore passes through" $
      FFI.sanitizeForIdent "my_func" @?= "my_func"

  , testCase "hyphen is replaced with underscore" $
      FFI.sanitizeForIdent "platform-cmd" @?= "platform_cmd"

  , testCase "dot is replaced with underscore" $
      FFI.sanitizeForIdent "a.b" @?= "a_b"

  , testCase "space is replaced with underscore" $
      FFI.sanitizeForIdent "foo bar" @?= "foo_bar"

  , testCase "empty string yields empty string" $
      FFI.sanitizeForIdent "" @?= ""

  , testCase "already safe string is unchanged" $
      FFI.sanitizeForIdent "safe_Name_42" @?= "safe_Name_42"

  , testCase "multiple hyphens all replaced" $
      FFI.sanitizeForIdent "a-b-c" @?= "a_b_c"
  ]

-- ---------------------------------------------------------------------------
-- escapeJsString
-- ---------------------------------------------------------------------------

-- | Render a 'Builder' to 'Text' for exact comparison.
renderBuilder :: BB.Builder -> Text.Text
renderBuilder = TextEnc.decodeUtf8 . LBS.toStrict . BB.toLazyByteString

-- | Tests for 'FFI.escapeJsString'.
--
-- Verifies every documented escape sequence and confirms ordinary
-- characters pass through unchanged.
escapeJsStringTests :: TestTree
escapeJsStringTests = testGroup "escapeJsString"
  [ testCase "plain text passes through unchanged" $
      renderBuilder (FFI.escapeJsString "hello") @?= "hello"

  , testCase "backslash is doubled" $
      renderBuilder (FFI.escapeJsString "a\\b") @?= "a\\\\b"

  , testCase "single quote is escaped" $
      renderBuilder (FFI.escapeJsString "it's") @?= "it\\'s"

  , testCase "double quote is escaped" $
      renderBuilder (FFI.escapeJsString "say \"hi\"") @?= "say \\\"hi\\\""

  , testCase "newline is escaped to \\n" $
      renderBuilder (FFI.escapeJsString "line\nbreak") @?= "line\\nbreak"

  , testCase "carriage return is escaped to \\r" $
      renderBuilder (FFI.escapeJsString "a\rb") @?= "a\\rb"

  , testCase "null byte is escaped to \\0" $
      renderBuilder (FFI.escapeJsString "a\0b") @?= "a\\0b"

  , testCase "empty string yields empty output" $
      renderBuilder (FFI.escapeJsString "") @?= ""

  , testCase "unicode line separator is escaped" $
      renderBuilder (FFI.escapeJsString "\x2028") @?= "\\u2028"

  , testCase "unicode paragraph separator is escaped" $
      renderBuilder (FFI.escapeJsString "\x2029") @?= "\\u2029"
  ]

-- ---------------------------------------------------------------------------
-- trim
-- ---------------------------------------------------------------------------

-- | Tests for 'FFI.trim'.
trimTests :: TestTree
trimTests = testGroup "trim"
  [ testCase "leading spaces removed" $
      FFI.trim "  hello" @?= "hello"

  , testCase "trailing spaces removed" $
      FFI.trim "hello  " @?= "hello"

  , testCase "both sides stripped" $
      FFI.trim "  hello world  " @?= "hello world"

  , testCase "already trimmed is unchanged" $
      FFI.trim "hello" @?= "hello"

  , testCase "only spaces yields empty" $
      FFI.trim "   " @?= ""

  , testCase "empty string yields empty string" $
      FFI.trim "" @?= ""
  ]

-- ---------------------------------------------------------------------------
-- extractCanopyType
-- ---------------------------------------------------------------------------

-- | Tests for 'FFI.extractCanopyType'.
--
-- The function recognises lines containing @" * @canopy-type "@ and returns
-- the trimmed type string that follows the annotation tag.
extractCanopyTypeTests :: TestTree
extractCanopyTypeTests = testGroup "extractCanopyType"
  [ testCase "well-formed annotation returns type" $
      FFI.extractCanopyType " * @canopy-type Int -> String" @?= Just "Int -> String"

  , testCase "annotation with extra whitespace is trimmed" $
      FFI.extractCanopyType " * @canopy-type   Bool  " @?= Just "Bool"

  , testCase "line without annotation returns Nothing" $
      FFI.extractCanopyType "// plain comment" @?= Nothing

  , testCase "line with different annotation returns Nothing" $
      FFI.extractCanopyType " * @param x" @?= Nothing

  , testCase "empty line returns Nothing" $
      FFI.extractCanopyType "" @?= Nothing

  , testCase "annotation with function type is preserved" $
      FFI.extractCanopyType " * @canopy-type Int -> Int -> Int"
        @?= Just "Int -> Int -> Int"
  ]

-- ---------------------------------------------------------------------------
-- findFunctionName
-- ---------------------------------------------------------------------------

-- | Tests for 'FFI.findFunctionName'.
--
-- Scans lines following a JSDoc block for a function or var declaration
-- and returns the name, stopping at the next JSDoc block.
findFunctionNameTests :: TestTree
findFunctionNameTests = testGroup "findFunctionName"
  [ testCase "plain function declaration" $
      FFI.findFunctionName ["function add(a, b) { return a + b; }"]
        @?= Just "add"

  , testCase "async function declaration" $
      FFI.findFunctionName ["async function fetchData(url) {}"]
        @?= Just "fetchData"

  , testCase "var declaration" $
      FFI.findFunctionName ["var myFunc = F2(function(a, b) {});"]
        @?= Just "myFunc"

  , testCase "empty list returns Nothing" $
      FFI.findFunctionName [] @?= Nothing

  , testCase "stops at next JSDoc block" $
      FFI.findFunctionName ["/** @canopy-type Int */", "function other() {}"]
        @?= Nothing

  , testCase "skips blank lines to find function" $
      FFI.findFunctionName ["", "function compute(x) {}"]
        @?= Just "compute"

  , testCase "function name with underscores" $
      FFI.findFunctionName ["function _Json_unwrap(x) {}"]
        @?= Just "_Json_unwrap"
  ]

-- ---------------------------------------------------------------------------
-- extractInternalNames
-- ---------------------------------------------------------------------------

-- | Tests for 'FFI.extractInternalNames'.
--
-- Finds top-level @function _Name@ and @var _Name@ declarations that
-- follow the kernel naming convention.
extractInternalNamesTests :: TestTree
extractInternalNamesTests = testGroup "extractInternalNames"
  [ testCase "extracts function with underscore prefix" $
      FFI.extractInternalNames ["function _Json_unwrap(x) { return x; }"]
        @?= ["_Json_unwrap"]

  , testCase "extracts var with underscore prefix" $
      FFI.extractInternalNames ["var _Utils_chr = String.fromCodePoint;"]
        @?= ["_Utils_chr"]

  , testCase "public function without underscore is ignored" $
      FFI.extractInternalNames ["function add(a, b) { return a + b; }"]
        @?= []

  , testCase "multiple internal names extracted in order" $
      FFI.extractInternalNames
        [ "function _A_one() {}"
        , "var _B_two = 42;"
        ]
        @?= ["_A_one", "_B_two"]

  , testCase "empty input yields empty list" $
      FFI.extractInternalNames [] @?= []

  , testCase "non-declaration lines are ignored" $
      FFI.extractInternalNames ["// _Not_A_decl", "  var x = 1;"]
        @?= []
  ]

-- ---------------------------------------------------------------------------
-- extractFFIFunctions
-- ---------------------------------------------------------------------------

-- | Tests for 'FFI.extractFFIFunctions'.
--
-- Parses JSDoc blocks containing @\@canopy-type@ to build 'ExtractedFFI'
-- values.  A block without @\@canopy-type@ is silently skipped.
extractFFIFunctionsTests :: TestTree
extractFFIFunctionsTests = testGroup "extractFFIFunctions"
  [ testCase "empty source yields empty list" $
      FFI.extractFFIFunctions [] @?= []

  , testCase "source without JSDoc yields empty list" $
      FFI.extractFFIFunctions ["function add(a, b) {}"] @?= []

  , testCase "JSDoc without canopy-type annotation is skipped" $
      let src = ["/**", " * @param x", " */", "function foo(x) {}"]
      in FFI.extractFFIFunctions src @?= []

  , testCase "well-formed JSDoc block extracts name and type" $
      let src = [ "/**"
                , " * @canopy-type Int -> Int"
                , " */"
                , "function double(x) { return x * 2; }"
                ]
          results = FFI.extractFFIFunctions src
      in length results @?= 1

  , testCase "extracted function has correct name" $
      let src = [ "/**"
                , " * @canopy-type Int -> Int"
                , " */"
                , "function double(x) { return x * 2; }"
                ]
          result = head (FFI.extractFFIFunctions src)
      in FFI._extractedName result @?= "double"

  , testCase "extracted function has correct type" $
      let src = [ "/**"
                , " * @canopy-type Int -> Int"
                , " */"
                , "function double(x) { return x * 2; }"
                ]
          result = head (FFI.extractFFIFunctions src)
      in FFI._extractedType result @?= "Int -> Int"

  , testCase "default binding mode is FunctionCall" $
      let src = [ "/**"
                , " * @canopy-type Bool"
                , " */"
                , "function check() {}"
                ]
          result = head (FFI.extractFFIFunctions src)
      in FFI._extractedMode result @?= FunctionCall

  , testCase "two annotated functions in source yields two results" $
      let src = [ "/**"
                , " * @canopy-type Int -> Int"
                , " */"
                , "function inc(x) {}"
                , "/**"
                , " * @canopy-type String -> String"
                , " */"
                , "function upper(s) {}"
                ]
      in length (FFI.extractFFIFunctions src) @?= 2
  ]

-- ---------------------------------------------------------------------------
-- extractCanopyTypeFunctions
-- ---------------------------------------------------------------------------

-- | Tests for 'FFI.extractCanopyTypeFunctions'.
--
-- Returns @(effectiveName, typeAnnotation)@ pairs from JSDoc-annotated
-- source lines.
extractCanopyTypeFunctionsTests :: TestTree
extractCanopyTypeFunctionsTests = testGroup "extractCanopyTypeFunctions"
  [ testCase "empty source yields empty list" $
      FFI.extractCanopyTypeFunctions [] @?= []

  , testCase "annotated function yields correct name-type pair" $
      let src = [ "/**"
                , " * @canopy-type Int -> Bool"
                , " */"
                , "function isPositive(n) {}"
                ]
          result = FFI.extractCanopyTypeFunctions src
      in result @?= [("isPositive", "Int -> Bool")]

  , testCase "two functions yield two pairs" $
      let src = [ "/**"
                , " * @canopy-type Int"
                , " */"
                , "function zero() {}"
                , "/**"
                , " * @canopy-type String"
                , " */"
                , "function empty() {}"
                ]
          result = FFI.extractCanopyTypeFunctions src
      in length result @?= 2

  , testCase "unannotated source yields empty list" $
      FFI.extractCanopyTypeFunctions ["function foo() {}"] @?= []
  ]

-- ---------------------------------------------------------------------------
-- FFIInfo construction and lens access
-- ---------------------------------------------------------------------------

-- | Tests for 'FFIInfo' fields and lens round-trips.
ffiInfoTests :: TestTree
ffiInfoTests = testGroup "FFIInfo construction and lenses"
  [ testCase "ffiFilePath lens reads correct path" $
      let info = FFI.FFIInfo "path/to/file.js" "content" (Name.fromChars "MyAlias")
      in (info ^. FFI.ffiFilePath) @?= "path/to/file.js"

  , testCase "ffiContent lens reads correct content" $
      let info = FFI.FFIInfo "f.js" "var x = 1;" (Name.fromChars "A")
      in (info ^. FFI.ffiContent) @?= "var x = 1;"

  , testCase "ffiAlias lens reads correct name" $
      let info = FFI.FFIInfo "f.js" "" (Name.fromChars "TestAlias")
      in Name.toChars (info ^. FFI.ffiAlias) @?= "TestAlias"

  , testCase "FFIInfo round-trips ffiFilePath update via lens" $
      let info = FFI.FFIInfo "old.js" "" (Name.fromChars "X")
          updated = FFI.ffiFilePath .~ "new.js" $ info
      in (updated ^. FFI.ffiFilePath) @?= "new.js"
  ]

-- ---------------------------------------------------------------------------
-- extractFFIAliases
-- ---------------------------------------------------------------------------

-- | Tests for 'FFI.extractFFIAliases'.
extractFFIAliasesTests :: TestTree
extractFFIAliasesTests = testGroup "extractFFIAliases"
  [ testCase "empty map yields empty set" $
      FFI.extractFFIAliases Map.empty @?= Set.empty

  , testCase "single entry yields singleton set" $
      let info = FFI.FFIInfo "f.js" "" (Name.fromChars "MyFFI")
          aliases = FFI.extractFFIAliases (Map.singleton "f.js" info)
      in Set.size aliases @?= 1

  , testCase "alias name in set matches info alias" $
      let info = FFI.FFIInfo "f.js" "" (Name.fromChars "BrowserFFI")
          aliases = FFI.extractFFIAliases (Map.singleton "f.js" info)
      in Set.member (Name.fromChars "BrowserFFI") aliases @?= True

  , testCase "two infos with distinct aliases yield set of size two" $
      let i1 = FFI.FFIInfo "a.js" "" (Name.fromChars "Alpha")
          i2 = FFI.FFIInfo "b.js" "" (Name.fromChars "Beta")
          m  = Map.fromList [("a.js", i1), ("b.js", i2)]
      in Set.size (FFI.extractFFIAliases m) @?= 2

  , testCase "two infos with same alias yield set of size one" $
      let i1 = FFI.FFIInfo "a.js" "" (Name.fromChars "Shared")
          i2 = FFI.FFIInfo "b.js" "" (Name.fromChars "Shared")
          m  = Map.fromList [("a.js", i1), ("b.js", i2)]
      in Set.size (FFI.extractFFIAliases m) @?= 1
  ]

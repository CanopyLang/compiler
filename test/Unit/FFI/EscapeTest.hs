-- | Unit tests for JavaScript string escaping in FFI module.
--
-- Validates that all dangerous characters are properly escaped
-- when constructing JavaScript string literals for FFI call paths.
--
-- @since 0.19.2
module Unit.FFI.EscapeTest (tests) where

import qualified Generate.JavaScript.FFI as FFI
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "FFI.escapeJsString"
    [ testCase "escapes backslash" $
        FFI.escapeJsString "a\\b" @?= "a\\\\b",
      testCase "escapes single quote" $
        FFI.escapeJsString "it's" @?= "it\\'s",
      testCase "escapes double quote" $
        FFI.escapeJsString "say \"hi\"" @?= "say \\\"hi\\\"",
      testCase "escapes newline" $
        FFI.escapeJsString "a\nb" @?= "a\\nb",
      testCase "escapes carriage return" $
        FFI.escapeJsString "a\rb" @?= "a\\rb",
      testCase "escapes null byte" $
        FFI.escapeJsString "a\0b" @?= "a\\0b",
      testCase "escapes U+2028 LINE SEPARATOR" $
        FFI.escapeJsString ('a' : '\x2028' : "b") @?= "a\\u2028b",
      testCase "escapes U+2029 PARAGRAPH SEPARATOR" $
        FFI.escapeJsString ('a' : '\x2029' : "b") @?= "a\\u2029b",
      testCase "leaves normal characters unchanged" $
        FFI.escapeJsString "hello.world" @?= "hello.world",
      testCase "handles empty string" $
        FFI.escapeJsString "" @?= "",
      testCase "handles multiple special characters" $
        FFI.escapeJsString "'\\\n\0" @?= "\\'\\\\\\n\\0"
    ]

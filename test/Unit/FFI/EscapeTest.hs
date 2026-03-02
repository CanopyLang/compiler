-- | Unit tests for JavaScript string escaping in FFI module.
--
-- Validates that all dangerous characters are properly escaped
-- when constructing JavaScript string literals for FFI call paths.
--
-- @since 0.19.2
module Unit.FFI.EscapeTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Generate.JavaScript.FFI as FFI
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

-- | Convert a Builder to a strict ByteString for assertion comparison.
builderToBS :: BB.Builder -> LBS.ByteString
builderToBS = BB.toLazyByteString

-- | Helper to test escapeJsString with Text input and expected Builder output.
assertEscape :: Text.Text -> LBS.ByteString -> IO ()
assertEscape input expected =
  builderToBS (FFI.escapeJsString input) @?= expected

tests :: TestTree
tests =
  testGroup
    "FFI.escapeJsString"
    [ testCase "escapes backslash" $
        assertEscape "a\\b" "a\\\\b",
      testCase "escapes single quote" $
        assertEscape "it's" "it\\'s",
      testCase "escapes double quote" $
        assertEscape "say \"hi\"" "say \\\"hi\\\"",
      testCase "escapes newline" $
        assertEscape "a\nb" "a\\nb",
      testCase "escapes carriage return" $
        assertEscape "a\rb" "a\\rb",
      testCase "escapes null byte" $
        assertEscape "a\0b" "a\\0b",
      testCase "escapes U+2028 LINE SEPARATOR" $
        assertEscape (Text.pack ['a', '\x2028', 'b']) "a\\u2028b",
      testCase "escapes U+2029 PARAGRAPH SEPARATOR" $
        assertEscape (Text.pack ['a', '\x2029', 'b']) "a\\u2029b",
      testCase "leaves normal characters unchanged" $
        assertEscape "hello.world" "hello.world",
      testCase "handles empty string" $
        assertEscape "" "",
      testCase "handles multiple special characters" $
        assertEscape "'\\\n\0" "\\'\\\\\\n\\0"
    ]

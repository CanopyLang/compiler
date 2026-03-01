{-# LANGUAGE OverloadedStrings #-}

-- | Security tests for HTML code generation.
--
-- Verifies that generated HTML includes Content-Security-Policy headers
-- and that HTML attribute values are properly escaped to prevent injection.
--
-- @since 0.19.2
module Unit.Generate.HtmlSecurityTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Generate.Html as Html
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Generate.Html Security"
    [ cspTests,
      htmlEscapeTests,
      prefetchSecurityTests
    ]

-- CSP HEADER TESTS

cspTests :: TestTree
cspTests =
  Test.testGroup
    "Content-Security-Policy"
    [ Test.testCase "sandwich includes CSP meta tag" $
        let output = renderSandwich (Name.fromChars "Main") mempty
         in Test.assertBool "CSP meta tag missing" (containsCSP output),
      Test.testCase "sandwichWithPrefetch includes CSP meta tag" $
        let output = renderSandwichPrefetch (Name.fromChars "Main") mempty []
         in Test.assertBool "CSP meta tag missing" (containsCSP output),
      Test.testCase "CSP restricts default-src to self" $
        let output = renderSandwich (Name.fromChars "Main") mempty
         in Test.assertBool "default-src 'self' missing" (containsText "default-src 'self'" output),
      Test.testCase "CSP restricts script-src to unsafe-inline" $
        let output = renderSandwich (Name.fromChars "Main") mempty
         in Test.assertBool "script-src 'unsafe-inline' missing" (containsText "script-src 'unsafe-inline'" output),
      Test.testCase "HTML output is valid HTML5" $
        let output = renderSandwich (Name.fromChars "Main") mempty
         in Test.assertBool "DOCTYPE missing" (containsText "<!DOCTYPE HTML>" output)
    ]

-- HTML ATTRIBUTE ESCAPE TESTS

htmlEscapeTests :: TestTree
htmlEscapeTests =
  Test.testGroup
    "HTML attribute escaping"
    [ Test.testCase "ampersand is escaped" $
        Html.escapeHtmlAttr "a&b" @?= "a&amp;b",
      Test.testCase "double quote is escaped" $
        Html.escapeHtmlAttr "a\"b" @?= "a&quot;b",
      Test.testCase "single quote is escaped" $
        Html.escapeHtmlAttr "a'b" @?= "a&#39;b",
      Test.testCase "less-than is escaped" $
        Html.escapeHtmlAttr "a<b" @?= "a&lt;b",
      Test.testCase "greater-than is escaped" $
        Html.escapeHtmlAttr "a>b" @?= "a&gt;b",
      Test.testCase "plain text is unchanged" $
        Html.escapeHtmlAttr "hello world" @?= "hello world",
      Test.testCase "empty string is unchanged" $
        Html.escapeHtmlAttr "" @?= "",
      Test.testCase "multiple special chars escaped" $
        Html.escapeHtmlAttr "<script>alert('xss')</script>"
          @?= "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;",
      Test.testCase "attribute breakout attempt is neutralized" $
        Html.escapeHtmlAttr "\" onload=\"alert(1)" @?= "&quot; onload=&quot;alert(1)"
    ]

-- PREFETCH SECURITY TESTS

prefetchSecurityTests :: TestTree
prefetchSecurityTests =
  Test.testGroup
    "Prefetch tag security"
    [ Test.testCase "prefetch with clean filename" $
        let output = renderSandwichPrefetch (Name.fromChars "Main") mempty ["chunk-0.js"]
         in Test.assertBool "prefetch tag missing" (containsText "rel=\"prefetch\" href=\"chunk-0.js\"" output),
      Test.testCase "prefetch escapes malicious filename" $
        let output = renderSandwichPrefetch (Name.fromChars "Main") mempty ["\" onload=\"alert(1)"]
         in do
              Test.assertBool "raw quote should not appear in href" (not (containsText "\" onload=" output)),
      Test.testCase "prefetch with no chunks produces no link tags" $
        let output = renderSandwichPrefetch (Name.fromChars "Main") mempty []
         in Test.assertBool "unexpected prefetch tag" (not (containsText "rel=\"prefetch\"" output)),
      Test.testCase "prefetch escapes angle brackets in filename" $
        let output = renderSandwichPrefetch (Name.fromChars "Main") mempty ["<img src=x>"]
         in Test.assertBool "raw angle bracket should not appear" (not (containsText "<img" output))
    ]

-- HELPERS

-- | Render sandwich output to a lazy ByteString.
renderSandwich :: Name.Name -> BB.Builder -> BL8.ByteString
renderSandwich name js = BB.toLazyByteString (Html.sandwich name js)

-- | Render sandwichWithPrefetch output to a lazy ByteString.
renderSandwichPrefetch :: Name.Name -> BB.Builder -> [FilePath] -> BL8.ByteString
renderSandwichPrefetch name js chunks = BB.toLazyByteString (Html.sandwichWithPrefetch name js chunks)

-- | Check if a string is contained in the output.
containsCSP :: BL8.ByteString -> Bool
containsCSP = containsText "Content-Security-Policy"

-- | Check if a plain string appears in a lazy ByteString.
containsText :: String -> BL8.ByteString -> Bool
containsText needle haystack =
  BL8.pack needle `isInfixOfLazy` haystack

-- | Check if a lazy ByteString is an infix of another.
isInfixOfLazy :: BL8.ByteString -> BL8.ByteString -> Bool
isInfixOfLazy n h = any (BL8.isPrefixOf n) (BL8.tails h)

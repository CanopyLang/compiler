{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -Wall #-}

-- | Tests for the @[c|...|]@ color quasi-quoter.
module Unit.Reporting.Doc.ColorQQTest (tests) where

import Reporting.Doc.ColorQQ (c)
import qualified Reporting.Doc as D
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Reporting.Doc.ColorQQ Tests"
    [ literalTests,
      interpolationTests,
      docEmbeddingTests,
      colorTests,
      multilineTests,
      escapeTests,
      combinationTests
    ]

literalTests :: TestTree
literalTests =
  testGroup
    "literal text"
    [ testCase "simple literal" $
        D.toString [c|Hello, world!|] @?= "Hello, world!",
      testCase "empty QQ" $
        D.toString [c||] @?= "",
      testCase "literal with punctuation" $
        D.toString [c|Error: file not found.|] @?= "Error: file not found."
    ]

interpolationTests :: TestTree
interpolationTests =
  testGroup
    "variable interpolation"
    [ testCase "single variable" $
        let path = "/usr/local" :: String
         in D.toString [c|Load from #{path}|] @?= "Load from /usr/local",
      testCase "variable in middle" $
        let name = "Main" :: String
         in D.toString [c|Module #{name} not found|] @?= "Module Main not found",
      testCase "multiple variables" $
        let src = "Foo" :: String
            dst = "Bar" :: String
         in D.toString [c|Rename #{src} to #{dst}|] @?= "Rename Foo to Bar",
      testCase "adjacent to literal" $
        let x = "ok" :: String
         in D.toString [c|#{x}!|] @?= "ok!"
    ]

docEmbeddingTests :: TestTree
docEmbeddingTests =
  testGroup
    "Doc embedding"
    [ testCase "embed a Doc value" $
        let detail = D.fromChars "some detail"
         in D.toString [c|Error: @{detail}|] @?= "Error: some detail",
      testCase "embed colored Doc" $
        let note = D.fromChars "important"
         in D.toString [c|See @{note} here|] @?= "See important here"
    ]

colorTests :: TestTree
colorTests =
  testGroup
    "color markup"
    [ testCase "red" $
        D.toString [c|{red|ERROR}|] @?= "ERROR",
      testCase "green" $
        D.toString [c|{green|OK}|] @?= "OK",
      testCase "blue" $
        D.toString [c|{blue|info}|] @?= "info",
      testCase "cyan" $
        D.toString [c|{cyan|hint}|] @?= "hint",
      testCase "magenta" $
        D.toString [c|{magenta|note}|] @?= "note",
      testCase "yellow" $
        D.toString [c|{yellow|warn}|] @?= "warn",
      testCase "black" $
        D.toString [c|{black|dark}|] @?= "dark",
      testCase "white" $
        D.toString [c|{white|light}|] @?= "light",
      testCase "dullred" $
        D.toString [c|{dullred|muted}|] @?= "muted",
      testCase "dullgreen" $
        D.toString [c|{dullgreen|subtle}|] @?= "subtle",
      testCase "dullblue" $
        D.toString [c|{dullblue|dim}|] @?= "dim",
      testCase "dullcyan" $
        D.toString [c|{dullcyan|soft}|] @?= "soft",
      testCase "dullmagenta" $
        D.toString [c|{dullmagenta|faded}|] @?= "faded",
      testCase "dullyellow" $
        D.toString [c|{dullyellow|pale}|] @?= "pale",
      testCase "bold" $
        D.toString [c|{bold|strong}|] @?= "strong",
      testCase "underline" $
        D.toString [c|{underline|emphasis}|] @?= "emphasis",
      testCase "color with surrounding text" $
        D.toString [c|{red|ERROR}: No canopy.json found.|]
          @?= "ERROR: No canopy.json found.",
      testCase "color preserves in encode" $
        let encoded = show (D.encode [c|{red|ERROR}|])
         in assertBool "encode output should contain red" ("red" `elem` words encoded
              || "RED" `elem` words encoded
              || "\"red\"" `elem` words encoded)
    ]

multilineTests :: TestTree
multilineTests =
  testGroup
    "multiline handling"
    [ testCase "newline becomes line break" $
        let result = D.toString [c|line one
line two|]
         in result @?= "line one\nline two",
      testCase "multiple newlines" $
        let result = D.toString [c|a
b
c|]
         in result @?= "a\nb\nc"
    ]

escapeTests :: TestTree
escapeTests =
  testGroup
    "brace escaping"
    [ testCase "escaped open brace" $
        D.toString [c|Use {{red|..}} for color.|] @?= "Use {red|..} for color.",
      testCase "double escaped braces" $
        D.toString [c|a {{b}} c|] @?= "a {b} c"
    ]

combinationTests :: TestTree
combinationTests =
  testGroup
    "combined features"
    [ testCase "color and interpolation" $
        let path = "/src/Main.can" :: String
         in D.toString [c|{red|ERROR}: Load from {cyan|#{path}}|]
              @?= "ERROR: Load from /src/Main.can",
      testCase "nested color with text" $
        D.toString [c|{red|ERROR}: {cyan|hint} here|]
          @?= "ERROR: hint here",
      testCase "doc embed with color" $
        let detail = D.fromChars "detail"
         in D.toString [c|{red|ERROR}: @{detail}|]
              @?= "ERROR: detail"
    ]

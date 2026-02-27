{-# LANGUAGE QuasiQuotes #-}

-- | Tests for the @[c|...|]@ color quasi-quoter.
module Unit.Reporting.Doc.ColorQQTest (tests) where

import Data.List (isInfixOf)
import Reporting.Doc.ColorQQ (c)
import qualified Reporting.Doc as Doc
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
        Doc.toString [c|Hello, world!|] @?= "Hello, world!",
      testCase "empty QQ" $
        Doc.toString [c||] @?= "",
      testCase "literal with punctuation" $
        Doc.toString [c|Error: file not found.|] @?= "Error: file not found."
    ]

interpolationTests :: TestTree
interpolationTests =
  testGroup
    "variable interpolation"
    [ testCase "single variable" $
        let path = "/usr/local" :: String
         in Doc.toString [c|Load from #{path}|] @?= "Load from /usr/local",
      testCase "variable in middle" $
        let name = "Main" :: String
         in Doc.toString [c|Module #{name} not found|] @?= "Module Main not found",
      testCase "multiple variables" $
        let src = "Foo" :: String
            dst = "Bar" :: String
         in Doc.toString [c|Rename #{src} to #{dst}|] @?= "Rename Foo to Bar",
      testCase "adjacent to literal" $
        let x = "ok" :: String
         in Doc.toString [c|#{x}!|] @?= "ok!"
    ]

docEmbeddingTests :: TestTree
docEmbeddingTests =
  testGroup
    "Doc embedding"
    [ testCase "embed a Doc value" $
        let detail = Doc.fromChars "some detail"
         in Doc.toString [c|Error: @{detail}|] @?= "Error: some detail",
      testCase "embed colored Doc" $
        let note = Doc.fromChars "important"
         in Doc.toString [c|See @{note} here|] @?= "See important here"
    ]

colorTests :: TestTree
colorTests =
  testGroup
    "color markup"
    [ testCase "red" $
        Doc.toString [c|{red|ERROR}|] @?= "ERROR",
      testCase "green" $
        Doc.toString [c|{green|OK}|] @?= "OK",
      testCase "blue" $
        Doc.toString [c|{blue|info}|] @?= "info",
      testCase "cyan" $
        Doc.toString [c|{cyan|hint}|] @?= "hint",
      testCase "magenta" $
        Doc.toString [c|{magenta|note}|] @?= "note",
      testCase "yellow" $
        Doc.toString [c|{yellow|warn}|] @?= "warn",
      testCase "black" $
        Doc.toString [c|{black|dark}|] @?= "dark",
      testCase "white" $
        Doc.toString [c|{white|light}|] @?= "light",
      testCase "dullred" $
        Doc.toString [c|{dullred|muted}|] @?= "muted",
      testCase "dullgreen" $
        Doc.toString [c|{dullgreen|subtle}|] @?= "subtle",
      testCase "dullblue" $
        Doc.toString [c|{dullblue|dim}|] @?= "dim",
      testCase "dullcyan" $
        Doc.toString [c|{dullcyan|soft}|] @?= "soft",
      testCase "dullmagenta" $
        Doc.toString [c|{dullmagenta|faded}|] @?= "faded",
      testCase "dullyellow" $
        Doc.toString [c|{dullyellow|pale}|] @?= "pale",
      testCase "bold" $
        Doc.toString [c|{bold|strong}|] @?= "strong",
      testCase "underline" $
        Doc.toString [c|{underline|emphasis}|] @?= "emphasis",
      testCase "color with surrounding text" $
        Doc.toString [c|{red|ERROR}: No canopy.json found.|]
          @?= "ERROR: No canopy.json found.",
      testCase "color preserves in encode" $
        let encoded = show (Doc.encode [c|{red|ERROR}|])
         in assertBool "encode output should contain RED (vivid)" ("RED" `isInfixOf` encoded)
    ]

multilineTests :: TestTree
multilineTests =
  testGroup
    "multiline handling"
    [ testCase "newline becomes line break" $
        let result = Doc.toString [c|line one
line two|]
         in result @?= "line one\nline two",
      testCase "multiple newlines" $
        let result = Doc.toString [c|a
b
c|]
         in result @?= "a\nb\nc"
    ]

escapeTests :: TestTree
escapeTests =
  testGroup
    "brace escaping"
    [ testCase "escaped open brace" $
        Doc.toString [c|Use {{red|..}} for color.|] @?= "Use {red|..} for color.",
      testCase "double escaped braces" $
        Doc.toString [c|a {{b}} c|] @?= "a {b} c"
    ]

combinationTests :: TestTree
combinationTests =
  testGroup
    "combined features"
    [ testCase "color and interpolation" $
        let path = "/src/Main.can" :: String
         in Doc.toString [c|{red|ERROR}: Load from {cyan|#{path}}|]
              @?= "ERROR: Load from /src/Main.can",
      testCase "nested color with text" $
        Doc.toString [c|{red|ERROR}: {cyan|hint} here|]
          @?= "ERROR: hint here",
      testCase "doc embed with color" $
        let detail = Doc.fromChars "detail"
         in Doc.toString [c|{red|ERROR}: @{detail}|]
              @?= "ERROR: detail"
    ]

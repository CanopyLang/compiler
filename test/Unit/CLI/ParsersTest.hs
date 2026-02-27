{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for CLI.Parsers module.
--
-- Tests command-line argument parsers, verifying correct parsing behavior,
-- validation, and error handling for interpreter and port parsers.
module Unit.CLI.ParsersTest (tests) where

import CLI.Parsers (createInterpreterParser, createPortParser)
import qualified Terminal
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

-- | All unit tests for CLI parser functionality.
tests :: TestTree
tests =
  testGroup
    "CLI Parsers Tests"
    [ testInterpreterParser,
      testPortParser
    ]

-- | Test interpreter path parser functionality.
testInterpreterParser :: TestTree
testInterpreterParser =
  testGroup
    "createInterpreterParser function"
    [ testCase "parser has correct singular form" $ do
        let parser = createInterpreterParser
        Terminal._singular parser @?= "interpreter",
      testCase "parser has correct plural form" $ do
        let parser = createInterpreterParser
        Terminal._plural parser @?= "interpreters",
      testCase "parser accepts node" $ do
        let parser = createInterpreterParser
            result = Terminal._parser parser "node"
        result @?= Just "node",
      testCase "parser accepts nodejs" $ do
        let parser = createInterpreterParser
            result = Terminal._parser parser "nodejs"
        result @?= Just "nodejs",
      testCase "parser accepts custom path" $ do
        let parser = createInterpreterParser
            result = Terminal._parser parser "/usr/bin/node"
        result @?= Just "/usr/bin/node",
      testCase "parser accepts empty string" $ do
        let parser = createInterpreterParser
            result = Terminal._parser parser ""
        result @?= Just ""
    ]

-- | Test port number parser functionality.
testPortParser :: TestTree
testPortParser =
  testGroup
    "createPortParser function"
    [ testCase "parser has correct singular form" $ do
        let parser = createPortParser
        Terminal._singular parser @?= "port",
      testCase "parser has correct plural form" $ do
        let parser = createPortParser
        Terminal._plural parser @?= "ports",
      testCase "parser accepts valid port 3000" $ do
        let parser = createPortParser
            result = Terminal._parser parser "3000"
        result @?= Just 3000,
      testCase "parser accepts valid port 8000" $ do
        let parser = createPortParser
            result = Terminal._parser parser "8000"
        result @?= Just 8000,
      testCase "parser accepts port 80" $ do
        let parser = createPortParser
            result = Terminal._parser parser "80"
        result @?= Just 80,
      testCase "parser accepts port 65535" $ do
        let parser = createPortParser
            result = Terminal._parser parser "65535"
        result @?= Just 65535,
      testCase "parser rejects non-numeric input" $ do
        let parser = createPortParser
            result = Terminal._parser parser "abc"
        result @?= Nothing,
      testCase "parser rejects empty string" $ do
        let parser = createPortParser
            result = Terminal._parser parser ""
        result @?= Nothing,
      testCase "parser rejects negative numbers" $ do
        let parser = createPortParser
            result = Terminal._parser parser "-1"
        result @?= Nothing
    ]

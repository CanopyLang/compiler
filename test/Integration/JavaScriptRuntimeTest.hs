{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Runtime behavior testing for JavaScript generation.
--
-- This module tests that generated JavaScript actually executes correctly
-- and produces the expected results, rather than comparing string output.
-- This approach is more robust and focuses on correctness over exact formatting.
--
-- @since 0.19.1
module Integration.JavaScriptRuntimeTest
  ( tests
  , RuntimeTest(..)
  , executeJS
  , validateSyntax
  ) where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import Control.Exception (SomeException, try)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.NonEmptyList as NE
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified Generate
import qualified Language.JavaScript.Parser as JS
import qualified Reporting
import qualified Reporting.Task as Task
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcess)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool, assertFailure)

-- | Runtime test case definition
data RuntimeTest = RuntimeTest
  { rtName :: !Text.Text
  , rtCanopySource :: !Text.Text
  , rtExpectedOutput :: !Text.Text
  , rtDescription :: !Text.Text
  } deriving (Eq, Show)

-- | All runtime behavior tests
tests :: TestTree
tests = testGroup "JavaScript Runtime Tests"
  [ testGroup "Basic Operations"
      [ testRuntimeBehavior basicArithmetic
      , testRuntimeBehavior stringOperations
      , testRuntimeBehavior functionComposition
      ]
  , testGroup "JavaScript Validation"
      [ testJSSyntax basicArithmetic
      , testJSSyntax stringOperations
      , testJSSyntax functionComposition
      ]
  ]

-- | Test that generated JS executes and produces expected output
testRuntimeBehavior :: RuntimeTest -> TestTree
testRuntimeBehavior rt = testCase (Text.unpack (rtName rt)) $ do
  jsCode <- generateCanopyJS rt
  result <- executeJS jsCode
  case result of
    Left err -> assertFailure ("JS execution failed: " ++ err)
    Right output ->
      Text.strip output @?= Text.strip (rtExpectedOutput rt)

-- | Test that generated JS is syntactically valid
testJSSyntax :: RuntimeTest -> TestTree
testJSSyntax rt = testCase (Text.unpack (rtName rt) ++ " (syntax)") $ do
  jsCode <- generateCanopyJS rt
  case validateSyntax jsCode of
    Left err -> assertFailure ("Invalid JavaScript syntax: " ++ err)
    Right _ -> pure ()

-- | Generate JavaScript code from Canopy source
generateCanopyJS :: RuntimeTest -> IO BL.ByteString
generateCanopyJS rt =
  withSystemTempDirectory "canopy-runtime-test" $ \tmpDir -> do
    setupCanopyProject tmpDir (rtCanopySource rt)
    compileToJS tmpDir

-- | Setup a Canopy project for testing
setupCanopyProject :: FilePath -> Text.Text -> IO ()
setupCanopyProject root source = do
  createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJsonConfig
  writeFile (root </> "src" </> "Main.can") (Text.unpack source)

-- | Compile Canopy project to JavaScript
compileToJS :: FilePath -> IO BL.ByteString
compileToJS tmpDir = do
  details <- BW.withScope $ \scope -> do
    result <- Details.load Reporting.silent scope tmpDir
    case result of
      Left _err -> error "Failed to load details"
      Right d -> pure d

  let srcFile = tmpDir </> "src" </> "Main.can"
  artifactsResult <- Build.fromPaths Reporting.silent tmpDir details (NE.List srcFile [])

  case artifactsResult of
    Left _err -> error "Build failed"
    Right artifacts -> do
      genResult <- Task.run (Generate.dev tmpDir details artifacts)
      case genResult of
        Left _err -> error "Generate failed"
        Right builder -> pure (BB.toLazyByteString builder)

-- | Execute JavaScript code and capture output
executeJS :: BL.ByteString -> IO (Either String Text.Text)
executeJS jsCode = do
  result <- try $ do
    let jsString = BL8.unpack jsCode
    -- Create a wrapper that captures console.log output
    let wrappedJS = unlines
          [ "let output = [];"
          , "let originalLog = console.log;"
          , "console.log = (...args) => { output.push(args.map(String).join(' ')); };"
          , jsString
          , "console.log = originalLog;"
          , "if (typeof global !== 'undefined') {"
          , "  if (typeof global.Elm !== 'undefined' && global.Elm.Main) {"
          , "    // Try to run Elm app and capture output"
          , "  }"
          , "}"
          , "console.log(output.join('\\n'));"
          ]

    nodeOutput <- readProcess "node" ["-e", wrappedJS] ""
    pure (Text.pack (lines nodeOutput !! 0))  -- Get first line of output

  case result of
    Left (err :: SomeException) -> pure (Left (show err))
    Right output -> pure (Right output)

-- | Validate JavaScript syntax using the JS parser
validateSyntax :: BL.ByteString -> Either String ()
validateSyntax jsCode =
  case JS.parse (BL8.unpack jsCode) "" of
    Left err -> Left (show err)
    Right _ -> Right ()

-- | Standard canopy.json configuration for tests
canopyJsonConfig :: String
canopyJsonConfig = unlines
  [ "{"
  , "  \"type\": \"application\","
  , "  \"source-directories\": [\"src\"],"
  , "  \"canopy-version\": \"0.19.1\","
  , "  \"dependencies\": {"
  , "    \"direct\": {"
  , "      \"elm/core\": \"1.0.5\","
  , "      \"elm/html\": \"1.0.0\""
  , "    },"
  , "    \"indirect\": {"
  , "      \"elm/json\": \"1.1.3\","
  , "      \"elm/virtual-dom\": \"1.0.3\""
  , "    }"
  , "  },"
  , "  \"test-dependencies\": {"
  , "    \"direct\": {},"
  , "    \"indirect\": {}"
  , "  }"
  , "}"
  ]

-- =============================================================================
-- Test Cases
-- =============================================================================

-- | Basic arithmetic operations test
basicArithmetic :: RuntimeTest
basicArithmetic = RuntimeTest
  { rtName = "basic-arithmetic"
  , rtDescription = "Test basic arithmetic with function composition"
  , rtCanopySource = Text.unlines
      [ "module Main exposing (main, add, mul, compose)"
      , ""
      , "import Html exposing (text)"
      , ""
      , "add x y = x + y"
      , "mul x y = x * y"
      , "compose f g x = f (g x)"
      , ""
      , "main = text (String.fromInt (compose (add 1) (mul 2) 3))"
      ]
  , rtExpectedOutput = "7"  -- mul 2 3 = 6, add 1 6 = 7
  }

-- | String operations test
stringOperations :: RuntimeTest
stringOperations = RuntimeTest
  { rtName = "string-operations"
  , rtDescription = "Test string concatenation and transformation"
  , rtCanopySource = Text.unlines
      [ "module Main exposing (main)"
      , ""
      , "import Html exposing (text)"
      , ""
      , "greet name = \"Hello, \" ++ name ++ \"!\""
      , ""
      , "main = text (greet \"Canopy\")"
      ]
  , rtExpectedOutput = "Hello, Canopy!"
  }

-- | Function composition test
functionComposition :: RuntimeTest
functionComposition = RuntimeTest
  { rtName = "function-composition"
  , rtDescription = "Test higher-order function composition"
  , rtCanopySource = Text.unlines
      [ "module Main exposing (main)"
      , ""
      , "import Html exposing (text)"
      , ""
      , "double x = x * 2"
      , "increment x = x + 1"
      , "pipe f g x = g (f x)"
      , ""
      , "result = pipe double increment 5"
      , ""
      , "main = text (String.fromInt result)"
      ]
  , rtExpectedOutput = "11"  -- double 5 = 10, increment 10 = 11
  }
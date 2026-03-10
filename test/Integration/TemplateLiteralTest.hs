{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for template literal compilation.
--
-- Tests the full compilation pipeline for backtick template literals,
-- including successful compilation, type error rejection, and
-- JavaScript code generation correctness.
--
-- @since 0.19.2
module Integration.TemplateLiteralTest (tests) where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Generate
import qualified Reporting
import qualified Reporting.Task as Task
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase)

tests :: TestTree
tests =
  testGroup
    "Template Literal Integration"
    [ testSuccessfulCompilation,
      testTypeErrorRejection,
      testCodeGeneration
    ]

-- SUCCESSFUL COMPILATION

testSuccessfulCompilation :: TestTree
testSuccessfulCompilation =
  testGroup
    "successful compilation"
    [ testCase "simple interpolation compiles" $
        assertCompiles simpleInterp,
      testCase "plain template literal compiles" $
        assertCompiles plainTemplate,
      testCase "empty template literal compiles" $
        assertCompiles emptyTemplate,
      testCase "nested template literal compiles" $
        assertCompiles nestedTemplate,
      testCase "template with String.fromInt compiles" $
        assertCompiles fromIntTemplate,
      testCase "template with if expression compiles" $
        assertCompiles ifExprTemplate,
      testCase "template with let expression compiles" $
        assertCompiles letExprTemplate,
      testCase "template in list compiles" $
        assertCompiles templateInList
    ]

-- TYPE ERROR REJECTION

testTypeErrorRejection :: TestTree
testTypeErrorRejection =
  testGroup
    "type error rejection"
    [ testCase "Int in template literal fails" $
        assertFailsToCompile intInTemplate,
      testCase "Bool in template literal fails" $
        assertFailsToCompile boolInTemplate,
      testCase "List in template literal fails" $
        assertFailsToCompile listInTemplate,
      testCase "Float in template literal fails" $
        assertFailsToCompile floatInTemplate
    ]

-- CODE GENERATION

testCodeGeneration :: TestTree
testCodeGeneration =
  testGroup
    "code generation"
    [ testCase "generates string concatenation" $
        assertOutputContains simpleInterp "$author$project$Main$greeting",
      testCase "plain template generates string literal" $
        assertOutputContains plainTemplate "$author$project$Main$plain",
      testCase "empty template generates empty string" $
        assertOutputContains emptyTemplate "$author$project$Main$empty"
    ]

-- TEST MODULES

simpleInterp :: String
simpleInterp =
  unlines
    [ "module Main exposing (main, greeting)",
      "",
      "import Html exposing (text)",
      "",
      "greeting : String -> String -> String",
      "greeting first last =",
      "    `Hello ${first} ${last}!`",
      "",
      "main = text (greeting \"World\" \"!\")"
    ]

plainTemplate :: String
plainTemplate =
  unlines
    [ "module Main exposing (main, plain)",
      "",
      "import Html exposing (text)",
      "",
      "plain : String",
      "plain = `just a string`",
      "",
      "main = text plain"
    ]

emptyTemplate :: String
emptyTemplate =
  unlines
    [ "module Main exposing (main, empty)",
      "",
      "import Html exposing (text)",
      "",
      "empty : String",
      "empty = ``",
      "",
      "main = text empty"
    ]

nestedTemplate :: String
nestedTemplate =
  unlines
    [ "module Main exposing (main, nested)",
      "",
      "import Html exposing (text)",
      "",
      "nested : String -> String",
      "nested name =",
      "    `outer ${`inner ${name}`}`",
      "",
      "main = text (nested \"world\")"
    ]

fromIntTemplate :: String
fromIntTemplate =
  unlines
    [ "module Main exposing (main, display)",
      "",
      "import Html exposing (text)",
      "",
      "display : Int -> String",
      "display count =",
      "    `You have ${String.fromInt count} items`",
      "",
      "main = text (display 42)"
    ]

ifExprTemplate :: String
ifExprTemplate =
  unlines
    [ "module Main exposing (main, greet)",
      "",
      "import Html exposing (text)",
      "",
      "greet : Bool -> String -> String",
      "greet formal name =",
      "    `${if formal then \"Dear\" else \"Hey\"} ${name}`",
      "",
      "main = text (greet True \"Alice\")"
    ]

letExprTemplate :: String
letExprTemplate =
  unlines
    [ "module Main exposing (main, format)",
      "",
      "import Html exposing (text)",
      "",
      "format : String -> String -> String",
      "format first last =",
      "    let",
      "        full = `${first} ${last}`",
      "    in",
      "    `Name: ${full}`",
      "",
      "main = text (format \"Jane\" \"Doe\")"
    ]

templateInList :: String
templateInList =
  unlines
    [ "module Main exposing (main, items)",
      "",
      "import Html exposing (text)",
      "",
      "items : String -> String -> List String",
      "items a b =",
      "    [ `item: ${a}`",
      "    , `item: ${b}`",
      "    ]",
      "",
      "main = text (String.concat (items \"x\" \"y\"))"
    ]

intInTemplate :: String
intInTemplate =
  unlines
    [ "module Main exposing (main)",
      "",
      "import Html exposing (text)",
      "",
      "main = text `count: ${42}`"
    ]

boolInTemplate :: String
boolInTemplate =
  unlines
    [ "module Main exposing (main)",
      "",
      "import Html exposing (text)",
      "",
      "main = text `flag: ${True}`"
    ]

listInTemplate :: String
listInTemplate =
  unlines
    [ "module Main exposing (main)",
      "",
      "import Html exposing (text)",
      "",
      "main = text `items: ${[1, 2, 3]}`"
    ]

floatInTemplate :: String
floatInTemplate =
  unlines
    [ "module Main exposing (main)",
      "",
      "import Html exposing (text)",
      "",
      "main = text `pi: ${3.14}`"
    ]

-- HELPERS

assertCompiles :: String -> IO ()
assertCompiles src =
  withSystemTempDirectory "can-tl-test" $ \tmp -> do
    setupProject tmp src
    result <- tryBuild tmp
    case result of
      Left msg -> assertFailure ("Expected compilation to succeed: " <> msg)
      Right _ -> return ()

assertFailsToCompile :: String -> IO ()
assertFailsToCompile src =
  withSystemTempDirectory "can-tl-test" $ \tmp -> do
    setupProject tmp src
    result <- tryBuild tmp
    case result of
      Left _ -> return ()
      Right _ -> assertFailure "Expected type error, but compilation succeeded"

assertOutputContains :: String -> String -> IO ()
assertOutputContains src needle =
  withSystemTempDirectory "can-tl-test" $ \tmp -> do
    setupProject tmp src
    result <- tryBuildAndGenerate tmp
    case result of
      Left msg -> assertFailure ("Build failed: " <> msg)
      Right output ->
        assertBool
          ("Expected output to contain: " <> needle)
          (BL8.pack needle `isInfixOfLazy` output)

tryBuild :: FilePath -> IO (Either String ())
tryBuild tmp = do
  detailsE <- BW.withScope $ \scope ->
    Details.load Reporting.silent scope tmp
  case detailsE of
    Left _ -> return (Left "details load failed")
    Right details -> do
      let srcFile = tmp </> "src" </> "Main.can"
      artifactsE <- Build.fromPaths Reporting.silent tmp details [srcFile]
      case artifactsE of
        Left _ -> return (Left "build failed (type error)")
        Right _ -> return (Right ())

tryBuildAndGenerate :: FilePath -> IO (Either String BL8.ByteString)
tryBuildAndGenerate tmp = do
  detailsE <- BW.withScope $ \scope ->
    Details.load Reporting.silent scope tmp
  case detailsE of
    Left _ -> return (Left "details load failed")
    Right details -> do
      let srcFile = tmp </> "src" </> "Main.can"
      artifactsE <- Build.fromPaths Reporting.silent tmp details [srcFile]
      case artifactsE of
        Left _ -> return (Left "build failed")
        Right artifacts -> do
          genE <- Task.run (Generate.dev tmp details artifacts)
          case genE of
            Left _ -> return (Left "generate failed")
            Right builder -> return (Right (BB.toLazyByteString builder))

setupProject :: FilePath -> String -> IO ()
setupProject root src = do
  createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJson
  writeFile (root </> "src" </> "Main.can") src

canopyJson :: String
canopyJson =
  unlines
    [ "{",
      "  \"type\": \"application\",",
      "  \"source-directories\": [\"src\"],",
      "  \"canopy-version\": \"0.19.1\",",
      "  \"dependencies\": {",
      "      \"direct\": {",
      "          \"canopy/core\": \"1.0.5\",",
      "          \"canopy/html\": \"1.0.0\"",
      "      },",
      "      \"indirect\": {",
      "          \"canopy/json\": \"1.1.3\",",
      "          \"canopy/virtual-dom\": \"1.0.3\"",
      "      }",
      "  },",
      "  \"test-dependencies\": {",
      "      \"direct\": {},",
      "      \"indirect\": {}",
      "  }",
      "}"
    ]

isInfixOfLazy :: BL8.ByteString -> BL8.ByteString -> Bool
isInfixOfLazy needle haystack =
  any (BL8.isPrefixOf needle) (BL8.tails haystack)

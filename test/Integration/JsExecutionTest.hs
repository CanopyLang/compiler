{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests that compile Canopy source to JavaScript and execute
-- it via Node.js, verifying runtime correctness.
--
-- These tests exercise the full compilation pipeline end-to-end:
-- parse → canonicalize → type-check → optimize → generate JS → run.
--
-- == Strategy
--
-- Each test creates a temporary Canopy project, compiles it to a single
-- IIFE file using @canopy make --output-format=iife@, then executes via
-- @node@. Programs use @Debug.log@ to produce observable output to stderr
-- during module evaluation. The Platform FFI crash after evaluation is
-- expected and ignored — we only care about the @Debug.log@ output.
--
-- Requires:
--
--   * @canopy@ binary built via @stack build@
--   * @node@ available on @PATH@
--   * @canopy\/core@ and @canopy\/html@ installed in the package cache
--
-- @since 0.19.2
module Integration.JsExecutionTest (tests) where

import qualified Data.List as List
import qualified System.Directory as Dir
import qualified System.Exit as Exit
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import qualified System.Process as Process
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase)

-- | All JS execution tests.
tests :: TestTree
tests =
  testGroup
    "JsExecution"
    [ testArithmetic,
      testStringConcat,
      testCustomTypePatternMatch,
      testRecordAccess,
      testHigherOrderFunctions,
      testLetBindings,
      testBooleanLogic,
      testListOperations,
      testNestedPatternMatch,
      testRecursion
    ]

-- | Compile a Canopy application and run it, returning Debug.log output.
--
-- Creates a temp project, compiles with @canopy make --output-format=iife@,
-- runs via @node@, and extracts @RESULT:@ lines from Debug.log output.
compileAndRun :: String -> IO String
compileAndRun source =
  Temp.withSystemTempDirectory "can-jsexec" $ \tmp -> do
    setupProject tmp source
    compileProject tmp
    runAndCapture tmp

-- | Set up a Canopy application project in the given directory.
setupProject :: FilePath -> String -> IO ()
setupProject root source = do
  Dir.createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJson
  writeFile (root </> "src" </> "Main.can") source

-- | Compile the project using the canopy CLI with IIFE output.
compileProject :: FilePath -> IO ()
compileProject projectDir = do
  canopyBin <- findCanopyBinary
  let cp = (Process.proc canopyBin ["make", "src/Main.can", "--output=elm.js", "--output-format=iife"])
             { Process.cwd = Just projectDir }
  (exitCode, stdout, stderr) <- Process.readCreateProcessWithExitCode cp ""
  case exitCode of
    Exit.ExitSuccess -> pure ()
    Exit.ExitFailure code ->
      fail
        ( "canopy make failed with code "
            ++ show code
            ++ "\nstdout: "
            ++ stdout
            ++ "\nstderr: "
            ++ stderr
        )

-- | Find the canopy binary via stack path.
findCanopyBinary :: IO FilePath
findCanopyBinary = do
  (exitCode, stdout, _) <-
    Process.readProcessWithExitCode "stack" ["exec", "--", "which", "canopy"] ""
  case exitCode of
    Exit.ExitSuccess -> pure (trimOutput stdout)
    Exit.ExitFailure _ -> pure "canopy"

-- | Run the compiled JS and extract Debug.log output from stderr.
--
-- @Debug.log@ writes to stderr during module evaluation. The Platform
-- runtime crash after evaluation is expected (exit code 1) since we
-- don't provide a real DOM environment. We only examine stderr for
-- lines matching our @RESULT:@ prefix.
runAndCapture :: FilePath -> IO String
runAndCapture projectDir = do
  let jsPath = projectDir </> "elm.js"
  jsExists <- Dir.doesFileExist jsPath
  if jsExists
    then do
      (_exitCode, stdout, stderr) <-
        Process.readProcessWithExitCode "node" [jsPath] ""
      let fromStderr = extractDebugOutput stderr
      let fromStdout = extractDebugOutput stdout
      pure (if null (trimOutput fromStderr) then fromStdout else fromStderr)
    else do
      files <- Dir.listDirectory projectDir
      fail ("elm.js not found at: " ++ jsPath ++ "\nFiles: " ++ show files)

-- | Extract Debug.log output values from stderr.
--
-- @Debug.log "RESULT" value@ prints @RESULT: <value>@ to stderr.
-- We find all such lines and return the value part.
extractDebugOutput :: String -> String
extractDebugOutput stderr =
  unlines (concatMap extractResult (lines stderr))
  where
    extractResult line =
      case stripPrefixStr "RESULT: " line of
        Just rest -> [rest]
        Nothing -> []

-- | Strip a prefix from a string, returning the remainder.
stripPrefixStr :: String -> String -> Maybe String
stripPrefixStr [] ys = Just ys
stripPrefixStr _ [] = Nothing
stripPrefixStr (x : xs) (y : ys)
  | x == y = stripPrefixStr xs ys
  | otherwise = Nothing

-- | Trim leading and trailing whitespace.
trimOutput :: String -> String
trimOutput = reverse . dropWhile isWs . reverse . dropWhile isWs
  where
    isWs c = c == ' ' || c == '\n' || c == '\r' || c == '\t'

-- | The canopy.json for an application project.
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

-- | Test basic integer arithmetic.
testArithmetic :: TestTree
testArithmetic =
  testCase "arithmetic operations produce correct results" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "42"
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "main =",
          "    let",
          "        _ = Debug.log \"RESULT\" ((3 + 4) * 6)",
          "    in",
          "    text \"\""
        ]

-- | Test string concatenation.
testStringConcat :: TestTree
testStringConcat =
  testCase "string concatenation works correctly" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "Hello, World!"
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "main =",
          "    let",
          "        _ = Debug.log \"RESULT\" (\"Hello, \" ++ \"World!\")",
          "    in",
          "    text \"\""
        ]

-- | Test custom type pattern matching.
testCustomTypePatternMatch :: TestTree
testCustomTypePatternMatch =
  testCase "custom type pattern matching works" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "red"
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "type Color = Red | Green | Blue",
          "",
          "colorToString : Color -> String",
          "colorToString color =",
          "    case color of",
          "        Red -> \"red\"",
          "        Green -> \"green\"",
          "        Blue -> \"blue\"",
          "",
          "main =",
          "    let",
          "        _ = Debug.log \"RESULT\" (colorToString Red)",
          "    in",
          "    text \"\""
        ]

-- | Test record field access.
testRecordAccess :: TestTree
testRecordAccess =
  testCase "record field access works" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "Alice"
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "type alias Person = { name : String, age : Int }",
          "",
          "main =",
          "    let",
          "        person = Person \"Alice\" 30",
          "        _ = Debug.log \"RESULT\" person.name",
          "    in",
          "    text \"\""
        ]

-- | Test higher-order functions.
testHigherOrderFunctions :: TestTree
testHigherOrderFunctions =
  testCase "higher-order functions work" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "10"
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "double : Int -> Int",
          "double x = x * 2",
          "",
          "apply : (a -> b) -> a -> b",
          "apply f x = f x",
          "",
          "main =",
          "    let",
          "        _ = Debug.log \"RESULT\" (apply double 5)",
          "    in",
          "    text \"\""
        ]

-- | Test let bindings.
testLetBindings :: TestTree
testLetBindings =
  testCase "let bindings evaluate correctly" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "15"
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "main =",
          "    let",
          "        a = 3",
          "        b = 5",
          "        c = a * b",
          "        _ = Debug.log \"RESULT\" c",
          "    in",
          "    text \"\""
        ]

-- | Test boolean logic and if-then-else.
testBooleanLogic :: TestTree
testBooleanLogic =
  testCase "boolean logic and if-then-else work" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "\"yes\""
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "isEven : Int -> Bool",
          "isEven n =",
          "    modBy 2 n == 0",
          "",
          "main =",
          "    let",
          "        answer = if isEven 4 then \"yes\" else \"no\"",
          "        _ = Debug.log \"RESULT\" answer",
          "    in",
          "    text \"\""
        ]

-- | Test List operations.
testListOperations :: TestTree
testListOperations =
  testCase "list operations work correctly" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "3"
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "main =",
          "    let",
          "        _ = Debug.log \"RESULT\" (List.length [1, 2, 3])",
          "    in",
          "    text \"\""
        ]

-- | Test pattern matching with data-carrying constructors.
testNestedPatternMatch :: TestTree
testNestedPatternMatch =
  testCase "nested constructors pattern match correctly" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "found: 42"
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "type MyMaybe a = MyJust a | MyNothing",
          "",
          "showMyMaybe : MyMaybe Int -> String",
          "showMyMaybe m =",
          "    case m of",
          "        MyJust n -> \"found: \" ++ String.fromInt n",
          "        MyNothing -> \"nothing\"",
          "",
          "main =",
          "    let",
          "        _ = Debug.log \"RESULT\" (showMyMaybe (MyJust 42))",
          "    in",
          "    text \"\""
        ]

-- | Test recursive functions.
testRecursion :: TestTree
testRecursion =
  testCase "recursive functions work correctly" $
    withPrereqs $ do
      result <- compileAndRun src
      assertContains result "120"
  where
    src =
      unlines
        [ "module Main exposing (main)",
          "",
          "import Html exposing (text)",
          "",
          "factorial : Int -> Int",
          "factorial n =",
          "    if n <= 1 then",
          "        1",
          "    else",
          "        n * factorial (n - 1)",
          "",
          "main =",
          "    let",
          "        _ = Debug.log \"RESULT\" (factorial 5)",
          "    in",
          "    text \"\""
        ]

-- | Run the test body only if prerequisites are available.
withPrereqs :: IO () -> IO ()
withPrereqs action = do
  nodeOk <- checkAvailable "node" ["--version"]
  canopyOk <- checkCanopyAvailable
  if nodeOk && canopyOk
    then action
    else do
      _ <- assertFailure "Prerequisites not met: need both 'node' and 'canopy' on PATH"
      pure ()

-- | Check if a command is available.
checkAvailable :: FilePath -> [String] -> IO Bool
checkAvailable cmd args = do
  (exitCode, _, _) <- Process.readProcessWithExitCode cmd args ""
  pure (exitCode == Exit.ExitSuccess)

-- | Check if the canopy binary is available.
checkCanopyAvailable :: IO Bool
checkCanopyAvailable = do
  (exitCode, _, _) <-
    Process.readProcessWithExitCode "stack" ["exec", "--", "canopy", "--version"] ""
  pure (exitCode == Exit.ExitSuccess)

-- | Assert that the output contains the expected substring.
assertContains :: String -> String -> IO ()
assertContains actual expected
  | expected `List.isInfixOf` actual = pure ()
  | otherwise =
      assertFailure
        ( "Expected output to contain: "
            ++ show expected
            ++ "\nActual output: "
            ++ show actual
        )

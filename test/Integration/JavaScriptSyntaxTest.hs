{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | JavaScript syntax validation tests.
--
-- This module validates that our generated JavaScript is syntactically correct
-- and follows proper JavaScript standards, without requiring exact string matching.
-- This approach is more robust for compiler testing.
--
-- @since 0.19.1
module Integration.JavaScriptSyntaxTest
  ( tests
  , validateJSSyntax
  , validateJSStructure
  , SyntaxTest(..)
  ) where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.NonEmptyList as NE
import qualified Data.Text as Text
import qualified Generate
import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Pretty.Printer as JSPrint
import qualified Reporting
import qualified Reporting.Task as Task
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, assertFailure)

-- | Syntax test definition
data SyntaxTest = SyntaxTest
  { stName :: !Text.Text
  , stSource :: !Text.Text
  , stRequiredElements :: ![Text.Text]  -- Elements that must be present
  , stForbiddenElements :: ![Text.Text] -- Elements that must not be present
  } deriving (Eq, Show)

-- | All JavaScript syntax validation tests
tests :: TestTree
tests = testGroup "JavaScript Syntax Validation"
  [ testGroup "Basic Language Features"
      [ testJSSyntax basicFunctions
      , testJSSyntax curryingSupport
      , testJSSyntax moduleSystem
      ]
  , testGroup "JavaScript Structure"
      [ testJSStructure basicFunctions
      , testJSStructure curryingSupport
      , testJSStructure moduleSystem
      ]
  ]

-- | Test that generated JS is syntactically valid
testJSSyntax :: SyntaxTest -> TestTree
testJSSyntax st = testCase (Text.unpack (stName st) ++ " (syntax)") $ do
  jsCode <- generateJS st
  case validateJSSyntax jsCode of
    Left err -> assertFailure ("Invalid JavaScript syntax: " ++ err)
    Right _ -> pure ()

-- | Test that generated JS has required structural elements
testJSStructure :: SyntaxTest -> TestTree
testJSStructure st = testCase (Text.unpack (stName st) ++ " (structure)") $ do
  jsCode <- generateJS st
  case validateJSStructure st jsCode of
    Left err -> assertFailure ("Missing required elements: " ++ err)
    Right _ -> pure ()

-- | Generate JavaScript from Canopy source
generateJS :: SyntaxTest -> IO BL8.ByteString
generateJS st =
  withSystemTempDirectory "canopy-syntax-test" $ \tmpDir -> do
    setupProject tmpDir (stSource st)
    compileToJS tmpDir

-- | Validate JavaScript syntax using parser
validateJSSyntax :: BL8.ByteString -> Either String ()
validateJSSyntax jsCode =
  case JS.parse (BL8.unpack jsCode) "" of
    Left err -> Left (show err)
    Right ast ->
      -- Additional validation: ensure the AST can be pretty-printed
      case JSPrint.renderToString ast of
        "" -> Left "Empty AST rendering"
        _ -> Right ()

-- | Validate JavaScript structure has required elements
validateJSStructure :: SyntaxTest -> BL8.ByteString -> Either String ()
validateJSStructure st jsCode = do
  let jsString = BL8.unpack jsCode

  -- Check required elements are present
  mapM_ (checkRequired jsString) (stRequiredElements st)

  -- Check forbidden elements are not present
  mapM_ (checkForbidden jsString) (stForbiddenElements st)

  pure ()
  where
    checkRequired jsString element =
      if Text.unpack element `elem` words jsString
        then Right ()
        else Left ("Required element missing: " ++ Text.unpack element)

    checkForbidden jsString element =
      if Text.unpack element `elem` words jsString
        then Left ("Forbidden element present: " ++ Text.unpack element)
        else Right ()

-- | Setup test project
setupProject :: FilePath -> Text.Text -> IO ()
setupProject root source = do
  createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyConfig
  writeFile (root </> "src" </> "Main.can") (Text.unpack source)

-- | Compile to JavaScript
compileToJS :: FilePath -> IO BL8.ByteString
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

-- | Standard canopy.json
canopyConfig :: String
canopyConfig = unlines
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

-- | Basic function definition test
basicFunctions :: SyntaxTest
basicFunctions = SyntaxTest
  { stName = "basic-functions"
  , stSource = Text.unlines
      [ "module Main exposing (main, add)"
      , ""
      , "import Html exposing (text)"
      , ""
      , "add x y = x + y"
      , ""
      , "main = text \"Hello\""
      ]
  , stRequiredElements =
      [ "function"      -- Should generate functions
      , "scope"         -- Should use proper scoping
      , "'use strict'"  -- Should be in strict mode
      ]
  , stForbiddenElements =
      [ "undefined"     -- Should not have undefined references
      , "eval"          -- Should not use eval
      , "with"          -- Should not use with statements
      ]
  }

-- | Currying support test
curryingSupport :: SyntaxTest
curryingSupport = SyntaxTest
  { stName = "currying-support"
  , stSource = Text.unlines
      [ "module Main exposing (main, curry3)"
      , ""
      , "import Html exposing (text)"
      , ""
      , "curry3 f a b c = f a b c"
      , "add3 x y z = x + y + z"
      , ""
      , "main = text (String.fromInt (curry3 add3 1 2 3))"
      ]
  , stRequiredElements =
      [ "function"      -- Should generate curried functions
      , "return"        -- Should have return statements for currying
      ]
  , stForbiddenElements = []
  }

-- | Module system test
moduleSystem :: SyntaxTest
moduleSystem = SyntaxTest
  { stName = "module-system"
  , stSource = Text.unlines
      [ "module Main exposing (main)"
      , ""
      , "import Html exposing (text)"
      , "import String"
      , ""
      , "main = text (String.fromInt 42)"
      ]
  , stRequiredElements =
      [ "function"      -- Should wrap in function
      , "scope"         -- Should use proper module scoping
      ]
  , stForbiddenElements =
      [ "var"           -- Should use proper scoping, not var
      ]
  }
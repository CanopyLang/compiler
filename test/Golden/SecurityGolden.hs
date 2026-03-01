-- | Security-focused golden tests for code generation.
--
-- Verifies that generated JavaScript properly escapes special characters
-- in string literals, preventing XSS and injection vulnerabilities.
--
-- @since 0.19.2
module Golden.SecurityGolden (tests) where

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
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)

tests :: TestTree
tests =
  testGroup
    "Golden.Security"
    [ goldenSecurity
        "EscapeScriptTag"
        extractUserDefs
        xssModule
        "test/Golden/expected/SecurityEscapeScriptTag.js",
      goldenSecurity
        "EscapeBackslash"
        extractUserDefs
        backslashModule
        "test/Golden/expected/SecurityEscapeBackslash.js"
    ]

goldenSecurity :: String -> (BL8.ByteString -> BL8.ByteString) -> String -> FilePath -> TestTree
goldenSecurity name extract src expectedPath =
  goldenVsString name expectedPath
    . withSystemTempDirectory "can-sec-golden"
    $ \tmp -> do
      setupPkgProject tmp src
      builder <- runDev tmp
      pure (extract (BB.toLazyByteString builder))

-- | Extract lines containing user-defined variables for comparison.
extractUserDefs :: BL8.ByteString -> BL8.ByteString
extractUserDefs bs =
  BL8.unlines (filter isUserDef (BL8.lines bs))
  where
    needle = BL8.pack "$author$project$Main$"
    isUserDef line = isInfixOfLazy needle line

-- | Check if a ByteString is an infix of another.
isInfixOfLazy :: BL8.ByteString -> BL8.ByteString -> Bool
isInfixOfLazy needle haystack =
  any (BL8.isPrefixOf needle) (BL8.tails haystack)

-- | Run the dev code generator on a project.
runDev :: FilePath -> IO BB.Builder
runDev tmp = do
  details <- BW.withScope $ \scope -> do
    e <- Details.load Reporting.silent scope tmp
    case e of
      Left _ -> error "details failed"
      Right d -> pure d
  let srcFile = tmp </> "src" </> "Main.can"
  artifactsE <- Build.fromPaths Reporting.silent tmp details [srcFile]
  case artifactsE of
    Left _ -> error "build failed"
    Right artifacts -> do
      res <- Task.run (Generate.dev tmp details artifacts)
      case res of
        Left _ -> error "generate failed"
        Right b -> pure b

-- | Set up a minimal package project.
setupPkgProject :: FilePath -> String -> IO ()
setupPkgProject root src = do
  createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJsonPackage
  writeFile (root </> "src" </> "Main.can") src

-- | Minimal canopy.json for application projects.
canopyJsonPackage :: String
canopyJsonPackage =
  unlines
    [ "{",
      "  \"type\": \"application\",",
      "  \"source-directories\": [",
      "      \"src\"",
      "  ],",
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

-- | Module with strings containing script tags and HTML entities.
--
-- The generated JS must escape angle brackets and ampersands so that
-- if the string is ever injected into HTML, no script execution occurs.
xssModule :: String
xssModule =
  unlines
    [ "module Main exposing (main, dangerous, withQuotes)",
      "",
      "import Html exposing (text)",
      "",
      "dangerous : String",
      "dangerous = \"<script>alert('xss')</script>\"",
      "",
      "withQuotes : String",
      "withQuotes = \"She said \\\"hello\\\" & goodbye\"",
      "",
      "main = text dangerous"
    ]

-- | Module with strings containing backslash sequences.
--
-- The generated JS must preserve backslash escaping so that
-- runtime strings match what the programmer wrote.
backslashModule :: String
backslashModule =
  unlines
    [ "module Main exposing (main, withNewlines, withTabs, withBackslash)",
      "",
      "import Html exposing (text)",
      "",
      "withNewlines : String",
      "withNewlines = \"line1\\nline2\\nline3\"",
      "",
      "withTabs : String",
      "withTabs = \"col1\\tcol2\\tcol3\"",
      "",
      "withBackslash : String",
      "withBackslash = \"path\\\\to\\\\file\"",
      "",
      "main = text withNewlines"
    ]

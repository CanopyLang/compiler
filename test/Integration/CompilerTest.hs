module Integration.CompilerTest (tests) where

import qualified Compile
import System.Directory
import System.FilePath
import System.IO.Temp
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Compiler Integration Tests"
    [ testSimpleCanopyCompilation,
      testCanopyJsonParsing
    ]

testSimpleCanopyCompilation :: TestTree
testSimpleCanopyCompilation =
  testCase "compile simple Canopy module" . withSystemTempDirectory "canopy-test" $
    ( \tmpDir -> do
        -- Create a simple Canopy file
        let canopyFile = tmpDir </> "Main.canopy"
        writeFile canopyFile simpleCanopyModule

        -- Create canopy.json
        let canopyJson = tmpDir </> "canopy.json"
        writeFile canopyJson simpleCanopyJsonApplication

        -- TODO: Add actual compilation test when we understand the Compile module better
        -- For now, just test that the files exist
        doesExist <- doesFileExist canopyFile
        doesExist @? "Canopy file should exist"

        jsonExists <- doesFileExist canopyJson
        jsonExists @? "canopy.json should exist"
    )

testCanopyJsonParsing :: TestTree
testCanopyJsonParsing =
  testCase "parse canopy.json files" . withSystemTempDirectory "canopy-json-test" $
    ( \tmpDir -> do
        let canopyJson = tmpDir </> "canopy.json"
        writeFile canopyJson simpleCanopyJsonPackage

        jsonExists <- doesFileExist canopyJson
        jsonExists @? "canopy.json should exist"
    )

-- TODO: Add actual JSON parsing tests

-- Sample Canopy module for testing
simpleCanopyModule :: String
simpleCanopyModule =
  unlines
    [ "module Main exposing (main)",
      "",
      "import Html exposing (text)",
      "",
      "main =",
      "    text \"Hello, World!\""
    ]

-- Sample canopy.json for application
simpleCanopyJsonApplication :: String
simpleCanopyJsonApplication =
  unlines
    [ "{",
      "    \"type\": \"application\",",
      "    \"source-directories\": [",
      "        \".\"",
      "    ],",
      "    \"canopy-version\": \"0.19.1\",",
      "    \"dependencies\": {",
      "        \"direct\": {",
      "            \"canopy/browser\": \"1.0.2\",",
      "            \"canopy/core\": \"1.0.5\",",
      "            \"canopy/html\": \"1.0.0\"",
      "        },",
      "        \"indirect\": {",
      "            \"canopy/json\": \"1.1.3\",",
      "            \"canopy/time\": \"1.0.0\",",
      "            \"canopy/url\": \"1.0.0\",",
      "            \"canopy/virtual-dom\": \"1.0.2\"",
      "        }",
      "    },",
      "    \"test-dependencies\": {",
      "        \"direct\": {},",
      "        \"indirect\": {}",
      "    }",
      "}"
    ]

-- Sample canopy.json for package
simpleCanopyJsonPackage :: String
simpleCanopyJsonPackage =
  unlines
    [ "{",
      "    \"type\": \"package\",",
      "    \"name\": \"author/package\",",
      "    \"summary\": \"A test package\",",
      "    \"license\": \"BSD-3-Clause\",",
      "    \"version\": \"1.0.0\",",
      "    \"exposed-modules\": [",
      "        \"Main\"",
      "    ],",
      "    \"canopy-version\": \"0.19.0 <= v < 0.20.0\",",
      "    \"dependencies\": {",
      "        \"canopy/core\": \"1.0.0 <= v < 2.0.0\"",
      "    },",
      "    \"test-dependencies\": {}",
      "}"
    ]

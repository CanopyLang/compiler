module Integration.JsGenTest (tests) where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.List as List
import qualified Data.NonEmptyList as NE
import qualified Generate
import qualified Reporting
import qualified Reporting.Task as Task
import System.Directory
import System.FilePath
import System.IO.Temp
import System.Process
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "JS Generation"
    [ testDevGenSingleFile,
      testProdGenSingleFile
    ]

testDevGenSingleFile :: TestTree
testDevGenSingleFile = testCase "Generate.dev produces JS with multiple functions" $ do
  withSystemTempDirectory "can-js-dev" $ \tmp -> do
    setupPkgProject tmp sampleModule
    -- load details and build
    details <- BW.withScope $ \scope -> do
      e <- Details.load Reporting.silent scope tmp
      case e of
        Left _ -> assertFailure "details failed" >> undefined
        Right d -> pure d
    let srcFile = tmp </> "src" </> "Main.can"
    artifactsE <- Build.fromPaths Reporting.silent tmp details (NE.List srcFile [])
    case artifactsE of
      Left _ -> assertFailure "build failed"
      Right artifacts -> do
        res <- Task.run (Generate.dev tmp details artifacts)
        case res of
          Left _ -> assertFailure "generate failed"
          Right builder -> do
            let s = toChars (BB.toLazyByteString builder)
            assertBool "contains $author$project$Main$add" ("$author$project$Main$add" `List.isInfixOf` s)
            assertBool "contains $author$project$Main$mul" ("$author$project$Main$mul" `List.isInfixOf` s)
            assertBool "contains $author$project$Main$compose" ("$author$project$Main$compose" `List.isInfixOf` s)

testProdGenSingleFile :: TestTree
testProdGenSingleFile = testCase "Generate.prod produces JS with multiple functions" $ do
  withSystemTempDirectory "can-js-prod" $ \tmp -> do
    setupPkgProject tmp sampleModule
    details <- BW.withScope $ \scope -> do
      e <- Details.load Reporting.silent scope tmp
      case e of
        Left _ -> assertFailure "details failed" >> undefined
        Right d -> pure d
    let srcFile = tmp </> "src" </> "Main.can"
    artifactsE <- Build.fromPaths Reporting.silent tmp details (NE.List srcFile [])
    case artifactsE of
      Left _ -> assertFailure "build failed"
      Right artifacts -> do
        res <- Task.run (Generate.prod tmp details artifacts)
        case res of
          Left _ -> assertFailure "generate failed"
          Right builder -> do
            let s = toChars (BB.toLazyByteString builder)
            -- In prod names may be shorter, but module markers remain
            assertBool "contains module marker" ("$author$project$Main$" `List.isInfixOf` s)

-- Helpers

setupPkgProject :: FilePath -> String -> IO ()
setupPkgProject root src = do
  createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJsonPackage
  writeFile (root </> "src" </> "Main.can") src
  callCommand ("cd " <> root <> " && " <> "canopy make src/Main.can")

toChars :: BL.ByteString -> String
toChars = map (toEnum . fromEnum) . BL.unpack

canopyJsonPackage :: String
canopyJsonPackage =
  unlines
    [ "{",
      "    \"type\": \"application\",",
      "    \"source-directories\": [",
      "        \"src\"",
      "    ],",
      "    \"canopy-version\": \"0.19.1\",",
      "    \"dependencies\": {",
      "        \"direct\": {",
      "            \"elm/core\": \"1.0.5\",",
      "            \"elm/html\": \"1.0.0\"",
      "        },",
      "        \"indirect\": {",
      "            \"elm/json\": \"1.1.3\",",
      "            \"elm/virtual-dom\": \"1.0.3\"",
      "        }",
      "    },",
      "    \"test-dependencies\": {",
      "        \"direct\": {},",
      "        \"indirect\": {}",
      "    }",
      "}"
    ]

sampleModule :: String
sampleModule =
  unlines
    [ "module Main exposing (main, add, mul, compose)",
      "",
      "import Html exposing (text)",
      "",
      "add x y = x + y",
      "mul x y = x * y",
      "compose f g x = f (g x)",
      "",
      "main = text (String.fromInt (compose (add 1) (mul 2) 3))"
    ]

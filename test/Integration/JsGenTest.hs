module Integration.JsGenTest (tests) where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import qualified Generate
import qualified Reporting
import qualified Reporting.Task as Task
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.List as List
import qualified Data.NonEmptyList as NE
import System.Directory
import System.FilePath
import System.IO.Temp
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
            assertBool "contains Main$add" ("Main$add" `List.isInfixOf` s)
            assertBool "contains Main$mul" ("Main$mul" `List.isInfixOf` s)
            assertBool "contains Main$compose" ("Main$compose" `List.isInfixOf` s)

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
            assertBool "contains module marker" ("Main$" `List.isInfixOf` s)

-- Helpers

setupPkgProject :: FilePath -> String -> IO ()
setupPkgProject root src = do
  createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJsonPackage
  writeFile (root </> "src" </> "Main.can") src

toChars :: BL.ByteString -> String
toChars = map (toEnum . fromEnum) . BL.unpack

canopyJsonPackage :: String
canopyJsonPackage = unlines
  [ "{",
    "  \"type\": \"package\",",
    "  \"name\": \"author/project\",",
    "  \"summary\": \"Test package\",",
    "  \"license\": \"BSD-3-Clause\",",
    "  \"version\": \"1.0.0\",",
    "  \"exposed-modules\": [ \"Main\" ],",
    "  \"canopy-version\": \"0.19.0 <= v < 0.20.0\",",
    "  \"dependencies\": {},",
    "  \"test-dependencies\": {}",
    "}"
  ]

sampleModule :: String
sampleModule = unlines
  [ "module Main exposing (main, add, mul, compose)",
    "",
    "add x y = x + y",
    "mul x y = x * y",
    "compose f g x = f (g x)",
    "",
    "main = add (mul 2 3) 4"
  ]

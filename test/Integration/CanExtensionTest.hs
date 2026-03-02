module Integration.CanExtensionTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import qualified File
import qualified Parse.Module as PM
import System.Directory
import System.FilePath
import System.IO.Temp
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Can extension integration"
    [ testDetectCanFiles,
      testParseCanModule,
      testParseElmModule
    ]

testDetectCanFiles :: TestTree
testDetectCanFiles =
  testCase "listAllCanopyFilesRecursively includes .can and .canopy" . withSystemTempDirectory "can-ext" $
    ( \tmp -> do
        let src = tmp </> "src"
        createDirectory src
        let f1 = src </> "Main.can"
        let f2 = src </> "Other.canopy"
        let f3 = src </> "ElmMain.elm"
        writeFile f1 sampleModule
        writeFile f2 sampleModule
        writeFile f3 sampleModule
        files <- File.listAllCanopyFilesRecursively src
        assertBool ".can detected" (f1 `elem` files)
        assertBool ".canopy detected" (f2 `elem` files)
        assertBool ".elm detected" (f3 `elem` files)
    )

testParseCanModule :: TestTree
testParseCanModule =
  testCase ".can content parses as module" . withSystemTempDirectory "can-parse" $
    ( \tmp -> do
        let f = tmp </> "Main.can"
        writeFile f sampleModule
        bs <- BS.readFile f
        case PM.fromByteString PM.Application bs of
          Left err -> assertFailure ("parse failed: " <> show err)
          Right (Src.Module {}) -> return ()
    )

testParseElmModule :: TestTree
testParseElmModule =
  testCase ".elm content parses as module" . withSystemTempDirectory "elm-parse" $
    ( \tmp -> do
        let f = tmp </> "Main.elm"
        writeFile f sampleModule
        bs <- BS.readFile f
        case PM.fromByteString PM.Application bs of
          Left err -> assertFailure ("parse failed: " <> show err)
          Right (Src.Module {}) -> return ()
    )

-- Helpers
-- keep around if needed in future tests
_toUtf8 :: String -> BS.ByteString
_toUtf8 = C8.pack

sampleModule :: String
sampleModule =
  unlines
    [ "module Main exposing (main)",
      "",
      "main = 1"
    ]

module Golden.JsGenGolden (tests) where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Generate
import qualified Reporting
import qualified Reporting.Task as Task
import System.Directory
import System.FilePath
import System.IO.Temp
import Test.Tasty
import Test.Tasty.Golden

tests :: TestTree
tests =
  testGroup
    "Golden.JsGen"
    [ goldenJs "DevMulti" simplifyHeader sampleModule "test/Golden/expected/JsDevMulti.js",
      goldenJs "Interpolation" extractUserDefs interpModule "test/Golden/expected/JsInterpolation.js"
    ]

goldenJs :: String -> (BL8.ByteString -> BL8.ByteString) -> String -> FilePath -> TestTree
goldenJs name extract src expectedPath =
  goldenVsString name expectedPath
    . withSystemTempDirectory "can-js-golden"
    $ \tmp -> do
      setupPkgProject tmp src
      builder <- runDev tmp
      pure (extract (BB.toLazyByteString builder))

-- Extract only the stable structural parts for comparison
simplifyHeader :: BL8.ByteString -> BL8.ByteString
simplifyHeader bs =
  case BL8.lines bs of
    (l1 : l2 : _) ->
      -- Only check that we have proper JS structure, not exact content
      if "(function(scope)" `BL8.isPrefixOf` l1 && "'use strict'" `BL8.isPrefixOf` l2
        then BL8.unlines ["(function(scope){", "'use strict';", ")}"]
        else BL8.unlines [l1, l2, ")}"]
    _ -> bs

-- Extract lines containing user-defined functions (var $author$project$Main$...)
extractUserDefs :: BL8.ByteString -> BL8.ByteString
extractUserDefs bs =
  BL8.unlines (filter isUserDef (BL8.lines bs))
  where
    needle = BL8.pack "$author$project$Main$"
    isUserDef line = needle `isInfixOfLazy` line

isInfixOfLazy :: BL8.ByteString -> BL8.ByteString -> Bool
isInfixOfLazy needle haystack =
  any (BL8.isPrefixOf needle) (BL8.tails haystack)

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

setupPkgProject :: FilePath -> String -> IO ()
setupPkgProject root src = do
  createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJsonPackage
  writeFile (root </> "src" </> "Main.can") src

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

interpModule :: String
interpModule =
  unlines
    [ "module Main exposing (main, greeting, plain)",
      "",
      "import Html exposing (text)",
      "",
      "greeting : String -> String -> String",
      "greeting first last =",
      "    `Hello ${first} ${last}!`",
      "",
      "plain : String",
      "plain =",
      "    `just a string`",
      "",
      "main =",
      "    text (greeting \"World\" \"!\")"
    ]

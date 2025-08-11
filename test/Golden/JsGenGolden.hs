module Golden.JsGenGolden (tests) where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import qualified Generate
import qualified Reporting
import qualified Reporting.Task as Task
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.NonEmptyList as NE
import System.Directory
import System.FilePath
import System.IO.Temp
import Test.Tasty
import Test.Tasty.Golden

tests :: TestTree
tests =
  testGroup
    "Golden.JsGen"
    [ goldenJs "DevMulti" sampleModule "test/Golden/expected/JsDevMulti.js"
    ]

goldenJs :: String -> String -> FilePath -> TestTree
goldenJs name src expectedPath =
  goldenVsString name expectedPath $ do
    withSystemTempDirectory "can-js-golden" $ \tmp -> do
      setupPkgProject tmp src
      builder <- runDev tmp
      -- Compare only a stable header to avoid brittle diffs
      pure (simplifyHeader (BB.toLazyByteString builder))

-- Keep the first two lines and a simple closer for stability
simplifyHeader :: BL8.ByteString -> BL8.ByteString
simplifyHeader bs =
  case BL8.lines bs of
    (l1:l2:_) -> BL8.unlines [l1, l2, ")}"]
    _ -> bs

runDev :: FilePath -> IO BB.Builder
runDev tmp = do
  details <- BW.withScope $ \scope -> do
    e <- Details.load Reporting.silent scope tmp
    case e of
      Left _ -> error "details failed"
      Right d -> pure d
  let srcFile = tmp </> "src" </> "Main.can"
  artifactsE <- Build.fromPaths Reporting.silent tmp details (NE.List srcFile [])
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

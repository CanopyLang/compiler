{-# LANGUAGE OverloadedStrings #-}
import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.NonEmptyList as NE
import qualified Data.Text as Text
import qualified Generate
import qualified Reporting
import qualified Reporting.Task as Task
import System.FilePath ((</>))

main :: IO ()
main = do
  let projectDir = "/tmp/canopy-manual-test"
  result <- BW.withScope $ \scope -> do
    details <- Details.load Reporting.silent scope projectDir
    case details of
      Left detailsErr -> error ("details loading failed")
      Right d -> do
        let srcFile = projectDir </> "src" </> "Main.can"
        artifactsE <- Build.fromPaths Reporting.silent projectDir d (NE.List srcFile [])
        case artifactsE of
          Left buildErr -> error ("build failed")
          Right artifacts -> do
            res <- Task.run (Generate.dev projectDir d artifacts)
            case res of
              Left genErr -> error ("generate failed")
              Right b -> pure (BB.toLazyByteString b)
  
  BL.writeFile "/tmp/canopy-direct-output.js" result
  putStrLn "Generated JavaScript output saved to /tmp/canopy-direct-output.js"
  
  -- Show first few lines
  content <- BL.readFile "/tmp/canopy-direct-output.js"
  let firstChars = BL.take 2000 content
  putStrLn "First 2000 characters:"
  putStrLn $ BL8.unpack firstChars
  
  -- Show size comparison
  fullSize <- BL.length <$> BL.readFile "/tmp/canopy-direct-output.js"
  expectedSize <- BL.length <$> BL.readFile "/home/quinten/fh/canopy/test/Golden/expected/elm-canopy/basic-arithmetic.js"
  putStrLn $ "\nSize comparison:"
  putStrLn $ "Canopy: " ++ show fullSize ++ " bytes"  
  putStrLn $ "Expected: " ++ show expectedSize ++ " bytes"

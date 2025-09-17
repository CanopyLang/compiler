#!/usr/bin/env stack
-- stack runghc --resolver lts-22.0 --package canopy

{-# LANGUAGE OverloadedStrings #-}

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Char8 as C8
import qualified Generate

main :: IO ()
main = do
  putStrLn "Testing runtime generation..."

  -- Use the test canopy file
  let testFile = "/tmp/correct_main.can"

  -- Generate using Generate.dev (elm-compatible mode)
  result <- Generate.dev testFile
  let output = Builder.toLazyByteString result
      outputBS = BS.concat (LBS.toChunks output)
      outputSize = BS.length outputBS

  putStrLn $ "Generated output size: " ++ show outputSize ++ " characters"
  putStrLn $ "Expected golden size: 91602 characters"

  -- Save the output
  BS.writeFile "/tmp/canopy_runtime_test.js" outputBS
  putStrLn "Output saved to /tmp/canopy_runtime_test.js"

  -- Check if size matches expectation
  if outputSize >= 80000
    then putStrLn "✓ SUCCESS: Large output suggests runtime is included!"
    else do
      putStrLn "✗ Size still small - let's check first few lines..."
      let firstLines = take 200 $ C8.unpack outputBS
      putStrLn firstLines
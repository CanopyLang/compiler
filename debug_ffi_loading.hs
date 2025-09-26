#!/usr/bin/env runhaskell
{-# LANGUAGE OverloadedStrings #-}

import qualified AST.Source as Src
import qualified Canonicalize.Module as Canonicalize
import qualified Foreign.FFI as FFI
import qualified Reporting.Annotation as A
import qualified Data.Name as Name
import qualified Data.Map as Map
import System.FilePath ((</>))

main :: IO ()
main = do
  putStrLn "=== Debug FFI Loading ==="

  -- Create a test foreign import like the one in AudioFFI.can
  let jsPath = "external/audio.js"
  let alias = A.At A.one (Name.fromChars "AudioFFI")
  let foreignImport = Src.ForeignImport (FFI.JavaScriptFFI jsPath) alias A.one

  putStrLn $ "Foreign import: " ++ jsPath
  putStrLn $ "Alias: " ++ Name.toChars (A.toValue alias)

  -- Test FFI content loading
  putStrLn "Loading FFI content..."
  ffiContentMap <- Canonicalize.loadFFIContentWithRoot "/home/quinten/fh/canopy/examples/audio-ffi" [foreignImport]

  putStrLn $ "FFI content map size: " ++ show (Map.size ffiContentMap)
  putStrLn "FFI content map keys:"
  mapM_ (putStrLn . ("  " ++)) (Map.keys ffiContentMap)

  case Map.lookup jsPath ffiContentMap of
    Nothing -> putStrLn "ERROR: No content found for external/audio.js"
    Just content -> do
      putStrLn $ "Content length: " ++ show (length content)
      putStrLn "First 200 characters:"
      putStrLn $ take 200 content

      putStrLn "\nSearching for checkWebAudioSupport function:"
      if "function checkWebAudioSupport" `elem` lines content
        then putStrLn "✓ Found checkWebAudioSupport function"
        else putStrLn "✗ checkWebAudioSupport function not found"
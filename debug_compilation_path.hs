#!/usr/bin/env stack
-- stack --resolver lts-18.18 script --package bytestring --package filepath --package directory

{-# LANGUAGE OverloadedStrings #-}

import System.FilePath
import System.Directory
import Control.Exception

main :: IO ()
main = do
  let wrongPath = "/home/quinten/.canopy/0.19.1/packages/elm/core/1.0.5/Array.elm"
  let correctPath = "/home/quinten/.canopy/0.19.1/packages/elm/core/1.0.5/src/Array.elm"

  putStrLn "=== PATH DEBUGGING ==="
  putStrLn $ "Wrong path: " ++ wrongPath
  putStrLn $ "Correct path: " ++ correctPath

  wrongExists <- doesFileExist wrongPath
  correctExists <- doesFileExist correctPath

  putStrLn $ "Wrong path exists: " ++ show wrongExists
  putStrLn $ "Correct path exists: " ++ show correctExists

  putStrLn "\n=== TESTING getModificationTime ==="
  putStrLn "Testing wrong path:"
  catch (getModificationTime wrongPath >>= print) $ \e ->
    putStrLn $ "ERROR: " ++ show (e :: IOError)

  putStrLn "Testing correct path:"
  catch (getModificationTime correctPath >>= print) $ \e ->
    putStrLn $ "ERROR: " ++ show (e :: IOError)
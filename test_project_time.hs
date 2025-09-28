{-# LANGUAGE OverloadedStrings #-}
import System.Directory as Dir
import qualified File

getProjectFileTime :: FilePath -> IO File.Time
getProjectFileTime root = do
  canopyExists <- Dir.doesFileExist (root </> "canopy.json")
  if canopyExists
    then File.getTime (root </> "canopy.json")
    else File.getTime (root </> "elm.json")

main :: IO ()
main = do
  time <- getProjectFileTime "/home/quinten/.canopy/0.19.1/packages/elm/core/1.0.5"
  putStrLn $ "Project file time: " ++ show time

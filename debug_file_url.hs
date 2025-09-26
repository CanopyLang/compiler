#!/usr/bin/env stack
-- stack --resolver lts-22.29 script --package network-uri

import Network.URI

main :: IO ()
main = do
  let url = "file:///home/quinten/fh/canopy-core-1.0.0.zip"
  putStrLn $ "Testing URL: " ++ url

  case parseURI url of
    Nothing -> putStrLn "❌ parseURI failed"
    Just uri -> do
      putStrLn $ "✅ parseURI succeeded"
      putStrLn $ "  scheme: " ++ uriScheme uri
      putStrLn $ "  path: " ++ uriPath uri
      putStrLn $ "  scheme == 'file:': " ++ show (uriScheme uri == "file:")

  -- Test another format
  let url2 = "https://example.com/test.zip"
  putStrLn $ "\nTesting URL: " ++ url2
  case parseURI url2 of
    Nothing -> putStrLn "❌ parseURI failed"
    Just uri -> do
      putStrLn $ "✅ parseURI succeeded"
      putStrLn $ "  scheme: " ++ uriScheme uri
      putStrLn $ "  scheme == 'https:': " ++ show (uriScheme uri == "https:")
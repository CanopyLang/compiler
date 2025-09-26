#!/usr/bin/env stack
-- stack --resolver lts-22.29 script --package network-uri

import Network.URI

-- Same function as in Http.hs
isFileUrl :: String -> Bool
isFileUrl url =
  case parseURI url of
    Just uri -> uriScheme uri == "file:"
    Nothing -> False

-- Same function as in Http.hs
fileUrlToPath :: String -> Maybe FilePath
fileUrlToPath url =
  case parseURI url of
    Just uri | uriScheme uri == "file:" -> Just (uriPath uri)
    _ -> Nothing

main :: IO ()
main = do
  let url = "file:///home/quinten/fh/canopy-core-1.0.0.zip"
  putStrLn $ "Testing URL: " ++ url
  putStrLn $ "isFileUrl result: " ++ show (isFileUrl url)
  putStrLn $ "fileUrlToPath result: " ++ show (fileUrlToPath url)

  -- Test with different formats
  let urls =
        [ "file:///home/quinten/fh/canopy-core-1.0.0.zip"
        , "https://example.com/test.zip"
        , "http://example.com/test.zip"
        ]

  mapM_ (\u -> putStrLn $ u ++ " -> isFileUrl: " ++ show (isFileUrl u)) urls
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Website integration stub for Terminal.
--
-- Minimal stub for package website operations. The OLD module handled
-- communication with package.elm-lang.org.
--
-- @since 0.19.1
module Deps.Website
  ( -- * Website Operations
    getVersions,
    publish,
    route,
  )
where

import qualified Data.List as List

-- | Get package versions from website (stub).
getVersions :: a -> IO (Either String ())
getVersions _ = pure (Right ())

-- | Publish package to website (stub).
publish :: a -> b -> c -> IO (Either String ())
publish _ _ _ = pure (Right ())

-- | Create a URL route with query parameters.
--
-- Constructs a full URL from base repository URL, path, and query parameters.
--
-- @since 0.19.1
route :: String -> String -> [(String, String)] -> String
route baseUrl path params =
  let url = baseUrl ++ path
      queryString = buildQueryString params
   in if null queryString then url else url ++ "?" ++ queryString

-- Helper: Build query string from parameters.
buildQueryString :: [(String, String)] -> String
buildQueryString params =
  List.intercalate "&" [encodeParam k v | (k, v) <- params]

-- Helper: Encode a single parameter.
encodeParam :: String -> String -> String
encodeParam key value = key ++ "=" ++ urlEncode value

-- Helper: Simple URL encoding.
urlEncode :: String -> String
urlEncode = concatMap encodeChar
  where
    encodeChar c
      | c == ' ' = "+"
      | c `elem` unreservedChars = [c]
      | otherwise = '%' : toHex (fromEnum c)

    unreservedChars = ['A'..'Z'] ++ ['a'..'z'] ++ ['0'..'9'] ++ "-_.~"

    toHex n = case showHex n of
      [x] -> ['0', x]
      xs -> xs

    showHex 0 = "0"
    showHex n = reverse (showHex' n)

    showHex' 0 = ""
    showHex' n = hexDigit (n `mod` 16) : showHex' (n `div` 16)

    hexDigit d
      | d < 10 = toEnum (fromEnum '0' + d)
      | otherwise = toEnum (fromEnum 'A' + d - 10)

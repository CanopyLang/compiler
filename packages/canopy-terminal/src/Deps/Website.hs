{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | URL construction utilities for the package registry website.
--
-- Provides URL routing helpers for constructing API endpoints on
-- @package.elm-lang.org@. Used by the publish and diff commands to
-- build download and documentation URLs.
--
-- @since 0.19.1
module Deps.Website
  ( -- * URL Construction
    route,
  )
where

import qualified Data.List as List

-- | Create a URL route with query parameters.
--
-- Constructs a full URL from base repository URL, path, and query parameters.
--
-- @since 0.19.1
route :: String -> String -> [(String, String)] -> String
route baseUrl path params
  | null queryString = url
  | otherwise = url ++ "?" ++ queryString
  where
    url = baseUrl ++ path
    queryString = buildQueryString params

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

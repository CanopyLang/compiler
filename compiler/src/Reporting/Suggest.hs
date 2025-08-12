{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Reporting.Suggest
  ( distance,
    sort,
    rank,
  )
where

import qualified Data.Char as Char
import qualified Data.List as List
import qualified Text.EditDistance as Dist

-- DISTANCE

distance :: String -> String -> Int
distance = Dist.restrictedDamerauLevenshteinDistance Dist.defaultEditCosts

-- SORT

sort :: String -> (a -> String) -> [a] -> [a]
sort target toString = List.sortOn (distance (toLower target) . toLower . toString)

toLower :: String -> String
toLower = fmap Char.toLower

-- RANK

rank :: String -> (a -> String) -> [a] -> [(Int, a)]
rank target toString values =
  let toRank v =
        distance (toLower target) (toLower (toString v))

      addRank v =
        (toRank v, v)
   in List.sortOn fst (fmap addRank values)

{-# LANGUAGE OverloadedStrings #-}

module Canonicalize.Environment.Dups
  ( detect,
    checkFields,
    checkFields',
    Dict,
    none,
    one,
    insert,
    union,
    unions,
  )
where

import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.OneOrMore as OneOrMore
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result

-- DUPLICATE TRACKER

type Dict value =
  Map.Map Name.Name (OneOrMore.OneOrMore (Info value))

data Info value = Info
  { _region :: A.Region,
    _value :: value
  }

-- DETECT

type ToError =
  Name.Name -> A.Region -> A.Region -> Error.Error

detect :: ToError -> Dict a -> Result.Result i w Error.Error (Map.Map Name.Name a)
detect toError = Map.traverseWithKey (detectHelp toError)

detectHelp :: ToError -> Name.Name -> OneOrMore.OneOrMore (Info a) -> Result.Result i w Error.Error a
detectHelp toError name values =
  case values of
    OneOrMore.One (Info _ value) ->
      return value
    OneOrMore.More left right ->
      let (Info r1 _, Info r2 _) =
            OneOrMore.getFirstTwo left right
       in Result.throw (toError name r1 r2)

-- CHECK FIELDS

checkFields :: [(A.Located Name.Name, a)] -> Result.Result i w Error.Error (Map.Map Name.Name a)
checkFields fields =
  detect Error.DuplicateField (foldr addField none fields)

addField :: (A.Located Name.Name, a) -> Dict a -> Dict a
addField (A.At region name, value) = Map.insertWith OneOrMore.more name (OneOrMore.one (Info region value))

checkFields' :: (A.Region -> a -> b) -> [(A.Located Name.Name, a)] -> Result.Result i w Error.Error (Map.Map Name.Name b)
checkFields' toValue fields =
  detect Error.DuplicateField (foldr (addField' toValue) none fields)

addField' :: (A.Region -> a -> b) -> (A.Located Name.Name, a) -> Dict b -> Dict b
addField' toValue (A.At region name, value) = Map.insertWith OneOrMore.more name (OneOrMore.one (Info region (toValue region value)))

-- BUILDING DICTIONARIES

none :: Dict a
none =
  Map.empty

one :: Name.Name -> A.Region -> value -> Dict value
one name region value =
  Map.singleton name (OneOrMore.one (Info region value))

insert :: Name.Name -> A.Region -> a -> Dict a -> Dict a
insert name region value = Map.insertWith (flip OneOrMore.more) name (OneOrMore.one (Info region value))

union :: Dict a -> Dict a -> Dict a
union = Map.unionWith OneOrMore.more

unions :: [Dict a] -> Dict a
unions = Map.unionsWith OneOrMore.more

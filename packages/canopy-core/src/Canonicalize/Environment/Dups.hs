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

import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result

-- DUPLICATE TRACKER

type Dict value =
  Map.Map Name.Name (OneOrMore.OneOrMore (Info value))

data Info value = Info
  { _region :: Ann.Region,
    _value :: value
  }

-- DETECT

type ToError =
  Name.Name -> Ann.Region -> Ann.Region -> Error.Error

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

checkFields :: [(Ann.Located Name.Name, a)] -> Result.Result i w Error.Error (Map.Map Name.Name a)
checkFields fields =
  detect Error.DuplicateField (foldr addField none fields)

addField :: (Ann.Located Name.Name, a) -> Dict a -> Dict a
addField (Ann.At region name, value) = Map.insertWith OneOrMore.more name (OneOrMore.one (Info region value))

checkFields' :: (Ann.Region -> a -> b) -> [(Ann.Located Name.Name, a)] -> Result.Result i w Error.Error (Map.Map Name.Name b)
checkFields' toValue fields =
  detect Error.DuplicateField (foldr (addField' toValue) none fields)

addField' :: (Ann.Region -> a -> b) -> (Ann.Located Name.Name, a) -> Dict b -> Dict b
addField' toValue (Ann.At region name, value) = Map.insertWith OneOrMore.more name (OneOrMore.one (Info region (toValue region value)))

-- BUILDING DICTIONARIES

none :: Dict a
none =
  Map.empty

one :: Name.Name -> Ann.Region -> value -> Dict value
one name region value =
  Map.singleton name (OneOrMore.one (Info region value))

insert :: Name.Name -> Ann.Region -> a -> Dict a -> Dict a
insert name region value = Map.insertWith (flip OneOrMore.more) name (OneOrMore.one (Info region value))

union :: Dict a -> Dict a -> Dict a
union = Map.unionWith OneOrMore.more

unions :: [Dict a] -> Dict a
unions = Map.unionsWith OneOrMore.more

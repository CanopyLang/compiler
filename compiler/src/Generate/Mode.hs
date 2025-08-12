module Generate.Mode
  ( Mode (..),
    isDebug,
    ShortFieldNames,
    shortenFieldNames,
  )
where

import AST.Optimized (GlobalGraph (..))
import qualified Canopy.Compiler.Type.Extract as Extract
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import qualified Generate.JavaScript.Name as JsName

-- MODE

data Mode
  = Dev (Maybe Extract.Types)
  | Prod ShortFieldNames
  deriving (Show)

isDebug :: Mode -> Bool
isDebug mode =
  case mode of
    Dev mi -> Maybe.isJust mi
    Prod _ -> False

-- SHORTEN FIELD NAMES

type ShortFieldNames =
  Map Name.Name JsName.Name

shortenFieldNames :: GlobalGraph -> ShortFieldNames
shortenFieldNames (GlobalGraph _ frequencies) =
  Map.foldr addToShortNames Map.empty $
    Map.foldrWithKey addToBuckets Map.empty frequencies

addToBuckets :: Name.Name -> Int -> Map Int [Name.Name] -> Map Int [Name.Name]
addToBuckets field frequency = Map.insertWith (++) frequency [field]

addToShortNames :: [Name.Name] -> ShortFieldNames -> ShortFieldNames
addToShortNames fields shortNames =
  List.foldl' addField shortNames fields

addField :: ShortFieldNames -> Name.Name -> ShortFieldNames
addField shortNames field =
  let rename = JsName.fromInt (Map.size shortNames)
   in Map.insert field rename shortNames

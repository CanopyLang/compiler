module Generate.Mode
  ( Mode(..)
  , isDebug
  , isElmCompatible
  , isFFIStrict
  , ShortFieldNames
  , shortenFieldNames
  , stringPool
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
import qualified Generate.JavaScript.StringPool as StringPool

-- MODE

-- | Compilation mode with associated configuration.
--
-- @since 0.19.1
data Mode
  = Dev (Maybe Extract.Types) Bool Bool
    -- ^ Development mode: (debug types, elm-compatibility, ffi-strict)
  | Prod ShortFieldNames Bool Bool StringPool.StringPool
    -- ^ Production mode: (short names, elm-compatibility, ffi-strict, string pool)
  deriving (Show)

-- | Check if debug mode is enabled.
isDebug :: Mode -> Bool
isDebug mode =
  case mode of
    Dev mi _ _ -> Maybe.isJust mi
    Prod {} -> False

-- ELM COMPATIBILITY

-- | Check if Elm compatibility mode is enabled.
isElmCompatible :: Mode -> Bool
isElmCompatible mode =
  case mode of
    Dev _ elmCompat _ -> elmCompat
    Prod _ elmCompat _ _ -> elmCompat

-- FFI STRICT MODE

-- | Check if FFI strict validation mode is enabled.
--
-- When enabled, the compiler generates runtime validators for FFI function
-- return values. This helps catch type mismatches at the JavaScript boundary
-- during development.
--
-- @since 0.19.1
isFFIStrict :: Mode -> Bool
isFFIStrict mode =
  case mode of
    Dev _ _ ffiStrict -> ffiStrict
    Prod _ _ ffiStrict _ -> ffiStrict

-- STRING POOL

-- | Extract the string pool from a mode (empty for Dev).
stringPool :: Mode -> StringPool.StringPool
stringPool mode =
  case mode of
    Dev {} -> StringPool.emptyPool
    Prod _ _ _ pool -> pool

-- SHORTEN FIELD NAMES

type ShortFieldNames =
  Map Name.Name JsName.Name

shortenFieldNames :: GlobalGraph -> ShortFieldNames
shortenFieldNames (GlobalGraph _ frequencies _) =
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

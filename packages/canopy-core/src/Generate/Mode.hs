module Generate.Mode
  ( Mode(..)
  , isDebug
  , isElmCompatible
  , isFFIStrict
  , isFFIAlias
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
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.StringPool as StringPool

-- MODE

-- | Compilation mode with associated configuration.
--
-- @since 0.19.1
data Mode
  = Dev (Maybe Extract.Types) Bool Bool (Set Name.Name)
    -- ^ Development mode: (debug types, elm-compatibility, ffi-unsafe, ffi-aliases)
  | Prod ShortFieldNames Bool Bool StringPool.StringPool (Set Name.Name)
    -- ^ Production mode: (short names, elm-compatibility, ffi-unsafe, string pool, ffi-aliases)
  deriving (Show)

-- | Check if debug mode is enabled.
isDebug :: Mode -> Bool
isDebug mode =
  case mode of
    Dev mi _ _ _ -> Maybe.isJust mi
    Prod {} -> False

-- ELM COMPATIBILITY

-- | Check if Elm compatibility mode is enabled.
isElmCompatible :: Mode -> Bool
isElmCompatible mode =
  case mode of
    Dev _ elmCompat _ _ -> elmCompat
    Prod _ elmCompat _ _ _ -> elmCompat

-- FFI VALIDATION MODE

-- | Check if FFI runtime validation is enabled.
--
-- Runtime validation is ENABLED BY DEFAULT. The compiler generates runtime
-- validators for FFI function return values to catch type mismatches at the
-- JavaScript boundary.
--
-- Use --ffi-unsafe to disable validation for performance-critical production
-- builds where you are confident the FFI types are correct.
--
-- @since 0.19.1
isFFIStrict :: Mode -> Bool
isFFIStrict mode =
  case mode of
    Dev _ _ ffiUnsafe _ -> not ffiUnsafe
    Prod _ _ ffiUnsafe _ _ -> not ffiUnsafe

-- | Check if a module name is an FFI alias (from foreign import statements).
--
-- FFI modules use direct JavaScript access (e.g., Math.add), while regular
-- application modules use qualified names (e.g., $author$project$UtilsTest$func).
--
-- @since 0.19.1
isFFIAlias :: Mode -> Name.Name -> Bool
isFFIAlias mode name =
  case mode of
    Dev _ _ _ ffiAliases -> Set.member name ffiAliases
    Prod _ _ _ _ ffiAliases -> Set.member name ffiAliases

-- STRING POOL

-- | Extract the string pool from a mode (empty for Dev).
stringPool :: Mode -> StringPool.StringPool
stringPool mode =
  case mode of
    Dev {} -> StringPool.emptyPool
    Prod _ _ _ pool _ -> pool

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

{-# LANGUAGE OverloadedStrings #-}

-- | Package diff operations for Terminal.
--
-- Computes differences between package versions for semantic versioning,
-- downloads and caches package documentation, and recommends version bumps.
--
-- @since 0.19.1
module Deps.Diff
  ( -- * Types
    Changes (..),
    ModuleChanges (..),
    PackageChanges (..),

    -- * Operations
    diff,
    toMagnitude,
    moduleChangeMagnitude,
    getDocs,
    bump,
  )
where

import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Docs as Docs
import qualified Canopy.Magnitude as Magnitude
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Json.String as Json
import Control.Monad (zipWithM)
import Data.Function (on)
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import qualified Deps.Website as Website
import qualified File.FileSystem as File
import qualified File.Utf8 as File
import qualified Http
import qualified Json.Decode as Decode
import qualified System.Directory as Dir
import System.FilePath ((</>))

-- | Changes in a map with additions, modifications, and removals.
data Changes k v = Changes
  { _added :: !(Map k v),
    _changed :: !(Map k (v, v)),
    _removed :: !(Map k v)
  }
  deriving (Show, Eq)

-- | Module-level changes across all declaration types.
data ModuleChanges = ModuleChanges
  { _unions :: !(Changes Name.Name Docs.Union),
    _aliases :: !(Changes Name.Name Docs.Alias),
    _values :: !(Changes Name.Name Docs.Value),
    _binops :: !(Changes Name.Name Docs.Binop)
  }

-- | Package-level changes with added, changed, and removed modules.
data PackageChanges = PackageChanges
  { _modulesAdded :: ![Name.Name],
    _modulesChanged :: !(Map Name.Name ModuleChanges),
    _modulesRemoved :: ![Name.Name]
  }

-- COMPUTE CHANGES

-- | Compute changes between two maps using an equivalence function.
getChanges :: (Ord k) => (v -> v -> Bool) -> Map k v -> Map k v -> Changes k v
getChanges isEquivalent old new =
  let overlap = Map.intersectionWith (,) old new
      changed = Map.filter (not . uncurry isEquivalent) overlap
   in Changes (Map.difference new old) changed (Map.difference old new)

-- DIFF DOCUMENTATION

-- | Compute diff between two documentation versions.
diff :: Docs.Documentation -> Docs.Documentation -> PackageChanges
diff oldDocs newDocs =
  let (Changes added changed removed) =
        getChanges (\_ _ -> False) oldDocs newDocs
      filterOutPatches = Map.filter (\chng -> moduleChangeMagnitude chng /= Magnitude.PATCH)
   in PackageChanges
        (Map.keys added)
        (filterOutPatches (Map.map diffModule changed))
        (Map.keys removed)

-- | Compute diff between two module versions.
diffModule :: (Docs.Module, Docs.Module) -> ModuleChanges
diffModule (Docs.Module _ _ u1 a1 v1 b1, Docs.Module _ _ u2 a2 v2 b2) =
  ModuleChanges
    (getChanges isEquivalentUnion u1 u2)
    (getChanges isEquivalentAlias a1 a2)
    (getChanges isEquivalentValue v1 v2)
    (getChanges isEquivalentBinop b1 b2)

-- EQUIVALENCE CHECKING

-- | Check if two union types are equivalent.
isEquivalentUnion :: Docs.Union -> Docs.Union -> Bool
isEquivalentUnion (Docs.Union _ oldVars oldCtors) (Docs.Union _ _ newCtors) =
  length oldCtors == length newCtors
    && and (zipWith (==) (fmap fst oldCtors) (fmap fst newCtors))
    && and (Map.elems (Map.intersectionWith equiv (Map.fromList oldCtors) (Map.fromList newCtors)))
  where
    equiv :: [Type.Type] -> [Type.Type] -> Bool
    equiv oldTypes newTypes =
      let allEquivalent =
            zipWith
              (\ot nt -> isEquivalentAlias (Docs.Alias (Json.fromChars "") oldVars ot) (Docs.Alias (Json.fromChars "") oldVars nt))
              oldTypes
              newTypes
       in length oldTypes == length newTypes && and allEquivalent

-- | Check if two type aliases are equivalent.
isEquivalentAlias :: Docs.Alias -> Docs.Alias -> Bool
isEquivalentAlias (Docs.Alias _ oldVars oldType) (Docs.Alias _ newVars newType) =
  case diffType oldType newType of
    Nothing -> False
    Just renamings ->
      length oldVars == length newVars
        && isEquivalentRenaming (zip oldVars newVars <> renamings)

-- | Check if two values are equivalent.
isEquivalentValue :: Docs.Value -> Docs.Value -> Bool
isEquivalentValue (Docs.Value _ t1) (Docs.Value _ t2) =
  isEquivalentAlias (Docs.Alias (Json.fromChars "") [] t1) (Docs.Alias (Json.fromChars "") [] t2)

-- | Check if two binops are equivalent.
isEquivalentBinop :: Docs.Binop -> Docs.Binop -> Bool
isEquivalentBinop (Docs.Binop _ t1 a1 p1) (Docs.Binop _ t2 a2 p2) =
  isEquivalentAlias (Docs.Alias (Json.fromChars "") [] t1) (Docs.Alias (Json.fromChars "") [] t2)
    && a1 == a2
    && p1 == p2

-- DIFF TYPES

-- | Compute type differences as variable renamings.
diffType :: Type.Type -> Type.Type -> Maybe [(Name.Name, Name.Name)]
diffType oldType newType =
  case (oldType, newType) of
    (Type.Var oldName, Type.Var newName) ->
      Just [(oldName, newName)]
    (Type.Lambda a b, Type.Lambda a' b') ->
      (++) <$> diffType a a' <*> diffType b b'
    (Type.Type oldName oldArgs, Type.Type newName newArgs) ->
      if not (isSameName oldName newName) || length oldArgs /= length newArgs
        then Nothing
        else concat <$> zipWithM diffType oldArgs newArgs
    (Type.Record fields maybeExt, Type.Record fields' maybeExt') ->
      case (maybeExt, maybeExt') of
        (Nothing, Just _) -> Nothing
        (Just _, Nothing) -> Nothing
        (Nothing, Nothing) -> diffFields fields fields'
        (Just oldExt, Just newExt) ->
          (:) (oldExt, newExt) <$> diffFields fields fields'
    (Type.Unit, Type.Unit) -> Just []
    (Type.Tuple a b cs, Type.Tuple x y zs) ->
      if length cs /= length zs
        then Nothing
        else do
          aVars <- diffType a x
          bVars <- diffType b y
          cVars <- concat <$> zipWithM diffType cs zs
          pure (aVars <> (bVars <> cVars))
    (_, _) -> Nothing

-- | Handle old docs that don't use qualified names.
isSameName :: Name.Name -> Name.Name -> Bool
isSameName oldFullName newFullName =
  let dedot name = reverse (Name.splitDots name)
   in case (dedot oldFullName, dedot newFullName) of
        ([oldName], newName : _) -> oldName == newName
        (oldName : _, [newName]) -> oldName == newName
        _ -> oldFullName == newFullName

-- | Diff record fields.
diffFields :: [(Name.Name, Type.Type)] -> [(Name.Name, Type.Type)] -> Maybe [(Name.Name, Name.Name)]
diffFields oldRawFields newRawFields =
  let sort = List.sortBy (compare `on` fst)
      oldFields = sort oldRawFields
      newFields = sort newRawFields
   in if length oldRawFields /= length newRawFields || or (zipWith ((/=) `on` fst) oldFields newFields)
        then Nothing
        else concat <$> zipWithM (diffType `on` snd) oldFields newFields

-- TYPE VARIABLE EQUIVALENCE

-- | Check if variable renamings are equivalent.
isEquivalentRenaming :: [(Name.Name, Name.Name)] -> Bool
isEquivalentRenaming varPairs =
  let renamings = Map.toList (foldr insert Map.empty varPairs)
      verify (old, news) =
        case news of
          [] -> Nothing
          new : rest ->
            if all (new ==) rest
              then Just (old, new)
              else Nothing
      allUnique list = length list == Set.size (Set.fromList list)
      insert (old, new) = Map.insertWith (++) old [new]
   in case traverse verify renamings of
        Nothing -> False
        Just verifiedRenamings ->
          all compatibleVars verifiedRenamings
            && allUnique (fmap snd verifiedRenamings)

-- | Category of type variable.
data TypeVarCategory
  = CompAppend
  | Comparable
  | Appendable
  | Number
  | Var
  deriving (Eq)

-- | Check if variables are compatible.
compatibleVars :: (Name.Name, Name.Name) -> Bool
compatibleVars (old, new) =
  case (categorizeVar old, categorizeVar new) of
    (CompAppend, CompAppend) -> True
    (Comparable, Comparable) -> True
    (Appendable, Appendable) -> True
    (Number, Number) -> True
    (Number, Comparable) -> True
    (_, Var) -> True
    (_, _) -> False

-- | Categorize a type variable.
categorizeVar :: Name.Name -> TypeVarCategory
categorizeVar name
  | Name.isCompappendType name = CompAppend
  | Name.isComparableType name = Comparable
  | Name.isAppendableType name = Appendable
  | Name.isNumberType name = Number
  | otherwise = Var

-- MAGNITUDE CALCULATION

-- | Bump version based on package changes.
bump :: PackageChanges -> Version.Version -> Version.Version
bump changes version =
  case toMagnitude changes of
    Magnitude.PATCH -> Version.bumpPatch version
    Magnitude.MINOR -> Version.bumpMinor version
    Magnitude.MAJOR -> Version.bumpMajor version

-- | Compute magnitude of package changes.
toMagnitude :: PackageChanges -> Magnitude.Magnitude
toMagnitude (PackageChanges added changed removed) =
  let addMag = if null added then Magnitude.PATCH else Magnitude.MINOR
      removeMag = if null removed then Magnitude.PATCH else Magnitude.MAJOR
      changeMags = fmap moduleChangeMagnitude (Map.elems changed)
   in maximum (addMag : removeMag : changeMags)

-- | Compute magnitude of module changes.
moduleChangeMagnitude :: ModuleChanges -> Magnitude.Magnitude
moduleChangeMagnitude (ModuleChanges unions aliases values binops) =
  maximum
    [ changeMagnitude unions,
      changeMagnitude aliases,
      changeMagnitude values,
      changeMagnitude binops
    ]

-- | Compute magnitude of specific changes.
changeMagnitude :: Changes k v -> Magnitude.Magnitude
changeMagnitude (Changes added changed removed)
  | Map.size removed > 0 || Map.size changed > 0 = Magnitude.MAJOR
  | Map.size added > 0 = Magnitude.MINOR
  | otherwise = Magnitude.PATCH

-- GET DOCUMENTATION

-- | Download and cache package documentation.
getDocs :: FilePath -> Http.Manager -> Pkg.Name -> Version.Version -> IO (Either String Docs.Documentation)
getDocs cache manager name version = do
  let home = cache </> Pkg.toChars name </> Version.toChars version
      path = home </> "docs.json"
  exists <- File.exists path
  if exists
    then readCachedDocs path
    else downloadAndCacheDocs manager name version home path

-- | Read cached documentation from disk.
readCachedDocs :: FilePath -> IO (Either String Docs.Documentation)
readCachedDocs path = do
  bytes <- File.readUtf8 path
  case Decode.fromByteString Docs.decoder bytes of
    Right docs -> pure (Right docs)
    Left _ -> do
      File.remove path
      pure (Left "Cached docs corrupted")

-- | Download documentation from registry and cache it.
downloadAndCacheDocs :: Http.Manager -> Pkg.Name -> Version.Version -> FilePath -> FilePath -> IO (Either String Docs.Documentation)
downloadAndCacheDocs manager name version home path = do
  let url = Website.route "https://package.elm-lang.org" ("/packages/" <> Pkg.toUrl name <> "/" <> Version.toChars version) [("file", "docs.json")]
  Http.getWithFallback manager url [] show $ \body ->
    case Decode.fromByteString Docs.decoder body of
      Right docs -> do
        Dir.createDirectoryIfMissing True home
        File.writeUtf8 path body
        pure (Right docs)
      Left _ ->
        pure (Left ("Failed to decode docs.json from " <> url))

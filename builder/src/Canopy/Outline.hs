{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
{-# OPTIONS_GHC -Wall #-}

module Canopy.Outline
  ( Outline (..),
    AppOutline (..),
    PkgOutline (..),
    Exposed (..),
    SrcDir (..),
    read,
    write,
    encode,
    decoder,
    elmDecoder,
    defaultSummary,
    flattenExposed,
  )
where

import Canopy.Constraint (Constraint)
import qualified Canopy.Constraint as Con
import qualified Canopy.Licenses as Licenses
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Canopy.PackageOverrideData (PackageOverrideData (..))
import qualified Canopy.PackageOverrideData as PkgOverride
import Canopy.Version (Version)
import qualified Canopy.Version as V
import Control.Monad (filterM)
import Data.Binary (Binary, get, getWord8, put, putWord8)
import Data.List (isSuffixOf)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe (mapMaybe)
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import qualified Data.OneOrMore as OneOrMore
import qualified File
import Foreign.Ptr (minusPtr)
import qualified Json.Decode as D
import Json.Encode ((==>))
import qualified Json.Encode as E
import qualified Json.String as Json
import qualified Parse.Primitives as P
import qualified Reporting.Exit as Exit
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.FilePath as FP
import Prelude hiding (read)

-- OUTLINE

data Outline
  = App AppOutline
  | Pkg PkgOutline
  deriving (Show)

data AppOutline = AppOutline
  { _app_canopy_version :: Version,
    _app_source_dirs :: List SrcDir,
    _app_deps_direct :: Map Pkg.Name Version,
    _app_deps_indirect :: Map Pkg.Name Version,
    _app_test_direct :: Map Pkg.Name Version,
    _app_test_indirect :: Map Pkg.Name Version,
    _app_zokka_package_overrides :: [PkgOverride.PackageOverrideData]
  }
  deriving (Show)

data PkgOutline = PkgOutline
  { _pkg_name :: Pkg.Name,
    _pkg_summary :: Json.String,
    _pkg_license :: Licenses.License,
    _pkg_version :: Version,
    _pkg_exposed :: Exposed,
    _pkg_deps :: Map Pkg.Name Constraint,
    _pkg_test_deps :: Map Pkg.Name Constraint,
    _pkg_canopy_version :: Constraint
  }
  deriving (Show)

data Exposed
  = ExposedList [ModuleName.Raw]
  | ExposedDict [(Json.String, [ModuleName.Raw])]
  deriving (Show)

data SrcDir
  = AbsoluteSrcDir FilePath
  | RelativeSrcDir FilePath
  deriving (Show)

-- DEFAULTS

defaultSummary :: Json.String
defaultSummary =
  Json.fromChars "helpful summary of your project, less than 80 characters"

-- HELPERS

flattenExposed :: Exposed -> [ModuleName.Raw]
flattenExposed exposed =
  case exposed of
    ExposedList names ->
      names
    ExposedDict sections ->
      concatMap snd sections

-- WRITE

write :: FilePath -> Outline -> IO ()
write root outline =
  do
    configPath <- Stuff.getConfigFilePath root
    E.write configPath (encode outline)

-- JSON ENCODE

encode :: Outline -> E.Value
encode outline =
  case outline of
    App (AppOutline canopy srcDirs depsDirect depsTrans testDirect testTrans pkgOverrides) ->
      E.object
        [ "type" ==> E.chars "application",
          "source-directories" ==> E.list encodeSrcDir (NE.toList srcDirs),
          "canopy-version" ==> V.encode canopy,
          "dependencies"
            ==> E.object
              [ "direct" ==> encodeDeps V.encode depsDirect,
                "indirect" ==> encodeDeps V.encode depsTrans
              ],
          "test-dependencies"
            ==> E.object
              [ "direct" ==> encodeDeps V.encode testDirect,
                "indirect" ==> encodeDeps V.encode testTrans
              ],
          "zokka-package-overrides" ==> E.list encodePkgOverride pkgOverrides
        ]
    Pkg (PkgOutline name summary license version exposed deps tests canopy) ->
      E.object
        [ "type" ==> E.string (Json.fromChars "package"),
          "name" ==> Pkg.encode name,
          "summary" ==> E.string summary,
          "license" ==> Licenses.encode license,
          "version" ==> V.encode version,
          "exposed-modules" ==> encodeExposed exposed,
          "canopy-version" ==> Con.encode canopy,
          "dependencies" ==> encodeDeps Con.encode deps,
          "test-dependencies" ==> encodeDeps Con.encode tests
        ]

encodeExposed :: Exposed -> E.Value
encodeExposed exposed =
  case exposed of
    ExposedList modules ->
      E.list encodeModule modules
    ExposedDict chunks ->
      E.object (fmap (fmap (E.list encodeModule)) chunks)

encodeModule :: ModuleName.Raw -> E.Value
encodeModule = E.name

encodeDeps :: (a -> E.Value) -> Map Pkg.Name a -> E.Value
encodeDeps = E.dict Pkg.toJsonString

encodeSrcDir :: SrcDir -> E.Value
encodeSrcDir srcDir =
  case srcDir of
    AbsoluteSrcDir dir -> E.chars dir
    RelativeSrcDir dir -> E.chars dir

encodePkgOverride :: PackageOverrideData -> E.Value
encodePkgOverride (PackageOverrideData overridePackageName overridePackageVersion originalPackageName originalPackageVersion) =
  E.object
    [ "original-package-name" ==> Pkg.encode originalPackageName,
      "original-package-version" ==> V.encode originalPackageVersion,
      "override-package-name" ==> Pkg.encode overridePackageName,
      "override-package-version" ==> V.encode overridePackageVersion
    ]

-- PARSE AND VERIFY

findPkgOverridesAgainstNonexistentDeps :: Map Pkg.Name Version -> PackageOverrideData -> Maybe (Pkg.Name, Version)
findPkgOverridesAgainstNonexistentDeps deps PackageOverrideData {_originalPackageName = originalPackageName, _originalPackageVersion = originalPackageVersion} =
  if nameAndVersionMatch then Nothing else Just (originalPackageName, originalPackageVersion)
  where
    nameAndVersionMatch = Map.lookup originalPackageName deps == Just originalPackageVersion

read :: FilePath -> IO (Either Exit.Outline Outline)
read root =
  do
    configPath <- Stuff.getConfigFilePath root
    let usedDecoder = if "canopy.json" `isSuffixOf` configPath then decoder else elmDecoder
    bytes <- File.readUtf8 configPath
    case D.fromByteString usedDecoder bytes of
      Left err ->
        return $ Left (Exit.OutlineHasBadStructure err)
      Right outline ->
        case outline of
          Pkg (PkgOutline pkg _ _ _ _ deps _ _) ->
            return $
              if Map.notMember Pkg.core deps && pkg /= Pkg.core
                then Left Exit.OutlineNoPkgCore
                else Right outline
          App (AppOutline _ srcDirs direct indirect _ _ pkgOverrides)
            | Map.notMember Pkg.core direct ->
              return $ Left Exit.OutlineNoAppCore
            | (packageName, packageVersion) : _ <- mapMaybe (findPkgOverridesAgainstNonexistentDeps (Map.union direct indirect)) pkgOverrides ->
              pure $ Left (Exit.OutlinePkgOverridesDoNotMatchDeps packageName packageVersion)
            | otherwise ->
              do
                badDirs <- filterM (isSrcDirMissing root) (NE.toList srcDirs)
                case fmap toGiven badDirs of
                  d : ds ->
                    return $ Left (Exit.OutlineHasMissingSrcDirs d ds)
                  [] ->
                    do
                      maybeDups <- detectDuplicates root (NE.toList srcDirs)
                      case maybeDups of
                        Nothing ->
                          return $ Right outline
                        Just (canonicalDir, (dir1, dir2)) ->
                          return $ Left (Exit.OutlineHasDuplicateSrcDirs canonicalDir dir1 dir2)

isSrcDirMissing :: FilePath -> SrcDir -> IO Bool
isSrcDirMissing root srcDir =
  not <$> Dir.doesDirectoryExist (toAbsolute root srcDir)

toGiven :: SrcDir -> FilePath
toGiven srcDir =
  case srcDir of
    AbsoluteSrcDir dir -> dir
    RelativeSrcDir dir -> dir

toAbsolute :: FilePath -> SrcDir -> FilePath
toAbsolute root srcDir =
  case srcDir of
    AbsoluteSrcDir dir -> dir
    RelativeSrcDir dir -> root </> dir

detectDuplicates :: FilePath -> [SrcDir] -> IO (Maybe (FilePath, (FilePath, FilePath)))
detectDuplicates root srcDirs =
  do
    pairs <- traverse (toPair root) srcDirs
    (return . Map.lookupMin) . Map.mapMaybe isDup $ Map.fromListWith OneOrMore.more pairs

toPair :: FilePath -> SrcDir -> IO (FilePath, OneOrMore.OneOrMore FilePath)
toPair root srcDir =
  do
    key <- Dir.canonicalizePath (toAbsolute root srcDir)
    return (key, OneOrMore.one (toGiven srcDir))

isDup :: OneOrMore.OneOrMore FilePath -> Maybe (FilePath, FilePath)
isDup paths =
  case paths of
    OneOrMore.One _ -> Nothing
    OneOrMore.More a b -> Just (OneOrMore.getFirstTwo a b)

-- JSON DECODE

type Decoder a =
  D.Decoder Exit.OutlineProblem a

decoder :: Decoder Outline
decoder =
  let application = Json.fromChars "application"
      package = Json.fromChars "package"
   in do
        tipe <- D.field "type" D.string
        if
            | tipe == application -> App <$> appDecoder
            | tipe == package -> Pkg <$> pkgDecoder
            | otherwise -> D.failure Exit.OP_BadType

elmDecoder :: Decoder Outline
elmDecoder =
  let application = Json.fromChars "application"
      package = Json.fromChars "package"
   in do
        tipe <- D.field "type" D.string
        if tipe == application
          then App <$> elmAppDecoder
          else
            if tipe == package
              then Pkg <$> elmPkgDecoder
              else D.failure Exit.OP_BadType

appDecoder :: Decoder AppOutline
appDecoder =
  AppOutline
    <$> D.field "canopy-version" versionDecoder
    <*> D.field "source-directories" dirsDecoder
    <*> D.field "dependencies" (D.field "direct" (depsDecoder versionDecoder))
    <*> D.field "dependencies" (D.field "indirect" (depsDecoder versionDecoder))
    <*> D.field "test-dependencies" (D.field "direct" (depsDecoder versionDecoder))
    <*> D.field "test-dependencies" (D.field "indirect" (depsDecoder versionDecoder))
    <*> D.oneOf [D.field "zokka-package-overrides" (D.list packageOverrideDataDecoder), pure []]

elmAppDecoder :: Decoder AppOutline
elmAppDecoder =
  AppOutline
    <$> D.field "elm-version" versionDecoder
    <*> D.field "source-directories" dirsDecoder
    <*> D.field "dependencies" (D.field "direct" (depsDecoder versionDecoder))
    <*> D.field "dependencies" (D.field "indirect" (depsDecoder versionDecoder))
    <*> D.field "test-dependencies" (D.field "direct" (depsDecoder versionDecoder))
    <*> D.field "test-dependencies" (D.field "indirect" (depsDecoder versionDecoder))
    <*> pure []

elmPkgDecoder :: Decoder PkgOutline
elmPkgDecoder =
  PkgOutline
    <$> D.field "name" nameDecoder
    <*> D.field "summary" summaryDecoder
    <*> D.field "license" (Licenses.decoder Exit.OP_BadLicense)
    <*> D.field "version" versionDecoder
    <*> D.field "exposed-modules" exposedDecoder
    <*> D.field "dependencies" (depsDecoder constraintDecoder)
    <*> D.field "test-dependencies" (depsDecoder constraintDecoder)
    <*> D.field "elm-version" constraintDecoder

pkgDecoder :: Decoder PkgOutline
pkgDecoder =
  PkgOutline
    <$> D.field "name" nameDecoder
    <*> D.field "summary" summaryDecoder
    <*> D.field "license" (Licenses.decoder Exit.OP_BadLicense)
    <*> D.field "version" versionDecoder
    <*> D.field "exposed-modules" exposedDecoder
    <*> D.field "dependencies" (depsDecoder constraintDecoder)
    <*> D.field "test-dependencies" (depsDecoder constraintDecoder)
    <*> D.field "canopy-version" constraintDecoder

-- JSON DECODE HELPERS

nameDecoder :: Decoder Pkg.Name
nameDecoder =
  D.mapError (uncurry Exit.OP_BadPkgName) Pkg.decoder

summaryDecoder :: Decoder Json.String
summaryDecoder =
  D.customString
    (boundParser 80 Exit.OP_BadSummaryTooLong)
    (\_ _ -> Exit.OP_BadSummaryTooLong)

versionDecoder :: Decoder Version
versionDecoder =
  D.mapError (uncurry Exit.OP_BadVersion) V.decoder

constraintDecoder :: Decoder Constraint
constraintDecoder =
  D.mapError Exit.OP_BadConstraint Con.decoder

depsDecoder :: Decoder a -> Decoder (Map Pkg.Name a)
depsDecoder = D.dict (Pkg.keyDecoder Exit.OP_BadDependencyName)

dirsDecoder :: Decoder (List SrcDir)
dirsDecoder =
  fmap (toSrcDir . Json.toChars) <$> D.nonEmptyList D.string Exit.OP_NoSrcDirs

packageOverrideDataDecoder :: Decoder PkgOverride.PackageOverrideData
packageOverrideDataDecoder =
  PkgOverride.PackageOverrideData
    <$> D.field "override-package-name" nameDecoder
    <*> D.field "override-package-version" versionDecoder
    <*> D.field "original-package-name" nameDecoder
    <*> D.field "original-package-version" versionDecoder

toSrcDir :: FilePath -> SrcDir
toSrcDir path =
  if FP.isRelative path
    then RelativeSrcDir path
    else AbsoluteSrcDir path

-- EXPOSED MODULES DECODER

exposedDecoder :: Decoder Exposed
exposedDecoder =
  D.oneOf
    [ ExposedList <$> D.list moduleDecoder,
      ExposedDict <$> D.pairs headerKeyDecoder (D.list moduleDecoder)
    ]

moduleDecoder :: Decoder ModuleName.Raw
moduleDecoder =
  D.mapError (uncurry Exit.OP_BadModuleName) ModuleName.decoder

headerKeyDecoder :: D.KeyDecoder Exit.OutlineProblem Json.String
headerKeyDecoder =
  D.KeyDecoder
    (boundParser 20 Exit.OP_BadModuleHeaderTooLong)
    (\_ _ -> Exit.OP_BadModuleHeaderTooLong)

-- BOUND PARSER

boundParser :: Int -> x -> P.Parser x Json.String
boundParser bound tooLong =
  P.Parser $ \(P.State src pos end indent row col) cok _ cerr _ ->
    let len = minusPtr end pos
        newCol = col + fromIntegral len
     in if len < bound
          then cok (Json.fromPtr pos end) (P.State src end end indent row newCol)
          else cerr row newCol (\_ _ -> tooLong)

-- BINARY

instance Binary SrcDir where
  put outline =
    case outline of
      AbsoluteSrcDir a -> putWord8 0 >> put a
      RelativeSrcDir a -> putWord8 1 >> put a

  get =
    do
      n <- getWord8
      case n of
        0 -> fmap AbsoluteSrcDir get
        1 -> fmap RelativeSrcDir get
        _ -> fail "binary encoding of SrcDir was corrupted"

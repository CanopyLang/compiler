{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall -Wno-orphans #-}

-- | Pure project outline (canopy.json) for Terminal.
--
-- Minimal NEW implementation of Outline types without STM/MVar.
-- Handles reading and writing canopy.json configuration files.
--
-- @since 0.19.1
module Canopy.Outline
  ( -- * Outline Types
    Outline (..),
    AppOutline (..),
    PkgOutline (..),
    Exposed (..),
    SrcDir (..),

    -- * Reading/Writing
    read,
    write,

    -- * Encoding
    encode,

    -- * Utilities
    flattenExposed,

    -- * Defaults
    defaultSummary,
  )
where

import qualified Canopy.Constraint as C
import qualified Canopy.Licenses as Licenses
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Applicative ((<|>))
import Data.Aeson ((.=))
import qualified Data.Aeson as Json
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Json.Encode ((==>))
import qualified Json.Encode as E
import Prelude hiding (read)
import qualified System.Directory
import System.FilePath ((</>))

-- Orphan JSON instances for core types used in outline serialization.
instance Json.ToJSON C.Constraint where
  toJSON _ = Json.String "any"

instance Json.FromJSON C.Constraint where
  parseJSON _ = pure C.anything

instance Json.ToJSON Licenses.License where
  toJSON _ = Json.String "BSD-3-Clause"

instance Json.FromJSON Licenses.License where
  parseJSON _ = pure Licenses.bsd3

-- | Project outline (App or Pkg).
data Outline
  = App AppOutline
  | Pkg PkgOutline
  deriving (Show)

-- | Application outline.
data AppOutline = AppOutline
  { _appCanopy :: !V.Version,
    _appSrcDirs :: ![SrcDir],
    _appDeps :: !(Map Pkg.Name C.Constraint),
    _appTestDeps :: !(Map Pkg.Name C.Constraint),
    _appDepsDirect :: !(Map Pkg.Name V.Version),
    _appDepsIndirect :: !(Map Pkg.Name V.Version),
    _appTestDepsDirect :: !(Map Pkg.Name V.Version)
  }
  deriving (Show)

-- | Package outline.
data PkgOutline = PkgOutline
  { _pkgName :: !Pkg.Name,
    _pkgSummary :: !Text.Text,
    _pkgLicense :: !Licenses.License,
    _pkgVersion :: !V.Version,
    _pkgExposed :: !Exposed,
    _pkgDeps :: !(Map Pkg.Name C.Constraint),
    _pkgTestDeps :: !(Map Pkg.Name C.Constraint),
    _pkgCanopy :: !C.Constraint
  }
  deriving (Show)

-- | Exposed modules specification.
data Exposed
  = ExposedList [ModuleName.Raw]
  | ExposedDict [(Text.Text, [ModuleName.Raw])]
  deriving (Show, Eq)

-- | Source directory specification.
data SrcDir
  = AbsoluteSrcDir FilePath
  | RelativeSrcDir FilePath
  deriving (Show, Eq)

-- | Read outline from project root.
-- Checks for canopy.json first, then elm.json as fallback.
read :: FilePath -> IO (Maybe Outline)
read root = do
  let canopyPath = root </> "canopy.json"
      elmPath = root </> "elm.json"
  maybeCanopy <- safeReadFile canopyPath
  case maybeCanopy of
    Just content -> pure (Json.decode content)
    Nothing -> do
      maybeElm <- safeReadFile elmPath
      case maybeElm of
        Nothing -> pure Nothing
        Just content -> pure (Json.decode content)

-- | Write outline to project root.
write :: FilePath -> Outline -> IO ()
write root outline = do
  let path = root </> "canopy.json"
      content = Json.encode outline
  LBS.writeFile path content

-- | Default package summary.
defaultSummary :: Text.Text
defaultSummary = "A Canopy project"

-- | Safe file reading.
safeReadFile :: FilePath -> IO (Maybe LBS.ByteString)
safeReadFile path = do
  exists <- System.Directory.doesFileExist path
  if exists
    then Just <$> LBS.readFile path
    else pure Nothing

-- JSON instances (minimal)
instance Json.ToJSON Outline where
  toJSON (App appOutline) = Json.toJSON appOutline
  toJSON (Pkg pkgOutline) = Json.toJSON pkgOutline

instance Json.FromJSON Outline where
  parseJSON value =
    (App <$> Json.parseJSON value)
      <|> (Pkg <$> Json.parseJSON value)

instance Json.ToJSON AppOutline where
  toJSON (AppOutline canopy srcDirs deps testDeps depsDirect depsIndirect testDepsDirect) =
    Json.object
      [ "type" .= ("application" :: Text.Text),
        "canopy-version" .= canopy,
        "source-directories" .= srcDirs,
        "dependencies" .= deps,
        "test-dependencies" .= testDeps,
        "dependencies-direct" .= depsDirect,
        "dependencies-indirect" .= depsIndirect,
        "test-dependencies-direct" .= testDepsDirect
      ]

instance Json.FromJSON AppOutline where
  parseJSON = Json.withObject "AppOutline" $ \o -> do
    -- Support both "canopy-version" and "elm-version" for compatibility
    canopyVer <- (o Json..: "canopy-version") <|> (o Json..: "elm-version")
    srcDirs <- o Json..: "source-directories"

    deps <- o Json..: "dependencies"
    depsDirect <- deps Json..: "direct"
    depsIndirect <- deps Json..: "indirect"

    testDeps <- o Json..: "test-dependencies"
    testDepsDirect <- testDeps Json..: "direct"

    pure (AppOutline canopyVer srcDirs Map.empty Map.empty depsDirect depsIndirect testDepsDirect)

instance Json.ToJSON PkgOutline where
  toJSON (PkgOutline name summary license version exposed deps testDeps canopy) =
    Json.object
      [ "type" .= ("package" :: Text.Text),
        "name" .= name,
        "summary" .= summary,
        "license" .= license,
        "version" .= version,
        "exposed-modules" .= exposed,
        "dependencies" .= deps,
        "test-dependencies" .= testDeps,
        "canopy-version" .= canopy
      ]

instance Json.FromJSON PkgOutline where
  parseJSON = Json.withObject "PkgOutline" $ \o -> do
    -- Support both "canopy-version" and "elm-version" for compatibility
    canopyVer <- (o Json..: "canopy-version") <|> (o Json..: "elm-version")
    PkgOutline
      <$> o Json..: "name"
      <*> o Json..: "summary"
      <*> o Json..: "license"
      <*> o Json..: "version"
      <*> o Json..: "exposed-modules"
      <*> o Json..: "dependencies"
      <*> o Json..: "test-dependencies"
      <*> pure canopyVer

instance Json.ToJSON Exposed where
  toJSON (ExposedList mods) = Json.toJSON mods
  toJSON (ExposedDict dict) = Json.toJSON (Map.fromList dict)

instance Json.FromJSON Exposed where
  parseJSON value =
    (ExposedList <$> Json.parseJSON value)
      <|> (ExposedDict . Map.toList <$> Json.parseJSON value)

instance Json.ToJSON SrcDir where
  toJSON (AbsoluteSrcDir path) = Json.toJSON path
  toJSON (RelativeSrcDir path) = Json.toJSON path

instance Json.FromJSON SrcDir where
  parseJSON value = RelativeSrcDir <$> Json.parseJSON value

-- | Encode outline for Json.Encode (used by development server).
--
-- Converts Outline to Json.Encode.Value for serialization.
-- Used primarily by the development server's index generation.
--
-- @since 0.19.1
encode :: Outline -> E.Value
encode (App appOutline) = encodeAppOutline appOutline
encode (Pkg pkgOutline) = encodePkgOutline pkgOutline

-- | Encode application outline.
encodeAppOutline :: AppOutline -> E.Value
encodeAppOutline (AppOutline canopy srcDirs deps testDeps depsDirect depsIndirect testDepsDirect) =
  E.object
    [ "type" ==> E.chars "application",
      "canopy-version" ==> V.encode canopy,
      "source-directories" ==> E.list encodeSrcDir srcDirs,
      "dependencies" ==> E.dict Pkg.toJsonString C.encode deps,
      "test-dependencies" ==> E.dict Pkg.toJsonString C.encode testDeps,
      "dependencies-direct" ==> E.dict Pkg.toJsonString V.encode depsDirect,
      "dependencies-indirect" ==> E.dict Pkg.toJsonString V.encode depsIndirect,
      "test-dependencies-direct" ==> E.dict Pkg.toJsonString V.encode testDepsDirect
    ]

-- | Encode package outline.
encodePkgOutline :: PkgOutline -> E.Value
encodePkgOutline (PkgOutline name summary license version exposed deps testDeps canopy) =
  E.object
    [ "type" ==> E.chars "package",
      "name" ==> Pkg.encode name,
      "summary" ==> E.chars (Text.unpack summary),
      "license" ==> Licenses.encode license,
      "version" ==> V.encode version,
      "exposed-modules" ==> encodeExposed exposed,
      "dependencies" ==> E.dict Pkg.toJsonString C.encode deps,
      "test-dependencies" ==> E.dict Pkg.toJsonString C.encode testDeps,
      "canopy-version" ==> C.encode canopy
    ]

-- | Encode exposed modules.
encodeExposed :: Exposed -> E.Value
encodeExposed (ExposedList mods) = E.list ModuleName.encode mods
encodeExposed (ExposedDict dict) =
  E.object (map (\(category, mods) -> Text.unpack category ==> E.list ModuleName.encode mods) dict)

-- | Encode source directory.
encodeSrcDir :: SrcDir -> E.Value
encodeSrcDir (AbsoluteSrcDir path) = E.chars path
encodeSrcDir (RelativeSrcDir path) = E.chars path

-- | Flatten exposed modules to a simple list.
--
-- Converts both ExposedList and ExposedDict formats to a flat list
-- of module names, discarding category information from dictionaries.
--
-- @since 0.19.1
flattenExposed :: Exposed -> [ModuleName.Raw]
flattenExposed (ExposedList mods) = mods
flattenExposed (ExposedDict dict) = concatMap snd dict

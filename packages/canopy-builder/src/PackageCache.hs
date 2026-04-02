
-- | Package artifact cache loading for dependency interfaces.
--
-- This module provides functions to load compiled interfaces from package
-- artifact cache files. These artifacts are generated when packages are
-- installed and contain the compiled interfaces needed for type checking.
--
-- ==== Package Cache Structure
--
-- Installed packages store artifacts at:
-- @~/.elm/0.19.1/packages/author/package/version/artifacts.dat@
--
-- For Canopy, packages may also be at:
-- @~/.canopy/packages/author/package/version/artifacts.dat@
--
-- ==== Examples
--
-- >>> -- Load elm/core 1.0.5 interfaces
-- >>> interfaces <- loadPackageInterfaces "elm" "core" "1.0.5"
-- >>> case interfaces of
-- ...   Just ifaces -> -- Use the interfaces for compilation
-- ...   Nothing -> -- Package not installed or no artifacts
--
-- @since 0.19.1
module PackageCache
  ( -- * Loading Interfaces
    loadPackageInterfaces
  , loadElmCoreInterfaces
  , loadAllDependencyInterfaces
  , loadModuleInterface
    -- * Loading Complete Artifacts
  , loadPackageArtifacts
  , loadAllPackageArtifacts
    -- * Writing Artifacts
  , writePackageArtifacts
  , getPackageArtifactPath
    -- * Types
  , PackageInterfaces
  , PackageArtifacts(..)
  , ArtifactCache(..)
  , Artifacts(..)
    -- * FFI Fingerprint Validation
  , verifyFFIFingerprints
  ) where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Builder.Hash as Hash
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Canopy.Version (Version (..))
import qualified Canopy.Version as Version
import Control.Concurrent.Async (mapConcurrently)
import qualified Control.Monad as Monad
import Data.Binary (Binary)
import qualified Data.Binary as Binary
import Data.Binary.Get (Get)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word8, Word16)
import qualified Generate.JavaScript as JS
import qualified Interface.JSON as IFace
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Canopy.Data.Utf8 as Utf8
import qualified System.Directory as Dir
import System.FilePath ((</>), takeDirectory)

-- | Map of module names to their dependency interfaces.
type PackageInterfaces = Map ModuleName.Raw Interface.DependencyInterface

-- | Complete package artifacts including interfaces, optimized code, and FFI info.
data PackageArtifacts = PackageArtifacts
  { artifactInterfaces :: !PackageInterfaces
  , artifactObjects :: !Opt.GlobalGraph
  , artifactFFIInfo :: !(Map String JS.FFIInfo)
  }
  deriving (Show)

-- | Fingerprint tracking package dependencies (matches old Details.hs).
type Fingerprint = Map Pkg.Name Version.Version

-- | Artifact cache structure (matches old/builder/src/Canopy/Details.hs).
--
-- The '_ffiFingerprints' field stores the SHA-256 hash of every FFI
-- JavaScript file that was present when the artifact was compiled.  On
-- load, each stored fingerprint is verified against the current file on
-- disk; any mismatch causes the artifact to be treated as stale and
-- triggers a full package rebuild.
data ArtifactCache = ArtifactCache
  { _fingerprints :: !(Set Fingerprint)
  , _artifacts :: !Artifacts
  , _ffiFingerprints :: !(Map FilePath Hash.ContentHash)
  }

instance Binary ArtifactCache where
  get = Monad.liftM3 ArtifactCache Binary.get Binary.get Binary.get
  put (ArtifactCache fps arts ffiFPs) =
    Binary.put fps >> Binary.put arts >> Binary.put ffiFPs

-- | Compiled artifacts for a package (new format with FFI info).
data Artifacts = Artifacts
  { _ifaces :: !PackageInterfaces
  , _objects :: !Opt.GlobalGraph
  , _ffiInfo :: !(Map String JS.FFIInfo)
  }

instance Binary Artifacts where
  get = Monad.liftM3 Artifacts Binary.get Binary.get Binary.get
  put (Artifacts ifaces objs ffi) = Binary.put ifaces >> Binary.put objs >> Binary.put ffi

-- | Legacy artifacts format (no FFI info) for backward-compatible decoding.
data LegacyArtifacts = LegacyArtifacts !PackageInterfaces !Opt.GlobalGraph

instance Binary LegacyArtifacts where
  get = Monad.liftM2 LegacyArtifacts Binary.get Binary.get
  put (LegacyArtifacts ifaces objs) = Binary.put ifaces >> Binary.put objs

-- | Legacy artifact cache for backward-compatible decoding.
data LegacyArtifactCache = LegacyArtifactCache !(Set Fingerprint) !LegacyArtifacts

instance Binary LegacyArtifactCache where
  get = Monad.liftM2 LegacyArtifactCache Binary.get Binary.get
  put (LegacyArtifactCache fps arts) = Binary.put fps >> Binary.put arts

-- | Elm-era Union decoder (4 fields: vars, alts, numAlts, opts).
--
-- The current format has 5 fields with variances at position 2.
-- Fills in empty variances for backward compatibility with old Elm artifacts.
--
-- @since 0.19.1
newtype ElmCanUnion = ElmCanUnion { fromElmCanUnion :: Can.Union }

instance Binary ElmCanUnion where
  get = do
    vars <- Binary.get
    alts <- Binary.get
    numAlts <- Binary.get
    opts <- Binary.get
    return (ElmCanUnion (Can.Union vars [] alts numAlts opts []))
  put (ElmCanUnion u) = Binary.put u

-- | Elm-era Alias decoder (2 fields: vars, tipe).
--
-- The current format has 4 fields with variances and supertype bound.
-- Fills in empty variances and Nothing bound.
--
-- @since 0.19.1
newtype ElmCanAlias = ElmCanAlias { fromElmCanAlias :: Can.Alias }

instance Binary ElmCanAlias where
  get = do
    vars <- Binary.get
    tipe <- Binary.get
    return (ElmCanAlias (Can.Alias vars [] tipe Nothing []))
  put (ElmCanAlias a) = Binary.put a

-- | Elm-era Interface.Union decoder wrapping ElmCanUnion.
--
-- @since 0.19.1
newtype ElmIfaceUnion = ElmIfaceUnion { fromElmIfaceUnion :: Interface.Union }

instance Binary ElmIfaceUnion where
  get = do
    tag <- Binary.getWord8
    case tag of
      0 -> ElmIfaceUnion . Interface.OpenUnion . fromElmCanUnion <$> Binary.get
      1 -> ElmIfaceUnion . Interface.ClosedUnion . fromElmCanUnion <$> Binary.get
      2 -> ElmIfaceUnion . Interface.PrivateUnion . fromElmCanUnion <$> Binary.get
      _ -> fail "ElmIfaceUnion: corrupt tag"
  put (ElmIfaceUnion u) = Binary.put u

-- | Elm-era Interface.Alias decoder wrapping ElmCanAlias.
--
-- @since 0.19.1
newtype ElmIfaceAlias = ElmIfaceAlias { fromElmIfaceAlias :: Interface.Alias }

instance Binary ElmIfaceAlias where
  get = do
    tag <- Binary.getWord8
    case tag of
      0 -> ElmIfaceAlias . Interface.PublicAlias . fromElmCanAlias <$> Binary.get
      1 -> ElmIfaceAlias . Interface.PrivateAlias . fromElmCanAlias <$> Binary.get
      _ -> fail "ElmIfaceAlias: corrupt tag"
  put (ElmIfaceAlias a) = Binary.put a

-- | Elm-era Interface decoder (5 fields, no guards).
--
-- The current format has 6 fields with guards at the end.
-- Fills in an empty guards map for backward compatibility.
--
-- @since 0.19.1
newtype ElmInterface = ElmInterface { fromElmInterface :: Interface.Interface }

instance Binary ElmInterface where
  get = do
    home <- Binary.get
    values <- Binary.get
    rawUnions <- Binary.get
    rawAliases <- Binary.get
    binops <- Binary.get
    return (ElmInterface (Interface.Interface home values
      (Map.map fromElmIfaceUnion rawUnions)
      (Map.map fromElmIfaceAlias rawAliases)
      binops Map.empty Map.empty []))
  put (ElmInterface i) = Binary.put i

-- | Elm-era DependencyInterface decoder using ElmInterface.
--
-- @since 0.19.1
newtype ElmDependencyInterface = ElmDependencyInterface
  { fromElmDI :: Interface.DependencyInterface }

instance Binary ElmDependencyInterface where
  get = do
    tag <- Binary.getWord8
    case tag of
      0 -> ElmDependencyInterface . Interface.Public . fromElmInterface <$> Binary.get
      1 -> decodeElmPrivateDI
      _ -> fail "ElmDependencyInterface: corrupt tag"
  put (ElmDependencyInterface di) = Binary.put di

-- | Decode a Private DependencyInterface with Elm-era Union/Alias format.
decodeElmPrivateDI :: Get ElmDependencyInterface
decodeElmPrivateDI = do
  pkg <- Binary.get
  rawUnions <- Binary.get
  rawAliases <- Binary.get
  return (ElmDependencyInterface (Interface.Private pkg
    (Map.map fromElmCanUnion rawUnions)
    (Map.map fromElmCanAlias rawAliases)))

-- | Elm-era artifacts (old Binary format, no FFI info).
--
-- @since 0.19.1
data ElmFormatLegacyArtifacts = ElmFormatLegacyArtifacts
  !(Map ModuleName.Raw ElmDependencyInterface)
  !Opt.GlobalGraph

instance Binary ElmFormatLegacyArtifacts where
  get = Monad.liftM2 ElmFormatLegacyArtifacts Binary.get Binary.get
  put (ElmFormatLegacyArtifacts a b) = Binary.put a >> Binary.put b

-- | Elm-era artifact cache (old Binary format throughout).
--
-- @since 0.19.1
data ElmFormatArtifactCache = ElmFormatArtifactCache
  !(Set Fingerprint)
  !ElmFormatLegacyArtifacts

instance Binary ElmFormatArtifactCache where
  get = Monad.liftM2 ElmFormatArtifactCache Binary.get Binary.get
  put (ElmFormatArtifactCache a b) = Binary.put a >> Binary.put b

-- PRE-P06 CANOPY FORMAT DECODERS

-- | Pre-P06 Canopy Interface decoder (6 fields, no abilities or impls).
--
-- Canopy added @_ifaceAbilities@ and @_ifaceImpls@ to 'Interface.Interface'
-- in the P06 ability system (commit accd191). Artifacts built before that
-- change use this 6-field format: home, values, unions, aliases, binops,
-- guards. This decoder reads those 6 fields and fills in empty abilities
-- and impls for backward compatibility.
--
-- @since 0.19.2
newtype CanopyPreP06Interface = CanopyPreP06Interface
  { fromCanopyPreP06Interface :: Interface.Interface }

instance Binary CanopyPreP06Interface where
  get = do
    home <- Binary.get
    values <- Binary.get
    unions <- Binary.get
    aliases <- Binary.get
    binops <- Binary.get
    guards <- Binary.get
    return (CanopyPreP06Interface
      (Interface.Interface home values unions aliases binops guards Map.empty []))
  put (CanopyPreP06Interface i) = Binary.put i

-- | Pre-P06 Canopy DependencyInterface decoder.
--
-- Wraps 'CanopyPreP06Interface' for decoding 'Interface.DependencyInterface'
-- values stored in pre-P06 artifact caches.
--
-- @since 0.19.2
newtype CanopyPreP06DependencyInterface = CanopyPreP06DependencyInterface
  { fromCanopyPreP06DI :: Interface.DependencyInterface }

instance Binary CanopyPreP06DependencyInterface where
  get = do
    tag <- Binary.getWord8
    case tag of
      0 ->
        (CanopyPreP06DependencyInterface . Interface.Public . fromCanopyPreP06Interface)
          <$> Binary.get
      1 -> decodeCanopyPreP06PrivateDI
      _ -> fail "CanopyPreP06DependencyInterface: corrupt tag"
  put (CanopyPreP06DependencyInterface di) = Binary.put di

-- | Decode a pre-P06 Private DependencyInterface.
decodeCanopyPreP06PrivateDI :: Get CanopyPreP06DependencyInterface
decodeCanopyPreP06PrivateDI = do
  pkg <- Binary.get
  unions <- Binary.get
  aliases <- Binary.get
  return (CanopyPreP06DependencyInterface
    (Interface.Private pkg unions aliases))

-- | Pre-P06 Canopy artifacts (6-field Interface, no FFI info).
--
-- @since 0.19.2
data CanopyPreP06LegacyArtifacts = CanopyPreP06LegacyArtifacts
  !(Map ModuleName.Raw CanopyPreP06DependencyInterface)
  !Opt.GlobalGraph

instance Binary CanopyPreP06LegacyArtifacts where
  get = Monad.liftM2 CanopyPreP06LegacyArtifacts Binary.get Binary.get
  put (CanopyPreP06LegacyArtifacts a b) = Binary.put a >> Binary.put b

-- | Pre-P06 Canopy artifact cache (no FFI info, 6-field Interface).
--
-- @since 0.19.2
data CanopyPreP06LegacyArtifactCache = CanopyPreP06LegacyArtifactCache
  !(Set Fingerprint)
  !CanopyPreP06LegacyArtifacts

instance Binary CanopyPreP06LegacyArtifactCache where
  get = Monad.liftM2 CanopyPreP06LegacyArtifactCache Binary.get Binary.get
  put (CanopyPreP06LegacyArtifactCache a b) = Binary.put a >> Binary.put b

-- | Pre-P06 Canopy artifacts with FFI info (6-field Interface + FFI).
--
-- @since 0.19.2
data CanopyPreP06Artifacts = CanopyPreP06Artifacts
  !(Map ModuleName.Raw CanopyPreP06DependencyInterface)
  !Opt.GlobalGraph
  !(Map String JS.FFIInfo)

instance Binary CanopyPreP06Artifacts where
  get = Monad.liftM3 CanopyPreP06Artifacts Binary.get Binary.get Binary.get
  put (CanopyPreP06Artifacts a b c) = Binary.put a >> Binary.put b >> Binary.put c

-- | Pre-P06 Canopy artifact cache with FFI info.
--
-- @since 0.19.2
data CanopyPreP06ArtifactCache = CanopyPreP06ArtifactCache
  !(Set Fingerprint)
  !CanopyPreP06Artifacts

instance Binary CanopyPreP06ArtifactCache where
  get = Monad.liftM2 CanopyPreP06ArtifactCache Binary.get Binary.get
  put (CanopyPreP06ArtifactCache a b) = Binary.put a >> Binary.put b

-- VERSIONED ARTIFACT FORMAT

-- | Magic bytes identifying a versioned artifacts.dat file.
artifactMagic :: [Word8]
artifactMagic = [0x43, 0x41, 0x52, 0x54] -- "CART"

-- | Current schema version for the artifact format.
--
-- Version history:
--   1 — initial versioned format (fingerprints + artifacts)
--   2 — 'ArtifactCache' gained '_ffiFingerprints' for FFI file change detection
--
-- @since 0.19.3
artifactSchemaVersion :: Word16
artifactSchemaVersion = 2

-- | Encode artifacts with a versioned header.
encodeVersionedArtifacts :: ArtifactCache -> LBS.ByteString
encodeVersionedArtifacts cache =
  LBS.pack (fmap fromIntegral artifactMagic)
    <> Binary.encode artifactSchemaVersion
    <> Binary.encode (fromIntegral major :: Word16)
    <> Binary.encode (fromIntegral minor :: Word16)
    <> Binary.encode (fromIntegral patch :: Word16)
    <> Binary.encode cache
  where
    Version major minor patch = Version.compiler

-- | Try to decode a versioned artifacts.dat file.
decodeVersionedArtifacts :: LBS.ByteString -> Maybe ArtifactCache
decodeVersionedArtifacts bytes
  | LBS.length bytes < 12 = Nothing
  | not (magicMatches bytes) = Nothing
  | otherwise =
      let schemaVer = decodeWord16At 4 bytes
          compMajor = decodeWord16At 6 bytes
          compMinor = decodeWord16At 8 bytes
          compPatch = decodeWord16At 10 bytes
          Version major minor patch = Version.compiler
       in if schemaVer /= artifactSchemaVersion
            || compMajor /= fromIntegral major
            || compMinor /= fromIntegral minor
            || compPatch /= fromIntegral patch
            then Nothing
            else either (const Nothing) (\(_, _, v) -> Just v) (Binary.decodeOrFail (LBS.drop 12 bytes))
  where
    magicMatches bs =
      LBS.index bs 0 == 0x43
        && LBS.index bs 1 == 0x41
        && LBS.index bs 2 == 0x52
        && LBS.index bs 3 == 0x54
    decodeWord16At offset bs =
      fromIntegral (LBS.index bs offset) * 256
        + fromIntegral (LBS.index bs (offset + 1)) :: Word16

-- | Try decoding a versioned artifacts.dat file, extracting a value on success.
--
-- For the current versioned format (schema v2), also verifies FFI fingerprints
-- against the current files on disk.  Returns 'Nothing' when any FFI file has
-- changed since the artifact was compiled.
-- | Result type for versioned artifact loading that distinguishes
-- "not this format" from "format matched but FFI files changed".
data VersionedResult a
  = VersionedOk a
  | VersionedStaleFFI  -- ^ Format matched, but FFI fingerprints are stale
  | VersionedNotThisFormat

-- | Try to load a versioned artifact, returning a structured result.
tryVersionedAsResult :: (ArtifactCache -> b) -> FilePath -> IO (VersionedResult b)
tryVersionedAsResult extract path = do
  bytes <- LBS.readFile path
  case decodeVersionedArtifacts bytes of
    Nothing -> pure VersionedNotThisFormat
    Just cache -> do
      valid <- verifyFFIFingerprints pkgRoot cache
      if valid
        then pure (VersionedOk (extract cache))
        else pure VersionedStaleFFI
  where
    pkgRoot = takeDirectory path

-- | Load a versioned artifact with FFI fingerprint validation.
--
-- Returns 'Nothing' both when the format doesn't match AND when
-- fingerprints are stale.  Use 'tryVersionedAsResult' when the caller
-- needs to distinguish these cases.
tryVersionedAs :: (ArtifactCache -> b) -> FilePath -> IO (Maybe b)
tryVersionedAs extract path = do
  result <- tryVersionedAsResult extract path
  pure (versionedToMaybe result)

versionedToMaybe :: VersionedResult a -> Maybe a
versionedToMaybe (VersionedOk a) = Just a
versionedToMaybe _ = Nothing

-- | Verify that all stored FFI fingerprints still match the current files on disk.
--
-- The fingerprints are stored as paths relative to the package directory, so
-- the caller must supply the package root to resolve them.  Returns 'True'
-- when all stored fingerprints match or when there are no fingerprints
-- (i.e., the artifact was built from a package with no FFI).
verifyFFIFingerprints :: FilePath -> ArtifactCache -> IO Bool
verifyFFIFingerprints pkgRoot cache =
  Monad.foldM checkOne True (Map.toList (_ffiFingerprints cache))
  where
    checkOne False _ = pure False
    checkOne True (relPath, storedHash) = do
      let absPath = pkgRoot </> relPath
      exists <- Dir.doesFileExist absPath
      if not exists
        then pure (Hash.hashesEqual storedHash Hash.emptyHash)
        else do
          bytes <- BS.readFile absPath
          let currentHash = Hash.hashBytes bytes
          pure (Hash.hashesEqual currentHash storedHash)

-- | Map between canopy and elm package authors for fallback lookups.
--
-- When looking up @canopy\/core@, also try @elm\/core@ on disk since the
-- package cache may still be stored under the legacy @elm@ author.
-- Conversely, @elm\/core@ lookups also try @canopy\/core@.
--
-- @since 0.19.1
fallbackAuthor :: String -> Maybe String
fallbackAuthor "canopy" = Just "elm"
fallbackAuthor "canopy-explorations" = Just "elm-explorations"
fallbackAuthor "elm" = Just "canopy"
fallbackAuthor "elm-explorations" = Just "canopy-explorations"
fallbackAuthor _ = Nothing

-- | Build the search paths for loading package artifacts.
--
-- Returns paths in priority order:
--
-- 1. @~\/.canopy\/packages\/{author}\/{package}\/{version}\/artifacts.dat@
-- 2. @~\/.canopy\/packages\/{fallback-author}\/{package}\/{version}\/artifacts.dat@ (if author has a fallback mapping)
-- 3. @~\/.elm\/0.19.1\/packages\/{author}\/{package}\/{version}\/artifacts.dat@
--
-- @since 0.19.1
packageArtifactPaths :: FilePath -> String -> String -> String -> [FilePath]
packageArtifactPaths homeDir author package version =
  [homeDir </> ".canopy" </> "packages" </> author </> package </> version </> "artifacts.dat"]
  ++ maybe [] (\mapped -> [homeDir </> ".canopy" </> "packages" </> mapped </> package </> version </> "artifacts.dat"]) (fallbackAuthor author)
  ++ [homeDir </> ".elm" </> "0.19.1" </> "packages" </> author </> package </> version </> "artifacts.dat"]
  ++ maybe [] (\mapped -> [homeDir </> ".elm" </> "0.19.1" </> "packages" </> mapped </> package </> version </> "artifacts.dat"]) (fallbackAuthor author)

-- | Try loading from a list of paths, returning the first successful result.
--
-- @since 0.19.1
tryLoadFirst :: (FilePath -> IO (Maybe a)) -> [FilePath] -> IO (Maybe a)
tryLoadFirst _ [] = return Nothing
tryLoadFirst loader (path : rest) = do
  exists <- Dir.doesFileExist path
  if exists
    then loader path >>= maybe (tryLoadFirst loader rest) (return . Just)
    else tryLoadFirst loader rest

-- | Load package interfaces from artifact cache.
--
-- Attempts to load compiled interfaces for a specific package version
-- from the package cache. Returns Nothing if the package isn't installed
-- or doesn't have cached artifacts.
--
-- >>> interfaces <- loadPackageInterfaces "elm" "core" "1.0.5"
--
-- ==== Search Order
--
-- 1. @~/.canopy/packages/author/package/version/artifacts.dat@
-- 2. @~/.canopy/packages/canopy/package/version/artifacts.dat@ (if author is @elm@)
-- 3. @~/.elm/0.19.1/packages/author/package/version/artifacts.dat@
--
-- @since 0.19.1
loadPackageInterfaces ::
  -- | Package author
  String ->
  -- | Package name
  String ->
  -- | Package version
  String ->
  IO (Maybe PackageInterfaces)
loadPackageInterfaces author package version = do
  homeDir <- Dir.getHomeDirectory
  exactResult <- tryLoadFirst loadArtifactsFile (packageArtifactPaths homeDir author package version)
  case exactResult of
    Just ifaces -> return (Just ifaces)
    Nothing -> scanForCompatibleVersion homeDir author package

-- | Scan installed versions when the exact version is not found.
--
-- When a package constraint resolves to a lower-bound version that
-- isn't installed, this function scans available versions in the
-- @~\/.canopy\/packages\/@ and @~\/.elm\/0.19.1\/packages\/@ directories,
-- returning the first version with a valid @artifacts.dat@.
--
-- @since 0.19.1
scanForCompatibleVersion :: FilePath -> String -> String -> IO (Maybe PackageInterfaces)
scanForCompatibleVersion = scanForCompatibleVersionWith loadArtifactsFile

-- | Scan installed versions using a custom loader function.
--
-- Generalized version of 'scanForCompatibleVersion' that works with any
-- artifact loader (interfaces-only or complete artifacts).
--
-- Searches both @~\/.canopy\/packages\/@ and @~\/.elm\/0.19.1\/packages\/@
-- for each author (including fallback author mappings), returning the first
-- version that can be successfully decoded.
--
-- @since 0.19.1
scanForCompatibleVersionWith :: (FilePath -> IO (Maybe a)) -> FilePath -> String -> String -> IO (Maybe a)
scanForCompatibleVersionWith loader homeDir author package =
  tryDirs searchDirs
  where
    authors = author : maybe [] (: []) (fallbackAuthor author)
    searchDirs =
      [ homeDir </> ".canopy" </> "packages" </> a </> package | a <- authors ]
      ++ [ homeDir </> ".elm" </> "0.19.1" </> "packages" </> a </> package | a <- authors ]
    tryDirs [] = return Nothing
    tryDirs (pkgDir : rest) = do
      exists <- Dir.doesDirectoryExist pkgDir
      if not exists
        then tryDirs rest
        else do
          versions <- Dir.listDirectory pkgDir
          result <- tryLoadFirst loader [pkgDir </> v </> "artifacts.dat" | v <- versions]
          maybe (tryDirs rest) (return . Just) result

-- | Try a list of IO actions returning Maybe, stopping at the first Just.
tryDecoders :: [IO (Maybe a)] -> IO (Maybe a)
tryDecoders [] = return Nothing
tryDecoders (action : rest) =
  action >>= maybe (tryDecoders rest) (return . Just)

-- | Try decoding a binary file, extracting a value on success.
tryDecodeAs :: Binary a => (a -> b) -> FilePath -> IO (Maybe b)
tryDecodeAs extract path =
  fmap (either (const Nothing) (Just . extract)) (Binary.decodeFileOrFail path)

-- | Load artifacts from a specific file path.
--
-- Tries formats in priority order:
--
-- 1. New Canopy format (with FFI info and 8-field Interface)
-- 2. Legacy Canopy format (no FFI info, 8-field Interface)
-- 3. Pre-P06 Canopy format (with FFI info, 6-field Interface — no abilities/impls)
-- 4. Pre-P06 Canopy legacy format (no FFI info, 6-field Interface)
-- 5. Elm-era format (no FFI info, old 4-field Union, 2-field Alias, 5-field Interface)
loadArtifactsFile :: FilePath -> IO (Maybe PackageInterfaces)
loadArtifactsFile path =
  tryDecoders
    [ tryVersionedAs (\(ArtifactCache _ arts _) -> _ifaces arts) path
    , tryDecodeAs (\(ArtifactCache _ arts _) -> _ifaces arts) path
    , tryDecodeAs (\(LegacyArtifactCache _ (LegacyArtifacts ifaces _)) -> ifaces) path
    , tryDecodeAs
        (\(CanopyPreP06ArtifactCache _ (CanopyPreP06Artifacts rawDIs _ _)) ->
          Map.map fromCanopyPreP06DI rawDIs)
        path
    , tryDecodeAs
        (\(CanopyPreP06LegacyArtifactCache _ (CanopyPreP06LegacyArtifacts rawDIs _)) ->
          Map.map fromCanopyPreP06DI rawDIs)
        path
    , tryDecodeAs
        (\(ElmFormatArtifactCache _ (ElmFormatLegacyArtifacts rawDIs _)) ->
          Map.map fromElmDI rawDIs)
        path
    ]

-- | Load complete artifacts (interfaces + objects + FFI info) from a specific file path.
--
-- Tries formats in priority order, filling in empty fields for older formats.
loadCompleteArtifactsFile :: FilePath -> IO (Maybe PackageArtifacts)
loadCompleteArtifactsFile path =
  tryDecoders
    [ tryVersionedAs
        (\(ArtifactCache _ arts _) ->
          PackageArtifacts (_ifaces arts) (_objects arts) (_ffiInfo arts))
        path
    , tryDecodeAs
        (\(ArtifactCache _ arts _) ->
          PackageArtifacts (_ifaces arts) (_objects arts) (_ffiInfo arts))
        path
    , tryDecodeAs
        (\(LegacyArtifactCache _ (LegacyArtifacts ifaces objs)) ->
          PackageArtifacts ifaces objs Map.empty)
        path
    , tryDecodeAs
        (\(CanopyPreP06ArtifactCache _ (CanopyPreP06Artifacts rawDIs objs ffi)) ->
          PackageArtifacts (Map.map fromCanopyPreP06DI rawDIs) objs ffi)
        path
    , tryDecodeAs
        (\(CanopyPreP06LegacyArtifactCache _ (CanopyPreP06LegacyArtifacts rawDIs objs)) ->
          PackageArtifacts (Map.map fromCanopyPreP06DI rawDIs) objs Map.empty)
        path
    , tryDecodeAs
        (\(ElmFormatArtifactCache _ (ElmFormatLegacyArtifacts rawDIs objs)) ->
          PackageArtifacts (Map.map fromElmDI rawDIs) objs Map.empty)
        path
    ]

-- | Load core package interfaces.
--
-- Convenience function to load the core package interfaces (looks up
-- as @elm\/core@ on disk for backward compatibility with existing caches).
-- This package contains Basics, List, Maybe, Result, String, etc.
-- Returns 'Nothing' when the package is not installed or its
-- artifact cache is missing.
--
-- @since 0.19.1
loadElmCoreInterfaces :: IO (Maybe PackageInterfaces)
loadElmCoreInterfaces =
  loadPackageInterfaces "elm" "core" "1.0.5"

-- | Load all dependency interfaces for a project.
--
-- Given a list of package dependencies, loads and merges all their
-- interfaces into a single map. Useful for setting up compilation
-- environment with all dependencies available.
--
-- Uses parallel I/O for significant performance improvement.
--
-- >>> let deps = [(Pkg.Name "elm" "core", Version.Version 1 0 5)]
-- >>> allInterfaces <- loadAllDependencyInterfaces deps
--
-- ==== Behavior
--
-- * Missing packages are silently skipped
-- * Later packages override earlier ones if they have conflicting modules
-- * Returns empty map if no packages can be loaded
-- * Loads packages in parallel for 10-20x speedup
--
-- @since 0.19.1
loadAllDependencyInterfaces ::
  -- | List of (package, version) pairs
  [(Pkg.Name, Version.Version)] ->
  IO PackageInterfaces
loadAllDependencyInterfaces deps = do
  -- Load in parallel using async
  interfaceLists <- mapConcurrently loadDep deps
  return (Map.unions (concat interfaceLists))
  where
    loadDep (Pkg.Name author project, Version.Version major minor patch) = do
      let authorStr = Utf8.toChars author
          projectStr = Utf8.toChars project
          versionStr = show major ++ "." ++ show minor ++ "." ++ show patch
      maybeIfaces <- loadPackageInterfaces authorStr projectStr versionStr
      return (maybe [] (: []) maybeIfaces)

-- | Load complete package artifacts (interfaces + objects).
--
-- Similar to loadPackageInterfaces but returns both type interfaces
-- and optimized GlobalGraph objects needed for code generation.
--
-- @since 0.19.1
loadPackageArtifacts ::
  -- | Package author
  String ->
  -- | Package name
  String ->
  -- | Package version
  String ->
  IO (Maybe PackageArtifacts)
loadPackageArtifacts author package version = do
  homeDir <- Dir.getHomeDirectory
  exactResult <- tryLoadFirst loadCompleteArtifactsFile (packageArtifactPaths homeDir author package version)
  case exactResult of
    Just arts -> return (Just arts)
    Nothing -> scanForCompatibleVersionWith loadCompleteArtifactsFile homeDir author package

-- | Load all package artifacts for multiple packages.
--
-- Returns both interfaces and GlobalGraph objects for all requested packages.
-- Merges GlobalGraphs from all packages into a single GlobalGraph.
--
-- Uses parallel I/O for significant performance improvement when loading
-- many packages. Typical speedup: 10-20x for 40+ packages.
--
-- @since 0.19.1
loadAllPackageArtifacts ::
  -- | List of (package, version) pairs
  [(Pkg.Name, Version.Version)] ->
  IO (Maybe PackageArtifacts)
loadAllPackageArtifacts deps = do
  -- Load packages in parallel using async - major performance improvement
  artifactsList <- mapConcurrently loadDep deps
  let validArtifacts = concat artifactsList
  if null validArtifacts
    then return Nothing
    else return (Just (mergeArtifacts validArtifacts))
  where
    loadDep (Pkg.Name author project, Version.Version major minor patch) = do
      let authorStr = Utf8.toChars author
          projectStr = Utf8.toChars project
          versionStr = show major ++ "." ++ show minor ++ "." ++ show patch
      -- Load with error handling - skip packages that fail
      maybeArtifacts <- loadPackageArtifacts authorStr projectStr versionStr
      case maybeArtifacts of
        Just artifacts -> return [artifacts]
        Nothing -> return []  -- Silently skip packages that fail to load

    mergeArtifacts :: [PackageArtifacts] -> PackageArtifacts
    mergeArtifacts artifacts =
      PackageArtifacts
        { artifactInterfaces = Map.unions (map artifactInterfaces artifacts)
        , artifactObjects = mergeGlobalGraphs (map artifactObjects artifacts)
        , artifactFFIInfo = Map.unions (map artifactFFIInfo artifacts)
        }

    mergeGlobalGraphs :: [Opt.GlobalGraph] -> Opt.GlobalGraph
    mergeGlobalGraphs graphs =
      let allGraphs = map (\(Opt.GlobalGraph g _ _) -> g) graphs
          allFields = map (\(Opt.GlobalGraph _ f _) -> f) graphs
          allLocs = map (\(Opt.GlobalGraph _ _ l) -> l) graphs
      in Opt.GlobalGraph (Map.unions allGraphs) (Map.unionsWith (+) allFields) (Map.unions allLocs)

-- | Load a single module interface from JSON or binary format.
--
-- This function provides granular interface loading for IDEs and tools
-- that need quick access to specific module interfaces without loading
-- the entire package artifacts.
--
-- Attempts to read JSON format first (faster parsing), falling back to
-- binary .cani if JSON is not available.
--
-- >>> interface <- loadModuleInterface "project-root" "Main"
-- >>> case interface of
-- ...   Right iface -> -- Use the interface for type checking
-- ...   Left err -> -- Handle error
--
-- @since 0.19.1
loadModuleInterface ::
  FilePath ->
  -- ^ Project root directory
  String ->
  -- ^ Module name (e.g., "Main", "Utils")
  IO (Either String Interface.Interface)
loadModuleInterface root moduleName = do
  let interfaceDir = root </> "canopy-stuff" </> "0.19.1" </> "i.cani"
      basePath = interfaceDir </> moduleName

  -- Try JSON first, fall back to binary
  IFace.readInterface basePath

-- | Load package artifacts specifically from the old Elm cache.
--
-- Used to supplement source-compiled artifacts with kernel module globals
-- that are only available in the original Elm-compiled artifacts. Kernel
-- modules (e.g., @Elm.Kernel.Debug@, @Elm.Kernel.Json@) are JavaScript-only
-- implementations not present in source compilations.
--
-- @since 0.19.1
_loadOldElmArtifacts ::
  -- | Package author
  String ->
  -- | Package name
  String ->
  -- | Package version
  String ->
  IO (Maybe PackageArtifacts)
_loadOldElmArtifacts author package version = do
  homeDir <- Dir.getHomeDirectory
  tryLoadFirst loadCompleteArtifactsFile
    [ homeDir </> ".elm" </> "0.19.1" </> "packages" </> a </> package </> version </> "artifacts.dat"
    | a <- author : maybe [] (:[]) (fallbackAuthor author)
    ]

-- | Get the path where a package's artifacts.dat should be stored.
--
-- Returns the path at @~/.canopy/packages/{author}/{project}/{version}/artifacts.dat@
--
-- @since 0.19.1
getPackageArtifactPath ::
  -- | Package author
  String ->
  -- | Package name
  String ->
  -- | Package version
  String ->
  IO FilePath
getPackageArtifactPath author package version = do
  homeDir <- Dir.getHomeDirectory
  return (homeDir </> ".canopy" </> "packages" </> author </> package </> version </> "artifacts.dat")

-- | Write package artifacts to the cache.
--
-- Serializes the given interfaces, GlobalGraph, and FFI info into an
-- @artifacts.dat@ file at the appropriate cache location for the
-- specified package.
--
-- This is used by the setup command to compile local packages and cache
-- their artifacts for faster subsequent loads.
--
-- >>> writePackageArtifacts "canopy" "test" "1.0.0" interfaces globalGraph ffiInfo
--
-- @since 0.19.1
writePackageArtifacts ::
  -- | Package author
  String ->
  -- | Package name
  String ->
  -- | Package version
  String ->
  -- | Compiled module interfaces
  PackageInterfaces ->
  -- | Optimized global graph
  Opt.GlobalGraph ->
  -- | FFI info from foreign import declarations
  Map String JS.FFIInfo ->
  IO ()
writePackageArtifacts author package version interfaces globalGraph ffiInfo = do
  artifactPath <- getPackageArtifactPath author package version
  let pkgRoot = takeDirectory artifactPath
  Dir.createDirectoryIfMissing True pkgRoot
  ffiFingerprints <- buildFFIFingerprints pkgRoot ffiInfo
  let artifacts = Artifacts interfaces globalGraph ffiInfo
      cache = ArtifactCache Set.empty artifacts ffiFingerprints
  LBS.writeFile artifactPath (encodeVersionedArtifacts cache)

-- | Build a map of FFI file path to current content hash.
--
-- The paths in 'JS.FFIInfo' are relative to the package root, so
-- @pkgRoot@ is used to resolve them on disk.  The map keys remain
-- relative so they can be verified later from any working directory.
--
-- @since 0.19.3
buildFFIFingerprints :: FilePath -> Map String JS.FFIInfo -> IO (Map FilePath Hash.ContentHash)
buildFFIFingerprints pkgRoot ffiInfo = do
  pairs <- traverse (hashFFIPath pkgRoot) (Map.keys ffiInfo)
  pure (Map.fromList pairs)

-- | Hash a single FFI file path and return (relative path, hash) pair.
hashFFIPath :: FilePath -> FilePath -> IO (FilePath, Hash.ContentHash)
hashFFIPath pkgRoot relPath = do
  let absPath = pkgRoot </> relPath
  exists <- Dir.doesFileExist absPath
  if exists
    then do
      bytes <- BS.readFile absPath
      pure (relPath, Hash.hashBytes bytes)
    else pure (relPath, Hash.emptyHash)

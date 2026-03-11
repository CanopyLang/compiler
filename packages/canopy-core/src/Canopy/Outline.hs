{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Pure project outline (canopy.json) for Terminal.
--
-- Handles reading and writing canopy.json configuration files.
--
-- The orphan JSON instances for 'Constraint.Constraint' and
-- 'Licenses.License' live here because 'Canopy.Outline' owns the
-- JSON schema definition for @canopy.json@. Moving them to the source
-- modules would create a dependency on @aeson@ in @canopy-core@.
--
-- @since 0.19.1
module Canopy.Outline
  ( -- * Outline Types
    Outline (..),
    AppOutline (..),
    PkgOutline (..),
    WorkspaceOutline (..),
    Exposed (..),
    SrcDir (..),
    CapabilityConfig (..),
    KitConfig (..),

    -- * Reading/Writing
    read,
    write,

    -- * Encoding
    encode,

    -- * Utilities
    flattenExposed,
    allDeps,
    isWorkspace,
    isKitProject,
    effectiveCapabilities,

    -- * Defaults
    defaultSummary,
    emptyCapabilities,
    defaultKitConfig,
  )
where

import qualified Canopy.Constraint as Constraint
import qualified Canopy.Licenses as Licenses
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Applicative ((<|>))
import Data.Aeson ((.!=), (.=), (.:?))
import Data.Aeson.Types (Parser)
import qualified Data.Aeson as Json
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Json.String as JsonStr
import Json.Encode ((==>))
import qualified Json.Encode as Encode
import Prelude hiding (read)
import qualified System.Directory
import System.FilePath ((</>))
import qualified Canopy.Limits as Limits

-- | Serialize a constraint as its full range string (e.g. @"1.0.0 <= v < 2.0.0"@).
--
-- This preserves the exact constraint during round-trips through canopy.json.
-- The previous implementation destroyed data by always serializing as @"any"@.
instance Json.ToJSON Constraint.Constraint where
  toJSON c = Json.String (Text.pack (Constraint.toChars c))

-- | Parse a constraint from either a range string or a bare version.
--
-- Accepts both @"1.0.0 <= v < 2.0.0"@ (range format from 'Constraint.toChars')
-- and @"1.0.0"@ (exact version, for backward compatibility with simple specs).
-- Fails with a parse error on invalid input instead of silently falling back
-- to 'Constraint.anything'.
instance Json.FromJSON Constraint.Constraint where
  parseJSON = Json.withText "Constraint" $ \txt ->
    parseConstraintRange txt
      <|> fmap Constraint.exactly (versionFromText txt)

-- | Attempt to parse a full range constraint like @"1.0.0 <= v < 2.0.0"@.
parseConstraintRange :: Text.Text -> Parser Constraint.Constraint
parseConstraintRange txt =
  case parseRangeText (Text.unpack txt) of
    Just c -> pure c
    Nothing -> fail ("Not a valid constraint range: " ++ Text.unpack txt)

-- | Parse a range string by splitting on @" v "@ and extracting bounds.
--
-- Expected format: @"<lower> <op1> v <op2> <upper>"@ where ops are @"<"@ or @"<="@.
parseRangeText :: String -> Maybe Constraint.Constraint
parseRangeText s =
  case words s of
    [lo, op1, "v", op2, hi] -> buildRange lo op1 op2 hi
    _ -> Nothing
  where
    buildRange lo op1 op2 hi = do
      lower <- Version.fromChars lo
      upper <- Version.fromChars hi
      lowerOp <- parseOp op1
      upperOp <- parseOp op2
      pure (buildConstraint lower lowerOp upperOp upper)

    parseOp "<" = Just False
    parseOp "<=" = Just True
    parseOp _ = Nothing

    buildConstraint lower lowerLe upperLe upper =
      Constraint.fromRange lower lowerLe upperLe upper

-- | Parse a version string via the Aeson instance for 'Version.Version'.
versionFromText :: Text.Text -> Parser Version.Version
versionFromText txt =
  case Json.fromJSON (Json.String txt) of
    Json.Success v -> pure v
    Json.Error _ -> fail "not a version"

-- | Serialize a license as its SPDX identifier string.
--
-- This preserves the actual license during round-trips through canopy.json.
-- The previous implementation destroyed data by always serializing as @"BSD-3-Clause"@.
instance Json.ToJSON Licenses.License where
  toJSON license = Json.String (Text.pack (Licenses.toChars license))

-- | Parse a license from its SPDX identifier string.
--
-- Validates against the OSI-approved SPDX license list. Rejects
-- invalid identifiers with a parse error.
instance Json.FromJSON Licenses.License where
  parseJSON = Json.withText "License" $ \txt ->
    case Licenses.check (JsonStr.fromChars (Text.unpack txt)) of
      Right license -> pure license
      Left _ -> fail ("Invalid SPDX license identifier: " ++ Text.unpack txt)

-- | Project outline (App, Pkg, or Workspace).
data Outline
  = App AppOutline
  | Pkg PkgOutline
  | Workspace WorkspaceOutline
  deriving (Show)

-- | Capability configuration with allow and deny lists.
--
-- The allow list specifies which capabilities the application may use.
-- The deny list explicitly forbids capabilities, taking precedence over allow.
-- This enables defense-in-depth: even if a dependency declares a capability,
-- the deny list can block it at the application level.
--
-- @since 0.19.2
data CapabilityConfig = CapabilityConfig
  { _capAllow :: !(Set Text.Text),
    _capDeny :: !(Set Text.Text)
  }
  deriving (Eq, Show)

-- | Empty capability configuration (no allow, no deny).
--
-- @since 0.19.2
emptyCapabilities :: CapabilityConfig
emptyCapabilities = CapabilityConfig Set.empty Set.empty

-- | Compute effective capabilities: allow minus deny.
--
-- @since 0.19.2
effectiveCapabilities :: CapabilityConfig -> Set Text.Text
effectiveCapabilities config =
  Set.difference (_capAllow config) (_capDeny config)

-- | CanopyKit configuration for file-based routing applications.
--
-- When present in an 'AppOutline', enables CanopyKit features including
-- file-based routing, layout resolution, and static site generation.
-- The routes directory is scanned for @page.can@, @layout.can@, and
-- @error.can@ files to build the route manifest.
--
-- @since 0.19.2
data KitConfig = KitConfig
  { _kitRoutesDir :: !FilePath
  }
  deriving (Eq, Show)

-- | Default kit configuration with @src/routes@ as the routes directory.
--
-- @since 0.19.2
defaultKitConfig :: KitConfig
defaultKitConfig = KitConfig "src/routes"

-- | Application outline.
--
-- The optional '_appScripts' field maps script names to shell commands,
-- enabling custom build hooks (prebuild, postbuild, test, etc.).
-- The optional '_appRepository' field records the project's source
-- repository URL for package metadata.
-- The '_appCapabilities' field declares which browser capabilities
-- (permissions, APIs) the application is allowed or denied through FFI.
-- The optional '_appKit' field enables CanopyKit meta-framework features
-- including file-based routing and static site generation.
--
-- @since 0.19.2
data AppOutline = AppOutline
  { _appCanopy :: !Version.Version,
    _appSrcDirs :: ![SrcDir],
    _appDeps :: !(Map Pkg.Name Constraint.Constraint),
    _appTestDeps :: !(Map Pkg.Name Constraint.Constraint),
    _appDepsDirect :: !(Map Pkg.Name Version.Version),
    _appDepsIndirect :: !(Map Pkg.Name Version.Version),
    _appTestDepsDirect :: !(Map Pkg.Name Version.Version),
    _appScripts :: !(Maybe (Map Text.Text Text.Text)),
    _appRepository :: !(Maybe Text.Text),
    _appCapabilities :: !CapabilityConfig,
    _appWebComponents :: !(Maybe [ModuleName.Raw]),
    _appKit :: !(Maybe KitConfig)
  }
  deriving (Show)

-- | Package outline.
data PkgOutline = PkgOutline
  { _pkgName :: !Pkg.Name,
    _pkgSummary :: !Text.Text,
    _pkgLicense :: !Licenses.License,
    _pkgVersion :: !Version.Version,
    _pkgExposed :: !Exposed,
    _pkgDeps :: !(Map Pkg.Name Constraint.Constraint),
    _pkgTestDeps :: !(Map Pkg.Name Constraint.Constraint),
    _pkgCanopy :: !Constraint.Constraint
  }
  deriving (Show)

-- | Workspace outline for monorepo support.
--
-- A workspace groups multiple Canopy packages (or applications) under a
-- single root directory.  The workspace @canopy.json@ lists the relative
-- paths to member packages and optionally declares shared dependency
-- constraints that every member inherits.
--
-- @since 0.19.2
data WorkspaceOutline = WorkspaceOutline
  { _wsPackages :: ![FilePath],
    _wsSharedDeps :: !(Map Pkg.Name Version.Version),
    _wsCanopy :: !Version.Version
  }
  deriving (Show, Eq)

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
--
-- Checks for canopy.json first, then elm.json as fallback.
-- Returns a detailed error when a file is present but malformed,
-- rather than silently returning 'Nothing'.
--
-- @since 0.19.1
read :: FilePath -> IO (Either String Outline)
read root = do
  let canopyPath = root </> "canopy.json"
      elmPath = root </> "elm.json"
  maybeCanopy <- safeReadFile canopyPath
  case maybeCanopy of
    Just content ->
      pure (either (Left . decorateError canopyPath) Right (Json.eitherDecode content))
    Nothing -> do
      maybeElm <- safeReadFile elmPath
      case maybeElm of
        Nothing -> pure (Left ("No canopy.json or elm.json found in " ++ root))
        Just content ->
          pure (either (Left . decorateError elmPath) Right (Json.eitherDecode content))
  where
    decorateError path msg = "Failed to parse " ++ path ++ ": " ++ msg

-- | Write outline to project root.
write :: FilePath -> Outline -> IO ()
write root outline = do
  let path = root </> "canopy.json"
      content = Json.encode outline
  LBS.writeFile path content

-- | Default package summary.
defaultSummary :: Text.Text
defaultSummary = "A Canopy project"

-- | Safe file reading with size limit.
--
-- Returns 'Nothing' if the file does not exist. Returns the content
-- wrapped in 'Just' if it exists and is within the outline size limit.
-- Throws an 'IOError' if the file exceeds 'Limits.maxOutlineBytes',
-- preventing out-of-memory conditions from corrupted config files.
--
-- @since 0.19.2
safeReadFile :: FilePath -> IO (Maybe LBS.ByteString)
safeReadFile path = do
  exists <- System.Directory.doesFileExist path
  if exists
    then do
      size <- System.Directory.getFileSize path
      enforceOutlineLimit path (fromIntegral size)
      Just <$> LBS.readFile path
    else pure Nothing

-- | Enforce the outline file size limit.
--
-- @since 0.19.2
enforceOutlineLimit :: FilePath -> Int -> IO ()
enforceOutlineLimit path size =
  case Limits.checkFileSize path size Limits.maxOutlineBytes of
    Nothing -> pure ()
    Just (Limits.FileSizeError fp actual limit) ->
      ioError (userError (outlineTooLargeMessage fp actual limit))

-- | Format a file-too-large error message for outline files.
--
-- @since 0.19.2
outlineTooLargeMessage :: FilePath -> Int -> Int -> String
outlineTooLargeMessage path actual limit =
  "FILE TOO LARGE -- " ++ path ++ "\n\n"
    ++ "    This configuration file is " ++ showMB actual
    ++ ", which exceeds the " ++ showMB limit ++ " limit.\n\n"
    ++ "    A valid canopy.json should be much smaller. Check if this\n"
    ++ "    file has been corrupted or accidentally overwritten.\n"
  where
    showMB bytes = show (bytes `div` (1024 * 1024)) ++ " MB"

-- JSON instances (minimal)
instance Json.ToJSON Outline where
  toJSON (App appOutline) = Json.toJSON appOutline
  toJSON (Pkg pkgOutline) = Json.toJSON pkgOutline
  toJSON (Workspace wsOutline) = Json.toJSON wsOutline

instance Json.FromJSON Outline where
  parseJSON value =
    (Workspace <$> Json.parseJSON value)
      <|> (App <$> Json.parseJSON value)
      <|> (Pkg <$> Json.parseJSON value)

instance Json.ToJSON KitConfig where
  toJSON kit =
    Json.object ["routes-dir" .= _kitRoutesDir kit]

instance Json.FromJSON KitConfig where
  parseJSON = Json.withObject "KitConfig" $ \o ->
    KitConfig <$> (o .:? "routes-dir" .!= "src/routes")

instance Json.ToJSON AppOutline where
  toJSON app =
    Json.object (requiredFields ++ optionalFields)
    where
      requiredFields =
        [ "type" .= ("application" :: Text.Text),
          "canopy-version" .= _appCanopy app,
          "source-directories" .= _appSrcDirs app,
          "dependencies" .= _appDeps app,
          "test-dependencies" .= _appTestDeps app,
          "dependencies-direct" .= _appDepsDirect app,
          "dependencies-indirect" .= _appDepsIndirect app,
          "test-dependencies-direct" .= _appTestDepsDirect app
        ]
      optionalFields =
        maybe [] (\s -> ["scripts" .= s]) (_appScripts app)
          ++ maybe [] (\r -> ["repository" .= r]) (_appRepository app)
          ++ capabilitiesField
          ++ maybe [] (\wc -> ["web-components" .= wc]) (_appWebComponents app)
          ++ maybe [] (\k -> ["kit" .= k]) (_appKit app)
      capabilitiesField
        | _appCapabilities app == emptyCapabilities = []
        | Set.null (_capDeny (_appCapabilities app)) =
            ["capabilities" .= Set.toList (_capAllow (_appCapabilities app))]
        | otherwise =
            ["capabilities" .= _appCapabilities app]

instance Json.FromJSON AppOutline where
  parseJSON = Json.withObject "AppOutline" $ \o -> do
    canopyVer <- (o Json..: "canopy-version") <|> (o Json..: "elm-version")
    srcDirs <- o Json..: "source-directories"
    deps <- o Json..: "dependencies"
    depsDirect <- deps Json..: "direct"
    depsIndirect <- deps Json..: "indirect"
    testDeps <- o Json..: "test-dependencies"
    testDepsDirect <- testDeps Json..: "direct"
    scripts <- o .:? "scripts"
    repository <- o .:? "repository"
    capabilities <- parseCapabilities o
    webComponents <- o .:? "web-components"
    kit <- o .:? "kit"
    pure
      AppOutline
        { _appCanopy = canopyVer,
          _appSrcDirs = srcDirs,
          _appDeps = Map.empty,
          _appTestDeps = Map.empty,
          _appDepsDirect = depsDirect,
          _appDepsIndirect = depsIndirect,
          _appTestDepsDirect = testDepsDirect,
          _appScripts = scripts,
          _appRepository = repository,
          _appCapabilities = capabilities,
          _appWebComponents = webComponents,
          _appKit = kit
        }

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

instance Json.ToJSON WorkspaceOutline where
  toJSON (WorkspaceOutline packages sharedDeps canopy) =
    Json.object
      [ "type" .= ("workspace" :: Text.Text),
        "packages" .= packages,
        "shared-dependencies" .= sharedDeps,
        "canopy-version" .= canopy
      ]

instance Json.FromJSON WorkspaceOutline where
  parseJSON = Json.withObject "WorkspaceOutline" $ \o -> do
    typeField <- o Json..: "type"
    if (typeField :: Text.Text) /= "workspace"
      then fail "Not a workspace outline"
      else do
        canopyVer <- (o Json..: "canopy-version") <|> (o Json..: "elm-version")
        packages <- o Json..: "packages"
        sharedDeps <- o .:? "shared-dependencies" .!= Map.empty
        pure (WorkspaceOutline packages sharedDeps canopyVer)

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

-- | Parse capabilities from canopy.json, supporting both formats.
--
-- Old format: @"capabilities": ["network", "storage"]@ → allow-only
-- New format: @"capabilities": {"allow": [...], "deny": [...]}@ → full config
--
-- @since 0.19.2
parseCapabilities :: Json.Object -> Parser CapabilityConfig
parseCapabilities o = do
  maybeCaps <- o .:? "capabilities"
  case maybeCaps of
    Nothing -> pure emptyCapabilities
    Just val -> parseCapabilityValue val

-- | Parse a capability value (either a list or an object).
parseCapabilityValue :: Json.Value -> Parser CapabilityConfig
parseCapabilityValue val =
  parseAsList val <|> parseAsObject val
  where
    parseAsList v = do
      capsList <- Json.parseJSON v :: Parser [Text.Text]
      pure (CapabilityConfig (Set.fromList capsList) Set.empty)
    parseAsObject v = Json.withObject "CapabilityConfig" parseFields v
    parseFields obj = do
      allow <- obj .:? "allow" .!= []
      deny <- obj .:? "deny" .!= []
      pure (CapabilityConfig (Set.fromList allow) (Set.fromList deny))

instance Json.ToJSON CapabilityConfig where
  toJSON config
    | Set.null (_capDeny config) = Json.toJSON (Set.toList (_capAllow config))
    | otherwise =
        Json.object
          [ "allow" .= Set.toList (_capAllow config),
            "deny" .= Set.toList (_capDeny config)
          ]

instance Json.FromJSON CapabilityConfig where
  parseJSON = parseCapabilityValue

-- | Encode outline for Json.Encode (used by development server).
--
-- Converts Outline to Json.Encode.Value for serialization.
-- Used primarily by the development server's index generation.
--
-- @since 0.19.1
encode :: Outline -> Encode.Value
encode (App appOutline) = encodeAppOutline appOutline
encode (Pkg pkgOutline) = encodePkgOutline pkgOutline
encode (Workspace wsOutline) = encodeWorkspaceOutline wsOutline

-- | Encode application outline.
encodeAppOutline :: AppOutline -> Encode.Value
encodeAppOutline app =
  Encode.object (requiredFields ++ capsField ++ kitField)
  where
    requiredFields =
      [ "type" ==> Encode.chars "application",
        "canopy-version" ==> Version.encode (_appCanopy app),
        "source-directories" ==> Encode.list encodeSrcDir (_appSrcDirs app),
        "dependencies" ==> Encode.dict Pkg.toJsonString Constraint.encode (_appDeps app),
        "test-dependencies" ==> Encode.dict Pkg.toJsonString Constraint.encode (_appTestDeps app),
        "dependencies-direct" ==> Encode.dict Pkg.toJsonString Version.encode (_appDepsDirect app),
        "dependencies-indirect" ==> Encode.dict Pkg.toJsonString Version.encode (_appDepsIndirect app),
        "test-dependencies-direct" ==> Encode.dict Pkg.toJsonString Version.encode (_appTestDepsDirect app)
      ]
    capsField
      | _appCapabilities app == emptyCapabilities = []
      | otherwise = ["capabilities" ==> Encode.list (Encode.chars . Text.unpack) (Set.toList (effectiveCapabilities (_appCapabilities app)))]
    kitField = maybe [] (\k -> ["kit" ==> encodeKitConfig k]) (_appKit app)

-- | Encode kit configuration.
encodeKitConfig :: KitConfig -> Encode.Value
encodeKitConfig kit =
  Encode.object ["routes-dir" ==> Encode.chars (_kitRoutesDir kit)]

-- | Encode package outline.
encodePkgOutline :: PkgOutline -> Encode.Value
encodePkgOutline (PkgOutline name summary license version exposed deps testDeps canopy) =
  Encode.object
    [ "type" ==> Encode.chars "package",
      "name" ==> Pkg.encode name,
      "summary" ==> Encode.chars (Text.unpack summary),
      "license" ==> Licenses.encode license,
      "version" ==> Version.encode version,
      "exposed-modules" ==> encodeExposed exposed,
      "dependencies" ==> Encode.dict Pkg.toJsonString Constraint.encode deps,
      "test-dependencies" ==> Encode.dict Pkg.toJsonString Constraint.encode testDeps,
      "canopy-version" ==> Constraint.encode canopy
    ]

-- | Encode workspace outline.
encodeWorkspaceOutline :: WorkspaceOutline -> Encode.Value
encodeWorkspaceOutline (WorkspaceOutline packages sharedDeps canopy) =
  Encode.object
    [ "type" ==> Encode.chars "workspace",
      "packages" ==> Encode.list Encode.chars packages,
      "shared-dependencies" ==> Encode.dict Pkg.toJsonString Version.encode sharedDeps,
      "canopy-version" ==> Version.encode canopy
    ]

-- | Encode exposed modules.
encodeExposed :: Exposed -> Encode.Value
encodeExposed (ExposedList mods) = Encode.list ModuleName.encode mods
encodeExposed (ExposedDict dict) =
  Encode.object (map (\(category, mods) -> Text.unpack category ==> Encode.list ModuleName.encode mods) dict)

-- | Encode source directory.
encodeSrcDir :: SrcDir -> Encode.Value
encodeSrcDir (AbsoluteSrcDir path) = Encode.chars path
encodeSrcDir (RelativeSrcDir path) = Encode.chars path

-- | Flatten exposed modules to a simple list.
--
-- Converts both ExposedList and ExposedDict formats to a flat list
-- of module names, discarding category information from dictionaries.
--
-- @since 0.19.1
flattenExposed :: Exposed -> [ModuleName.Raw]
flattenExposed (ExposedList mods) = mods
flattenExposed (ExposedDict dict) = concatMap snd dict

-- | Extract all dependency packages with resolved versions.
--
-- For applications: merges direct, indirect, and test-direct deps.
-- For packages: extracts 'Constraint.lowerBound' from each constraint in deps and test-deps.
--
-- @since 0.19.1
allDeps :: Outline -> [(Pkg.Name, Version.Version)]
allDeps (App o) =
  Map.toList (_appDepsDirect o)
    ++ Map.toList (_appDepsIndirect o)
    ++ Map.toList (_appTestDepsDirect o)
allDeps (Pkg o) =
  Map.toList (Map.map Constraint.lowerBound (Map.union (_pkgDeps o) (_pkgTestDeps o)))
allDeps (Workspace o) =
  Map.toList (_wsSharedDeps o)

-- | Check whether an outline represents a workspace.
--
-- @since 0.19.2
isWorkspace :: Outline -> Bool
isWorkspace (Workspace _) = True
isWorkspace _ = False

-- | Check whether an outline is a CanopyKit application.
--
-- Returns 'True' when the outline is an 'App' with a 'KitConfig' present,
-- indicating file-based routing and meta-framework features are enabled.
--
-- @since 0.19.2
isKitProject :: Outline -> Bool
isKitProject (App app) = maybe False (const True) (_appKit app)
isKitProject _ = False

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | FFI.Manifest - Capability manifest generation from FFI content
--
-- Scans FFI JavaScript content for @capability annotations and produces
-- a structured manifest of all capabilities required by the application.
-- This manifest is written as @capabilities.json@ alongside compiled output.
--
-- == Manifest Format
--
-- @
-- {
--   "required": {
--     "permissions": ["microphone", "geolocation"],
--     "initialization": ["AudioContext"],
--     "userActivation": true
--   },
--   "by-module": {
--     "Audio": {
--       "permissions": ["microphone"],
--       "functions": {
--         "decodeAudio": ["permission:microphone", "init:AudioContext"]
--       }
--     }
--   }
-- }
-- @
--
-- @since 0.19.1
module FFI.Manifest
  ( -- * Types
    CapabilityManifest (..),
    ModuleCapabilities (..),
    FunctionCapability (..),
    PackageCapabilities (..),

    -- * Lenses
    manifestPermissions,
    manifestInitializations,
    manifestUserActivation,
    manifestModules,
    manifestByPackage,
    mcModuleName,
    mcFunctions,
    fcFunctionName,
    fcConstraints,
    pcPackageName,
    pcCapabilities,

    -- * Collection
    collectCapabilities,
    collectCapabilitiesWithPackages,
    collectByPackage,

    -- * Serialization
    writeManifest,
    readManifest,
  )
where

import Control.Lens (makeLenses)
import qualified Data.Aeson as Json
import Data.Aeson ((.=), (.:), (.:?))
import Data.Aeson.Types (Object, Parser)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified FFI.Capability as Capability
import FFI.Types (JsFunctionName (..), PermissionName (..), ResourceName (..))
import qualified Foreign.FFI as FFI
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import qualified System.Directory as Dir

-- | Top-level capability manifest for the compiled application.
--
-- @since 0.19.1
data CapabilityManifest = CapabilityManifest
  { _manifestPermissions :: !(Set.Set Text),
    _manifestInitializations :: !(Set.Set Text),
    _manifestUserActivation :: !Bool,
    _manifestModules :: ![ModuleCapabilities],
    _manifestByPackage :: ![PackageCapabilities]
  }
  deriving (Show)

-- | Capabilities required by a single module.
--
-- @since 0.19.1
data ModuleCapabilities = ModuleCapabilities
  { _mcModuleName :: !Text,
    _mcFunctions :: ![FunctionCapability]
  }
  deriving (Show)

-- | Capabilities required by a single FFI function.
--
-- @since 0.19.1
data FunctionCapability = FunctionCapability
  { _fcFunctionName :: !Text,
    _fcConstraints :: ![Text]
  }
  deriving (Show)

-- | Capabilities grouped by dependency package.
--
-- Used by @canopy audit --capabilities@ to show which capabilities
-- each dependency requires.
--
-- @since 0.20.0
data PackageCapabilities = PackageCapabilities
  { _pcPackageName :: !Text,
    _pcCapabilities :: !(Set.Set Text)
  }
  deriving (Show)

makeLenses ''CapabilityManifest
makeLenses ''ModuleCapabilities
makeLenses ''FunctionCapability
makeLenses ''PackageCapabilities

-- | Collect capabilities from parsed FFI functions.
--
-- Scans the FFI content for @capability annotations and produces
-- a structured manifest. Accepts an optional file-to-package mapping
-- to populate the per-package breakdown used by @canopy audit@.
--
-- @since 0.19.1
collectCapabilities :: [(Text, [FFI.JSDocFunction])] -> CapabilityManifest
collectCapabilities = collectCapabilitiesWithPackages Map.empty

-- | Collect capabilities with a file-to-package name mapping.
--
-- When a non-empty mapping is provided, groups capabilities by their
-- originating package for the @_manifestByPackage@ field.
--
-- @since 0.20.1
collectCapabilitiesWithPackages :: Map.Map Text Text -> [(Text, [FFI.JSDocFunction])] -> CapabilityManifest
collectCapabilitiesWithPackages pkgMap moduleFunctions =
  CapabilityManifest
    { _manifestPermissions = allPermissions,
      _manifestInitializations = allInits,
      _manifestUserActivation = anyUserActivation,
      _manifestModules = modCaps,
      _manifestByPackage = collectByPackage packageCaps
    }
  where
    modCaps = concatMap buildModuleCaps moduleFunctions
    allConstraints = concatMap gatherConstraints moduleFunctions
    allPermissions = Set.fromList [t | t <- allConstraints, "permission:" `Text.isPrefixOf` t]
    allInits = Set.fromList [t | t <- allConstraints, "init:" `Text.isPrefixOf` t]
    anyUserActivation = any ("user-activation" ==) allConstraints
    packageCaps = mapMaybe (extractPackageCaps pkgMap) moduleFunctions

-- | Extract package capabilities for a single module using the package map.
extractPackageCaps :: Map.Map Text Text -> (Text, [FFI.JSDocFunction]) -> Maybe (Text, Set.Set Text)
extractPackageCaps pkgMap (filePath, funcs) =
  case Map.lookup filePath pkgMap of
    Nothing -> Nothing
    Just pkgName ->
      let caps = Set.fromList (concatMap extractConstraintTexts (extractFunctionConstraints funcs))
       in if Set.null caps then Nothing else Just (pkgName, caps)

-- | Collect capabilities grouped by package name.
--
-- Takes a list of (package name, capability names) pairs and groups them
-- into 'PackageCapabilities' entries for the manifest.
--
-- @since 0.20.0
collectByPackage :: [(Text, Set.Set Text)] -> [PackageCapabilities]
collectByPackage =
  map (\(pkg, caps) -> PackageCapabilities pkg caps) . Map.toList . Map.fromListWith Set.union

-- | Gather all constraint text labels from a module's FFI functions.
gatherConstraints :: (Text, [FFI.JSDocFunction]) -> [Text]
gatherConstraints (_, functions) =
  concatMap extractConstraintTexts (extractFunctionConstraints functions)

-- | Build module capabilities from a list of JSDoc functions.
buildModuleCaps :: (Text, [FFI.JSDocFunction]) -> [ModuleCapabilities]
buildModuleCaps (moduleName, functions) =
  let funCaps = extractFunctionConstraints functions
      nonEmpty = filter (not . null . snd) funCaps
  in  if null nonEmpty
        then []
        else
          [ ModuleCapabilities
              { _mcModuleName = moduleName,
                _mcFunctions = map toFunctionCap nonEmpty
              }
          ]

-- | Extract constraints from a list of JSDoc functions.
extractFunctionConstraints :: [FFI.JSDocFunction] -> [(Text, [Text])]
extractFunctionConstraints = map extractOne
  where
    extractOne f =
      let JsFunctionName fname = FFI.jsDocFuncName f
          caps = maybe [] flattenConstraint (FFI.jsDocFuncCapabilities f)
      in (fname, caps)

-- | Convert a function constraint pair to a FunctionCapability.
toFunctionCap :: (Text, [Text]) -> FunctionCapability
toFunctionCap (fname, constraints) =
  FunctionCapability
    { _fcFunctionName = fname,
      _fcConstraints = constraints
    }

-- | Flatten a CapabilityConstraint into text labels.
flattenConstraint :: Capability.CapabilityConstraint -> [Text]
flattenConstraint Capability.UserActivationRequired = ["user-activation"]
flattenConstraint (Capability.PermissionRequired (PermissionName p)) = ["permission:" <> p]
flattenConstraint (Capability.InitializationRequired (ResourceName r)) = ["init:" <> r]
flattenConstraint (Capability.AvailabilityRequired feat) = ["availability:" <> feat]
flattenConstraint (Capability.MultipleConstraints cs) = concatMap flattenConstraint cs

-- | Extract all constraint text labels from a list of text pairs.
extractConstraintTexts :: (Text, [Text]) -> [Text]
extractConstraintTexts (_, cs) = cs

-- | Write the capability manifest to a JSON file.
--
-- @since 0.19.1
writeManifest :: FilePath -> CapabilityManifest -> IO ()
writeManifest path manifest = do
  Log.logEvent (PackageOperation "capabilities-write" (Text.pack path))
  LBS.writeFile path (Json.encode manifest)

-- JSON serialization

instance Json.ToJSON CapabilityManifest where
  toJSON m =
    Json.object
      ( [ "required"
            .= Json.object
              [ "permissions" .= Set.toList (_manifestPermissions m),
                "initialization" .= Set.toList (_manifestInitializations m),
                "userActivation" .= _manifestUserActivation m
              ],
          "by-module" .= Map.fromList (map moduleToKV (_manifestModules m))
        ]
          ++ byPackageField
      )
    where
      moduleToKV mc =
        ( _mcModuleName mc,
          Json.object
            [ "functions"
                .= Map.fromList
                  (map (\fc -> (_fcFunctionName fc, Json.toJSON (_fcConstraints fc))) (_mcFunctions mc))
            ]
        )
      byPackageField
        | null (_manifestByPackage m) = []
        | otherwise =
            ["by-package" .= Map.fromList (map pkgToKV (_manifestByPackage m))]
      pkgToKV pc = (_pcPackageName pc, Set.toList (_pcCapabilities pc))

instance Json.FromJSON CapabilityManifest where
  parseJSON = Json.withObject "CapabilityManifest" parseManifestObject

instance Json.FromJSON PackageCapabilities where
  parseJSON = Json.withObject "PackageCapabilities" parsePackageCaps

-- | Parse the top-level manifest JSON object.
--
-- @since 0.20.0
parseManifestObject :: Object -> Parser CapabilityManifest
parseManifestObject o = do
  reqVal <- o .: "required"
  requiredFields <- Json.withObject "required" parseRequired reqVal
  byMod <- o .:? "by-module"
  byPkg <- o .:? "by-package"
  pure (applyOptionalFields requiredFields (parseByModuleField byMod) byPkg)

-- | Parse the required capabilities section.
--
-- @since 0.20.0
parseRequired :: Object -> Parser ([Text], [Text], Bool)
parseRequired req = do
  perms <- req .: "permissions"
  inits <- req .: "initialization"
  userAct <- req .: "userActivation"
  pure (perms, inits, userAct)

-- | Apply optional fields to build the final manifest.
--
-- @since 0.20.0
applyOptionalFields ::
  ([Text], [Text], Bool) ->
  [ModuleCapabilities] ->
  Maybe (Map.Map Text [Text]) ->
  CapabilityManifest
applyOptionalFields (perms, inits, userAct) modCaps byPkg =
  buildManifest perms inits userAct modCaps byPkg

-- | Parse the optional by-module field from the manifest.
--
-- Each module entry contains a @functions@ map of function name to
-- constraint list. When the field is absent, returns an empty list.
--
-- @since 0.20.0
parseByModuleField :: Maybe (Map.Map Text ModuleEntry) -> [ModuleCapabilities]
parseByModuleField Nothing = []
parseByModuleField (Just modMap) =
  map toModCap (Map.toList modMap)
  where
    toModCap (name, entry) =
      ModuleCapabilities name (map toFuncCap (Map.toList (_meFunctions entry)))
    toFuncCap (fname, constraints) =
      FunctionCapability fname constraints

-- | Intermediate type for parsing module entries from JSON.
--
-- @since 0.20.0
newtype ModuleEntry = ModuleEntry
  { _meFunctions :: Map.Map Text [Text]
  }

instance Json.FromJSON ModuleEntry where
  parseJSON = Json.withObject "ModuleEntry" (\o -> ModuleEntry <$> o .: "functions")

-- | Assemble a manifest from parsed JSON fields.
--
-- @since 0.20.0
buildManifest ::
  [Text] ->
  [Text] ->
  Bool ->
  [ModuleCapabilities] ->
  Maybe (Map.Map Text [Text]) ->
  CapabilityManifest
buildManifest perms inits userAct modCaps byPkg =
  CapabilityManifest
    { _manifestPermissions = Set.fromList perms,
      _manifestInitializations = Set.fromList inits,
      _manifestUserActivation = userAct,
      _manifestModules = modCaps,
      _manifestByPackage = maybe [] parsePkgMap byPkg
    }

-- | Convert a by-package JSON map into package capabilities.
--
-- @since 0.20.0
parsePkgMap :: Map.Map Text [Text] -> [PackageCapabilities]
parsePkgMap =
  map (\(name, caps) -> PackageCapabilities name (Set.fromList caps)) . Map.toList

-- | Parse a 'PackageCapabilities' from a JSON object with name and capabilities.
--
-- @since 0.20.0
parsePackageCaps :: Object -> Parser PackageCapabilities
parsePackageCaps o = do
  name <- o .: "name"
  caps <- o .: "capabilities"
  pure (PackageCapabilities name (Set.fromList caps))

-- | Read a capability manifest from a JSON file.
--
-- Returns 'Nothing' if the file does not exist or cannot be parsed.
--
-- @since 0.20.0
readManifest :: FilePath -> IO (Maybe CapabilityManifest)
readManifest path = do
  exists <- Dir.doesFileExist path
  if exists
    then Json.decode <$> LBS.readFile path
    else pure Nothing

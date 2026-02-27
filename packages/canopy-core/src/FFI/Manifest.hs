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

    -- * Lenses
    manifestPermissions,
    manifestInitializations,
    manifestUserActivation,
    manifestModules,
    mcModuleName,
    mcFunctions,
    fcFunctionName,
    fcConstraints,

    -- * Collection
    collectCapabilities,

    -- * Serialization
    writeManifest,
  )
where

import Control.Lens (makeLenses)
import qualified Data.Aeson as Json
import Data.Aeson ((.=))
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified FFI.Capability as Capability
import FFI.Types (JsFunctionName (..), PermissionName (..), ResourceName (..))
import qualified Foreign.FFI as FFI
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log

-- | Top-level capability manifest for the compiled application.
--
-- @since 0.19.1
data CapabilityManifest = CapabilityManifest
  { _manifestPermissions :: !(Set.Set Text),
    _manifestInitializations :: !(Set.Set Text),
    _manifestUserActivation :: !Bool,
    _manifestModules :: ![ModuleCapabilities]
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

makeLenses ''CapabilityManifest
makeLenses ''ModuleCapabilities
makeLenses ''FunctionCapability

-- | Collect capabilities from parsed FFI functions.
--
-- Scans the FFI content for @capability annotations and produces
-- a structured manifest.
--
-- @since 0.19.1
collectCapabilities :: [(Text, [FFI.JSDocFunction])] -> CapabilityManifest
collectCapabilities moduleFunctions =
  CapabilityManifest
    { _manifestPermissions = allPermissions,
      _manifestInitializations = allInits,
      _manifestUserActivation = anyUserActivation,
      _manifestModules = modCaps
    }
  where
    modCaps = concatMap buildModuleCaps moduleFunctions
    allConstraints = concatMap gatherConstraints moduleFunctions
    allPermissions = Set.fromList [t | t <- allConstraints, "permission:" `Text.isPrefixOf` t]
    allInits = Set.fromList [t | t <- allConstraints, "init:" `Text.isPrefixOf` t]
    anyUserActivation = any ("user-activation" ==) allConstraints

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
      [ "required"
          .= Json.object
            [ "permissions" .= Set.toList (_manifestPermissions m),
              "initialization" .= Set.toList (_manifestInitializations m),
              "userActivation" .= _manifestUserActivation m
            ],
        "by-module" .= Map.fromList (map moduleToKV (_manifestModules m))
      ]
    where
      moduleToKV mc =
        ( _mcModuleName mc,
          Json.object
            [ "functions"
                .= Map.fromList
                  (map (\fc -> (_fcFunctionName fc, Json.toJSON (_fcConstraints fc))) (_mcFunctions mc))
            ]
        )

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Capability-based constraint system for FFI safety
--
-- This module implements a compile-time capability system that prevents
-- runtime errors in Web API usage by encoding constraints in the type system.
--
-- Key concepts:
-- * Capabilities represent permissions, user activation, or initialization state
-- * Functions declare capability requirements in their type signatures
-- * Type checker enforces capability constraints at compile time
-- * JavaScript FFI generates runtime capability checks
--
-- @since 0.19.1
module Type.Capability
  ( -- * Core capability types
    Capability(..)
  , CapabilityConstraint(..)
  , CapabilityError(..)
  , CapabilityRequirement(..)

    -- * Capability constraint checking
  , checkCapabilityConstraints
  , inferCapabilityRequirements
  , validateFFICapabilities

    -- * Built-in capability types
  , builtinCapabilities
  , parseCapabilityAnnotation

    -- * JavaScript generation
  , generateCapabilityCheck
  , generateCapabilityAcquisition
  ) where

import qualified Data.Map.Strict as Map
import Data.Map (Map)
import qualified Data.Set as Set
import Data.Set (Set)
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Name as Name
import qualified Reporting.Annotation as A
import qualified Type.Type as Type

-- | Core capability types that represent different kinds of constraints
data Capability
  = UserActivationCapability
    -- ^ Requires user gesture (click, keypress, etc.)
    -- Required for: Audio/Video playback, Fullscreen, Clipboard, Payment Request

  | PermissionCapability Text
    -- ^ Requires browser permission grant
    -- Examples: "geolocation", "camera", "microphone", "notifications"

  | InitializationCapability Text
    -- ^ Requires resource initialization
    -- Examples: "AudioContext", "WebGLContext", "ServiceWorker", "Database"

  | AvailabilityCapability Text
    -- ^ Requires API/feature availability check
    -- Examples: "WebGL", "ServiceWorker", "Clipboard", "Geolocation"

  | SecureContextCapability
    -- ^ Requires HTTPS/secure context
    -- Required for: Service Workers, Clipboard, some permissions

  | CustomCapability Text
    -- ^ Custom application-specific capabilities
    -- Allows extending the system for domain-specific constraints
  deriving (Eq, Ord, Show)

-- | Capability constraints attached to function types
data CapabilityConstraint = CapabilityConstraint
  { _constraintCapabilities :: !(Set Capability)
    -- ^ Set of capabilities required by this function
  , _constraintLocation :: !A.Region
    -- ^ Source location where constraint was declared
  , _constraintReason :: !Text
    -- ^ Human-readable explanation of why capability is needed
  } deriving (Eq, Show)

-- | Errors that occur during capability constraint checking
data CapabilityError
  = MissingCapability
      { _missingCapability :: !Capability
      , _missingLocation :: !A.Region
      , _missingFunction :: !Name.Name
      , _missingReason :: !Text
      }
  | ConflictingCapabilities
      { _conflictingCapabilities :: !(Set Capability)
      , _conflictingLocation :: !A.Region
      , _conflictingExplanation :: !Text
      }
  | InvalidCapabilityAnnotation
      { _invalidAnnotation :: !Text
      , _invalidLocation :: !A.Region
      , _invalidExpected :: !Text
      }
  | UnsupportedCapability
      { _unsupportedCapability :: !Capability
      , _unsupportedLocation :: !A.Region
      , _unsupportedAlternatives :: ![Text]
      }
  deriving (Eq, Show)

-- | Capability requirements for a function or expression
data CapabilityRequirement = CapabilityRequirement
  { _reqCapabilities :: !(Set Capability)
    -- ^ All capabilities needed
  , _reqAcquisitionOrder :: ![Capability]
    -- ^ Order in which capabilities must be acquired
  , _reqOptionalCapabilities :: !(Set Capability)
    -- ^ Capabilities that provide enhanced functionality but aren't required
  } deriving (Eq, Show)

-- | Check if capability constraints are satisfied in a given context
checkCapabilityConstraints ::
  Set Capability                    -- ^ Available capabilities in current context
  -> CapabilityConstraint           -- ^ Required capabilities
  -> Either CapabilityError ()
checkCapabilityConstraints availableCapabilities constraint =
  let required = _constraintCapabilities constraint
      missing = Set.difference required availableCapabilities
  in if Set.null missing
     then Right ()
     else Left $ MissingCapability
       { _missingCapability = Set.findMin missing  -- Report first missing capability
       , _missingLocation = _constraintLocation constraint
       , _missingFunction = Name.fromChars "unknown"  -- TODO: pass function name
       , _missingReason = _constraintReason constraint
       }

-- | Infer capability requirements from a function type signature
inferCapabilityRequirements :: Type.Type -> CapabilityRequirement
inferCapabilityRequirements _functionType =
  -- TODO: Analyze function type to extract capability constraints
  -- This would walk the type structure looking for capability annotations
  CapabilityRequirement
    { _reqCapabilities = Set.empty
    , _reqAcquisitionOrder = []
    , _reqOptionalCapabilities = Set.empty
    }

-- | Validate FFI function capability annotations
validateFFICapabilities ::
  Text                              -- ^ FFI function name
  -> Text                           -- ^ Capability annotation string
  -> A.Region                       -- ^ Source location
  -> Either CapabilityError CapabilityConstraint
validateFFICapabilities funcName annotation location = do
  capabilities <- parseCapabilityAnnotation annotation location
  pure $ CapabilityConstraint
    { _constraintCapabilities = capabilities
    , _constraintLocation = location
    , _constraintReason = "FFI function " <> funcName <> " requires capabilities"
    }

-- | Built-in capability definitions with their JavaScript runtime checks
builtinCapabilities :: Map Text Capability
builtinCapabilities = Map.fromList
  [ ("user-activation", UserActivationCapability)
  , ("geolocation", PermissionCapability "geolocation")
  , ("camera", PermissionCapability "camera")
  , ("microphone", PermissionCapability "microphone")
  , ("notifications", PermissionCapability "notifications")
  , ("audio-context", InitializationCapability "AudioContext")
  , ("webgl-context", InitializationCapability "WebGLContext")
  , ("service-worker", InitializationCapability "ServiceWorker")
  , ("webgl", AvailabilityCapability "WebGL")
  , ("clipboard", AvailabilityCapability "Clipboard")
  , ("secure-context", SecureContextCapability)
  ]

-- | Parse capability annotation from FFI type comment
parseCapabilityAnnotation :: Text -> A.Region -> Either CapabilityError (Set Capability)
parseCapabilityAnnotation annotation location = do
  let capabilityStrings = Text.splitOn "," (Text.strip annotation)
  capabilities <- traverse (parseIndividualCapability location) capabilityStrings
  pure $ Set.fromList capabilities

-- | Parse a single capability from text
parseIndividualCapability :: A.Region -> Text -> Either CapabilityError Capability
parseIndividualCapability location capText = do
  let cleanText = Text.strip capText
  case Map.lookup cleanText builtinCapabilities of
    Just capability -> Right capability
    Nothing ->
      if Text.isPrefixOf "permission:" cleanText
        then Right $ PermissionCapability (Text.drop 11 cleanText)
        else if Text.isPrefixOf "init:" cleanText
        then Right $ InitializationCapability (Text.drop 5 cleanText)
        else if Text.isPrefixOf "available:" cleanText
        then Right $ AvailabilityCapability (Text.drop 10 cleanText)
        else if Text.isPrefixOf "custom:" cleanText
        then Right $ CustomCapability (Text.drop 7 cleanText)
        else Left $ InvalidCapabilityAnnotation
          { _invalidAnnotation = cleanText
          , _invalidLocation = location
          , _invalidExpected = "user-activation, permission:name, init:resource, available:feature, or custom:name"
          }

-- | Generate JavaScript runtime capability check
generateCapabilityCheck :: Capability -> Text
generateCapabilityCheck capability =
  case capability of
    UserActivationCapability ->
      "if (!window.CapabilityTracker.hasUserActivation()) { throw new Error('User activation required'); }"

    PermissionCapability permission ->
      "if (!window.CapabilityTracker.hasPermission('" <> permission <> "')) { throw new Error('Permission required: " <> permission <> "'); }"

    InitializationCapability resource ->
      "if (!window.CapabilityTracker.isInitialized('" <> resource <> "')) { throw new Error('Resource not initialized: " <> resource <> "'); }"

    AvailabilityCapability feature ->
      "if (!window.CapabilityTracker.isAvailable('" <> feature <> "')) { throw new Error('Feature not available: " <> feature <> "'); }"

    SecureContextCapability ->
      "if (!window.isSecureContext) { throw new Error('Secure context required (HTTPS)'); }"

    CustomCapability name ->
      "if (!window.CapabilityTracker.hasCustomCapability('" <> name <> "')) { throw new Error('Custom capability required: " <> name <> "'); }"

-- | Generate JavaScript code to acquire a capability
generateCapabilityAcquisition :: Capability -> Text
generateCapabilityAcquisition capability =
  case capability of
    UserActivationCapability ->
      "// User activation acquired through event handler"

    PermissionCapability permission ->
      "await window.CapabilityTracker.requestPermission('" <> permission <> "')"

    InitializationCapability resource ->
      "await window.CapabilityTracker.initializeResource('" <> resource <> "')"

    AvailabilityCapability feature ->
      "window.CapabilityTracker.checkAvailability('" <> feature <> "')"

    SecureContextCapability ->
      "// Secure context check - upgrade to HTTPS if needed"

    CustomCapability name ->
      "await window.CapabilityTracker.acquireCustomCapability('" <> name <> "')"
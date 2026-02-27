{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Capability constraints for FFI functions - lightweight parsing types
--
-- This module provides simple capability constraint types used during JSDoc
-- parsing in Foreign.FFI. These types represent the parsed @capability
-- annotations from JavaScript files.
--
-- = Module Design
--
-- There are two capability-related modules in canopy-core:
--
-- * 'FFI.Capability' (this module) - Lightweight types for parsing @capability
--   annotations from JSDoc. Used by 'Foreign.FFI' during FFI processing.
--   These types are simple sum types representing parsed constraints.
--
-- * 'Type.Capability' - Comprehensive capability infrastructure including
--   validation, runtime check generation, and built-in capability definitions.
--   Intended for future runtime validation features.
--
-- = Usage
--
-- This module is imported by 'Foreign.FFI' to store capability information
-- parsed from JSDoc annotations like:
--
-- @
-- \/**
--  * \@capability user-activation
--  * \@capability permission microphone
--  *\/
-- @
--
-- @since 0.19.1
module FFI.Capability
  ( -- * Basic Capability Types
    CapabilityConstraint(..)
  , CapabilityError(..)
  , Capability(..)
  ) where

import Data.Text (Text)

-- | Basic capability constraint types
data CapabilityConstraint
  = UserActivationRequired
    -- ^ Function requires user activation (click, keypress, etc.)
  | PermissionRequired !Text
    -- ^ Function requires browser permission (geolocation, microphone, etc.)
  | InitializationRequired !Text
    -- ^ Function requires initialized resource (AudioContext, WebGL context, etc.)
  | AvailabilityRequired !Text
    -- ^ Function requires feature availability check
  | MultipleConstraints ![CapabilityConstraint]
    -- ^ Function requires multiple capabilities
  deriving (Eq, Show)

-- | Capability errors that can occur at runtime
data CapabilityError
  = UserActivationRequiredError !Text
    -- ^ User activation was required but not present
  | PermissionRequiredError !Text
    -- ^ Permission was required but not granted
  | InitializationRequiredError !Text
    -- ^ Resource initialization was required but not done
  | FeatureNotAvailableError !Text
    -- ^ Required feature is not available in browser
  deriving (Eq, Show)

-- | Individual capability types
data Capability
  = UserActivationCapability
    -- ^ User has performed a gesture (click, keypress, etc.)
  | PermissionCapability !Text
    -- ^ Browser permission has been granted
  | InitializationCapability !Text
    -- ^ Resource has been properly initialized
  | AvailabilityCapability !Text
    -- ^ Feature is available in the browser
  deriving (Eq, Show)
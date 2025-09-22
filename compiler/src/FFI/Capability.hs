{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Capability constraints for FFI functions - minimal version to avoid circular imports
--
-- This module provides basic capability constraint types for the FFI system
-- without heavy dependencies that could cause circular imports.
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
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Universal Capability System for Safe Web API Access
--
-- This module provides a comprehensive capability-based type system that can be
-- applied to ANY Web API to prevent runtime errors at compile time.
--
-- @since 0.19.1
module Capability.Core
  ( -- * Core Capability Types
    Capability(..)
  , CapabilityConstraint(..)
  , CapabilityError(..)

    -- * Universal Capability Constraints
  , UserActivated
  , Initialized(..)
  , Permitted(..)
  , Available(..)

    -- * API Patterns
  , ApiPattern(..)
  , requiresUserActivation
  , requiresPermission
  , requiresInitialization
  , requiresAvailability
  ) where

import Data.Text (Text)

-- | Universal capability phantom types
-- These can be applied to ANY Web API that has constraints

-- | User activation capability - prevents "user activation required" errors
data UserActivated = UserActivated
  deriving (Eq, Show)

-- | Initialization capability - prevents "not initialized" errors
data Initialized a = Initialized a
  deriving (Eq, Show)

-- | Permission capability - prevents "permission denied" errors
data Permitted a = Permitted a
  deriving (Eq, Show)

-- | Availability capability - prevents "feature not available" errors
data Available a = Available a
  deriving (Eq, Show)

-- | Core capability types that can be combined
data Capability
  = UserActivationCapability
  | PermissionCapability !Text       -- geolocation, microphone, camera, etc.
  | InitializationCapability !Text   -- AudioContext, WebGL, ServiceWorker, etc.
  | AvailabilityCapability !Text     -- WebGL, WebAssembly, Notifications, etc.
  deriving (Eq, Show)

-- | Capability constraints that can be applied to any API function
data CapabilityConstraint
  = RequiresUserActivation
  | RequiresPermission !Text
  | RequiresInitialization !Text
  | RequiresAvailability !Text
  | RequiresMultiple ![CapabilityConstraint]
  deriving (Eq, Show)

-- | Capability errors that can occur with any API
data CapabilityError
  = UserActivationRequired !Text
  | PermissionRequired !Text
  | InitializationRequired !Text
  | FeatureNotAvailable !Text
  deriving (Eq, Show)

-- | Universal API patterns that apply to all Web APIs
data ApiPattern
  = MediaPattern        -- Audio, Video, Camera, Microphone
  | LocationPattern     -- Geolocation, GPS
  | StoragePattern      -- LocalStorage, IndexedDB, Cache
  | ClipboardPattern    -- Clipboard read/write
  | FullscreenPattern   -- Fullscreen API
  | NotificationPattern -- Push notifications
  | GraphicsPattern     -- WebGL, Canvas, WebGPU
  | WorkerPattern       -- ServiceWorker, WebWorker
  | NetworkPattern      -- Fetch, WebSocket, WebRTC
  deriving (Eq, Show)

-- | Check if an API pattern requires user activation
requiresUserActivation :: ApiPattern -> Bool
requiresUserActivation pattern = case pattern of
  MediaPattern -> True
  ClipboardPattern -> True
  FullscreenPattern -> True
  _ -> False

-- | Check if an API pattern requires permission
requiresPermission :: ApiPattern -> Maybe Text
requiresPermission pattern = case pattern of
  MediaPattern -> Just "microphone"
  LocationPattern -> Just "geolocation"
  NotificationPattern -> Just "notifications"
  _ -> Nothing

-- | Check if an API pattern requires initialization
requiresInitialization :: ApiPattern -> Maybe Text
requiresInitialization pattern = case pattern of
  MediaPattern -> Just "AudioContext"
  GraphicsPattern -> Just "WebGLContext"
  WorkerPattern -> Just "ServiceWorker"
  _ -> Nothing

-- | Check if an API pattern requires availability check
requiresAvailability :: ApiPattern -> Maybe Text
requiresAvailability pattern = case pattern of
  GraphicsPattern -> Just "WebGL"
  WorkerPattern -> Just "ServiceWorker"
  NetworkPattern -> Just "WebRTC"
  _ -> Nothing
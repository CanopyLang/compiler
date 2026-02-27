{-# LANGUAGE OverloadedStrings #-}

-- | Synchronous write scope for the Canopy build system.
--
-- The original Elm compiler used STM-based concurrent file writing to flush
-- artifact caches in the background. Canopy's pure build pipeline writes
-- artifacts synchronously through the query-based compiler, making the
-- background writer unnecessary. This module preserves the 'Scope' API
-- so that call sites (e.g. 'Canopy.Details.load') can pass a unit scope
-- without structural changes.
--
-- @since 0.19.1
module BackgroundWriter
  ( -- * Scope Type
    Scope,

    -- * Scope Operations
    withScope,
  )
where

-- | Build scope token passed to operations that may write artifacts.
--
-- In the synchronous pipeline this is simply @()@.
type Scope = ()

-- | Run an action within a write scope.
--
-- Executes the action directly since Canopy's build pipeline handles
-- artifact persistence synchronously through the query engine.
withScope :: (Scope -> IO a) -> IO a
withScope action = action ()

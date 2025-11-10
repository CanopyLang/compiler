{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Background writer placeholder for Terminal.
--
-- The OLD BackgroundWriter used STM for concurrent file writing.
-- Since we're using the NEW pure compiler, this is now a simple
-- placeholder that provides the same API without actual background writing.
--
-- @since 0.19.1
module BackgroundWriter
  ( -- * Scope Type
    Scope,

    -- * Scope Operations
    withScope,
  )
where

-- | Scope placeholder (no actual background writing).
type Scope = ()

-- | Run action with scope (simplified, no background writing).
--
-- In the OLD system, this managed background file writing with STM.
-- Since the NEW compiler handles its own caching with JSON files,
-- we don't need this anymore.
withScope :: (Scope -> IO a) -> IO a
withScope action = action ()

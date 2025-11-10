{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | File timestamp operations for the Canopy build system.
--
-- This module provides functionality for working with file modification times
-- and time representations used throughout the build system.
--
-- The 'Time' type represents file modification times with high precision,
-- using POSIX timestamps internally for consistency and performance.
--
-- ==== Examples
--
-- >>> time <- getTime "src/Main.hs"
-- >>> time > zeroTime
-- True
--
-- >>> show zeroTime
-- "Time 0.000000000000s"
--
-- ==== Error Handling
--
-- 'getTime' can fail with 'IOException' if:
--   * File does not exist
--   * Insufficient permissions to read file metadata
--   * File system errors
--
-- @since 0.19.1
module File.Time
  ( -- * Time Type
    Time(..)
    -- * Time Operations
  , getTime
  , zeroTime
  ) where

import qualified Data.Binary as Binary
import qualified Data.Fixed as Fixed
import qualified Data.Time.Clock as Time
import qualified Data.Time.Clock.POSIX as Time
import qualified System.Directory as Dir

-- | High-precision file modification time.
--
-- Internally represents time as POSIX seconds with picosecond precision
-- for accurate comparison and storage operations.
newtype Time = Time Fixed.Pico
  deriving (Eq, Ord, Show)

-- | Get the modification time of a file.
--
-- Returns the file's modification time converted to POSIX seconds.
-- This provides a consistent time representation across different
-- file systems and platforms.
--
-- >>> time <- getTime "cabal.project"
-- >>> time > zeroTime
-- True
--
-- ==== Errors
--
-- Throws 'IOException' if the file cannot be accessed or does not exist.
getTime :: FilePath -> IO Time
getTime path =
  fmap convertToTime (Dir.getModificationTime path)

-- | Convert UTCTime to internal Time representation.
convertToTime :: Time.UTCTime -> Time
convertToTime = Time . Time.nominalDiffTimeToSeconds . Time.utcTimeToPOSIXSeconds

-- | Zero time constant for initialization and comparison.
--
-- Represents the Unix epoch (1970-01-01 00:00:00 UTC).
-- Used as a default value and for checking if time has been set.
--
-- >>> zeroTime == Time 0
-- True
zeroTime :: Time
zeroTime = Time 0

-- | Binary serialization instance for Time.
--
-- Enables efficient storage and retrieval of time values in cache files
-- and build artifacts. Uses the underlying Fixed.Pico serialization.
instance Binary.Binary Time where
  put (Time time) = Binary.put time
  get = Time <$> Binary.get
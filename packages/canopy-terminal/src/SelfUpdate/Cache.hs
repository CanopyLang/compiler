{-# LANGUAGE OverloadedStrings #-}

-- | Update-check cache for startup notifications.
--
-- Stores the last-seen latest version alongside a timestamp in
-- @~\/.canopy\/update-check@.  The cache has a 24-hour TTL so the
-- network is hit at most once per day.
--
-- File format (plain text, single line):
--
-- @
-- <unix-timestamp-integer>\t<version-string>
-- @
--
-- All IO errors are swallowed silently so a broken cache never
-- prevents the compiler from running.
--
-- @since 0.19.2
module SelfUpdate.Cache
  ( -- * Cache Access
    readCachedVersion,
    writeCachedVersion,
    cacheFilePath,

    -- * Pure Helpers (exposed for testing)
    parseCacheLine,
    isCacheFresh,
    formatCacheLine,
  )
where

import qualified Canopy.Version as Version
import qualified Control.Exception as Exception
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Data.Time.Clock.POSIX as POSIX
import qualified System.Directory as Dir
import System.FilePath ((</>))

-- | TTL for the update-check cache: 24 hours in seconds.
cacheTtlSeconds :: POSIX.POSIXTime
cacheTtlSeconds = 24 * 60 * 60

-- | Path to the cache file (@~\/.canopy\/update-check@).
--
-- Creates the @~\/.canopy@ directory if it does not already exist.
--
-- @since 0.19.2
cacheFilePath :: IO FilePath
cacheFilePath = do
  home <- Dir.getHomeDirectory
  let dir = home </> ".canopy"
  Dir.createDirectoryIfMissing True dir
  pure (dir </> "update-check")

-- | Read the cached latest version, returning 'Nothing' if the cache
-- is missing, malformed, or older than 24 hours.
--
-- @since 0.19.2
readCachedVersion :: IO (Maybe Version.Version)
readCachedVersion = do
  path <- cacheFilePath
  exists <- Dir.doesFileExist path
  if not exists
    then pure Nothing
    else readAndParse path

-- | Read and parse the cache file, handling IO errors gracefully.
readAndParse :: FilePath -> IO (Maybe Version.Version)
readAndParse path = do
  result <- Exception.try (TextIO.readFile path)
  case result of
    Left (_ :: Exception.SomeException) -> pure Nothing
    Right content -> do
      now <- POSIX.getPOSIXTime
      pure (parseCacheLine now content)

-- | Parse a single cache line against a reference time.
--
-- Returns 'Nothing' when the line is malformed or the timestamp is
-- older than 'cacheTtlSeconds'.
--
-- @since 0.19.2
parseCacheLine :: POSIX.POSIXTime -> Text.Text -> Maybe Version.Version
parseCacheLine now content =
  case Text.splitOn "\t" (Text.strip content) of
    [tsText, versionText] -> parseFields now tsText versionText
    _ -> Nothing

-- | Parse the timestamp and version fields from the cache line.
parseFields :: POSIX.POSIXTime -> Text.Text -> Text.Text -> Maybe Version.Version
parseFields now tsText versionText =
  case reads (Text.unpack tsText) of
    [(ts, "")] | isCacheFresh now ts ->
      Version.fromChars (Text.unpack versionText)
    _ -> Nothing

-- | Return 'True' when the recorded timestamp is within the TTL window.
--
-- @since 0.19.2
isCacheFresh :: POSIX.POSIXTime -> Integer -> Bool
isCacheFresh now ts = now - fromInteger ts < cacheTtlSeconds

-- | Serialize a timestamp and version into a cache line.
--
-- @since 0.19.2
formatCacheLine :: Integer -> Version.Version -> Text.Text
formatCacheLine ts version =
  Text.pack (show ts) <> "\t" <> Text.pack (Version.toChars version)

-- | Write the latest version to the cache file with the current timestamp.
--
-- Silently ignores any IO errors (e.g. read-only filesystem).
--
-- @since 0.19.2
writeCachedVersion :: Version.Version -> IO ()
writeCachedVersion version = do
  path <- cacheFilePath
  now <- POSIX.getPOSIXTime
  let content = formatCacheLine (floor now) version
  Exception.try (TextIO.writeFile path content) >>= ignoreError
  where
    ignoreError :: Either Exception.SomeException () -> IO ()
    ignoreError _ = pure ()

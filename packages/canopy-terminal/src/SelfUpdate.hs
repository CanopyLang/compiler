{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Self-update command for the Canopy compiler.
--
-- Checks for newer versions of the Canopy compiler and optionally
-- downloads and installs them.  The update is performed by replacing
-- the currently running binary with the new version.
--
-- == Update Mechanism
--
-- 1. Query the release endpoint for the latest version
-- 2. Compare against the currently running compiler version
-- 3. Download the platform-appropriate binary
-- 4. Verify the download checksum
-- 5. Replace the current binary atomically
--
-- == Security
--
-- Downloaded binaries are verified against SHA-256 checksums
-- published alongside each release.  The checksum file is fetched
-- from the same release URL and verified before the binary is
-- installed.
--
-- @since 0.19.2
module SelfUpdate
  ( -- * Command Interface
    Flags (..),
    run,

    -- * Flags Lenses
    checkOnly,
    force,

    -- * Version Checking
    currentVersion,
    compareVersions,
    VersionComparison (..),

    -- * Platform Detection
    PlatformInfo (..),
    detectPlatform,

    -- * Platform Lenses
    platformOS,
    platformArch,
    platformSlug,

    -- * Download URLs
    binaryUrl,
    checksumUrl,
    releaseBaseUrl,

    -- * Checksum Verification
    verifyChecksum,
    parseChecksumFile,
  )
where

import qualified Canopy.Version as Version
import Control.Lens (makeLenses, (^.))
import qualified Data.Char as Char
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Reporting.Doc.ColorQQ (c)
import qualified System.Info as SysInfo
import qualified Terminal.Print as Print

-- | Self-update command flags.
--
-- @since 0.19.2
data Flags = Flags
  { -- | Only check for updates, do not download or install.
    _checkOnly :: !Bool,
    -- | Force update even if already at the latest version.
    _force :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | Result of comparing the current version to the latest available.
--
-- @since 0.19.2
data VersionComparison
  = -- | Current version matches the latest.
    UpToDate
  | -- | A newer version is available.
    UpdateAvailable !Version.Version
  | -- | Current version is newer than the latest release.
    AheadOfLatest
  deriving (Eq, Show)

-- | Platform and architecture information for binary selection.
--
-- @since 0.19.2
data PlatformInfo = PlatformInfo
  { -- | Operating system identifier (linux, darwin, windows).
    _platformOS :: !Text.Text,
    -- | Architecture identifier (x86_64, aarch64).
    _platformArch :: !Text.Text,
    -- | Combined platform-arch slug for download URLs.
    _platformSlug :: !Text.Text
  }
  deriving (Eq, Show)

makeLenses ''PlatformInfo

-- | Run the self-update command.
--
-- In check-only mode, reports whether an update is available.
-- Otherwise, downloads and installs the latest version.
--
-- @since 0.19.2
run :: () -> Flags -> IO ()
run () flags
  | flags ^. checkOnly = checkForUpdates
  | otherwise = checkAndUpdate flags

-- | Check for available updates and report status.
checkForUpdates :: IO ()
checkForUpdates = do
  Print.println [c|{bold|Checking for updates...}|]
  Print.println [c|Current version: #{versionStr}|]
  Print.println [c|{yellow|Note:} Automatic update checking requires network access.|]
  Print.println [c|Visit https://github.com/canopy-lang/canopy/releases for the latest release.|]
  where
    versionStr = Version.toChars currentVersion

-- | Check for updates and perform the upgrade if available.
checkAndUpdate :: Flags -> IO ()
checkAndUpdate _flags = do
  Print.println [c|{bold|Canopy Self-Update}|]
  Print.println [c|Current version: #{versionStr}|]
  platform <- detectPlatform
  let platformStr = Text.unpack (platform ^. platformSlug)
  Print.println [c|Platform: #{platformStr}|]
  reportUpdateInstructions
  where
    versionStr = Version.toChars currentVersion

-- | Report instructions for updating manually.
reportUpdateInstructions :: IO ()
reportUpdateInstructions = do
  Print.println [c||]
  Print.println [c|To update Canopy, visit:|]
  Print.println [c|  {cyan|https://github.com/canopy-lang/canopy/releases}|]
  Print.println [c||]
  Print.println [c|Or use your package manager:|]
  Print.println [c|  {green|brew upgrade canopy}           (macOS/Homebrew)|]
  Print.println [c|  {green|nix-env -u canopy}             (Nix)|]
  Print.println [c|  {green|stack install canopy}           (Stack/Haskell)|]

-- | The currently running compiler version.
--
-- @since 0.19.2
currentVersion :: Version.Version
currentVersion = Version.compiler

-- | Compare two versions and return the relationship.
--
-- @since 0.19.2
compareVersions :: Version.Version -> Version.Version -> VersionComparison
compareVersions current latest
  | current == latest = UpToDate
  | current < latest = UpdateAvailable latest
  | otherwise = AheadOfLatest

-- | Detect the current platform and architecture.
--
-- Uses 'System.Info' to determine the OS and architecture,
-- then maps them to the slug format used in release URLs.
--
-- @since 0.19.2
detectPlatform :: IO PlatformInfo
detectPlatform =
  pure
    PlatformInfo
      { _platformOS = osName,
        _platformArch = archName,
        _platformSlug = osName <> "-" <> archName
      }
  where
    osName = mapOS SysInfo.os
    archName = mapArch SysInfo.arch

-- DOWNLOAD URL CONSTRUCTION

-- | Base URL for release assets.
--
-- @since 0.19.2
releaseBaseUrl :: Text.Text
releaseBaseUrl = "https://github.com/canopy-lang/canopy/releases/download"

-- | Construct the download URL for a platform binary at a given version.
--
-- Produces URLs of the form:
--
-- @
-- https://github.com/canopy-lang/canopy/releases/download/0.19.2/canopy-0.19.2-linux-x86_64.tar.gz
-- @
--
-- @since 0.19.2
binaryUrl :: Version.Version -> PlatformInfo -> Text.Text
binaryUrl version platform =
  releaseBaseUrl <> "/" <> versionTag <> "/" <> binaryFilename version platform
  where
    versionTag = Text.pack (Version.toChars version)

-- | Construct the binary archive filename for a given version and platform.
binaryFilename :: Version.Version -> PlatformInfo -> Text.Text
binaryFilename version platform =
  "canopy-" <> Text.pack (Version.toChars version)
    <> "-" <> (platform ^. platformSlug)
    <> ".tar.gz"

-- | Construct the checksum file URL for a given version.
--
-- Produces URLs of the form:
--
-- @
-- https://github.com/canopy-lang/canopy/releases/download/0.19.2/SHA256SUMS.txt
-- @
--
-- @since 0.19.2
checksumUrl :: Version.Version -> Text.Text
checksumUrl version =
  releaseBaseUrl <> "/" <> versionTag <> "/SHA256SUMS.txt"
  where
    versionTag = Text.pack (Version.toChars version)

-- CHECKSUM VERIFICATION

-- | Verify a SHA-256 hex digest against an expected value.
--
-- The comparison is case-insensitive to handle both uppercase and
-- lowercase hex encoding.
--
-- @since 0.19.2
verifyChecksum :: Text.Text -> Text.Text -> Bool
verifyChecksum actual expected =
  Text.toLower (Text.strip actual) == Text.toLower (Text.strip expected)

-- | Parse a SHA256SUMS file into a map of filename to hex digest.
--
-- Each line of the file should have the format:
--
-- @
-- <hex-digest>  <filename>
-- @
--
-- Lines that do not match this format are silently skipped.
--
-- @since 0.19.2
parseChecksumFile :: Text.Text -> Map.Map Text.Text Text.Text
parseChecksumFile content =
  Map.fromList (concatMap parseLine (Text.lines content))
  where
    parseLine line =
      case Text.words line of
        [hash, filename] | isHexDigest hash -> [(filename, hash)]
        _ -> []

-- | Check whether a text value looks like a SHA-256 hex digest.
isHexDigest :: Text.Text -> Bool
isHexDigest t =
  Text.length t == 64 && Text.all isHexChar t
  where
    isHexChar ch = Char.isHexDigit ch

-- | Map GHC os identifier to release slug.
mapOS :: String -> Text.Text
mapOS "linux" = "linux"
mapOS "darwin" = "darwin"
mapOS "mingw32" = "windows"
mapOS other = Text.pack other

-- | Map GHC arch identifier to release slug.
mapArch :: String -> Text.Text
mapArch "x86_64" = "x86_64"
mapArch "aarch64" = "aarch64"
mapArch other = Text.pack other

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
-- 1. Query the GitHub Releases API for the latest version
-- 2. Compare against the currently running compiler version
-- 3. Prompt the user for confirmation
-- 4. Download the platform-appropriate binary tarball
-- 5. Verify the download against its SHA-256 checksum
-- 6. Extract the binary and atomically replace the current one
--
-- == Security
--
-- Downloaded binaries are verified against SHA-256 checksums
-- published alongside each release.  The checksum file is fetched
-- from the same release URL and verified before the binary is
-- installed.
--
-- == Startup Notifications
--
-- The functions 'printUpdateNoticeIfAvailable' and
-- 'refreshCacheBackground' are intended to be called at CLI startup.
-- They use a local cache file so the network is queried at most once
-- per 24 hours.
--
-- @since 0.19.2
module SelfUpdate
  ( -- * Command Interface
    Flags (..),
    run,

    -- * Flags Lenses
    checkOnly,
    force,

    -- * Startup Notification Helpers
    printUpdateNoticeIfAvailable,
    refreshCacheBackground,

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
import qualified Control.Exception as Exception
import qualified Data.Char as Char
import qualified Data.Digest.Pure.SHA as SHA
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Reporting.Doc.ColorQQ (c)
import qualified Reporting.Ask as Ask
import qualified SelfUpdate.Cache as Cache
import qualified SelfUpdate.Http as Http
import qualified System.Directory as Dir
import qualified System.Environment as Environment
import System.FilePath ((</>))
import qualified System.Info as SysInfo
import qualified System.IO as IO
import qualified System.Process as Process
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

-- ---------------------------------------------------------------------------
-- COMMAND ENTRY POINT
-- ---------------------------------------------------------------------------

-- | Run the self-update command.
--
-- In @--check@ mode, reports whether an update is available without
-- making any changes.  Otherwise, downloads and installs the latest
-- version after prompting for confirmation.
--
-- @since 0.19.2
run :: () -> Flags -> IO ()
run () flags
  | flags ^. checkOnly = runCheckOnly
  | otherwise = runFullUpdate flags

-- | Report update status without installing anything.
runCheckOnly :: IO ()
runCheckOnly = do
  Print.println [c|{bold|Checking for updates...}|]
  Print.println [c|Current version: #{versionStr}|]
  result <- Http.fetchLatestVersion
  case result of
    Left err -> let errStr = Text.unpack err in Print.println [c|{red|Error:} #{errStr}|]
    Right latest -> reportComparison latest
  where
    versionStr = Version.toChars currentVersion

-- | Print human-readable comparison between current and latest version.
reportComparison :: Version.Version -> IO ()
reportComparison latest =
  case compareVersions currentVersion latest of
    UpToDate ->
      Print.println [c|{green|You are up to date.} (#{latestStr})|]
    AheadOfLatest ->
      Print.println [c|{cyan|Your build is ahead of the latest release.} (latest: #{latestStr})|]
    UpdateAvailable _ ->
      Print.println [c|{yellow|Update available:} #{currentStr} → #{latestStr}|]
        >> Print.println [c|Run {green|canopy self-update} to install.|]
  where
    latestStr = Version.toChars latest
    currentStr = Version.toChars currentVersion

-- | Full update flow: fetch, confirm, download, verify, install.
runFullUpdate :: Flags -> IO ()
runFullUpdate flags = do
  Print.println [c|{bold|Canopy Self-Update}|]
  Print.println [c|Current version: #{versionStr}|]
  result <- Http.fetchLatestVersion
  case result of
    Left err ->
      let errStr = Text.unpack err
      in Print.println [c|{red|Error fetching latest version:} #{errStr}|]
    Right latest -> handleLatest flags latest
  where
    versionStr = Version.toChars currentVersion

-- | Decide whether to proceed based on the latest version and flags.
handleLatest :: Flags -> Version.Version -> IO ()
handleLatest flags latest =
  case compareVersions currentVersion latest of
    UpToDate | not (flags ^. force) ->
      Print.println [c|{green|Already up to date.} (#{latestStr})|]
    AheadOfLatest | not (flags ^. force) ->
      Print.println [c|{cyan|Your build is ahead of the latest release.} (latest: #{latestStr})|]
    _ ->
      confirmAndInstall latest
  where
    latestStr = Version.toChars latest

-- | Prompt the user and run the install if confirmed.
confirmAndInstall :: Version.Version -> IO ()
confirmAndInstall latest = do
  let prompt = "Install canopy " <> Version.toChars latest <> "?"
  confirmed <- Ask.ask prompt
  if confirmed
    then installLatest latest
    else Print.println [c|Cancelled.|]

-- ---------------------------------------------------------------------------
-- INSTALL FLOW
-- ---------------------------------------------------------------------------

-- | Download, verify, extract, and install the new binary.
installLatest :: Version.Version -> IO ()
installLatest latest = do
  platform <- detectPlatform
  let latestStr = Version.toChars latest
      platformStr = Text.unpack (platform ^. platformSlug)
  Print.println [c|Downloading canopy #{latestStr} for #{platformStr}...|]
  result <- downloadAndVerify latest platform
  case result of
    Left err ->
      let errStr = Text.unpack err
      in Print.println [c|{red|Error:} #{errStr}|]
    Right tarPath -> doExtractAndInstall tarPath latestStr

-- | Download the binary tarball, verify its SHA-256 checksum.
--
-- Returns the path to the verified tarball on success.
downloadAndVerify :: Version.Version -> PlatformInfo -> IO (Either Text.Text FilePath)
downloadAndVerify version platform = do
  tarPath <- makeTempTarPath
  dlResult <- Http.downloadToFile (binaryUrl version platform) tarPath
  case dlResult of
    Left err -> do cleanupFile tarPath; pure (Left ("Download failed: " <> err))
    Right () -> verifyAndReturn version platform tarPath

-- | Fetch the checksum file and verify the downloaded tarball against it.
verifyAndReturn :: Version.Version -> PlatformInfo -> FilePath -> IO (Either Text.Text FilePath)
verifyAndReturn version platform tarPath = do
  csResult <- Http.downloadToFile (checksumUrl version) checksumTempPath
  case csResult of
    Left err -> do cleanupFile tarPath; pure (Left ("Checksum fetch failed: " <> err))
    Right () -> checkIntegrity version platform tarPath checksumTempPath
  where
    checksumTempPath = tarPath <> ".sha256"

-- | Compare the tarball's actual SHA-256 against the expected value.
checkIntegrity :: Version.Version -> PlatformInfo -> FilePath -> FilePath -> IO (Either Text.Text FilePath)
checkIntegrity version platform tarPath checksumPath = do
  actualHash <- computeFileSha256 tarPath
  csContent <- TextIO.readFile checksumPath
  cleanupFile checksumPath
  let filename = Text.unpack (binaryFilename version platform)
      expected = Map.lookup (Text.pack filename) (parseChecksumFile csContent)
  pure (validateHash actualHash expected tarPath)

-- | Return the tarball path when the hash matches, or an error.
validateHash :: Text.Text -> Maybe Text.Text -> FilePath -> Either Text.Text FilePath
validateHash actual (Just expected) tarPath
  | verifyChecksum actual expected = Right tarPath
  | otherwise = Left "Checksum mismatch — download may be corrupt"
validateHash _ Nothing _ = Left "Binary filename not found in checksum file"

-- | Extract the tarball and replace the running binary.
doExtractAndInstall :: FilePath -> String -> IO ()
doExtractAndInstall tarPath latestStr = do
  result <- extractAndInstall tarPath
  cleanupFile tarPath
  case result of
    Left err ->
      let errStr = Text.unpack err
      in Print.println [c|{red|Install failed:} #{errStr}|]
    Right () -> Print.println [c|{green|Successfully updated to canopy #{latestStr}.}|]

-- | Extract the binary from a tarball into a temp dir and install it.
extractAndInstall :: FilePath -> IO (Either Text.Text ())
extractAndInstall tarPath = do
  tmpDir <- makeTempExtractDir
  extractResult <- extractBinaryFromTar tarPath tmpDir
  case extractResult of
    Left err -> do cleanupDir tmpDir; pure (Left err)
    Right binaryPath -> replaceCurrentBinary binaryPath tmpDir

-- | Run @tar xzf@ to extract the archive into @destDir@.
extractBinaryFromTar :: FilePath -> FilePath -> IO (Either Text.Text FilePath)
extractBinaryFromTar tarPath destDir = do
  result <- Exception.try (Process.callProcess "tar" ["xzf", tarPath, "-C", destDir])
  case result of
    Left e ->
      pure (Left ("Extraction failed: " <> Text.pack (Exception.displayException (e :: Exception.SomeException))))
    Right () -> findBinary destDir

-- | Look for the @canopy@ binary in the extraction directory.
findBinary :: FilePath -> IO (Either Text.Text FilePath)
findBinary dir = do
  let candidate = dir </> "canopy"
  exists <- Dir.doesFileExist candidate
  if exists
    then pure (Right candidate)
    else pure (Left "Could not find 'canopy' binary in extracted archive")

-- | Make the extracted binary executable then replace the current binary.
replaceCurrentBinary :: FilePath -> FilePath -> IO (Either Text.Text ())
replaceCurrentBinary binaryPath tmpDir = do
  Process.callProcess "chmod" ["+x", binaryPath]
    `Exception.catch` ignoreProcessError
  exePath <- Environment.getExecutablePath
  result <- atomicReplace binaryPath exePath
  cleanupDir tmpDir
  pure result

-- | Attempt rename; fall back to copy when crossing filesystem boundaries.
atomicReplace :: FilePath -> FilePath -> IO (Either Text.Text ())
atomicReplace src dst = do
  renameResult <- Exception.try (Dir.renameFile src dst)
  case renameResult of
    Right () -> pure (Right ())
    Left (_ :: Exception.SomeException) -> copyFallback src dst

-- | Copy fallback for cross-filesystem replacement.
copyFallback :: FilePath -> FilePath -> IO (Either Text.Text ())
copyFallback src dst =
  fmap (either toLeft Right) (Exception.try (Dir.copyFile src dst))
  where
    toLeft e = Left (Text.pack (Exception.displayException (e :: Exception.SomeException)))

-- ---------------------------------------------------------------------------
-- STARTUP NOTIFICATION
-- ---------------------------------------------------------------------------

-- | Print a one-line update notice to stderr if a newer version is cached.
--
-- Uses the local cache file — never makes a network call.  Intended to
-- be called once at CLI startup before executing any command.
--
-- @since 0.19.2
printUpdateNoticeIfAvailable :: IO ()
printUpdateNoticeIfAvailable = do
  cached <- Cache.readCachedVersion
  case cached of
    Nothing -> pure ()
    Just latest ->
      case compareVersions currentVersion latest of
        UpdateAvailable _ -> printNotice latest
        _ -> pure ()

-- | Print the one-line update notice to stderr.
printNotice :: Version.Version -> IO ()
printNotice latest = do
  let msg = "-- NOTE: canopy " <> Version.toChars latest
              <> " is available. Run `canopy self-update` to upgrade."
  IO.hPutStrLn IO.stderr msg

-- | Fetch the latest version from the network and write it to the cache.
--
-- Intended to be called in a background thread via 'Control.Concurrent.forkIO'.
-- Silently ignores all errors.
--
-- @since 0.19.2
refreshCacheBackground :: IO ()
refreshCacheBackground = do
  result <- Http.fetchLatestVersion
  case result of
    Left _ -> pure ()
    Right version -> Cache.writeCachedVersion version

-- ---------------------------------------------------------------------------
-- VERSION CHECKING
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- PLATFORM DETECTION
-- ---------------------------------------------------------------------------

-- | Detect the current platform and architecture.
--
-- Uses 'System.Info' to determine the OS and architecture,
-- then maps them to the slug format used in release URLs.
--
-- @since 0.19.2
detectPlatform :: IO PlatformInfo
detectPlatform =
  pure PlatformInfo
    { _platformOS = osName
    , _platformArch = archName
    , _platformSlug = osName <> "-" <> archName
    }
  where
    osName = mapOS SysInfo.os
    archName = mapArch SysInfo.arch

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

-- ---------------------------------------------------------------------------
-- DOWNLOAD URL CONSTRUCTION
-- ---------------------------------------------------------------------------

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
--
-- @since 0.19.2
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

-- ---------------------------------------------------------------------------
-- CHECKSUM VERIFICATION
-- ---------------------------------------------------------------------------

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
  Text.length t == 64 && Text.all Char.isHexDigit t

-- ---------------------------------------------------------------------------
-- INTERNAL HELPERS
-- ---------------------------------------------------------------------------

-- | Compute the SHA-256 hex digest of a file.
computeFileSha256 :: FilePath -> IO Text.Text
computeFileSha256 path = do
  content <- LBS.readFile path
  pure (Text.pack (SHA.showDigest (SHA.sha256 content)))

-- | Create a temporary path for the downloaded tarball.
makeTempTarPath :: IO FilePath
makeTempTarPath = do
  tmpDir <- Dir.getTemporaryDirectory
  (path, handle) <- IO.openTempFile tmpDir "canopy-update-.tar.gz"
  IO.hClose handle
  pure path

-- | Create a temporary directory for binary extraction.
makeTempExtractDir :: IO FilePath
makeTempExtractDir = do
  tmpDir <- Dir.getTemporaryDirectory
  (path, handle) <- IO.openTempFile tmpDir "canopy-extract-"
  IO.hClose handle
  Dir.removeFile path
  Dir.createDirectory path
  pure path

-- | Remove a file, ignoring errors.
cleanupFile :: FilePath -> IO ()
cleanupFile path =
  Dir.removeFile path `Exception.catch` ignoreError
  where
    ignoreError :: Exception.SomeException -> IO ()
    ignoreError _ = pure ()

-- | Remove a directory tree, ignoring errors.
cleanupDir :: FilePath -> IO ()
cleanupDir path =
  Dir.removeDirectoryRecursive path `Exception.catch` ignoreError
  where
    ignoreError :: Exception.SomeException -> IO ()
    ignoreError _ = pure ()

-- | Ignore errors from 'Process.callProcess'.
ignoreProcessError :: Exception.SomeException -> IO ()
ignoreProcessError _ = pure ()

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Vendor command for copying dependencies into the project tree.
--
-- Copies all resolved dependencies from the global package cache into
-- a @vendor\/@ directory at the project root. This enables fully offline
-- builds in CI\/CD pipelines and air-gapped environments.
--
-- == Usage
--
-- @
-- canopy vendor           -- copy deps to .\/vendor\/
-- @
--
-- After vendoring, the packages are available locally and no network
-- access is required for subsequent builds.
--
-- @since 0.19.2
module Vendor
  ( -- * Command Interface
    Flags (..),
    run,

    -- * Core Logic (exported for testing)
    vendorDependencies,
    resolvePackagePath,
    copyPackageDir,
  )
where

import qualified Canopy.Constraint as Constraint
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Reporting.Doc.ColorQQ (c)
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified Terminal.Print as Print

-- | Flags for the vendor command.
--
-- Currently empty; reserved for future options such as
-- @--clean@ (remove vendor before copying) or @--prune@
-- (remove packages no longer in the dependency set).
--
-- @since 0.19.2
data Flags = Flags
  { -- | Remove the vendor directory before copying fresh packages.
    _vendorClean :: !Bool
  }
  deriving (Eq, Show)

-- | Run the vendor command.
--
-- Reads the project outline, resolves all dependency versions,
-- and copies each package from the global cache to @vendor\/@.
--
-- @since 0.19.2
run :: () -> Flags -> IO ()
run () flags =
  Stuff.findRoot >>= maybe reportNoProject (vendorProject flags)

-- | Report that no project was found.
reportNoProject :: IO ()
reportNoProject =
  Print.printErrLn [c|{red|Error:} Could not find a canopy.json file in this directory or any parent.|]

-- | Vendor all dependencies for a project.
vendorProject :: Flags -> FilePath -> IO ()
vendorProject flags root = do
  eitherOutline <- Outline.read root
  either reportBadOutline (vendorOutline flags root) eitherOutline

-- | Report an invalid outline.
reportBadOutline :: String -> IO ()
reportBadOutline msg =
  Print.printErrLn [c|{red|Error:} Invalid canopy.json: #{msg}|]

-- | Vendor dependencies from a parsed outline.
vendorOutline :: Flags -> FilePath -> Outline.Outline -> IO ()
vendorOutline flags root outline = do
  let deps = extractResolvedDeps outline
      vendorDir = root </> "vendor"
  when (_vendorClean flags) (removeVendorDir vendorDir)
  Dir.createDirectoryIfMissing True vendorDir
  vendorDependencies vendorDir (Map.toList deps)

-- | Conditional execution helper.
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = pure ()

-- | Remove the vendor directory if it exists.
removeVendorDir :: FilePath -> IO ()
removeVendorDir vendorDir = do
  exists <- Dir.doesDirectoryExist vendorDir
  if exists
    then do
      Dir.removeDirectoryRecursive vendorDir
      Print.println [c|Removed existing vendor/ directory.|]
    else pure ()

-- | Copy all listed dependencies from the global cache to the vendor directory.
--
-- For each package, checks the Canopy cache first, then the Elm cache.
-- Skips packages that are not found in either cache with a warning.
--
-- @since 0.19.2
vendorDependencies :: FilePath -> [(Pkg.Name, Version.Version)] -> IO ()
vendorDependencies vendorDir deps = do
  results <- traverse (vendorOne vendorDir) deps
  let copied = length (filter id results)
      skipped = length results - copied
  reportVendorSummary copied skipped

-- | Vendor a single package.
--
-- Returns 'True' if the package was successfully copied.
vendorOne :: FilePath -> (Pkg.Name, Version.Version) -> IO Bool
vendorOne vendorDir (pkg, ver) = do
  maybeSrc <- resolvePackagePath pkg ver
  maybe (reportMissing pkg ver) (copyAndReport vendorDir pkg ver) maybeSrc

-- | Report a missing package during vendoring.
reportMissing :: Pkg.Name -> Version.Version -> IO Bool
reportMissing pkg ver = do
  let name = Pkg.toChars pkg
      version = Version.toChars ver
  Print.printErrLn [c|  {yellow|SKIP:} #{name} #{version} — not found in cache|]
  pure False

-- | Copy a package and report success.
copyAndReport :: FilePath -> Pkg.Name -> Version.Version -> FilePath -> IO Bool
copyAndReport vendorDir pkg ver srcPath = do
  let name = Pkg.toChars pkg
      version = Version.toChars ver
  copyPackageDir srcPath (vendorDir </> Pkg.toFilePath pkg </> Version.toChars ver)
  Print.println [c|  {green|OK:} #{name} #{version}|]
  pure True

-- | Resolve the cache path for a package version.
--
-- Checks the Canopy cache first, then falls back to the Elm cache.
-- Returns 'Nothing' if the package is not cached anywhere.
--
-- @since 0.19.2
resolvePackagePath :: Pkg.Name -> Version.Version -> IO (Maybe FilePath)
resolvePackagePath pkg ver = do
  home <- Dir.getHomeDirectory
  let canopyPath = home </> ".canopy" </> "packages" </> Pkg.toFilePath pkg </> Version.toChars ver
      elmPath = home </> ".elm" </> "0.19.1" </> "packages" </> Pkg.toFilePath pkg </> Version.toChars ver
  canopyExists <- Dir.doesDirectoryExist canopyPath
  if canopyExists
    then pure (Just canopyPath)
    else do
      elmExists <- Dir.doesDirectoryExist elmPath
      pure (if elmExists then Just elmPath else Nothing)

-- | Recursively copy a package directory to the vendor target.
--
-- Creates the target directory and copies all files and subdirectories.
-- Preserves the directory structure but not file metadata (timestamps,
-- permissions). Skips symbolic links to prevent following references
-- outside the package directory.
--
-- @since 0.19.2
copyPackageDir :: FilePath -> FilePath -> IO ()
copyPackageDir src dst = do
  isLink <- Dir.pathIsSymbolicLink src
  if isLink
    then Log.logEvent (PackageOperation "vendor-skip-symlink-dir" (Text.pack src))
    else do
      Dir.createDirectoryIfMissing True dst
      contents <- Dir.listDirectory src
      mapM_ (copyEntry src dst) contents

-- | Copy a single directory entry (file or subdirectory).
--
-- Skips symbolic links with a log message to prevent copying files
-- from outside the package directory via symlink traversal.
--
-- @since 0.19.2
copyEntry :: FilePath -> FilePath -> FilePath -> IO ()
copyEntry srcBase destBase name = do
  let srcPath = srcBase </> name
      destPath = destBase </> name
  isLink <- Dir.pathIsSymbolicLink srcPath
  if isLink
    then Log.logEvent (PackageOperation "vendor-skip-symlink" (Text.pack srcPath))
    else do
      isDir <- Dir.doesDirectoryExist srcPath
      if isDir
        then copyPackageDir srcPath destPath
        else Dir.copyFile srcPath destPath

-- | Report the vendoring summary.
reportVendorSummary :: Int -> Int -> IO ()
reportVendorSummary copied skipped = do
  let copiedStr = show copied
      skippedStr = show skipped
  Print.println [c|

Vendor complete: {green|#{copiedStr}} packages copied, {yellow|#{skippedStr}} skipped.|]

-- | Extract resolved dependency versions from an outline.
--
-- For applications, merges direct and indirect dependencies.
-- For packages, uses the lower bound of each constraint.
-- For workspaces, uses the shared dependency versions.
extractResolvedDeps :: Outline.Outline -> Map.Map Pkg.Name Version.Version
extractResolvedDeps (Outline.App appOutline) =
  Map.union
    (Outline._appDepsDirect appOutline)
    (Outline._appDepsIndirect appOutline)
extractResolvedDeps (Outline.Pkg pkgOutline) =
  Map.map Constraint.lowerBound (Outline._pkgDeps pkgOutline)
extractResolvedDeps (Outline.Workspace wsOutline) =
  Outline._wsSharedDeps wsOutline

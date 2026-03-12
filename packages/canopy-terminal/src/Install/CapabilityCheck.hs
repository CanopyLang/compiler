{-# LANGUAGE OverloadedStrings #-}

-- | Post-install capability detection for newly added packages.
--
-- After a package is installed, scans its FFI JavaScript files for
-- @capability annotations and warns the user about any capabilities
-- the package requires. This ensures developers are aware of the
-- security implications of their dependencies.
--
-- @since 0.20.1
module Install.CapabilityCheck
  ( -- * Capability Detection
    warnNewCapabilities,
  )
where

import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified FFI.Capability as Capability
import qualified FFI.Types as FFI.Types
import qualified Foreign.FFI as FFI
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.FilePath as FilePath
import qualified System.IO as IO

-- | Warn about capabilities required by newly installed packages.
--
-- Compares old and new outlines to find newly added or upgraded packages,
-- then scans their FFI files for @capability annotations. Prints a
-- warning for each package that requires capabilities.
--
-- @since 0.20.1
warnNewCapabilities :: Outline.Outline -> Outline.Outline -> IO ()
warnNewCapabilities oldOutline newOutline =
  mapM_ checkPackageCapabilities (findChangedPackages oldOutline newOutline)

-- | Find packages that were added or had their version changed.
findChangedPackages :: Outline.Outline -> Outline.Outline -> [(Pkg.Name, Maybe Version.Version, Version.Version)]
findChangedPackages oldOutline newOutline =
  concatMap (findChanged oldDeps) (Map.toList newDeps)
  where
    oldDeps = extractDeps oldOutline
    newDeps = extractDeps newOutline

-- | Identify a single changed dependency.
findChanged :: Map.Map Pkg.Name Version.Version -> (Pkg.Name, Version.Version) -> [(Pkg.Name, Maybe Version.Version, Version.Version)]
findChanged oldDeps (pkg, newVer) =
  case Map.lookup pkg oldDeps of
    Nothing -> [(pkg, Nothing, newVer)]
    Just oldVer
      | oldVer /= newVer -> [(pkg, Just oldVer, newVer)]
      | otherwise -> []

-- | Extract resolved dependency versions from an outline.
extractDeps :: Outline.Outline -> Map.Map Pkg.Name Version.Version
extractDeps (Outline.App app) =
  Map.union (Outline._appDepsDirect app) (Outline._appDepsIndirect app)
extractDeps (Outline.Pkg _) = Map.empty
extractDeps (Outline.Workspace ws) = Outline._wsSharedDeps ws

-- | Check a single package for capability requirements.
checkPackageCapabilities :: (Pkg.Name, Maybe Version.Version, Version.Version) -> IO ()
checkPackageCapabilities (pkg, oldVer, newVer) = do
  caps <- scanPackageCapabilities pkg newVer
  if Set.null caps
    then pure ()
    else printCapabilityWarning pkg oldVer newVer caps

-- | Scan a package's cached FFI files for capability annotations.
scanPackageCapabilities :: Pkg.Name -> Version.Version -> IO (Set Text)
scanPackageCapabilities pkg ver = do
  srcDir <- getPackageSrcDir pkg ver
  exists <- Dir.doesDirectoryExist srcDir
  if exists
    then scanDirectoryForCapabilities srcDir
    else pure Set.empty

-- | Get the source directory for a cached package.
getPackageSrcDir :: Pkg.Name -> Version.Version -> IO FilePath
getPackageSrcDir pkg ver = do
  home <- Dir.getHomeDirectory
  pure (home </> ".canopy" </> "packages" </> Pkg.toChars pkg </> Version.toChars ver </> "src")

-- | Scan a directory tree for JS files with capability annotations.
scanDirectoryForCapabilities :: FilePath -> IO (Set Text)
scanDirectoryForCapabilities dir = do
  entries <- listJsFiles dir
  caps <- traverse scanFileCapabilities entries
  pure (Set.unions caps)

-- | Recursively list all .js files in a directory.
listJsFiles :: FilePath -> IO [FilePath]
listJsFiles dir = do
  contents <- Dir.listDirectory dir
  results <- traverse (processEntry dir) contents
  pure (concat results)

-- | Process a single directory entry for JS file listing.
processEntry :: FilePath -> FilePath -> IO [FilePath]
processEntry dir entry = do
  let fullPath = dir </> entry
  isDir <- Dir.doesDirectoryExist fullPath
  if isDir
    then listJsFiles fullPath
    else pure [fullPath | FilePath.takeExtension entry == ".js"]

-- | Scan a single JS file for capability annotations.
scanFileCapabilities :: FilePath -> IO (Set Text)
scanFileCapabilities path = do
  result <- FFI.parseJSDocFromFile path
  pure (either (const Set.empty) extractCapNames result)

-- | Extract capability names from parsed JSDoc functions.
extractCapNames :: [FFI.JSDocFunction] -> Set Text
extractCapNames = Set.fromList . concatMap extractFromFunc
  where
    extractFromFunc func =
      maybe [] extractNames (FFI.jsDocFuncCapabilities func)

-- | Extract text names from a capability constraint.
extractNames :: Capability.CapabilityConstraint -> [Text]
extractNames Capability.UserActivationRequired = ["user-activation"]
extractNames (Capability.PermissionRequired perm) = [FFI.Types.unPermissionName perm]
extractNames (Capability.InitializationRequired res) = [FFI.Types.unResourceName res]
extractNames (Capability.AvailabilityRequired name) = [name]
extractNames (Capability.MultipleConstraints cs) = concatMap extractNames cs

-- | Print a warning about capability requirements.
printCapabilityWarning :: Pkg.Name -> Maybe Version.Version -> Version.Version -> Set Text -> IO ()
printCapabilityWarning pkg oldVer newVer caps = do
  IO.hPutStrLn IO.stderr header
  IO.hPutStrLn IO.stderr ("  " <> Text.unpack capList)
  IO.hPutStrLn IO.stderr "  Ensure these are declared in your canopy.json capabilities field."
  where
    pkgStr = Pkg.toChars pkg
    verStr = Version.toChars newVer
    capList = Text.intercalate ", " (Set.toList caps)
    header = case oldVer of
      Nothing -> "Warning: New package " <> pkgStr <> " " <> verStr <> " requires capabilities:"
      Just old ->
        "Warning: Package " <> pkgStr <> " " <> Version.toChars old <> " -> " <> verStr <> " now requires capabilities:"

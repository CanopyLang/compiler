{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Pure project details and configuration.
--
-- Loads and manages project configuration (canopy.json) without STM/MVar.
-- Provides pure functional interface to project metadata.
--
-- @since 0.19.1
module Canopy.Details
  ( -- * Details Type
    Details (..),
    ValidOutline (..),
    PkgName,

    -- * Loading
    load,
    loadForReactorTH,
    verifyInstall,

    -- * Version Checking
    checkCompilerVersion,
    VersionCheck (..),

    -- * Utilities
    dummyPkgName,

    -- * Lenses
    detailsTime,
    detailsOutline,
    detailsPlatform,
    detailsRoot,
    detailsSrcDirs,
    detailsDeps,
  )
where

import qualified Canopy.Constraint as Constraint
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Lens (makeLenses)
import qualified Canopy.Data.Utf8 as Utf8
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Time as Time
import qualified Reporting
import System.FilePath ((</>))

-- | Re-export package name type for convenience.
type PkgName = Pkg.Name

-- | Dummy package name for applications.
-- NOTE: Must match Pkg.dummyName in canopy-core to ensure consistent JS naming.
dummyPkgName :: Pkg.Name
dummyPkgName = Pkg.Name (Utf8.fromChars "author") (Utf8.fromChars "project")

-- | Project details and configuration (pure, no MVar).
data Details = Details
  { _detailsTime :: !Time.UTCTime,
    _detailsOutline :: !ValidOutline,
    _detailsPlatform :: !FilePath,
    _detailsRoot :: !FilePath,
    _detailsSrcDirs :: ![FilePath],
    _detailsDeps :: !(Map Pkg.Name ())
  }
  deriving (Show)

-- | Validated outline (App or Pkg).
data ValidOutline
  = ValidApp Outline.AppOutline
  | ValidPkg Pkg.Name [ModuleName.Raw] [FilePath]
  deriving (Show)

makeLenses ''Details

-- | Load project details from root directory (pure, no MVar).
load ::
  Reporting.Style ->
  () -> -- BackgroundWriter scope (synchronous in Canopy)
  FilePath ->
  IO (Either FilePath Details)
load _style _scope root = do
  eitherOutline <- Outline.read root
  case eitherOutline of
    Left _ -> pure (Left root)
    Right outline -> do
      time <- Time.getCurrentTime
      let details =
            Details
              { _detailsTime = time,
                _detailsOutline = validateOutline outline,
                _detailsPlatform = root </> ".canopy",
                _detailsRoot = root,
                _detailsSrcDirs = getSrcDirs outline,
                _detailsDeps = extractDeps outline
              }
      pure (Right details)

-- | Validate outline structure.
validateOutline :: Outline.Outline -> ValidOutline
validateOutline outline =
  case outline of
    Outline.App appOutline -> ValidApp appOutline
    Outline.Pkg (Outline.PkgOutline pkg _ _ _ exposed _ _ _) ->
      ValidPkg pkg (getExposedList exposed) []

-- | Get exposed modules list from either list or dict format.
getExposedList :: Outline.Exposed -> [ModuleName.Raw]
getExposedList = Outline.flattenExposed

-- | Get source directories from outline.
getSrcDirs :: Outline.Outline -> [FilePath]
getSrcDirs outline =
  case outline of
    Outline.App (Outline.AppOutline _ srcDirs _ _ _ _ _) ->
      map toAbsPath srcDirs
    Outline.Pkg _ -> ["src"]
  where
    toAbsPath (Outline.AbsoluteSrcDir dir) = dir
    toAbsPath (Outline.RelativeSrcDir dir) = dir

-- | Extract dependency package names from the project outline.
extractDeps :: Outline.Outline -> Map Pkg.Name ()
extractDeps outline =
  case outline of
    Outline.App appOutline ->
      Map.map (const ()) (Outline._appDepsDirect appOutline)
        `Map.union` Map.map (const ()) (Outline._appDepsIndirect appOutline)
    Outline.Pkg pkgOutline ->
      Map.map (const ()) (Outline._pkgDeps pkgOutline)

-- | Load details for Reactor (development server).
--
-- Simplified loading for the development server, using Template Haskell hints.
loadForReactorTH ::
  Reporting.Style ->
  FilePath ->
  IO (Either FilePath Details)
loadForReactorTH style root = load style () root

-- | Verify installation by loading and validating details from new outline.
--
-- Attempts to create Details from the new outline to ensure the installation
-- is valid. Returns error message if verification fails.
--
-- @since 0.19.1
verifyInstall ::
  () -> -- BackgroundWriter scope (synchronous in Canopy)
  FilePath ->
  a -> -- Solver environment (unused in current implementation)
  Outline.Outline ->
  IO (Either String ())
verifyInstall _scope root _env newOutline = do
  time <- Time.getCurrentTime
  let validOutline = validateOutline newOutline
      srcDirs = getSrcDirs newOutline
      details =
        Details
          { _detailsTime = time,
            _detailsOutline = validOutline,
            _detailsPlatform = root </> ".canopy",
            _detailsRoot = root,
            _detailsSrcDirs = srcDirs,
            _detailsDeps = Map.empty
          }
  pure (verifyDetailsStructure details)
  where
    verifyDetailsStructure :: Details -> Either String ()
    verifyDetailsStructure details
      | null (_detailsSrcDirs details) = Left "No source directories found"
      | otherwise = Right ()

-- | Result of a compiler version compatibility check.
--
-- @since 0.19.2
data VersionCheck
  = -- | The project's Canopy version requirement is satisfied.
    VersionOk
  | -- | The compiler version does not match the project's requirement.
    --
    -- Carries the required version description and the running compiler version.
    VersionMismatch !String !String
  deriving (Eq, Show)

-- | Check whether the running compiler satisfies the project's
-- version requirement.
--
-- For application outlines, checks that the compiler's major and minor
-- version match the project's @canopy-version@ field. Patch differences
-- are allowed since they are backward-compatible.
--
-- For package outlines, uses the constraint range in @canopy@ to
-- determine compatibility via 'Constraint.goodCanopy'.
--
-- @since 0.19.2
checkCompilerVersion :: Outline.Outline -> VersionCheck
checkCompilerVersion (Outline.App appOutline) =
  checkAppVersion (Outline._appCanopy appOutline)
checkCompilerVersion (Outline.Pkg pkgOutline) =
  checkPkgVersion (Outline._pkgCanopy pkgOutline)

-- | Check an app's required version against the compiler.
--
-- Applications pin to a specific version. We consider it compatible
-- if the major and minor versions match (patch can differ).
--
-- @since 0.19.2
checkAppVersion :: Version.Version -> VersionCheck
checkAppVersion requiredVersion
  | isCompatible = VersionOk
  | otherwise =
      VersionMismatch
        (Version.toChars requiredVersion)
        (Version.toChars Version.compiler)
  where
    isCompatible =
      Version._major requiredVersion == Version._major Version.compiler
        && Version._minor requiredVersion == Version._minor Version.compiler

-- | Check a package's constraint against the compiler.
--
-- Packages specify a version range. Uses 'Constraint.goodCanopy'
-- which checks 'Constraint.satisfies' against 'Version.compiler'.
--
-- @since 0.19.2
checkPkgVersion :: Constraint.Constraint -> VersionCheck
checkPkgVersion constraint
  | Constraint.goodCanopy constraint = VersionOk
  | otherwise =
      VersionMismatch
        (Constraint.toChars constraint)
        (Version.toChars Version.compiler)

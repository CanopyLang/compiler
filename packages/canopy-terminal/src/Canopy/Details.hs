{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

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

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import Control.Lens (makeLenses)
import qualified Data.Utf8 as Utf8
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Time as Time
import qualified Reporting
import System.FilePath ((</>))

-- | Re-export package name type for convenience.
type PkgName = Pkg.Name

-- | Dummy package name for applications.
dummyPkgName :: Pkg.Name
dummyPkgName = Pkg.Name (Utf8.fromChars "user") (Utf8.fromChars "project")

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
  () -> -- Scope placeholder (no BackgroundWriter)
  FilePath ->
  IO (Either FilePath Details)
load _style _scope root = do
  maybeOutline <- Outline.read root
  case maybeOutline of
    Nothing -> pure (Left root)
    Just outline -> do
      time <- Time.getCurrentTime
      let details =
            Details
              { _detailsTime = time,
                _detailsOutline = validateOutline outline,
                _detailsPlatform = root </> ".canopy",
                _detailsRoot = root,
                _detailsSrcDirs = getSrcDirs outline,
                _detailsDeps = Map.empty -- TODO: load dependencies
              }
      pure (Right details)

-- | Validate outline structure.
validateOutline :: Outline.Outline -> ValidOutline
validateOutline outline =
  case outline of
    Outline.App appOutline -> ValidApp appOutline
    Outline.Pkg (Outline.PkgOutline pkg _ _ _ exposed _ _ _) ->
      ValidPkg pkg (getExposedList exposed) []

-- | Get exposed modules list.
getExposedList :: Outline.Exposed -> [ModuleName.Raw]
getExposedList exposed =
  case exposed of
    Outline.ExposedList mods -> mods
    Outline.ExposedDict _ -> [] -- TODO: handle dict

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
  () -> -- Scope placeholder (no BackgroundWriter)
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

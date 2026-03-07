{-# LANGUAGE OverloadedStrings #-}

-- | Dynamic kernel module discovery for the Canopy compiler.
--
-- This module provides functionality for discovering kernel modules by scanning
-- package directories rather than maintaining a hardcoded list. This makes the
-- compiler future-proof and allows new packages with kernel modules to work
-- without compiler updates.
--
-- === Architecture
--
-- Kernel modules are discovered by:
--
-- 1. Scanning package directories after extraction
-- 2. Finding all .js files in src/Elm/Kernel/ directories
-- 3. Recording discovered modules with metadata
-- 4. Storing in build artifacts (canopy-stuff/kernels.dat)
-- 5. Reading during compilation for JavaScript generation
--
-- === Discovery Process
--
-- When a package is extracted:
--
-- @
-- packageDir <- extractPackage archive
-- kernels <- discoverKernelModules packageName packageDir
-- updateKernelRegistry stuffDir packageName kernels
-- @
--
-- === Usage During Compilation
--
-- @
-- registry <- readKernelRegistry stuffDir
-- let jsCode = Generate.generate mode graph mains ffiInfos registry
-- @
--
-- @since 0.19.1
module Canopy.Kernel.Discovery
  ( -- * Discovery Types
    KernelModuleDiscovery (..),
    KernelRegistry,

    -- * Discovery Operations
    discoverKernelModules,
    discoverKernelModulesFromDir,

    -- * Registry Operations
    emptyRegistry,
    insertDiscoveries,
    lookupPackageKernels,
    lookupKernelModule,
    allDiscoveredKernels,

    -- * Persistence
    readKernelRegistry,
    writeKernelRegistry,
    getKernelRegistryPath,
  )
where

import qualified Canopy.Package as Pkg
import qualified Data.Binary as Binary
import qualified Data.ByteString as BS
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import System.FilePath ((</>))

-- | Information about a discovered kernel module.
--
-- Each discovered kernel module has metadata describing where it came from
-- and how it should be used during JavaScript generation.
data KernelModuleDiscovery = KernelModuleDiscovery
  { _discoveryModuleName :: !Name.Name,
    -- ^ Module name (e.g., "Kernel.List", "Kernel.Json")
    _discoveryPackage :: !Pkg.Name,
    -- ^ Source package (e.g., elm/core, elm/json)
    _discoveryJsPackage :: !Pkg.Name,
    -- ^ JavaScript runtime package (for imports)
    _discoveryHasDollarExport :: !Bool
    -- ^ Whether module has $ entry point (always True for .js kernels)
  }
  deriving (Eq, Show)

-- Binary instance for serialization
instance Binary.Binary KernelModuleDiscovery where
  put discovery = do
    Binary.put (_discoveryModuleName discovery)
    Binary.put (_discoveryPackage discovery)
    Binary.put (_discoveryJsPackage discovery)
    Binary.put (_discoveryHasDollarExport discovery)

  get = do
    moduleName <- Binary.get
    pkg <- Binary.get
    jsPkg <- Binary.get
    hasDollar <- Binary.get
    pure
      ( KernelModuleDiscovery
          { _discoveryModuleName = moduleName,
            _discoveryPackage = pkg,
            _discoveryJsPackage = jsPkg,
            _discoveryHasDollarExport = hasDollar
          }
      )

-- | Registry of all discovered kernel modules.
--
-- Maps package names to their discovered kernel modules.
-- This is the complete runtime registry built from scanning packages.
type KernelRegistry = Map.Map Pkg.Name [KernelModuleDiscovery]

-- | Empty kernel registry.
emptyRegistry :: KernelRegistry
emptyRegistry = Map.empty

-- | Insert discovered kernels for a package into the registry.
insertDiscoveries :: Pkg.Name -> [KernelModuleDiscovery] -> KernelRegistry -> KernelRegistry
insertDiscoveries = Map.insert

-- | Look up all kernel modules for a specific package.
lookupPackageKernels :: Pkg.Name -> KernelRegistry -> [KernelModuleDiscovery]
lookupPackageKernels pkg registry = Map.findWithDefault [] pkg registry

-- | Look up a specific kernel module across all packages.
lookupKernelModule :: Name.Name -> KernelRegistry -> Maybe KernelModuleDiscovery
lookupKernelModule moduleName registry =
  let allKernels = concatMap snd (Map.toList registry)
   in List.find (\k -> _discoveryModuleName k == moduleName) allKernels

-- | Get all discovered kernel modules across all packages.
allDiscoveredKernels :: KernelRegistry -> [KernelModuleDiscovery]
allDiscoveredKernels registry = concat (Map.elems registry)

-- | Discover kernel modules from a package directory.
--
-- Scans the package's src/Elm/Kernel/ directory for .js files and creates
-- discovery records for each found kernel module.
--
-- Packages with the @canopy@ author are skipped entirely — they use the
-- FFI system instead of kernel JS modules.
--
-- ==== Examples
--
-- >>> discoveries <- discoverKernelModules Pkg.core "/path/to/elm/core/1.0.5"
-- >>> map _discoveryModuleName discoveries
-- ["Kernel.Basics", "Kernel.List", "Kernel.Utils", ...]
--
-- ==== Discovery Rules
--
-- * Skips packages with author @canopy@ (use FFI instead)
-- * Only scans src/Elm/Kernel/ directory
-- * Only includes .js files (excluding .server.js variants)
-- * Module name is "Kernel." + base filename
-- * All discovered kernels have $ entry points
--
-- @since 0.19.1
discoverKernelModules :: Pkg.Name -> FilePath -> IO [KernelModuleDiscovery]
discoverKernelModules packageName packageDir
  | Pkg._author packageName == Pkg.canopy = pure []
  | otherwise = do
      let kernelDir = packageDir </> "src" </> "Elm" </> "Kernel"
      discoveries <- discoverKernelModulesFromDir kernelDir
      pure
        [ d
            { _discoveryPackage = packageName,
              _discoveryJsPackage = determineJsPackage packageName
            }
          | d <- discoveries
        ]

-- | Discover kernel modules from a specific Kernel/ directory.
--
-- Lower-level function that scans a directory and creates discovery records.
-- Does not set package information - that's done by 'discoverKernelModules'.
--
-- @since 0.19.1
discoverKernelModulesFromDir :: FilePath -> IO [KernelModuleDiscovery]
discoverKernelModulesFromDir kernelDir = do
  exists <- Dir.doesDirectoryExist kernelDir
  if exists
    then do
      files <- Dir.listDirectory kernelDir
      let jsFiles = filter isKernelJsFile files
          moduleNames = map filenameToModuleName jsFiles
      pure
        [ KernelModuleDiscovery
            { _discoveryModuleName = name,
              _discoveryPackage = Pkg.kernel, -- Default; caller may override
              _discoveryJsPackage = Pkg.core, -- Default; caller may override
              _discoveryHasDollarExport = True
            }
          | name <- moduleNames
        ]
    else pure []
  where
    isKernelJsFile :: FilePath -> Bool
    isKernelJsFile f =
      FP.takeExtension f == ".js"
        && not (".server.js" `List.isSuffixOf` f)

    filenameToModuleName :: FilePath -> Name.Name
    filenameToModuleName filename =
      let baseName = FP.takeBaseName filename
       in Name.fromChars ("Kernel." ++ baseName)

-- | Determine JavaScript package for a source package.
--
-- This encodes the mapping rules:
--   * canopy/kernel → elm/core
--   * elm/* packages → themselves
--   * Other packages → themselves
--
-- @since 0.19.1
determineJsPackage :: Pkg.Name -> Pkg.Name
determineJsPackage pkg
  | Pkg._author pkg == Pkg.canopy
      && Pkg._project pkg == Pkg._project Pkg.kernel =
      Pkg.core -- canopy/kernel maps to elm/core at runtime
  | otherwise = pkg -- Most packages map to themselves

-- | Get the path to the kernel registry file.
--
-- ==== Examples
--
-- >>> getKernelRegistryPath "/path/to/project/canopy-stuff"
-- "/path/to/project/canopy-stuff/0.19.1/kernels.dat"
--
-- @since 0.19.1
getKernelRegistryPath :: FilePath -> FilePath
getKernelRegistryPath stuffDir = stuffDir </> "0.19.1" </> "kernels.dat"

-- | Read kernel registry from disk.
--
-- Reads the binary-encoded registry from canopy-stuff/0.19.1/kernels.dat.
-- Returns Nothing if the file doesn't exist or cannot be decoded.
--
-- ==== Examples
--
-- >>> maybeRegistry <- readKernelRegistry "/path/to/project/canopy-stuff"
-- >>> case maybeRegistry of
-- ...   Just registry -> print (length (allDiscoveredKernels registry))
-- ...   Nothing -> putStrLn "No registry found"
--
-- @since 0.19.1
readKernelRegistry :: FilePath -> IO (Maybe KernelRegistry)
readKernelRegistry stuffDir = do
  let kernelsPath = getKernelRegistryPath stuffDir
  exists <- Dir.doesFileExist kernelsPath
  if exists
    then do
      bytes <- BS.readFile kernelsPath
      case Binary.decodeOrFail (BS.fromStrict bytes) of
        Right (_, _, registry) -> pure (Just registry)
        Left _ -> pure Nothing
    else pure Nothing

-- | Write kernel registry to disk.
--
-- Writes the binary-encoded registry to canopy-stuff/0.19.1/kernels.dat.
-- Creates parent directories if they don't exist.
--
-- ==== Examples
--
-- >>> registry <- discoverAllPackageKernels
-- >>> writeKernelRegistry "/path/to/project/canopy-stuff" registry
--
-- @since 0.19.1
writeKernelRegistry :: FilePath -> KernelRegistry -> IO ()
writeKernelRegistry stuffDir registry = do
  let kernelsPath = getKernelRegistryPath stuffDir
      kernelsDir = FP.takeDirectory kernelsPath
  Dir.createDirectoryIfMissing True kernelsDir
  BS.writeFile kernelsPath (BS.toStrict (Binary.encode registry))

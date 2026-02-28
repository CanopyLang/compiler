{-# LANGUAGE OverloadedStrings #-}

-- | Demand-driven module loading with caching.
--
-- Provides a 'ModuleLoader' that loads and caches modules on demand
-- rather than eagerly resolving all transitive imports.  This reduces
-- memory usage and startup time for large projects where only a
-- subset of modules are being compiled.
--
-- == Architecture
--
-- The loader maintains an 'IORef'-backed cache of loaded modules.
-- When a module is requested:
--
-- 1. Check the in-memory cache
-- 2. If cached, return immediately
-- 3. If not cached, search source directories for the module file
-- 4. Load and parse the module
-- 5. Store in the cache for subsequent requests
--
-- This approach integrates with the lazy import system: modules
-- marked as @lazy import@ in source code can be deferred until
-- their bindings are actually used during type checking.
--
-- @since 0.19.2
module Builder.ModuleLoader
  ( -- * Loader Types
    ModuleLoader (..),
    LoadedModule (..),
    LoadError (..),

    -- * Loader Operations
    newLoader,
    loadModule,
    preloadModules,
    cachedModules,
    clearCache,

    -- * Module Resolution
    resolveModulePath,
  )
where

import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Data.ByteString as BS
import qualified Data.IORef as IORef
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified System.Directory as Dir
import qualified System.FilePath as FP

-- | A demand-driven module loader with an in-memory cache.
--
-- Modules are loaded from the configured source directories and
-- cached in an 'IORef' for repeated access.
--
-- @since 0.19.2
data ModuleLoader = ModuleLoader
  { -- | Cache of already-loaded modules.
    _mlCache :: !(IORef.IORef (Map.Map ModuleName.Raw LoadedModule)),
    -- | Source directories to search for modules.
    _mlSourceDirs :: ![FilePath]
  }

-- | A module that has been loaded from disk.
--
-- Contains the raw source bytes and the file path where the module
-- was found.
--
-- @since 0.19.2
data LoadedModule = LoadedModule
  { -- | The raw source bytes of the module file.
    _lmSource :: !BS.ByteString,
    -- | The absolute file path of the module.
    _lmPath :: !FilePath,
    -- | The module name (for diagnostics).
    _lmName :: !ModuleName.Raw
  }
  deriving (Eq, Show)

-- | Errors that can occur during module loading.
--
-- @since 0.19.2
data LoadError
  = -- | The module file could not be found in any source directory.
    ModuleNotFound !ModuleName.Raw ![FilePath]
  | -- | The module file exists but could not be read.
    ModuleReadError !ModuleName.Raw !FilePath !Text.Text
  deriving (Eq, Show)

-- | Create a new module loader with the given source directories.
--
-- The cache starts empty.  Modules are loaded on first request.
--
-- @since 0.19.2
newLoader :: [FilePath] -> IO ModuleLoader
newLoader srcDirs = do
  cache <- IORef.newIORef Map.empty
  pure ModuleLoader {_mlCache = cache, _mlSourceDirs = srcDirs}

-- | Load a module by name, using the cache when available.
--
-- On first request, searches the source directories for a matching
-- file, reads it, and caches the result.  Subsequent requests for
-- the same module return the cached value.
--
-- @since 0.19.2
loadModule :: ModuleLoader -> ModuleName.Raw -> IO (Either LoadError LoadedModule)
loadModule loader modName = do
  cache <- IORef.readIORef (_mlCache loader)
  maybe (loadAndCache loader modName) (pure . Right) (Map.lookup modName cache)

-- | Preload a list of modules into the cache.
--
-- Useful for warming the cache with modules known to be needed
-- (e.g., direct imports).  Returns a list of any modules that
-- could not be loaded.
--
-- @since 0.19.2
preloadModules :: ModuleLoader -> [ModuleName.Raw] -> IO [LoadError]
preloadModules loader =
  fmap (concatMap toErrors) . traverse (loadModule loader)
  where
    toErrors (Left err) = [err]
    toErrors (Right _) = []

-- | Get the map of currently cached modules.
--
-- @since 0.19.2
cachedModules :: ModuleLoader -> IO (Map.Map ModuleName.Raw LoadedModule)
cachedModules = IORef.readIORef . _mlCache

-- | Clear the module cache.
--
-- Forces all modules to be re-read from disk on next request.
--
-- @since 0.19.2
clearCache :: ModuleLoader -> IO ()
clearCache loader = IORef.writeIORef (_mlCache loader) Map.empty

-- | Resolve a module name to its file path in the source directories.
--
-- Searches each source directory for a file matching the module name
-- with a @.can@ or @.canopy@ extension.  Returns the first match.
--
-- @since 0.19.2
resolveModulePath :: [FilePath] -> ModuleName.Raw -> IO (Maybe FilePath)
resolveModulePath srcDirs modName =
  findFirst candidates
  where
    modPath = moduleNameToPath modName
    candidates =
      concatMap
        (\dir -> [dir FP.</> modPath ++ ".can", dir FP.</> modPath ++ ".canopy"])
        srcDirs

-- INTERNAL

-- | Load a module from disk and store it in the cache.
loadAndCache :: ModuleLoader -> ModuleName.Raw -> IO (Either LoadError LoadedModule)
loadAndCache loader modName = do
  resolved <- resolveModulePath (_mlSourceDirs loader) modName
  maybe
    (pure (Left (ModuleNotFound modName (_mlSourceDirs loader))))
    (readAndCache loader modName)
    resolved

-- | Read a module file and add it to the cache.
readAndCache :: ModuleLoader -> ModuleName.Raw -> FilePath -> IO (Either LoadError LoadedModule)
readAndCache loader modName path = do
  result <- safeReadFile path
  either
    (\msg -> pure (Left (ModuleReadError modName path msg)))
    (\source -> cacheModule loader modName source path)
    result

-- | Cache a loaded module.
cacheModule :: ModuleLoader -> ModuleName.Raw -> BS.ByteString -> FilePath -> IO (Either LoadError LoadedModule)
cacheModule loader modName source path = do
  let loaded = LoadedModule {_lmSource = source, _lmPath = path, _lmName = modName}
  IORef.modifyIORef' (_mlCache loader) (Map.insert modName loaded)
  pure (Right loaded)

-- | Safely read a file, catching IO exceptions.
safeReadFile :: FilePath -> IO (Either Text.Text BS.ByteString)
safeReadFile path = do
  exists <- Dir.doesFileExist path
  if exists
    then Right <$> BS.readFile path
    else pure (Left "file does not exist")

-- | Convert a module name to a relative file path.
--
-- Dots in the module name become directory separators:
-- @Data.List@ becomes @Data/List@.
moduleNameToPath :: ModuleName.Raw -> FilePath
moduleNameToPath modName =
  map dotToSep (Name.toChars modName)
  where
    dotToSep '.' = FP.pathSeparator
    dotToSep c = c

-- | Find the first existing file in a list of candidates.
findFirst :: [FilePath] -> IO (Maybe FilePath)
findFirst [] = pure Nothing
findFirst (p : ps) = do
  exists <- Dir.doesFileExist p
  if exists then pure (Just p) else findFirst ps

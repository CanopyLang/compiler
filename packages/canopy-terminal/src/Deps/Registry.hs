{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Package registry stub for Terminal.
--
-- Minimal stub for package registry operations. The OLD module handled
-- downloading and caching package metadata from the Elm package registry.
--
-- @since 0.19.1
module Deps.Registry
  ( -- * Registry Type
    Registry (..),
    CanopyRegistries (..),
    KnownVersions (..),
    RegistryKey (RepositoryUrlKey, PackageUrlKey),

    -- * Operations
    read,
    mergeRegistries,
    latest,
    createAuthHeader,
    getVersions',
  )
where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Prelude hiding (read)

-- | Package registry with package counts and versions.
data Registry = Registry !Int !(Map Pkg.Name (Map V.Version ()))
  deriving (Show, Eq)

-- | Registry key types for authentication and package lookup.
data RegistryKey
  = RepositoryUrlKey String
  | PackageUrlKey Pkg.Name
  deriving (Show, Eq)

-- | Multiple registries combined (stub).
data CanopyRegistries = CanopyRegistries
  { _registriesMain :: !Registry
  , _registriesCustom :: ![Registry]
  , _registries :: !(Map RegistryKey Registry)
  }
  deriving (Show, Eq)

-- | Known package versions with latest and previous.
data KnownVersions = KnownVersions !V.Version ![V.Version]
  deriving (Show, Eq)

-- | Create authentication header from token.
createAuthHeader :: String -> (String, String)
createAuthHeader token = ("Authorization", "Bearer " <> token)

-- | Read registry from cache (stub - returns empty registry).
read :: FilePath -> IO (Maybe Registry)
read _cache = pure Nothing

-- | Merge multiple registries (stub - identity function).
mergeRegistries :: Registry -> Registry
mergeRegistries = id

-- | Get latest registry (stub - returns empty registry).
latest :: a -> b -> c -> d -> IO (Either String Registry)
latest _ _ _ _ = pure (Right (Registry 0 Map.empty))

-- | Get versions for a package (stub).
getVersions' :: CanopyRegistries -> Pkg.Name -> Maybe KnownVersions
getVersions' _ _ = Nothing

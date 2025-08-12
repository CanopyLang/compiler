{-# LANGUAGE EmptyDataDecls #-}

module Canopy.PackageOverrideData
  ( PackageOverrideData (..),
  )
where

import Canopy.Package (Name)
import Canopy.Version (Version)

data PackageOverrideData = PackageOverrideData
  { _overridePackageName :: !Name,
    _overridePackageVersion :: !Version,
    _originalPackageName :: !Name,
    _originalPackageVersion :: !Version
  }
  deriving (Show)

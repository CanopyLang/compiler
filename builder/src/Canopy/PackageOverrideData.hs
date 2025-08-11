
{-# LANGUAGE EmptyDataDecls #-}
module Canopy.PackageOverrideData
  ( PackageOverrideData(..)
  )
  where

import Canopy.Version (Version)
import Canopy.Package (Name)

data PackageOverrideData = 
  PackageOverrideData
    { _overridePackageName :: !Name
    , _overridePackageVersion :: !Version
    , _originalPackageName :: !Name
    , _originalPackageVersion :: !Version
    }
    deriving Show

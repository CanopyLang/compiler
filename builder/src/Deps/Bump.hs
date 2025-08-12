module Deps.Bump
  ( getPossibilities,
  )
where

import qualified Canopy.Magnitude as M
import qualified Canopy.Version as V
import qualified Data.List as List
import qualified Deps.Registry as Registry

-- GET POSSIBILITIES

getPossibilities :: Registry.KnownVersions -> [(V.Version, V.Version, M.Magnitude)]
getPossibilities (Registry.KnownVersions latest previous) =
  let allVersions = reverse (latest : previous)
      minorPoints = fmap last (List.groupBy sameMajor allVersions)
      patchPoints = fmap last (List.groupBy sameMinor allVersions)
   in (latest, V.bumpMajor latest, M.MAJOR) :
      (fmap (\v -> (v, V.bumpMinor v, M.MINOR)) minorPoints <> fmap (\v -> (v, V.bumpPatch v, M.PATCH)) patchPoints)

sameMajor :: V.Version -> V.Version -> Bool
sameMajor (V.Version major1 _ _) (V.Version major2 _ _) =
  major1 == major2

sameMinor :: V.Version -> V.Version -> Bool
sameMinor (V.Version major1 minor1 _) (V.Version major2 minor2 _) =
  major1 == major2 && minor1 == minor2

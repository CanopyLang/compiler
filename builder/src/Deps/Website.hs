module Deps.Website
  ( standardCanopyPkgRepoDomain,
    route,
    metadata,
  )
where

import Canopy.CustomRepositoryData (RepositoryUrl)
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import qualified Data.Utf8 as Utf8
import qualified Http

standardCanopyPkgRepoDomain :: RepositoryUrl
standardCanopyPkgRepoDomain =
  Utf8.fromChars "https://package.canopy-lang.org"

route :: RepositoryUrl -> String -> [(String, String)] -> String
route repositoryUrl path = Http.toUrl (Utf8.toChars repositoryUrl <> path)

metadata :: RepositoryUrl -> Pkg.Name -> V.Version -> String -> String
metadata repositoryUrl name version file =
  Utf8.toChars repositoryUrl <> ("/packages/" <> (Pkg.toUrl name <> ("/" <> (V.toChars version <> ("/" <> file)))))

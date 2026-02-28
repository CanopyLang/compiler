{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- | Package registry operations for Canopy publishing.
--
-- This module handles registry lookups, package registration,
-- and repository management for different repository types.
--
-- @since 0.19.1
module Publish.Registry
  ( -- * Repository Management
    lookupRepositoryByLocalName,
    getAllLocalNamesInRegistries,

    -- * Package Registration
    registerToDefaultServer,
    registerToPZRServer,

    -- * Helper Functions
    convertRegistryKey,
    findRepositoryByName,
  )
where

import Canopy.CustomRepositoryData
  ( CustomSingleRepositoryData,
    RepositoryAuthToken,
    RepositoryLocalName,
    RepositoryUrl,
  )
import qualified Canopy.CustomRepositoryData as CustomRepo
import Canopy.Docs (Documentation)
import qualified Canopy.Docs as Docs
import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import Canopy.Version (Version)
import qualified Canopy.Version as Version
import Codec.Archive.Zip (Archive)
import qualified Codec.Archive.Zip as Zip
import Control.Lens ((^.))
import qualified Data.ByteString.Char8 as BS
import qualified Data.CaseInsensitive as CI
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import Deps.Registry (RegistryKey, CanopyRegistries, createAuthHeader)
import qualified Deps.Registry as Registry
import qualified Deps.Website as Website
import Http (Manager, Sha)
import qualified Http
import Network.HTTP.Client.MultipartFormData (Part)
import Publish.Types (RegistrationData (..), regCommitHash, regDocs, regPkg, regSha, regVersion)
import Reporting.Exit (Publish)
import qualified Reporting.Exit as Exit
import Reporting.Task (Task)
import qualified Reporting.Task as Task

-- | Convert a registry key to custom repository data if applicable.
--
-- Currently returns 'Nothing' for all keys since Canopy uses the standard
-- Elm package registry and does not yet support custom repositories.
-- When custom repository support is added, 'RepositoryUrlKey' entries
-- will be resolved to their full 'CustomSingleRepositoryData'.
--
-- @since 0.19.1
convertRegistryKey :: RegistryKey -> Maybe CustomSingleRepositoryData
convertRegistryKey = \case
  Registry.RepositoryUrlKey _url -> Nothing
  Registry.PackageUrlKey _ -> Nothing

-- | Extract all custom repository data from the registries.
--
-- @since 0.19.1
getAllCustomRepositoryData :: CanopyRegistries -> [CustomSingleRepositoryData]
getAllCustomRepositoryData registries =
  Maybe.mapMaybe convertRegistryKey registryKeys
  where
    Registry.CanopyRegistries {Registry._registries = registriesMap} = registries
    registryKeys = Map.keys registriesMap

-- | Get the local name from custom repository data.
--
-- @since 0.19.1
getLocalName :: CustomSingleRepositoryData -> RepositoryLocalName
getLocalName = \case
  CustomRepo.DefaultPackageServerRepoData localName _ _ -> localName
  CustomRepo.PZRPackageServerRepoData localName _ _ -> localName

-- | Find repository data by local name in a list.
--
-- Uses linear search which is acceptable for the expected small number of repositories.
--
-- @since 0.19.1
findRepositoryByName :: RepositoryLocalName -> [CustomSingleRepositoryData] -> Maybe CustomSingleRepositoryData
findRepositoryByName targetName = \case
  [] -> Nothing
  repo : rest ->
    if getLocalName repo == targetName
      then Just repo
      else findRepositoryByName targetName rest

-- | Look up repository configuration by local name.
--
-- @since 0.19.1
lookupRepositoryByLocalName :: RepositoryLocalName -> CanopyRegistries -> Maybe CustomSingleRepositoryData
lookupRepositoryByLocalName localName registries =
  findRepositoryByName localName (getAllCustomRepositoryData registries)

-- | Get all available repository local names.
--
-- @since 0.19.1
getAllLocalNamesInRegistries :: CanopyRegistries -> [RepositoryLocalName]
getAllLocalNamesInRegistries registries =
  map getLocalName (getAllCustomRepositoryData registries)

-- | Register package to a standard repository with Git verification.
--
-- @since 0.19.1
registerToDefaultServer :: Manager -> RepositoryUrl -> Name -> Version -> Documentation -> String -> Sha -> Task Publish ()
registerToDefaultServer manager repositoryUrl pkg vsn docs commitHash sha = do
  let regData = RegistrationData pkg vsn docs commitHash sha
  let url = createRegistrationUrl repositoryUrl regData
  let uploadParts = createUploadParts regData
  result <- Task.io (Http.upload manager url uploadParts)
  either (Task.throw . Exit.PublishCannotRegister . show) pure result

-- | Create registration URL for default server.
--
-- @since 0.19.1
createRegistrationUrl :: RepositoryUrl -> RegistrationData -> String
createRegistrationUrl repoUrl regData =
  Website.route
    (Text.unpack repoUrl)
    "/register"
    [ ("name", Pkg.toChars (regData ^. regPkg)),
      ("version", Version.toChars (regData ^. regVersion)),
      ("commit-hash", regData ^. regCommitHash)
    ]

-- | Create upload parts for default server registration.
--
-- @since 0.19.1
createUploadParts :: RegistrationData -> [Part]
createUploadParts regData =
  [ Http.filePart "canopy.json" "canopy.json",
    Http.jsonPart "docs.json" "docs.json" (Docs.encode (regData ^. regDocs)),
    Http.filePart "README.md" "README.md",
    Http.stringPart "github-hash" (Http.shaToChars (regData ^. regSha))
  ]

-- | Register package to a PZR repository with ZIP archive.
--
-- @since 0.19.1
registerToPZRServer :: Manager -> RepositoryUrl -> RepositoryAuthToken -> Name -> Version -> Documentation -> Archive -> Task Publish ()
registerToPZRServer manager repositoryUrl authToken pkg vsn docs zipArchive = do
  let url = createPZRUrl repositoryUrl pkg vsn
  let uploadParts = createPZRUploadParts docs zipArchive
  let authHeaderValue = Text.unpack authToken
  let (headerName, headerValue) = createAuthHeader authHeaderValue
  let authHeader = (CI.mk (BS.pack headerName), BS.pack headerValue)
  result <- Task.io (Http.uploadWithHeaders manager url uploadParts [authHeader])
  either (Task.throw . Exit.PublishCannotRegister . show) pure result

-- | Create PZR registration URL.
--
-- @since 0.19.1
createPZRUrl :: RepositoryUrl -> Name -> Version -> String
createPZRUrl repoUrl package version =
  Website.route
    (Text.unpack repoUrl)
    "/upload-package"
    [ ("name", Pkg.toChars package),
      ("version", Version.toChars version)
    ]

-- | Create upload parts for PZR server registration.
--
-- @since 0.19.1
createPZRUploadParts :: Documentation -> Archive -> [Part]
createPZRUploadParts documentation archive =
  [ Http.filePart "canopy.json" "canopy.json",
    Http.jsonPart "docs.json" "docs.json" (Docs.encode documentation),
    Http.filePart "README.md" "README.md",
    Http.bytesPart "package.zip" "package.zip" (BS.toStrict (Zip.fromArchive archive))
  ]

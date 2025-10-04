{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Custom repository data placeholder for Terminal.
--
-- Minimal stub for repository configuration. The OLD module handled
-- custom package repositories, but this is rarely used functionality.
--
-- @since 0.19.1
module Canopy.CustomRepositoryData
  ( -- * Types
    RepositoryLocalName,
    CustomRepositoriesData,
    CustomSingleRepositoryData (..),
    RepositoryAuthToken,
    RepositoryUrl,
  )
where

import Data.Map.Strict (Map)
import qualified Data.Text as Text

-- | Repository local name type.
type RepositoryLocalName = Text.Text

-- | Authentication token for custom repository.
type RepositoryAuthToken = Text.Text

-- | Repository URL type.
type RepositoryUrl = Text.Text

-- | Single repository configuration (sum type).
data CustomSingleRepositoryData
  = DefaultPackageServerRepoData
      { _defaultPackageServerRepoLocalName :: !RepositoryLocalName,
        _defaultPackageServerRepoUrl :: !RepositoryUrl,
        _defaultPackageServerRepoAuthToken :: !(Maybe RepositoryAuthToken)
      }
  | PZRPackageServerRepoData
      { _pzrPackageServerRepoLocalName :: !RepositoryLocalName,
        _pzrPackageServerRepoUrl :: !RepositoryUrl,
        _pzrPackageServerRepoAuthToken :: !(Maybe RepositoryAuthToken)
      }
  deriving (Eq, Show)

-- | Custom repositories data type (stub).
type CustomRepositoriesData = Map RepositoryLocalName CustomSingleRepositoryData

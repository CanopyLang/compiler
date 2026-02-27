{-# LANGUAGE OverloadedStrings #-}

-- | Custom repository data I\/O operations.
--
-- Loads custom repository configuration from disk. Currently returns
-- an empty configuration since Canopy uses the standard Elm package
-- registry at @package.elm-lang.org@. When custom repository support
-- is added, this module will read from @~\/.canopy\/repositories.json@.
--
-- @since 0.19.1
module Deps.CustomRepositoryDataIO
  ( loadCustomRepositoriesData,
  )
where

import qualified Canopy.CustomRepositoryData as CustomRepo

-- | Load custom repository configuration from the cache directory.
--
-- Returns an empty configuration since Canopy currently only supports
-- the standard Elm package registry.
loadCustomRepositoriesData :: FilePath -> IO (Either String CustomRepo.CustomRepositoriesData)
loadCustomRepositoriesData _cache = pure (Right mempty)

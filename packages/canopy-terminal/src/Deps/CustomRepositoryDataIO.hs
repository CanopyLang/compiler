{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Custom repository data I/O stub for Terminal.
--
-- Minimal stub for custom repository data operations.
--
-- @since 0.19.1
module Deps.CustomRepositoryDataIO
  ( loadCustomRepositoriesData,
  )
where

import qualified Canopy.CustomRepositoryData as CustomRepo

-- | Load custom repositories data (stub - returns empty).
loadCustomRepositoriesData :: FilePath -> IO (Either String CustomRepo.CustomRepositoriesData)
loadCustomRepositoriesData _cache = pure (Right mempty)

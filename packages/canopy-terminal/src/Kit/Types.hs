{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Core types for the Kit framework CLI commands.
--
-- Defines the command, flag, and configuration types used by the Kit
-- subcommands (@kit-new@, @kit-dev@, @kit-build@). These types are consumed
-- by the 'Kit' dispatcher and the individual command implementations.
--
-- @since 0.19.2
module Kit.Types
  ( KitCommand (..)
  , KitDevFlags (..)
  , KitBuildFlags (..)
  , kitDevPort
  , kitDevOpen
  , kitBuildOptimize
  , kitBuildOutput
  ) where

import Control.Lens (makeLenses)
import Data.Text (Text)

-- | Top-level Kit subcommand dispatched by 'Kit.run'.
--
-- Each constructor carries the data needed by the corresponding
-- command module ('Kit.New', 'Kit.Dev', 'Kit.Build').
--
-- @since 0.19.2
data KitCommand
  = KitNew !Text
    -- ^ Scaffold a new Kit project with the given name.
  | KitDev !KitDevFlags
    -- ^ Start the development server.
  | KitBuild !KitBuildFlags
    -- ^ Produce a production build.
  deriving (Eq, Show)

-- | Flags for the @kit-dev@ development server command.
--
-- @since 0.19.2
data KitDevFlags = KitDevFlags
  { _kitDevPort :: !(Maybe Int)
    -- ^ Port number for the Vite dev server (default: 5173).
  , _kitDevOpen :: !Bool
    -- ^ Whether to open a browser window automatically.
  } deriving (Eq, Show)

-- | Flags for the @kit-build@ production build command.
--
-- @since 0.19.2
data KitBuildFlags = KitBuildFlags
  { _kitBuildOptimize :: !Bool
    -- ^ Enable Canopy optimizations (dead-code elimination, minification).
  , _kitBuildOutput :: !(Maybe FilePath)
    -- ^ Override the default output directory (@build/@).
  } deriving (Eq, Show)

makeLenses ''KitDevFlags
makeLenses ''KitBuildFlags

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
  , KitPreviewFlags (..)
  , DeployTarget (..)
  , kitDevPort
  , kitDevOpen
  , kitBuildOptimize
  , kitBuildOutput
  , kitBuildTarget
  , kitPreviewPort
  , kitPreviewOpen
  , parseDeployTarget
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
  | KitPreview !KitPreviewFlags
    -- ^ Preview a production build locally.
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

-- | Deployment target for the @kit-build@ command.
--
-- Determines what deploy adapter runs after bundling to produce
-- target-specific configuration and entry points.
--
-- @since 0.20.1
data DeployTarget
  = TargetStatic
    -- ^ Default: fully static site, no server.
  | TargetNode
    -- ^ Node.js server with Express for SSR routes.
  | TargetVercel
    -- ^ Vercel platform with @vercel.json@ configuration.
  | TargetNetlify
    -- ^ Netlify platform with @netlify.toml@ configuration.
  deriving (Eq, Show)

-- | Parse a deploy target string from the @--target@ flag.
--
-- @since 0.20.1
parseDeployTarget :: String -> Maybe DeployTarget
parseDeployTarget "static" = Just TargetStatic
parseDeployTarget "node" = Just TargetNode
parseDeployTarget "vercel" = Just TargetVercel
parseDeployTarget "netlify" = Just TargetNetlify
parseDeployTarget _ = Nothing

-- | Flags for the @kit-build@ production build command.
--
-- @since 0.19.2
data KitBuildFlags = KitBuildFlags
  { _kitBuildOptimize :: !Bool
    -- ^ Enable Canopy optimizations (dead-code elimination, minification).
  , _kitBuildOutput :: !(Maybe FilePath)
    -- ^ Override the default output directory (@build/@).
  , _kitBuildTarget :: !(Maybe DeployTarget)
    -- ^ Deployment target (default: 'TargetStatic' when 'Nothing').
  } deriving (Eq, Show)

-- | Flags for the @kit-preview@ command.
--
-- @since 0.20.1
data KitPreviewFlags = KitPreviewFlags
  { _kitPreviewPort :: !(Maybe Int)
    -- ^ Port number for the preview server (default: 3000).
  , _kitPreviewOpen :: !Bool
    -- ^ Whether to open a browser window automatically.
  } deriving (Eq, Show)

makeLenses ''KitDevFlags
makeLenses ''KitBuildFlags
makeLenses ''KitPreviewFlags

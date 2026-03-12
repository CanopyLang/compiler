{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Vite configuration and plugin file generation for Kit projects.
--
-- Provides generators for two companion files needed by every Kit application:
--
--   * @vite.config.ts@ — a TypeScript Vite configuration that wires in the
--     Canopy plugin, sets the dev-server port, and configures the output
--     directory for production builds.
--   * @canopy-plugin.js@ — a Vite plugin that transforms @.can@ files by
--     delegating to @canopy make --esm@, injects the route manifest as the
--     virtual module @virtual:canopy-routes@, and sets up HMR by watching
--     @.can@ files for changes.
--
-- Both generators are pure functions over 'ViteConfig', so the outputs can
-- be tested without touching the filesystem.
--
-- @since 0.19.2
module Kit.VitePlugin
  ( ViteConfig (..)
  , defaultViteConfig
  , generateViteConfig
  , generateCanopyPlugin
  , vcPort
  , vcOutDir
  , vcSourceDir
  , vcRouteManifest
  , vcHmr
  ) where

import Control.Lens (makeLenses)
import qualified Data.Text as Text

-- | Configuration used to render @vite.config.ts@ and @canopy-plugin.js@.
--
-- Use 'defaultViteConfig' for sensible defaults and update fields with lenses.
--
-- @since 0.19.2
data ViteConfig = ViteConfig
  { _vcPort :: !Int
    -- ^ Port the Vite dev server listens on (default: 5173).
  , _vcOutDir :: !FilePath
    -- ^ Output directory for @vite build@ (default: @"build"@).
  , _vcSourceDir :: !FilePath
    -- ^ Directory containing Canopy source files (default: @"src"@).
  , _vcRouteManifest :: !Bool
    -- ^ Whether the plugin should inject the @virtual:canopy-routes@ module.
  , _vcHmr :: !Bool
    -- ^ Whether to enable hot-module replacement for @.can@ files.
  } deriving (Eq, Show)

makeLenses ''ViteConfig

-- | Sensible defaults for a Kit project.
--
-- Port 5173, output to @build/@, sources in @src/@, route manifest and HMR
-- both enabled.
--
-- @since 0.19.2
defaultViteConfig :: ViteConfig
defaultViteConfig = ViteConfig
  { _vcPort = 5173
  , _vcOutDir = "build"
  , _vcSourceDir = "src"
  , _vcRouteManifest = True
  , _vcHmr = True
  }

-- | Render a @vite.config.ts@ file for the given configuration.
--
-- The generated file imports Vite's @defineConfig@ and the local
-- @canopy-plugin@ module, then wires together the plugin, dev-server, build,
-- and resolve sections according to the supplied 'ViteConfig'.
--
-- @since 0.19.2
generateViteConfig :: ViteConfig -> Text.Text
generateViteConfig cfg =
  Text.unlines
    [ "import { defineConfig } from 'vite';"
    , "import canopyPlugin from './canopy-plugin';"
    , ""
    , "export default defineConfig({"
    , "  plugins: [canopyPlugin(" <> pluginOptions cfg <> ")],"
    , "  server: { port: " <> portText cfg <> " },"
    , "  build: { outDir: '" <> outDirText cfg <> "' },"
    , "  resolve: {"
    , "    alias: { '@': '/" <> srcDirText cfg <> "' }"
    , "  }"
    , "});"
    ]

-- | Render the plugin options object literal for @vite.config.ts@.
pluginOptions :: ViteConfig -> Text.Text
pluginOptions cfg =
  "{ routes: " <> boolText (_vcRouteManifest cfg)
    <> ", hmr: " <> boolText (_vcHmr cfg)
    <> " }"

-- | Render the dev-server port as a 'Text' value.
portText :: ViteConfig -> Text.Text
portText cfg = Text.pack (show (_vcPort cfg))

-- | Render the output directory as a 'Text' value.
outDirText :: ViteConfig -> Text.Text
outDirText cfg = Text.pack (_vcOutDir cfg)

-- | Render the source directory as a 'Text' value.
srcDirText :: ViteConfig -> Text.Text
srcDirText cfg = Text.pack (_vcSourceDir cfg)

-- | Render a 'Bool' as a JavaScript boolean literal.
boolText :: Bool -> Text.Text
boolText True = "true"
boolText False = "false"

-- | Render a @canopy-plugin.js@ Vite plugin.
--
-- The plugin:
--
--   * Registers @.can@ as a valid transform target.
--   * Invokes @canopy make --esm@ to compile each @.can@ file on demand.
--   * Exposes a virtual module @virtual:canopy-routes@ that re-exports the
--     route manifest, enabled when route injection is configured.
--   * Watches @.can@ files for changes and triggers HMR when enabled.
--
-- This function produces a static JavaScript string that is independent of
-- the 'ViteConfig' — all runtime behaviour is governed by the options object
-- passed to the plugin factory in @vite.config.ts@.
--
-- @since 0.19.2
generateCanopyPlugin :: Text.Text
generateCanopyPlugin =
  Text.unlines
    [ "import { execSync } from 'node:child_process';"
    , "import { readFileSync } from 'node:fs';"
    , ""
    , "const VIRTUAL_ROUTES = 'virtual:canopy-routes';"
    , "const RESOLVED_VIRTUAL = '\\0' + VIRTUAL_ROUTES;"
    , ""
    , "export default function canopyPlugin(options = {}) {"
    , "  const { routes = true, hmr = true } = options;"
    , "  return {"
    , "    name: 'canopy',"
    , "    enforce: 'pre',"
    , pluginTransformHook
    , pluginResolveIdHook
    , pluginLoadHook
    , pluginHandleHotUpdate
    , "  };"
    , "}"
    ]

-- | Render the @transform@ hook that compiles @.can@ files.
pluginTransformHook :: Text.Text
pluginTransformHook =
  Text.unlines
    [ "    transform(code, id) {"
    , "      if (!id.endsWith('.can')) return null;"
    , "      execSync('canopy make --esm ' + JSON.stringify(id));"
    , "      const jsPath = id.replace(/\\.can$/, '.js');"
    , "      return { code: readFileSync(jsPath, 'utf8'), map: null };"
    , "    },"
    ]

-- | Render the @resolveId@ hook that intercepts the virtual routes module.
pluginResolveIdHook :: Text.Text
pluginResolveIdHook =
  Text.unlines
    [ "    resolveId(id) {"
    , "      if (id === VIRTUAL_ROUTES) return RESOLVED_VIRTUAL;"
    , "      return null;"
    , "    },"
    ]

-- | Render the @load@ hook that serves the virtual routes module.
pluginLoadHook :: Text.Text
pluginLoadHook =
  Text.unlines
    [ "    load(id) {"
    , "      if (id !== RESOLVED_VIRTUAL) return null;"
    , "      return 'export default window.__CANOPY_ROUTES__ || {};';"
    , "    },"
    ]

-- | Render the @handleHotUpdate@ hook.
--
-- The hook checks the @hmr@ option at JavaScript runtime, so the Haskell
-- generator always emits the full handler regardless of configuration.
pluginHandleHotUpdate :: Text.Text
pluginHandleHotUpdate =
  Text.unlines
    [ "    handleHotUpdate({ file, server }) {"
    , "      if (!hmr) return;"
    , "      if (file.endsWith('.can') || file.endsWith('.canopy-hmr-trigger')) {"
    , "        server.ws.send({ type: 'full-reload', path: '*' });"
    , "        return [];"
    , "      }"
    , "    },"
    ]

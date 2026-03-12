{-# LANGUAGE OverloadedStrings #-}

-- | Client-side hydration bootstrap for CanopyKit SSR.
--
-- Generates a JavaScript snippet that reads embedded loader data from the
-- server-rendered HTML and passes it to the Canopy app's @init@ function.
-- This avoids a visual flash by providing the same data that was used
-- during server rendering.
--
-- == How It Works
--
-- 1. SSR embeds loader data as @\<script id="__CANOPY_DATA__" type="application\/json"\>@
-- 2. SSR marks the root node with @data-canopy-hydrate@
-- 3. This bootstrap script reads the JSON, parses it, and passes as flags
-- 4. Since the same data produces the same view, no visual flash occurs
--
-- @since 0.20.1
module Kit.Hydration
  ( generateHydrationBootstrap
  , generateHydrationCheck
  ) where

import Data.Text (Text)
import qualified Data.Text as Text

-- | Generate the hydration bootstrap script.
--
-- This script is injected into the client-side entry point. It detects
-- whether the page was server-rendered (via @data-canopy-hydrate@) and
-- reads embedded data to pass as flags.
--
-- @since 0.20.1
generateHydrationBootstrap :: Text -> Text
generateHydrationBootstrap modulePath =
  Text.unlines
    [ "import * as App from './" <> modulePath <> "';"
    , ""
    , "var root = document.getElementById('app');"
    , "var flags = {};"
    , ""
    , "if (root && root.hasAttribute('data-canopy-hydrate')) {"
    , "  var dataEl = document.getElementById('__CANOPY_DATA__');"
    , "  if (dataEl) {"
    , "    try { flags = JSON.parse(dataEl.textContent); }"
    , "    catch (e) { console.warn('Canopy hydration: failed to parse embedded data', e); }"
    , "  }"
    , "  root.removeAttribute('data-canopy-hydrate');"
    , "}"
    , ""
    , "App.init({ node: root, flags: flags });"
    ]

-- | Generate a check expression that returns true if the page was SSR'd.
--
-- Useful for conditional behavior in generated entry points.
--
-- @since 0.20.1
generateHydrationCheck :: Text
generateHydrationCheck =
  "document.getElementById('app') && document.getElementById('app').hasAttribute('data-canopy-hydrate')"

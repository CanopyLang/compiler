{-# LANGUAGE OverloadedStrings #-}

-- | Kit.Route.ClientNav -- Client-side navigation runtime generation.
--
-- Generates JavaScript that provides single-page-application navigation
-- for Canopy Kit applications. The emitted runtime handles:
--
-- * @pushState@ navigation without full page reloads.
-- * @popstate@ event handling for browser back\/forward buttons.
-- * Lazy route module loading via the code split manifest.
-- * Interception of @\<a\>@ click events for same-origin links.
--
-- The output is a 'Data.ByteString.Builder.Builder' that can be
-- concatenated with other generated JavaScript and flushed to disk
-- in a single pass.
--
-- @since 0.19.2
module Kit.Route.ClientNav
  ( generateNavRuntime
  ) where

import Control.Lens ((^.))
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as Builder
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import Kit.Route.Types
  ( RouteEntry
  , RouteManifest (..)
  , RouteSegment (..)
  , reModuleName
  , rePattern
  , rpSegments
  )

-- | Generate the complete client-side navigation runtime.
--
-- The emitted JavaScript is an IIFE (immediately-invoked function
-- expression) that registers event listeners on @window@ and
-- provides a @__canopy_navigate@ function for programmatic navigation.
--
-- @since 0.19.2
generateNavRuntime :: RouteManifest -> Builder
generateNavRuntime manifest =
  mconcat
    [ iifeOpen
    , stateSection
    , navigateFunction manifest
    , matchRouteFunction manifest
    , loadModuleFunction
    , linkInterceptor
    , popstateHandler
    , initSection
    , iifeClose
    ]

-- | Opening of the IIFE wrapper.
iifeOpen :: Builder
iifeOpen = Builder.stringUtf8 "(function() {\n\"use strict\";\n\n"

-- | Closing of the IIFE wrapper.
iifeClose :: Builder
iifeClose = Builder.stringUtf8 "\n})();\n"

-- | Internal state variables for the navigation runtime.
stateSection :: Builder
stateSection = mconcat
  [ jsLine "var __canopy_current_route = null;"
  , jsLine "var __canopy_current_module = null;"
  , jsLine "var __canopy_app_node = null;"
  , jsLine ""
  ]

-- | The @__canopy_navigate@ function that drives route transitions.
--
-- Performs a @pushState@ call, resolves the matching route, lazy-loads
-- the route module, and invokes the Canopy runtime to swap the view.
navigateFunction :: RouteManifest -> Builder
navigateFunction _manifest = mconcat
  [ jsLine "function __canopy_navigate(url, pushState) {"
  , jsLine "  var segments = __canopy_parse_url(url);"
  , jsLine "  var match = __canopy_match_route(segments);"
  , jsLine "  if (!match) return;"
  , jsLine "  if (pushState) {"
  , jsLine "    history.pushState(null, \"\", url);"
  , jsLine "  }"
  , jsLine "  __canopy_load_module(match.module, function(mod) {"
  , jsLine "    __canopy_current_route = match;"
  , jsLine "    __canopy_current_module = mod;"
  , jsLine "    mod.init(__canopy_app_node, match.params);"
  , jsLine "  });"
  , jsLine "}"
  , jsLine ""
  , parseUrlHelper
  ]

-- | Helper that splits a URL pathname into path segments.
parseUrlHelper :: Builder
parseUrlHelper = mconcat
  [ jsLine "function __canopy_parse_url(url) {"
  , jsLine "  var a = document.createElement(\"a\");"
  , jsLine "  a.href = url;"
  , jsLine "  var path = a.pathname || \"/\";"
  , jsLine "  if (path[0] === \"/\") path = path.slice(1);"
  , jsLine "  return path ? path.split(\"/\") : [];"
  , jsLine "}"
  , jsLine ""
  ]

-- | The route matching function that maps segments to route metadata.
--
-- Emits a sequence of segment-count checks and literal comparisons
-- that correspond to the routes in the manifest. Each successful
-- match returns an object with @module@ (the module name for lazy
-- loading) and @params@ (an object of captured dynamic values).
matchRouteFunction :: RouteManifest -> Builder
matchRouteFunction manifest = mconcat
  [ jsLine "function __canopy_match_route(segments) {"
  , mconcat (fmap emitRouteMatch (_rmRoutes manifest))
  , jsLine "  return null;"
  , jsLine "}"
  , jsLine ""
  ]

-- | Emit one @if@ block that matches a single route entry.
emitRouteMatch :: RouteEntry -> Builder
emitRouteMatch entry = mconcat
  [ Builder.stringUtf8 "  if ("
  , condition
  , Builder.stringUtf8 ") {\n"
  , Builder.stringUtf8 "    return "
  , returnObj
  , Builder.stringUtf8 ";\n"
  , jsLine "  }"
  ]
  where
    segs = entry ^. rePattern . rpSegments
    condition = buildMatchCondition segs
    returnObj = buildReturnObject entry segs

-- | Build the boolean condition that tests segment count and literals.
buildMatchCondition :: [RouteSegment] -> Builder
buildMatchCondition [] =
  Builder.stringUtf8 "segments.length === 0"
buildMatchCondition segs =
  mconcat
    [ Builder.stringUtf8 "segments.length === "
    , Builder.stringUtf8 (show (length segs))
    , mconcat (concatMap staticCheck (zip [0 ..] segs))
    ]

-- | Emit an equality check for static segments.
staticCheck :: (Int, RouteSegment) -> [Builder]
staticCheck (i, StaticSegment t) =
  [ Builder.stringUtf8 " && segments["
  , Builder.stringUtf8 (show i)
  , Builder.stringUtf8 "] === \""
  , Builder.byteString (TextEnc.encodeUtf8 t)
  , Builder.stringUtf8 "\""
  ]
staticCheck (_, DynamicSegment _) = []
staticCheck (_, CatchAll _) = []

-- | Build the return object literal with module name and params.
buildReturnObject :: RouteEntry -> [RouteSegment] -> Builder
buildReturnObject entry segs = mconcat
  [ Builder.stringUtf8 "{ module: \""
  , Builder.byteString (TextEnc.encodeUtf8 (entry ^. reModuleName))
  , Builder.stringUtf8 "\", params: {"
  , mconcat (intersperse commaSpace (paramEntries segs))
  , Builder.stringUtf8 "} }"
  ]

-- | Build key-value pairs for dynamic segment parameters.
paramEntries :: [RouteSegment] -> [Builder]
paramEntries segs =
  concatMap paramEntry (zip [0 ..] segs)

-- | Emit a single param key-value pair for a dynamic segment.
paramEntry :: (Int, RouteSegment) -> [Builder]
paramEntry (i, DynamicSegment name) =
  [dynamicParam name i]
paramEntry (i, CatchAll name) =
  [dynamicParam name i]
paramEntry (_, StaticSegment _) = []

-- | Build @\"name\": segments[i]@ for a dynamic parameter.
dynamicParam :: Text.Text -> Int -> Builder
dynamicParam name idx = mconcat
  [ Builder.stringUtf8 "\""
  , Builder.byteString (TextEnc.encodeUtf8 name)
  , Builder.stringUtf8 "\": segments["
  , Builder.stringUtf8 (show idx)
  , Builder.stringUtf8 "]"
  ]

-- | Intersperse a separator between builders.
intersperse :: Builder -> [Builder] -> [Builder]
intersperse _ [] = []
intersperse _ [x] = [x]
intersperse sep (x : xs) = x : sep : intersperse sep xs

-- | A comma followed by a space.
commaSpace :: Builder
commaSpace = Builder.stringUtf8 ", "

-- | Lazy module loader that delegates to the code split runtime.
--
-- If @__canopy_load@ is available (code splitting active), uses it.
-- Otherwise assumes the module is already in scope.
loadModuleFunction :: Builder
loadModuleFunction = mconcat
  [ jsLine "function __canopy_load_module(name, callback) {"
  , jsLine "  if (typeof __canopy_load === \"function\") {"
  , jsLine "    var result = __canopy_load(name);"
  , jsLine "    if (result && typeof result.then === \"function\") {"
  , jsLine "      result.then(callback);"
  , jsLine "    } else {"
  , jsLine "      callback(result);"
  , jsLine "    }"
  , jsLine "  } else {"
  , jsLine "    callback(window[\"__canopy_modules\"][name]);"
  , jsLine "  }"
  , jsLine "}"
  , jsLine ""
  ]

-- | Click event interceptor for same-origin @\<a\>@ elements.
--
-- Prevents the default browser navigation and delegates to
-- @__canopy_navigate@ for links that point to the same origin.
linkInterceptor :: Builder
linkInterceptor = mconcat
  [ jsLine "document.addEventListener(\"click\", function(e) {"
  , jsLine "  var target = e.target;"
  , jsLine "  while (target && target.tagName !== \"A\") {"
  , jsLine "    target = target.parentElement;"
  , jsLine "  }"
  , jsLine "  if (!target) return;"
  , jsLine "  if (target.origin !== location.origin) return;"
  , jsLine "  if (target.hasAttribute(\"download\")) return;"
  , jsLine "  if (target.getAttribute(\"target\") === \"_blank\") return;"
  , jsLine "  e.preventDefault();"
  , jsLine "  __canopy_navigate(target.href, true);"
  , jsLine "});"
  , jsLine ""
  ]

-- | Handler for the browser back/forward buttons.
popstateHandler :: Builder
popstateHandler = mconcat
  [ jsLine "window.addEventListener(\"popstate\", function() {"
  , jsLine "  __canopy_navigate(location.href, false);"
  , jsLine "});"
  , jsLine ""
  ]

-- | Initialisation code that runs the first route match on load.
initSection :: Builder
initSection = mconcat
  [ jsLine "__canopy_app_node = document.getElementById(\"app\");"
  , jsLine "__canopy_navigate(location.href, false);"
  ]

-- | Emit a single line of JavaScript followed by a newline.
jsLine :: String -> Builder
jsLine s = Builder.stringUtf8 s <> Builder.char8 '\n'

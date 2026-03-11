{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Kit.ApiHandler -- API route handler code generation.
--
-- Generates JavaScript handler functions and router dispatch code for
-- API routes discovered in the @src\/routes\/api\/@ directory tree. Each
-- @page.can@ file whose 'PageKind' is 'ApiRoute' produces a corresponding
-- serverless-style handler that imports and calls the compiled Canopy
-- module's @handler@ function.
--
-- The generated output is used in two contexts:
--
--   * During @kit-dev@, a @.canopy\/api-handlers.js@ file is written so
--     that the Vite dev server can load it as Express-compatible middleware.
--   * During @kit-build@, each API route is written to @build\/api\/@ as
--     an isolated handler file with a standard @export default handler@
--     signature, ready for use in any Node-compatible serverless platform.
--
-- @since 0.19.2
module Kit.ApiHandler
  ( ApiHandler (..)
  , HandlerOutput (..)
  , generateApiHandlers
  , generateApiRouter
    -- * Lenses
  , ahModuleName
  , ahPattern
  , ahSourceFile
  , hoHandlerCode
  , hoRoutePath
  , hoFunctionName
  ) where

import Control.Lens (makeLenses, (^.))
import qualified Data.List as List
import Data.Text (Text)
import qualified Data.Text as Text
import Kit.Route.Types
  ( PageKind (..)
  , RouteEntry (..)
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  , reModuleName
  , rePageKind
  , rePattern
  , reSourceFile
  , rpSegments
  )
import qualified Kit.Route.Types as Route

-- | A discovered API route ready for handler code generation.
--
-- Carries the Canopy module name, URL pattern, and source file path
-- extracted from a 'RouteEntry' whose 'PageKind' is 'ApiRoute'.
--
-- @since 0.19.2
data ApiHandler = ApiHandler
  { _ahModuleName :: !Text
    -- ^ Fully-qualified Canopy module name, e.g. @"Routes.Api.Users"@.
  , _ahPattern :: !RoutePattern
    -- ^ The URL pattern this handler responds to.
  , _ahSourceFile :: !FilePath
    -- ^ Absolute path to the @page.can@ source file.
  } deriving (Eq, Show)

-- | Generated JavaScript code for a single API route.
--
-- The 'hoHandlerCode' field contains a self-contained JavaScript
-- function that can be registered as an HTTP handler. The
-- 'hoRoutePath' field contains the Express-style URL pattern
-- (e.g. @"\/api\/users\/:id"@) used to register the handler with a router.
-- The 'hoFunctionName' field is the JavaScript identifier of the exported
-- function, needed when wrapping it in a @export default@ statement for
-- production builds.
--
-- @since 0.19.2
data HandlerOutput = HandlerOutput
  { _hoHandlerCode :: !Text
    -- ^ JavaScript handler function as a self-contained text snippet.
  , _hoRoutePath :: !Text
    -- ^ URL path pattern for router registration (e.g. @"\/api\/users\/:id"@).
  , _hoFunctionName :: !Text
    -- ^ JavaScript function identifier, e.g. @"handler_Routes_Api_Users"@.
  } deriving (Eq, Show)

makeLenses ''ApiHandler
makeLenses ''HandlerOutput

-- | Extract all API routes from a manifest and generate handler code.
--
-- Filters the manifest for entries whose 'PageKind' is 'ApiRoute', wraps
-- each in an 'ApiHandler', and calls 'generateHandler' to produce the
-- corresponding 'HandlerOutput'.
--
-- @since 0.19.2
generateApiHandlers :: RouteManifest -> [HandlerOutput]
generateApiHandlers manifest =
  fmap generateHandler (routeEntriesToHandlers apiRoutes)
  where
    apiRoutes = filter isApiRoute (Route._rmRoutes manifest)

-- | Test whether a 'RouteEntry' is an API route.
isApiRoute :: RouteEntry -> Bool
isApiRoute entry = entry ^. rePageKind == ApiRoute

-- | Convert 'RouteEntry' values to 'ApiHandler' values.
routeEntriesToHandlers :: [RouteEntry] -> [ApiHandler]
routeEntriesToHandlers = fmap entryToHandler

-- | Convert a single 'RouteEntry' to an 'ApiHandler'.
entryToHandler :: RouteEntry -> ApiHandler
entryToHandler entry = ApiHandler
  { _ahModuleName = entry ^. reModuleName
  , _ahPattern = entry ^. rePattern
  , _ahSourceFile = entry ^. reSourceFile
  }

-- | Generate a JavaScript handler that calls the Canopy module's @handler@.
--
-- The emitted function imports the compiled module and delegates the
-- request to the @handler@ export. The request\/response contract follows
-- the Node.js @(req, res)@ convention so the output is compatible with
-- Express and Vite's dev server middleware API.
--
-- @since 0.19.2
generateHandler :: ApiHandler -> HandlerOutput
generateHandler apiHandler = HandlerOutput
  { _hoHandlerCode = buildHandlerCode moduleName routePath fnName
  , _hoRoutePath = routePath
  , _hoFunctionName = fnName
  }
  where
    moduleName = apiHandler ^. ahModuleName
    routePath = patternToRoutePath (apiHandler ^. ahPattern)
    fnName = "handler_" <> sanitizeModuleName moduleName

-- | Build the JavaScript source for a handler function.
buildHandlerCode :: Text -> Text -> Text -> Text
buildHandlerCode moduleName routePath fnName =
  Text.unlines
    [ "// Handler for " <> routePath
    , "async function " <> fnName <> "(req, res) {"
    , "  const mod = await import('./" <> moduleToPath moduleName <> ".js');"
    , "  const result = await mod.handler(req);"
    , "  res.setHeader('Content-Type', 'application/json');"
    , "  res.end(JSON.stringify(result));"
    , "}"
    ]

-- | Convert a module name like @Routes.Api.Users@ to a file path.
moduleToPath :: Text -> Text
moduleToPath = Text.replace "." "/"

-- | Replace dots in a module name with underscores for use as a JS identifier.
sanitizeModuleName :: Text -> Text
sanitizeModuleName = Text.replace "." "_"

-- | Convert a 'RoutePattern' to an Express-style URL path string.
--
-- 'StaticSegment' values become literal path components. 'DynamicSegment'
-- values become @:param@ placeholders. 'CatchAll' values become @*param@
-- placeholders.
--
-- @since 0.19.2
patternToRoutePath :: RoutePattern -> Text
patternToRoutePath pattern =
  "/" <> Text.intercalate "/" (fmap segmentToPathPart segments)
  where
    segments = pattern ^. rpSegments

-- | Convert a single route segment to its URL path representation.
segmentToPathPart :: RouteSegment -> Text
segmentToPathPart (StaticSegment t) = t
segmentToPathPart (DynamicSegment t) = ":" <> t
segmentToPathPart (CatchAll t) = "*" <> t

-- | Generate a JavaScript router that dispatches requests to API handlers.
--
-- Emits a self-contained module that defines all handler functions and
-- a route-table array. Exports a @matchApiRoute@ function that accepts a
-- URL path and returns either the matching handler function or @null@ for
-- unrecognised paths.
--
-- @since 0.19.2
generateApiRouter :: [HandlerOutput] -> Text
generateApiRouter outputs =
  Text.unlines (header : handlerBodies ++ [routeTable, footer])
  where
    header = "// AUTO-GENERATED by canopy kit. Do not edit."
    handlerBodies = fmap (^. hoHandlerCode) outputs
    routeTable = buildRouteTable outputs
    footer = buildFooter outputs

-- | Build the route-table array mapping path patterns to handler names.
buildRouteTable :: [HandlerOutput] -> Text
buildRouteTable outputs =
  Text.unlines
    [ "const apiRoutes = ["
    , Text.intercalate ",\n" (fmap buildRouteEntry outputs)
    , "];"
    ]

-- | Build a single route table entry object.
buildRouteEntry :: HandlerOutput -> Text
buildRouteEntry output =
  "  { path: \"" <> path <> "\", handler: " <> fnName <> " }"
  where
    path = output ^. hoRoutePath
    fnName = output ^. hoFunctionName

-- | Build the exported @matchApiRoute@ dispatch function.
buildFooter :: [HandlerOutput] -> Text
buildFooter outputs
  | List.null outputs = emptyMatchFn
  | otherwise = matchFn
  where
    emptyMatchFn = "export function matchApiRoute(_path) { return null; }"
    matchFn =
      Text.unlines
        [ "export function matchApiRoute(path) {"
        , "  const match = apiRoutes.find(r => r.path === path);"
        , "  return match ? match.handler : null;"
        , "}"
        ]

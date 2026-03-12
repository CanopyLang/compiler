{-# LANGUAGE OverloadedStrings #-}

-- | Shared serverless function generation for deploy adapters.
--
-- Both Vercel and Netlify serverless functions follow a similar pattern:
-- import the SSR entry, call @renderRoute@ with the request path and params,
-- and return the HTML response. This module provides the common generation
-- logic.
--
-- @since 0.20.1
module Kit.Deploy.Serverless
  ( generateServerlessHandler
  , isDynamicRoute
  , routeToFunctionName
  ) where

import Control.Lens ((^.))
import Data.Text (Text)
import qualified Data.Text as Text
import Kit.Route.Types (PageKind (..), RouteEntry)
import qualified Kit.Route.Types as Route

-- | Generate the JavaScript content for a serverless function handler.
--
-- The generated function imports the SSR entry module and calls
-- @renderRoute@ with the route path and request parameters.
--
-- @since 0.20.1
generateServerlessHandler :: Text -> RouteEntry -> Text
generateServerlessHandler ssrEntryPath entry =
  Text.unlines
    [ "import { renderRoute } from '" <> ssrEntryPath <> "';"
    , ""
    , "export default async function handler(req, res) {"
    , "  const params = req.query || {};"
    , "  const html = await renderRoute('" <> modName <> "', params);"
    , "  if (html) {"
    , "    res.setHeader('Content-Type', 'text/html; charset=utf-8');"
    , "    res.status(200).send(html);"
    , "  } else {"
    , "    res.status(404).send('Not found');"
    , "  }"
    , "}"
    ]
  where
    modName = entry ^. Route.reModuleName

-- | Check if a route entry is a dynamic route.
--
-- @since 0.20.1
isDynamicRoute :: RouteEntry -> Bool
isDynamicRoute entry = entry ^. Route.rePageKind == DynamicPage

-- | Convert a route entry to a function name for serverless deployment.
--
-- Replaces dots with hyphens in the module name to create a valid
-- filename: @Routes.Users.Id@ becomes @routes-users-id@.
--
-- @since 0.20.1
routeToFunctionName :: RouteEntry -> String
routeToFunctionName entry =
  Text.unpack (Text.toLower (Text.replace "." "-" (entry ^. Route.reModuleName)))

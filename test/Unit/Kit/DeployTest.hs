{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit deploy adapters.
--
-- Verifies that 'deployNode', 'deployVercel', and 'deployNetlify' produce
-- correct configuration files in the output directory.
--
-- @since 0.20.1
module Unit.Kit.DeployTest
  ( tests
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Kit.Route.Types (PageKind (..), RouteEntry (..), RouteManifest (..), RoutePattern (..), RouteSegment (..))
import qualified Kit.Deploy.Netlify as Netlify
import qualified Kit.Deploy.Node as Node
import qualified Kit.Deploy.Serverless as Serverless
import qualified Kit.Deploy.Vercel as Vercel
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import qualified System.IO.Temp as Temp
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit


tests :: TestTree
tests =
  Test.testGroup "Kit.Deploy"
    [ nodeServerJsExpressSetup
    , nodeServerJsStaticAssets
    , nodeServerJsFallback
    , nodeServerJsListen
    , nodePackageJsonContent
    , vercelJsonBuildCommand
    , vercelJsonRewrites
    , vercelJsonHeaders
    , netlifyTomlBuildSection
    , netlifyTomlRedirects
    , netlifyTomlHeaders
    , serverlessIsDynamic
    , serverlessFunctionName
    , vercelServerlessFunctionCreated
    , vercelServerlessFunctionContent
    , vercelJsonDynamicRewrite
    , netlifyFunctionCreated
    , netlifyFunctionContent
    , netlifyTomlDynamicRedirect
    , netlifyTomlFunctionsDirective
    ]


-- | Node server.js starts with ESM imports and app creation.
nodeServerJsExpressSetup :: TestTree
nodeServerJsExpressSetup =
  HUnit.testCase "Node server.js has ESM Express setup" $
    Temp.withSystemTempDirectory "deploy-node" $ \tmpDir -> do
      Node.deployNode tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "server.js")
      let outputLines = Text.lines content
      outputLines !! 0 @?= "import express from 'express';"
      outputLines !! 1 @?= "import { fileURLToPath } from 'url';"
      outputLines !! 2 @?= "import path from 'path';"
      outputLines !! 4 @?= "const __filename = fileURLToPath(import.meta.url);"
      outputLines !! 5 @?= "const __dirname = path.dirname(__filename);"
      outputLines !! 6 @?= "const app = express();"
      outputLines !! 7 @?= "const PORT = process.env.PORT || 3000;"


-- | Node server.js serves static assets from /assets.
nodeServerJsStaticAssets :: TestTree
nodeServerJsStaticAssets =
  HUnit.testCase "Node server.js serves static assets" $
    Temp.withSystemTempDirectory "deploy-node" $ \tmpDir -> do
      Node.deployNode tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "server.js")
      let outputLines = Text.lines content
      outputLines !! 17 @?= "app.use('/assets', express.static(path.join(__dirname, 'assets')));"


-- | Node server.js has SPA fallback route.
nodeServerJsFallback :: TestTree
nodeServerJsFallback =
  HUnit.testCase "Node server.js has SPA fallback" $
    Temp.withSystemTempDirectory "deploy-node" $ \tmpDir -> do
      Node.deployNode tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "server.js")
      let outputLines = Text.lines content
      outputLines !! 22 @?= "// Fallback to index.html for SPA navigation"
      outputLines !! 23 @?= "app.get('*', (req, res) => {"
      outputLines !! 24 @?= "  res.sendFile(path.join(__dirname, 'index.html'));"
      outputLines !! 25 @?= "});"


-- | Node server.js listens on configured PORT.
nodeServerJsListen :: TestTree
nodeServerJsListen =
  HUnit.testCase "Node server.js listens on PORT" $
    Temp.withSystemTempDirectory "deploy-node" $ \tmpDir -> do
      Node.deployNode tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "server.js")
      let outputLines = Text.lines content
      outputLines !! 27 @?= "app.listen(PORT, () => {"
      outputLines !! 28 @?= "  console.log(`Canopy app listening on http://localhost:${PORT}`);"
      outputLines !! 29 @?= "});"


-- | Node package.json has exact expected content including ESM type.
nodePackageJsonContent :: TestTree
nodePackageJsonContent =
  HUnit.testCase "Node package.json content" $
    Temp.withSystemTempDirectory "deploy-node" $ \tmpDir -> do
      Node.deployNode tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "package.json")
      let outputLines = Text.lines content
      outputLines !! 0 @?= "{"
      outputLines !! 1 @?= "  \"name\": \"canopy-kit-server\","
      outputLines !! 2 @?= "  \"private\": true,"
      outputLines !! 3 @?= "  \"type\": \"module\","
      outputLines !! 4 @?= "  \"scripts\": {"
      outputLines !! 5 @?= "    \"start\": \"node server.js\""
      outputLines !! 6 @?= "  },"
      outputLines !! 7 @?= "  \"dependencies\": {"
      outputLines !! 8 @?= "    \"express\": \"^4.18.0\""
      outputLines !! 9 @?= "  }"
      outputLines !! 10 @?= "}"


-- | Vercel config has correct build command and output directory.
vercelJsonBuildCommand :: TestTree
vercelJsonBuildCommand =
  HUnit.testCase "Vercel config build settings" $
    Temp.withSystemTempDirectory "deploy-vercel" $ \tmpDir -> do
      Vercel.deployVercel tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "vercel.json")
      let outputLines = Text.lines content
      outputLines !! 0 @?= "{"
      outputLines !! 1 @?= "  \"buildCommand\": \"canopy kit-build --optimize\","
      outputLines !! 2 @?= "  \"outputDirectory\": \"build\","


-- | Vercel config has SPA rewrite rules.
vercelJsonRewrites :: TestTree
vercelJsonRewrites =
  HUnit.testCase "Vercel config rewrite rules" $
    Temp.withSystemTempDirectory "deploy-vercel" $ \tmpDir -> do
      Vercel.deployVercel tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "vercel.json")
      let outputLines = Text.lines content
      outputLines !! 3 @?= "  \"rewrites\": ["
      outputLines !! 4 @?= "    { \"source\": \"/(.*)\", \"destination\": \"/index.html\" }"
      outputLines !! 5 @?= "  ],"


-- | Vercel config has cache headers for assets.
vercelJsonHeaders :: TestTree
vercelJsonHeaders =
  HUnit.testCase "Vercel config cache headers" $
    Temp.withSystemTempDirectory "deploy-vercel" $ \tmpDir -> do
      Vercel.deployVercel tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "vercel.json")
      let outputLines = Text.lines content
      outputLines !! 6 @?= "  \"headers\": ["
      outputLines !! 7 @?= "    {"
      outputLines !! 8 @?= "      \"source\": \"/assets/(.*)\","
      outputLines !! 9 @?= "      \"headers\": ["
      outputLines !! 10 @?= "        {"
      outputLines !! 11 @?= "          \"key\": \"Cache-Control\","
      outputLines !! 12 @?= "          \"value\": \"public, max-age=31536000, immutable\""
      outputLines !! 13 @?= "        }"
      outputLines !! 14 @?= "      ]"
      outputLines !! 15 @?= "    }"
      outputLines !! 16 @?= "  ]"
      outputLines !! 17 @?= "}"


-- | Netlify config has correct build section.
netlifyTomlBuildSection :: TestTree
netlifyTomlBuildSection =
  HUnit.testCase "Netlify config build section" $
    Temp.withSystemTempDirectory "deploy-netlify" $ \tmpDir -> do
      Netlify.deployNetlify tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "netlify.toml")
      let outputLines = Text.lines content
      outputLines !! 0 @?= "[build]"
      outputLines !! 1 @?= "  command = \"canopy kit-build --optimize\""
      outputLines !! 2 @?= "  publish = \"build\""


-- | Netlify config has SPA redirect rules.
netlifyTomlRedirects :: TestTree
netlifyTomlRedirects =
  HUnit.testCase "Netlify config redirect rules" $
    Temp.withSystemTempDirectory "deploy-netlify" $ \tmpDir -> do
      Netlify.deployNetlify tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "netlify.toml")
      let outputLines = Text.lines content
      outputLines !! 4 @?= "[[redirects]]"
      outputLines !! 5 @?= "  from = \"/*\""
      outputLines !! 6 @?= "  to = \"/index.html\""
      outputLines !! 7 @?= "  status = 200"


-- | Netlify config has cache headers for assets.
netlifyTomlHeaders :: TestTree
netlifyTomlHeaders =
  HUnit.testCase "Netlify config cache headers" $
    Temp.withSystemTempDirectory "deploy-netlify" $ \tmpDir -> do
      Netlify.deployNetlify tmpDir emptyManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "netlify.toml")
      let outputLines = Text.lines content
      outputLines !! 9 @?= "[[headers]]"
      outputLines !! 10 @?= "  for = \"/assets/*\""
      outputLines !! 11 @?= "  [headers.values]"
      outputLines !! 12 @?= "    Cache-Control = \"public, max-age=31536000, immutable\""


-- | Serverless isDynamicRoute correctly identifies dynamic pages.
serverlessIsDynamic :: TestTree
serverlessIsDynamic =
  HUnit.testCase "isDynamicRoute identifies dynamic pages" $ do
    HUnit.assertBool "dynamic route is dynamic" (Serverless.isDynamicRoute dynamicUserRoute)
    HUnit.assertBool "static route is not dynamic" (not (Serverless.isDynamicRoute staticAboutRoute))


-- | Serverless routeToFunctionName converts module names correctly.
serverlessFunctionName :: TestTree
serverlessFunctionName =
  HUnit.testCase "routeToFunctionName converts module name" $
    Serverless.routeToFunctionName dynamicUserRoute @?= "routes-users-id"


-- | Vercel creates a serverless function file for a dynamic route.
vercelServerlessFunctionCreated :: TestTree
vercelServerlessFunctionCreated =
  HUnit.testCase "Vercel creates serverless function for dynamic route" $
    Temp.withSystemTempDirectory "deploy-vercel" $ \tmpDir -> do
      Vercel.deployVercel tmpDir dynamicManifest
      exists <- Dir.doesFileExist (tmpDir FilePath.</> "api" FilePath.</> "routes-users-id.js")
      HUnit.assertBool "serverless function file exists" exists


-- | Vercel serverless function has correct import and handler structure.
vercelServerlessFunctionContent :: TestTree
vercelServerlessFunctionContent =
  HUnit.testCase "Vercel serverless function has correct content" $
    Temp.withSystemTempDirectory "deploy-vercel" $ \tmpDir -> do
      Vercel.deployVercel tmpDir dynamicManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "api" FilePath.</> "routes-users-id.js")
      let outputLines = Text.lines content
      outputLines !! 0 @?= "import { renderRoute } from '../ssr-entry.js';"
      outputLines !! 2 @?= "export default async function handler(req, res) {"
      outputLines !! 4 @?= "  const html = await renderRoute('Routes.Users.Id', params);"


-- | Vercel config includes a rewrite rule pointing to the serverless function.
vercelJsonDynamicRewrite :: TestTree
vercelJsonDynamicRewrite =
  HUnit.testCase "Vercel config includes dynamic route rewrite" $
    Temp.withSystemTempDirectory "deploy-vercel" $ \tmpDir -> do
      Vercel.deployVercel tmpDir dynamicManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "vercel.json")
      let outputLines = Text.lines content
      outputLines !! 3 @?= "  \"rewrites\": ["
      outputLines !! 4 @?= "    { \"source\": \"/users/:id\", \"destination\": \"/api/routes-users-id\" },"
      outputLines !! 5 @?= "    { \"source\": \"/(.*)\", \"destination\": \"/index.html\" }"


-- | Netlify creates a function file for a dynamic route.
netlifyFunctionCreated :: TestTree
netlifyFunctionCreated =
  HUnit.testCase "Netlify creates function for dynamic route" $
    Temp.withSystemTempDirectory "deploy-netlify" $ \tmpDir -> do
      Netlify.deployNetlify tmpDir dynamicManifest
      exists <- Dir.doesFileExist (tmpDir FilePath.</> "netlify" FilePath.</> "functions" FilePath.</> "routes-users-id.js")
      HUnit.assertBool "netlify function file exists" exists


-- | Netlify function has correct SSR entry import path.
netlifyFunctionContent :: TestTree
netlifyFunctionContent =
  HUnit.testCase "Netlify function has correct content" $
    Temp.withSystemTempDirectory "deploy-netlify" $ \tmpDir -> do
      Netlify.deployNetlify tmpDir dynamicManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "netlify" FilePath.</> "functions" FilePath.</> "routes-users-id.js")
      let outputLines = Text.lines content
      outputLines !! 0 @?= "import { renderRoute } from '../../ssr-entry.js';"
      outputLines !! 4 @?= "  const html = await renderRoute('Routes.Users.Id', params);"


-- | Netlify config includes a function redirect for the dynamic route.
netlifyTomlDynamicRedirect :: TestTree
netlifyTomlDynamicRedirect =
  HUnit.testCase "Netlify config includes function redirect" $
    Temp.withSystemTempDirectory "deploy-netlify" $ \tmpDir -> do
      Netlify.deployNetlify tmpDir dynamicManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "netlify.toml")
      let outputLines = Text.lines content
      outputLines !! 5 @?= "[[redirects]]"
      outputLines !! 6 @?= "  from = \"/users/:splat\""
      outputLines !! 7 @?= "  to = \"/.netlify/functions/routes-users-id\""
      outputLines !! 8 @?= "  status = 200"


-- | Netlify config includes functions directive when dynamic routes exist.
netlifyTomlFunctionsDirective :: TestTree
netlifyTomlFunctionsDirective =
  HUnit.testCase "Netlify config includes functions directive" $
    Temp.withSystemTempDirectory "deploy-netlify" $ \tmpDir -> do
      Netlify.deployNetlify tmpDir dynamicManifest
      content <- TextIO.readFile (tmpDir FilePath.</> "netlify.toml")
      let outputLines = Text.lines content
      outputLines !! 3 @?= "  functions = \"netlify/functions\""


-- TEST DATA


emptyManifest :: RouteManifest
emptyManifest = RouteManifest [] [] []


dynamicUserRoute :: RouteEntry
dynamicUserRoute = RouteEntry
  { _rePattern = RoutePattern [StaticSegment "users", DynamicSegment "id"] "src/routes/users/[id]/page.can"
  , _rePageKind = DynamicPage
  , _reSourceFile = "src/routes/users/[id]/page.can"
  , _reModuleName = "Routes.Users.Id"
  }


staticAboutRoute :: RouteEntry
staticAboutRoute = RouteEntry
  { _rePattern = RoutePattern [StaticSegment "about"] "src/routes/about/page.can"
  , _rePageKind = StaticPage
  , _reSourceFile = "src/routes/about/page.can"
  , _reModuleName = "Routes.About"
  }


dynamicManifest :: RouteManifest
dynamicManifest = RouteManifest [dynamicUserRoute] [] []

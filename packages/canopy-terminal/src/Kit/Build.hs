{-# LANGUAGE OverloadedStrings #-}

-- | Kit production build pipeline.
--
-- Orchestrates the full build process for a Kit application:
--
--   1. Scan the routes directory and generate @Routes.can@.
--   2. Detect data loaders from route modules.
--   3. Compile all Canopy source to ES modules via @canopy make@.
--   4. Pre-render static pages into HTML shells.
--   5. Bundle the application with Vite.
--
-- @since 0.19.2
module Kit.Build
  ( build
  ) where

import Control.Lens ((^.))
import qualified Control.Monad as Monad
import qualified Data.Aeson as Aeson
import Data.Aeson ((.:?))
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Kit.DataLoader (DataLoader)
import qualified Kit.DataLoader as DataLoader
import Kit.Route.Types (RouteManifest (..), ScanError, ValidationError)
import qualified Kit.Route.Generate as Generate
import qualified Kit.Route.Scanner as Scanner
import qualified Kit.Route.Validate as Validate
import Kit.SSG (generateStaticPages)
import qualified Kit.SSR as SSR
import Kit.Types (DeployTarget (..), KitBuildFlags, kitBuildOptimize, kitBuildOutput, kitBuildTarget)
import qualified Kit.Deploy.Static as Deploy.Static
import qualified Kit.Deploy.Node as Deploy.Node
import qualified Kit.Deploy.Vercel as Deploy.Vercel
import qualified Kit.Deploy.Netlify as Deploy.Netlify
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BSL
import Generate.JavaScript.WebComponent (WebComponentConfig (..))
import qualified Generate.JavaScript.WebComponent as WebComponent
import qualified Generate.JavaScript.WebComponent.Introspect as Introspect
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Exit.Kit as ExitKit
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import qualified System.Process as Process

-- | Run the Kit production build pipeline.
--
-- Validates the project, generates routes, compiles Canopy source,
-- pre-renders static pages, and runs Vite build. Exits with a
-- structured error report on failure.
--
-- @since 0.19.2
build :: KitBuildFlags -> IO ()
build flags = do
  hasOutline <- Dir.doesFileExist "canopy.json"
  if hasOutline
    then runBuild flags
    else Help.toStderr (ExitKit.kitToReport ExitKit.KitNoOutline)

-- | Execute the build after outline validation.
runBuild :: KitBuildFlags -> IO ()
runBuild flags = do
  hasRoutes <- Dir.doesDirectoryExist "src/routes"
  if hasRoutes
    then executeBuildPipeline flags
    else Help.toStderr (ExitKit.kitToReport ExitKit.KitNotKitProject)

-- | Run each build phase in sequence with the route manifest.
executeBuildPipeline :: KitBuildFlags -> IO ()
executeBuildPipeline flags = do
  scanResult <- Scanner.scanRoutes "."
  case scanResult of
    Left err -> reportScanError err
    Right manifest -> validateAndBuild flags manifest

-- | Validate the manifest, then proceed to build.
validateAndBuild :: KitBuildFlags -> RouteManifest -> IO ()
validateAndBuild flags manifest =
  case Validate.validateManifest manifest of
    Left err -> reportValidationError err
    Right validManifest -> buildWithManifest flags validManifest

-- | Build with a validated route manifest.
buildWithManifest :: KitBuildFlags -> RouteManifest -> IO ()
buildWithManifest flags manifest = do
  writeRoutesModule manifest
  loaders <- DataLoader.detectLoaders (_rmRoutes manifest)
  writeLoaderModule loaders
  compileCanopy flags
  writeStaticPages manifest
  renderSsrPages outputDir manifest loaders
  generateWebComponents outputDir
  runViteBuild flags
  runDeployAdapter (resolveTarget (flags ^. kitBuildTarget)) outputDir manifest loaders
  where
    outputDir = maybe "build" id (flags ^. kitBuildOutput)

-- | Dispatch to the correct deploy adapter based on the build target.
runDeployAdapter :: DeployTarget -> FilePath -> RouteManifest -> [DataLoader] -> IO ()
runDeployAdapter TargetStatic outputDir manifest _ =
  Deploy.Static.deployStatic outputDir manifest
runDeployAdapter TargetNode outputDir manifest loaders = do
  Deploy.Node.deployNode outputDir manifest
  TextIO.writeFile (outputDir FilePath.</> "ssr-entry.js") (SSR.generateSsrEntry loaders)
runDeployAdapter TargetVercel outputDir manifest _ =
  Deploy.Vercel.deployVercel outputDir manifest
runDeployAdapter TargetNetlify outputDir manifest _ =
  Deploy.Netlify.deployNetlify outputDir manifest

-- | Write the generated Routes.can module.
writeRoutesModule :: RouteManifest -> IO ()
writeRoutesModule manifest =
  TextIO.writeFile "src/Routes.can" (Generate.generateRoutesModule manifest)

-- | Write the generated Loaders.can module.
writeLoaderModule :: [DataLoader] -> IO ()
writeLoaderModule loaders =
  TextIO.writeFile "src/Loaders.can" (DataLoader.generateLoaderModule loaders)

-- | Report a route scanning error.
reportScanError :: ScanError -> IO ()
reportScanError err =
  Help.toStderr (ExitKit.kitToReport (ExitKit.KitRouteScanError (show err)))

-- | Report a route validation error.
reportValidationError :: ValidationError -> IO ()
reportValidationError err =
  Help.toStderr (ExitKit.kitToReport (ExitKit.KitRouteValidationError (show err)))

-- | Compile Canopy source to ES modules.
compileCanopy :: KitBuildFlags -> IO ()
compileCanopy flags =
  Process.callProcess "canopy" (buildMakeArgs flags)

-- | Build the argument list for @canopy make@.
--
-- Kit projects use @src/Routes.can@ as the entry point since
-- @canopy make@ requires an explicit source file for application
-- projects. The Routes module transitively imports all page modules
-- via lazy imports, so compiling it covers the full application.
buildMakeArgs :: KitBuildFlags -> [String]
buildMakeArgs flags =
  ["make", "src/Routes.can", "--output-format=esm"] ++ optimizeArg ++ outputArg
  where
    optimizeArg = if flags ^. kitBuildOptimize then ["--optimize"] else []
    outputArg = maybe [] (\o -> ["--output=" ++ o]) (flags ^. kitBuildOutput)

-- | Generate and write HTML shells for all static pages.
writeStaticPages :: RouteManifest -> IO ()
writeStaticPages manifest = do
  Dir.createDirectoryIfMissing True "build"
  Monad.void (Map.traverseWithKey writeStaticPage (generateStaticPages manifest))

-- | Pre-render SSR pages for routes with static data loaders.
renderSsrPages :: FilePath -> RouteManifest -> [DataLoader] -> IO ()
renderSsrPages outputDir manifest loaders =
  SSR.renderStaticRoutes outputDir manifest loaders

-- | Write a single static HTML page to disk.
writeStaticPage :: FilePath -> Text.Text -> IO ()
writeStaticPage path content = do
  Dir.createDirectoryIfMissing True (FilePath.takeDirectory fullPath)
  TextIO.writeFile fullPath content
  where
    fullPath = "build/" ++ path

-- | Run the Vite bundler for production output.
runViteBuild :: KitBuildFlags -> IO ()
runViteBuild flags =
  Process.callProcess "npx" (["vite", "build"] ++ outDirArg)
  where
    outDirArg = maybe [] (\o -> ["--outDir", o]) (flags ^. kitBuildOutput)

-- | Generate Web Component wrappers for modules listed in canopy.json.
--
-- Reads @_appWebComponents@ from the project outline and generates
-- a Custom Element JS file for each listed module.
generateWebComponents :: FilePath -> IO ()
generateWebComponents outputDir = do
  outlineResult <- Outline.read "."
  case outlineResult of
    Right (Outline.App appOutline) ->
      mapM_ (writeWebComponent outputDir) (maybe [] id (Outline._appWebComponents appOutline))
    _ -> pure ()

-- | Write a single Web Component JS file to the output directory.
--
-- Attempts to read flag/port metadata from a companion @.wc.json@
-- file next to the module source. Falls back to untyped attribute
-- forwarding if no config exists.
writeWebComponent :: FilePath -> ModuleName.Raw -> IO ()
writeWebComponent outputDir modName = do
  wcConfig <- loadWcConfig modName
  let tagName = WebComponent.moduleToTagName modName
      config = WebComponentConfig
        { _wcModuleName = modName
        , _wcFlagAttrs = wcFlagAttrs wcConfig
        , _wcPortEvents = wcPortEvents wcConfig
        , _wcFormAssociated = False
        }
      content = WebComponent.generateWebComponent config
          <> "\n"
          <> WebComponent.generateRegistration modName
      fullPath = outputDir FilePath.</> tagName <> ".js"
  BSL.writeFile fullPath (BB.toLazyByteString content)

-- | Parsed companion config for a Web Component module.
data WcConfig = WcConfig
  { wcFlagAttrs :: ![WebComponent.FlagAttr]
  , wcPortEvents :: ![WebComponent.PortEvent]
  }

-- | Load Web Component metadata from a companion @.wc.json@ file.
--
-- The file is expected at @src\/\<Module\>.wc.json@ and contains:
--
-- @
-- { "flags": [["count", "Int"], ["title", "String"]]
-- , "ports": [["onResult", "outgoing"], ["setInput", "incoming"]]
-- }
-- @
--
-- Returns empty attrs/events when the file does not exist or fails
-- to parse.
loadWcConfig :: ModuleName.Raw -> IO WcConfig
loadWcConfig modName = do
  let wcPath = moduleToWcPath modName
  exists <- Dir.doesFileExist wcPath
  if exists
    then parseWcFile wcPath
    else pure emptyWcConfig

-- | Convert a module name to its companion @.wc.json@ path.
moduleToWcPath :: ModuleName.Raw -> FilePath
moduleToWcPath modName =
  "src" FilePath.</> map dotToSep (Utf8.toChars modName) ++ ".wc.json"
  where
    dotToSep '.' = FilePath.pathSeparator
    dotToSep c = c

-- | Parse a @.wc.json@ file into flag attrs and port events.
parseWcFile :: FilePath -> IO WcConfig
parseWcFile path = do
  content <- BSL.readFile path
  pure (maybe emptyWcConfig id (decodeWcJson content))

-- | Raw JSON representation of a @.wc.json@ file.
data WcJsonRaw = WcJsonRaw
  { _wjFlags :: ![[String]]
  , _wjPorts :: ![[String]]
  }

instance Aeson.FromJSON WcJsonRaw where
  parseJSON = Aeson.withObject "WcJsonRaw" $ \o -> do
    flags <- maybe [] id <$> o .:? "flags"
    ports <- maybe [] id <$> o .:? "ports"
    pure (WcJsonRaw flags ports)

-- | Decode the JSON content of a @.wc.json@ file.
--
-- Parses the JSON and delegates to 'Introspect.extractFlagAttrs' and
-- 'Introspect.extractPortEvents' for type-aware conversion.
decodeWcJson :: BSL.ByteString -> Maybe WcConfig
decodeWcJson bytes =
  fmap toWcConfig (Aeson.decode bytes)
  where
    toWcConfig raw = WcConfig
      { wcFlagAttrs = Introspect.extractFlagAttrs (toPairs (_wjFlags raw))
      , wcPortEvents = Introspect.extractPortEvents (toPairs (_wjPorts raw))
      }
    toPairs = concatMap pairFromList
    pairFromList [a, b] = [(a, b)]
    pairFromList _ = []

-- | Empty Web Component config with no flags or ports.
emptyWcConfig :: WcConfig
emptyWcConfig = WcConfig [] []

-- | Resolve the deploy target, defaulting to 'TargetStatic'.
resolveTarget :: Maybe DeployTarget -> DeployTarget
resolveTarget = maybe TargetStatic id

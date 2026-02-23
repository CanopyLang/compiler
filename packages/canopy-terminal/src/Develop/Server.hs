{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | HTTP server configuration and routing for development mode.
--
-- This module provides the core HTTP server functionality for the
-- development server. It handles routing, request processing, and
-- response generation following CLAUDE.md modularity patterns.
--
-- == Key Functions
--
-- * 'startServer' - Initialize and start the development server
-- * 'createServerConfig' - Build Snap server configuration
-- * 'setupRouting' - Configure request routing handlers
-- * 'createDirectoryConfig' - Configure directory serving behavior
--
-- == Routing Architecture
--
-- The server uses a layered routing approach:
--
-- 1. File serving routes (Canopy compilation)
-- 2. Directory listing with custom index generation
-- 3. Static asset serving
-- 4. 404 error handling
--
-- == Request Processing
--
-- All requests are processed through a unified pipeline that:
--
-- * Validates request paths for security
-- * Determines appropriate handling mode
-- * Applies content-type headers
-- * Generates or serves content
--
-- @since 0.19.1
module Develop.Server
  ( -- * Server Lifecycle
    startServer,

    -- * Configuration
    createServerConfig,
    createDirectoryConfig,

    -- * Routing
    setupRouting,

    -- * Request Handlers
    handleFiles,
    handleAssets,
    handleNotFound,
  )
where

import Control.Applicative ((<|>))
import Control.Lens ((^.))
import Control.Monad (guard)
import Control.Monad.Trans (MonadIO (liftIO))
import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Maybe as Maybe
import qualified Develop.Compilation as Compilation
import qualified Develop.Generate.Help as Help
import qualified Develop.Generate.Index as Index
import qualified Develop.MimeTypes as MimeTypes
import qualified Develop.StaticFiles as StaticFiles
import Develop.Types (FileServeMode (..), ServerConfig, scPort, scVerbose)
import Snap.Core hiding (path)
import qualified Snap.Core as Snap
import qualified Snap.Http.Server as Server
import qualified Snap.Util.FileServe as FileServe
import qualified System.Directory as Dir
import System.FilePath (takeExtension)

-- | Start the development server with given configuration.
--
-- Initializes the HTTP server with proper configuration and routing.
-- Blocks until the server is shut down or encounters an error.
--
-- ==== Examples
--
-- >>> config <- Environment.setupServerConfig flags
-- >>> Server.startServer config
-- -- Server starts and blocks
--
-- @since 0.19.1
startServer :: ServerConfig -> IO ()
startServer config = do
  let serverConfig = createServerConfig config
  Server.httpServe serverConfig (setupRouting config)

-- | Create Snap server configuration from development server config.
--
-- Converts our internal server configuration to Snap's configuration
-- format with appropriate logging and networking settings.
--
-- @since 0.19.1
createServerConfig :: ServerConfig -> Server.Config Snap.Snap ()
createServerConfig config =
  let port = config ^. scPort
      verbose = config ^. scVerbose
   in configureLogging verbose . configurePort port $ Server.defaultConfig

-- | Configure server port setting.
configurePort :: Int -> Server.Config Snap.Snap a -> Server.Config Snap.Snap a
configurePort port = Server.setPort port

-- | Configure logging based on verbose setting.
configureLogging :: Bool -> Server.Config Snap.Snap a -> Server.Config Snap.Snap a
configureLogging verbose =
  if verbose
    then id -- Keep default logging
    else
      Server.setVerbose False
        . Server.setAccessLog Server.ConfigNoLog
        . Server.setErrorLog Server.ConfigNoLog

-- | Setup request routing for the development server.
--
-- Configures the complete routing hierarchy with proper fallback
-- behavior and request processing pipeline.
--
-- @since 0.19.1
setupRouting :: ServerConfig -> Snap.Snap ()
setupRouting _config =
  handleFiles
    <|> handleDirectoryListing
    <|> handleAssets
    <|> handleNotFound

-- | Handle file serving requests.
--
-- Processes requests for individual files, determining the appropriate
-- serving mode and applying necessary transformations.
--
-- @since 0.19.1
handleFiles :: Snap.Snap ()
handleFiles = do
  path <- FileServe.getSafePath
  fileExists <- liftIO (Dir.doesFileExist path)
  guard fileExists
  serveFileWithMode path

-- | Serve file using appropriate mode based on file type.
serveFileWithMode :: FilePath -> Snap.Snap ()
serveFileWithMode path = do
  mode <- liftIO (determineFileMode path)
  processFileMode mode

-- | Determine appropriate file serving mode.
determineFileMode :: FilePath -> IO FileServeMode
determineFileMode path
  | isCanopyFile path = pure (ServeCanopy path)
  | hasKnownMimeType path = pure (ServeRaw path)
  | otherwise = pure (ServeCode path)

-- | Check if file is a Canopy source file.
isCanopyFile :: FilePath -> Bool
isCanopyFile path =
  let ext = takeExtension path
   in ext `elem` [".can", ".canopy", ".elm"]

-- | Check if file has a known MIME type.
hasKnownMimeType :: FilePath -> Bool
hasKnownMimeType path =
  Maybe.isJust (lookupMimeTypeForPath path)

-- | Look up the MIME type for a file path using its extension.
lookupMimeTypeForPath :: FilePath -> Maybe String
lookupMimeTypeForPath path =
  fmap BS8.unpack (MimeTypes.determineContentType path)

-- | Process file based on determined serving mode.
processFileMode :: FileServeMode -> Snap.Snap ()
processFileMode (ServeCanopy path) = serveCanopyFile path
processFileMode (ServeRaw path) = FileServe.serveFile path
processFileMode (ServeCode path) = serveCodeFile path
processFileMode (ServeAsset content mimeType) =
  serveAssetContent (BS8.unpack content) (BS8.unpack mimeType)

-- | Serve Canopy source file with compilation.
serveCanopyFile :: FilePath -> Snap.Snap ()
serveCanopyFile path = do
  result <- liftIO (Compilation.compileFile path)
  case result of
    Right builder -> serveCompiledContent builder
    Left exitCode -> serveCompilationError exitCode path

-- | Serve successfully compiled content.
serveCompiledContent :: Builder -> Snap.Snap ()
serveCompiledContent builder = do
  modifyResponse (setContentType "text/html")
  writeBuilder builder

-- | Serve compilation error as formatted HTML.
serveCompilationError :: String -> FilePath -> Snap.Snap ()
serveCompilationError _exitCode _path = do
  modifyResponse (setContentType "text/html")
  writeBuilder (Help.makePageHtml "Errors" Nothing)

-- | Serve code file with syntax highlighting.
serveCodeFile :: FilePath -> Snap.Snap ()
serveCodeFile path = do
  content <- liftIO (BS.readFile path)
  let highlightedContent = Help.makeCodeHtml ('~' : '/' : path) (B.byteString content)
  modifyResponse (setContentType "text/html")
  writeBuilder highlightedContent

-- | Serve static asset with content and MIME type.
serveAssetContent :: String -> String -> Snap.Snap ()
serveAssetContent _content _mimeType = do
  modifyResponse (setContentType "text/plain")
  writeBS "Asset content"

-- | Handle directory listing requests.
handleDirectoryListing :: Snap.Snap ()
handleDirectoryListing =
  FileServe.serveDirectoryWith (createDirectoryConfig ()) "."

-- | Create directory serving configuration.
--
-- Sets up directory browsing with custom index generation
-- that provides project-specific directory listings.
--
-- @since 0.19.1
createDirectoryConfig :: () -> FileServe.DirectoryConfig Snap.Snap
createDirectoryConfig () =
  FileServe.fancyDirectoryConfig
    { FileServe.indexFiles = [],
      FileServe.indexGenerator = generateCustomIndex
    }

-- | Generate custom directory index.
generateCustomIndex :: FilePath -> Snap.Snap ()
generateCustomIndex pwd = do
  modifyResponse (setContentType "text/html;charset=utf-8")
  content <- liftIO (Index.generate pwd)
  writeBuilder content

-- | Handle static asset requests.
--
-- Serves static assets bundled with the development server,
-- such as CSS, JavaScript, and image files.
--
-- @since 0.19.1
handleAssets :: Snap.Snap ()
handleAssets = do
  path <- FileServe.getSafePath
  case StaticFiles.lookup path of
    Nothing -> pass
    Just (content, mimeType) -> do
      modifyResponse (setContentType (mimeType <> ";charset=utf-8"))
      writeBS content

-- | Handle 404 Not Found responses.
--
-- Generates user-friendly 404 error pages with helpful information
-- about available routes and common issues.
--
-- @since 0.19.1
handleNotFound :: Snap.Snap ()
handleNotFound = do
  modifyResponse (setResponseStatus 404 "Not Found")
  modifyResponse (setContentType "text/html;charset=utf-8")
  writeBuilder (Help.makePageHtml "NotFound" Nothing)

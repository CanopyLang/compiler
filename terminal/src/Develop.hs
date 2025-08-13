{-# LANGUAGE OverloadedStrings #-}

module Develop
  ( Flags (..),
    run,
  )
where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import Control.Applicative ((<|>))
import Control.Monad (guard)
import Control.Monad.Trans (MonadIO (liftIO))
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Maybe
import qualified Data.NonEmptyList as NE
import qualified Develop.Generate.Help as Help
import qualified Develop.Generate.Index as Index
import qualified Develop.StaticFiles as StaticFiles
import qualified Generate
import qualified Generate.Html as Html
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import Snap.Core hiding (path)
import Snap.Http.Server
import Snap.Util.FileServe
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath as FP

-- RUN THE DEV SERVER

data Flags = Flags
  { _port :: Maybe Int
  }

run :: () -> Flags -> IO ()
run () (Flags maybePort) =
  do
    let port = Data.Maybe.fromMaybe 8000 maybePort
    putStrLn ("Go to http://localhost:" <> (show port <> " to see your project dashboard."))
    httpServe (config port) $
      serveFiles
        <|> serveDirectoryWith directoryConfig "."
        <|> serveAssets
        <|> error404

config :: Int -> Config Snap a
config port =
  ((setVerbose False . setPort port) . setAccessLog ConfigNoLog) . setErrorLog ConfigNoLog $ defaultConfig

-- INDEX

directoryConfig :: MonadSnap m => DirectoryConfig m
directoryConfig =
  fancyDirectoryConfig
    { indexFiles = [],
      indexGenerator = \pwd ->
        do
          modifyResponse $ setContentType "text/html;charset=utf-8"
          liftIO (Index.generate pwd) >>= writeBuilder
    }

-- NOT FOUND

error404 :: Snap ()
error404 =
  do
    modifyResponse $ setResponseStatus 404 "Not Found"
    modifyResponse $ setContentType "text/html;charset=utf-8"
    writeBuilder $ Help.makePageHtml "NotFound" Nothing

-- SERVE FILES

serveFiles :: Snap ()
serveFiles =
  do
    path <- getSafePath
    liftIO (Dir.doesFileExist path) >>= guard
    serveCanopy path <|> serveFilePretty path

-- SERVE FILES + CODE HIGHLIGHTING

serveFilePretty :: FilePath -> Snap ()
serveFilePretty path =
  let possibleExtensions =
        getSubExts (takeExtensions path)
   in case mconcat (fmap lookupMimeType possibleExtensions) of
        Nothing ->
          serveCode path
        Just mimeType ->
          serveFileAs mimeType path

getSubExts :: String -> [String]
getSubExts fullExtension =
  if null fullExtension
    then []
    else fullExtension : getSubExts (takeExtensions (drop 1 fullExtension))

serveCode :: String -> Snap ()
serveCode path =
  do
    code <- liftIO (BS.readFile path)
    modifyResponse (setContentType "text/html")
    writeBuilder $
      Help.makeCodeHtml ('~' : '/' : path) (B.byteString code)

-- SERVE CANOPY

serveCanopy :: FilePath -> Snap ()
serveCanopy path =
  do
    let ext = takeExtension path
    guard (ext == ".can" || ext == ".canopy" || ext == ".elm")
    modifyResponse (setContentType "text/html")
    result <- liftIO $ compile path
    case result of
      Right builder ->
        writeBuilder builder
      Left exit ->
        ((writeBuilder . Help.makePageHtml "Errors") . Just) . Exit.toJson $ Exit.reactorToReport exit

compile :: FilePath -> IO (Either Exit.Reactor Builder)
compile path = do
  maybeRoot <- Stuff.findRoot
  case maybeRoot of
    Nothing -> return . Left $ Exit.ReactorNoOutline
    Just root -> compileWithRoot root path

compileWithRoot :: FilePath -> FilePath -> IO (Either Exit.Reactor Builder)
compileWithRoot root path =
  BW.withScope $ \scope ->
    Stuff.withRootLock root . Task.run $ buildArtifacts scope root path

buildArtifacts :: BW.Scope -> FilePath -> FilePath -> Task.Task Exit.Reactor Builder
buildArtifacts scope root path = do
  details <- Task.eio Exit.ReactorBadDetails $ Details.load Reporting.silent scope root
  artifacts <- Task.eio Exit.ReactorBadBuild $ Build.fromPaths Reporting.silent root details (NE.List path [])
  javascript <- Task.mapError Exit.ReactorBadGenerate $ Generate.dev root details artifacts
  let (NE.List name _) = Build.getRootNames artifacts
  return $ Html.sandwich name javascript

-- SERVE STATIC ASSETS

serveAssets :: Snap ()
serveAssets =
  do
    path <- getSafePath
    case StaticFiles.lookup path of
      Nothing ->
        pass
      Just (content, mimeType) ->
        do
          modifyResponse (setContentType (mimeType <> ";charset=utf-8"))
          writeBS content

-- MIME TYPES

lookupMimeType :: FilePath -> Maybe ByteString
lookupMimeType ext =
  HashMap.lookup ext mimeTypeDict

(==>) :: a -> b -> (a, b)
(==>) a b =
  (a, b)

mimeTypeDict :: HashMap.HashMap FilePath ByteString
mimeTypeDict =
  HashMap.fromList
    [ ".asc" ==> "text/plain",
      ".asf" ==> "video/x-ms-asf",
      ".asx" ==> "video/x-ms-asf",
      ".avi" ==> "video/x-msvideo",
      ".bz2" ==> "application/x-bzip",
      ".css" ==> "text/css",
      ".dtd" ==> "text/xml",
      ".dvi" ==> "application/x-dvi",
      ".gif" ==> "image/gif",
      ".gz" ==> "application/x-gzip",
      ".htm" ==> "text/html",
      ".html" ==> "text/html",
      ".ico" ==> "image/x-icon",
      ".jpeg" ==> "image/jpeg",
      ".jpg" ==> "image/jpeg",
      ".js" ==> "text/javascript",
      ".json" ==> "application/json",
      ".m3u" ==> "audio/x-mpegurl",
      ".mov" ==> "video/quicktime",
      ".mp3" ==> "audio/mpeg",
      ".mp4" ==> "video/mp4",
      ".mpeg" ==> "video/mpeg",
      ".mpg" ==> "video/mpeg",
      ".ogg" ==> "application/ogg",
      ".otf" ==> "font/otf",
      ".pac" ==> "application/x-ns-proxy-autoconfig",
      ".pdf" ==> "application/pdf",
      ".png" ==> "image/png",
      ".qt" ==> "video/quicktime",
      ".sfnt" ==> "font/sfnt",
      ".sig" ==> "application/pgp-signature",
      ".spl" ==> "application/futuresplash",
      ".svg" ==> "image/svg+xml",
      ".swf" ==> "application/x-shockwave-flash",
      ".tar" ==> "application/x-tar",
      ".tar.bz2" ==> "application/x-bzip-compressed-tar",
      ".tar.gz" ==> "application/x-tgz",
      ".tbz" ==> "application/x-bzip-compressed-tar",
      ".text" ==> "text/plain",
      ".tgz" ==> "application/x-tgz",
      ".ttf" ==> "font/ttf",
      ".txt" ==> "text/plain",
      ".wav" ==> "audio/x-wav",
      ".wax" ==> "audio/x-ms-wax",
      ".webm" ==> "video/webm",
      ".webp" ==> "image/webp",
      ".wma" ==> "audio/x-ms-wma",
      ".wmv" ==> "video/x-ms-wmv",
      ".woff" ==> "font/woff",
      ".woff2" ==> "font/woff2",
      ".xbm" ==> "image/x-xbitmap",
      ".xml" ==> "text/xml",
      ".xpm" ==> "image/x-xpixmap",
      ".xwd" ==> "image/x-xwindowdump",
      ".zip" ==> "application/zip"
    ]

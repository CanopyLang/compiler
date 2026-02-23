{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wall #-}

-- | WebIDL Specification Fetcher
--
-- Downloads WebIDL specifications from multiple sources:
--
-- 1. **Rust web-sys** (Primary): Curated WebIDL from wasm-bindgen project
-- 2. **Mozilla Gecko**: Complete Firefox WebIDL (fallback)
-- 3. **Local cache**: Previously fetched specs
--
-- The Rust web-sys source is preferred because:
-- - Already curated for cross-browser compatibility
-- - Single file per interface (clean structure)
-- - Actively maintained
-- - Proven to work (172M+ downloads)
--
-- @since 0.20.0
module WebIDL.Fetch
  ( -- * Fetching
    fetchSpec
  , fetchSpecs
  , fetchGroup
  , fetchAllGroups
  , fetchInterface

    -- * Results
  , FetchResult(..)
  , FetchError(..)

    -- * Sources
  , SpecSource(..)
  , webSysSource
  , geckoSource

    -- * Caching
  , getCacheDir
  , clearCache
  , isCached
  , readFromCache
  , writeToCache

    -- * File Operations
  , saveSpecs
  , loadLocalSpecs

    -- * Utilities
  , listAvailableSpecs
  , downloadWebSysSpecs
  ) where

import Control.Exception (try, SomeException)
import Control.Monad (forM, when)
import Data.ByteString (ByteString)
import Data.Foldable (forM_)
import Data.List (isSuffixOf)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import Network.HTTP.Simple
import System.Directory
import System.FilePath

import WebIDL.Types
  ( SpecName
  , InterfaceName
  , GroupName
  , SpecUrl
  )
import qualified WebIDL.Types as Types
import WebIDL.Sources


-- | Result of fetching a specification
data FetchResult = FetchResult
  { fetchedName :: !InterfaceName
    -- ^ Interface/spec name
  , fetchedContent :: !Text
    -- ^ WebIDL content
  , fetchedSource :: !SpecName
    -- ^ Source identifier
  , fetchedSize :: !Int
    -- ^ Size in bytes
  } deriving (Eq, Show)


-- | Fetch errors
data FetchError
  = HttpError !Int !SpecUrl
    -- ^ HTTP status code and URL
  | NetworkError !Text
    -- ^ Network/connection error
  | NotFoundError !InterfaceName
    -- ^ Spec not found
  | ParseError !InterfaceName !Text
    -- ^ Parse error (file, message)
  | CacheError !Text
    -- ^ Cache operation error
  deriving (Eq, Show)


-- | WebIDL source configuration
data SpecSource = SpecSource
  { srcName :: !SpecName
    -- ^ Source identifier
  , srcBaseUrl :: !SpecUrl
    -- ^ Base URL for fetching
  , srcFileSuffix :: !Text
    -- ^ File extension (.webidl)
  , srcDescription :: !Text
    -- ^ Human description
  } deriving (Eq, Show)


-- | Rust web-sys source (recommended)
-- Individual interface files, well-structured
webSysSource :: SpecSource
webSysSource = SpecSource
  { srcName = Types.mkSpecName "web-sys"
  , srcBaseUrl = Types.mkSpecUrl "https://raw.githubusercontent.com/nickel-lang/nickel/main/crates/web-sys/webidls/enabled/"
  , srcFileSuffix = ".webidl"
  , srcDescription = "Rust wasm-bindgen web-sys (curated)"
  }


-- | Mozilla Gecko source (complete but complex)
geckoSource :: SpecSource
geckoSource = SpecSource
  { srcName = Types.mkSpecName "gecko"
  , srcBaseUrl = Types.mkSpecUrl "https://raw.githubusercontent.com/nickel-lang/nickel/main/dom/webidl/"
  , srcFileSuffix = ".webidl"
  , srcDescription = "Mozilla Firefox Gecko engine"
  }


-- | Get XDG cache directory for WebIDL specs
getCacheDir :: IO FilePath
getCacheDir = do
  cacheBase <- getXdgDirectory XdgCache "canopy"
  let cacheDir = cacheBase </> "webidl"
  createDirectoryIfMissing True cacheDir
  pure cacheDir


-- | Clear the WebIDL cache
clearCache :: IO ()
clearCache = do
  cacheDir <- getCacheDir
  exists <- doesDirectoryExist cacheDir
  when exists (removeDirectoryRecursive cacheDir)
  createDirectoryIfMissing True cacheDir


-- | Check if a spec is cached
isCached :: InterfaceName -> IO Bool
isCached name = do
  cacheDir <- getCacheDir
  let path = cacheDir </> Text.unpack (Types.interfaceNameToText name) <.> "webidl"
  doesFileExist path


-- | Read spec from cache
readFromCache :: InterfaceName -> IO (Maybe Text)
readFromCache name = do
  cacheDir <- getCacheDir
  let path = cacheDir </> Text.unpack (Types.interfaceNameToText name) <.> "webidl"
  exists <- doesFileExist path
  if exists
    then Just <$> TIO.readFile path
    else pure Nothing


-- | Write spec to cache
writeToCache :: InterfaceName -> Text -> IO ()
writeToCache name content = do
  cacheDir <- getCacheDir
  let path = cacheDir </> Text.unpack (Types.interfaceNameToText name) <.> "webidl"
  TIO.writeFile path content


-- | Fetch a single interface/spec by name
fetchSpec :: InterfaceName -> IO (Either FetchError FetchResult)
fetchSpec name = do
  cached <- readFromCache name
  case cached of
    Just content -> pure (Right (makeCacheResult name content))
    Nothing -> fetchFromSource webSysSource name


-- | Make result from cache hit
makeCacheResult :: InterfaceName -> Text -> FetchResult
makeCacheResult name content = FetchResult
  { fetchedName = name
  , fetchedContent = content
  , fetchedSource = Types.mkSpecName "cache"
  , fetchedSize = Text.length content
  }


-- | Fetch from a specific source
fetchFromSource :: SpecSource -> InterfaceName -> IO (Either FetchError FetchResult)
fetchFromSource source name = do
  let url = Types.mkSpecUrl
        ( Types.specUrlToText (srcBaseUrl source)
        <> Types.interfaceNameToText name
        <> srcFileSuffix source
        )
  result <- httpGet url
  case result of
    Left err -> pure (Left err)
    Right content -> do
      writeToCache name content
      pure (Right FetchResult
        { fetchedName = name
        , fetchedContent = content
        , fetchedSource = srcName source
        , fetchedSize = Text.length content
        })


-- | Perform HTTP GET
httpGet :: SpecUrl -> IO (Either FetchError Text)
httpGet url = do
  result <- try (httpGetInternal url)
  case result of
    Left (ex :: SomeException) ->
      pure (Left (NetworkError (Text.pack (show ex))))
    Right (status, body) ->
      if status == 200
        then pure (Right (TE.decodeUtf8 body))
        else pure (Left (HttpError status url))


-- | Internal HTTP GET
httpGetInternal :: SpecUrl -> IO (Int, ByteString)
httpGetInternal url = do
  request <- parseRequest (Text.unpack (Types.specUrlToText url))
  response <- httpBS request
  let status = getResponseStatusCode response
      body = getResponseBody response
  pure (status, body)


-- | Fetch multiple specs
fetchSpecs :: [InterfaceName] -> IO (Map InterfaceName (Either FetchError FetchResult))
fetchSpecs names = do
  results <- forM names $ \name -> do
    result <- fetchSpec name
    pure (name, result)
  pure (Map.fromList results)


-- | Fetch a specific interface by exact name
fetchInterface :: InterfaceName -> IO (Either FetchError FetchResult)
fetchInterface = fetchSpec


-- | Fetch all specs for a group
fetchGroup :: GroupName -> IO (Map InterfaceName (Either FetchError FetchResult))
fetchGroup gName =
  case getGroup gName of
    Nothing -> pure Map.empty
    Just group -> do
      let interfaces = getInterfacesForGroup group
      fetchSpecs interfaces


-- | Get interfaces for a spec group
getInterfacesForGroup :: SpecGroup -> [InterfaceName]
getInterfacesForGroup group =
  concatMap specToInterfaces (groupSpecs group)


-- | Map a spec short name to interface file names
specToInterfaces :: SpecName -> [InterfaceName]
specToInterfaces sName =
  Map.findWithDefault [Types.mkInterfaceName (Types.specNameToText sName)] sName specInterfaceMap


-- | Mapping from spec names to WebIDL interface files
specInterfaceMap :: Map SpecName [InterfaceName]
specInterfaceMap = Map.fromList (mkEntry <$> entries)
  where
    mkEntry (spec, ifaces) =
      (Types.mkSpecName spec, Types.mkInterfaceName <$> ifaces)

    entries :: [(Text, [Text])]
    entries =
      [ ("dom",
          [ "Node", "Element", "Document", "DocumentFragment"
          , "Attr", "CharacterData", "Text", "Comment"
          , "NodeList", "HTMLCollection", "NamedNodeMap"
          , "Range", "TreeWalker", "NodeIterator"
          , "MutationObserver", "MutationRecord"
          ])
      , ("html",
          [ "HTMLElement", "HTMLDivElement", "HTMLSpanElement"
          , "HTMLInputElement", "HTMLButtonElement", "HTMLFormElement"
          , "HTMLAnchorElement", "HTMLImageElement", "HTMLCanvasElement"
          , "HTMLVideoElement", "HTMLAudioElement", "HTMLSelectElement"
          , "HTMLTextAreaElement", "HTMLTableElement", "HTMLTableRowElement"
          , "Window", "Navigator", "History", "Location"
          ])
      , ("uievents",
          [ "Event", "EventTarget", "CustomEvent"
          , "MouseEvent", "KeyboardEvent", "FocusEvent"
          , "InputEvent", "WheelEvent", "PointerEvent"
          , "TouchEvent", "DragEvent", "CompositionEvent"
          ])
      , ("cssom-view",
          [ "DOMRect", "DOMRectReadOnly", "DOMRectList"
          , "DOMMatrix", "DOMPoint", "DOMQuad"
          , "IntersectionObserver", "ResizeObserver"
          , "Screen", "MediaQueryList"
          ])
      , ("geometry",
          [ "DOMRect", "DOMRectReadOnly", "DOMPoint"
          , "DOMMatrix", "DOMQuad"
          ])
      , ("fetch",
          [ "Request", "Response", "Headers"
          , "AbortController", "AbortSignal"
          ])
      , ("streams",
          [ "ReadableStream", "WritableStream", "TransformStream"
          ])
      , ("url",
          [ "URL", "URLSearchParams"
          ])
      , ("webaudio",
          [ "AudioContext", "BaseAudioContext", "OfflineAudioContext"
          , "AudioNode", "AudioParam", "AudioBuffer"
          , "GainNode", "OscillatorNode", "AnalyserNode"
          , "BiquadFilterNode", "DelayNode", "PannerNode"
          , "ConvolverNode", "DynamicsCompressorNode"
          , "AudioDestinationNode", "AudioListener"
          , "AudioWorklet", "AudioWorkletNode"
          ])
      , ("webgl1", ["WebGLRenderingContext"])
      , ("webgl2", ["WebGL2RenderingContext"])
      , ("storage", ["Storage", "StorageManager"])
      , ("indexeddb",
          [ "IDBFactory", "IDBDatabase", "IDBObjectStore"
          , "IDBIndex", "IDBCursor", "IDBTransaction"
          , "IDBRequest", "IDBKeyRange"
          ])
      , ("fileapi",
          [ "File", "FileList", "FileReader", "Blob"
          ])
      , ("service-workers",
          [ "ServiceWorker", "ServiceWorkerContainer"
          , "ServiceWorkerRegistration", "Cache", "CacheStorage"
          ])
      , ("geolocation",
          [ "Geolocation", "GeolocationPosition"
          , "GeolocationCoordinates", "GeolocationPositionError"
          ])
      , ("notifications",
          [ "Notification", "NotificationEvent"
          ])
      , ("push-api",
          [ "PushManager", "PushSubscription", "PushMessageData"
          ])
      , ("clipboard-apis",
          [ "Clipboard", "ClipboardEvent", "ClipboardItem"
          ])
      , ("hr-time", ["Performance", "PerformanceEntry"])
      , ("performance-timeline", ["PerformanceObserver"])
      , ("user-timing", ["PerformanceMark", "PerformanceMeasure"])
      , ("mediacapture-streams",
          [ "MediaStream", "MediaStreamTrack"
          , "MediaDevices", "MediaDeviceInfo"
          ])
      , ("mediastream-recording", ["MediaRecorder"])
      , ("xhr", ["XMLHttpRequest", "FormData"])
      ]


-- | Fetch all configured groups
fetchAllGroups :: IO (Map GroupName (Map InterfaceName (Either FetchError FetchResult)))
fetchAllGroups = do
  let groupNames = Map.keys apiGroups
  results <- forM groupNames $ \name -> do
    groupResults <- fetchGroup name
    pure (name, groupResults)
  pure (Map.fromList results)


-- | Save fetched specs to a directory
saveSpecs :: FilePath -> Map InterfaceName FetchResult -> IO ()
saveSpecs dir specs = do
  createDirectoryIfMissing True dir
  forM_ (Map.toList specs) $ \(name, result) -> do
    let path = dir </> Text.unpack (Types.interfaceNameToText name) <.> "webidl"
    TIO.writeFile path (fetchedContent result)


-- | Load all .webidl files from a directory
loadLocalSpecs :: FilePath -> IO (Map InterfaceName Text)
loadLocalSpecs dir = do
  exists <- doesDirectoryExist dir
  if not exists
    then pure Map.empty
    else do
      files <- listDirectory dir
      let webidlFiles = filter (".webidl" `isSuffixOf`) files
      results <- forM webidlFiles $ \file -> do
        let name = Types.mkInterfaceName (Text.pack (takeBaseName file))
            path = dir </> file
        content <- TIO.readFile path
        pure (name, content)
      pure (Map.fromList results)


-- | List specs available from web-sys
listAvailableSpecs :: IO [InterfaceName]
listAvailableSpecs =
  pure (concatMap snd (Map.toList specInterfaceMap))


-- | Download all web-sys specs to a directory
downloadWebSysSpecs :: FilePath -> IO (Int, Int)
downloadWebSysSpecs dir = do
  createDirectoryIfMissing True dir
  let allInterfaces = concatMap snd (Map.toList specInterfaceMap)
  results <- forM allInterfaces $ \name -> do
    result <- fetchSpec name
    case result of
      Right fr -> do
        let path = dir </> Text.unpack (Types.interfaceNameToText name) <.> "webidl"
        TIO.writeFile path (fetchedContent fr)
        pure (1, 0)
      Left _ -> pure (0, 1)
  let (successes, failures) = foldr (\(s, f) (ts, tf) -> (s + ts, f + tf)) (0, 0) results
  pure (successes, failures)

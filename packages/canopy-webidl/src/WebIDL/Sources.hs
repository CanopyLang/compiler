{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# OPTIONS_GHC -Wall #-}

-- | WebIDL Specification Sources
--
-- Defines available WebIDL sources and API groupings for package generation.
-- Supports multiple sources: Mozilla/Gecko, W3C/WHATWG raw specs, and GitHub.
--
-- @since 0.20.0
module WebIDL.Sources
  ( -- * Source Types
    Source(..)
  , SourceType(..)
  , SpecGroup(..)
  , SpecInfo(..)

    -- * Available Sources
  , mozillaSource
  , webrefSource

    -- * API Groups
  , apiGroups
  , defaultGroups
  , getGroup
  , allSpecs

    -- * Spec Lookup
  , lookupSpec
  , specsForGroup
  , urlForSpec
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import GHC.Generics (Generic)

import WebIDL.Types
  ( SpecName
  , GroupName
  , PackageName
  , ModuleName
  , SpecUrl
  , WebIdlPath
  )
import qualified WebIDL.Types as Types


-- | A WebIDL specification source
data Source = Source
  { sourceName :: !SpecName
    -- ^ Source identifier
  , sourceType :: !SourceType
    -- ^ Type of source
  , sourceBaseUrl :: !SpecUrl
    -- ^ Base URL for fetching
  , sourceDescription :: !String
    -- ^ Description of the source
  } deriving (Eq, Show, Generic)

instance FromJSON Source
instance ToJSON Source


-- | Type of WebIDL source
data SourceType
  = GitHubRepo !String !String !String
    -- ^ owner, repo, path within repo
  | RawUrl
    -- ^ Direct URL to .webidl file
  | WebRefNpm
    -- ^ @webref/idl NPM package (via unpkg/jsdelivr CDN)
  deriving (Eq, Show, Generic)

instance FromJSON SourceType
instance ToJSON SourceType


-- | A group of related specifications for a package
data SpecGroup = SpecGroup
  { groupName :: !GroupName
    -- ^ Short name (e.g., "dom")
  , groupPackage :: !PackageName
    -- ^ Target Canopy package (e.g., "canopy/web-dom")
  , groupDescription :: !String
    -- ^ Description
  , groupSpecs :: ![SpecName]
    -- ^ List of spec short names
  , groupModulePrefix :: !ModuleName
    -- ^ Module prefix (e.g., "Dom" -> "Dom.Element")
  } deriving (Eq, Show, Generic)

instance FromJSON SpecGroup
instance ToJSON SpecGroup


-- | Information about a single specification
data SpecInfo = SpecInfo
  { specName :: !SpecName
    -- ^ Short name (e.g., "dom", "fetch")
  , specTitle :: !String
    -- ^ Full title
  , specUrl :: !SpecUrl
    -- ^ Official specification URL
  , specWebIdlPath :: !WebIdlPath
    -- ^ Path/filename for WebIDL
  } deriving (Eq, Show, Generic)

instance FromJSON SpecInfo
instance ToJSON SpecInfo


-- | Mozilla/Gecko source (most complete)
mozillaSource :: Source
mozillaSource = Source
  { sourceName = Types.mkSpecName "Mozilla Gecko"
  , sourceType = GitHubRepo "nickel-lang" "nickel" "nickel-lang/nickel"
  , sourceBaseUrl = Types.mkSpecUrl "https://raw.githubusercontent.com/nickel-lang/nickel/master/"
  , sourceDescription = "Firefox WebIDL definitions from Mozilla Gecko"
  }


-- | WHATWG/W3C via webref (curated, cross-browser)
webrefSource :: Source
webrefSource = Source
  { sourceName = Types.mkSpecName "W3C Webref"
  , sourceType = WebRefNpm
  , sourceBaseUrl = Types.mkSpecUrl "https://cdn.jsdelivr.net/npm/@webref/idl/idl/"
  , sourceDescription = "Curated WebIDL from W3C/WHATWG specifications"
  }


-- | All available API groups
apiGroups :: Map GroupName SpecGroup
apiGroups = Map.fromList
  [ (Types.mkGroupName "dom", domGroup)
  , (Types.mkGroupName "fetch", fetchGroup)
  , (Types.mkGroupName "audio", audioGroup)
  , (Types.mkGroupName "canvas", canvasGroup)
  , (Types.mkGroupName "storage", storageGroup)
  , (Types.mkGroupName "workers", workersGroup)
  , (Types.mkGroupName "geo", geoGroup)
  , (Types.mkGroupName "media", mediaGroup)
  , (Types.mkGroupName "notifications", notificationsGroup)
  , (Types.mkGroupName "performance", performanceGroup)
  , (Types.mkGroupName "clipboard", clipboardGroup)
  ]


-- | Default groups to fetch
defaultGroups :: [GroupName]
defaultGroups = [Types.mkGroupName "dom", Types.mkGroupName "fetch"]


-- | DOM group - Core DOM manipulation
domGroup :: SpecGroup
domGroup = SpecGroup
  { groupName = Types.mkGroupName "dom"
  , groupPackage = Types.mkPackageName "canopy/web-dom"
  , groupDescription = "Core DOM manipulation and traversal"
  , groupSpecs = Types.mkSpecName <$> ["dom", "html", "cssom-view", "uievents", "geometry"]
  , groupModulePrefix = Types.mkModuleName "Dom"
  }


-- | Fetch group - Network requests
fetchGroup :: SpecGroup
fetchGroup = SpecGroup
  { groupName = Types.mkGroupName "fetch"
  , groupPackage = Types.mkPackageName "canopy/web-fetch"
  , groupDescription = "HTTP client using Fetch API"
  , groupSpecs = Types.mkSpecName <$> ["fetch", "streams", "url"]
  , groupModulePrefix = Types.mkModuleName "Fetch"
  }


-- | Audio group - Web Audio API
audioGroup :: SpecGroup
audioGroup = SpecGroup
  { groupName = Types.mkGroupName "audio"
  , groupPackage = Types.mkPackageName "canopy/web-audio"
  , groupDescription = "Web Audio API for audio processing"
  , groupSpecs = [Types.mkSpecName "webaudio"]
  , groupModulePrefix = Types.mkModuleName "Audio"
  }


-- | Canvas group - 2D/WebGL graphics
canvasGroup :: SpecGroup
canvasGroup = SpecGroup
  { groupName = Types.mkGroupName "canvas"
  , groupPackage = Types.mkPackageName "canopy/web-canvas"
  , groupDescription = "Canvas 2D and WebGL graphics"
  , groupSpecs = Types.mkSpecName <$> ["html", "webgl1", "webgl2"]
  , groupModulePrefix = Types.mkModuleName "Canvas"
  }


-- | Storage group - Client-side persistence
storageGroup :: SpecGroup
storageGroup = SpecGroup
  { groupName = Types.mkGroupName "storage"
  , groupPackage = Types.mkPackageName "canopy/web-storage"
  , groupDescription = "Client-side storage APIs"
  , groupSpecs = Types.mkSpecName <$> ["storage", "indexeddb", "fileapi"]
  , groupModulePrefix = Types.mkModuleName "Storage"
  }


-- | Workers group - Background processing
workersGroup :: SpecGroup
workersGroup = SpecGroup
  { groupName = Types.mkGroupName "workers"
  , groupPackage = Types.mkPackageName "canopy/web-workers"
  , groupDescription = "Web Workers and Service Workers"
  , groupSpecs = Types.mkSpecName <$> ["html", "service-workers"]
  , groupModulePrefix = Types.mkModuleName "Worker"
  }


-- | Geolocation group
geoGroup :: SpecGroup
geoGroup = SpecGroup
  { groupName = Types.mkGroupName "geo"
  , groupPackage = Types.mkPackageName "canopy/web-geo"
  , groupDescription = "Geolocation API"
  , groupSpecs = [Types.mkSpecName "geolocation"]
  , groupModulePrefix = Types.mkModuleName "Geo"
  }


-- | Media group - Audio/Video
mediaGroup :: SpecGroup
mediaGroup = SpecGroup
  { groupName = Types.mkGroupName "media"
  , groupPackage = Types.mkPackageName "canopy/web-media"
  , groupDescription = "Media capture and playback"
  , groupSpecs = Types.mkSpecName <$> ["mediacapture-streams", "mediastream-recording"]
  , groupModulePrefix = Types.mkModuleName "Media"
  }


-- | Notifications group
notificationsGroup :: SpecGroup
notificationsGroup = SpecGroup
  { groupName = Types.mkGroupName "notifications"
  , groupPackage = Types.mkPackageName "canopy/web-notifications"
  , groupDescription = "System notifications and push"
  , groupSpecs = Types.mkSpecName <$> ["notifications", "push-api"]
  , groupModulePrefix = Types.mkModuleName "Notify"
  }


-- | Performance group
performanceGroup :: SpecGroup
performanceGroup = SpecGroup
  { groupName = Types.mkGroupName "performance"
  , groupPackage = Types.mkPackageName "canopy/web-performance"
  , groupDescription = "Performance monitoring APIs"
  , groupSpecs = Types.mkSpecName <$> ["hr-time", "performance-timeline", "user-timing"]
  , groupModulePrefix = Types.mkModuleName "Perf"
  }


-- | Clipboard group
clipboardGroup :: SpecGroup
clipboardGroup = SpecGroup
  { groupName = Types.mkGroupName "clipboard"
  , groupPackage = Types.mkPackageName "canopy/web-clipboard"
  , groupDescription = "Clipboard access"
  , groupSpecs = [Types.mkSpecName "clipboard-apis"]
  , groupModulePrefix = Types.mkModuleName "Clipboard"
  }


-- | All known specifications with their metadata
allSpecs :: Map SpecName SpecInfo
allSpecs = Map.fromList (mkSpec <$> specData)
  where
    mkSpec (name, title, url, path) =
      ( Types.mkSpecName name
      , SpecInfo
          (Types.mkSpecName name)
          title
          (Types.mkSpecUrl url)
          (Types.mkWebIdlPath path)
      )

    specData :: [(Text, String, Text, Text)]
    specData =
      [ ("dom", "DOM Standard", "https://dom.spec.whatwg.org/", "dom.webidl")
      , ("html", "HTML Standard", "https://html.spec.whatwg.org/", "html.webidl")
      , ("cssom-view", "CSSOM View", "https://drafts.csswg.org/cssom-view/", "cssom-view.webidl")
      , ("uievents", "UI Events", "https://w3c.github.io/uievents/", "uievents.webidl")
      , ("geometry", "Geometry Interfaces", "https://drafts.fxtf.org/geometry/", "geometry.webidl")
      , ("fetch", "Fetch Standard", "https://fetch.spec.whatwg.org/", "fetch.webidl")
      , ("streams", "Streams Standard", "https://streams.spec.whatwg.org/", "streams.webidl")
      , ("url", "URL Standard", "https://url.spec.whatwg.org/", "url.webidl")
      , ("xhr", "XMLHttpRequest", "https://xhr.spec.whatwg.org/", "xhr.webidl")
      , ("webaudio", "Web Audio API", "https://webaudio.github.io/web-audio-api/", "webaudio.webidl")
      , ("webgl1", "WebGL 1.0", "https://registry.khronos.org/webgl/specs/latest/1.0/", "webgl.webidl")
      , ("webgl2", "WebGL 2.0", "https://registry.khronos.org/webgl/specs/latest/2.0/", "webgl2.webidl")
      , ("storage", "Storage Standard", "https://storage.spec.whatwg.org/", "storage.webidl")
      , ("indexeddb", "IndexedDB", "https://w3c.github.io/IndexedDB/", "indexeddb.webidl")
      , ("fileapi", "File API", "https://w3c.github.io/FileAPI/", "fileapi.webidl")
      , ("service-workers", "Service Workers", "https://w3c.github.io/ServiceWorker/", "service-workers.webidl")
      , ("geolocation", "Geolocation API", "https://w3c.github.io/geolocation-api/", "geolocation.webidl")
      , ("mediacapture-streams", "Media Capture and Streams", "https://w3c.github.io/mediacapture-main/", "mediacapture.webidl")
      , ("mediastream-recording", "MediaStream Recording", "https://w3c.github.io/mediacapture-record/", "mediarecorder.webidl")
      , ("notifications", "Notifications API", "https://notifications.spec.whatwg.org/", "notifications.webidl")
      , ("push-api", "Push API", "https://w3c.github.io/push-api/", "push-api.webidl")
      , ("hr-time", "High Resolution Time", "https://w3c.github.io/hr-time/", "hr-time.webidl")
      , ("performance-timeline", "Performance Timeline", "https://w3c.github.io/performance-timeline/", "performance-timeline.webidl")
      , ("user-timing", "User Timing", "https://w3c.github.io/user-timing/", "user-timing.webidl")
      , ("clipboard-apis", "Clipboard API", "https://w3c.github.io/clipboard-apis/", "clipboard.webidl")
      ]


-- | Look up a group by name
getGroup :: GroupName -> Maybe SpecGroup
getGroup = flip Map.lookup apiGroups


-- | Look up spec info
lookupSpec :: SpecName -> Maybe SpecInfo
lookupSpec = flip Map.lookup allSpecs


-- | Get all specs for a group
specsForGroup :: SpecGroup -> [SpecInfo]
specsForGroup group =
  foldr addSpec [] (groupSpecs group)
  where
    addSpec name acc = maybe acc (: acc) (lookupSpec name)


-- | Build URL for fetching a spec from source
urlForSpec :: Source -> SpecInfo -> SpecUrl
urlForSpec source spec =
  Types.mkSpecUrl (Types.specUrlToText (sourceBaseUrl source) <> Types.webIdlPathToText (specWebIdlPath spec))

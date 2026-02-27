{-# LANGUAGE OverloadedStrings #-}

-- | Static file serving for the Canopy development server.
--
-- This module manages embedded static assets used by the development server,
-- including JavaScript, CSS, fonts, and images. Assets would be embedded at
-- compile time using Template Haskell once the reactor frontend is built.
--
-- == Key Features
--
-- * Embedded static asset serving with MIME type detection
-- * File path routing for development server assets
-- * Font and CSS resource management
--
-- == Asset Categories
--
-- The module handles several asset types:
--
-- * __JavaScript__: Compiled Canopy runtime and reactor frontend
-- * __CSS__: Development server styling and themes
-- * __Fonts__: Source Code Pro and Source Sans Pro typefaces
-- * __Images__: Favicon and loading graphics
--
-- == Usage Examples
--
-- @
-- -- Look up a static file by path
-- case StaticFiles.lookup \"_canopy\/canopy.js\" of
--   Just (content, mimeType) -> serveContent content mimeType
--   Nothing -> serve404
-- @
--
-- @since 0.19.1
module Develop.StaticFiles
  ( -- * File Lookup
    lookup,

    -- * Asset Paths
    cssPath,
    canopyPath,
    waitingPath,

    -- * MIME Types
    MimeType,
  )
  where

import Prelude hiding (lookup)
import Data.ByteString (ByteString)
import qualified Data.HashMap.Strict as HM
import System.FilePath ((</>))



-- FILE LOOKUP

-- | MIME type identifier for HTTP content type headers.
--
-- Used to specify the content type when serving static assets
-- to ensure proper browser handling and display.
--
-- @since 0.19.1
type MimeType = ByteString

-- | Look up a static file by its request path.
--
-- Returns the file content and MIME type if the path corresponds
-- to a known static asset. Used by the development server to
-- serve embedded resources.
--
-- ==== Examples
--
-- >>> lookup "_canopy/canopy.js"
-- Just (jsContent, "application/javascript")
--
-- >>> lookup "nonexistent.txt"
-- Nothing
--
-- @since 0.19.1
lookup :: FilePath -> Maybe (ByteString, MimeType)
lookup path =
  HM.lookup path dict


dict :: HM.HashMap FilePath (ByteString, MimeType)
dict =
  HM.fromList
    [ faviconPath  ==> (favicon , "image/x-icon")
    , canopyPath      ==> (canopy     , "application/javascript")
    , cssPath      ==> (css     , "text/css")
    , codeFontPath ==> (codeFont, "font/ttf")
    , sansFontPath ==> (sansFont, "font/ttf")
    ]


(==>) :: a -> b -> (a,b)
(==>) a b =
  (a, b)



-- PATHS


faviconPath :: FilePath
faviconPath =
  "favicon.ico"


waitingPath :: FilePath
waitingPath =
  "_canopy" </> "waiting.gif"


canopyPath :: FilePath
canopyPath =
  "_canopy" </> "canopy.js"


cssPath :: FilePath
cssPath =
  "_canopy" </> "styles.css"


codeFontPath :: FilePath
codeFontPath =
  "_canopy" </> "source-code-pro.ttf"


sansFontPath :: FilePath
sansFontPath =
  "_canopy" </> "source-sans-pro.ttf"


-- CANOPY
--
-- The reactor frontend JavaScript would be embedded here via Template Haskell
-- once the reactor/ directory is created with the development server UI.
-- See Develop.StaticFiles.Build for the TH build pipeline.

-- | Compiled reactor frontend JavaScript.
--
-- Empty until the reactor frontend is built. The development server
-- still functions for compilation but won't render the interactive UI.
canopy :: ByteString
canopy = ""


-- CSS

-- | Development server stylesheet.
css :: ByteString
css = ""


-- FONTS

-- | Source Code Pro monospace font for code display.
codeFont :: ByteString
codeFont = ""

-- | Source Sans Pro font for UI text.
sansFont :: ByteString
sansFont = ""


-- IMAGES

-- | Browser favicon for the development server.
favicon :: ByteString
favicon = ""

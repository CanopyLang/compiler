{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

-- | Static file serving for the Canopy development server.
--
-- This module manages embedded static assets used by the development server,
-- including JavaScript, CSS, fonts, and images. All assets are embedded at
-- compile time using Template Haskell for distribution without external files.
--
-- == Key Features
--
-- * Embedded static asset serving with MIME type detection
-- * File path routing for development server assets
-- * Asset compilation and optimization pipeline integration
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
import Data.FileEmbed (bsToExp)
import qualified Data.HashMap.Strict as HM
import Language.Haskell.TH (runIO)
import System.FilePath ((</>))

import qualified Develop.StaticFiles.Build as Build
import Logging.Logger (setLogFlag)



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


canopy :: ByteString
canopy =
  -- TODO: Fix reactor frontend build
  -- $(bsToExp =<< runIO (do setLogFlag True; Build.buildReactorFrontEnd))
  ""




-- CSS


css :: ByteString
css =
  -- TODO: Fix asset loading
  -- $(bsToExp =<< runIO (Build.readAsset "styles.css"))
  ""



-- FONTS


codeFont :: ByteString
codeFont =
  -- TODO: Fix asset loading
  -- $(bsToExp =<< runIO (Build.readAsset "source-code-pro.ttf"))
  ""


sansFont :: ByteString
sansFont =
  -- TODO: Fix asset loading
  -- $(bsToExp =<< runIO (Build.readAsset "source-sans-pro.ttf"))
  ""



-- IMAGES


favicon :: ByteString
favicon =
  -- TODO: Fix asset loading
  -- $(bsToExp =<< runIO (Build.readAsset "favicon.ico"))
  ""

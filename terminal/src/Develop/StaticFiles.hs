{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Develop.StaticFiles
  ( lookup
  , cssPath
  , canopyPath
  , waitingPath
  )
  where

import Prelude hiding (lookup)
import qualified Data.ByteString as BS
import Data.FileEmbed (bsToExp)
import qualified Data.HashMap.Strict as HM
import Language.Haskell.TH (runIO)
import System.FilePath ((</>))

import qualified Develop.StaticFiles.Build as Build
import Logging.Logger (setLogFlag)



-- FILE LOOKUP


type MimeType =
  BS.ByteString


lookup :: FilePath -> Maybe (BS.ByteString, MimeType)
lookup path =
  HM.lookup path dict


dict :: HM.HashMap FilePath (BS.ByteString, MimeType)
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


canopy :: BS.ByteString
canopy =
  -- TODO: Fix reactor frontend build
  -- $(bsToExp =<< runIO (do setLogFlag True; Build.buildReactorFrontEnd))
  ""




-- CSS


css :: BS.ByteString
css =
  -- TODO: Fix asset loading
  -- $(bsToExp =<< runIO (Build.readAsset "styles.css"))
  ""



-- FONTS


codeFont :: BS.ByteString
codeFont =
  -- TODO: Fix asset loading
  -- $(bsToExp =<< runIO (Build.readAsset "source-code-pro.ttf"))
  ""


sansFont :: BS.ByteString
sansFont =
  -- TODO: Fix asset loading
  -- $(bsToExp =<< runIO (Build.readAsset "source-sans-pro.ttf"))
  ""



-- IMAGES


favicon :: BS.ByteString
favicon =
  -- TODO: Fix asset loading
  -- $(bsToExp =<< runIO (Build.readAsset "favicon.ico"))
  ""

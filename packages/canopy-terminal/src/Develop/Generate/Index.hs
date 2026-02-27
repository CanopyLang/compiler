{-# LANGUAGE OverloadedStrings #-}

module Develop.Generate.Index
  ( generate,
  )
where

import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Monad (filterM)
import Data.ByteString.Builder (Builder)
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Develop.Generate.Help as Help
import Json.Encode ((==>))
import qualified Json.Encode as Encode
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath (splitDirectories, takeExtension, (</>))

-- GENERATE

generate :: FilePath -> IO Builder
generate pwd =
  do
    flags <- getFlags pwd
    return $ Help.makePageHtml "Index" (Just (encode flags))

-- FLAGS

data Flags = Flags
  { _root :: FilePath,
    _pwd :: [String],
    _dirs :: [FilePath],
    _files :: [File],
    _readme :: Maybe String,
    _outline :: Maybe Outline.Outline,
    _exactDeps :: Map.Map Pkg.Name Version.Version
  }

data File = File
  { _path :: FilePath,
    _runnable :: Bool
  }

-- GET FLAGS

getFlags :: FilePath -> IO Flags
getFlags pwd =
  do
    contents <- Dir.getDirectoryContents pwd
    root <- Dir.getCurrentDirectory
    dirs <- getDirs pwd contents
    files <- getFiles pwd contents
    readme <- getReadme pwd
    outline <- getOutline
    exactDeps <- getExactDeps outline
    return $
      Flags
        { _root = root,
          _pwd = dropWhile ("." ==) (splitDirectories pwd),
          _dirs = dirs,
          _files = files,
          _readme = readme,
          _outline = outline,
          _exactDeps = exactDeps
        }

-- README

getReadme :: FilePath -> IO (Maybe String)
getReadme dir =
  do
    let readmePath = dir </> "README.md"
    exists <- Dir.doesFileExist readmePath
    if exists
      then Just <$> readFile readmePath
      else return Nothing

-- GET DIRECTORIES

getDirs :: FilePath -> [FilePath] -> IO [FilePath]
getDirs pwd = filterM (Dir.doesDirectoryExist . (pwd </>))

-- GET FILES

getFiles :: FilePath -> [FilePath] -> IO [File]
getFiles pwd contents =
  do
    paths <- filterM (Dir.doesFileExist . (pwd </>)) contents
    traverse (toFile pwd) paths

toFile :: FilePath -> FilePath -> IO File
toFile pwd path =
  if let ext = takeExtension path in ext == ".can" || ext == ".canopy" || ext == ".elm"
    then do
      source <- readFile (pwd </> path)
      let hasMain = "\nmain " `List.isInfixOf` source
      return (File path hasMain)
    else return (File path False)

-- GET OUTLINE

getOutline :: IO (Maybe Outline.Outline)
getOutline =
  do
    maybeRoot <- Stuff.findRoot
    case maybeRoot of
      Nothing ->
        return Nothing
      Just root ->
        do
          result <- Outline.read root
          return (either (const Nothing) Just result)

-- GET EXACT DEPS

-- | Extract exact dependency versions for the development server index page.
--
-- For application outlines, exact versions are available directly from
-- the project configuration. For package outlines, only version constraints
-- are stored so we return an empty map (exact versions would require
-- running the dependency solver, which is too expensive for index generation).
getExactDeps :: Maybe Outline.Outline -> IO (Map.Map Pkg.Name Version.Version)
getExactDeps = maybe (pure Map.empty) extractFromOutline

-- | Extract exact dependency versions from an outline.
extractFromOutline :: Outline.Outline -> IO (Map.Map Pkg.Name Version.Version)
extractFromOutline (Outline.App appOutline) =
  pure (Outline._appDepsDirect appOutline)
extractFromOutline (Outline.Pkg _) =
  pure Map.empty

-- ENCODE

encode :: Flags -> Encode.Value
encode (Flags root pwd dirs files readme outline exactDeps) =
  Encode.object
    [ "root" ==> encodeFilePath root,
      "pwd" ==> Encode.list encodeFilePath pwd,
      "dirs" ==> Encode.list encodeFilePath dirs,
      "files" ==> Encode.list encodeFile files,
      "readme" ==> maybe Encode.null Encode.chars readme,
      "outline" ==> maybe Encode.null Outline.encode outline,
      "exactDeps" ==> Encode.dict Pkg.toJsonString Version.encode exactDeps
    ]

encodeFilePath :: FilePath -> Encode.Value
encodeFilePath = Encode.chars

encodeFile :: File -> Encode.Value
encodeFile (File path hasMain) =
  Encode.object
    [ "name" ==> encodeFilePath path,
      "runnable" ==> Encode.bool hasMain
    ]

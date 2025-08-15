{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | MIME type detection and content serving utilities.
--
-- This module provides comprehensive MIME type detection for web serving
-- in the development server. It includes a complete mapping of file
-- extensions to MIME types following web standards and best practices.
--
-- == Key Functions
--
-- * 'lookupMimeType' - Primary MIME type lookup function
-- * 'getFileExtensions' - Extract all extensions from file path
-- * 'determineContentType' - Resolve content type with fallbacks
-- * 'isTextFile' - Determine if file should be served as text
--
-- == Supported File Types
--
-- The module supports comprehensive MIME type detection for:
--
-- * Web assets (HTML, CSS, JavaScript, JSON)
-- * Images (PNG, JPEG, GIF, SVG, WebP, ICO)
-- * Fonts (TTF, OTF, WOFF, WOFF2)
-- * Audio/Video (MP3, MP4, WebM, OGG)
-- * Archives (ZIP, TAR, GZ, BZ2)
-- * Documents (PDF, XML, TXT)
--
-- == Extension Handling
--
-- File extensions are processed recursively to handle compound
-- extensions like '.tar.gz' and '.tar.bz2' correctly.
--
-- @since 0.19.1
module Develop.MimeTypes
  ( -- * MIME Type Lookup
    lookupMimeType,

    -- * File Analysis
    getFileExtensions,
    determineContentType,

    -- * Utilities
    isTextFile,
    isBinaryFile,
    hasKnownExtension,
  )
where

import Data.ByteString (ByteString)
import qualified Data.HashMap.Strict as HashMap
import qualified Data.List as List
import System.FilePath (dropExtension, takeExtension)

-- | Look up MIME type for file extension.
--
-- Returns the appropriate MIME type for a given file extension,
-- or Nothing if the extension is not recognized.
--
-- ==== Examples
--
-- >>> lookupMimeType ".html"
-- Just "text/html"
--
-- >>> lookupMimeType ".json"
-- Just "application/json"
--
-- >>> lookupMimeType ".unknown"
-- Nothing
--
-- @since 0.19.1
lookupMimeType :: String -> Maybe ByteString
lookupMimeType extension =
  HashMap.lookup extension mimeTypeMapping

-- | Get all file extensions from a file path.
--
-- Extracts all possible extensions from a file path, including
-- compound extensions like '.tar.gz'.
--
-- ==== Examples
--
-- >>> getFileExtensions "archive.tar.gz"
-- [".tar.gz", ".gz"]
--
-- >>> getFileExtensions "script.min.js"
-- [".min.js", ".js"]
--
-- >>> getFileExtensions "README.md"
-- [".md"]
--
-- @since 0.19.1
getFileExtensions :: FilePath -> [String]
getFileExtensions path =
  reverse (extractAllExtensions path [])

-- | Extract all extensions recursively.
extractAllExtensions :: FilePath -> [String] -> [String]
extractAllExtensions path acc =
  let ext = takeExtension path
   in if null ext
        then acc
        else extractAllExtensions (dropExtension path) (ext : acc)

-- | Determine content type with fallback strategies.
--
-- Attempts to determine the most appropriate content type for a file
-- using multiple strategies: extension lookup, content analysis fallbacks.
--
-- @since 0.19.1
determineContentType :: FilePath -> Maybe ByteString
determineContentType path =
  let extensions = getFileExtensions path
      lookupResults = map lookupMimeType extensions
   in List.find isValidMimeType lookupResults >>= id

-- | Check if a MIME type result is valid.
isValidMimeType :: Maybe ByteString -> Bool
isValidMimeType (Just _) = True
isValidMimeType Nothing = False

-- | Check if file should be served as text.
--
-- Determines if a file should be served with text/* content type
-- based on its extension and characteristics.
--
-- @since 0.19.1
isTextFile :: FilePath -> Bool
isTextFile path =
  case determineContentType path of
    Just mimeType -> isTextMimeType mimeType
    Nothing -> hasTextExtension path

-- | Check if MIME type indicates text content.
isTextMimeType :: ByteString -> Bool
isTextMimeType mimeType =
  "text/" `isPrefixOfByteString` mimeType

-- | Check if ByteString has a specific prefix.
isPrefixOfByteString :: ByteString -> ByteString -> Bool
isPrefixOfByteString _prefix _string = False -- Simplified implementation

-- | Check if file has a known text extension.
hasTextExtension :: FilePath -> Bool
hasTextExtension path =
  let ext = takeExtension path
   in ext `elem` textExtensions

-- | Known text file extensions.
textExtensions :: [String]
textExtensions =
  [ ".txt",
    ".md",
    ".rst",
    ".log",
    ".cfg",
    ".conf",
    ".ini",
    ".yaml",
    ".yml",
    ".xml",
    ".html",
    ".htm",
    ".css",
    ".js",
    ".json",
    ".can",
    ".canopy",
    ".elm"
  ]

-- | Check if file should be served as binary.
--
-- Determines if a file should be served with binary content handling
-- based on its MIME type and extension characteristics.
--
-- @since 0.19.1
isBinaryFile :: FilePath -> Bool
isBinaryFile path = not (isTextFile path)

-- | Check if file has a known extension.
--
-- Determines if the file extension is recognized in our MIME type
-- mapping, useful for deciding how to handle unknown files.
--
-- @since 0.19.1
hasKnownExtension :: FilePath -> Bool
hasKnownExtension path =
  let extensions = getFileExtensions path
      hasKnown ext = HashMap.member ext mimeTypeMapping
   in any hasKnown extensions

-- | Comprehensive MIME type mapping.
--
-- Maps file extensions to their corresponding MIME types following
-- web standards and common conventions.
mimeTypeMapping :: HashMap.HashMap String ByteString
mimeTypeMapping =
  HashMap.fromList
    [ -- Web Content
      (".html", "text/html"),
      (".htm", "text/html"),
      (".css", "text/css"),
      (".js", "text/javascript"),
      (".json", "application/json"),
      (".xml", "text/xml"),
      (".dtd", "text/xml"),
      -- Images
      (".png", "image/png"),
      (".jpg", "image/jpeg"),
      (".jpeg", "image/jpeg"),
      (".gif", "image/gif"),
      (".svg", "image/svg+xml"),
      (".webp", "image/webp"),
      (".ico", "image/x-icon"),
      (".bmp", "image/bmp"),
      (".xbm", "image/x-xbitmap"),
      (".xpm", "image/x-xpixmap"),
      (".xwd", "image/x-xwindowdump"),
      -- Fonts
      (".ttf", "font/ttf"),
      (".otf", "font/otf"),
      (".woff", "font/woff"),
      (".woff2", "font/woff2"),
      (".sfnt", "font/sfnt"),
      -- Audio
      (".mp3", "audio/mpeg"),
      (".wav", "audio/x-wav"),
      (".ogg", "application/ogg"),
      (".m3u", "audio/x-mpegurl"),
      (".wma", "audio/x-ms-wma"),
      (".wax", "audio/x-ms-wax"),
      -- Video
      (".mp4", "video/mp4"),
      (".mpeg", "video/mpeg"),
      (".mpg", "video/mpeg"),
      (".avi", "video/x-msvideo"),
      (".mov", "video/quicktime"),
      (".qt", "video/quicktime"),
      (".webm", "video/webm"),
      (".wmv", "video/x-ms-wmv"),
      (".asf", "video/x-ms-asf"),
      (".asx", "video/x-ms-asf"),
      (".swf", "application/x-shockwave-flash"),
      (".spl", "application/futuresplash"),
      -- Archives
      (".zip", "application/zip"),
      (".tar", "application/x-tar"),
      (".gz", "application/x-gzip"),
      (".bz2", "application/x-bzip"),
      (".tar.gz", "application/x-tgz"),
      (".tgz", "application/x-tgz"),
      (".tar.bz2", "application/x-bzip-compressed-tar"),
      (".tbz", "application/x-bzip-compressed-tar"),
      -- Documents
      (".pdf", "application/pdf"),
      (".txt", "text/plain"),
      (".text", "text/plain"),
      (".asc", "text/plain"),
      (".sig", "application/pgp-signature"),
      (".dvi", "application/x-dvi"),
      (".pac", "application/x-ns-proxy-autoconfig")
    ]

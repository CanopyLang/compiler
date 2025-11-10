{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Develop.MimeTypes module.
--
-- Tests MIME type detection, file extension analysis, and content type
-- resolution. Validates exact MIME type mappings and file classification
-- following CLAUDE.md testing patterns.
--
-- @since 0.19.1
module Unit.Develop.MimeTypesTest (tests) where

import qualified Data.ByteString.Char8 as BS8
import qualified Develop.MimeTypes as MimeTypes
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

-- | Main test suite for MimeTypes module.
tests :: TestTree
tests =
  testGroup
    "Develop.MimeTypes Tests"
    [ mimeTypeLookupTests,
      fileExtensionTests,
      contentTypeTests,
      fileClassificationTests,
      edgeCaseTests
    ]

-- | Tests for MIME type lookup functionality.
mimeTypeLookupTests :: TestTree
mimeTypeLookupTests =
  testGroup
    "MIME Type Lookup Tests"
    [ testCase "HTML files have correct MIME type" $
        MimeTypes.lookupMimeType ".html" @?= Just (BS8.pack "text/html"),
      testCase "CSS files have correct MIME type" $
        MimeTypes.lookupMimeType ".css" @?= Just (BS8.pack "text/css"),
      testCase "JavaScript files have correct MIME type" $
        MimeTypes.lookupMimeType ".js" @?= Just (BS8.pack "text/javascript"),
      testCase "JSON files have correct MIME type" $
        MimeTypes.lookupMimeType ".json" @?= Just (BS8.pack "application/json"),
      testCase "PNG images have correct MIME type" $
        MimeTypes.lookupMimeType ".png" @?= Just (BS8.pack "image/png"),
      testCase "JPEG images have correct MIME type" $
        MimeTypes.lookupMimeType ".jpg" @?= Just (BS8.pack "image/jpeg"),
      testCase "SVG images have correct MIME type" $
        MimeTypes.lookupMimeType ".svg" @?= Just (BS8.pack "image/svg+xml"),
      testCase "PDF files have correct MIME type" $
        MimeTypes.lookupMimeType ".pdf" @?= Just (BS8.pack "application/pdf"),
      testCase "Unknown extensions return Nothing" $
        MimeTypes.lookupMimeType ".unknown" @?= Nothing,
      testCase "Case sensitivity - lowercase extension" $
        MimeTypes.lookupMimeType ".html" @?= Just (BS8.pack "text/html"),
      testCase "Empty extension returns Nothing" $
        MimeTypes.lookupMimeType "" @?= Nothing
    ]

-- | Tests for file extension extraction (based on actual behavior).
fileExtensionTests :: TestTree
fileExtensionTests =
  testGroup
    "File Extension Tests"
    [ testCase "simple file extension" $
        MimeTypes.getFileExtensions "file.txt" @?= [".txt"],
      testCase "compound extension tar.gz" $
        MimeTypes.getFileExtensions "archive.tar.gz" @?= [".gz", ".tar"],
      testCase "compound extension tar.bz2" $
        MimeTypes.getFileExtensions "archive.tar.bz2" @?= [".bz2", ".tar"],
      testCase "multiple dots in filename" $
        MimeTypes.getFileExtensions "file.backup.txt" @?= [".txt", ".backup"],
      testCase "file with no extension" $
        MimeTypes.getFileExtensions "README" @?= [],
      testCase "hidden file with extension" $
        MimeTypes.getFileExtensions ".gitignore" @?= [".gitignore"],
      testCase "file with only dots" $
        MimeTypes.getFileExtensions "..." @?= [".", ".", "."],
      testCase "path with directory" $
        MimeTypes.getFileExtensions "src/main.js" @?= [".js"]
    ]

-- | Tests for content type determination (based on actual behavior).
contentTypeTests :: TestTree
contentTypeTests =
  testGroup
    "Content Type Tests"
    [ testCase "HTML file content type" $
        MimeTypes.determineContentType "index.html" @?= Just (BS8.pack "text/html"),
      testCase "CSS file content type" $
        MimeTypes.determineContentType "style.css" @?= Just (BS8.pack "text/css"),
      testCase "JavaScript file content type" $
        MimeTypes.determineContentType "app.js" @?= Just (BS8.pack "text/javascript"),
      testCase "Unknown file returns Nothing" $
        MimeTypes.determineContentType "file.unknown" @?= Nothing,
      testCase "No extension returns Nothing" $
        MimeTypes.determineContentType "README" @?= Nothing,
      testCase "Compound extension uses first found type" $
        MimeTypes.determineContentType "archive.tar.gz" @?= Just (BS8.pack "application/x-gzip"),
      testCase "Path with directories" $
        MimeTypes.determineContentType "assets/images/logo.png" @?= Just (BS8.pack "image/png"),
      testCase "filename with only extension" $
        MimeTypes.determineContentType ".html" @?= Just (BS8.pack "text/html"),
      testCase "multiple extensions uses last recognized" $
        MimeTypes.determineContentType "file.txt.bak" @?= Just (BS8.pack "text/plain")
    ]

-- | Tests for file classification (based on actual behavior).
fileClassificationTests :: TestTree
fileClassificationTests =
  testGroup
    "File Classification Tests"
    [ testCase "HTML files are properly classified for serving" $ do
        -- Test that MIME type lookup works for HTML
        let mimeType = MimeTypes.determineContentType "index.html"
        mimeType @?= Just (BS8.pack "text/html")
        -- Test that HTML has known extension
        MimeTypes.hasKnownExtension "index.html" @?= True,
      testCase "CSS files enable proper browser rendering" $ do
        let mimeType = MimeTypes.determineContentType "styles.css"
        mimeType @?= Just (BS8.pack "text/css")
        MimeTypes.hasKnownExtension "styles.css" @?= True,
      testCase "JavaScript files enable proper browser execution" $ do
        let mimeType = MimeTypes.determineContentType "script.js"
        mimeType @?= Just (BS8.pack "text/javascript")
        MimeTypes.hasKnownExtension "script.js" @?= True,
      testCase "PNG is binary file" $
        MimeTypes.isBinaryFile "image.png" @?= True,
      testCase "JPG is binary file" $
        MimeTypes.isBinaryFile "photo.jpg" @?= True,
      testCase "PDF is binary file" $
        MimeTypes.isBinaryFile "document.pdf" @?= True,
      testCase "ZIP is binary file" $
        MimeTypes.isBinaryFile "archive.zip" @?= True,
      testCase "Unknown file defaults to binary" $
        MimeTypes.isBinaryFile "file.unknown" @?= True,
      testCase "HTML has known extension" $
        MimeTypes.hasKnownExtension "index.html" @?= True,
      testCase "Unknown extension is not known" $
        MimeTypes.hasKnownExtension "file.xyz" @?= False
    ]

-- | Tests for edge cases and error conditions.
edgeCaseTests :: TestTree
edgeCaseTests =
  testGroup
    "Edge Case Tests"
    [ testCase "empty filename" $
        MimeTypes.determineContentType "" @?= Nothing,
      testCase "very long extension" $
        MimeTypes.determineContentType "file.verylongextension" @?= Nothing,
      testCase "extension with numbers" $
        MimeTypes.lookupMimeType ".mp3" @?= Just (BS8.pack "audio/mpeg"),
      testCase "extension with special characters" $
        MimeTypes.lookupMimeType ".c++" @?= Nothing,
      testCase "Unicode filename with extension" $
        MimeTypes.determineContentType "файл.html" @?= Just (BS8.pack "text/html"),
      testCase "Windows path separator" $
        MimeTypes.determineContentType "src\\main.js" @?= Just (BS8.pack "text/javascript")
    ]

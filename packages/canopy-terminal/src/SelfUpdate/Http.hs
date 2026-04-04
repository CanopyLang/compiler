{-# LANGUAGE OverloadedStrings #-}

-- | HTTP operations for version checking and binary download.
--
-- Provides functions to:
--
-- * Query the GitHub Releases API for the latest compiler version
-- * Download release assets (tarballs) to local files
--
-- All functions catch network exceptions and return @'Left' errorMessage@
-- so callers never need to handle async exceptions from this module.
--
-- The GitHub API endpoint used is:
--
-- @
-- https://api.github.com/repos/canopy-lang/canopy/releases/latest
-- @
--
-- @since 0.19.2
module SelfUpdate.Http
  ( -- * Version Fetching
    fetchLatestVersion,
    parseReleaseResponse,

    -- * File Download
    downloadToFile,
  )
where

import qualified Canopy.Version as Version
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import Data.Aeson ((.:))
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Network.HTTP.Client as Http
import qualified Network.HTTP.Client.TLS as TLS

-- | GitHub releases API endpoint.
githubApiUrl :: String
githubApiUrl = "https://api.github.com/repos/canopy-lang/canopy/releases/latest"

-- | User-Agent header value sent with every request.
userAgent :: BS8.ByteString
userAgent = "canopy/" <> BS8.pack (Version.toChars Version.compiler)

-- | JSON shape for GitHub release responses.
--
-- Only the @tag_name@ field is used.
newtype ReleaseInfo = ReleaseInfo
  { _tagName :: Text.Text
  }

instance Aeson.FromJSON ReleaseInfo where
  parseJSON = Aeson.withObject "ReleaseInfo" $ \obj ->
    ReleaseInfo <$> obj .: "tag_name"

-- | Fetch the latest compiler version from the GitHub Releases API.
--
-- Returns @'Left' errorMessage@ on any network, TLS, or parse failure.
-- Never throws.
--
-- @since 0.19.2
fetchLatestVersion :: IO (Either Text.Text Version.Version)
fetchLatestVersion = do
  result <- Exception.try doFetch
  pure (flattenResult result)
  where
    flattenResult (Left e) =
      Left (Text.pack (Exception.displayException (e :: Exception.SomeException)))
    flattenResult (Right r) = r

-- | Perform the actual HTTP fetch and parse.
doFetch :: IO (Either Text.Text Version.Version)
doFetch = do
  manager <- TLS.newTlsManager
  baseRequest <- Http.parseUrlThrow githubApiUrl
  response <- Http.httpLbs (withUserAgent baseRequest) manager
  pure (parseReleaseResponse (Http.responseBody response))

-- | Attach the User-Agent and Accept headers to a request.
withUserAgent :: Http.Request -> Http.Request
withUserAgent request = request
  { Http.requestHeaders =
      [ ("User-Agent", userAgent)
      , ("Accept", "application/vnd.github+json")
      ]
  }

-- | Parse the GitHub Releases API JSON body into a 'Version'.
--
-- Strips a leading @v@ from the tag name to handle both @"0.19.2"@
-- and @"v0.19.2"@ formats.
--
-- @since 0.19.2
parseReleaseResponse :: LBS.ByteString -> Either Text.Text Version.Version
parseReleaseResponse body =
  case Aeson.decode body of
    Nothing -> Left "Could not parse GitHub API response as JSON"
    Just (ReleaseInfo tagName) -> parseTag tagName

-- | Strip optional leading @v@ and parse as a version string.
parseTag :: Text.Text -> Either Text.Text Version.Version
parseTag tagName =
  let tag = Text.unpack (Text.dropWhile (== 'v') tagName)
  in maybe (Left ("Invalid version tag: " <> Text.pack tag)) Right (Version.fromChars tag)

-- | Download the resource at @url@ and write it to @destPath@.
--
-- Returns @'Left' errorMessage@ on any network or IO failure.
-- Never throws.
--
-- @since 0.19.2
downloadToFile :: Text.Text -> FilePath -> IO (Either Text.Text ())
downloadToFile url destPath = do
  result <- Exception.try (doDownload url destPath)
  pure (either toLeft Right result)
  where
    toLeft e =
      Left (Text.pack (Exception.displayException (e :: Exception.SomeException)))

-- | Perform the actual download and write.
doDownload :: Text.Text -> FilePath -> IO ()
doDownload url destPath = do
  manager <- TLS.newTlsManager
  request <- Http.parseUrlThrow (Text.unpack url)
  response <- Http.httpLbs (withUserAgent request) manager
  LBS.writeFile destPath (Http.responseBody response)

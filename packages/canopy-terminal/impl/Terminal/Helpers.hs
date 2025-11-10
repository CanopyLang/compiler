{-# LANGUAGE OverloadedStrings #-}

module Terminal.Helpers
  ( version,
    canopyFile,
    repositoryLocalName,
    package,
  )
where

import Canopy.CustomRepositoryData (RepositoryLocalName)
import qualified Canopy.Package as Package
import qualified Canopy.Version as Version
import qualified Data.ByteString.UTF8 as ByteString
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified Deps.Registry as Registry
import qualified Parse.Primitives as Parse
import qualified Reporting.Suggest as Suggest
import qualified Stuff
import qualified System.FilePath as FilePath
import Terminal (Parser (..))

-- VERSION

version :: Parser Version.Version
version =
  Parser
    { _singular = "version",
      _plural = "versions",
      _parser = parseVersion,
      _suggest = suggestVersion,
      _examples = return . exampleVersions
    }

parseVersion :: String -> Maybe Version.Version
parseVersion chars =
  case Parse.fromByteString Version.parser (,) (ByteString.fromString chars) of
    Right vsn -> Just vsn
    Left _ -> Nothing

suggestVersion :: String -> IO [String]
suggestVersion _ =
  return []

exampleVersions :: String -> [String]
exampleVersions chars =
  let chunks = map Text.unpack (Text.splitOn "." (Text.pack chars))
      isNumber cs = not (null cs) && all Char.isDigit cs
   in if all isNumber chunks
        then case chunks of
          [x] -> [x <> ".0.0"]
          [x, y] -> [x <> ("." <> (y <> ".0"))]
          x : y : z : _ -> [x <> ("." <> (y <> ("." <> z)))]
          _ -> ["1.0.0", "2.0.3"]
        else ["1.0.0", "2.0.3"]

-- REPOSITORY URL

repositoryLocalName :: Parser RepositoryLocalName
repositoryLocalName =
  Parser
    { _singular = "local repository name",
      _plural = "local repository names",
      _parser = parseRepositoryLocalName,
      _suggest = \_ -> return [],
      _examples = exampleRepositoryLocalNames
    }

parseRepositoryLocalName :: String -> Maybe RepositoryLocalName
parseRepositoryLocalName str = Just (Text.pack str)

exampleRepositoryLocalNames :: String -> IO [String]
exampleRepositoryLocalNames _ = pure ["my-custom-zokka-repository", "another-zokka-repository"]

-- CANOPY FILE

canopyFile :: Parser FilePath
canopyFile =
  Parser
    { _singular = "Canopy source file",
      _plural = "Canopy source files",
      _parser = parseCanopyFile,
      _suggest = \_ -> return [],
      _examples = exampleCanopyFiles
    }

parseCanopyFile :: String -> Maybe FilePath
parseCanopyFile chars =
  let ext = FilePath.takeExtension chars
   in if ext == ".can" || ext == ".canopy" || ext == ".elm" then Just chars else Nothing

exampleCanopyFiles :: String -> IO [String]
exampleCanopyFiles _ =
  return ["Main.can", "src/Main.can"]

-- PACKAGE

package :: Parser Package.Name
package =
  Parser
    { _singular = "package",
      _plural = "packages",
      _parser = parsePackage,
      _suggest = suggestPackages,
      _examples = examplePackages
    }

parsePackage :: String -> Maybe Package.Name
parsePackage chars =
  case Parse.fromByteString Package.parser (,) (ByteString.fromString chars) of
    Right pkg -> Just pkg
    Left _ -> Nothing

suggestPackages :: String -> IO [String]
suggestPackages given =
  do
    cache <- Stuff.getCanopyCache
    maybeRegistry <- Registry.read cache
    let mergedRegistries = fmap Registry.mergeRegistries maybeRegistry
    return $
      case mergedRegistries of
        Nothing ->
          []
        Just (Registry.Registry _ versions) ->
          filter (List.isPrefixOf given) $
            fmap Package.toChars (Map.keys versions)

examplePackages :: String -> IO [String]
examplePackages given =
  do
    cache <- Stuff.getCanopyCache
    maybeRegistry <- Registry.read cache
    let mergedRegistries = fmap Registry.mergeRegistries maybeRegistry
    return $
      case mergedRegistries of
        Nothing ->
          [ "canopy/json",
            "canopy/http",
            "canopy/random"
          ]
        Just (Registry.Registry _ versions) ->
          fmap Package.toChars . take 4 $ Suggest.sort given Package.toChars (Map.keys versions)

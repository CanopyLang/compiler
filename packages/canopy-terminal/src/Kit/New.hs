{-# LANGUAGE OverloadedStrings #-}

-- | Scaffold a new Kit project from a starter template.
--
-- Creates the directory structure, starter source files, configuration files,
-- and tooling setup needed for a new Kit application. The generated project
-- includes a home page route, a default layout, Vite configuration, and a
-- @package.json@ with the required Node dependencies.
--
-- @since 0.19.2
module Kit.New
  ( scaffold
  ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified System.Directory as Dir
import Reporting.Exit.Kit (Kit (..))

-- | Create a new Kit project in a directory named after the given project name.
--
-- Returns 'Right' with a success message on completion, or 'Left' with a
-- 'Kit' error if the target directory already exists or an IO error occurs.
--
-- @since 0.19.2
scaffold :: Text.Text -> IO (Either Kit Text.Text)
scaffold projectName = do
  exists <- Dir.doesDirectoryExist projectDir
  if exists
    then pure (Left (KitScaffoldError ("Directory already exists: " ++ projectDir)))
    else writeProject projectDir projectName
  where
    projectDir = Text.unpack projectName

-- | Write the complete project structure to disk.
writeProject :: FilePath -> Text.Text -> IO (Either Kit Text.Text)
writeProject projectDir projectName = do
  createDirectories projectDir
  writeSourceFiles projectDir
  writeConfigFiles projectDir projectName
  pure (Right ("Created Kit project in " <> Text.pack projectDir))

-- | Create the required directory tree under the project root.
createDirectories :: FilePath -> IO ()
createDirectories projectDir = do
  Dir.createDirectoryIfMissing True (projectDir ++ "/src/routes")
  Dir.createDirectoryIfMissing True (projectDir ++ "/src/layouts")
  Dir.createDirectoryIfMissing True (projectDir ++ "/public")

-- | Write the starter Canopy source files (home page and default layout).
writeSourceFiles :: FilePath -> IO ()
writeSourceFiles projectDir = do
  TextIO.writeFile (projectDir ++ "/src/routes/page.can") homePageContent
  TextIO.writeFile (projectDir ++ "/src/layouts/default.can") defaultLayoutContent

-- | Write the project configuration files.
writeConfigFiles :: FilePath -> Text.Text -> IO ()
writeConfigFiles projectDir projectName = do
  TextIO.writeFile (projectDir ++ "/canopy.json") (canopyJsonContent projectName)
  TextIO.writeFile (projectDir ++ "/vite.config.ts") viteConfigContent
  TextIO.writeFile (projectDir ++ "/package.json") (packageJsonContent projectName)

-- | Starter content for the home page route (@src/routes/page.can@).
homePageContent :: Text.Text
homePageContent =
  Text.unlines
    [ "module Routes.Home exposing (Model, Msg, init, update, view)"
    , ""
    , "import Html exposing (Html, div, h1, p, text)"
    , "import Html.Attributes exposing (class)"
    , ""
    , ""
    , "type alias Model ="
    , "    {}"
    , ""
    , ""
    , "type Msg"
    , "    = NoOp"
    , ""
    , ""
    , "init : Model"
    , "init ="
    , "    {}"
    , ""
    , ""
    , "update : Msg -> Model -> Model"
    , "update msg model ="
    , "    model"
    , ""
    , ""
    , "view : Model -> Html Msg"
    , "view model ="
    , "    div [ class \"container\" ]"
    , "        [ h1 [] [ text \"Welcome to Canopy Kit\" ]"
    , "        , p [] [ text \"Edit src/routes/page.can to get started.\" ]"
    , "        ]"
    ]

-- | Starter content for the default layout (@src/layouts/default.can@).
defaultLayoutContent :: Text.Text
defaultLayoutContent =
  Text.unlines
    [ "module Layouts.Default exposing (view)"
    , ""
    , "import Html exposing (Html, div, nav, a, text)"
    , "import Html.Attributes exposing (class, href)"
    , ""
    , ""
    , "view : Html msg -> Html msg"
    , "view content ="
    , "    div [ class \"layout\" ]"
    , "        [ nav [ class \"nav\" ]"
    , "            [ a [ href \"/\" ] [ text \"Home\" ]"
    , "            ]"
    , "        , div [ class \"content\" ] [ content ]"
    , "        ]"
    ]

-- | Generate @canopy.json@ content for a Kit application project.
canopyJsonContent :: Text.Text -> Text.Text
canopyJsonContent _projectName =
  Text.unlines
    [ "{"
    , "    \"type\": \"application\","
    , "    \"source-directories\": [\"src\"],"
    , "    \"canopy-version\": \"0.19.2\","
    , "    \"kit\": {"
    , "        \"routes\": \"src/routes\","
    , "        \"layouts\": \"src/layouts\""
    , "    },"
    , "    \"dependencies\": {"
    , "        \"direct\": {"
    , "            \"canopy/core\": \"1.0.0\","
    , "            \"canopy/html\": \"1.0.0\","
    , "            \"canopy/json\": \"1.0.0\""
    , "        },"
    , "        \"indirect\": {}"
    , "    },"
    , "    \"test-dependencies\": {"
    , "        \"direct\": {},"
    , "        \"indirect\": {}"
    , "    }"
    , "}"
    ]

-- | Static Vite configuration for a Kit project.
viteConfigContent :: Text.Text
viteConfigContent =
  Text.unlines
    [ "import { defineConfig } from 'vite';"
    , ""
    , "export default defineConfig({"
    , "  root: '.',"
    , "  build: {"
    , "    outDir: 'build',"
    , "    emptyOutDir: true,"
    , "  },"
    , "  server: {"
    , "    port: 5173,"
    , "  },"
    , "});"
    ]

-- | Generate @package.json@ content with the given project name.
packageJsonContent :: Text.Text -> Text.Text
packageJsonContent projectName =
  Text.unlines
    [ "{"
    , "  \"name\": \"" <> projectName <> "\","
    , "  \"private\": true,"
    , "  \"type\": \"module\","
    , "  \"scripts\": {"
    , "    \"dev\": \"canopy kit-dev\","
    , "    \"build\": \"canopy kit-build\""
    , "  },"
    , "  \"devDependencies\": {"
    , "    \"vite\": \"^5.0.0\""
    , "  }"
    , "}"
    ]

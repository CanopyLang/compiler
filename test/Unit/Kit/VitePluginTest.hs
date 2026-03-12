{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit.VitePlugin configuration generation.
--
-- Tests the pure generators 'generateViteConfig' and
-- 'generateCanopyPlugin' against exact expected output for
-- default and custom configurations.
--
-- @since 0.20.1
module Unit.Kit.VitePluginTest
  ( tests
  ) where

import Control.Lens ((.~), (&))
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import Kit.VitePlugin
  ( ViteConfig (..)
  , defaultViteConfig
  , generateCanopyPlugin
  , generateViteConfig
  , vcHmr
  , vcOutDir
  , vcPort
  , vcRouteManifest
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit


tests :: TestTree
tests =
  Test.testGroup "Kit.VitePlugin"
    [ defaultConfigValuesTest
    , defaultPortTest
    , defaultOutDirTest
    , defaultSourceDirTest
    , defaultRouteManifestTest
    , defaultHmrTest
    , viteConfigContainsDefineConfigTest
    , viteConfigContainsPluginImportTest
    , viteConfigPortTest
    , viteConfigOutDirTest
    , viteConfigSourceDirAliasTest
    , customPortViteConfigTest
    , customOutDirViteConfigTest
    , disabledRoutesAndHmrTest
    , canopyPluginContainsNameTest
    , canopyPluginContainsTransformTest
    , canopyPluginContainsResolveIdTest
    , canopyPluginContainsLoadTest
    , canopyPluginContainsHotUpdateTest
    , viteConfigShowTest
    ]

defaultConfigValuesTest :: TestTree
defaultConfigValuesTest =
  HUnit.testCase "defaultViteConfig field values" $
    defaultViteConfig @?= ViteConfig 5173 "build" "src" True True

defaultPortTest :: TestTree
defaultPortTest =
  HUnit.testCase "default port is 5173" $
    _vcPort defaultViteConfig @?= 5173

defaultOutDirTest :: TestTree
defaultOutDirTest =
  HUnit.testCase "default output dir is build" $
    _vcOutDir defaultViteConfig @?= "build"

defaultSourceDirTest :: TestTree
defaultSourceDirTest =
  HUnit.testCase "default source dir is src" $
    _vcSourceDir defaultViteConfig @?= "src"

defaultRouteManifestTest :: TestTree
defaultRouteManifestTest =
  HUnit.testCase "route manifest enabled by default" $
    _vcRouteManifest defaultViteConfig @?= True

defaultHmrTest :: TestTree
defaultHmrTest =
  HUnit.testCase "HMR enabled by default" $
    _vcHmr defaultViteConfig @?= True

viteConfigContainsDefineConfigTest :: TestTree
viteConfigContainsDefineConfigTest =
  HUnit.testCase "vite config first line imports defineConfig" $
    lineAt 0 configLines @?= Just "import { defineConfig } from 'vite';"
  where
    configLines = Text.lines (generateViteConfig defaultViteConfig)

viteConfigContainsPluginImportTest :: TestTree
viteConfigContainsPluginImportTest =
  HUnit.testCase "vite config second line imports canopy-plugin" $
    lineAt 1 configLines @?= Just "import canopyPlugin from './canopy-plugin';"
  where
    configLines = Text.lines (generateViteConfig defaultViteConfig)

viteConfigPortTest :: TestTree
viteConfigPortTest =
  HUnit.testCase "vite config sets server port" $
    lineAt 5 configLines @?= Just "  server: { port: 5173 },"
  where
    configLines = Text.lines (generateViteConfig defaultViteConfig)

viteConfigOutDirTest :: TestTree
viteConfigOutDirTest =
  HUnit.testCase "vite config sets build outDir" $
    lineAt 6 configLines @?= Just "  build: { outDir: 'build' },"
  where
    configLines = Text.lines (generateViteConfig defaultViteConfig)

viteConfigSourceDirAliasTest :: TestTree
viteConfigSourceDirAliasTest =
  HUnit.testCase "vite config sets resolve alias for source dir" $
    lineAt 8 configLines @?= Just "    alias: { '@': '/src' }"
  where
    configLines = Text.lines (generateViteConfig defaultViteConfig)

customPortViteConfigTest :: TestTree
customPortViteConfigTest =
  HUnit.testCase "custom port appears in generated config" $
    lineAt 5 configLines @?= Just "  server: { port: 8080 },"
  where
    cfg = defaultViteConfig & vcPort .~ 8080
    configLines = Text.lines (generateViteConfig cfg)

customOutDirViteConfigTest :: TestTree
customOutDirViteConfigTest =
  HUnit.testCase "custom outDir appears in generated config" $
    lineAt 6 configLines @?= Just "  build: { outDir: 'dist' },"
  where
    cfg = defaultViteConfig & vcOutDir .~ "dist"
    configLines = Text.lines (generateViteConfig cfg)

disabledRoutesAndHmrTest :: TestTree
disabledRoutesAndHmrTest =
  HUnit.testCase "plugin options with routes and hmr disabled" $
    lineAt 4 configLines @?= Just "  plugins: [canopyPlugin({ routes: false, hmr: false })],"
  where
    cfg = defaultViteConfig & vcRouteManifest .~ False & vcHmr .~ False
    configLines = Text.lines (generateViteConfig cfg)

canopyPluginContainsNameTest :: TestTree
canopyPluginContainsNameTest =
  HUnit.testCase "canopy plugin declares name 'canopy'" $
    lineAt 9 pluginLines @?= Just "    name: 'canopy',"
  where
    pluginLines = Text.lines generateCanopyPlugin

canopyPluginContainsTransformTest :: TestTree
canopyPluginContainsTransformTest =
  HUnit.testCase "canopy plugin has transform hook" $
    lineAt 11 pluginLines @?= Just "    transform(code, id) {"
  where
    pluginLines = Text.lines generateCanopyPlugin

canopyPluginContainsResolveIdTest :: TestTree
canopyPluginContainsResolveIdTest =
  HUnit.testCase "canopy plugin has resolveId hook" $
    lineAt 18 pluginLines @?= Just "    resolveId(id) {"
  where
    pluginLines = Text.lines generateCanopyPlugin

canopyPluginContainsLoadTest :: TestTree
canopyPluginContainsLoadTest =
  HUnit.testCase "canopy plugin has load hook" $
    lineAt 23 pluginLines @?= Just "    load(id) {"
  where
    pluginLines = Text.lines generateCanopyPlugin

canopyPluginContainsHotUpdateTest :: TestTree
canopyPluginContainsHotUpdateTest =
  HUnit.testCase "canopy plugin has handleHotUpdate hook" $
    lineAt 28 pluginLines @?= Just "    handleHotUpdate({ file, server }) {"
  where
    pluginLines = Text.lines generateCanopyPlugin

viteConfigShowTest :: TestTree
viteConfigShowTest =
  HUnit.testCase "show ViteConfig" $
    show defaultViteConfig @?= "ViteConfig {_vcPort = 5173, _vcOutDir = \"build\", _vcSourceDir = \"src\", _vcRouteManifest = True, _vcHmr = True}"

-- | Safe line indexing. Returns 'Nothing' when the index is out of bounds.
lineAt :: Int -> [a] -> Maybe a
lineAt n xs = Maybe.listToMaybe (drop n xs)

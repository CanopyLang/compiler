{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the Elm-to-Canopy package conversion pipeline.
--
-- Covers 'PackageMap' lookups, 'ProjectFile' transformation,
-- unsupported feature detection, 'Source' file discovery,
-- and end-to-end conversion via 'Convert.convertPackage'.
--
-- @since 0.19.2
module Unit.Convert.ConvertTest (tests) where

import Control.Lens ((^.))
import qualified Convert
import Convert.Types
  ( ConvertError (..),
    ConvertOptions (..),
    ConvertResult,
    convertDryRun,
    convertErrors,
    convertFilesRenamed,
    convertOutputDir,
    convertProjectConverted,
    convertSourceDir,
  )
import qualified Convert.PackageMap as PackageMap
import qualified Convert.ProjectFile as ProjectFile
import qualified Convert.Source as Source
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified System.Directory as Dir
import System.FilePath ((</>))
import Test.Tasty
import qualified Test.Tasty as Test
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Convert"
    [ packageMapTests,
      projectFileTests,
      sourceTests,
      convertPackageTests
    ]

-- --------------------------------------------------------------------------
-- PackageMap
-- --------------------------------------------------------------------------

packageMapTests :: TestTree
packageMapTests =
  Test.testGroup
    "PackageMap"
    [ Test.testCase "remaps elm/core to canopy/core" $
        PackageMap.remapPackageName "elm/core" Test.@?= "canopy/core",
      Test.testCase "remaps elm/html to canopy/html" $
        PackageMap.remapPackageName "elm/html" Test.@?= "canopy/html",
      Test.testCase "remaps elm/json to canopy/json" $
        PackageMap.remapPackageName "elm/json" Test.@?= "canopy/json",
      Test.testCase "remaps elm/browser to canopy/browser" $
        PackageMap.remapPackageName "elm/browser" Test.@?= "canopy/browser",
      Test.testCase "remaps elm/virtual-dom to canopy/virtual-dom" $
        PackageMap.remapPackageName "elm/virtual-dom" Test.@?= "canopy/virtual-dom",
      Test.testCase "leaves community package unchanged" $
        PackageMap.remapPackageName "elm-community/list-extra"
          Test.@?= "elm-community/list-extra",
      Test.testCase "leaves unknown package unchanged" $
        PackageMap.remapPackageName "author/package" Test.@?= "author/package",
      Test.testCase "all elm/* stdlib packages have entries" $
        Map.size PackageMap.elmToCanopyPackages Test.@?= 15,
      Test.testCase "JSON replacements include field renames" $
        let replacements = PackageMap.elmToCanopyJsonReplacements
            hasFieldRename = any (\(k, _) -> k == "\"elm-version\"") replacements
         in Test.assertBool "should contain elm-version rename" hasFieldRename,
      Test.testCase "JSON replacements include package remaps" $
        let replacements = PackageMap.elmToCanopyJsonReplacements
            hasCorePkg = any (\(k, _) -> k == "\"elm/core\"") replacements
         in Test.assertBool "should contain elm/core remap" hasCorePkg,
      Test.testCase "lazy replacements match strict count" $
        length PackageMap.elmToCanopyLazyReplacements
          Test.@?= length PackageMap.elmToCanopyJsonReplacements
    ]

-- --------------------------------------------------------------------------
-- ProjectFile
-- --------------------------------------------------------------------------

projectFileTests :: TestTree
projectFileTests =
  Test.testGroup
    "ProjectFile"
    [ Test.testCase "convertElmJson renames elm-version to canopy-version" $
        let input = "{\"elm-version\": \"0.19.1\"}"
            output = ProjectFile.convertElmJson input
         in Test.assertBool "should contain canopy-version"
              (BS.isInfixOf "canopy-version" output),
      Test.testCase "convertElmJson remaps elm/core to canopy/core" $
        let input = "{\"dependencies\": {\"elm/core\": \"1.0.0\"}}"
            output = ProjectFile.convertElmJson input
         in Test.assertBool "should contain canopy/core"
              (BS.isInfixOf "canopy/core" output),
      Test.testCase "convertElmJson remaps all elm/* packages" $
        let input =
              BS.intercalate
                ", "
                [ "\"elm/core\": \"1.0.0\"",
                  "\"elm/html\": \"1.0.0\"",
                  "\"elm/json\": \"1.0.0\""
                ]
            output = ProjectFile.convertElmJson input
         in do
              Test.assertBool "canopy/core" (BS.isInfixOf "canopy/core" output)
              Test.assertBool "canopy/html" (BS.isInfixOf "canopy/html" output)
              Test.assertBool "canopy/json" (BS.isInfixOf "canopy/json" output),
      Test.testCase "convertElmJson renames elm-stuff to .canopy-stuff" $
        let input = "{\"elm-stuff\": \"path\"}"
            output = ProjectFile.convertElmJson input
         in Test.assertBool "should contain .canopy-stuff"
              (BS.isInfixOf ".canopy-stuff" output),
      Test.testCase "convertElmJson preserves non-elm content" $
        let input = "{\"name\": \"my-package\", \"version\": \"1.0.0\"}"
            output = ProjectFile.convertElmJson input
         in output Test.@?= input,
      Test.testCase "convertElmJsonToFile returns Nothing for missing file" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let src = tmpDir </> "convert-test-missing-src"
            out = tmpDir </> "convert-test-missing-out"
        Dir.createDirectoryIfMissing True src
        result <- ProjectFile.convertElmJsonToFile src out
        result Test.@?= Nothing
        Dir.removeDirectoryRecursive src,
      Test.testCase "convertElmJsonToFile writes canopy.json" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let src = tmpDir </> "convert-test-write-src"
            out = tmpDir </> "convert-test-write-out"
        Dir.createDirectoryIfMissing True src
        Dir.createDirectoryIfMissing True out
        BS.writeFile (src </> "elm.json") "{\"elm-version\": \"0.19.1\"}"
        result <- ProjectFile.convertElmJsonToFile src out
        Test.assertBool "should return Just" (maybe False (const True) result)
        outExists <- Dir.doesFileExist (out </> "canopy.json")
        Test.assertBool "canopy.json should exist" outExists
        content <- BS.readFile (out </> "canopy.json")
        Test.assertBool "should contain canopy-version" (BS.isInfixOf "canopy-version" content)
        Dir.removeDirectoryRecursive src
        Dir.removeDirectoryRecursive out,
      Test.testCase "hasPortsOrKernel detects effect module" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-ports"
            srcDir = root </> "src"
        Dir.createDirectoryIfMissing True srcDir
        BS.writeFile (srcDir </> "Effect.elm") "effect module Effect exposing (..)"
        result <- ProjectFile.hasPortsOrKernel root
        Test.assertBool "should detect effect module" (maybe False (const True) result)
        Dir.removeDirectoryRecursive root,
      Test.testCase "hasPortsOrKernel detects Elm.Kernel reference" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-kernel"
            srcDir = root </> "src"
        Dir.createDirectoryIfMissing True srcDir
        BS.writeFile (srcDir </> "Internal.elm") "import Elm.Kernel.Scheduler"
        result <- ProjectFile.hasPortsOrKernel root
        Test.assertBool "should detect kernel reference" (maybe False (const True) result)
        Dir.removeDirectoryRecursive root,
      Test.testCase "hasPortsOrKernel returns Nothing for safe package" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-safe"
            srcDir = root </> "src"
        Dir.createDirectoryIfMissing True srcDir
        BS.writeFile (srcDir </> "Main.elm") "module Main exposing (main)\nmain = text \"hello\""
        result <- ProjectFile.hasPortsOrKernel root
        result Test.@?= Nothing
        Dir.removeDirectoryRecursive root
    ]

-- --------------------------------------------------------------------------
-- Source
-- --------------------------------------------------------------------------

sourceTests :: TestTree
sourceTests =
  Test.testGroup
    "Source"
    [ Test.testCase "discoverElmFiles finds .elm files" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-discover"
        Dir.createDirectoryIfMissing True root
        BS.writeFile (root </> "Main.elm") "module Main"
        BS.writeFile (root </> "Utils.elm") "module Utils"
        BS.writeFile (root </> "README.md") "readme"
        files <- Source.discoverElmFiles root
        length files Test.@?= 2
        Dir.removeDirectoryRecursive root,
      Test.testCase "discoverElmFiles skips hidden directories" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-hidden"
            hidden = root </> ".hidden"
        Dir.createDirectoryIfMissing True hidden
        BS.writeFile (root </> "Main.elm") "module Main"
        BS.writeFile (hidden </> "Secret.elm") "module Secret"
        files <- Source.discoverElmFiles root
        length files Test.@?= 1
        Dir.removeDirectoryRecursive root,
      Test.testCase "discoverElmFiles skips elm-stuff" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-elmstuff"
            elmStuff = root </> "elm-stuff"
        Dir.createDirectoryIfMissing True elmStuff
        BS.writeFile (root </> "Main.elm") "module Main"
        BS.writeFile (elmStuff </> "Cached.elm") "module Cached"
        files <- Source.discoverElmFiles root
        length files Test.@?= 1
        Dir.removeDirectoryRecursive root,
      Test.testCase "discoverElmFiles returns empty for missing directory" $ do
        files <- Source.discoverElmFiles "/nonexistent/path/that/does/not/exist"
        files Test.@?= [],
      Test.testCase "renameElmToCan produces .can file" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let elmFile = tmpDir </> "convert-test-rename.elm"
            canFile = tmpDir </> "convert-test-rename.can"
        BS.writeFile elmFile "module Test"
        result <- Source.renameElmToCan elmFile
        result Test.@?= canFile
        canExists <- Dir.doesFileExist canFile
        Test.assertBool ".can file should exist" canExists
        elmExists <- Dir.doesFileExist elmFile
        Test.assertBool ".elm file should be removed" (not elmExists)
        Dir.removeFile canFile
    ]

-- --------------------------------------------------------------------------
-- End-to-end: convertPackage
-- --------------------------------------------------------------------------

convertPackageTests :: TestTree
convertPackageTests =
  Test.testGroup
    "convertPackage"
    [ Test.testCase "returns SourceDirNotFound for missing directory" $ do
        result <- Convert.convertPackage (ConvertOptions "/nonexistent/convert/dir" Nothing False)
        result ^. convertErrors Test.@?= [SourceDirNotFound "/nonexistent/convert/dir"],
      Test.testCase "returns NoElmJson for directory without elm.json" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-noelmjson"
        Dir.createDirectoryIfMissing True root
        result <- Convert.convertPackage (ConvertOptions root Nothing False)
        result ^. convertErrors Test.@?= [NoElmJson root]
        Dir.removeDirectoryRecursive root,
      Test.testCase "dry run counts .elm files" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-dryrun"
            srcDir = root </> "src"
        Dir.createDirectoryIfMissing True srcDir
        BS.writeFile (root </> "elm.json") "{\"elm-version\": \"0.19.1\"}"
        BS.writeFile (srcDir </> "Main.elm") "module Main exposing (..)"
        BS.writeFile (srcDir </> "Utils.elm") "module Utils exposing (..)"
        result <- Convert.convertPackage (ConvertOptions root Nothing True)
        result ^. convertFilesRenamed Test.@?= 2
        Dir.removeDirectoryRecursive root,
      Test.testCase "live conversion renames files and converts project" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-live"
            srcDir = root </> "src"
            outDir = tmpDir </> "convert-test-live-out"
        Dir.createDirectoryIfMissing True srcDir
        BS.writeFile (root </> "elm.json") "{\"elm-version\": \"0.19.1\", \"dependencies\": {\"elm/core\": \"1.0.0\"}}"
        BS.writeFile (srcDir </> "Main.elm") "module Main exposing (..)\nmain = text \"hello\""
        result <- Convert.convertPackage (ConvertOptions root (Just outDir) False)
        result ^. convertFilesRenamed Test.@?= 1
        result ^. convertProjectConverted Test.@?= True
        canopyJsonExists <- Dir.doesFileExist (outDir </> "canopy.json")
        Test.assertBool "canopy.json should exist" canopyJsonExists
        content <- BS.readFile (outDir </> "canopy.json")
        Test.assertBool "should contain canopy-version" (BS.isInfixOf "canopy-version" content)
        Test.assertBool "should contain canopy/core" (BS.isInfixOf "canopy/core" content)
        Dir.removeDirectoryRecursive root
        Dir.removeDirectoryRecursive outDir,
      Test.testCase "detects unsupported features and blocks conversion" $ do
        tmpDir <- Dir.getTemporaryDirectory
        let root = tmpDir </> "convert-test-unsupported"
            srcDir = root </> "src"
        Dir.createDirectoryIfMissing True srcDir
        BS.writeFile (root </> "elm.json") "{\"elm-version\": \"0.19.1\"}"
        BS.writeFile (srcDir </> "Effect.elm") "effect module Effect exposing (..)"
        result <- Convert.convertPackage (ConvertOptions root Nothing False)
        result ^. convertFilesRenamed Test.@?= 0
        let hasUnsupported = any isUnsupportedFeature (result ^. convertErrors)
        Test.assertBool "should contain UnsupportedFeature error" hasUnsupported
        Dir.removeDirectoryRecursive root
    ]

-- | Check if a 'ConvertError' is an 'UnsupportedFeature'.
isUnsupportedFeature :: ConvertError -> Bool
isUnsupportedFeature (UnsupportedFeature _ _) = True
isUnsupportedFeature _ = False

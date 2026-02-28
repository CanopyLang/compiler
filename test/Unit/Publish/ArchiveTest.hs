{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Publish.Archive module.
--
-- Tests archive entry collection, file filtering, and directory
-- exclusion for reproducible package archive creation.
--
-- @since 0.19.2
module Unit.Publish.ArchiveTest (tests) where

import qualified Data.List as List
import qualified Publish.Archive as Archive
import qualified System.FilePath as FP
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Publish.Archive Tests"
    [ testSourceExtensions,
      testAlwaysIncludeFiles,
      testExcludedDirectories,
      testIsIncludedFile,
      testIsExcludedDirectory,
      testCollectArchiveEntries
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Source extensions
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testSourceExtensions :: TestTree
testSourceExtensions =
  testGroup
    "Source extensions"
    [ testCase "includes .can extension" $
        assertBool ".can should be a source extension"
          (".can" `elem` Archive.sourceExtensions),
      testCase "includes .canopy extension" $
        assertBool ".canopy should be a source extension"
          (".canopy" `elem` Archive.sourceExtensions),
      testCase "does not include .hs extension" $
        assertBool ".hs should not be a source extension"
          (not (".hs" `elem` Archive.sourceExtensions)),
      testCase "does not include .js extension" $
        assertBool ".js should not be a source extension"
          (not (".js" `elem` Archive.sourceExtensions)),
      testCase "exact extensions list" $
        Archive.sourceExtensions @?= [".can", ".canopy"]
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Always-included files
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testAlwaysIncludeFiles :: TestTree
testAlwaysIncludeFiles =
  testGroup
    "Always-included files"
    [ testCase "includes canopy.json" $
        assertBool "canopy.json should always be included"
          ("canopy.json" `elem` Archive.alwaysIncludeFiles),
      testCase "includes LICENSE" $
        assertBool "LICENSE should always be included"
          ("LICENSE" `elem` Archive.alwaysIncludeFiles),
      testCase "includes README.md" $
        assertBool "README.md should always be included"
          ("README.md" `elem` Archive.alwaysIncludeFiles),
      testCase "exact list of always-included files" $
        Archive.alwaysIncludeFiles @?= ["canopy.json", "LICENSE", "README.md"]
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Excluded directories
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testExcludedDirectories :: TestTree
testExcludedDirectories =
  testGroup
    "Excluded directories"
    [ testCase "excludes canopy-stuff" $
        assertBool "canopy-stuff should be excluded"
          ("canopy-stuff" `elem` Archive.excludedDirectories),
      testCase "excludes elm-stuff" $
        assertBool "elm-stuff should be excluded"
          ("elm-stuff" `elem` Archive.excludedDirectories),
      testCase "excludes .canopy-stuff" $
        assertBool ".canopy-stuff should be excluded"
          (".canopy-stuff" `elem` Archive.excludedDirectories),
      testCase "excludes node_modules" $
        assertBool "node_modules should be excluded"
          ("node_modules" `elem` Archive.excludedDirectories),
      testCase "excludes .git" $
        assertBool ".git should be excluded"
          (".git" `elem` Archive.excludedDirectories),
      testCase "excludes .svn" $
        assertBool ".svn should be excluded"
          (".svn" `elem` Archive.excludedDirectories),
      testCase "excludes .hg" $
        assertBool ".hg should be excluded"
          (".hg" `elem` Archive.excludedDirectories),
      testCase "excludes .stack-work" $
        assertBool ".stack-work should be excluded"
          (".stack-work" `elem` Archive.excludedDirectories),
      testCase "excludes dist-newstyle" $
        assertBool "dist-newstyle should be excluded"
          ("dist-newstyle" `elem` Archive.excludedDirectories),
      testCase "does not exclude src" $
        assertBool "src should not be excluded"
          (not ("src" `elem` Archive.excludedDirectories))
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- isIncludedFile
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testIsIncludedFile :: TestTree
testIsIncludedFile =
  testGroup
    "isIncludedFile"
    [ testCase "includes .can source file" $
        Archive.isIncludedFile "/project" "/project/src/Main.can" @?= True,
      testCase "includes .canopy source file" $
        Archive.isIncludedFile "/project" "/project/src/App.canopy" @?= True,
      testCase "includes canopy.json" $
        Archive.isIncludedFile "/project" "/project/canopy.json" @?= True,
      testCase "includes LICENSE" $
        Archive.isIncludedFile "/project" "/project/LICENSE" @?= True,
      testCase "includes README.md" $
        Archive.isIncludedFile "/project" "/project/README.md" @?= True,
      testCase "excludes .js files" $
        Archive.isIncludedFile "/project" "/project/build/output.js" @?= False,
      testCase "excludes .hs files" $
        Archive.isIncludedFile "/project" "/project/src/Main.hs" @?= False,
      testCase "excludes arbitrary text files" $
        Archive.isIncludedFile "/project" "/project/notes.txt" @?= False,
      testCase "includes nested .can file" $
        Archive.isIncludedFile "/project" "/project/src/Data/List.can" @?= True,
      testCase "includes deeply nested .canopy file" $
        Archive.isIncludedFile "/project" "/project/src/App/Utils/Helper.canopy" @?= True,
      testCase "includes LICENSE in subdirectory" $
        Archive.isIncludedFile "/project" "/project/docs/LICENSE" @?= True,
      testCase "includes README.md in subdirectory" $
        Archive.isIncludedFile "/project" "/project/docs/README.md" @?= True,
      testCase "excludes executable files" $
        Archive.isIncludedFile "/project" "/project/canopy" @?= False,
      testCase "excludes .o object files" $
        Archive.isIncludedFile "/project" "/project/build/Main.o" @?= False
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- isExcludedDirectory
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testIsExcludedDirectory :: TestTree
testIsExcludedDirectory =
  testGroup
    "isExcludedDirectory"
    [ testCase "excludes canopy-stuff directory" $
        Archive.isExcludedDirectory "canopy-stuff" @?= True,
      testCase "excludes node_modules directory" $
        Archive.isExcludedDirectory "node_modules" @?= True,
      testCase "excludes .git directory" $
        Archive.isExcludedDirectory ".git" @?= True,
      testCase "excludes nested .git directory by basename" $
        Archive.isExcludedDirectory (FP.joinPath ["project", ".git"]) @?= True,
      testCase "does not exclude src directory" $
        Archive.isExcludedDirectory "src" @?= False,
      testCase "does not exclude lib directory" $
        Archive.isExcludedDirectory "lib" @?= False,
      testCase "does not exclude test directory" $
        Archive.isExcludedDirectory "test" @?= False,
      testCase "excludes .stack-work directory" $
        Archive.isExcludedDirectory ".stack-work" @?= True,
      testCase "excludes dist-newstyle directory" $
        Archive.isExcludedDirectory "dist-newstyle" @?= True,
      testCase "excludes nested dist-newstyle" $
        Archive.isExcludedDirectory (FP.joinPath ["project", "dist-newstyle"]) @?= True
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- collectArchiveEntries
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testCollectArchiveEntries :: TestTree
testCollectArchiveEntries =
  testGroup
    "collectArchiveEntries"
    [ testCase "collects .can files" $ do
        let root = "/project"
            files = ["/project/src/Main.can", "/project/src/Utils.can"]
            entries = Archive.collectArchiveEntries root files
        length entries @?= 2,
      testCase "excludes non-source files" $ do
        let root = "/project"
            files = ["/project/src/Main.can", "/project/build/output.js"]
            entries = Archive.collectArchiveEntries root files
        length entries @?= 1,
      testCase "includes metadata files" $ do
        let root = "/project"
            files = ["/project/canopy.json", "/project/LICENSE", "/project/README.md"]
            entries = Archive.collectArchiveEntries root files
        length entries @?= 3,
      testCase "entries are sorted by path" $ do
        let root = "/project"
            files =
              [ "/project/src/Zebra.can",
                "/project/src/Alpha.can",
                "/project/canopy.json"
              ]
            entries = Archive.collectArchiveEntries root files
            paths = map Archive._entryPath entries
        paths @?= List.sort paths,
      testCase "entry paths are relative to root" $ do
        let root = "/project"
            files = ["/project/src/Main.can"]
            entries = Archive.collectArchiveEntries root files
        map Archive._entryPath entries @?= ["src/Main.can"],
      testCase "empty file list yields empty entries" $ do
        let entries = Archive.collectArchiveEntries "/project" []
        entries @?= [],
      testCase "all excluded files yields empty entries" $ do
        let root = "/project"
            files = ["/project/build/out.js", "/project/notes.txt"]
            entries = Archive.collectArchiveEntries root files
        entries @?= [],
      testCase "mixed source and metadata files" $ do
        let root = "/project"
            files =
              [ "/project/src/Main.can",
                "/project/canopy.json",
                "/project/LICENSE",
                "/project/build/output.js",
                "/project/README.md",
                "/project/src/App.canopy"
              ]
            entries = Archive.collectArchiveEntries root files
        length entries @?= 5,
      testCase "entry sizes default to zero" $ do
        let root = "/project"
            files = ["/project/src/Main.can"]
            entries = Archive.collectArchiveEntries root files
        map Archive._entrySize entries @?= [0]
    ]

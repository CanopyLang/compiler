{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for the New (project scaffolding) module.
--
-- Tests project creation, validation, template generation,
-- and error handling for the @canopy new@ command.
--
-- @since 0.19.1
module Unit.NewTest (tests) where

import qualified Data.List as List
import qualified New
import qualified Reporting.Exit as Exit
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import Terminal (Parser (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase)

tests :: TestTree
tests =
  testGroup
    "New Command Tests"
    [ testProjectNameValidation,
      testTemplateParser,
      testModuleNameConversion,
      testProjectCreation,
      testErrorConditions,
      testContentGeneration
    ]

-- | Test project name validation rules.
testProjectNameValidation :: TestTree
testProjectNameValidation =
  testGroup
    "project name validation"
    [ testCase "valid simple name succeeds" $
        withNewProject "hello" noGitAppFlags assertIsRight,
      testCase "valid hyphenated name succeeds" $
        withNewProject "my-project" noGitAppFlags assertIsRight,
      testCase "valid name with digits succeeds" $
        withNewProject "app2" noGitAppFlags assertIsRight,
      testCase "valid single character succeeds" $
        withNewProject "a" noGitAppFlags assertIsRight,
      testCase "rejects empty name" $
        withNewProject "" noGitAppFlags (assertIsLeftWith isNewEmptyName),
      testCase "rejects name starting with uppercase" $
        withNewProject "MyProject" noGitAppFlags (assertIsLeftWith isNewInvalidName),
      testCase "rejects name starting with digit" $
        withNewProject "1project" noGitAppFlags (assertIsLeftWith isNewInvalidName),
      testCase "rejects name starting with hyphen" $
        withNewProject "-project" noGitAppFlags (assertIsLeftWith isNewInvalidName),
      testCase "rejects name ending with hyphen" $
        withNewProject "project-" noGitAppFlags (assertIsLeftWith isNewInvalidName),
      testCase "rejects name with spaces" $
        withNewProject "my project" noGitAppFlags (assertIsLeftWith isNewInvalidName),
      testCase "rejects name with underscores" $
        withNewProject "my_project" noGitAppFlags (assertIsLeftWith isNewInvalidName),
      testCase "rejects name with uppercase in middle" $
        withNewProject "myProject" noGitAppFlags (assertIsLeftWith isNewInvalidName),
      testCase "rejects name exceeding 50 chars" $
        withNewProject (replicate 51 'a') noGitAppFlags (assertIsLeftWith isNewInvalidName)
    ]

-- | Test template parser accepts correct values.
testTemplateParser :: TestTree
testTemplateParser =
  testGroup
    "template parser"
    [ testCase "parses 'app' as AppTemplate" $
        assertEqual "app" (Just New.AppTemplate) (parseTemplateStr "app"),
      testCase "parses 'application' as AppTemplate" $
        assertEqual "application" (Just New.AppTemplate) (parseTemplateStr "application"),
      testCase "parses 'pkg' as PackageTemplate" $
        assertEqual "pkg" (Just New.PackageTemplate) (parseTemplateStr "pkg"),
      testCase "parses 'package' as PackageTemplate" $
        assertEqual "package" (Just New.PackageTemplate) (parseTemplateStr "package"),
      testCase "rejects unknown template" $
        assertEqual "unknown" Nothing (parseTemplateStr "unknown"),
      testCase "rejects empty string" $
        assertEqual "empty" Nothing (parseTemplateStr "")
    ]

-- | Test module name conversion from hyphenated project names.
testModuleNameConversion :: TestTree
testModuleNameConversion =
  testGroup
    "module name conversion"
    [ testCase "simple name capitalizes first letter" $
        assertEqual "hello -> Hello" "Hello" (New.toModuleName "hello"),
      testCase "hyphenated name becomes CamelCase" $
        assertEqual "my-project -> MyProject" "MyProject" (New.toModuleName "my-project"),
      testCase "multiple hyphens produce multiple capitals" $
        assertEqual "a-b-c -> ABC" "ABC" (New.toModuleName "a-b-c"),
      testCase "single character is capitalized" $
        assertEqual "a -> A" "A" (New.toModuleName "a"),
      testCase "name with digits preserves them" $
        assertEqual "app2 -> App2" "App2" (New.toModuleName "app2")
    ]

-- | Test actual project creation in temp directories.
testProjectCreation :: TestTree
testProjectCreation =
  testGroup
    "project creation"
    [ testCase "app template creates correct directory structure" $
        withNewProject "test-app" noGitAppFlags $ \result -> do
          assertIsRight result,
      testCase "app template has expected directories" $
        Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
          result <- New.createProjectIn tmpDir "my-app" noGitAppFlags
          assertIsRight result
          assertDirExists (tmpDir </> "my-app")
          assertDirExists (tmpDir </> "my-app" </> "src")
          assertDirExists (tmpDir </> "my-app" </> "tests"),
      testCase "app template creates canopy.json" $
        Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
          _ <- New.createProjectIn tmpDir "json-app" noGitAppFlags
          assertFileExists (tmpDir </> "json-app" </> "canopy.json"),
      testCase "app template creates Main.can" $
        Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
          _ <- New.createProjectIn tmpDir "main-app" noGitAppFlags
          assertFileExists (tmpDir </> "main-app" </> "src" </> "Main.can"),
      testCase "app template creates gitignore" $
        Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
          _ <- New.createProjectIn tmpDir "git-app" noGitAppFlags
          assertFileExists (tmpDir </> "git-app" </> ".gitignore"),
      testCase "package template creates library module" $
        Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
          result <- New.createProjectIn tmpDir "my-lib" noGitPkgFlags
          assertIsRight result
          assertFileExists (tmpDir </> "my-lib" </> "src" </> "MyLib.can"),
      testCase "Main.can references project name" $
        Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
          _ <- New.createProjectIn tmpDir "hello-world" noGitAppFlags
          content <- readFile (tmpDir </> "hello-world" </> "src" </> "Main.can")
          assertBool
            "Main.can should mention project name"
            (List.isInfixOf "hello-world" content),
      testCase "app canopy.json has application type" $
        Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
          _ <- New.createProjectIn tmpDir "app-type" noGitAppFlags
          content <- readFile (tmpDir </> "app-type" </> "canopy.json")
          assertBool
            "canopy.json should specify application type"
            (List.isInfixOf "\"type\": \"application\"" content),
      testCase "package canopy.json has package type" $
        Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
          _ <- New.createProjectIn tmpDir "pkg-type" noGitPkgFlags
          content <- readFile (tmpDir </> "pkg-type" </> "canopy.json")
          assertBool
            "canopy.json should specify package type"
            (List.isInfixOf "\"type\": \"package\"" content)
    ]

-- | Test error conditions produce correct error types.
testErrorConditions :: TestTree
testErrorConditions =
  testGroup
    "error conditions"
    [ testCase "existing directory produces NewDirectoryExists" $
        Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
          Dir.createDirectoryIfMissing True (tmpDir </> "existing-dir")
          result <- New.createProjectIn tmpDir "existing-dir" noGitAppFlags
          assertIsLeftWith isNewDirectoryExists result
    ]

-- | Test generated file content correctness.
testContentGeneration :: TestTree
testContentGeneration =
  testGroup
    "content generation"
    [ testCase "app canopy.json includes elm/core" $
        assertBool "should include elm/core"
          (List.isInfixOf "elm/core" (New.canopyJsonContent New.AppTemplate)),
      testCase "app canopy.json includes elm/html" $
        assertBool "should include elm/html"
          (List.isInfixOf "elm/html" (New.canopyJsonContent New.AppTemplate)),
      testCase "app canopy.json includes elm/browser" $
        assertBool "should include elm/browser"
          (List.isInfixOf "elm/browser" (New.canopyJsonContent New.AppTemplate)),
      testCase "app canopy.json has source-directories" $
        assertBool "should have source-directories"
          (List.isInfixOf "source-directories" (New.canopyJsonContent New.AppTemplate)),
      testCase "app canopy.json has canopy-version" $
        assertBool "should have canopy-version"
          (List.isInfixOf "canopy-version" (New.canopyJsonContent New.AppTemplate)),
      testCase "package canopy.json has exposed-modules" $
        assertBool "should have exposed-modules"
          (List.isInfixOf "exposed-modules" (New.canopyJsonContent New.PackageTemplate)),
      testCase "package canopy.json has license field" $
        assertBool "should have license"
          (List.isInfixOf "license" (New.canopyJsonContent New.PackageTemplate)),
      testCase "gitignore excludes canopy-stuff" $
        assertBool "should exclude canopy-stuff"
          (List.isInfixOf "canopy-stuff/" New.gitignoreContent),
      testCase "gitignore excludes node_modules" $
        assertBool "should exclude node_modules"
          (List.isInfixOf "node_modules/" New.gitignoreContent),
      testCase "gitignore excludes elm-stuff for compatibility" $
        assertBool "should exclude elm-stuff"
          (List.isInfixOf "elm-stuff/" New.gitignoreContent),
      testCase "main content has module declaration" $
        assertBool "should have module Main"
          (List.isInfixOf "module Main" (New.mainCanContent "test")),
      testCase "main content has Html import" $
        assertBool "should import Html"
          (List.isInfixOf "import Html" (New.mainCanContent "test")),
      testCase "main content has main function" $
        assertBool "should have main ="
          (List.isInfixOf "main =" (New.mainCanContent "test")),
      testCase "module content has module declaration" $
        assertBool "should have module declaration"
          (List.isInfixOf "module MyMod" (New.moduleCanContent "MyMod")),
      testCase "module content has exposing clause" $
        assertBool "should have exposing (..)"
          (List.isInfixOf "exposing (..)" (New.moduleCanContent "MyMod"))
    ]

-- Helpers

-- | Run createProjectIn in a temp directory and check result.
withNewProject ::
  String ->
  New.Flags ->
  (Either Exit.New () -> IO ()) ->
  IO ()
withNewProject projectName flags check =
  Temp.withSystemTempDirectory "newtest" $ \tmpDir -> do
    result <- New.createProjectIn tmpDir projectName flags
    check result

-- | Extract the parser function from templateParser.
parseTemplateStr :: String -> Maybe New.Template
parseTemplateStr s =
  let (Parser _ _ parser _ _) = New.templateParser
   in parser s

-- | Flags for app template with no git.
noGitAppFlags :: New.Flags
noGitAppFlags =
  New.Flags
    { New._newTemplate = Nothing,
      New._newNoGit = True
    }

-- | Flags for package template with no git.
noGitPkgFlags :: New.Flags
noGitPkgFlags =
  New.Flags
    { New._newTemplate = Just New.PackageTemplate,
      New._newNoGit = True
    }

-- | Assert a result is Right.
assertIsRight :: Either Exit.New () -> IO ()
assertIsRight (Right ()) = pure ()
assertIsRight (Left err) =
  assertBool ("Expected Right but got Left: " ++ show err) False

-- | Assert a result is Left and matches a predicate.
assertIsLeftWith :: (Exit.New -> Bool) -> Either Exit.New () -> IO ()
assertIsLeftWith predicate (Left err) =
  assertBool ("Error did not match predicate: " ++ show err) (predicate err)
assertIsLeftWith _ (Right ()) =
  assertBool "Expected Left but got Right" False

-- | Check if error is NewEmptyName.
isNewEmptyName :: Exit.New -> Bool
isNewEmptyName Exit.NewEmptyName = True
isNewEmptyName _ = False

-- | Check if error is NewInvalidName.
isNewInvalidName :: Exit.New -> Bool
isNewInvalidName (Exit.NewInvalidName _ _) = True
isNewInvalidName _ = False

-- | Check if error is NewDirectoryExists.
isNewDirectoryExists :: Exit.New -> Bool
isNewDirectoryExists (Exit.NewDirectoryExists _) = True
isNewDirectoryExists _ = False

-- | Assert a directory exists at the given path.
assertDirExists :: FilePath -> IO ()
assertDirExists path = do
  exists <- Dir.doesDirectoryExist path
  assertBool ("Directory should exist: " ++ path) exists

-- | Assert a file exists at the given path.
assertFileExists :: FilePath -> IO ()
assertFileExists path = do
  exists <- Dir.doesFileExist path
  assertBool ("File should exist: " ++ path) exists

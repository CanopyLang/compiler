{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Project scaffolding command for Canopy.
--
-- This module implements the @canopy new@ command, which creates a complete
-- project directory structure including configuration files, source templates,
-- version control initialization, and standard project scaffolding.
--
-- Unlike @canopy init@ which only creates a @canopy.json@ in the current
-- directory, @canopy new@ creates an entire project from scratch in a new
-- directory.
--
-- == Supported Templates
--
-- * 'AppTemplate' - Application project with @Main.can@ entry point
-- * 'PackageTemplate' - Library package with exposed module
--
-- == Generated Structure (Application)
--
-- @
-- my-project/
-- +-- canopy.json
-- +-- src/
-- |   +-- Main.can
-- +-- tests/
-- +-- .gitignore
-- @
--
-- == Generated Structure (Package)
--
-- @
-- my-project/
-- +-- canopy.json
-- +-- src/
-- |   +-- MyProject.can
-- +-- tests/
-- +-- .gitignore
-- @
--
-- @since 0.19.1
module New
  ( -- * Entry Point
    run,

    -- * Core Logic (exported for testing)
    createProject,
    createProjectIn,

    -- * Types
    Flags (..),
    Template (..),

    -- * Parsers
    templateParser,

    -- * Internal Helpers (exported for testing)
    toModuleName,
    canopyJsonContent,
    mainCanContent,
    moduleCanContent,
    gitignoreContent,
  )
where

import Control.Lens (makeLenses, (^.))
import qualified Control.Exception as Exception
import qualified Data.Char as Char
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.Process as Process
import qualified Reporting
import qualified Reporting.Exit as Exit
import Terminal (Parser (..))

-- | Project template selection.
--
-- Determines the kind of project scaffolding to generate.
-- Application templates include a @Main.can@ with an entry point,
-- while package templates create a library module stub.
data Template
  = -- | Application with @Main.can@ entry point
    AppTemplate
  | -- | Library package with exposed module
    PackageTemplate
  deriving (Eq, Show)

-- | Flags for the @canopy new@ command.
data Flags = Flags
  { -- | Which project template to use (default: application)
    _newTemplate :: !(Maybe Template),
    -- | Skip git repository initialization
    _newNoGit :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | Run the @canopy new@ command.
--
-- Creates a new project directory with complete scaffolding including
-- configuration, source files, and optional git initialization.
--
-- The project name must be a valid directory name containing only
-- lowercase letters, digits, and hyphens.
--
-- @since 0.19.1
run :: String -> Flags -> IO ()
run projectName flags =
  Reporting.attempt Exit.newToReport $
    createProject projectName flags

-- | Create a new project in the current directory.
--
-- Validates the project name, then delegates to 'createProjectIn' with
-- the current directory as the base.
createProject :: String -> Flags -> IO (Either Exit.New ())
createProject projectName flags =
  createProjectIn "." projectName flags

-- | Create a new project in a specified base directory.
--
-- This is the core implementation. The project directory will be created
-- at @baseDir </> projectName@.
--
-- @since 0.19.1
createProjectIn :: FilePath -> String -> Flags -> IO (Either Exit.New ())
createProjectIn baseDir projectName flags = do
  validationResult <- validateProjectName projectName
  maybe (proceedWithCreation baseDir projectName flags) (pure . Left) validationResult

-- | Proceed after validation passes.
proceedWithCreation :: FilePath -> String -> Flags -> IO (Either Exit.New ())
proceedWithCreation baseDir projectName flags = do
  exists <- Dir.doesDirectoryExist projectDir
  if exists
    then pure (Left (Exit.NewDirectoryExists projectName))
    else createProjectDirectory baseDir projectName flags
  where
    projectDir = baseDir </> projectName

-- | Create the project directory and all contents.
createProjectDirectory :: FilePath -> String -> Flags -> IO (Either Exit.New ())
createProjectDirectory baseDir projectName flags = do
  result <- safeCreateDirectory projectDir
  either (pure . Left) (\() -> populateProject projectDir projectName flags) result
  where
    projectDir = baseDir </> projectName

-- | Populate the project directory with all files.
populateProject :: FilePath -> String -> Flags -> IO (Either Exit.New ())
populateProject projectDir projectName flags = do
  createResult <- createAllFiles projectDir projectName template
  either (pure . Left) (\() -> finalizeProject projectDir projectName flags) createResult
  where
    template = maybe AppTemplate id (flags ^. newTemplate)

-- | Finalize project creation with optional git init.
finalizeProject :: FilePath -> String -> Flags -> IO (Either Exit.New ())
finalizeProject projectDir projectName flags =
  if flags ^. newNoGit
    then reportSuccess projectName >> pure (Right ())
    else initGitAndReport projectDir projectName

-- | Initialize git and report success.
initGitAndReport :: FilePath -> String -> IO (Either Exit.New ())
initGitAndReport projectDir projectName = do
  gitResult <- initGitRepo projectDir
  either (pure . Left) (\() -> reportSuccess projectName >> pure (Right ())) gitResult

-- | Validate that a project name is suitable for a directory.
--
-- Valid project names:
--   * Non-empty
--   * Start with a lowercase letter
--   * Contain only lowercase letters, digits, and hyphens
--   * Do not start or end with a hyphen
--   * Maximum 50 characters
validateProjectName :: String -> IO (Maybe Exit.New)
validateProjectName [] =
  pure (Just Exit.NewEmptyName)
validateProjectName name
  | length name > 50 =
      pure (Just (Exit.NewInvalidName name "Project name must be 50 characters or fewer."))
  | not (startsWithLower name) =
      pure (Just (Exit.NewInvalidName name "Project name must start with a lowercase letter."))
  | not (all isValidChar name) =
      pure (Just (Exit.NewInvalidName name "Project name may only contain lowercase letters, digits, and hyphens."))
  | endsWithHyphen name =
      pure (Just (Exit.NewInvalidName name "Project name must not end with a hyphen."))
  | otherwise =
      pure Nothing
  where
    isValidChar c = Char.isLower c || Char.isDigit c || c == '-'
    startsWithLower (c : _) = Char.isLower c
    startsWithLower [] = False
    endsWithHyphen [] = False
    endsWithHyphen [c] = c == '-'
    endsWithHyphen (_ : cs) = endsWithHyphen cs

-- | Safely create a directory, catching IO exceptions.
safeCreateDirectory :: FilePath -> IO (Either Exit.New ())
safeCreateDirectory path = do
  result <- Exception.try (Dir.createDirectoryIfMissing True path)
  pure (either (Left . Exit.NewCannotCreateDirectory path . showIOError) Right result)

-- | Create all project files for the given template.
--
-- The @projectDir@ is the full path to the project directory.
-- The @projectName@ is the display name used in generated content.
createAllFiles :: FilePath -> String -> Template -> IO (Either Exit.New ())
createAllFiles projectDir projectName template = do
  srcResult <- safeCreateDirectory (projectDir </> "src")
  either (pure . Left) (\() -> continueCreation projectDir projectName template) srcResult

-- | Continue file creation after src directory exists.
continueCreation :: FilePath -> String -> Template -> IO (Either Exit.New ())
continueCreation projectDir projectName template = do
  testsResult <- safeCreateDirectory (projectDir </> "tests")
  either (pure . Left) (\() -> writeProjectFiles projectDir projectName template) testsResult

-- | Write all project files to disk.
writeProjectFiles :: FilePath -> String -> Template -> IO (Either Exit.New ())
writeProjectFiles projectDir projectName template = do
  configResult <- writeCanopyJson projectDir template
  either (pure . Left) (\() -> writeRemainingFiles projectDir projectName template) configResult

-- | Write the remaining files after canopy.json.
writeRemainingFiles :: FilePath -> String -> Template -> IO (Either Exit.New ())
writeRemainingFiles projectDir projectName template = do
  sourceResult <- writeSourceFile projectDir projectName template
  either (pure . Left) (\() -> writeGitignore projectDir) sourceResult

-- | Write canopy.json configuration file.
writeCanopyJson :: FilePath -> Template -> IO (Either Exit.New ())
writeCanopyJson projectDir template =
  safeWriteFile (projectDir </> "canopy.json") (canopyJsonContent template)

-- | Write the initial source file.
writeSourceFile :: FilePath -> String -> Template -> IO (Either Exit.New ())
writeSourceFile projectDir projectName AppTemplate =
  safeWriteFile (projectDir </> "src" </> "Main.can") (mainCanContent projectName)
writeSourceFile projectDir projectName PackageTemplate =
  safeWriteFile (projectDir </> "src" </> modulePath) (moduleCanContent moduleName)
  where
    moduleName = toModuleName projectName
    modulePath = moduleName ++ ".can"

-- | Write the .gitignore file.
writeGitignore :: FilePath -> IO (Either Exit.New ())
writeGitignore projectDir =
  safeWriteFile (projectDir </> ".gitignore") gitignoreContent

-- | Safely write a file, catching IO exceptions.
safeWriteFile :: FilePath -> String -> IO (Either Exit.New ())
safeWriteFile path content = do
  result <- Exception.try (writeFile path content)
  pure (either (Left . Exit.NewCannotWriteFile path . showIOError) Right result)

-- | Initialize a git repository in the project directory.
initGitRepo :: FilePath -> IO (Either Exit.New ())
initGitRepo projectDir = do
  result <- Exception.try (Process.callProcess "git" ["init", projectDir])
  pure (either (Left . Exit.NewGitInitFailed . showIOError) Right result)

-- | Report successful project creation.
reportSuccess :: String -> IO ()
reportSuccess projectName =
  putStrLn (successMessage projectName)

-- | Build the success message.
successMessage :: String -> String
successMessage projectName =
  unlines
    [ ""
    , "  I created a new Canopy project in ./" ++ projectName ++ "/"
    , ""
    , "  To get started:"
    , ""
    , "    cd " ++ projectName
    , "    canopy make src/Main.can"
    , ""
    , "  Learn more at https://guide.canopy-lang.org"
    , ""
    ]

-- | Convert an IOException to a user-friendly string.
showIOError :: Exception.IOException -> String
showIOError = show

-- | Convert a hyphenated project name to a CamelCase module name.
--
-- Examples:
--   "my-project" -> "MyProject"
--   "hello"      -> "Hello"
--   "a-b-c"      -> "ABC"
toModuleName :: String -> String
toModuleName = concatMap capitalize . splitOnHyphens
  where
    capitalize [] = []
    capitalize (c : cs) = Char.toUpper c : cs

    splitOnHyphens [] = []
    splitOnHyphens s =
      let (word, rest) = break (== '-') s
       in word : splitOnHyphens (drop 1 rest)

-- | Generate canopy.json content for the given template.
canopyJsonContent :: Template -> String
canopyJsonContent AppTemplate =
  unlines
    [ "{"
    , "    \"type\": \"application\","
    , "    \"source-directories\": ["
    , "        \"src\""
    , "    ],"
    , "    \"canopy-version\": \"0.19.1\","
    , "    \"dependencies\": {"
    , "        \"direct\": {"
    , "            \"elm/core\": \"1.0.5\","
    , "            \"elm/browser\": \"1.0.2\","
    , "            \"elm/html\": \"1.0.0\""
    , "        },"
    , "        \"indirect\": {"
    , "            \"elm/json\": \"1.1.3\","
    , "            \"elm/time\": \"1.0.0\","
    , "            \"elm/url\": \"1.0.0\","
    , "            \"elm/virtual-dom\": \"1.0.3\""
    , "        }"
    , "    },"
    , "    \"test-dependencies\": {"
    , "        \"direct\": {},"
    , "        \"indirect\": {}"
    , "    }"
    , "}"
    ]
canopyJsonContent PackageTemplate =
  unlines
    [ "{"
    , "    \"type\": \"package\","
    , "    \"name\": \"author/project\","
    , "    \"summary\": \"A new Canopy package\","
    , "    \"license\": \"BSD-3-Clause\","
    , "    \"version\": \"1.0.0\","
    , "    \"exposed-modules\": [],"
    , "    \"canopy-version\": \"0.19.1 <= v < 0.20.0\","
    , "    \"dependencies\": {"
    , "        \"elm/core\": \"1.0.0 <= v < 2.0.0\""
    , "    },"
    , "    \"test-dependencies\": {}"
    , "}"
    ]

-- | Generate Main.can content for an application template.
mainCanContent :: String -> String
mainCanContent projectName =
  unlines
    [ "module Main exposing (main)"
    , ""
    , "import Html"
    , ""
    , ""
    , "main ="
    , "    Html.text \"Hello from " ++ projectName ++ "!\""
    ]

-- | Generate a library module stub for a package template.
moduleCanContent :: String -> String
moduleCanContent moduleName =
  unlines
    [ "module " ++ moduleName ++ " exposing (..)"
    , ""
    , ""
    , "-- Add your module code here"
    ]

-- | Content for the .gitignore file.
gitignoreContent :: String
gitignoreContent =
  unlines
    [ "canopy-stuff/"
    , "elm-stuff/"
    , "node_modules/"
    , "*.dat"
    ]

-- | Parser for the @--template@ flag.
--
-- Accepts "app" or "package" as valid template names.
templateParser :: Parser Template
templateParser =
  Parser
    { _singular = "template",
      _plural = "templates",
      _parser = parseTemplate,
      _suggest = suggestTemplates,
      _examples = exampleTemplates
    }

-- | Parse a template name string.
parseTemplate :: String -> Maybe Template
parseTemplate "app" = Just AppTemplate
parseTemplate "application" = Just AppTemplate
parseTemplate "pkg" = Just PackageTemplate
parseTemplate "package" = Just PackageTemplate
parseTemplate _ = Nothing

-- | Suggest template names for shell completion.
suggestTemplates :: String -> IO [String]
suggestTemplates _ = pure ["app", "package"]

-- | Provide example template names.
exampleTemplates :: String -> IO [String]
exampleTemplates _ = pure ["app", "package"]

{-# LANGUAGE OverloadedStrings #-}

-- | External JavaScript module loading for browser test harness.
--
-- Locates and loads external JavaScript files (@test-runner.js@,
-- @task-executor.js@) from the installed @canopy\/test@ package.
--
-- == Package Resolution
--
-- Files are located through the standard package cache at
-- @~\/.canopy\/packages\/canopy\/test\/{version}\/external\/@.
-- The version is read from the project's @canopy.json@ dependency list.
-- Falls back to the Elm cache at @~\/.elm\/0.19.1\/packages\/@ if
-- the Canopy cache path does not exist.
--
-- @since 0.19.1
module Test.External
  ( -- * Types
    ExternalModule (..),
    ExternalModuleError (..),
    JsContent (..),

    -- * Loading
    loadExternalModule,
    loadTestRunnerBundle,
    loadBrowserTestRunner,
    loadPlaywrightRpc,
    loadBrowserTestBundle,
  )
where

import Data.Text (Text)
import qualified Data.List as List
import qualified Data.Text.IO as TextIO
import qualified System.Directory as Dir
import System.FilePath ((</>))

import qualified Stuff

-- | Known external JavaScript modules from the @canopy\/test@ package.
data ExternalModule
  = -- | Main test runner with sync\/async support
    TestRunner
  | -- | Task monad executor for async operations
    TaskExecutor
  | -- | Playwright browser automation bindings
    PlaywrightBindings
  | -- | Browser-side test runner for BrowserTest execution
    BrowserTestRunner
  | -- | Node.js RPC dispatcher bridging console.log to Playwright commands
    PlaywrightRpc
  deriving (Eq, Show)

-- | Errors when loading external modules.
data ExternalModuleError
  = -- | No @canopy.json@ found (cannot determine project root)
    ProjectRootNotFound
  | -- | The test package could not be found in the package cache
    TestPackageNotInstalled
  | -- | The external JS file does not exist at the expected location
    ModuleFileNotFound !ExternalModule !FilePath
  | -- | File read failed
    ModuleReadFailed !ExternalModule !Text
  deriving (Eq, Show)

-- | JavaScript file content wrapper.
newtype JsContent = JsContent {unJsContent :: Text}
  deriving (Eq, Show)

-- | Load a single external module from the @canopy\/test@ package.
--
-- Resolves the package installation directory via the package cache,
-- then reads the file from the @external\/@ subdirectory.
--
-- @since 0.19.1
loadExternalModule :: ExternalModule -> IO (Either ExternalModuleError JsContent)
loadExternalModule modType = do
  maybeDir <- findTestPackageDir
  case maybeDir of
    Left err -> pure (Left err)
    Right dir -> loadFromDir modType dir

-- | Load all modules needed for the browser test harness.
--
-- Returns @(test-runner.js, task-executor.js, playwright.js)@ as a triple.
--
-- @since 0.19.1
loadTestRunnerBundle :: IO (Either ExternalModuleError (JsContent, JsContent, JsContent))
loadTestRunnerBundle = do
  maybeDir <- findTestPackageDir
  case maybeDir of
    Left err -> pure (Left err)
    Right dir -> do
      runnerResult <- loadFromDir TestRunner dir
      executorResult <- loadFromDir TaskExecutor dir
      playwrightResult <- loadFromDir PlaywrightBindings dir
      pure (combineThree runnerResult executorResult playwrightResult)
  where
    combineThree (Right r) (Right e) (Right p) = Right (r, e, p)
    combineThree (Left err) _ _ = Left err
    combineThree _ (Left err) _ = Left err
    combineThree _ _ (Left err) = Left err

-- | Find the @canopy\/test@ package installation directory.
--
-- Searches the Canopy package cache first, then the Elm package cache.
-- Looks for any installed version by scanning the version directories.
findTestPackageDir :: IO (Either ExternalModuleError FilePath)
findTestPackageDir = do
  cacheDir <- Stuff.getPackageCache
  let canopyTestDir = cacheDir </> "canopy" </> "test"
  canopyExists <- Dir.doesDirectoryExist canopyTestDir
  if canopyExists
    then findVersionDir canopyTestDir
    else tryElmFallback

-- | Find the latest version directory within a package directory.
findVersionDir :: FilePath -> IO (Either ExternalModuleError FilePath)
findVersionDir pkgDir = do
  entries <- Dir.listDirectory pkgDir
  dirs <- filterVersionDirs pkgDir entries
  case List.sortBy (flip compare) dirs of
    (latest : _) -> pure (Right (pkgDir </> latest))
    [] -> pure (Left TestPackageNotInstalled)

-- | Filter directory entries to only valid version directories.
filterVersionDirs :: FilePath -> [FilePath] -> IO [FilePath]
filterVersionDirs pkgDir entries = do
  let candidates = filter (not . ("." `List.isPrefixOf`)) entries
  existing <- mapM (\e -> Dir.doesDirectoryExist (pkgDir </> e) >>= \b -> pure (e, b)) candidates
  pure (map fst (filter snd existing))

-- | Try the Elm package cache as a fallback.
tryElmFallback :: IO (Either ExternalModuleError FilePath)
tryElmFallback = do
  homeDir <- Dir.getHomeDirectory
  let elmTestDir = homeDir </> ".elm" </> "0.19.1" </> "packages" </> "canopy" </> "test"
  elmExists <- Dir.doesDirectoryExist elmTestDir
  if elmExists
    then findVersionDir elmTestDir
    else pure (Left TestPackageNotInstalled)

-- | Load a specific external module file from a package directory.
loadFromDir :: ExternalModule -> FilePath -> IO (Either ExternalModuleError JsContent)
loadFromDir modType pkgVersionDir = do
  let path = pkgVersionDir </> "external" </> moduleFileName modType
  exists <- Dir.doesFileExist path
  if exists
    then fmap (Right . JsContent) (TextIO.readFile path)
    else pure (Left (ModuleFileNotFound modType path))

-- | Load the browser-side test runner for BrowserTest execution.
--
-- @since 0.19.1
loadBrowserTestRunner :: IO (Either ExternalModuleError JsContent)
loadBrowserTestRunner = loadExternalModule BrowserTestRunner

-- | Load the Node.js Playwright RPC dispatcher.
--
-- @since 0.19.1
loadPlaywrightRpc :: IO (Either ExternalModuleError JsContent)
loadPlaywrightRpc = loadExternalModule PlaywrightRpc

-- | Load both the browser test runner and Playwright RPC module.
--
-- Returns @(browser-test-runner.js, playwright-rpc.js)@.
--
-- @since 0.19.1
loadBrowserTestBundle :: IO (Either ExternalModuleError (JsContent, JsContent))
loadBrowserTestBundle = do
  maybeDir <- findTestPackageDir
  case maybeDir of
    Left err -> pure (Left err)
    Right dir -> do
      runnerResult <- loadFromDir BrowserTestRunner dir
      rpcResult <- loadFromDir PlaywrightRpc dir
      pure (combineTwo runnerResult rpcResult)
  where
    combineTwo (Right r) (Right p) = Right (r, p)
    combineTwo (Left err) _ = Left err
    combineTwo _ (Left err) = Left err

-- | Map a module type to its filename.
moduleFileName :: ExternalModule -> FilePath
moduleFileName TestRunner = "test-runner.js"
moduleFileName TaskExecutor = "task-executor.js"
moduleFileName PlaywrightBindings = "playwright.js"
moduleFileName BrowserTestRunner = "browser-test-runner.js"
moduleFileName PlaywrightRpc = "playwright-rpc.js"

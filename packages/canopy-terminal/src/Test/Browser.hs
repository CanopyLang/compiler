{-# LANGUAGE OverloadedStrings #-}

-- | Browser test detection and application discovery.
--
-- This module identifies whether compiled test JavaScript contains browser
-- or async tests and locates the application entry point needed to serve
-- browser tests.
--
-- == Test Type Detection
--
-- Compiled JavaScript is scanned for @BrowserTest@ and @AsyncTest@
-- constructor tags emitted by the Canopy compiler:
--
-- @
-- detectTestType compiledJs
-- -- Returns 'BrowserTest' if BrowserTest constructors found
-- -- Returns 'AsyncTest' if only AsyncTest constructors found
-- -- Returns 'UnitTest' otherwise
-- @
--
-- == Application Discovery
--
-- Browser tests need an application to test against. The entry point
-- is discovered via a @\@browser-app@ annotation in the test source:
--
-- @
-- {-| \@browser-app src\/Main.can -}
-- @
--
-- Or via the @--app@ CLI flag as fallback.
--
-- @since 0.19.1
module Test.Browser
  ( -- * Test Types
    TestType (..),

    -- * Application Entry Point
    AppEntryPoint (..),
    AppDiscoveryError (..),

    -- * Detection
    detectTestType,

    -- * App Discovery
    parseAppAnnotation,
    findAppEntryPoint,
  )
where

import Data.Text (Text)
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified System.Directory as Dir

-- | Classification of test types based on compiled output.
--
-- Used to determine which test execution pipeline to invoke.
data TestType
  = -- | Simple synchronous test (no browser or async operations)
    UnitTest
  | -- | Requires Playwright browser automation
    BrowserTest
  | -- | Async task-based test (no browser, but needs task executor)
    AsyncTest
  deriving (Eq, Show)

-- | Application entry point path for browser tests.
--
-- Wraps a 'FilePath' to the @.can@ file that should be compiled and
-- served via HTTP for browser test execution.
newtype AppEntryPoint = AppEntryPoint {unAppEntryPoint :: FilePath}
  deriving (Eq, Show)

-- | Errors during application entry point discovery.
data AppDiscoveryError
  = -- | No @\@browser-app@ annotation found and no @--app@ flag given
    NoAppAnnotation
  | -- | The specified app file does not exist on disk
    AppFileNotFound !AppEntryPoint
  deriving (Eq, Show)

-- | Detect the test type from compiled JavaScript content.
--
-- Scans for constructor tags in the compiled output. The Canopy compiler
-- emits @\$ = \'BrowserTest\'@ for browser tests and @\$ = \'AsyncTest\'@
-- for async tests.
--
-- ==== Examples
--
-- >>> detectTestType "var x = {$: 'BrowserTest', a: ...}"
-- BrowserTest
--
-- >>> detectTestType "var x = {$: 'UnitTest', a: ...}"
-- UnitTest
--
-- @since 0.19.1
detectTestType :: Text -> TestType
detectTestType jsContent
  | hasBrowserTest = BrowserTest
  | hasAsyncTest = AsyncTest
  | otherwise = UnitTest
  where
    hasBrowserTest =
      Text.isInfixOf "'BrowserTest'" jsContent
        || Text.isInfixOf "\"BrowserTest\"" jsContent
    hasAsyncTest =
      Text.isInfixOf "'AsyncTest'" jsContent
        || Text.isInfixOf "\"AsyncTest\"" jsContent

-- | Parse a @\@browser-app@ annotation from test file source.
--
-- Searches each line for the pattern @\@browser-app path/to/Main.can@.
--
-- ==== Examples
--
-- >>> parseAppAnnotation "{-| @browser-app src/Main.can -}"
-- Just (AppEntryPoint "src/Main.can")
--
-- >>> parseAppAnnotation "module Test exposing (..)"
-- Nothing
--
-- @since 0.19.1
parseAppAnnotation :: Text -> Maybe AppEntryPoint
parseAppAnnotation source =
  Maybe.listToMaybe (Maybe.mapMaybe extractFromLine (Text.lines source))
  where
    extractFromLine line =
      case Text.breakOn "@browser-app" line of
        (_, match)
          | Text.null match -> Nothing
          | otherwise ->
              extractPath (Text.drop (Text.length "@browser-app") match)

    extractPath rest =
      let trimmed = Text.strip rest
          path = Text.takeWhile (\c -> c /= ' ' && c /= '-' && c /= '}') trimmed
       in if Text.null path
            then Nothing
            else Just (AppEntryPoint (Text.unpack path))

-- | Discover the application entry point for browser tests.
--
-- Search order:
--
-- 1. @\@browser-app@ annotations in test files
-- 2. Explicit @--app@ flag value
-- 3. Error if neither is found
--
-- @since 0.19.1
findAppEntryPoint ::
  [FilePath] ->
  Maybe AppEntryPoint ->
  IO (Either AppDiscoveryError AppEntryPoint)
findAppEntryPoint testFiles maybeFlag = do
  annotations <- mapM readAndParseAnnotation testFiles
  resolveEntryPoint (Maybe.catMaybes annotations) maybeFlag
  where
    readAndParseAnnotation path = do
      exists <- Dir.doesFileExist path
      if exists
        then fmap parseAppAnnotation (TextIO.readFile path)
        else pure Nothing

-- | Resolve the final entry point from annotations and flag.
resolveEntryPoint ::
  [AppEntryPoint] ->
  Maybe AppEntryPoint ->
  IO (Either AppDiscoveryError AppEntryPoint)
resolveEntryPoint (app : _) _ = validateAppFile app
resolveEntryPoint [] (Just app) = validateAppFile app
resolveEntryPoint [] Nothing = pure (Left NoAppAnnotation)

-- | Validate that the app entry point file exists on disk.
validateAppFile :: AppEntryPoint -> IO (Either AppDiscoveryError AppEntryPoint)
validateAppFile app = do
  exists <- Dir.doesFileExist (unAppEntryPoint app)
  pure (if exists then Right app else Left (AppFileNotFound app))

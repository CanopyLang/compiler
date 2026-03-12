{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit route scanning.
--
-- Tests the filesystem-based route scanner that discovers page, layout,
-- and error boundary modules from the @src\/routes\/@ directory tree.
--
-- @since 0.20.1
module Unit.Kit.Route.ScannerTest
  ( tests
  ) where

import qualified Data.Text as Text
import Kit.Route.Types
  ( LayoutEntry (..)
  , PageKind (..)
  , RouteEntry (..)
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  , ScanError (..)
  )
import qualified Kit.Route.Scanner as Scanner
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO.Temp as Temp
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup "Kit.Route.Scanner"
    [ scanEmptyRoutesDir
    , scanSingleStaticRoute
    , scanNestedStaticRoutes
    , scanDynamicSegment
    , scanCatchAllSegment
    , scanLayoutDiscovery
    , scanErrorBoundaryDiscovery
    , scanApiRouteClassification
    , scanMissingDirectoryError
    , scanIndexRoute
    ]


-- | Scanning an empty routes directory produces a manifest with no routes.
scanEmptyRoutesDir :: TestTree
scanEmptyRoutesDir =
  HUnit.testCase "empty routes directory produces empty manifest" $
    withRoutesDir [] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Right manifest -> _rmRoutes manifest @?= []
        Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | A single page.can produces one static route.
scanSingleStaticRoute :: TestTree
scanSingleStaticRoute =
  HUnit.testCase "single page.can produces static route" $
    withRoutesDir [("about/page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Right manifest -> do
          length (_rmRoutes manifest) @?= 1
          let route = head (_rmRoutes manifest)
          _rePageKind route @?= StaticPage
          _reModuleName route @?= "Routes.About"
        Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | Nested directories produce routes with multiple segments.
scanNestedStaticRoutes :: TestTree
scanNestedStaticRoutes =
  HUnit.testCase "nested directories produce multi-segment routes" $
    withRoutesDir [("blog/posts/page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Right manifest -> do
          length (_rmRoutes manifest) @?= 1
          let route = head (_rmRoutes manifest)
          _rpSegments (_rePattern route) @?=
            [StaticSegment "blog", StaticSegment "posts"]
          _reModuleName route @?= "Routes.Blog.Posts"
        Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | Directory named [id] produces a dynamic segment.
scanDynamicSegment :: TestTree
scanDynamicSegment =
  HUnit.testCase "[param] directory produces DynamicSegment" $
    withRoutesDir [("users/[id]/page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Right manifest -> do
          length (_rmRoutes manifest) @?= 1
          let route = head (_rmRoutes manifest)
          _rpSegments (_rePattern route) @?=
            [StaticSegment "users", DynamicSegment "id"]
          _rePageKind route @?= DynamicPage
        Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | Directory named [...rest] produces a catch-all segment.
scanCatchAllSegment :: TestTree
scanCatchAllSegment =
  HUnit.testCase "[...rest] directory produces CatchAll" $
    withRoutesDir [("docs/[...path]/page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Right manifest -> do
          length (_rmRoutes manifest) @?= 1
          let route = head (_rmRoutes manifest)
          _rpSegments (_rePattern route) @?=
            [StaticSegment "docs", CatchAll "path"]
          _rePageKind route @?= DynamicPage
        Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | layout.can files are discovered as layout entries.
scanLayoutDiscovery :: TestTree
scanLayoutDiscovery =
  HUnit.testCase "layout.can files produce layout entries" $
    withRoutesDir [("layout.can", ""), ("page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Right manifest -> do
          length (_rmLayouts manifest) @?= 1
          let layout = head (_rmLayouts manifest)
          _lePrefix layout @?= []
        Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | error.can files are discovered as error boundary entries.
scanErrorBoundaryDiscovery :: TestTree
scanErrorBoundaryDiscovery =
  HUnit.testCase "error.can files produce error boundary entries" $
    withRoutesDir [("error.can", ""), ("page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Right manifest ->
          length (_rmErrorBoundaries manifest) @?= 1
        Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | Routes under an api/ directory are classified as ApiRoute.
scanApiRouteClassification :: TestTree
scanApiRouteClassification =
  HUnit.testCase "api/ subdirectory routes are ApiRoute" $
    withRoutesDir [("api/users/page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Right manifest -> do
          length (_rmRoutes manifest) @?= 1
          _rePageKind (head (_rmRoutes manifest)) @?= ApiRoute
        Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)

-- | Scanning a nonexistent directory returns DirectoryNotFound.
scanMissingDirectoryError :: TestTree
scanMissingDirectoryError =
  HUnit.testCase "nonexistent directory returns DirectoryNotFound" $ do
    result <- Scanner.scanRoutes "/nonexistent/path"
    case result of
      Left (DirectoryNotFound _) -> pure ()
      Left err -> HUnit.assertFailure ("wrong error: " ++ show err)
      Right _ -> HUnit.assertFailure "expected error but got success"

-- | A page.can at root level (no subdirectories) produces an index route.
scanIndexRoute :: TestTree
scanIndexRoute =
  HUnit.testCase "root page.can produces index route" $
    withRoutesDir [("page.can", "")] $ \root -> do
      result <- Scanner.scanRoutes root
      case result of
        Right manifest -> do
          length (_rmRoutes manifest) @?= 1
          let route = head (_rmRoutes manifest)
          _rpSegments (_rePattern route) @?= []
          _reModuleName route @?= "Routes.Index"
        Left err -> HUnit.assertFailure ("unexpected error: " ++ show err)


-- TEST HELPERS


-- | Create a temporary directory with the given route structure and run a test.
--
-- Files are specified as @(relativePath, content)@ pairs. The root path
-- passed to the callback is the parent of @src\/routes\/@.
withRoutesDir :: [(FilePath, String)] -> (FilePath -> IO ()) -> IO ()
withRoutesDir files action =
  Temp.withSystemTempDirectory "canopy-kit-test" $ \tmpDir -> do
    let routesDir = tmpDir FP.</> "src" FP.</> "routes"
    Dir.createDirectoryIfMissing True routesDir
    mapM_ (createFile routesDir) files
    action tmpDir

-- | Create a file relative to the routes directory.
createFile :: FilePath -> (FilePath, String) -> IO ()
createFile routesDir (relPath, content) = do
  let fullPath = routesDir FP.</> relPath
  Dir.createDirectoryIfMissing True (FP.takeDirectory fullPath)
  writeFile fullPath content

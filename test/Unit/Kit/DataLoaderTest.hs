{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit data loader detection.
--
-- Tests that the data loader scanner correctly identifies @load@
-- functions in route source files and classifies them as static
-- or dynamic based on their type signatures.
--
-- @since 0.20.1
module Unit.Kit.DataLoaderTest
  ( tests
  ) where

import qualified Data.Text as Text
import Kit.DataLoader (DataLoader (..), LoaderKind (..))
import qualified Kit.DataLoader as DataLoader
import Kit.Route.Types
  ( PageKind (..)
  , RouteEntry (..)
  , RoutePattern (..)
  , RouteSegment (..)
  )
import qualified System.Directory as Dir
import qualified System.FilePath as FP
import qualified System.IO.Temp as Temp
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup "Kit.DataLoader"
    [ detectsStaticLoader
    , detectsDynamicLoader
    , skipsModuleWithoutLoad
    , devModeForcesDynamic
    , generatesEmptyLoaderModule
    , generatesLoaderModuleWithEntries
    , handlesMultipleRoutes
    ]


-- | A module with a pure load function is detected as StaticLoader.
detectsStaticLoader :: TestTree
detectsStaticLoader =
  HUnit.testCase "pure load function detected as StaticLoader" $
    withSourceFile staticLoadSource $ \entry -> do
      loaders <- DataLoader.detectLoaders [entry]
      length loaders @?= 1
      _dlKind (head loaders) @?= StaticLoader

-- | A module with a Task-returning load function is DynamicLoader.
detectsDynamicLoader :: TestTree
detectsDynamicLoader =
  HUnit.testCase "Task-returning load detected as DynamicLoader" $
    withSourceFile dynamicLoadSource $ \entry -> do
      loaders <- DataLoader.detectLoaders [entry]
      length loaders @?= 1
      _dlKind (head loaders) @?= DynamicLoader

-- | A module without a load function produces no loader.
skipsModuleWithoutLoad :: TestTree
skipsModuleWithoutLoad =
  HUnit.testCase "module without load is skipped" $
    withSourceFile noLoadSource $ \entry -> do
      loaders <- DataLoader.detectLoaders [entry]
      length loaders @?= 0

-- | Dev mode forces all loaders to DynamicLoader.
devModeForcesDynamic :: TestTree
devModeForcesDynamic =
  HUnit.testCase "dev mode forces all loaders to DynamicLoader" $
    withSourceFile staticLoadSource $ \entry -> do
      loaders <- DataLoader.detectLoadersDev [entry]
      length loaders @?= 1
      _dlKind (head loaders) @?= DynamicLoader

-- | Empty loader list produces a valid empty module.
generatesEmptyLoaderModule :: TestTree
generatesEmptyLoaderModule =
  HUnit.testCase "empty loader list produces valid module" $ do
    let output = DataLoader.generateLoaderModule []
    HUnit.assertBool "starts with module"
      ("module Loaders" `Text.isPrefixOf` output)
    HUnit.assertBool "contains loaders value"
      ("loaders" `Text.isInfixOf` output)

-- | Loader list generates imports and entries.
generatesLoaderModuleWithEntries :: TestTree
generatesLoaderModuleWithEntries =
  HUnit.testCase "loaders generate imports and entries" $ do
    let loader = DataLoader
          { _dlRoute = mkEntry "src/routes/about/page.can" "Routes.About"
          , _dlKind = StaticLoader
          , _dlModuleName = "Routes.About"
          }
        output = DataLoader.generateLoaderModule [loader]
    HUnit.assertBool "imports module"
      ("import Routes.About" `Text.isInfixOf` output)
    HUnit.assertBool "references load function"
      ("Routes.About.load" `Text.isInfixOf` output)

-- | Multiple routes are each detected independently.
handlesMultipleRoutes :: TestTree
handlesMultipleRoutes =
  HUnit.testCase "multiple routes detected independently" $
    Temp.withSystemTempDirectory "canopy-loader-test" $ \tmpDir -> do
      let aboutDir = tmpDir FP.</> "about"
          contactDir = tmpDir FP.</> "contact"
      Dir.createDirectoryIfMissing True aboutDir
      Dir.createDirectoryIfMissing True contactDir
      writeFile (aboutDir FP.</> "page.can") staticLoadSource
      writeFile (contactDir FP.</> "page.can") noLoadSource
      let entries =
            [ mkEntry (aboutDir FP.</> "page.can") "Routes.About"
            , mkEntry (contactDir FP.</> "page.can") "Routes.Contact"
            ]
      loaders <- DataLoader.detectLoaders entries
      length loaders @?= 1
      _dlModuleName (head loaders) @?= "Routes.About"


-- TEST DATA


staticLoadSource :: String
staticLoadSource = unlines
  [ "module Routes.About exposing (Model, Msg, load, init, update, view)"
  , ""
  , "load : String"
  , "load ="
  , "  \"static data\""
  ]

dynamicLoadSource :: String
dynamicLoadSource = unlines
  [ "module Routes.Dashboard exposing (Model, Msg, load, init, update, view)"
  , ""
  , "load : Task Http.Error Data"
  , "load ="
  , "  Http.get \"/api/data\""
  ]

noLoadSource :: String
noLoadSource = unlines
  [ "module Routes.Contact exposing (Model, Msg, init, update, view)"
  , ""
  , "init ="
  , "  ( {}, Cmd.none )"
  ]


-- HELPERS


withSourceFile :: String -> (RouteEntry -> IO ()) -> IO ()
withSourceFile content action =
  Temp.withSystemTempDirectory "canopy-loader-test" $ \tmpDir -> do
    let srcFile = tmpDir FP.</> "page.can"
    writeFile srcFile content
    action (mkEntry srcFile "Routes.Test")

mkEntry :: FilePath -> Text.Text -> RouteEntry
mkEntry srcFile modName = RouteEntry
  { _rePattern = RoutePattern [StaticSegment "test"] srcFile
  , _rePageKind = StaticPage
  , _reSourceFile = srcFile
  , _reModuleName = modName
  }

{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit.Hydration client-side bootstrap generation.
--
-- Verifies that 'generateHydrationBootstrap' produces correct JavaScript
-- that reads embedded SSR data and passes it to the Canopy app, and that
-- 'generateHydrationCheck' produces the correct detection expression.
--
-- @since 0.20.1
module Unit.Kit.HydrationTest
  ( tests
  ) where

import qualified Data.Text as Text
import qualified Kit.Hydration as Hydration
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup "Kit.Hydration"
    [ bootstrapImportsModule
    , bootstrapReadsCanopyData
    , bootstrapRemovesHydrateAttr
    , bootstrapInitWithFlags
    , hydrationCheckExpression
    ]


-- | The bootstrap script imports the specified module path.
bootstrapImportsModule :: TestTree
bootstrapImportsModule =
  HUnit.testCase "bootstrap imports module" $ do
    let output = Hydration.generateHydrationBootstrap "canopy.user.Routes.Home.js"
        outputLines = Text.lines output
    outputLines !! 0 @?= "import * as App from './canopy.user.Routes.Home.js';"


-- | The bootstrap script reads the __CANOPY_DATA__ element by ID.
bootstrapReadsCanopyData :: TestTree
bootstrapReadsCanopyData =
  HUnit.testCase "bootstrap reads __CANOPY_DATA__ element" $ do
    let output = Hydration.generateHydrationBootstrap "main.js"
        outputLines = Text.lines output
    outputLines !! 6 @?= "  var dataEl = document.getElementById('__CANOPY_DATA__');"


-- | The bootstrap script removes the data-canopy-hydrate attribute after reading.
bootstrapRemovesHydrateAttr :: TestTree
bootstrapRemovesHydrateAttr =
  HUnit.testCase "bootstrap removes data-canopy-hydrate attribute" $ do
    let output = Hydration.generateHydrationBootstrap "main.js"
        outputLines = Text.lines output
    outputLines !! 11 @?= "  root.removeAttribute('data-canopy-hydrate');"


-- | The bootstrap script calls App.init with parsed flags.
bootstrapInitWithFlags :: TestTree
bootstrapInitWithFlags =
  HUnit.testCase "bootstrap calls App.init with flags" $ do
    let output = Hydration.generateHydrationBootstrap "main.js"
        outputLines = Text.lines output
    outputLines !! 14 @?= "App.init({ node: root, flags: flags });"


-- | The hydration check expression detects the data-canopy-hydrate attribute.
hydrationCheckExpression :: TestTree
hydrationCheckExpression =
  HUnit.testCase "hydration check expression" $
    Hydration.generateHydrationCheck
      @?= "document.getElementById('app') && document.getElementById('app').hasAttribute('data-canopy-hydrate')"

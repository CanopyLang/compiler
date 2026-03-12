{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit.Dev pure helper functions.
--
-- The 'Kit.Dev' module exports only the IO-heavy 'dev' function, but
-- internally uses 'isRelevantFile' and 'resolvePort' which are not
-- exported. We test the closely related pure types from 'Kit.Types'
-- that support the dev server: 'KitDevFlags' construction and
-- 'KitPreviewFlags' construction.
--
-- @since 0.20.1
module Unit.Kit.DevTest
  ( tests
  ) where

import Kit.Types
  ( KitDevFlags (..)
  , KitPreviewFlags (..)
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit


tests :: TestTree
tests =
  Test.testGroup "Kit.Dev"
    [ devFlagsDefaultShowTest
    , devFlagsWithPortShowTest
    , devFlagsWithOpenShowTest
    , devFlagsEqualityTest
    , devFlagsInequalityTest
    , previewFlagsDefaultShowTest
    , previewFlagsWithPortShowTest
    , previewFlagsWithOpenShowTest
    , previewFlagsEqualityTest
    ]

devFlagsDefaultShowTest :: TestTree
devFlagsDefaultShowTest =
  HUnit.testCase "show default KitDevFlags" $
    show defaultDev @?= "KitDevFlags {_kitDevPort = Nothing, _kitDevOpen = False}"
  where
    defaultDev = KitDevFlags Nothing False

devFlagsWithPortShowTest :: TestTree
devFlagsWithPortShowTest =
  HUnit.testCase "show KitDevFlags with port" $
    show flags @?= "KitDevFlags {_kitDevPort = Just 8080, _kitDevOpen = False}"
  where
    flags = KitDevFlags (Just 8080) False

devFlagsWithOpenShowTest :: TestTree
devFlagsWithOpenShowTest =
  HUnit.testCase "show KitDevFlags with open" $
    show flags @?= "KitDevFlags {_kitDevPort = Nothing, _kitDevOpen = True}"
  where
    flags = KitDevFlags Nothing True

devFlagsEqualityTest :: TestTree
devFlagsEqualityTest =
  HUnit.testCase "equal KitDevFlags are equal" $
    (KitDevFlags Nothing False == KitDevFlags Nothing False) @?= True

devFlagsInequalityTest :: TestTree
devFlagsInequalityTest =
  HUnit.testCase "different KitDevFlags are not equal" $
    (KitDevFlags Nothing False == KitDevFlags (Just 3000) True) @?= False

previewFlagsDefaultShowTest :: TestTree
previewFlagsDefaultShowTest =
  HUnit.testCase "show default KitPreviewFlags" $
    show defaultPreview @?= "KitPreviewFlags {_kitPreviewPort = Nothing, _kitPreviewOpen = False}"
  where
    defaultPreview = KitPreviewFlags Nothing False

previewFlagsWithPortShowTest :: TestTree
previewFlagsWithPortShowTest =
  HUnit.testCase "show KitPreviewFlags with port" $
    show flags @?= "KitPreviewFlags {_kitPreviewPort = Just 3000, _kitPreviewOpen = False}"
  where
    flags = KitPreviewFlags (Just 3000) False

previewFlagsWithOpenShowTest :: TestTree
previewFlagsWithOpenShowTest =
  HUnit.testCase "show KitPreviewFlags with open" $
    show flags @?= "KitPreviewFlags {_kitPreviewPort = Nothing, _kitPreviewOpen = True}"
  where
    flags = KitPreviewFlags Nothing True

previewFlagsEqualityTest :: TestTree
previewFlagsEqualityTest =
  HUnit.testCase "KitPreviewFlags equality" $
    (KitPreviewFlags (Just 3000) True == KitPreviewFlags (Just 3000) True) @?= True

{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit.Build-related pure logic.
--
-- The 'Kit.Build' module exports only the IO-heavy 'build' function,
-- so we test the pure helpers that support it via 'Kit.Types':
-- 'parseDeployTarget' for target resolution, and 'DeployTarget'
-- constructor semantics.
--
-- @since 0.20.1
module Unit.Kit.BuildTest
  ( tests
  ) where

import Kit.Types (DeployTarget (..), KitBuildFlags (..))
import qualified Kit.Types as Types
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit


tests :: TestTree
tests =
  Test.testGroup "Kit.Build"
    [ parseDeployTargetStaticTest
    , parseDeployTargetNodeTest
    , parseDeployTargetVercelTest
    , parseDeployTargetNetlifyTest
    , parseDeployTargetUnknownTest
    , parseDeployTargetEmptyTest
    , parseDeployTargetCaseSensitiveTest
    , kitBuildFlagsDefaultsTest
    , kitBuildFlagsOptimizeTest
    , deployTargetEqualityTest
    , deployTargetShowStaticTest
    , deployTargetShowNodeTest
    , deployTargetShowVercelTest
    , deployTargetShowNetlifyTest
    ]

parseDeployTargetStaticTest :: TestTree
parseDeployTargetStaticTest =
  HUnit.testCase "parseDeployTarget \"static\" yields TargetStatic" $
    Types.parseDeployTarget "static" @?= Just TargetStatic

parseDeployTargetNodeTest :: TestTree
parseDeployTargetNodeTest =
  HUnit.testCase "parseDeployTarget \"node\" yields TargetNode" $
    Types.parseDeployTarget "node" @?= Just TargetNode

parseDeployTargetVercelTest :: TestTree
parseDeployTargetVercelTest =
  HUnit.testCase "parseDeployTarget \"vercel\" yields TargetVercel" $
    Types.parseDeployTarget "vercel" @?= Just TargetVercel

parseDeployTargetNetlifyTest :: TestTree
parseDeployTargetNetlifyTest =
  HUnit.testCase "parseDeployTarget \"netlify\" yields TargetNetlify" $
    Types.parseDeployTarget "netlify" @?= Just TargetNetlify

parseDeployTargetUnknownTest :: TestTree
parseDeployTargetUnknownTest =
  HUnit.testCase "parseDeployTarget rejects unknown targets" $
    Types.parseDeployTarget "cloudflare" @?= Nothing

parseDeployTargetEmptyTest :: TestTree
parseDeployTargetEmptyTest =
  HUnit.testCase "parseDeployTarget rejects empty string" $
    Types.parseDeployTarget "" @?= Nothing

parseDeployTargetCaseSensitiveTest :: TestTree
parseDeployTargetCaseSensitiveTest =
  HUnit.testCase "parseDeployTarget is case-sensitive" $
    Types.parseDeployTarget "Static" @?= Nothing

kitBuildFlagsDefaultsTest :: TestTree
kitBuildFlagsDefaultsTest =
  HUnit.testCase "KitBuildFlags without optimize or output" $
    show defaultFlags @?= "KitBuildFlags {_kitBuildOptimize = False, _kitBuildOutput = Nothing, _kitBuildTarget = Nothing}"
  where
    defaultFlags = KitBuildFlags False Nothing Nothing

kitBuildFlagsOptimizeTest :: TestTree
kitBuildFlagsOptimizeTest =
  HUnit.testCase "KitBuildFlags with optimize and output" $
    show optimizedFlags @?= "KitBuildFlags {_kitBuildOptimize = True, _kitBuildOutput = Just \"dist\", _kitBuildTarget = Just TargetNode}"
  where
    optimizedFlags = KitBuildFlags True (Just "dist") (Just TargetNode)

deployTargetEqualityTest :: TestTree
deployTargetEqualityTest =
  HUnit.testCase "different deploy targets are not equal" $
    (TargetStatic == TargetNode) @?= False

deployTargetShowStaticTest :: TestTree
deployTargetShowStaticTest =
  HUnit.testCase "show TargetStatic" $
    show TargetStatic @?= "TargetStatic"

deployTargetShowNodeTest :: TestTree
deployTargetShowNodeTest =
  HUnit.testCase "show TargetNode" $
    show TargetNode @?= "TargetNode"

deployTargetShowVercelTest :: TestTree
deployTargetShowVercelTest =
  HUnit.testCase "show TargetVercel" $
    show TargetVercel @?= "TargetVercel"

deployTargetShowNetlifyTest :: TestTree
deployTargetShowNetlifyTest =
  HUnit.testCase "show TargetNetlify" $
    show TargetNetlify @?= "TargetNetlify"

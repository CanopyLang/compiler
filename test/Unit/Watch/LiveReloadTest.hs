{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Watch.LiveReload module.
--
-- Tests live reload script generation, error overlay generation,
-- and basic server configuration.
--
-- Note: WebSocket server start/stop tests are not included here as they
-- require network operations and port binding.  Those are covered by
-- integration tests.
--
-- @since 0.19.2
module Unit.Watch.LiveReloadTest (tests) where

import qualified Data.Text as Text
import Test.Tasty
import Test.Tasty.HUnit
import qualified Watch.LiveReload as LiveReload

tests :: TestTree
tests =
  testGroup
    "Watch.LiveReload Tests"
    [ testScriptGeneration,
      testErrorOverlay,
      testConfiguration
    ]

testScriptGeneration :: TestTree
testScriptGeneration =
  testGroup
    "Live reload script"
    [ testCase "script contains WebSocket connection to correct port" $ do
        let script = LiveReload.liveReloadScript 8234
        assertBool
          "script contains port 8234"
          (Text.isInfixOf "ws://localhost:8234" script),
      testCase "script contains reload logic" $ do
        let script = LiveReload.liveReloadScript 9000
        assertBool
          "script contains reload on message"
          (Text.isInfixOf "location.reload()" script),
      testCase "script wraps in script tags" $ do
        let script = LiveReload.liveReloadScript 8234
        assertBool "starts with <script>" (Text.isPrefixOf "<script>" script)
        assertBool "ends with </script>" (Text.isSuffixOf "</script>" script),
      testCase "script contains reconnection logic" $ do
        let script = LiveReload.liveReloadScript 8234
        assertBool
          "script contains onclose handler"
          (Text.isInfixOf "onclose" script),
      testCase "custom port is embedded in script" $ do
        let script = LiveReload.liveReloadScript 12345
        assertBool
          "script contains custom port"
          (Text.isInfixOf "12345" script)
    ]

testErrorOverlay :: TestTree
testErrorOverlay =
  testGroup
    "Error overlay"
    [ testCase "error overlay contains error message" $ do
        let overlay = LiveReload.errorOverlayScript "Type mismatch on line 42"
        assertBool
          "overlay contains error text"
          (Text.isInfixOf "Type mismatch on line 42" overlay),
      testCase "error overlay has fixed positioning" $ do
        let overlay = LiveReload.errorOverlayScript "err"
        assertBool
          "overlay uses fixed position"
          (Text.isInfixOf "position:fixed" overlay),
      testCase "error overlay escapes special characters" $ do
        let overlay = LiveReload.errorOverlayScript "error with 'quotes' and <html>"
        assertBool
          "overlay contains escaped content"
          (Text.isInfixOf "\\'" overlay)
        assertBool
          "overlay escapes angle brackets"
          (Text.isInfixOf "\\x3c" overlay),
      testCase "error overlay wraps in script tags" $ do
        let overlay = LiveReload.errorOverlayScript "test"
        assertBool "starts with <script>" (Text.isPrefixOf "<script>" overlay)
        assertBool "ends with </script>" (Text.isSuffixOf "</script>" overlay)
    ]

testConfiguration :: TestTree
testConfiguration =
  testGroup
    "Configuration"
    [ testCase "default port is 8234" $
        LiveReload.defaultPort @?= 8234
    ]

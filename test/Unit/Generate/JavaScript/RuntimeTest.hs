{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.JavaScript.Runtime'.
--
-- Verifies that the embedded Canopy runtime:
--
--   * Prepends the correct @__canopy_debug@ declaration in both Dev and Prod
--     modes via 'embeddedRuntimeForMode'.
--   * Contains the critical global identifiers that generated code depends on
--     (@_Utils_eq@, @_List_Nil@, @_Platform_worker@, @_Scheduler_succeed@).
--   * Is non-trivially large (not accidentally empty or truncated).
--   * Produces identical body content in Dev and Prod — only the debug flag
--     line differs.
--
-- @since 0.20.0
module Unit.Generate.JavaScript.RuntimeTest (tests) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generate.JavaScript.Runtime as Runtime
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Test.Tasty
import Test.Tasty.HUnit

-- ── Helpers ─────────────────────────────────────────────────────────────────

-- | Convert a 'BB.Builder' to a strict 'BS.ByteString'.
builderToBS :: BB.Builder -> BS.ByteString
builderToBS = LBS.toStrict . BB.toLazyByteString

-- | A minimal 'Mode.Dev' value for testing (no debug types, no flags).
devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

-- | A minimal 'Mode.Prod' value for testing (no short names, no flags).
prodMode :: Mode.Mode
prodMode = Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty

-- ── Tests ────────────────────────────────────────────────────────────────────

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Runtime"
    [ debugFlagTests,
      contentTests,
      bodyConsistencyTest
    ]

-- | Tests for the @__canopy_debug@ preamble emitted by 'embeddedRuntimeForMode'.
debugFlagTests :: TestTree
debugFlagTests =
  testGroup
    "embeddedRuntimeForMode debug flag"
    [ testCase "Dev mode starts with 'var __canopy_debug = true;'" $ do
        let bs = builderToBS (Runtime.embeddedRuntimeForMode devMode)
        assertBool
          "Expected Dev runtime to begin with 'var __canopy_debug = true;'"
          ("var __canopy_debug = true;" `BS.isPrefixOf` bs),
      testCase "Prod mode starts with 'var __canopy_debug = false;'" $ do
        let bs = builderToBS (Runtime.embeddedRuntimeForMode prodMode)
        assertBool
          "Expected Prod runtime to begin with 'var __canopy_debug = false;'"
          ("var __canopy_debug = false;" `BS.isPrefixOf` bs)
    ]

-- | Tests for critical identifiers that must be present in the embedded runtime.
contentTests :: TestTree
contentTests =
  testGroup
    "embeddedRuntime critical identifiers"
    [ testCase "contains _Utils_eq" $
        assertContains "_Utils_eq" runtimeBS,
      testCase "contains _List_Nil" $
        assertContains "_List_Nil" runtimeBS,
      testCase "contains _Platform_worker" $
        assertContains "_Platform_worker" runtimeBS,
      testCase "contains _Scheduler_succeed" $
        assertContains "_Scheduler_succeed" runtimeBS,
      testCase "is non-empty and has substantial content" $
        assertBool
          ("Expected runtime to be at least 10000 bytes, got " ++ show (BS.length runtimeBS))
          (BS.length runtimeBS >= 10000)
    ]
  where
    runtimeBS :: BS.ByteString
    runtimeBS = builderToBS Runtime.embeddedRuntime

-- | Verify that Dev and Prod runtimes share identical body content after
-- their respective debug-flag prefix lines.
bodyConsistencyTest :: TestTree
bodyConsistencyTest =
  testCase "Dev and Prod runtimes have identical content after the debug flag line" $ do
    let devBS = builderToBS (Runtime.embeddedRuntimeForMode devMode)
        prodBS = builderToBS (Runtime.embeddedRuntimeForMode prodMode)
        devBody = BS.drop (BS.length "var __canopy_debug = true;\n") devBS
        prodBody = BS.drop (BS.length "var __canopy_debug = false;\n") prodBS
    devBody @?= prodBody

-- ── Internal helpers ─────────────────────────────────────────────────────────

-- | Assert that a strict 'BS.ByteString' needle appears somewhere in the
-- given haystack, failing the test with a descriptive message if absent.
assertContains :: BS.ByteString -> BS.ByteString -> Assertion
assertContains needle haystack =
  assertBool
    ("Expected runtime to contain '" ++ show needle ++ "'")
    (needle `BS.isInfixOf` haystack)

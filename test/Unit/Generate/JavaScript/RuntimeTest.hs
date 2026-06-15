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
prodMode = Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty Map.empty

-- ── Tests ────────────────────────────────────────────────────────────────────

tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Runtime"
    [ debugFlagTests,
      contentTests,
      bodyConsistencyTest,
      devSeamTests
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

-- | Verify that the Prod runtime body is strictly smaller than the Dev body.
--
-- Prod mode applies 'FFIMinify.stripDebugBranches' to remove conditional
-- debug-only code paths, so the prod body must be a strict subset of the
-- dev body in terms of size.
bodyConsistencyTest :: TestTree
bodyConsistencyTest =
  testCase "Prod runtime body is smaller than Dev after debug branches are stripped" $ do
    let devBS = builderToBS (Runtime.embeddedRuntimeForMode devMode)
        prodBS = builderToBS (Runtime.embeddedRuntimeForMode prodMode)
        devBody = BS.drop (BS.length "var __canopy_debug = true;\n") devBS
        prodBody = BS.drop (BS.length "var __canopy_debug = false;\n") prodBS
    assertBool
      ( "Expected Prod body ("
          ++ show (BS.length prodBody)
          ++ " bytes) to be smaller than Dev body ("
          ++ show (BS.length devBody)
          ++ " bytes) after stripping debug branches"
      )
      (BS.length prodBody < BS.length devBody)

-- | DEV-3: the inert-unless-requested state seam (_Platform_live /
-- _Platform_shutdown) must be present in the embedded runtime, installed from
-- inside _Platform_initialize, and — the load-bearing regression — survive
-- tree-shaking because _Platform_initialize transitively depends on it.
devSeamTests :: TestTree
devSeamTests =
  testGroup
    "DEV-3 state seam (_Platform_live / _Platform_shutdown)"
    [ testCase "embedded runtime declares _Platform_live" $
        assertContains "_Platform_live" runtimeBS,
      testCase "embedded runtime declares _Platform_shutdown" $
        assertContains "_Platform_shutdown" runtimeBS,
      testCase "embedded runtime declares the _Platform_devSeam opt-in flag" $
        assertContains "_Platform_devSeam" runtimeBS,
      testCase "_Platform_initialize body installs the seam (references _Platform_live)" $ do
        let body = initializeBody runtimeBS
        assertBool
          "Expected _Platform_initialize body to reference _Platform_live"
          ("_Platform_live" `BS.isInfixOf` body),
      testCase "_Platform_initialize body guards on _Platform_devSeam" $ do
        let body = initializeBody runtimeBS
        assertBool
          "Expected _Platform_initialize body to guard the seam on _Platform_devSeam"
          ("_Platform_devSeam" `BS.isInfixOf` body),
      testCase "tree-shaker keeps _Platform_live via closeDeps(_Platform_initialize)" $ do
        let closure =
              Runtime.closeDeps (Set.singleton (Runtime.RuntimeId "_Platform_initialize"))
        assertBool
          "closeDeps from _Platform_initialize must include _Platform_live"
          (Set.member (Runtime.RuntimeId "_Platform_live") closure),
      testCase "tree-shaker keeps _Platform_shutdown via closeDeps(_Platform_initialize)" $ do
        let closure =
              Runtime.closeDeps (Set.singleton (Runtime.RuntimeId "_Platform_initialize"))
        assertBool
          "closeDeps from _Platform_initialize must include _Platform_shutdown"
          (Set.member (Runtime.RuntimeId "_Platform_shutdown") closure),
      testCase "tree-shaker keeps _Platform_devSeam via closeDeps(_Platform_initialize)" $ do
        let closure =
              Runtime.closeDeps (Set.singleton (Runtime.RuntimeId "_Platform_initialize"))
        assertBool
          "closeDeps from _Platform_initialize must include _Platform_devSeam"
          (Set.member (Runtime.RuntimeId "_Platform_devSeam") closure),
      testCase "tree-shaker keeps _Platform_devGlobal via closeDeps(_Platform_initialize)" $ do
        let closure =
              Runtime.closeDeps (Set.singleton (Runtime.RuntimeId "_Platform_initialize"))
        assertBool
          "closeDeps from _Platform_initialize must include _Platform_devGlobal"
          (Set.member (Runtime.RuntimeId "_Platform_devGlobal") closure),
      testCase "shutdown pulls _Scheduler_kill into the closure (Subs are stoppable)" $ do
        let closure =
              Runtime.closeDeps (Set.singleton (Runtime.RuntimeId "_Platform_initialize"))
        assertBool
          "closeDeps from _Platform_initialize must include _Scheduler_kill"
          (Set.member (Runtime.RuntimeId "_Scheduler_kill") closure),
      testCase "emitNeeded(closeDeps _Platform_initialize) byte-contains the seam" $ do
        let closure =
              Runtime.closeDeps (Set.singleton (Runtime.RuntimeId "_Platform_initialize"))
            emitted = builderToBS (Runtime.emitNeeded devMode closure)
        assertContains "_Platform_live" emitted
        assertContains "_Platform_shutdown" emitted
    ]
  where
    runtimeBS :: BS.ByteString
    runtimeBS = builderToBS Runtime.embeddedRuntime

-- | Extract the body of @_Platform_initialize@ from the embedded runtime text,
-- from its declaration up to the next top-level @function _Platform_@ that
-- follows it. Good enough to assert the seam install lives inside this function
-- (not merely elsewhere in the file).
initializeBody :: BS.ByteString -> BS.ByteString
initializeBody bs =
  let afterDecl = snd (BS.breakSubstring "function _Platform_initialize" bs)
      -- skip past the decl line so the next "function _Platform_" search finds
      -- the *following* declaration, not _Platform_initialize itself.
      afterHead = BS.drop (BS.length "function _Platform_initialize") afterDecl
      next = fst (BS.breakSubstring "\nfunction _Platform_" afterHead)
   in next

-- ── Internal helpers ─────────────────────────────────────────────────────────

-- | Assert that a strict 'BS.ByteString' needle appears somewhere in the
-- given haystack, failing the test with a descriptive message if absent.
assertContains :: BS.ByteString -> BS.ByteString -> Assertion
assertContains needle haystack =
  assertBool
    ("Expected runtime to contain '" ++ show needle ++ "'")
    (needle `BS.isInfixOf` haystack)

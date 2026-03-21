-- | Unit tests for IIFE variable name uniqueness in FFI code generation.
--
-- Regression tests for the bug where multiple FFI files sharing the same
-- alias all emitted the same IIFE variable name (e.g. @_PlatformFFIIIFE@),
-- causing later assignments to clobber earlier ones at runtime.
--
-- The fix incorporates the file's basename into the IIFE variable name so
-- that @platform-cmd.js@ and @platform-sub.js@ (both aliased @PlatformFFI@)
-- produce distinct variable names.
--
-- @since 0.19.2
module Unit.FFI.IIFEVarTest (tests) where

import qualified Generate.JavaScript.FFI as FFI
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "FFI.sanitizeForIdent"
    [ testCase "leaves alphanumeric and underscore unchanged" $
        FFI.sanitizeForIdent "platform_cmd" @?= "platform_cmd",
      testCase "replaces hyphens with underscores" $
        FFI.sanitizeForIdent "platform-cmd" @?= "platform_cmd",
      testCase "replaces dots with underscores" $
        FFI.sanitizeForIdent "some.module" @?= "some_module",
      testCase "replaces spaces with underscores" $
        FFI.sanitizeForIdent "my module" @?= "my_module",
      testCase "handles empty string" $
        FFI.sanitizeForIdent "" @?= "",
      testCase "handles already-valid identifier" $
        FFI.sanitizeForIdent "PlatformFFI" @?= "PlatformFFI",
      iifVarUniquenessTests
    ]

-- | Verify that two FFI files with the same alias but different basenames
-- produce distinct IIFE variable name prefixes, preventing clobbering.
--
-- This is the core regression test: if both files produced @_PlatformFFIIIFE@
-- the last write would silently win and @.batch@ would be undefined at runtime.
iifVarUniquenessTests :: TestTree
iifVarUniquenessTests =
  testGroup
    "IIFE variable uniqueness (regression: same-alias collision)"
    [ testCase "platform-cmd vs platform-sub produce distinct prefixes" $
        FFI.sanitizeForIdent "platform-cmd" /= FFI.sanitizeForIdent "platform-sub"
          @?= True,
      testCase "platform-cmd basename sanitizes correctly" $
        FFI.sanitizeForIdent "platform-cmd" @?= "platform_cmd",
      testCase "platform-sub basename sanitizes correctly" $
        FFI.sanitizeForIdent "platform-sub" @?= "platform_sub",
      testCase "platform basename sanitizes correctly" $
        FFI.sanitizeForIdent "platform" @?= "platform",
      testCase "all three platform files produce distinct sanitized names" $
        let names = map FFI.sanitizeForIdent ["platform-cmd", "platform-sub", "platform"]
         in length names @?= length (dedupe names)
    ]

-- | Remove duplicates while preserving order.
dedupe :: (Eq a) => [a] -> [a]
dedupe [] = []
dedupe (x : xs) = x : dedupe (filter (/= x) xs)

{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Reporting.Error.Hierarchy module.
--
-- Tests the unified error hierarchy types, ensuring proper
-- construction, equality, and show instances for all error
-- categories and newtypes.
--
-- @since 0.19.2
module Unit.Reporting.ErrorHierarchyTest (tests) where

import qualified Reporting.Error.Hierarchy as Hierarchy
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Reporting.Error.Hierarchy Tests"
    [ testCompilerError,
      testBuildError,
      testOutlineError,
      testCacheError,
      testInterfaceError,
      testFileIOError,
      testParseIOError
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- CompilerError tests
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testCompilerError :: TestTree
testCompilerError =
  testGroup
    "CompilerError"
    [ testCase "SyntaxPhaseError carries message" $
        show (Hierarchy.SyntaxPhaseError "unexpected token") @?=
          "SyntaxPhaseError \"unexpected token\"",
      testCase "CanonicalizePhaseError carries message" $
        show (Hierarchy.CanonicalizePhaseError "unresolved name") @?=
          "CanonicalizePhaseError \"unresolved name\"",
      testCase "TypePhaseError carries message" $
        show (Hierarchy.TypePhaseError "type mismatch") @?=
          "TypePhaseError \"type mismatch\"",
      testCase "different phases are not equal" $
        (Hierarchy.SyntaxPhaseError "x" == Hierarchy.TypePhaseError "x") @?= False,
      testCase "same phase same message are equal" $
        (Hierarchy.FFIPhaseError "bad binding" == Hierarchy.FFIPhaseError "bad binding") @?= True,
      testCase "same phase different message are not equal" $
        (Hierarchy.OptimizePhaseError "a" == Hierarchy.OptimizePhaseError "b") @?= False
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- BuildError tests
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testBuildError :: TestTree
testBuildError =
  testGroup
    "BuildError"
    [ testCase "CompileError wraps CompilerError" $
        show (Hierarchy.CompileError (Hierarchy.SyntaxPhaseError "bad")) @?=
          "CompileError (SyntaxPhaseError \"bad\")",
      testCase "DependencyError carries description" $
        show (Hierarchy.DependencyError "version conflict") @?=
          "DependencyError \"version conflict\"",
      testCase "BuildCacheError wraps CacheError" $
        show buildCacheErr @?=
          "BuildCacheError (CacheReadError \"/tmp/cache\" \"corrupt\")",
      testCase "BuildIOError wraps FileIOError" $
        show buildIOErr @?=
          "BuildIOError (FileReadError \"/src/Main.can\" \"permission denied\")"
    ]
  where
    buildCacheErr =
      Hierarchy.BuildCacheError (Hierarchy.CacheReadError "/tmp/cache" "corrupt")
    buildIOErr =
      Hierarchy.BuildIOError (Hierarchy.FileReadError "/src/Main.can" "permission denied")

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- OutlineError tests
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testOutlineError :: TestTree
testOutlineError =
  testGroup
    "OutlineError"
    [ testCase "OutlineReadError carries path and message" $
        outlineReadErr @?= outlineReadErr,
      testCase "OutlineReadError show includes path" $
        assertContains "canopy.json" (show outlineReadErr),
      testCase "OutlineDecodeError show includes path" $
        assertContains "canopy.json" (show outlineDecodeErr),
      testCase "OutlineValidationError show includes detail" $
        assertContains "invalid version" (show outlineValidErr),
      testCase "different OutlineError constructors are not equal" $
        (outlineReadErr == outlineDecodeErr) @?= False
    ]
  where
    outlineReadErr = Hierarchy.OutlineReadError "canopy.json" "file not found"
    outlineDecodeErr = Hierarchy.OutlineDecodeError "canopy.json" "invalid JSON"
    outlineValidErr = Hierarchy.OutlineValidationError "canopy.json" "invalid version"

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- CacheError tests
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testCacheError :: TestTree
testCacheError =
  testGroup
    "CacheError"
    [ testCase "CacheReadError carries path and reason" $
        show cacheReadErr @?=
          "CacheReadError \"/cache/iface\" \"binary decode failed\"",
      testCase "CacheWriteError carries path and reason" $
        show cacheWriteErr @?=
          "CacheWriteError \"/cache/iface\" \"disk full\"",
      testCase "CacheVersionMismatch carries versions" $
        show cacheVersionErr @?=
          "CacheVersionMismatch \"/cache/iface\" \"0.19.1\" \"0.19.2\"",
      testCase "different CacheError constructors are not equal" $
        (cacheReadErr == cacheWriteErr) @?= False
    ]
  where
    cacheReadErr = Hierarchy.CacheReadError "/cache/iface" "binary decode failed"
    cacheWriteErr = Hierarchy.CacheWriteError "/cache/iface" "disk full"
    cacheVersionErr = Hierarchy.CacheVersionMismatch "/cache/iface" "0.19.1" "0.19.2"

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- InterfaceError tests
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testInterfaceError :: TestTree
testInterfaceError =
  testGroup
    "InterfaceError"
    [ testCase "InterfaceReadError carries path" $
        show ifaceReadErr @?=
          "InterfaceReadError \"/iface/Main.elmi\" \"not found\"",
      testCase "InterfaceDecodeError carries path" $
        show ifaceDecodeErr @?=
          "InterfaceDecodeError \"/iface/Main.elmi\" \"version mismatch\"",
      testCase "different InterfaceError constructors are not equal" $
        (ifaceReadErr == ifaceDecodeErr) @?= False
    ]
  where
    ifaceReadErr = Hierarchy.InterfaceReadError "/iface/Main.elmi" "not found"
    ifaceDecodeErr = Hierarchy.InterfaceDecodeError "/iface/Main.elmi" "version mismatch"

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- FileIOError tests
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testFileIOError :: TestTree
testFileIOError =
  testGroup
    "FileIOError"
    [ testCase "FileReadError show output" $
        show fileReadErr @?=
          "FileReadError \"/src/App.can\" \"permission denied\"",
      testCase "FileWriteError show output" $
        show fileWriteErr @?=
          "FileWriteError \"/out/app.js\" \"read-only filesystem\"",
      testCase "FileCopyError carries source and destination" $
        show fileCopyErr @?=
          "FileCopyError \"/src/a.can\" \"/dst/a.can\" \"cross-device link\"",
      testCase "different FileIOError constructors are not equal" $
        (fileReadErr == fileWriteErr) @?= False
    ]
  where
    fileReadErr = Hierarchy.FileReadError "/src/App.can" "permission denied"
    fileWriteErr = Hierarchy.FileWriteError "/out/app.js" "read-only filesystem"
    fileCopyErr = Hierarchy.FileCopyError "/src/a.can" "/dst/a.can" "cross-device link"

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- ParseIOError tests
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testParseIOError :: TestTree
testParseIOError =
  testGroup
    "ParseIOError"
    [ testCase "ParseFileReadError show output" $
        show parseReadErr @?=
          "ParseFileReadError \"/src/Main.can\" \"not found\"",
      testCase "ParseFileParseError show output" $
        show parseParseErr @?=
          "ParseFileParseError \"/src/Main.can\" \"unexpected token at line 42\"",
      testCase "different ParseIOError constructors are not equal" $
        (parseReadErr == parseParseErr) @?= False
    ]
  where
    parseReadErr = Hierarchy.ParseFileReadError "/src/Main.can" "not found"
    parseParseErr = Hierarchy.ParseFileParseError "/src/Main.can" "unexpected token at line 42"

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Assertion helpers
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- | Assert that a string contains a substring.
assertContains :: String -> String -> Assertion
assertContains needle haystack =
  assertBool
    ("Expected " ++ show haystack ++ " to contain " ++ show needle)
    (needle `isInfixOf` haystack)

-- | Check if a list contains a sublist.
isInfixOf :: (Eq a) => [a] -> [a] -> Bool
isInfixOf needle haystack =
  any (isPrefixOf needle) (tails haystack)

-- | Check if a list starts with a prefix.
isPrefixOf :: (Eq a) => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (x : xs) (y : ys) = x == y && isPrefixOf xs ys

-- | Get all tails of a list.
tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_ : rest) = xs : tails rest

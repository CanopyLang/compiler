{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.JavaScript.FFI.Minify'.
--
-- Covers:
--   * 'stripDebugBranches' — AST-level debug branch elimination on parsed statements
--   * 'stripDebugBranchesBS' — ByteString round-trip variant with graceful degradation
--
-- Each test verifies the exact transformation, not just that output is non-empty.
--
-- @since 0.20.2
module Unit.Generate.JavaScript.FFI.MinifyTest (tests) where

import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import qualified Generate.JavaScript.FFI.JSAnalysis as JSAnalysis
import qualified Generate.JavaScript.FFI.Minify as Minify
import qualified Generate.JavaScript.FFI.Registry as Registry
import qualified Language.JavaScript.Parser as JSParser
import qualified Language.JavaScript.Parser.AST as JSAST
import qualified Language.JavaScript.Pretty.Printer as JSPrint
import qualified Blaze.ByteString.Builder as Blaze
import Test.Tasty
import Test.Tasty.HUnit


tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.FFI.Minify"
    [ stripDebugBranchesTests,
      stripDebugBranchesBSTests
    ]


-- STRIP DEBUG BRANCHES TESTS (AST-level)

stripDebugBranchesTests :: TestTree
stripDebugBranchesTests =
  testGroup
    "stripDebugBranches"
    [ testCase "if (__canopy_debug) { ... } is removed entirely" $
        let input = parseStmts "if (__canopy_debug) { debug(); }"
            result = Minify.stripDebugBranches input
         in length result @?= 0,
      testCase "debug ternary: cond ? debugVal : prodVal becomes prodVal" $
        let input = parseStmts "var x = __canopy_debug ? debug() : prod();"
            result = Minify.stripDebugBranches input
            output = renderStmtsToString result
         in "prod" `isInfixOf` output @?= True,
      testCase "debug ternary: cond ? debugVal : prodVal does NOT contain debugVal" $
        let input = parseStmts "var x = __canopy_debug ? debugOnlyCall() : prodCall();"
            result = Minify.stripDebugBranches input
            output = renderStmtsToString result
         in "debugOnlyCall" `isInfixOf` output @?= False,
      testCase "if (__canopy_debug) { ... } else { prod(); } becomes prod body" $
        let input = parseStmts "if (__canopy_debug) { debug(); } else { prod(); }"
            result = Minify.stripDebugBranches input
            output = renderStmtsToString result
         in "prod" `isInfixOf` output @?= True,
      testCase "if (__canopy_debug) { ... } else { prod(); } removes debug body" $
        let input = parseStmts "if (__canopy_debug) { debug(); } else { prod(); }"
            result = Minify.stripDebugBranches input
            output = renderStmtsToString result
         in "debug" `isInfixOf` output @?= False,
      testCase "non-debug code passes through unchanged (contains original identifier)" $
        let input = parseStmts "var keep = normalCode();"
            result = Minify.stripDebugBranches input
            output = renderStmtsToString result
         in "normalCode" `isInfixOf` output @?= True,
      testCase "empty input produces empty output" $
        Minify.stripDebugBranches [] @?= [],
      testCase "non-debug if statement is kept" $
        let input = parseStmts "if (condition) { doSomething(); }"
            result = Minify.stripDebugBranches input
         in length result @?= 1,
      testCase "multiple statements: only debug branch removed, others kept" $
        let input = parseStmts "var x = 1;\nif (__canopy_debug) { debug(); }\nvar y = 2;"
            result = Minify.stripDebugBranches input
         in length result @?= 2
    ]


-- STRIP DEBUG BRANCHES BS TESTS

stripDebugBranchesBSTests :: TestTree
stripDebugBranchesBSTests =
  testGroup
    "stripDebugBranchesBS"
    [ testCase "if (__canopy_debug) block is removed from ByteString input" $
        let input = BS8.pack "if (__canopy_debug) { debug(); }"
            output = BS8.unpack (Minify.stripDebugBranchesBS input)
         in "debug" `isInfixOf` output @?= False,
      testCase "debug ternary in ByteString: prod branch kept" $
        let input = BS8.pack "var x = __canopy_debug ? debugValue : prodValue;"
            output = BS8.unpack (Minify.stripDebugBranchesBS input)
         in "prodValue" `isInfixOf` output @?= True,
      testCase "debug ternary in ByteString: debug branch removed" $
        let input = BS8.pack "var x = __canopy_debug ? debugValue : prodValue;"
            output = BS8.unpack (Minify.stripDebugBranchesBS input)
         in "debugValue" `isInfixOf` output @?= False,
      testCase "invalid JS returns input unchanged" $
        let input = BS8.pack "<<< this is definitely not javascript >>>"
            output = Minify.stripDebugBranchesBS input
         in output @?= input,
      testCase "valid JS with no debug branches is returned with equivalent content" $
        let input = BS8.pack "var x = 1; function f() { return x; }"
            output = Minify.stripDebugBranchesBS input
         in "stripDebugBranchesBS" `isInfixOf` BS8.unpack output @?= False,
      testCase "valid JS with no debug branches still contains original identifiers" $
        let input = BS8.pack "var keepMe = 42;"
            output = BS8.unpack (Minify.stripDebugBranchesBS input)
         in "keepMe" `isInfixOf` output @?= True
    ]


-- HELPERS

-- | Parse a JavaScript string into a flat statement list.
-- Returns empty list on parse failure.
parseStmts :: String -> [JSAST.JSStatement]
parseStmts src =
  case JSAnalysis.parseAllGroups (Text.pack src) of
    Nothing -> []
    Just (stmts, _) -> stmts

-- | Render statements back to a String for content inspection.
renderStmtsToString :: [JSAST.JSStatement] -> String
renderStmtsToString stmts =
  LChar8.unpack
    (BB.toLazyByteString
      (BB.lazyByteString
        (Blaze.toLazyByteString
          (JSPrint.renderJS (JSAST.JSAstProgram stmts JSAST.JSNoAnnot)))))

isInfixOf :: String -> String -> Bool
isInfixOf needle haystack = go needle haystack
  where
    go [] _ = True
    go _ [] = False
    go ns@(n : ns') (h : hs)
      | n == h = go ns' hs || go ns hs
      | otherwise = go ns hs

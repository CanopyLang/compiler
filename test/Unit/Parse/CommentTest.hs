{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'Parse.Comment'.
--
-- Exercises 'extractComments' against a range of inputs: empty buffers,
-- source with no comments, single and multiple line comments, block
-- comments (including nested ones), doc-comment exclusion, and comment
-- position tracking.  String and character literal skipping is also
-- verified so that comment-like sequences inside literals are not
-- mistakenly extracted.
--
-- @since 0.19.2
module Unit.Parse.CommentTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Parse.Comment as Comment
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Run 'extractComments' on an ASCII string.
extract :: String -> [Src.RawComment]
extract = Comment.extractComments . C8.pack

-- | Assert that no comments are returned.
assertEmpty :: [Src.RawComment] -> IO ()
assertEmpty cs = assertBool ("expected empty, got: " <> show cs) (null cs)

-- | Assert that exactly one comment is returned and hand it to the check.
assertOne :: [Src.RawComment] -> (Src.RawComment -> IO ()) -> IO ()
assertOne [c] check = check c
assertOne cs _ = assertBool ("expected exactly 1 comment, got " <> show (length cs)) False

-- ---------------------------------------------------------------------------
-- Test suite
-- ---------------------------------------------------------------------------

-- | All 'Parse.Comment' tests.
tests :: TestTree
tests =
  testGroup
    "Parse.Comment"
    [ testEmpty,
      testNoComments,
      testLineComment,
      testMultipleLineComments,
      testBlockComment,
      testNestedBlockComment,
      testMixedComments,
      testCommentPosition,
      testInlineComment,
      testDocCommentExcluded,
      testStringLiteralSkipped,
      testCharLiteralSkipped,
      testEmptyLineComment,
      testMultilineBlockComment
    ]

-- ---------------------------------------------------------------------------
-- Empty and comment-free inputs
-- ---------------------------------------------------------------------------

-- | Empty input yields an empty list.
testEmpty :: TestTree
testEmpty =
  testCase "empty input" $
    assertEmpty (extract "")

-- | Source with no comment characters yields an empty list.
testNoComments :: TestTree
testNoComments =
  testCase "no comments" $
    assertEmpty (extract "x = 42\ny = x + 1\n")

-- ---------------------------------------------------------------------------
-- Line comments
-- ---------------------------------------------------------------------------

-- | A single @-- hello@ line comment is extracted correctly.
testLineComment :: TestTree
testLineComment =
  testCase "single line comment" $
    assertOne (extract "-- hello") $ \c -> do
      Src._rcKind c @?= Src.LineComment
      Src._rcText c @?= " hello"

-- | Two consecutive line comments both appear in the result.
testMultipleLineComments :: TestTree
testMultipleLineComments =
  testCase "multiple line comments" $ do
    let cs = extract "-- first\n-- second\n"
    length cs @?= 2
    Src._rcKind (head cs) @?= Src.LineComment
    Src._rcKind (cs !! 1) @?= Src.LineComment
    Src._rcText (head cs) @?= " first"
    Src._rcText (cs !! 1) @?= " second"

-- | An empty line comment @--@ (nothing after the dashes) has empty text.
testEmptyLineComment :: TestTree
testEmptyLineComment =
  testCase "empty line comment text" $
    assertOne (extract "--") $ \c -> do
      Src._rcKind c @?= Src.LineComment
      Src._rcText c @?= ""

-- | An inline comment after code is still captured.
testInlineComment :: TestTree
testInlineComment =
  testCase "inline comment after code" $
    assertOne (extract "x = 1 -- note") $ \c -> do
      Src._rcKind c @?= Src.LineComment
      Src._rcText c @?= " note"

-- ---------------------------------------------------------------------------
-- Block comments
-- ---------------------------------------------------------------------------

-- | A simple @{- hello -}@ block comment is extracted.
testBlockComment :: TestTree
testBlockComment =
  testCase "block comment" $
    assertOne (extract "{- hello -}") $ \c -> do
      Src._rcKind c @?= Src.BlockComment
      Src._rcText c @?= " hello "

-- | A @{- {- inner -} outer -}@ nested block comment is treated as a single
-- comment; the scanner tracks depth so the outer close @-}@ terminates it.
testNestedBlockComment :: TestTree
testNestedBlockComment =
  testCase "nested block comment" $
    assertOne (extract "{- {- inner -} outer -}") $ \c -> do
      Src._rcKind c @?= Src.BlockComment
      Src._rcText c @?= " {- inner -} outer "

-- | A block comment that spans multiple lines is extracted as one entry.
testMultilineBlockComment :: TestTree
testMultilineBlockComment =
  testCase "multiline block comment" $
    assertOne (extract "{-\nhello\nworld\n-}") $ \c ->
      Src._rcKind c @?= Src.BlockComment

-- ---------------------------------------------------------------------------
-- Mixed and position tests
-- ---------------------------------------------------------------------------

-- | A line comment followed by a block comment yields two results in order.
testMixedComments :: TestTree
testMixedComments =
  testCase "mixed line and block comments" $ do
    let cs = extract "-- line\n{- block -}\n"
    length cs @?= 2
    Src._rcKind (head cs) @?= Src.LineComment
    Src._rcKind (cs !! 1) @?= Src.BlockComment

-- | Position tracking: a comment starting at the first column of the first
-- row is annotated with row 1, col 1; a comment on the second row has row 2.
testCommentPosition :: TestTree
testCommentPosition =
  testCase "comment position tracking" $ do
    let cs = extract "-- first\n-- second\n"
    Src._rcRow (head cs) @?= 1
    Src._rcCol (head cs) @?= 1
    Src._rcRow (cs !! 1) @?= 2
    Src._rcCol (cs !! 1) @?= 1

-- ---------------------------------------------------------------------------
-- Doc comment exclusion
-- ---------------------------------------------------------------------------

-- | A @{-| doc -}@ doc comment must NOT appear in the result, because doc
-- comments are already captured by the main parser.
testDocCommentExcluded :: TestTree
testDocCommentExcluded =
  testCase "doc comment excluded" $
    assertEmpty (extract "{-| this is a doc comment -}")

-- ---------------------------------------------------------------------------
-- Literal skipping
-- ---------------------------------------------------------------------------

-- | @--@ inside a string literal must not be extracted as a comment.
testStringLiteralSkipped :: TestTree
testStringLiteralSkipped =
  testCase "comment-like sequence inside string literal is ignored" $
    assertEmpty (extract "\"hello -- world\"")

-- | @--@ inside a character literal must not be extracted as a comment.
testCharLiteralSkipped :: TestTree
testCharLiteralSkipped =
  testCase "dash inside char literal is ignored" $
    assertEmpty (extract "x = '-'")

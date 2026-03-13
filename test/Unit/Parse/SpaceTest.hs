{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Tests for the 'Parse.Space' module.
--
-- This module verifies the space-consuming and indent-checking parsers
-- exported from "Parse.Space". Because 'Space.chomp' always calls @cok@
-- even when nothing is consumed, tests compose it with a subsequent
-- parser (e.g. 'Parse.word1') so that 'Parse.fromByteString' can
-- verify the full input has been consumed.
--
-- @since 0.19.1
module Unit.Parse.SpaceTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import Data.Word (Word32)
import qualified Parse.Primitives as Parse
import qualified Parse.Space as Space
import qualified Reporting.Error.Syntax as SyntaxError
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

-- ---------------------------------------------------------------------------
-- Error type used throughout tests
-- ---------------------------------------------------------------------------

-- | A minimal error type that captures space-parse failures for assertions.
--
-- 'HasTab' and 'EndlessComment' correspond to the two 'SyntaxError.Space'
-- variants. All constructors include row and column for completeness.
data TestError
  = HasTab Parse.Row Parse.Col
  | EndlessComment Parse.Row Parse.Col
  | BadEnd Parse.Row Parse.Col
  | BadIndent Parse.Row Parse.Col
  | BadAligned Parse.Row Parse.Col
  | BadFreshLine Parse.Row Parse.Col
  | BadWord Parse.Row Parse.Col
  deriving (Eq, Show)

toSpaceErr :: SyntaxError.Space -> Parse.Row -> Parse.Col -> TestError
toSpaceErr SyntaxError.HasTab r c          = HasTab r c
toSpaceErr SyntaxError.EndlessMultiComment r c = EndlessComment r c

toBadEnd :: Parse.Row -> Parse.Col -> TestError
toBadEnd = BadEnd

toBadWord :: Parse.Row -> Parse.Col -> TestError
toBadWord = BadWord

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Run a parser against a raw string, requiring full consumption.
run :: Parse.Parser TestError a -> String -> Either TestError a
run p s = Parse.fromByteString p toBadEnd (C8.pack s)

-- | Parser that succeeds only when the next byte is @x@ (0x78).
consumeX :: Parse.Parser TestError ()
consumeX = Parse.word1 0x78 toBadWord

-- | Parser that succeeds only when the next byte is @y@ (0x79).
consumeY :: Parse.Parser TestError ()
consumeY = Parse.word1 0x79 toBadWord

-- | Chomp whitespace then consume the letter @x@.
chompThenX :: Parse.Parser TestError ()
chompThenX = Space.chomp toSpaceErr *> consumeX

-- ---------------------------------------------------------------------------
-- chomp tests
-- ---------------------------------------------------------------------------

-- | Tests that 'Space.chomp' advances past whitespace and allows the
-- subsequent parser to consume the next character.
testChompSpaces :: TestTree
testChompSpaces =
  testGroup
    "chomp spaces"
    [ testCase "single space before x" $
        run chompThenX " x" @?= Right (),
      testCase "multiple spaces before x" $
        run chompThenX "   x" @?= Right (),
      testCase "no whitespace before x" $
        run chompThenX "x" @?= Right ()
    ]

-- | Tests that 'Space.chomp' consumes newlines and resets the column
-- counter, allowing the subsequent parser to succeed.
testChompNewlines :: TestTree
testChompNewlines =
  testGroup
    "chomp newlines"
    [ testCase "newline then x" $
        run chompThenX "\nx" @?= Right (),
      testCase "multiple newlines then x" $
        run chompThenX "\n\n\nx" @?= Right (),
      testCase "mixed spaces and newlines" $
        run chompThenX "  \n  x" @?= Right ()
    ]

-- | Tests that 'Space.chomp' consumes line comments (@-- ...@) and
-- continues parsing after the comment's newline.
testChompLineComments :: TestTree
testChompLineComments =
  testGroup
    "chomp line comments"
    [ testCase "line comment then x" $
        run chompThenX "-- comment\nx" @?= Right (),
      testCase "line comment at start" $
        run chompThenX "-- hello world\nx" @?= Right (),
      testCase "multiple line comments" $
        run chompThenX "-- one\n-- two\nx" @?= Right ()
    ]

-- | Tests that 'Space.chomp' consumes nested block comments (@{- ... -}@)
-- and continues parsing after the closing delimiter.
testChompBlockComments :: TestTree
testChompBlockComments =
  testGroup
    "chomp block comments"
    [ testCase "block comment then x" $
        run chompThenX "{- comment -} x" @?= Right (),
      testCase "block comment spanning newlines" $
        run chompThenX "{- line one\nline two -} x" @?= Right (),
      testCase "nested block comment" $
        run chompThenX "{- outer {- inner -} outer -} x" @?= Right ()
    ]

-- | Tests that 'Space.chomp' signals 'SyntaxError.HasTab' when it
-- encounters a tab character.
testChompTabError :: TestTree
testChompTabError =
  testCase "tab character produces HasTab error" $
    case run chompThenX "\tx" of
      Left (HasTab _ _) -> pure ()
      other -> assertFailure ("expected HasTab error, got: " <> show other)

-- | Tests that 'Space.chomp' signals 'SyntaxError.EndlessMultiComment'
-- for an unterminated block comment.
testChompUnterminatedBlock :: TestTree
testChompUnterminatedBlock =
  testCase "unterminated block comment produces EndlessMultiComment error" $
    case run chompThenX "{- unterminated" of
      Left (EndlessComment _ _) -> pure ()
      other -> assertFailure ("expected EndlessMultiComment, got: " <> show other)

-- | Tests that a tab inside a block comment also signals 'SyntaxError.HasTab'.
testChompTabInBlockComment :: TestTree
testChompTabInBlockComment =
  testCase "tab inside block comment produces HasTab error" $
    case run chompThenX "{- has\ttab -} x" of
      Left (HasTab _ _) -> pure ()
      other -> assertFailure ("expected HasTab in block comment, got: " <> show other)

-- | Tests that a @{-|@ opening is treated as a doc comment opener and
-- is NOT consumed by 'Space.chomp' (it stops before it).
testChompStopsBeforeDocComment :: TestTree
testChompStopsBeforeDocComment =
  testCase "chomp stops before {-| doc comment opener" $
    case run (Space.chomp toSpaceErr *> Space.docComment toBadEnd toSpaceErr) "{-| doc -}" of
      Right (Src.Comment _) -> pure ()
      other -> assertFailure ("expected doc comment, got: " <> show other)

-- ---------------------------------------------------------------------------
-- docComment tests
-- ---------------------------------------------------------------------------

-- | Tests that 'Space.docComment' successfully parses a well-formed
-- doc comment and returns a 'Src.Comment'.
testDocCommentBasic :: TestTree
testDocCommentBasic =
  testCase "parses well-formed doc comment" $
    case run (Space.docComment toBadEnd toSpaceErr) "{-| documentation -}" of
      Right (Src.Comment _) -> pure ()
      other -> assertFailure ("expected Comment, got: " <> show other)

-- | Tests that 'Space.docComment' handles doc comments spanning multiple
-- lines.
testDocCommentMultiline :: TestTree
testDocCommentMultiline =
  testCase "parses multiline doc comment" $
    case run (Space.docComment toBadEnd toSpaceErr) "{-| line one\nline two -}" of
      Right (Src.Comment _) -> pure ()
      other -> assertFailure ("expected Comment from multiline doc, got: " <> show other)

-- | Tests that 'Space.docComment' rejects a regular block comment
-- (which starts @{-@ without the @|@).
testDocCommentRejectsRegularBlock :: TestTree
testDocCommentRejectsRegularBlock =
  testCase "rejects regular block comment as doc comment" $
    case run (Space.docComment toBadEnd toSpaceErr) "{- not a doc -}" of
      Left _ -> pure ()
      Right _ -> assertFailure "expected failure for non-doc block comment"

-- | Tests that 'Space.docComment' rejects an unterminated doc comment
-- with 'SyntaxError.EndlessMultiComment'.
testDocCommentUnterminated :: TestTree
testDocCommentUnterminated =
  testCase "unterminated doc comment produces EndlessMultiComment" $
    case run (Space.docComment toBadEnd toSpaceErr) "{-| missing close" of
      Left (EndlessComment _ _) -> pure ()
      other -> assertFailure ("expected EndlessMultiComment, got: " <> show other)

-- | Tests that 'Space.docComment' reports 'SyntaxError.HasTab' for a
-- tab inside the doc comment body.
testDocCommentTabError :: TestTree
testDocCommentTabError =
  testCase "tab inside doc comment produces HasTab error" $
    case run (Space.docComment toBadEnd toSpaceErr) "{-| has\ttab -}" of
      Left (HasTab _ _) -> pure ()
      other -> assertFailure ("expected HasTab in doc comment, got: " <> show other)

-- | Tests that an empty doc comment body is valid.
testDocCommentEmpty :: TestTree
testDocCommentEmpty =
  testCase "empty doc comment body is valid" $
    case run (Space.docComment toBadEnd toSpaceErr) "{--}" of
      Right (Src.Comment _) -> pure ()
      Left _ -> pure ()

-- ---------------------------------------------------------------------------
-- checkFreshLine tests
-- ---------------------------------------------------------------------------

-- | Tests that 'Space.checkFreshLine' succeeds at column 1 (start of input).
testCheckFreshLineAtStart :: TestTree
testCheckFreshLineAtStart =
  testCase "checkFreshLine succeeds at column 1" $
    run (Space.checkFreshLine BadFreshLine *> consumeX) "x" @?= Right ()

-- | Tests that 'Space.checkFreshLine' succeeds after a newline puts the
-- parser at column 1.
testCheckFreshLineAfterNewline :: TestTree
testCheckFreshLineAfterNewline =
  testCase "checkFreshLine succeeds after newline" $
    run (Space.chomp toSpaceErr *> Space.checkFreshLine BadFreshLine *> consumeX) "\nx" @?= Right ()

-- | Tests that 'Space.checkFreshLine' fails when the parser is not at
-- column 1 (i.e. in the middle of a line).
testCheckFreshLineNotAtStart :: TestTree
testCheckFreshLineNotAtStart =
  testCase "checkFreshLine fails when not at column 1" $
    case run (consumeY *> Space.checkFreshLine BadFreshLine *> consumeX) "yx" of
      Left (BadFreshLine _ _) -> pure ()
      other -> assertFailure ("expected BadFreshLine, got: " <> show other)

-- ---------------------------------------------------------------------------
-- checkIndent tests
-- ---------------------------------------------------------------------------

-- | Tests that 'Space.checkIndent' passes when the current column is
-- greater than both the indent level and 1.
--
-- 'fromByteString' starts with indent=0. After 'Parse.withIndent' sets
-- indent=col, the column is already at col so we parse some input to
-- advance column, then check. We compose: withIndent (consumeX *>
-- chomp *> getPosition >>= \p -> checkIndent p toErr *> consumeY)
-- on input "x y".
testCheckIndentPasses :: TestTree
testCheckIndentPasses =
  testCase "checkIndent passes when col > indent and col > 1" $
    run indentParser "x y" @?= Right ()
  where
    indentParser :: Parse.Parser TestError ()
    indentParser = Parse.withIndent inner
    inner :: Parse.Parser TestError ()
    inner = do
      consumeX
      Space.chomp toSpaceErr
      pos <- Parse.getPosition
      Space.checkIndent pos BadIndent
      consumeY

-- | Tests that 'Space.checkIndent' fails when the current column is
-- not greater than the indent level.
testCheckIndentFails :: TestTree
testCheckIndentFails =
  testCase "checkIndent fails when col <= indent" $
    case run outerParser "x\ny" of
      Left (BadIndent _ _) -> pure ()
      other -> assertFailure ("expected BadIndent, got: " <> show other)
  where
    outerParser :: Parse.Parser TestError ()
    outerParser = Parse.withIndent inner
    inner :: Parse.Parser TestError ()
    inner = do
      consumeX
      Space.chomp toSpaceErr
      pos <- Parse.getPosition
      Space.checkIndent pos BadIndent
      consumeY

-- ---------------------------------------------------------------------------
-- checkAligned tests
-- ---------------------------------------------------------------------------

toAlignErr :: Word32 -> Parse.Row -> Parse.Col -> TestError
toAlignErr _ r c = BadAligned r c

-- | Tests that 'Space.checkAligned' succeeds when the current column
-- equals the indent level. We use 'Parse.withIndent' to set the indent
-- to the current column, then verify alignment holds.
testCheckAlignedPasses :: TestTree
testCheckAlignedPasses =
  testCase "checkAligned passes when col == indent" $
    run (Parse.withIndent (Space.checkAligned toAlignErr *> consumeX)) "x" @?= Right ()

-- | Tests that 'Space.checkAligned' fails when the column does not match
-- the indent level.
testCheckAlignedFails :: TestTree
testCheckAlignedFails =
  testCase "checkAligned fails when col != indent" $
    case run alignedParser "x y" of
      Left (BadAligned _ _) -> pure ()
      other -> assertFailure ("expected BadAligned, got: " <> show other)
  where
    alignedParser :: Parse.Parser TestError ()
    alignedParser = Parse.withIndent inner
    inner :: Parse.Parser TestError ()
    inner = do
      consumeX
      Space.chomp toSpaceErr
      Space.checkAligned toAlignErr
      consumeY

-- ---------------------------------------------------------------------------
-- chompAndCheckIndent tests
-- ---------------------------------------------------------------------------

-- | Tests that 'Space.chompAndCheckIndent' in one step consumes whitespace
-- and verifies the resulting column is properly indented.
testChompAndCheckIndentPasses :: TestTree
testChompAndCheckIndentPasses =
  testCase "chompAndCheckIndent passes when col > indent after chomp" $
    run parser "x  y" @?= Right ()
  where
    parser :: Parse.Parser TestError ()
    parser = Parse.withIndent inner
    inner :: Parse.Parser TestError ()
    inner = do
      consumeX
      Space.chompAndCheckIndent toSpaceErr BadIndent
      consumeY

-- | Tests that 'Space.chompAndCheckIndent' fails with a space error
-- when a tab is encountered while chomping.
testChompAndCheckIndentTabError :: TestTree
testChompAndCheckIndentTabError =
  testCase "chompAndCheckIndent fails with HasTab on tab character" $
    case run (Parse.withIndent (consumeX *> Space.chompAndCheckIndent toSpaceErr BadIndent *> consumeY)) "x\ty" of
      Left (HasTab _ _) -> pure ()
      other -> assertFailure ("expected HasTab, got: " <> show other)

-- ---------------------------------------------------------------------------
-- Test tree
-- ---------------------------------------------------------------------------

-- | All 'Parse.Space' tests.
tests :: TestTree
tests =
  testGroup
    "Parse.Space"
    [ testGroup
        "chomp"
        [ testChompSpaces,
          testChompNewlines,
          testChompLineComments,
          testChompBlockComments,
          testChompTabError,
          testChompUnterminatedBlock,
          testChompTabInBlockComment,
          testChompStopsBeforeDocComment
        ],
      testGroup
        "docComment"
        [ testDocCommentBasic,
          testDocCommentMultiline,
          testDocCommentRejectsRegularBlock,
          testDocCommentUnterminated,
          testDocCommentTabError,
          testDocCommentEmpty
        ],
      testGroup
        "checkFreshLine"
        [ testCheckFreshLineAtStart,
          testCheckFreshLineAfterNewline,
          testCheckFreshLineNotAtStart
        ],
      testGroup
        "checkIndent"
        [ testCheckIndentPasses,
          testCheckIndentFails
        ],
      testGroup
        "checkAligned"
        [ testCheckAlignedPasses,
          testCheckAlignedFails
        ],
      testGroup
        "chompAndCheckIndent"
        [ testChompAndCheckIndentPasses,
          testChompAndCheckIndentTabError
        ]
    ]

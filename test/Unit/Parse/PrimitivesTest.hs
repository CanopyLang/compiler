-- | Unit tests for 'Parse.Primitives'.
--
-- These tests exercise the core parser combinators directly through
-- 'fromByteString', verifying that each primitive behaves correctly
-- on both successful and failing inputs.  Position-tracking functions
-- are tested by composing them with character consumers so that the
-- column advance is observable.
module Unit.Parse.PrimitivesTest (tests) where

import qualified Data.ByteString.Char8 as C8
import qualified Data.Word as Word (Word32)
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

-- ---------------------------------------------------------------------------
-- Error type used throughout this test module.
--
-- 'TestError' carries the row/col pair reported by the parser on failure so
-- that error-position tests can make precise assertions.
-- ---------------------------------------------------------------------------

-- | A simple error value that records where the parser failed.
data TestError = TestError Word.Word32 Word.Word32
  deriving (Eq, Show)

-- | Build a 'TestError' from the row and column supplied by the framework.
mkError :: Word.Word32 -> Word.Word32 -> TestError
mkError = TestError

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Run a parser over an ASCII string, returning the result or a 'TestError'.
run :: Parse.Parser TestError a -> String -> Either TestError a
run parser input = Parse.fromByteString parser mkError (C8.pack input)

-- | Assert that parsing succeeds and return the value; fail the test otherwise.
expectRight :: (Show e) => Either e a -> (a -> IO ()) -> IO ()
expectRight result check =
  either (\e -> assertFailure ("unexpected failure: " <> show e)) check result

-- ---------------------------------------------------------------------------
-- Test suite
-- ---------------------------------------------------------------------------

-- | All 'Parse.Primitives' tests.
tests :: TestTree
tests =
  testGroup
    "Parse.Primitives"
    [ testWord1,
      testWord2,
      testOneOf,
      testOneOfWithFallback,
      testGetPosition,
      testGetCol,
      testFromByteString,
      testGetCharWidth,
      testAddLocation
    ]

-- ---------------------------------------------------------------------------
-- word1
-- ---------------------------------------------------------------------------

-- | Tests for 'Parse.word1': matches exactly one byte.
testWord1 :: TestTree
testWord1 =
  testGroup
    "word1"
    [ testCase "succeeds on matching byte" $
        run (Parse.word1 0x61 mkError) "a" @?= Right (),
      testCase "fails on non-matching byte" $
        assertBool "expected Left" (isLeft (run (Parse.word1 0x61 mkError) "b")),
      testCase "fails on empty input" $
        assertBool "expected Left" (isLeft (run (Parse.word1 0x61 mkError) "")),
      testCase "fails when unconsumed input remains" $
        assertBool "expected Left" (isLeft (run (Parse.word1 0x61 mkError) "ab")),
      testCase "succeeds on digit byte 0x30 ('0')" $
        run (Parse.word1 0x30 mkError) "0" @?= Right ()
    ]

-- ---------------------------------------------------------------------------
-- word2
-- ---------------------------------------------------------------------------

-- | Tests for 'Parse.word2': matches exactly two consecutive bytes.
testWord2 :: TestTree
testWord2 =
  testGroup
    "word2"
    [ testCase "succeeds on matching two-byte sequence" $
        run (Parse.word2 0x61 0x62 mkError) "ab" @?= Right (),
      testCase "fails when first byte mismatches" $
        assertBool "expected Left" (isLeft (run (Parse.word2 0x61 0x62 mkError) "xb")),
      testCase "fails when second byte mismatches" $
        assertBool "expected Left" (isLeft (run (Parse.word2 0x61 0x62 mkError) "ax")),
      testCase "fails on single-byte input" $
        assertBool "expected Left" (isLeft (run (Parse.word2 0x61 0x62 mkError) "a")),
      testCase "fails on empty input" $
        assertBool "expected Left" (isLeft (run (Parse.word2 0x61 0x62 mkError) "")),
      testCase "fails when unconsumed input remains after match" $
        assertBool "expected Left" (isLeft (run (Parse.word2 0x61 0x62 mkError) "abc"))
    ]

-- ---------------------------------------------------------------------------
-- oneOf
-- ---------------------------------------------------------------------------

-- | Tests for 'Parse.oneOf': tries each parser in order and takes the first
-- success.
testOneOf :: TestTree
testOneOf =
  testGroup
    "oneOf"
    [ testCase "first alternative matches" $
        run parseAOrB "a" @?= Right 'a',
      testCase "second alternative matches when first fails" $
        run parseAOrB "b" @?= Right 'b',
      testCase "fails when no alternative matches" $
        assertBool "expected Left" (isLeft (run parseAOrB "c")),
      testCase "empty list always fails" $
        assertBool "expected Left" (isLeft (run (Parse.oneOf mkError []) "a"))
    ]
  where
    parseAOrB :: Parse.Parser TestError Char
    parseAOrB =
      Parse.oneOf
        mkError
        [ 'a' <$ Parse.word1 0x61 mkError,
          'b' <$ Parse.word1 0x62 mkError
        ]

-- ---------------------------------------------------------------------------
-- oneOfWithFallback
-- ---------------------------------------------------------------------------

-- | Tests for 'Parse.oneOfWithFallback': returns the fallback value when all
-- alternatives fail without consuming input.
testOneOfWithFallback :: TestTree
testOneOfWithFallback =
  testGroup
    "oneOfWithFallback"
    [ testCase "returns result of first matching alternative" $
        run (Parse.oneOfWithFallback [Parse.word1 0x61 mkError] ()) "a" @?= Right (),
      testCase "returns fallback when empty list provided" $
        run (Parse.oneOfWithFallback [] (42 :: Int)) "" @?= Right 42,
      testCase "returns fallback on empty input when no alternative matches" $
        run (Parse.oneOfWithFallback [Parse.word1 0x61 mkError] ()) "" @?= Right (),
      testCase "first matching alternative wins" $
        run parseFallbackChoice "a" @?= Right (1 :: Int),
      testCase "second matching alternative used when first fails" $
        run parseFallbackChoice "b" @?= Right (2 :: Int),
      testCase "fallback returned on empty input when no parser matches" $
        run parseFallbackChoice "" @?= Right (0 :: Int)
    ]
  where
    parseFallbackChoice :: Parse.Parser TestError Int
    parseFallbackChoice =
      Parse.oneOfWithFallback
        [ 1 <$ Parse.word1 0x61 mkError,
          2 <$ Parse.word1 0x62 mkError
        ]
        0

-- ---------------------------------------------------------------------------
-- getPosition
-- ---------------------------------------------------------------------------

-- | Tests for 'Parse.getPosition': reports the current row and column.
testGetPosition :: TestTree
testGetPosition =
  testGroup
    "getPosition"
    [ testCase "position at start is row 1, col 1" $
        run Parse.getPosition "" @?= Right (Ann.Position 1 1),
      testCase "col advances by 1 after consuming one byte" $
        expectRight (run posAfterOne "a") (\p -> p @?= Ann.Position 1 2),
      testCase "col advances by 2 after consuming two bytes" $
        expectRight (run posAfterTwo "ab") (\p -> p @?= Ann.Position 1 3)
    ]
  where
    posAfterOne :: Parse.Parser TestError Ann.Position
    posAfterOne = Parse.word1 0x61 mkError *> Parse.getPosition

    posAfterTwo :: Parse.Parser TestError Ann.Position
    posAfterTwo =
      Parse.word1 0x61 mkError
        *> Parse.word1 0x62 mkError
        *> Parse.getPosition

-- ---------------------------------------------------------------------------
-- getCol
-- ---------------------------------------------------------------------------

-- | Tests for 'Parse.getCol': returns the current column number.
testGetCol :: TestTree
testGetCol =
  testGroup
    "getCol"
    [ testCase "col is 1 at the start of input" $
        run Parse.getCol "" @?= Right 1,
      testCase "col is 2 after consuming one byte" $
        expectRight (run colAfterByte "x") (\c -> c @?= 2),
      testCase "col is 3 after consuming two bytes" $
        expectRight (run colAfterTwo "xy") (\c -> c @?= 3)
    ]
  where
    colAfterByte :: Parse.Parser TestError Word.Word32
    colAfterByte = Parse.word1 0x78 mkError *> Parse.getCol

    colAfterTwo :: Parse.Parser TestError Word.Word32
    colAfterTwo =
      Parse.word1 0x78 mkError
        *> Parse.word1 0x79 mkError
        *> Parse.getCol

-- ---------------------------------------------------------------------------
-- fromByteString
-- ---------------------------------------------------------------------------

-- | Tests for 'Parse.fromByteString' itself: verifies that it reports an
-- error when input is not fully consumed, and succeeds when it is.
testFromByteString :: TestTree
testFromByteString =
  testGroup
    "fromByteString"
    [ testCase "Right when all input consumed" $
        Parse.fromByteString (Parse.word1 0x61 mkError) mkError (C8.pack "a")
          @?= Right (),
      testCase "Left when input not fully consumed" $
        assertBool "expected Left" $
          isLeft
            (Parse.fromByteString (Parse.word1 0x61 mkError) mkError (C8.pack "ab")),
      testCase "Left with correct position on unconsumed input" $
        Parse.fromByteString (Parse.word1 0x61 mkError) mkError (C8.pack "ab")
          @?= Left (TestError 1 2),
      testCase "Right on empty parser over empty input" $
        Parse.fromByteString (pure ()) mkError (C8.pack "")
          @?= Right ()
    ]

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------

-- | Predicate mirroring 'Data.Either.isLeft' without importing it.
isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

-- ---------------------------------------------------------------------------
-- getCharWidth
-- ---------------------------------------------------------------------------

-- | Tests for 'Parse.getCharWidth': returns the number of bytes in the
-- UTF-8 character introduced by the given leading byte.
testGetCharWidth :: TestTree
testGetCharWidth =
  testGroup
    "getCharWidth"
    [ testCase "ASCII byte 0x41 ('A') has width 1" $
        Parse.getCharWidth 0x41 @?= 1,
      testCase "ASCII byte 0x7F (DEL) has width 1" $
        Parse.getCharWidth 0x7F @?= 1,
      testCase "two-byte leader 0xC3 has width 2" $
        Parse.getCharWidth 0xC3 @?= 2,
      testCase "two-byte leader 0xDF has width 2" $
        Parse.getCharWidth 0xDF @?= 2,
      testCase "three-byte leader 0xE2 has width 3" $
        Parse.getCharWidth 0xE2 @?= 3,
      testCase "three-byte leader 0xEF has width 3" $
        Parse.getCharWidth 0xEF @?= 3,
      testCase "four-byte leader 0xF0 has width 4" $
        Parse.getCharWidth 0xF0 @?= 4,
      testCase "four-byte leader 0xF4 has width 4" $
        Parse.getCharWidth 0xF4 @?= 4
    ]

-- ---------------------------------------------------------------------------
-- addLocation
-- ---------------------------------------------------------------------------

-- | Tests for 'Parse.addLocation': wraps a parsed value with its source region.
testAddLocation :: TestTree
testAddLocation =
  testGroup
    "addLocation"
    [ testCase "region starts at col 1 for first token" $
        expectRight
          (run (Parse.addLocation (Parse.word1 0x61 mkError)) "a")
          (\(Ann.At (Ann.Region start _) _) -> start @?= Ann.Position 1 1),
      testCase "region ends at col 2 after consuming one byte" $
        expectRight
          (run (Parse.addLocation (Parse.word1 0x61 mkError)) "a")
          (\(Ann.At (Ann.Region _ end) _) -> end @?= Ann.Position 1 2),
      testCase "region spans two bytes for word2" $
        expectRight
          (run (Parse.addLocation (Parse.word2 0x61 0x62 mkError)) "ab")
          (\(Ann.At (Ann.Region start end) _) ->
            (start, end) @?= (Ann.Position 1 1, Ann.Position 1 3))
    ]

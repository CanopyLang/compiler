{-# LANGUAGE BangPatterns, UnboxedTuples, OverloadedStrings #-}

-- | Parse.Space — Whitespace, comment, and indentation utilities.
--
-- Implements the Canopy layout rules: indentation-sensitivity for
-- let\/case\/where blocks, alignment checks for definition lists, and
-- comment stripping (line comments @--@ and block comments @{- -}@).
--
-- The 'Parser' type alias re-exports the underlying parser type with
-- the additional position information required for indent checking.
--
-- @since 0.19.1
module Parse.Space
  ( Parser
  --
  , chomp
  , chompAndCheckIndent
  --
  , checkIndent
  , checkAligned
  , checkFreshLine
  --
  , docComment
  )
  where


import Data.Word (Word8, Word32)
import Foreign.Ptr (Ptr, plusPtr, minusPtr)
import Foreign.ForeignPtr.Unsafe (unsafeForeignPtrToPtr)

import qualified AST.Source as Src
import Parse.Primitives (Row, Col)
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError



-- SPACE PARSING


-- | A parser that returns its result paired with the source end position.
--
-- The position is used by callers to perform indentation checks after
-- consuming whitespace.
--
-- @since 0.19.1
type Parser x a =
  Parse.Parser x (a, Ann.Position)



-- CHOMP


-- | Consume whitespace and comments, failing on tabs or endless block comments.
--
-- Skips spaces, newlines, line comments (@--@), and balanced block
-- comments (@{- -}@).  Returns a committed error if a tab character is
-- encountered (tabs are not permitted in Canopy source) or if a block
-- comment is not closed before end-of-file.
--
-- @since 0.19.1
chomp :: (SyntaxError.Space -> Row -> Col -> x) -> Parse.Parser x ()
chomp toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr _ ->
    let
      (# status, newPos, newRow, newCol #) = eatSpaces pos end row col
    in
    case status of
      Good ->
        let
          !newState = Parse.State src newPos end indent newRow newCol
        in
        cok () newState

      HasTab               -> cerr newRow newCol (toError SyntaxError.HasTab)
      EndlessMultiComment  -> cerr newRow newCol (toError SyntaxError.EndlessMultiComment)



-- CHECKS -- to be called right after a `chomp`


-- | Assert that the current column is greater than the indent level.
--
-- The @end@ position is used in the error message to point at the last
-- successfully parsed token rather than the current whitespace position.
-- Fails with an empty error to allow backtracking.
--
-- @since 0.19.1
checkIndent :: Ann.Position -> (Row -> Col -> x) -> Parse.Parser x ()
checkIndent (Ann.Position endRow endCol) toError =
  Parse.Parser $ \state@(Parse.State _ _ _ indent _ col) _ eok _ eerr ->
    if col > indent && col > 1
    then eok () state
    else eerr endRow endCol toError


-- | Assert that the current column equals the current indent level.
--
-- Used to enforce alignment of definitions within a let block or case
-- alternatives.  The error callback receives the expected indent column
-- as its first argument so the error message can be precise.
--
-- @since 0.19.1
checkAligned :: (Word32 -> Row -> Col -> x) -> Parse.Parser x ()
checkAligned toError =
  Parse.Parser $ \state@(Parse.State _ _ _ indent row col) _ eok _ eerr ->
    if col == indent
    then eok () state
    else eerr row col (toError indent)


-- | Assert that the parser is positioned at the start of a line (column 1).
--
-- Used for top-level declarations that must begin at column 1.
--
-- @since 0.19.1
checkFreshLine :: (Row -> Col -> x) -> Parse.Parser x ()
checkFreshLine toError =
  Parse.Parser $ \state@(Parse.State _ _ _ _ row col) _ eok _ eerr ->
    if col == 1
    then eok () state
    else eerr row col toError



-- CHOMP AND CHECK


-- | Consume whitespace then assert the result is properly indented.
--
-- Combines 'chomp' and 'checkIndent' into a single pass to avoid
-- duplicate whitespace traversal.  The space-error callback is used for
-- tab\/endless-comment failures; the indent-error callback is used when
-- the next non-whitespace character is not sufficiently indented.
--
-- @since 0.19.1
chompAndCheckIndent :: (SyntaxError.Space -> Row -> Col -> x) -> (Row -> Col -> x) -> Parse.Parser x ()
chompAndCheckIndent toSpaceError toIndentError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr _ ->
    let
      (# status, newPos, newRow, newCol #) = eatSpaces pos end row col
    in
    case status of
      Good ->
        if newCol > indent && newCol > 1
        then

          let
            !newState = Parse.State src newPos end indent newRow newCol
          in
          cok () newState

        else
          cerr row col toIndentError

      HasTab               -> cerr newRow newCol (toSpaceError SyntaxError.HasTab)
      EndlessMultiComment  -> cerr newRow newCol (toSpaceError SyntaxError.EndlessMultiComment)



-- EAT SPACES


data Status
  = Good
  | HasTab
  | EndlessMultiComment


eatSpaces :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# Status, Ptr Word8, Row, Col #)
eatSpaces pos end row col =
  if pos >= end then
    (# Good, pos, row, col #)

  else
    case Parse.unsafeIndex pos of
      0x20 {-   -} ->
        eatSpaces (plusPtr pos 1) end row (col + 1)

      0x0A {- \n -} ->
        eatSpaces (plusPtr pos 1) end (row + 1) 1

      0x7B {- { -} ->
        eatMultiComment pos end row col

      0x2D {- - -} ->
        let !pos1 = plusPtr pos 1 in
        if pos1 < end && Parse.unsafeIndex pos1 == 0x2D {- - -} then
          eatLineComment (plusPtr pos 2) end row (col + 2)
        else
          (# Good, pos, row, col #)

      0x0D {- \r -} ->
        eatSpaces (plusPtr pos 1) end row col

      0x09 {- \t -} ->
        (# HasTab, pos, row, col #)

      _ ->
        (# Good, pos, row, col #)



-- LINE COMMENTS


eatLineComment :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# Status, Ptr Word8, Row, Col #)
eatLineComment pos end row col =
  if pos >= end then
    (# Good, pos, row, col #)

  else
    let !word = Parse.unsafeIndex pos in
    if word == 0x0A {- \n -} then
      eatSpaces (plusPtr pos 1) end (row + 1) 1
    else
      let !newPos = plusPtr pos (Parse.getCharWidth word) in
      eatLineComment newPos end row (col + 1)



-- MULTI COMMENTS


eatMultiComment :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# Status, Ptr Word8, Row, Col #)
eatMultiComment pos end row col =
  let
    !pos1 = plusPtr pos 1
    !pos2 = plusPtr pos 2
  in
  if pos2 >= end then
    (# Good, pos, row, col #)

  else if Parse.unsafeIndex pos1 == 0x2D {- - -} then

    if Parse.unsafeIndex pos2 == 0x7C {- | -} then
      (# Good, pos, row, col #)
    else
      let
        (# status, newPos, newRow, newCol #) =
          eatMultiCommentHelp pos2 end row (col + 2) 1
      in
      case status of
        MultiGood    -> eatSpaces newPos end newRow newCol
        MultiTab     -> (# HasTab, newPos, newRow, newCol #)
        MultiEndless -> (# EndlessMultiComment, pos, row, col #)

  else
    (# Good, pos, row, col #)


data MultiStatus
  = MultiGood
  | MultiTab
  | MultiEndless


eatMultiCommentHelp :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> Word32 -> (# MultiStatus, Ptr Word8, Row, Col #)
eatMultiCommentHelp pos end row col openComments =
  if pos >= end then
    (# MultiEndless, pos, row, col #)

  else
    let !word = Parse.unsafeIndex pos in
    if word == 0x0A {- \n -} then
      eatMultiCommentHelp (plusPtr pos 1) end (row + 1) 1 openComments

    else if word == 0x09 {- \t -} then
      (# MultiTab, pos, row, col #)

    else if word == 0x2D {- - -} && Parse.isWord (plusPtr pos 1) end 0x7D {- } -} then
      if openComments == 1 then
        (# MultiGood, plusPtr pos 2, row, col + 2 #)
      else
        eatMultiCommentHelp (plusPtr pos 2) end row (col + 2) (openComments - 1)

    else if word == 0x7B {- { -} && Parse.isWord (plusPtr pos 1) end 0x2D {- - -} then
      eatMultiCommentHelp (plusPtr pos 2) end row (col + 2) (openComments + 1)

    else
      let !newPos = plusPtr pos (Parse.getCharWidth word) in
      eatMultiCommentHelp newPos end row (col + 1) openComments



-- DOCUMENTATION COMMENT


-- | Parse a documentation comment (@{-| … -}@).
--
-- A doc comment begins with the three-character sequence @{-|@ and ends
-- with @-}@.  The content is returned as a 'Src.Comment' snippet
-- preserving the exact source bytes for later rendering.  Tab characters
-- and unclosed comments produce committed errors.
--
-- @since 0.19.1
docComment :: (Row -> Col -> x) -> (SyntaxError.Space -> Row -> Col -> x) -> Parse.Parser x Src.Comment
docComment toExpectation toSpaceError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr eerr ->
    let
      !pos3 = plusPtr pos 3
    in
    if pos3 <= end
      && Parse.unsafeIndex (        pos  ) == 0x7B {- { -}
      && Parse.unsafeIndex (plusPtr pos 1) == 0x2D {- - -}
      && Parse.unsafeIndex (plusPtr pos 2) == 0x7C {- | -}
    then
      let
        !col3 = col + 3

        (# status, newPos, newRow, newCol #) =
           eatMultiCommentHelp pos3 end row col3 1
      in
      case status of
        MultiGood ->
          let
            !off = minusPtr pos3 (unsafeForeignPtrToPtr src)
            !len = minusPtr newPos pos3 - 2
            !snippet = Parse.Snippet src off len row col3
            !comment = Src.Comment snippet
            !newState = Parse.State src newPos end indent newRow newCol
          in
          cok comment newState

        MultiTab -> cerr newRow newCol (toSpaceError SyntaxError.HasTab)
        MultiEndless -> cerr row col (toSpaceError SyntaxError.EndlessMultiComment)
    else
      eerr row col toExpectation

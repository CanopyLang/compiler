{-# LANGUAGE OverloadedStrings #-}

-- | Comment extraction from source bytes.
--
-- Provides a standalone scanner that extracts all non-doc comments
-- (line comments and block comments) from Canopy source code. This
-- runs as a separate pass before the main parser so that the parser
-- itself is not modified.
--
-- The scanner produces a list of 'RawComment' values sorted by
-- source position. The formatter uses these to re-emit comments
-- at the correct locations relative to declarations.
--
-- Doc comments (@{-| ... -}@) are excluded because they are already
-- captured by the parser and stored in the 'Docs' field of 'Module'.
--
-- @since 0.19.2
module Parse.Comment
  ( extractComments,
  )
where

import qualified AST.Source as Src
import qualified Data.ByteString as BS
import Data.Word (Word8, Word32)

-- | Extract all non-doc comments from a source ByteString.
--
-- Scans the bytes sequentially, identifying line comments (@-- ...@)
-- and block comments (@{- ... -}@) but skipping doc comments
-- (@{-| ... -}@). Returns comments sorted by position (naturally,
-- since the scan is sequential).
extractComments :: BS.ByteString -> [Src.RawComment]
extractComments bytes =
  reverse (scanBytes bytes 0 1 1 [])

-- | Scan bytes from a given offset, accumulating comments.
--
-- Tracks row and column position to annotate each comment with
-- its source location.
scanBytes :: BS.ByteString -> Int -> Word32 -> Word32 -> [Src.RawComment] -> [Src.RawComment]
scanBytes bytes offset row col acc
  | offset >= BS.length bytes = acc
  | otherwise = scanByte bytes offset row col (BS.index bytes offset) acc

-- | Process a single byte and decide how to continue scanning.
scanByte :: BS.ByteString -> Int -> Word32 -> Word32 -> Word8 -> [Src.RawComment] -> [Src.RawComment]
scanByte bytes offset row col byte acc
  | byte == 0x0A = -- newline
      scanBytes bytes (offset + 1) (row + 1) 1 acc
  | byte == 0x0D = -- carriage return
      scanBytes bytes (offset + 1) row col acc
  | byte == 0x2D = -- dash, possible line comment
      scanDash bytes offset row col acc
  | byte == 0x7B = -- open brace, possible block comment
      scanOpenBrace bytes offset row col acc
  | byte == 0x22 = -- double quote, skip string literal
      skipString bytes (offset + 1) row (col + 1) acc
  | byte == 0x27 = -- single quote, skip char literal
      skipChar bytes (offset + 1) row (col + 1) acc
  | otherwise =
      scanBytes bytes (offset + 1) row (col + 1) acc

-- | Handle a dash character: check for @--@ line comment.
scanDash :: BS.ByteString -> Int -> Word32 -> Word32 -> [Src.RawComment] -> [Src.RawComment]
scanDash bytes offset row col acc
  | offset + 1 < BS.length bytes && BS.index bytes (offset + 1) == 0x2D =
      extractLineComment bytes offset row col acc
  | otherwise =
      scanBytes bytes (offset + 1) row (col + 1) acc

-- | Handle an open brace: check for @{-@ block comment (but not @{-|@ doc comment).
scanOpenBrace :: BS.ByteString -> Int -> Word32 -> Word32 -> [Src.RawComment] -> [Src.RawComment]
scanOpenBrace bytes offset row col acc
  | offset + 1 < BS.length bytes && BS.index bytes (offset + 1) == 0x2D =
      scanBlockCommentStart bytes offset row col acc
  | otherwise =
      scanBytes bytes (offset + 1) row (col + 1) acc

-- | Check whether a @{-@ is a doc comment (@{-|@) or a regular block comment.
scanBlockCommentStart :: BS.ByteString -> Int -> Word32 -> Word32 -> [Src.RawComment] -> [Src.RawComment]
scanBlockCommentStart bytes offset row col acc
  | offset + 2 < BS.length bytes && BS.index bytes (offset + 2) == 0x7C =
      -- Doc comment {-| ... -}, skip it (already handled by parser)
      skipBlockComment bytes (offset + 2) row (col + 2) 1 acc
  | otherwise =
      extractBlockComment bytes offset row col acc

-- | Extract a line comment starting at the given offset.
--
-- The comment text includes everything from @--@ to end of line (exclusive).
extractLineComment :: BS.ByteString -> Int -> Word32 -> Word32 -> [Src.RawComment] -> [Src.RawComment]
extractLineComment bytes offset row col acc =
  scanBytes bytes endOffset (row + 1) 1 (comment : acc)
  where
    contentStart = offset + 2
    endOffset = findLineEnd bytes contentStart
    commentText = BS.take (endOffset - contentStart) (BS.drop contentStart bytes)
    comment = Src.RawComment Src.LineComment row col commentText

-- | Find the end of a line (offset of the newline character or end of input).
findLineEnd :: BS.ByteString -> Int -> Int
findLineEnd bytes offset
  | offset >= BS.length bytes = offset
  | BS.index bytes offset == 0x0A = offset + 1
  | BS.index bytes offset == 0x0D = offset + 1
  | otherwise = findLineEnd bytes (offset + 1)

-- | Extract a block comment starting at the given offset.
--
-- Handles nested block comments by tracking the nesting depth.
-- The comment text includes everything between @{-@ and @-}@ (exclusive).
extractBlockComment :: BS.ByteString -> Int -> Word32 -> Word32 -> [Src.RawComment] -> [Src.RawComment]
extractBlockComment bytes offset row col acc =
  let contentStart = offset + 2
      (endOffset, endRow, endCol) = findBlockEnd bytes contentStart row (col + 2) 1
      commentText = BS.take (endOffset - contentStart - 2) (BS.drop contentStart bytes)
      comment = Src.RawComment Src.BlockComment row col commentText
   in scanBytes bytes endOffset endRow endCol (comment : acc)

-- | Find the end of a nested block comment, tracking depth and position.
findBlockEnd :: BS.ByteString -> Int -> Word32 -> Word32 -> Int -> (Int, Word32, Word32)
findBlockEnd bytes offset row col depth
  | offset >= BS.length bytes = (offset, row, col)
  | byte == 0x0A =
      findBlockEnd bytes (offset + 1) (row + 1) 1 depth
  | byte == 0x2D && offset + 1 < BS.length bytes && BS.index bytes (offset + 1) == 0x7D =
      if depth <= 1
        then (offset + 2, row, col + 2)
        else findBlockEnd bytes (offset + 2) row (col + 2) (depth - 1)
  | byte == 0x7B && offset + 1 < BS.length bytes && BS.index bytes (offset + 1) == 0x2D =
      findBlockEnd bytes (offset + 2) row (col + 2) (depth + 1)
  | otherwise =
      findBlockEnd bytes (offset + 1) row (col + 1) depth
  where
    byte = BS.index bytes offset

-- | Skip over a block comment without extracting (for doc comments).
skipBlockComment :: BS.ByteString -> Int -> Word32 -> Word32 -> Int -> [Src.RawComment] -> [Src.RawComment]
skipBlockComment bytes offset row col depth acc
  | offset >= BS.length bytes = acc
  | byte == 0x0A =
      skipBlockComment bytes (offset + 1) (row + 1) 1 depth acc
  | byte == 0x2D && offset + 1 < BS.length bytes && BS.index bytes (offset + 1) == 0x7D =
      if depth <= 1
        then scanBytes bytes (offset + 2) row (col + 2) acc
        else skipBlockComment bytes (offset + 2) row (col + 2) (depth - 1) acc
  | byte == 0x7B && offset + 1 < BS.length bytes && BS.index bytes (offset + 1) == 0x2D =
      skipBlockComment bytes (offset + 2) row (col + 2) (depth + 1) acc
  | otherwise =
      skipBlockComment bytes (offset + 1) row (col + 1) depth acc
  where
    byte = BS.index bytes offset

-- | Skip a string literal (delimited by double quotes).
--
-- Handles escaped characters inside strings.
skipString :: BS.ByteString -> Int -> Word32 -> Word32 -> [Src.RawComment] -> [Src.RawComment]
skipString bytes offset row col acc
  | offset >= BS.length bytes = acc
  | byte == 0x22 = -- closing quote
      scanBytes bytes (offset + 1) row (col + 1) acc
  | byte == 0x5C && offset + 1 < BS.length bytes = -- backslash escape
      skipString bytes (offset + 2) row (col + 2) acc
  | byte == 0x0A =
      skipString bytes (offset + 1) (row + 1) 1 acc
  | otherwise =
      skipString bytes (offset + 1) row (col + 1) acc
  where
    byte = BS.index bytes offset

-- | Skip a character literal (delimited by single quotes).
--
-- Handles escaped characters inside char literals.
skipChar :: BS.ByteString -> Int -> Word32 -> Word32 -> [Src.RawComment] -> [Src.RawComment]
skipChar bytes offset row col acc
  | offset >= BS.length bytes = acc
  | byte == 0x27 = -- closing quote
      scanBytes bytes (offset + 1) row (col + 1) acc
  | byte == 0x5C && offset + 1 < BS.length bytes = -- backslash escape
      skipChar bytes (offset + 2) row (col + 2) acc
  | otherwise =
      skipChar bytes (offset + 1) row (col + 1) acc
  where
    byte = BS.index bytes offset

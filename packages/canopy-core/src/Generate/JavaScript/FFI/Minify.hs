{-# LANGUAGE OverloadedStrings #-}

-- | FFI content minification for production builds.
--
-- Applies basic JavaScript minification to FFI file content:
--
--   * Strip single-line comments (@\/\/@) that start a line
--   * Strip multi-line comments (@\/* ... *\/@) except JSDoc with \@canopy-type
--   * Remove blank lines
--   * Remove @if (__canopy_debug)@ branches in production mode
--
-- @since 0.20.2
module Generate.JavaScript.FFI.Minify
  ( minifyFFI
  , stripDebugBranches
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8


-- | Apply basic minification to FFI JavaScript content.
--
-- Strips line-leading comments and removes blank lines.
minifyFFI :: ByteString -> ByteString
minifyFFI content =
  BS8.unlines (filter keepLine processedLines)
  where
    rawLines = BS8.lines content
    processedLines = stripBlockComments rawLines
    keepLine line =
      let stripped = BS8.strip line
       in not (BS.null stripped)
            && not (isFullLineComment stripped)

-- | Check if a line is purely a comment (@\/\/@ at start).
isFullLineComment :: ByteString -> Bool
isFullLineComment line =
  BS8.isPrefixOf "//" line

-- | Remove multi-line comment blocks, preserving JSDoc with \@canopy-type.
stripBlockComments :: [ByteString] -> [ByteString]
stripBlockComments [] = []
stripBlockComments (line : rest)
  | isBlockCommentStart (BS8.strip line)
  , not (hasCanopyType (line : rest)) =
      let remaining = dropUntilCommentEnd rest
       in stripBlockComments remaining
  | otherwise = line : stripBlockComments rest

-- | Check if a line starts a block comment (@\/*@).
isBlockCommentStart :: ByteString -> Bool
isBlockCommentStart line =
  BS8.isPrefixOf "/*" line || BS8.isPrefixOf "/**" line

-- | Check if a block comment contains \@canopy-type.
hasCanopyType :: [ByteString] -> Bool
hasCanopyType [] = False
hasCanopyType (line : rest)
  | BS8.isInfixOf "@canopy-type" line = True
  | BS8.isInfixOf "*/" line = False
  | otherwise = hasCanopyType rest

-- | Drop lines until end of block comment (@*\/@).
dropUntilCommentEnd :: [ByteString] -> [ByteString]
dropUntilCommentEnd [] = []
dropUntilCommentEnd (line : rest)
  | BS8.isInfixOf "*/" line = rest
  | otherwise = dropUntilCommentEnd rest

-- | Strip @if (__canopy_debug)@ branches from FFI content.
--
-- In production mode (@__canopy_debug = false@), removes the entire
-- @if (__canopy_debug) { ... }@ block including any else clause.
stripDebugBranches :: ByteString -> ByteString
stripDebugBranches content =
  BS8.unlines (go (BS8.lines content))
  where
    go [] = []
    go (line : rest)
      | isDebugBranchStart line =
          let (remaining, hasElse) = skipBracedBlock rest 0
           in if hasElse
                then go (skipElseClause remaining)
                else go remaining
      | otherwise = line : go rest

-- | Check if a line starts a @__canopy_debug@ conditional.
isDebugBranchStart :: ByteString -> Bool
isDebugBranchStart line =
  BS8.isInfixOf "__canopy_debug" stripped
    && BS8.isInfixOf "if" stripped
  where
    stripped = BS8.strip line

-- | Skip a braced block, tracking depth. Returns remaining lines
-- and whether an @else@ follows.
skipBracedBlock :: [ByteString] -> Int -> ([ByteString], Bool)
skipBracedBlock [] _ = ([], False)
skipBracedBlock (line : rest) depth =
  let opens = BS8.count '{' line
      closes = BS8.count '}' line
      newDepth = depth + opens - closes
   in if newDepth <= 0 && opens + closes > 0
        then (rest, startsWithElse rest)
        else skipBracedBlock rest newDepth

-- | Check if the next non-blank line starts with @else@.
startsWithElse :: [ByteString] -> Bool
startsWithElse [] = False
startsWithElse (line : _) =
  BS8.isPrefixOf "else" (BS8.strip line)

-- | Skip an else clause (else { ... } or else if { ... }).
skipElseClause :: [ByteString] -> [ByteString]
skipElseClause [] = []
skipElseClause (line : rest)
  | BS8.isPrefixOf "else" (BS8.strip line) =
      fst (skipBracedBlock rest 0)
  | otherwise = line : rest

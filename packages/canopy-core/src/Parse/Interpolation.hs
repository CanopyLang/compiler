{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE UnboxedTuples #-}

-- | Parse.Interpolation - Parser for string interpolation syntax
--
-- Parses @[i|...|]@ string interpolation expressions with @#{expr}@
-- interpolation points. Follows the same quasi-quoter pattern as
-- "Parse.Shader" for @[glsl|...|]@.
--
-- Interpolation expressions desugar to @Basics.append@ chains during
-- canonicalization, producing zero-overhead native JavaScript @+@
-- concatenation when string literals are present.
--
-- ==== Syntax
--
-- @
-- [i|Hello #{name}!|]                     -- simple interpolation
-- [i|#{greeting}, #{name}!|]              -- multiple interpolations
-- [i|just a plain string|]                -- no interpolation (literal)
-- [i|cost is \\#100|]                      -- escaped hash (literal #)
-- [i|#{String.fromInt count} items|]      -- expression interpolation
-- @
--
-- ==== Desugaring
--
-- @[i|Hello #{name}!|]@ desugars to @"Hello " ++ name ++ "!"@,
-- which the code generator optimizes to @"Hello " + name + "!"@ in JS.
--
-- @since 0.19.2
module Parse.Interpolation
  ( interpolation,
  )
where

import qualified AST.Source as Src
import qualified Canopy.String as ES
import Data.Word (Word8)
import Foreign.Ptr (Ptr, minusPtr, plusPtr)
import Parse.Primitives (Col, Parser, Row)
import qualified Parse.Primitives as Parse
import qualified Parse.Space as Space
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError

-- INTERPOLATION

-- | Parse a string interpolation @[i|...|]@ expression.
--
-- Detects the @[i|@ opening sequence and parses segments until @|]@.
-- Expression segments @#{expr}@ are parsed using the provided expression
-- parser, avoiding circular module dependencies with "Parse.Expression".
--
-- @since 0.19.2
interpolation ::
  Space.Parser SyntaxError.Expr Src.Expr ->
  Ann.Position ->
  Parser SyntaxError.Expr Src.Expr
interpolation exprParser start =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr eerr ->
    let !pos3 = plusPtr pos 3
     in if pos3 <= end
          && Parse.unsafeIndex pos == 0x5B {- [ -}
          && Parse.unsafeIndex (plusPtr pos 1) == 0x69 {- i -}
          && Parse.unsafeIndex (plusPtr pos 2) == 0x7C {- | -}
          then
            let !afterOpen = Parse.State src pos3 end indent row (col + 3)
                !(Parse.Parser segParser) = chompSegments exprParser []
             in segParser
                  afterOpen
                  ( \segments s ->
                      let !(Parse.State _ _ _ _ er ec) = s
                       in cok (Ann.at start (Ann.Position er ec) (Src.Interpolation segments)) s
                  )
                  ( \segments s ->
                      let !(Parse.State _ _ _ _ er ec) = s
                       in cok (Ann.at start (Ann.Position er ec) (Src.Interpolation segments)) s
                  )
                  cerr
                  cerr
          else eerr row col SyntaxError.Start

-- SEGMENTS

-- | Parse interpolation segments until @|]@ is reached.
--
-- Alternates between scanning literal text and parsing embedded
-- expressions. Accumulates segments in reverse order for efficiency.
--
-- @since 0.19.2
chompSegments ::
  Space.Parser SyntaxError.Expr Src.Expr ->
  [Src.InterpolationSegment] ->
  Parser SyntaxError.Expr [Src.InterpolationSegment]
chompSegments exprParser revSegments =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr _ ->
    case scanLiteral pos end row col pos [] of
      ScanInterp chunks newPos newRow newCol ->
        let !revSegs = addTextSegment chunks revSegments
            !afterBrace = Parse.State src newPos end indent newRow newCol
            !(Parse.Parser rest) = chompExprSegment exprParser revSegs
         in rest afterBrace cok cok cerr cerr
      ScanEnd chunks newPos newRow newCol ->
        let !revSegs = addTextSegment chunks revSegments
            !afterEnd = Parse.State src newPos end indent newRow newCol
         in cok (reverse revSegs) afterEnd
      ScanEndless endRow endCol ->
        cerr endRow endCol SyntaxError.EndlessInterpolation

-- | Parse an expression inside @#{...}@ and continue with more segments.
--
-- Skips leading whitespace, parses the expression, expects closing @}@,
-- then resumes segment scanning.
--
-- @since 0.19.2
chompExprSegment ::
  Space.Parser SyntaxError.Expr Src.Expr ->
  [Src.InterpolationSegment] ->
  Parser SyntaxError.Expr [Src.InterpolationSegment]
chompExprSegment exprParser revSegments =
  do
    Space.chomp SyntaxError.Space
    (expr, _) <- Parse.specialize SyntaxError.InterpolationExpr exprParser
    Parse.word1 0x7D {- } -} SyntaxError.InterpolationClose
    chompSegments exprParser (Src.IExpr expr : revSegments)

-- LITERAL SCANNING

-- | Result of scanning literal text within interpolation.
data ScanResult
  = -- | Found @#{@, returning chunks before it and position after @{@.
    ScanInterp ![ES.Chunk] !(Ptr Word8) !Row !Col
  | -- | Found @|]@, returning chunks before it and position after @]@.
    ScanEnd ![ES.Chunk] !(Ptr Word8) !Row !Col
  | -- | Reached end of input without finding @|]@.
    ScanEndless !Row !Col

-- | Scan literal text bytes until a break point is reached.
--
-- Accumulates text as 'ES.Chunk' slices for efficient string building.
-- Handles escape sequence @\\#@ which produces a literal @#@ character.
--
-- @since 0.19.2
scanLiteral ::
  Ptr Word8 ->
  Ptr Word8 ->
  Row ->
  Col ->
  Ptr Word8 ->
  [ES.Chunk] ->
  ScanResult
scanLiteral pos end row col sliceStart revChunks =
  if pos >= end
    then ScanEndless row col
    else
      let !word = Parse.unsafeIndex pos
       in if word == 0x23 {- # -}
            then scanHash pos end row col sliceStart revChunks
            else
              if word == 0x7C {- | -}
                then scanPipe pos end row col sliceStart revChunks
                else
                  if word == 0x5C {- \ -}
                    then scanBackslash pos end row col sliceStart revChunks
                    else
                      if word == 0x0A {- \n -}
                        then scanLiteral (plusPtr pos 1) end (row + 1) 1 sliceStart revChunks
                        else
                          let !newPos = plusPtr pos (Parse.getCharWidth word)
                           in scanLiteral newPos end row (col + 1) sliceStart revChunks

-- | Handle @#@ character during literal scanning.
--
-- If followed by @{@, this is an interpolation break.
-- Otherwise, the @#@ is literal text.
--
-- @since 0.19.2
scanHash ::
  Ptr Word8 ->
  Ptr Word8 ->
  Row ->
  Col ->
  Ptr Word8 ->
  [ES.Chunk] ->
  ScanResult
scanHash pos end row col sliceStart revChunks =
  let !pos1 = plusPtr pos 1
   in if pos1 < end && Parse.unsafeIndex pos1 == 0x7B {- { -}
        then
          let !chunks = addSlice sliceStart pos revChunks
           in ScanInterp chunks (plusPtr pos 2) row (col + 2)
        else scanLiteral pos1 end row (col + 1) sliceStart revChunks

-- | Handle @|@ character during literal scanning.
--
-- If followed by @]@, this is the end of interpolation.
-- Otherwise, the @|@ is literal text.
--
-- @since 0.19.2
scanPipe ::
  Ptr Word8 ->
  Ptr Word8 ->
  Row ->
  Col ->
  Ptr Word8 ->
  [ES.Chunk] ->
  ScanResult
scanPipe pos end row col sliceStart revChunks =
  let !pos1 = plusPtr pos 1
   in if pos1 < end && Parse.unsafeIndex pos1 == 0x5D {- ] -}
        then
          let !chunks = addSlice sliceStart pos revChunks
           in ScanEnd chunks (plusPtr pos 2) row (col + 2)
        else scanLiteral pos1 end row (col + 1) sliceStart revChunks

-- | Handle @\\@ character during literal scanning.
--
-- If followed by @#@, produces a literal @#@ (escape sequence).
-- Otherwise, the backslash is included as literal text.
--
-- @since 0.19.2
scanBackslash ::
  Ptr Word8 ->
  Ptr Word8 ->
  Row ->
  Col ->
  Ptr Word8 ->
  [ES.Chunk] ->
  ScanResult
scanBackslash pos end row col sliceStart revChunks =
  let !pos1 = plusPtr pos 1
   in if pos1 < end && Parse.unsafeIndex pos1 == 0x23 {- # -}
        then
          let !chunks = addSlice sliceStart pos revChunks
              !pos2 = plusPtr pos 2
              !newChunks = ES.Slice pos1 1 : chunks
           in scanLiteral pos2 end row (col + 2) pos2 newChunks
        else scanLiteral pos1 end row (col + 1) sliceStart revChunks

-- CHUNK HELPERS

-- | Add a byte slice to the chunk list if non-empty.
--
-- @since 0.19.2
addSlice :: Ptr Word8 -> Ptr Word8 -> [ES.Chunk] -> [ES.Chunk]
addSlice start end revChunks =
  let !len = minusPtr end start
   in if len > 0
        then ES.Slice start len : revChunks
        else revChunks

-- | Add a text segment from chunks to the segment list.
--
-- Only adds the segment if the chunks list is non-empty,
-- avoiding zero-length string literal segments.
--
-- @since 0.19.2
addTextSegment ::
  [ES.Chunk] ->
  [Src.InterpolationSegment] ->
  [Src.InterpolationSegment]
addTextSegment [] revSegments = revSegments
addTextSegment chunks revSegments =
  Src.IStr (ES.fromChunks (reverse chunks)) : revSegments

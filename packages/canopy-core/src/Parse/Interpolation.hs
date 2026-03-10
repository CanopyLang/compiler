{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE UnboxedTuples #-}

-- | Parse.Interpolation - Parser for template literal syntax
--
-- Parses backtick-delimited template literals with @${expr}@
-- interpolation points, following JavaScript ES6 template literal
-- conventions for familiarity with web developers.
--
-- Template literals desugar to @Basics.append@ chains during
-- canonicalization, producing zero-overhead native JavaScript @+@
-- concatenation when string literals are present.
--
-- ==== Syntax
--
-- @
-- \`Hello ${name}!\`                       -- simple interpolation
-- \`${greeting}, ${name}!\`                -- multiple interpolations
-- \`just a plain string\`                  -- no interpolation (literal)
-- \`cost is \\$100\`                       -- escaped dollar (literal $)
-- \`${String.fromInt count} items\`        -- expression interpolation
-- \`multi
--   line\`                                 -- multi-line support
-- @
--
-- ==== Desugaring
--
-- @\`Hello ${name}!\`@ desugars to @"Hello " ++ name ++ "!"@,
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

-- | Parse a backtick template literal expression.
--
-- Detects the opening backtick and parses segments until the closing
-- backtick. Expression segments @${expr}@ are parsed using the provided
-- expression parser, avoiding circular module dependencies with
-- "Parse.Expression".
--
-- @since 0.19.2
interpolation ::
  Space.Parser SyntaxError.Expr Src.Expr ->
  Ann.Position ->
  Parser SyntaxError.Expr Src.Expr
interpolation exprParser start =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr eerr ->
    if pos < end && Parse.unsafeIndex pos == 0x60 {- ` -}
      then
        let !afterOpen = Parse.State src (plusPtr pos 1) end indent row (col + 1)
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

-- | Parse interpolation segments until closing backtick is reached.
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

-- | Parse an expression inside @${...}@ and continue with more segments.
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

-- | Result of scanning literal text within a template literal.
data ScanResult
  = -- | Found @${@, returning chunks before it and position after @{@.
    ScanInterp ![ES.Chunk] !(Ptr Word8) !Row !Col
  | -- | Found closing backtick, returning chunks before it and position after.
    ScanEnd ![ES.Chunk] !(Ptr Word8) !Row !Col
  | -- | Reached end of input without finding closing backtick.
    ScanEndless !Row !Col

-- | Scan literal text bytes until a break point is reached.
--
-- Dispatches on the current byte to handle interpolation markers,
-- closing backticks, escape sequences, and newlines. Accumulates
-- text as 'ES.Chunk' slices for efficient string building.
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
scanLiteral pos end row col sliceStart revChunks
  | pos >= end = ScanEndless row col
  | otherwise = dispatchByte (Parse.unsafeIndex pos) pos end row col sliceStart revChunks

-- | Dispatch on the current byte to the appropriate handler.
--
-- @since 0.19.2
dispatchByte ::
  Word8 -> Ptr Word8 -> Ptr Word8 -> Row -> Col -> Ptr Word8 -> [ES.Chunk] -> ScanResult
dispatchByte 0x24 {- $ -} = scanDollar
dispatchByte 0x60 {- ` -} = scanClosingBacktick
dispatchByte 0x5C {- \ -} = scanBackslash
dispatchByte 0x0A {- \n -} = scanNewline
dispatchByte 0x0D {- \r -} = scanCarriageReturn
dispatchByte word = scanRegularChar word

-- | Handle @$@ — starts interpolation if followed by @{@, literal otherwise.
scanDollar :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> Ptr Word8 -> [ES.Chunk] -> ScanResult
scanDollar pos end row col sliceStart revChunks
  | Parse.isWord pos1 end 0x7B {- { -} =
      ScanInterp (addSlice sliceStart pos revChunks) (plusPtr pos 2) row (col + 2)
  | otherwise =
      scanLiteral pos1 end row (col + 1) sliceStart revChunks
  where
    !pos1 = plusPtr pos 1

-- | Handle closing backtick — ends the template literal.
scanClosingBacktick :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> Ptr Word8 -> [ES.Chunk] -> ScanResult
scanClosingBacktick pos _end row col sliceStart revChunks =
  ScanEnd (addSlice sliceStart pos revChunks) (plusPtr pos 1) row (col + 1)

-- | Handle @\\@ — resolves escape sequences via 'resolveEscape'.
scanBackslash :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> Ptr Word8 -> [ES.Chunk] -> ScanResult
scanBackslash pos end row col sliceStart revChunks
  | pos1 >= end = ScanEndless row col
  | otherwise =
      case resolveEscape (Parse.unsafeIndex pos1) of
        EscapeLiteral ->
          let !chunks = addSlice sliceStart pos revChunks
           in scanLiteral pos2 end row (col + 2) pos2 (ES.Slice pos1 1 : chunks)
        EscapeCode code ->
          let !chunks = addSlice sliceStart pos revChunks
           in scanLiteral pos2 end row (col + 2) pos2 (ES.Escape code : chunks)
        EscapeIgnore ->
          scanLiteral pos1 end row (col + 1) sliceStart revChunks
  where
    !pos1 = plusPtr pos 1
    !pos2 = plusPtr pos 2

-- | Classify an escape sequence following a backslash.
data EscapeResult
  = EscapeLiteral
  | EscapeCode !Word8
  | EscapeIgnore

-- | Resolve the byte after @\\@ into an escape action.
--
-- @\\$@, @\\`@, @\\\\@ produce the literal character.
-- @\\n@, @\\t@ produce the corresponding control code.
-- Anything else ignores the backslash (pass-through).
resolveEscape :: Word8 -> EscapeResult
resolveEscape 0x24 {- $ -} = EscapeLiteral
resolveEscape 0x60 {- ` -} = EscapeLiteral
resolveEscape 0x5C {- \ -} = EscapeLiteral
resolveEscape 0x6E {- n -} = EscapeCode 0x6E
resolveEscape 0x74 {- t -} = EscapeCode 0x74
resolveEscape _ = EscapeIgnore

-- | Handle newline — emits escape chunk and advances row.
scanNewline :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> Ptr Word8 -> [ES.Chunk] -> ScanResult
scanNewline pos end row _col sliceStart revChunks =
  let !chunks = addSlice sliceStart pos revChunks
   in scanLiteral (plusPtr pos 1) end (row + 1) 1 (plusPtr pos 1) (ES.Escape 0x6E : chunks)

-- | Handle carriage return — skip without emitting.
scanCarriageReturn :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> Ptr Word8 -> [ES.Chunk] -> ScanResult
scanCarriageReturn pos end row col sliceStart revChunks =
  scanLiteral (plusPtr pos 1) end row col (plusPtr pos 1) (addSlice sliceStart pos revChunks)

-- | Handle a regular character — advance by its UTF-8 width.
scanRegularChar :: Word8 -> Ptr Word8 -> Ptr Word8 -> Row -> Col -> Ptr Word8 -> [ES.Chunk] -> ScanResult
scanRegularChar word pos end row col sliceStart revChunks =
  scanLiteral (plusPtr pos (Parse.getCharWidth word)) end row (col + 1) sliceStart revChunks

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

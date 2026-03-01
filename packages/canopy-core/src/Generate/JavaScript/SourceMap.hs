{-# LANGUAGE OverloadedStrings #-}

-- | Source Map V3 generation for the Canopy compiler.
--
-- Implements the Source Map V3 specification
-- (<https://sourcemaps.info/spec.html>) to map generated JavaScript
-- back to original @.can@ source files with line and column precision.
--
-- The encoding uses Base64 Variable-Length Quantity (VLQ) encoding for
-- compact representation of source positions. Each mapping segment
-- encodes up to 5 fields as relative deltas from the previous segment,
-- following the standard VLQ encoding scheme where the sign bit is
-- stored in the least significant bit and continuation bits in the MSB
-- of each 6-bit group.
--
-- == Usage
--
-- @
-- let sm = SourceMap.empty "output.js"
--       & SourceMap.addMapping (Mapping 0 0 0 0 0 Nothing)
--       & SourceMap.addMapping (Mapping 5 0 0 4 0 Nothing)
-- let json = SourceMap.toBuilder sm
-- @
--
-- @since 0.19.2
module Generate.JavaScript.SourceMap
  ( -- * Types
    SourceMap (..)
  , Mapping (..)

    -- * Construction
  , empty
  , addMapping
  , addSource

    -- * Serialization
  , toBuilder

    -- * VLQ Encoding (exported for testing)
  , encodeVLQ
  ) where

import Data.Bits ((.&.), (.|.), shiftL, shiftR)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import Data.Vector (Vector)
import Data.Word (Word8)

-- | Source Map V3 representation.
--
-- Holds all the data needed to produce a compliant Source Map V3 JSON
-- document: the output file name, the list of original source files,
-- optional inline source content, and the collected mappings.
--
-- @since 0.19.2
data SourceMap = SourceMap
  { _smFile :: !FilePath
  , _smSources :: ![FilePath]
  , _smSourcesContent :: ![Text.Text]
  , _smNames :: ![Text.Text]
  , _smMappings :: ![Mapping]
  } deriving (Show)

-- | A single source-map mapping entry.
--
-- Maps a generated position (line + column) to an original source
-- position (source index + line + column), with an optional name
-- index for symbol attribution.
--
-- All line and column numbers are __0-based__, matching the Source Map
-- V3 specification.
--
-- @since 0.19.2
data Mapping = Mapping
  { _mGenLine :: !Int
  , _mGenCol :: !Int
  , _mSrcIndex :: !Int
  , _mSrcLine :: !Int
  , _mSrcCol :: !Int
  , _mNameIndex :: !(Maybe Int)
  } deriving (Show, Eq)

-- | Create an empty source map for the given output file.
--
-- @since 0.19.2
empty :: FilePath -> SourceMap
empty outputFile =
  SourceMap outputFile [] [] [] []

-- | Append a mapping entry to the source map.
--
-- Mappings are accumulated in reverse order for efficient prepend
-- and reversed during serialization.
--
-- @since 0.19.2
addMapping :: Mapping -> SourceMap -> SourceMap
addMapping m sm =
  sm { _smMappings = m : _smMappings sm }

-- | Register a source file, returning its index and the updated map.
--
-- If the source path is already registered, the existing index is
-- returned without duplicating the entry.
--
-- @since 0.19.2
addSource :: FilePath -> Maybe Text.Text -> SourceMap -> (Int, SourceMap)
addSource path maybeContent sm =
  case List.elemIndex path (_smSources sm) of
    Just idx -> (idx, sm)
    Nothing ->
      let idx = length (_smSources sm)
          content = maybe Text.empty id maybeContent
       in ( idx
          , sm { _smSources = _smSources sm ++ [path]
               , _smSourcesContent = _smSourcesContent sm ++ [content]
               }
          )

-- | Serialize the source map to a JSON 'Builder'.
--
-- Produces a complete Source Map V3 JSON document. The @mappings@
-- field uses VLQ-encoded segments with semicolons separating
-- generated lines and commas separating segments within a line.
--
-- @since 0.19.2
toBuilder :: SourceMap -> Builder
toBuilder sm =
  BB.stringUtf8 "{\"version\":3,\"file\":"
    <> jsonString (_smFile sm)
    <> BB.stringUtf8 ",\"sources\":"
    <> jsonStringArray (_smSources sm)
    <> BB.stringUtf8 ",\"sourcesContent\":"
    <> jsonTextArray (_smSourcesContent sm)
    <> BB.stringUtf8 ",\"names\":"
    <> jsonTextArray (_smNames sm)
    <> BB.stringUtf8 ",\"mappings\":\""
    <> encodeMappings (List.sortOn _mGenLine (reverse (_smMappings sm)))
    <> BB.stringUtf8 "\"}"

-- MAPPINGS ENCODING

-- | Encode all mappings into the VLQ mappings string.
--
-- Groups mappings by generated line, separates lines with @;@
-- and segments within a line with @,@. Each segment's fields
-- are encoded as deltas from the previous segment.
encodeMappings :: [Mapping] -> Builder
encodeMappings mappings =
  go 0 initialState mappings
  where
    initialState = VLQState 0 0 0 0 0
    go _currentLine _st [] = mempty
    go currentLine st ms =
      let (lineMs, rest) = span (\m -> _mGenLine m == currentLine) ms
       in encodeOneLine currentLine st lineMs rest

-- | Encode mappings for one generated line and continue.
encodeOneLine :: Int -> VLQState -> [Mapping] -> [Mapping] -> Builder
encodeOneLine currentLine st lineMs rest =
  case lineMs of
    [] ->
      BB.char7 ';' <> encodeMappingsFrom (currentLine + 1) st rest
    _ ->
      let prefix = if currentLine > 0 then BB.char7 ';' else mempty
          (segBuilder, st') = encodeLineSegments st lineMs
       in prefix <> segBuilder <> encodeMappingsFrom (currentLine + 1) st' rest

-- | Continue encoding from a specific line number.
encodeMappingsFrom :: Int -> VLQState -> [Mapping] -> Builder
encodeMappingsFrom _currentLine _st [] = mempty
encodeMappingsFrom currentLine st ms =
  let (lineMs, rest) = span (\m -> _mGenLine m == currentLine) ms
   in encodeOneLine currentLine st lineMs rest

-- | Accumulator for relative VLQ encoding state.
--
-- Source Map V3 encodes each field as a delta from the previous
-- segment's value, so we carry the running totals.
data VLQState = VLQState
  { _prevGenCol :: !Int
  , _prevSrcIndex :: !Int
  , _prevSrcLine :: !Int
  , _prevSrcCol :: !Int
  , _prevNameIndex :: !Int
  }

-- | Encode all segments for a single generated line.
encodeLineSegments :: VLQState -> [Mapping] -> (Builder, VLQState)
encodeLineSegments st [] = (mempty, st)
encodeLineSegments st [m] = encodeSegment st m
encodeLineSegments st (m : ms) =
  let (seg, st') = encodeSegment st m
      (rest, st'') = encodeLineSegments st' ms
   in (seg <> BB.char7 ',' <> rest, st'')

-- | Encode a single segment as relative VLQ fields.
--
-- Each segment has 4 mandatory fields (genCol, srcIndex, srcLine,
-- srcCol) plus an optional 5th field (nameIndex). All values are
-- encoded relative to the previous segment's corresponding value.
encodeSegment :: VLQState -> Mapping -> (Builder, VLQState)
encodeSegment st m =
  let genColDelta = _mGenCol m - _prevGenCol st
      srcIdxDelta = _mSrcIndex m - _prevSrcIndex st
      srcLineDelta = _mSrcLine m - _prevSrcLine st
      srcColDelta = _mSrcCol m - _prevSrcCol st
      base =
        encodeVLQ genColDelta
          <> encodeVLQ srcIdxDelta
          <> encodeVLQ srcLineDelta
          <> encodeVLQ srcColDelta
   in encodeSegmentName st m base

-- | Encode optional name index and build final state.
encodeSegmentName :: VLQState -> Mapping -> Builder -> (Builder, VLQState)
encodeSegmentName st m base =
  let (nameBuilder, newNameIdx) = case _mNameIndex m of
        Nothing -> (mempty, _prevNameIndex st)
        Just ni ->
          (encodeVLQ (ni - _prevNameIndex st), ni)
      st' = VLQState
        { _prevGenCol = _mGenCol m
        , _prevSrcIndex = _mSrcIndex m
        , _prevSrcLine = _mSrcLine m
        , _prevSrcCol = _mSrcCol m
        , _prevNameIndex = newNameIdx
        }
   in (base <> nameBuilder, st')

-- VLQ ENCODING

-- | Base64 VLQ encoding of a signed integer.
--
-- Encodes a signed integer using the VLQ scheme defined by the
-- Source Map V3 specification:
--
--   1. The sign is stored in the LSB of the first 6-bit group
--      (0 = positive, 1 = negative).
--   2. The magnitude is shifted left by 1 bit.
--   3. Each 6-bit group is emitted with a continuation bit in the
--      MSB (bit 5): 1 means more groups follow, 0 means last group.
--   4. Each 6-bit value is mapped to a Base64 character.
--
-- ==== Examples
--
-- >>> toLazyByteString (encodeVLQ 0)
-- "A"
--
-- >>> toLazyByteString (encodeVLQ 1)
-- "C"
--
-- >>> toLazyByteString (encodeVLQ (-1))
-- "D"
--
-- >>> toLazyByteString (encodeVLQ 16)
-- "gB"
--
-- @since 0.19.2
encodeVLQ :: Int -> Builder
encodeVLQ n =
  emitVLQGroups vlqValue
  where
    vlqValue
      | n >= 0    = n `shiftL` 1
      | otherwise = (negate n `shiftL` 1) + 1

-- | Emit 6-bit VLQ groups with continuation bits.
emitVLQGroups :: Int -> Builder
emitVLQGroups value
  | remaining == 0 = encodeBase64Digit (value .&. 0x1F)
  | otherwise =
      encodeBase64Digit ((value .&. 0x1F) .|. 0x20)
        <> emitVLQGroups remaining
  where
    remaining = value `shiftR` 5

-- | Map a 6-bit value (0--63) to its Base64 character.
--
-- Uses 'Vector' indexing for bounds safety. The index is guaranteed
-- to be in range by the VLQ encoding (masked to 6 bits), but safe
-- indexing prevents undefined behavior if the invariant is violated.
encodeBase64Digit :: Int -> Builder
encodeBase64Digit n =
  BB.word8 (base64Alphabet Vector.! n)

-- | The Base64 encoding alphabet used by VLQ.
base64Alphabet :: Vector Word8
base64Alphabet =
  Vector.fromList $ map (fromIntegral . fromEnum)
    ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" :: String)

-- JSON HELPERS

-- | Encode a string as a JSON string with proper escaping.
jsonString :: String -> Builder
jsonString s =
  BB.char7 '"' <> foldMap escapeJsonChar s <> BB.char7 '"'

-- | Escape a single character for JSON string encoding.
escapeJsonChar :: Char -> Builder
escapeJsonChar '"' = BB.stringUtf8 "\\\""
escapeJsonChar '\\' = BB.stringUtf8 "\\\\"
escapeJsonChar '\n' = BB.stringUtf8 "\\n"
escapeJsonChar '\r' = BB.stringUtf8 "\\r"
escapeJsonChar '\t' = BB.stringUtf8 "\\t"
escapeJsonChar c = BB.charUtf8 c

-- | Encode a list of strings as a JSON string array.
jsonStringArray :: [String] -> Builder
jsonStringArray xs =
  BB.char7 '['
    <> mconcat (List.intersperse (BB.char7 ',') (map jsonString xs))
    <> BB.char7 ']'

-- | Encode a list of Text values as a JSON string array.
jsonTextArray :: [Text.Text] -> Builder
jsonTextArray xs =
  BB.char7 '['
    <> mconcat (List.intersperse (BB.char7 ',') (map jsonText xs))
    <> BB.char7 ']'

-- | Encode a Text value as a JSON string.
jsonText :: Text.Text -> Builder
jsonText t =
  BB.char7 '"' <> foldMap escapeJsonChar (Text.unpack t) <> BB.char7 '"'

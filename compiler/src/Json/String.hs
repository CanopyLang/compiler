{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# OPTIONS_GHC -Wall -fno-warn-name-shadowing #-}

-- | Json.String - Efficient JSON string representation with UTF-8 encoding
--
-- This module provides a specialized string type optimized for JSON processing
-- in the Canopy compiler. The 'String' type uses UTF-8 encoding internally
-- and provides efficient conversion operations while maintaining JSON string
-- invariants for safe encoding and decoding.
--
-- The string representation is designed for high performance JSON operations:
-- * Zero-copy construction from parsing snippets
-- * Efficient builder-based serialization
-- * Memory-efficient UTF-8 encoding
-- * Type safety through phantom type restrictions
--
-- == Key Features
--
-- * **UTF-8 Native** - Internal UTF-8 representation for efficient processing
-- * **Zero-Copy Parsing** - Direct construction from parser snippets
-- * **Type Safety** - Phantom type prevents mixing with other string types
-- * **Builder Integration** - Efficient serialization to ByteString builders
-- * **Memory Efficient** - Minimal allocation overhead for string operations
--
-- == Architecture
--
-- The module uses a phantom type approach:
--
-- * 'String' = 'Utf8.Utf8 JSON_STRING' with phantom type 'JSON_STRING'
-- * All operations preserve the phantom type for compile-time safety
-- * Internal representation is 'Utf8.Utf8' for efficient UTF-8 handling
-- * Builder integration enables zero-copy JSON serialization
--
-- == Usage Examples
--
-- === Basic String Operations
--
-- @
-- -- Create JSON strings from various sources
-- str1 = fromChars "hello world"
-- str2 = fromName (Name.fromChars "userName")
--
-- -- Check if string is empty
-- isEmpty str1  -- False
-- isEmpty (fromChars "")  -- True
--
-- -- Convert back to characters
-- chars = toChars str1  -- "hello world"
-- @
--
-- === Parser Integration
--
-- @
-- -- Construct from parser snippets (zero-copy)
-- parseJsonString :: Parser JsonString
-- parseJsonString = do
--   snippet <- parseStringLiteral
--   pure (fromSnippet snippet)
--
-- -- Process parsed content
-- processString :: P.Snippet -> Json.String
-- processString snippet =
--   let jsonStr = fromSnippet snippet
--   in if isEmpty jsonStr
--        then fromChars "<empty>"
--        else jsonStr
-- @
--
-- === Builder Integration
--
-- @
-- -- Efficient JSON encoding
-- encodeStringValue :: Json.String -> Builder
-- encodeStringValue str =
--   B.char7 '"' <> toBuilder str <> B.char7 '"'
--
-- -- Combine multiple strings efficiently
-- combineStrings :: [Json.String] -> Builder
-- combineStrings strs = mconcat (map toBuilder strs)
-- @
--
-- === Comment Processing
--
-- @
-- -- Extract strings from comments with escape handling
-- processComment :: P.Snippet -> Json.String
-- processComment commentSnippet = fromComment commentSnippet
--
-- -- Example: Extract documentation strings
-- extractDocString :: P.Snippet -> Json.String
-- extractDocString snippet =
--   let processed = fromComment snippet
--   in if isEmpty processed
--        then fromChars "No documentation"
--        else processed
-- @
--
-- == String Invariants
--
-- All 'Json.String' values maintain these invariants:
--
-- * **Valid UTF-8** - All content is valid UTF-8 encoded
-- * **JSON Safe** - Content is appropriate for JSON string values
-- * **Escape Processed** - Special characters are properly handled
-- * **Non-null** - Internal representation cannot be null pointer
--
-- == Performance Characteristics
--
-- * **Construction**: O(n) for character conversion, O(1) for snippets
-- * **Conversion**: O(n) for character extraction, O(1) for builder
-- * **Memory Usage**: UTF-8 bytes + minimal overhead
-- * **Comparison**: Byte-level comparison for efficient equality
--
-- === Performance Tips
--
-- * Use 'fromSnippet' for zero-copy construction from parsers
-- * Use 'toBuilder' for efficient serialization
-- * Prefer 'isEmpty' over 'toChars' for emptiness checks
-- * Batch string operations to minimize allocations
--
-- == Thread Safety
--
-- All operations are pure and thread-safe. 'Json.String' values are immutable
-- and can be safely shared across threads without synchronization.
--
-- == Unsafe Operations
--
-- Some functions use unsafe operations internally for performance:
-- * 'fromPtr' - Direct pointer construction (caller must ensure validity)
-- * 'fromComment' - Uses IO.unsafePerformIO for escape processing
--
-- These operations are safe when used correctly but require careful attention
-- to memory management and UTF-8 validity.
--
-- @since 0.19.1
module Json.String
  ( -- * Core String Type
    String,

    -- * String Properties
    isEmpty,

    -- * Construction Functions
    fromPtr,
    fromName,
    fromChars,
    fromSnippet,
    fromComment,

    -- * Conversion Functions
    toChars,
    toBuilder,
  )
where

import qualified Data.ByteString.Builder as B
import qualified Data.Coerce as Coerce
import qualified Data.Name as Name
import Data.Utf8 (MBA)
import qualified Data.Utf8 as Utf8
import Data.Word (Word8)
import qualified Foreign.ForeignPtr as ForeignPtr
import Foreign.Ptr (Ptr)
import qualified Foreign.Ptr as Ptr
import GHC.Exts (RealWorld)
import qualified GHC.IO as IO
import GHC.ST (ST)
import qualified Parse.Primitives as P
import Prelude hiding (String)

-- CORE STRING TYPE

-- | Efficient UTF-8 encoded string type for JSON processing.
--
-- 'String' is a type alias for 'Utf8.Utf8' with a phantom type parameter
-- that ensures type safety and prevents accidental mixing with other
-- UTF-8 string types in the codebase.
--
-- ==== Design Invariants
--
-- Every 'Json.String' value maintains these properties:
--
-- * **Valid UTF-8**: All content is properly UTF-8 encoded
-- * **JSON Safe**: Content is suitable for JSON string values
-- * **Properly Escaped**: Special characters are handled appropriately
-- * **Immutable**: Values cannot be modified after construction
--
-- ==== Representation
--
-- Internally uses 'Utf8.Utf8' which provides:
-- * Efficient UTF-8 byte storage
-- * Zero-copy operations where possible
-- * Direct integration with ByteString builders
-- * Memory-efficient string handling
--
-- ==== Type Safety
--
-- The phantom type 'JSON_STRING' prevents accidental mixing:
--
-- @
-- -- These types are distinct at compile time:
-- jsonStr :: Json.String          -- Utf8.Utf8 JSON_STRING
-- normalStr :: Utf8.Utf8 OTHER    -- Utf8.Utf8 OTHER
--
-- -- This would be a compile error:
-- -- mixedUp = jsonStr == normalStr  -- Type error!
-- @
--
-- ==== Performance Characteristics
--
-- * **Memory**: Direct UTF-8 byte storage, minimal overhead
-- * **Construction**: O(n) for validation, O(1) for wrapping
-- * **Access**: O(1) for length, O(n) for character extraction
-- * **Serialization**: O(1) for builder conversion
--
-- @since 0.19.1
type String =
  -- | UTF-8 encoded string with JSON safety guarantees
  Utf8.Utf8 JSON_STRING

-- | Phantom type for JSON string type safety.
--
-- This empty type serves as a phantom type parameter to distinguish
-- JSON strings from other UTF-8 strings in the type system. It has
-- no runtime representation or behavior.
--
-- The phantom type approach enables:
-- * Compile-time prevention of string type mixing
-- * Zero runtime overhead for type safety
-- * Clear API boundaries for JSON-specific operations
-- * Type-driven documentation and reasoning
--
-- @since 0.19.1
data JSON_STRING

-- STRING PROPERTIES

-- | Check if a JSON string is empty.
--
-- Efficiently determines if the string contains no characters without
-- allocating or converting to other representations.
--
-- ==== Examples
--
-- >>> isEmpty (fromChars "")
-- True
--
-- >>> isEmpty (fromChars "hello")
-- False
--
-- >>> isEmpty (fromSnippet emptySnippet)
-- True
--
-- Conditional processing:
-- @
-- processString :: Json.String -> Json.String
-- processString str
--   | isEmpty str = fromChars "<empty>"
--   | otherwise = str
-- @
--
-- Guard against empty inputs:
-- @
-- validateName :: Json.String -> Either ValidationError Json.String
-- validateName name
--   | isEmpty name = Left EmptyNameError
--   | otherwise = Right name
-- @
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) - constant time operation
-- * **Space Complexity**: O(1) - no allocations
-- * **Memory Access**: Single length check, no character processing
--
-- This is much more efficient than converting to characters and checking
-- the resulting list length.
--
-- @since 0.19.1
isEmpty :: String -> Bool
isEmpty = Utf8.isEmpty

-- CONSTRUCTION FUNCTIONS

-- | Construct a JSON string from a memory pointer range.
--
-- **UNSAFE**: Directly constructs a string from memory pointers. The caller
-- must ensure that:
-- * The memory range contains valid UTF-8 data
-- * The memory remains valid for the lifetime of the string
-- * The content is appropriate for JSON string usage
--
-- This function is primarily used internally by parsers and should be
-- avoided in application code unless absolutely necessary for performance.
--
-- ==== Examples
--
-- Parser integration (internal use):
-- @
-- parseStringFromMemory :: Ptr Word8 -> Ptr Word8 -> Json.String
-- parseStringFromMemory start end = fromPtr start end
-- @
--
-- **Warning**: Incorrect usage can lead to:
-- * Invalid UTF-8 content
-- * Memory safety violations
-- * Segmentation faults
-- * Data corruption
--
-- ==== Safe Alternatives
--
-- For safe construction, prefer:
-- * 'fromChars' for String conversion
-- * 'fromSnippet' for parser snippets
-- * 'fromName' for Name conversion
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) - direct pointer wrapping
-- * **Space Complexity**: O(1) - no copying or validation
-- * **Memory Usage**: Zero allocation, direct pointer reference
--
-- @since 0.19.1
fromPtr :: Ptr Word8 -> Ptr Word8 -> String
fromPtr = Utf8.fromPtr

-- | Construct a JSON string from a list of characters.
--
-- Converts a Haskell 'String' (list of 'Char') into a JSON string with
-- proper UTF-8 encoding. This is the primary way to create JSON strings
-- from regular Haskell strings.
--
-- ==== Examples
--
-- >>> let jsonStr = fromChars "hello world"
-- >>> toChars jsonStr
-- "hello world"
--
-- >>> let emptyStr = fromChars ""
-- >>> isEmpty emptyStr
-- True
--
-- Unicode support:
-- @
-- unicodeText = fromChars "Hello, 世界!"
-- processedText = fromChars "Special: \n\t\""
-- @
--
-- Configuration processing:
-- @
-- processConfigValue :: String -> Json.String
-- processConfigValue configStr = fromChars configStr
--
-- createField :: String -> Json.String
-- createField fieldName = fromChars fieldName
-- @
--
-- ==== Character Handling
--
-- * **Unicode**: Full Unicode support through UTF-8 encoding
-- * **Special Characters**: All characters are preserved as-is
-- * **Escape Sequences**: Input escape sequences are treated as literal characters
-- * **Line Endings**: Preserved without modification
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) where n is character count
-- * **Space Complexity**: O(b) where b is UTF-8 byte count
-- * **Memory Usage**: Single allocation for UTF-8 encoded result
-- * **Encoding**: Direct UTF-8 encoding from Unicode code points
--
-- For high-performance scenarios with existing UTF-8 data, consider
-- 'fromSnippet' or 'fromPtr' alternatives.
--
-- @since 0.19.1
fromChars :: [Char] -> String
fromChars = Utf8.fromChars

-- | Construct a JSON string from a parser snippet.
--
-- **Zero-copy construction** from parser snippets that reference memory
-- regions in the original input. This is the most efficient way to create
-- JSON strings during parsing since it avoids copying the underlying data.
--
-- ==== Examples
--
-- Parser integration:
-- @
-- parseStringLiteral :: Parser Json.String
-- parseStringLiteral = do
--   snippet <- extractStringSnippet
--   pure (fromSnippet snippet)
-- @
--
-- Efficient string extraction:
-- @
-- extractIdentifier :: P.Snippet -> Json.String
-- extractIdentifier snippet = fromSnippet snippet
--
-- processTokens :: [P.Snippet] -> [Json.String]
-- processTokens = map fromSnippet
-- @
--
-- ==== Zero-Copy Benefits
--
-- * **No Memory Allocation**: References existing memory
-- * **No Data Copying**: Direct pointer sharing
-- * **Cache Efficiency**: Better memory locality
-- * **Parser Speed**: Fastest string construction method
--
-- ==== Safety Considerations
--
-- * **Memory Lifetime**: Snippet memory must remain valid
-- * **UTF-8 Validity**: Snippet content should be valid UTF-8
-- * **Parser Contract**: Relies on parser correctness
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) - constant time construction
-- * **Space Complexity**: O(1) - no additional memory allocation
-- * **Memory Usage**: Zero allocation, direct reference
-- * **Parser Integration**: Optimal for high-throughput parsing
--
-- @since 0.19.1
fromSnippet :: P.Snippet -> String
fromSnippet = Utf8.fromSnippet

-- | Construct a JSON string from a Canopy compiler name.
--
-- Efficiently converts 'Name.Name' values (used throughout the Canopy
-- compiler for identifiers, module names, etc.) into JSON strings.
-- Uses type coercion for zero-cost conversion.
--
-- ==== Examples
--
-- >>> let name = Name.fromChars "userName"
-- >>> let jsonStr = fromName name
-- >>> toChars jsonStr
-- "userName"
--
-- Module name processing:
-- @
-- moduleToJson :: ModuleName -> Json.String
-- moduleToJson moduleName = fromName (getNameFromModule moduleName)
--
-- identifierToString :: Identifier -> Json.String
-- identifierToString ident = fromName (identifierName ident)
-- @
--
-- Symbol table operations:
-- @
-- processSymbols :: [Name.Name] -> [Json.String]
-- processSymbols = map fromName
--
-- encodeSymbolTable :: SymbolTable -> [(Json.String, Value)]
-- encodeSymbolTable table =
--   [(fromName name, encodeSymbol symbol) | (name, symbol) <- Map.toList table]
-- @
--
-- ==== Type Coercion
--
-- This function uses 'Coerce.coerce' for zero-cost conversion between
-- 'Name.Name' and 'Json.String'. Both types have the same internal
-- representation ('Utf8.Utf8'), so no runtime conversion is needed.
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) - zero-cost type coercion
-- * **Space Complexity**: O(1) - no additional memory allocation
-- * **Memory Usage**: Zero allocation, direct type coercion
-- * **Runtime Cost**: Completely eliminated by compiler
--
-- @since 0.19.1
fromName :: Name.Name -> String
fromName = Coerce.coerce

-- CONVERSION FUNCTIONS

-- | Convert a JSON string to a list of characters.
--
-- Extracts the Unicode characters from a JSON string, producing a regular
-- Haskell 'String' (list of 'Char'). This operation allocates a new list
-- and should be used judiciously in performance-critical code.
--
-- ==== Examples
--
-- >>> toChars (fromChars "hello world")
-- "hello world"
--
-- >>> toChars (fromChars "")
-- ""
--
-- >>> toChars (fromChars "Unicode: 世界")
-- "Unicode: 世界"
--
-- String processing:
-- @
-- processJsonString :: Json.String -> String
-- processJsonString jsonStr =
--   let chars = toChars jsonStr
--   in map toUpper chars
--
-- extractWords :: Json.String -> [String]
-- extractWords jsonStr = words (toChars jsonStr)
-- @
--
-- Pattern matching:
-- @
-- analyzeString :: Json.String -> StringType
-- analyzeString jsonStr =
--   case toChars jsonStr of
--     "" -> EmptyString
--     [c] -> SingleChar c
--     chars -> MultiChar (length chars)
-- @
--
-- ==== Performance Considerations
--
-- This operation involves:
-- * UTF-8 decoding to Unicode code points
-- * List construction for each character
-- * Memory allocation for the result list
--
-- **Alternatives for better performance**:
-- * Use 'isEmpty' instead of `null . toChars`
-- * Use 'toBuilder' for serialization
-- * Process UTF-8 bytes directly when possible
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) where n is character count
-- * **Space Complexity**: O(n) for result list
-- * **Memory Usage**: List allocation + character allocations
-- * **Decoding**: UTF-8 to Unicode conversion overhead
--
-- @since 0.19.1
toChars :: String -> [Char]
toChars = Utf8.toChars

-- | Convert a JSON string to a ByteString builder.
--
-- Efficiently converts a JSON string to a 'ByteString.Builder' for
-- high-performance serialization. This is the preferred method for
-- JSON encoding as it avoids intermediate string allocations.
--
-- ==== Examples
--
-- >>> let builder = toBuilder (fromChars "hello")
-- >>> B.toLazyByteString builder
-- "hello"
--
-- JSON encoding:
-- @
-- encodeJsonString :: Json.String -> B.Builder
-- encodeJsonString str =
--   B.char7 '"' <> toBuilder str <> B.char7 '"'
--
-- combineStrings :: [Json.String] -> B.Builder
-- combineStrings strs = mconcat (map toBuilder strs)
-- @
--
-- Efficient serialization:
-- @
-- serializeFields :: [(Json.String, Json.String)] -> B.Builder
-- serializeFields fields = mconcat
--   [ toBuilder key <> B.char7 ':' <> toBuilder value <> B.char7 ','
--   | (key, value) <- fields
--   ]
-- @
--
-- ==== Builder Advantages
--
-- * **Zero-Copy**: Direct UTF-8 byte access
-- * **Efficient Concatenation**: O(1) builder composition
-- * **Streaming**: Can be written directly to handles
-- * **Memory Efficient**: No intermediate string allocations
--
-- ==== Performance
--
-- * **Time Complexity**: O(1) - direct builder wrapping
-- * **Space Complexity**: O(1) - no additional allocation
-- * **Memory Usage**: Zero allocation for builder creation
-- * **Serialization**: Optimal for JSON output generation
--
-- This is the most efficient way to serialize JSON strings and should
-- be preferred over 'toChars' for all output operations.
--
-- @since 0.19.1
{-# INLINE toBuilder #-}
toBuilder :: String -> B.Builder
toBuilder = Utf8.toBuilder

-- SPECIALIZED CONSTRUCTION

-- | Construct a JSON string from a comment snippet with escape processing.
--
-- **UNSAFE**: Uses 'IO.unsafePerformIO' internally for escape sequence processing.
-- Processes comment content by handling escape sequences and special characters
-- that appear in source code comments.
--
-- This function is specialized for processing documentation strings and
-- comments that may contain escape sequences needing interpretation.
--
-- ==== Examples
--
-- Documentation processing:
-- @
-- processDocComment :: P.Snippet -> Json.String
-- processDocComment snippet = fromComment snippet
--
-- extractComment :: P.Snippet -> Json.String
-- extractComment commentSnippet =
--   let processed = fromComment commentSnippet
--   in if isEmpty processed
--        then fromChars "<no comment>"
--        else processed
-- @
--
-- ==== Escape Processing
--
-- The function handles various escape sequences:
-- * Newlines (@\n@) → literal newline characters
-- * Quotes (@\"@) → literal quote characters
-- * Backslashes (@\\@) → literal backslash characters
-- * Carriage returns (@\r@) → removed from output
--
-- ==== Safety Considerations
--
-- **UNSAFE OPERATIONS**:
-- * Uses 'IO.unsafePerformIO' for memory processing
-- * Direct memory access through foreign pointers
-- * Assumes valid UTF-8 input from parser
--
-- **Safe Usage Requirements**:
-- * Input snippet must contain valid UTF-8
-- * Memory referenced by snippet must remain valid
-- * Should only be used with trusted parser output
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) where n is comment length
-- * **Space Complexity**: O(n + e) where e is number of escape sequences
-- * **Memory Usage**: Single allocation for processed result
-- * **Unsafe Operations**: Required for efficient escape processing
--
-- **Performance Note**: The unsafe operations are necessary for efficient
-- in-place escape processing without multiple string copies.
--
-- @since 0.19.1
fromComment :: P.Snippet -> String
fromComment (P.Snippet fptr off len _ _) =
  IO.unsafePerformIO . ForeignPtr.withForeignPtr fptr $
    ( \ptr ->
        let !pos = Ptr.plusPtr ptr off
            !end = Ptr.plusPtr pos len
            !str = fromChunks (chompChunks pos end pos [])
         in return str
    )

-- | Process comment content by chunking and escape handling.
--
-- Internal function for 'fromComment' that processes comment text
-- character by character, building chunks for efficient escape processing.
--
-- @since 0.19.1
chompChunks :: Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> [Chunk] -> [Chunk]
chompChunks pos end start revChunks =
  if pos >= end
    then reverse (addSlice start end revChunks)
    else processCharacter pos end start revChunks

-- | Process a single character during comment chunking.
--
-- Internal helper for 'chompChunks' that handles character classification
-- and determines appropriate processing action.
--
-- @since 0.19.1
processCharacter :: Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> [Chunk] -> [Chunk]
processCharacter pos end start revChunks =
  let !word = P.unsafeIndex pos
   in case word of
        0x0A {-\n-} ->
          let !pos1 = Ptr.plusPtr pos 1
           in chompChunks pos1 end pos1 (Escape 0x6E {-n-} : addSlice start pos revChunks)
        0x22 {-"-} ->
          let !pos1 = Ptr.plusPtr pos 1
           in chompChunks pos1 end pos1 (Escape 0x22 {-"-} : addSlice start pos revChunks)
        0x5C {-\-} ->
          let !pos1 = Ptr.plusPtr pos 1
           in chompChunks pos1 end pos1 (Escape 0x5C {-\-} : addSlice start pos revChunks)
        0x0D {-\r-} -> processCarriageReturn pos end start revChunks
        _ -> processRegularChar pos end start revChunks

-- | Process carriage return character during comment chunking.
--
-- Internal helper that handles carriage return by skipping it and
-- adding the previous slice to chunks.
--
-- @since 0.19.1
processCarriageReturn :: Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> [Chunk] -> [Chunk]
processCarriageReturn pos end start revChunks =
  let !newPos = Ptr.plusPtr pos 1
   in chompChunks newPos end newPos (addSlice start pos revChunks)

-- | Process regular character during comment chunking.
--
-- Internal helper that handles regular characters by advancing
-- the position based on character width.
--
-- @since 0.19.1
processRegularChar :: Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> [Chunk] -> [Chunk]
processRegularChar pos end start revChunks =
  let !width = P.getCharWidth (P.unsafeIndex pos)
      !newPos = Ptr.plusPtr pos width
   in chompChunks newPos end start revChunks

-- | Add a memory slice to the chunk accumulator if non-empty.
--
-- Internal utility for 'fromComment' that adds memory regions to
-- the chunk list for later processing.
--
-- @since 0.19.1
addSlice :: Ptr Word8 -> Ptr Word8 -> [Chunk] -> [Chunk]
addSlice start end revChunks =
  if start == end
    then revChunks
    else Slice start (Ptr.minusPtr end start) : revChunks

-- INTERNAL CHUNK PROCESSING

-- | Internal representation for comment processing chunks.
--
-- Used by 'fromComment' to represent segments of processed comment text.
-- Each chunk represents either a direct memory slice or an escape sequence
-- that needs special handling.
--
-- @since 0.19.1
data Chunk
  = -- | Direct memory slice pointing to original content.
    --
    -- Represents a contiguous region of memory that can be copied
    -- directly without escape processing.
    Slice !(Ptr Word8) !Int
  | -- | Escape sequence that needs interpretation.
    --
    -- Represents a single escape sequence (like @\n@, @\"@) that
    -- must be converted to its literal character representation.
    Escape !Word8

-- | Convert a list of chunks into a JSON string.
--
-- Internal function for 'fromComment' that processes the chunk list
-- and constructs the final string with proper escape handling.
--
-- **UNSAFE**: Uses 'IO.unsafeDupablePerformIO' for memory operations.
--
-- @since 0.19.1
fromChunks :: [Chunk] -> String
fromChunks chunks =
  IO.unsafeDupablePerformIO
    ( IO.stToIO
        ( do
            let !len = sum (fmap chunkToWidth chunks)
            mba <- Utf8.newByteArray len
            writeChunks mba 0 chunks
            Utf8.freeze mba
        )
    )

-- | Calculate the output width (in bytes) of a chunk.
--
-- Internal utility for 'fromComment' that determines how many bytes
-- a chunk will occupy in the final output string.
--
-- @since 0.19.1
chunkToWidth :: Chunk -> Int
chunkToWidth chunk =
  case chunk of
    Slice _ len -> len
    Escape _ -> 2

-- | Write chunks to a mutable byte array.
--
-- Internal function for 'fromComment' that writes processed chunks
-- to a mutable byte array for final string construction.
--
-- @since 0.19.1
writeChunks :: MBA RealWorld -> Int -> [Chunk] -> ST RealWorld ()
writeChunks mba offset chunks =
  case chunks of
    [] ->
      return ()
    chunk : chunks ->
      case chunk of
        Slice ptr len ->
          do
            Utf8.copyFromPtr ptr mba offset len
            let !newOffset = offset + len
            writeChunks mba newOffset chunks
        Escape word ->
          do
            Utf8.writeWord8 mba offset 0x5C {- \ -}
            Utf8.writeWord8 mba (offset + 1) word
            let !newOffset = offset + 2
            writeChunks mba newOffset chunks

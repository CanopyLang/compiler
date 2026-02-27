-- |
-- Module: Canopy.Data.Index
-- Description: Zero-based indexing operations for the Canopy compiler
-- Copyright: (c) 2024 Canopy Contributors
-- License: BSD-3-Clause
--
-- This module provides a type-safe zero-based indexing system for the Canopy compiler.
-- It prevents off-by-one errors by explicitly distinguishing between zero-based machine
-- indices and one-based human-readable indices.
--
-- The module also provides indexed versions of common operations like 'map', 'traverse',
-- and 'zipWith', which are essential for compiler passes that need to track element positions
-- during transformations.
--
-- ==== Key Features
--
-- * **Type-safe indexing** - 'ZeroBased' prevents mixing of indexing schemes
-- * **Indexed operations** - Position-aware versions of standard list operations
-- * **Verified zipping** - Length-checked zipping with comprehensive error reporting
-- * **Human conversion** - Safe conversion between machine and human indices
--
-- ==== Usage Examples
--
-- @
-- -- Basic indexing operations
-- let idx = first                    -- ZeroBased 0
--     next_idx = next idx           -- ZeroBased 1
--     human = toHuman idx           -- 1
--     machine = toMachine idx       -- 0
--
-- -- Indexed mapping with positions
-- let items = ["apple", "banana", "cherry"]
--     indexed = indexedMap (\\i item -> show (toHuman i) <> ": " <> item) items
--     -- Result: ["1: apple", "2: banana", "3: cherry"]
--
-- -- Length-verified zipping
-- case indexedZipWith (\\i x y -> (toHuman i, x, y)) [1,2,3] ['a','b','c'] of
--   LengthMatch results -> processResults results
--   LengthMismatch lenX lenY -> error ("Length mismatch: " <> show lenX <> " vs " <> show lenY)
-- @
--
-- ==== Architecture
--
-- The indexing system is built around the 'ZeroBased' newtype, which wraps an 'Int'
-- but provides type safety to prevent accidental mixing with raw integers.
--
-- All indexed operations follow these patterns:
-- 1. Accept position-aware functions that receive both index and value
-- 2. Automatically handle index generation and incrementing
-- 3. Maintain list order and structure during transformations
--
-- ==== Performance Characteristics
--
-- * **Time Complexity**: All operations are O(n) where n is list length
-- * **Space Complexity**: O(1) additional space beyond result allocation
-- * **Memory Usage**: Minimal overhead from 'ZeroBased' newtype wrapping
--
-- ==== Error Handling
--
-- Length mismatches in zipping operations are reported through the 'VerifiedList'
-- type, which explicitly represents success ('LengthMatch') or failure ('LengthMismatch')
-- cases with detailed length information.
--
-- @since 0.19.1
module Canopy.Data.Index
  ( -- * Zero-based Index Type
    ZeroBased,

    -- * Index Constants
    first,
    second,
    third,

    -- * Index Operations
    next,
    toMachine,
    toHuman,

    -- * Indexed List Operations
    indexedMap,
    indexedTraverse,
    indexedForA,

    -- * Verified Zipping
    VerifiedList (..),
    indexedZipWith,
    indexedZipWithA,
  )
where

import qualified Data.Aeson as Aeson
import Data.Binary

-- | Zero-based index type for type-safe indexing operations.
--
-- This newtype wraps an 'Int' to provide type safety and prevent
-- accidental mixing of zero-based indices with raw integers or
-- one-based human indices.
--
-- All arithmetic on indices should go through the provided functions
-- rather than unwrapping the constructor directly.
--
-- ==== Examples
--
-- >>> first
-- ZeroBased 0
--
-- >>> next first
-- ZeroBased 1
--
-- >>> toHuman first
-- 1
--
-- @since 0.19.1
newtype ZeroBased = ZeroBased Int
  deriving (Eq, Ord, Show)

-- | The first index in zero-based indexing (0).
--
-- This constant represents the starting position for all zero-based
-- indexing operations and array access.
--
-- ==== Examples
--
-- >>> first
-- ZeroBased 0
--
-- >>> toMachine first
-- 0
--
-- @since 0.19.1
first :: ZeroBased
first =
  ZeroBased 0

-- | The second index in zero-based indexing (1).
--
-- Commonly used for accessing the second element in lists and arrays.
--
-- ==== Examples
--
-- >>> second
-- ZeroBased 1
--
-- >>> toHuman second
-- 2
--
-- @since 0.19.1
second :: ZeroBased
second =
  ZeroBased 1

-- | The third index in zero-based indexing (2).
--
-- Commonly used for accessing the third element in lists and arrays.
--
-- ==== Examples
--
-- >>> third
-- ZeroBased 2
--
-- >>> toMachine third
-- 2
--
-- @since 0.19.1
third :: ZeroBased
third =
  ZeroBased 2

-- | Increment a zero-based index by one.
--
-- This function provides safe index increment operations without
-- exposing the underlying integer representation.
--
-- ==== Examples
--
-- >>> next first
-- ZeroBased 1
--
-- >>> next (next first)
-- ZeroBased 2
--
-- ==== Performance
--
-- This function is marked INLINE for zero-cost abstraction in
-- tight loops and recursive functions.
--
-- @since 0.19.1
{-# INLINE next #-}
next :: ZeroBased -> ZeroBased
next (ZeroBased i) =
  ZeroBased (i + 1)

-- | Convert zero-based index to machine-readable integer.
--
-- This function extracts the underlying integer value for use in
-- array indexing, pointer arithmetic, and other low-level operations
-- that expect zero-based indexing.
--
-- ==== Examples
--
-- >>> toMachine first
-- 0
--
-- >>> toMachine second
-- 1
--
-- >>> let items = ["a", "b", "c"]
-- >>> items !! toMachine second
-- "b"
--
-- ==== Use Cases
--
-- * Array and list indexing
-- * Pointer arithmetic
-- * Interface with C libraries
-- * Internal compiler bookkeeping
--
-- @since 0.19.1
toMachine :: ZeroBased -> Int
toMachine (ZeroBased index) =
  index

-- | Convert zero-based index to human-readable one-based integer.
--
-- This function converts internal zero-based indices to the one-based
-- numbering that humans naturally use for counting and error reporting.
--
-- ==== Examples
--
-- >>> toHuman first
-- 1
--
-- >>> toHuman second
-- 2
--
-- >>> "Error at position " <> show (toHuman first)
-- "Error at position 1"
--
-- ==== Use Cases
--
-- * Error messages and diagnostics
-- * User-facing output
-- * Line and column numbers
-- * Progress reporting
--
-- @since 0.19.1
toHuman :: ZeroBased -> Int
toHuman (ZeroBased index) =
  index + 1

-- | Map a function over a list with zero-based position information.
--
-- This function is similar to the standard 'map', but the mapping function
-- receives both the zero-based index and the value. This is essential for
-- compiler operations that need to track element positions.
--
-- The function automatically generates indices starting from 'first' (0)
-- and incrementing for each subsequent element.
--
-- ==== Examples
--
-- >>> indexedMap (\\i x -> show (toHuman i) <> ": " <> x) ["a", "b", "c"]
-- ["1: a", "2: b", "3: c"]
--
-- >>> indexedMap (\\i x -> (toMachine i, x)) ["apple", "banana"]
-- [(0, "apple"), (1, "banana")]
--
-- ==== Use Cases
--
-- * Adding line numbers to source code
-- * Generating indexed error messages
-- * Creating position-aware transformations
-- * Building source maps during compilation
--
-- ==== Performance
--
-- This function is marked INLINE and generates indices lazily,
-- making it suitable for use in performance-critical compiler passes.
--
-- @since 0.19.1
{-# INLINE indexedMap #-}
indexedMap :: (ZeroBased -> a -> b) -> [a] -> [b]
indexedMap func xs =
  zipWith func (fmap ZeroBased [0 .. length xs]) xs

-- | Traverse a list with zero-based position information in an applicative context.
--
-- This function combines the power of 'traverse' with position tracking,
-- allowing effectful operations that depend on element positions.
--
-- ==== Examples
--
-- >>> indexedTraverse (\\i x -> putStrLn (show (toHuman i) <> ": " <> x)) ["hello", "world"]
-- 1: hello
-- 2: world
-- [(), ()]
--
-- >>> indexedTraverse (\\i x -> if i == first then Just x else Nothing) ["a", "b"]
-- Nothing
--
-- ==== Error Handling
--
-- If any individual operation fails, the entire traversal fails according
-- to the semantics of the underlying 'Applicative' instance.
--
-- ==== Performance
--
-- This function is marked INLINE and uses 'sequenceA' for optimal
-- performance with the specific applicative functor being used.
--
-- @since 0.19.1
{-# INLINE indexedTraverse #-}
indexedTraverse :: (Applicative f) => (ZeroBased -> a -> f b) -> [a] -> f [b]
indexedTraverse func xs =
  sequenceA (indexedMap func xs)

-- | Flipped version of 'indexedTraverse' for more natural application.
--
-- This function provides a more natural syntax when the list is known
-- before the transformation function, similar to how 'forM' relates to 'mapM'.
--
-- ==== Examples
--
-- >>> indexedForA ["x", "y", "z"] \\i val -> print (toHuman i, val)
-- (1, "x")
-- (2, "y")
-- (3, "z")
-- [(), (), ()]
--
-- >>> indexedForA [1, 2, 3] \\i x -> pure (toMachine i + x)
-- [1, 3, 5]
--
-- ==== Use Cases
--
-- * Processing known data with position-dependent effects
-- * Validation with position-aware error reporting
-- * Building indexed data structures
--
-- @since 0.19.1
{-# INLINE indexedForA #-}
indexedForA :: (Applicative f) => [a] -> (ZeroBased -> a -> f b) -> f [b]
indexedForA xs func =
  sequenceA (indexedMap func xs)

-- | Result type for length-verified operations on lists.
--
-- This type explicitly represents the success or failure of operations
-- that require lists to have matching lengths, providing detailed
-- error information when lengths don't match.
--
-- ==== Examples
--
-- >>> case indexedZipWith (\\i x y -> (i, x, y)) [1, 2] ['a', 'b'] of
-- ...   LengthMatch results -> print results
-- ...   LengthMismatch lenX lenY -> error "Length mismatch"
-- [(ZeroBased 0, 1, 'a'), (ZeroBased 1, 2, 'b')]
--
-- >>> indexedZipWith (\\_ x y -> x + y) [1, 2, 3] [10, 20]
-- LengthMismatch 3 2
--
-- @since 0.19.1
data VerifiedList a
  = -- | Lists have matching lengths with successful results
    LengthMatch [a]
  | -- | Lists have mismatched lengths (first length, second length)
    LengthMismatch Int Int
  deriving (Eq, Show)

-- | Zip two lists with a position-aware function, verifying length compatibility.
--
-- This function performs indexed zipping while explicitly checking that both
-- input lists have the same length. If lengths differ, it returns precise
-- length information rather than silently truncating.
--
-- ==== Examples
--
-- >>> indexedZipWith (\\i x y -> show (toHuman i) <> ": " <> show (x + y)) [1, 2] [10, 20]
-- LengthMatch ["1: 11", "2: 22"]
--
-- >>> indexedZipWith (\\i x y -> (toMachine i, x, y)) [1, 2, 3] ['a', 'b']
-- LengthMismatch 3 2
--
-- >>> case indexedZipWith (\\i x y -> x ++ [toHuman i] ++ y) [[1]] [[2]] of
-- ...   LengthMatch [[1, 1, 2]] -> "Success"
-- ...   LengthMismatch _ _ -> "Failed"
-- "Success"
--
-- ==== Use Cases
--
-- * Parallel processing with length validation
-- * Compiler passes requiring matched AST structures
-- * Data validation with precise error reporting
-- * Safe parallel transformation of related data
--
-- ==== Error Conditions
--
-- Returns 'LengthMismatch' when input lists have different lengths,
-- including the actual lengths for detailed error reporting.
--
-- @since 0.19.1
indexedZipWith :: (ZeroBased -> a -> b -> c) -> [a] -> [b] -> VerifiedList c
indexedZipWith func listX listY =
  indexedZipWithHelp func 0 listX listY []

-- | Helper function for 'indexedZipWith' with tail-call optimization.
--
-- This internal function accumulates results in reverse order for efficiency,
-- then reverses the final result. It tracks the current index and remaining
-- elements from both lists.
--
-- ==== Implementation Details
--
-- Uses accumulator pattern with reverse for O(n) performance and
-- minimal memory allocation during the zipping process.
--
-- @since 0.19.1
indexedZipWithHelp :: (ZeroBased -> a -> b -> c) -> Int -> [a] -> [b] -> [c] -> VerifiedList c
indexedZipWithHelp func index listX listY revListZ =
  case (listX, listY) of
    ([], []) ->
      LengthMatch (reverse revListZ)
    (x : xs, y : ys) ->
      indexedZipWithHelp func (index + 1) xs ys $
        func (ZeroBased index) x y : revListZ
    (_, _) ->
      LengthMismatch (index + length listX) (index + length listY)

-- | Applicative version of 'indexedZipWith' for effectful operations.
--
-- This function performs length-verified indexed zipping in an applicative
-- context, allowing for effectful operations while maintaining length checking.
--
-- ==== Examples
--
-- >>> indexedZipWithA (\\i x y -> print (toHuman i, x + y) >> pure (x + y)) [1, 2] [10, 20]
-- (1, 11)
-- (2, 22)
-- LengthMatch [11, 22]
--
-- >>> indexedZipWithA (\\i x y -> if i == first then Just (x, y) else Nothing) [1] [2]
-- LengthMatch [Just (1, 2)]
--
-- >>> indexedZipWithA (\\_ x y -> [x, y]) [1, 2] [3]
-- LengthMismatch 2 1
--
-- ==== Error Handling
--
-- If lists have mismatched lengths, returns 'LengthMismatch' immediately
-- without performing any effectful operations. If lengths match but
-- individual operations fail, the failure propagates through the
-- 'Applicative' instance.
--
-- ==== Performance
--
-- For matching lengths, this function sequences all effects after
-- computing the pure indexed zip, providing optimal performance
-- for the common success case.
--
-- @since 0.19.1
indexedZipWithA :: (Applicative f) => (ZeroBased -> a -> b -> f c) -> [a] -> [b] -> f (VerifiedList c)
indexedZipWithA func listX listY =
  case indexedZipWith func listX listY of
    LengthMatch xs ->
      LengthMatch <$> sequenceA xs
    LengthMismatch x y ->
      pure (LengthMismatch x y)

-- | Binary serialization instance for 'ZeroBased'.
--
-- This instance provides efficient serialization and deserialization
-- of zero-based indices for compiler caching, intermediate file storage,
-- and network communication.
--
-- The serialization preserves the underlying integer value while
-- maintaining type safety through the newtype wrapper.
--
-- ==== Examples
--
-- >>> let encoded = encode second
-- >>> decode encoded :: ZeroBased
-- ZeroBased 1
--
-- >>> encode first == encode (ZeroBased 0)
-- True
--
-- ==== Use Cases
--
-- * Compiler intermediate file storage
-- * Caching compiled modules with position information
-- * Network protocols requiring indexed data
-- * Persistent storage of indexed structures
--
-- @since 0.19.1
instance Binary ZeroBased where
  get = fmap ZeroBased get
  put (ZeroBased n) = put n

-- AESON JSON INSTANCES

instance Aeson.ToJSON ZeroBased where
  toJSON (ZeroBased n) = Aeson.toJSON n

instance Aeson.FromJSON ZeroBased where
  parseJSON value = ZeroBased <$> Aeson.parseJSON value

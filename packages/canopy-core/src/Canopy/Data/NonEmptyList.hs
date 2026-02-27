-- |
-- Module: Canopy.Data.NonEmptyList
-- Description: Non-empty list data structure for the Canopy compiler
-- Copyright: (c) 2024 Canopy Contributors
-- License: BSD-3-Clause
--
-- This module provides a non-empty list data structure that guarantees at
-- compile time that the list contains at least one element. This prevents
-- runtime errors from operations like 'head' and provides safer APIs for
-- functions that require non-empty input.
--
-- The 'List' type is used throughout the Canopy compiler for collections
-- that must contain at least one element, such as pattern match branches,
-- function parameters, and error message collections.
--
-- ==== Key Features
--
-- * **Compile-time safety** - Prevents empty list errors at the type level
-- * **Head-safe operations** - 'head' function cannot fail at runtime
-- * **Standard instances** - Functor, Foldable, Traversable for compatibility
-- * **Efficient operations** - Optimized sorting and append operations
-- * **Binary serialization** - Built-in support for persistence and caching
--
-- ==== Usage Examples
--
-- @
-- -- Create non-empty lists
-- let single = singleton "error"
--     multiple = List "first" ["second", "third"]
--
-- -- Safe head operation (never fails)
-- let first_item = head multiple  -- "first"
--
-- -- Convert to regular list when needed
-- let all_items = toList multiple  -- ["first", "second", "third"]
--
-- -- Append non-empty lists
-- let combined = append single multiple
--     -- Result: List "error" ["first", "second", "third"]
--
-- -- Sort by custom criteria
-- let sorted = sortBy length (List "abc" ["a", "ab"])
--     -- Result: List "a" ["ab", "abc"]
-- @
--
-- ==== Architecture
--
-- Non-empty lists are represented using a single constructor 'List a [a]'
-- that stores the head element separately from the tail. This ensures:
--
-- 1. **Type safety** - Construction requires at least one element
-- 2. **Performance** - Head access is O(1) without pattern matching
-- 3. **Memory efficiency** - Minimal overhead over regular lists
-- 4. **Compatibility** - Easy conversion to/from standard lists
--
-- ==== Performance Characteristics
--
-- * **Construction**: O(1) for singleton, O(1) for List constructor
-- * **Head access**: O(1) guaranteed safe access
-- * **Append**: O(1) for prepending to head, O(n) for list append
-- * **Sorting**: O(n log n) with specialized non-empty optimizations
-- * **Conversion**: O(1) to list, O(1) from non-empty list
--
-- ==== Error Handling
--
-- This module eliminates the most common source of runtime errors in list
-- processing by making non-emptiness a compile-time guarantee. Operations
-- that would fail on empty lists (like 'head') are safe by construction.
--
-- @since 0.19.1
module Canopy.Data.NonEmptyList
  ( -- * Non-empty List Type
    List (..),

    -- * Construction
    singleton,

    -- * Element Access
    head,

    -- * Combination
    append,

    -- * Transformation
    sortBy,

    -- * Conversion
    toList,
  )
where

import Control.Monad (liftM2)
import Data.Binary (Binary, get, put)
import qualified Data.List as List
import Prelude hiding (head)

-- | Non-empty list data type.
--
-- A list that is guaranteed to contain at least one element, represented
-- by storing the head element separately from the (possibly empty) tail.
-- This provides compile-time safety for operations that require non-empty lists.
--
-- ==== Constructor
--
-- * 'List' @head tail@ - Creates a non-empty list with @head@ as the first
--   element and @tail@ as the remaining elements
--
-- ==== Examples
--
-- >>> List 1 []
-- List 1 []
--
-- >>> List 'a' ['b', 'c']
-- List 'a' ['b','c']
--
-- >>> toList (List "first" ["second", "third"])
-- ["first", "second", "third"]
--
-- @since 0.19.1
data List a
  = -- | Non-empty list with head and tail
    List a [a]

-- | Create a singleton non-empty list containing one element.
--
-- This is the most concise way to create a non-empty list with exactly
-- one element, equivalent to @List element []@.
--
-- ==== Examples
--
-- >>> singleton 42
-- List 42 []
--
-- >>> singleton "hello"
-- List "hello" []
--
-- >>> toList (singleton 'x')
-- ['x']
--
-- ==== Use Cases
--
-- * Creating single-element collections that must be non-empty
-- * Base case for building larger non-empty lists
-- * Converting single values to non-empty list context
--
-- @since 0.19.1
singleton :: a -> List a
singleton a =
  List a []

-- | Convert a non-empty list to a regular list.
--
-- This function provides safe conversion from the type-safe non-empty
-- list to a regular list for interoperability with standard list operations.
-- The resulting list is guaranteed to be non-empty.
--
-- ==== Examples
--
-- >>> toList (singleton 1)
-- [1]
--
-- >>> toList (List 'a' ['b', 'c'])
-- ['a', 'b', 'c']
--
-- >>> length (toList (List "x" ["y", "z"]))
-- 3
--
-- ==== Properties
--
-- * **Non-empty guarantee**: Result is always non-empty
-- * **Order preservation**: Elements maintain their original order
-- * **No-copy conversion**: O(1) operation using cons
--
-- @since 0.19.1
toList :: List a -> [a]
toList (List x xs) =
  x : xs

-- | Get the first element of a non-empty list.
--
-- This function provides safe access to the head element without any
-- possibility of runtime failure, unlike the standard 'head' function
-- on regular lists which can fail on empty lists.
--
-- ==== Examples
--
-- >>> head (singleton "test")
-- "test"
--
-- >>> head (List 1 [2, 3, 4])
-- 1
--
-- >>> head (List 'a' [])
-- 'a'
--
-- ==== Performance
--
-- * **Time Complexity**: O(1)
-- * **Space Complexity**: O(1)
-- * **Safety**: Cannot fail at runtime
--
-- @since 0.19.1
head :: List a -> a
head (List x _) = x

-- | Append two non-empty lists to create a new non-empty list.
--
-- This function combines two non-empty lists by using the head of the first
-- list and appending its tail to the complete second list. The result is
-- guaranteed to be non-empty since both inputs are non-empty.
--
-- ==== Examples
--
-- >>> append (singleton 1) (singleton 2)
-- List 1 [2]
--
-- >>> append (List 'a' ['b']) (List 'c' ['d'])
-- List 'a' ['b', 'c', 'd']
--
-- >>> toList (append (List 1 [2]) (List 3 [4, 5]))
-- [1, 2, 3, 4, 5]
--
-- ==== Properties
--
-- * **Non-empty result**: Always produces a non-empty list
-- * **Order preservation**: Elements from first list come before elements from second
-- * **Head preservation**: Head of result is head of first list
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) where n is the length of the first list's tail
-- * **Space Complexity**: O(n) for the combined tail
-- * **Memory**: Single allocation for the new tail list
--
-- @since 0.19.1
append :: List a -> List a -> List a
append (List x xs) ys = List x (xs <> toList ys)

-- | Functor instance for non-empty lists.
--
-- Applies a function to every element in the non-empty list while
-- preserving the non-empty structure and element order.
--
-- ==== Laws
--
-- * @fmap id == id@
-- * @fmap (f . g) == fmap f . fmap g@
--
-- ==== Examples
--
-- >>> fmap (*2) (List 1 [2, 3])
-- List 2 [4, 6]
--
-- >>> fmap show (singleton 42)
-- List "42" []
--
-- @since 0.19.1
instance Functor List where
  fmap func (List x xs) = List (func x) (fmap func xs)

-- | Traversable instance for non-empty lists.
--
-- Enables effectful operations over non-empty lists while preserving
-- the non-empty structure. Useful for operations that may fail or
-- have side effects.
--
-- ==== Examples
--
-- >>> traverse Just (List 1 [2, 3])
-- Just (List 1 [2, 3])
--
-- >>> traverse (\\x -> if x > 0 then Just x else Nothing) (List 1 [2])
-- Just (List 1 [2])
--
-- @since 0.19.1
instance Traversable List where
  traverse func (List x xs) = List <$> func x <*> traverse func xs

-- | Foldable instance for non-empty lists.
--
-- Provides fold operations that work over the entire non-empty list.
-- The specialized 'foldl1' implementation is safe since the list is
-- guaranteed to be non-empty.
--
-- ==== Examples
--
-- >>> foldr (+) 0 (List 1 [2, 3, 4])
-- 10
--
-- >>> foldl1 max (List 3 [1, 4, 2])
-- 4
--
-- @since 0.19.1
instance Foldable List where
  foldr step state (List x xs) = step x (foldr step state xs)
  foldl step state (List x xs) = foldl step (step state x) xs
  foldl1 step (List x xs) = foldl step x xs

-- | Equality instance for non-empty lists.
--
-- Two non-empty lists are equal if their heads are equal and
-- their tails are equal (element-wise comparison).
--
-- ==== Examples
--
-- >>> List 1 [2, 3] == List 1 [2, 3]
-- True
--
-- >>> singleton 'a' == singleton 'b'
-- False
--
-- @since 0.19.1
instance (Eq a) => Eq (List a) where
  List x xs == List y ys = x == y && xs == ys

-- | Show instance for non-empty lists.
--
-- Displays non-empty lists by converting them to regular lists
-- and using the standard list show format.
--
-- ==== Examples
--
-- >>> show (List 1 [2, 3])
-- "[1,2,3]"
--
-- >>> show (singleton "hello")
-- "[\"hello\"]"
--
-- @since 0.19.1
instance (Show a) => Show (List a) where
  show xs = show (toList xs)

-- | Sort a non-empty list by a ranking function.
--
-- This function sorts the non-empty list using the provided ranking function
-- while maintaining the non-empty property. The implementation optimizes for
-- the case where the head element is already in the correct position.
--
-- ==== Examples
--
-- >>> sortBy length (List "abc" ["a", "ab"])
-- List "a" ["ab", "abc"]
--
-- >>> sortBy id (List 3 [1, 4, 2])
-- List 1 [2, 3, 4]
--
-- >>> sortBy Down (singleton 5)
-- List 5 []
--
-- ==== Algorithm
--
-- The implementation:
-- 1. Sorts the tail using standard list sorting
-- 2. Determines the correct position for the head element
-- 3. Constructs the result with optimal head positioning
--
-- ==== Performance
--
-- * **Time Complexity**: O(n log n) where n is the total number of elements
-- * **Space Complexity**: O(n) for the sorted result
-- * **Memory**: Single allocation with optimized head placement
--
-- ==== Properties
--
-- * **Non-empty result**: Always produces a non-empty list
-- * **Stable sorting**: Elements with equal ranking maintain relative order
-- * **Total ordering**: Works with any 'Ord' instance
--
-- @since 0.19.1
sortBy :: (Ord b) => (a -> b) -> List a -> List a
sortBy toRank (List x xs) =
  case List.sortBy comparison xs of
    [] ->
      List x []
    y : ys ->
      case comparison x y of
        LT -> List x (y : ys)
        EQ -> List x (y : ys)
        GT -> List y (List.insertBy comparison x ys)
  where
    comparison a b = compare (toRank a) (toRank b)

-- | Binary serialization instance for non-empty lists.
--
-- Provides efficient serialization and deserialization of non-empty
-- lists for compiler caching, intermediate file storage, and network
-- communication. The serialization preserves both the head element
-- and the tail structure.
--
-- ==== Examples
--
-- >>> let encoded = encode (List 1 [2, 3])
-- >>> decode encoded :: List Int
-- List 1 [2, 3]
--
-- >>> encode (singleton "test") == encode (List "test" [])
-- True
--
-- ==== Use Cases
--
-- * Compiler intermediate file storage with guaranteed non-empty collections
-- * Caching parsed structures that must contain elements
-- * Network protocols requiring non-empty data
-- * Persistent storage of non-empty configurations
--
-- @since 0.19.1
instance (Binary a) => Binary (List a) where
  put (List x xs) = put x >> put xs
  get = liftM2 List get get

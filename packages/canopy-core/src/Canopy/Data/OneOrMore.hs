{-# LANGUAGE StandaloneDeriving #-}

-- |
-- Module: Canopy.Data.OneOrMore
-- Description: Tree-based non-empty collection for the Canopy compiler
-- Copyright: (c) 2024 Canopy Contributors
-- License: BSD-3-Clause
--
-- This module provides a tree-based non-empty collection that guarantees at
-- compile time that the structure contains at least one element. Unlike
-- 'Data.NonEmptyList', this structure is optimized for combining and splitting
-- operations rather than sequential access.
--
-- The 'OneOrMore' type uses a binary tree representation that makes it ideal
-- for scenarios where data is accumulated from multiple sources and later
-- processed, such as collecting error messages from parallel compiler passes
-- or combining results from recursive tree traversals.
--
-- ==== Key Features
--
-- * **Compile-time non-emptiness** - Type-safe guarantee of containing elements
-- * **Efficient combining** - O(1) merging of two collections
-- * **Tree-based structure** - Optimized for parallel processing patterns
-- * **Deconstruction support** - Safe extraction to head/tail representation
-- * **Flexible access patterns** - Support for both tree and list-like operations
--
-- ==== Usage Examples
--
-- @
-- -- Create collections
-- let single = one "error"
--     combined = more (one "parse") (one "type")
--     nested = more single combined
--
-- -- Transform all elements
-- let prefixed = map ("Error: " <>) nested
--
-- -- Extract elements for processing
-- let asList = destruct (\\head tail -> head : tail) prefixed
--     -- Result: ["Error: error", "Error: parse", "Error: type"]
--
-- -- Access first elements from two collections
-- let (first, second) = getFirstTwo (one "a") (one "b")
--     -- Result: ("a", "b")
-- @
--
-- ==== Architecture
--
-- The structure is implemented as a binary tree with two constructors:
-- * 'One' - contains a single element (leaf node)
-- * 'More' - combines two sub-collections (internal node)
--
-- This design provides:
-- 1. **Type safety** - Cannot represent empty collections
-- 2. **Efficient combination** - O(1) merging without copying
-- 3. **Lazy evaluation** - Elements processed only when accessed
-- 4. **Parallel processing** - Natural tree structure for divide-and-conquer
--
-- ==== Performance Characteristics
--
-- * **Creation**: O(1) for both single elements and combinations
-- * **Combining**: O(1) for merging any two collections
-- * **Mapping**: O(n) where n is the number of elements
-- * **Deconstruction**: O(n) for converting to list representation
-- * **First access**: O(log n) worst case for deeply nested structures
--
-- ==== Comparison with NonEmptyList
--
-- Use 'OneOrMore' when:
-- * Frequent combining of collections is required
-- * Data comes from parallel or tree-based sources
-- * Order is less important than combining efficiency
-- * Working with recursive tree algorithms
--
-- Use 'NonEmptyList' when:
-- * Sequential access patterns dominate
-- * Head/tail operations are primary
-- * Compatibility with list operations is needed
-- * Order preservation is critical
--
-- @since 0.19.1
module Canopy.Data.OneOrMore
  ( -- * OneOrMore Type
    OneOrMore (..),

    -- * Construction
    one,
    more,

    -- * Transformation
    map,

    -- * Deconstruction
    destruct,
    getFirstTwo,
  )
where

import Prelude hiding (map)

-- | Tree-based non-empty collection data type.
--
-- A recursive binary tree structure that guarantees non-emptiness at the
-- type level. Each node either contains a single element ('One') or
-- combines two existing collections ('More').
--
-- ==== Constructors
--
-- * 'One' @element@ - A leaf node containing a single element
-- * 'More' @left right@ - An internal node combining two sub-collections
--
-- ==== Examples
--
-- >>> One "hello"
-- One "hello"
--
-- >>> More (One 1) (One 2)
-- More (One 1) (One 2)
--
-- >>> More (One 'a') (More (One 'b') (One 'c'))
-- More (One 'a') (More (One 'b') (One 'c'))
--
-- @since 0.19.1
data OneOrMore a
  = -- | Single element (leaf node)
    One a
  | -- | Combined collections (internal node)
    More (OneOrMore a) (OneOrMore a)
  deriving (Eq)

-- | Show instance for OneOrMore.
--
-- Provides readable display of the tree structure, showing the
-- hierarchical organization of elements and combinations.
--
-- @since 0.19.1
deriving instance Show a => Show (OneOrMore a)

-- | Create a single-element collection.
--
-- This function constructs the simplest possible 'OneOrMore' containing
-- exactly one element. It serves as the base case for building larger
-- collections through combination.
--
-- ==== Examples
--
-- >>> one 42
-- One 42
--
-- >>> one "error message"
-- One "error message"
--
-- >>> one [1, 2, 3]
-- One [1,2,3]
--
-- ==== Use Cases
--
-- * Converting single values to 'OneOrMore' for uniform handling
-- * Base case in recursive collection building
-- * Initial element in accumulation patterns
-- * Creating leaf nodes in tree construction
--
-- @since 0.19.1
one :: a -> OneOrMore a
one =
  One

-- | Combine two collections into a new collection.
--
-- This function merges two existing 'OneOrMore' collections into a single
-- collection containing all elements from both inputs. The operation is
-- O(1) and creates a new tree node without copying existing data.
--
-- ==== Examples
--
-- >>> more (one 1) (one 2)
-- More (One 1) (One 2)
--
-- >>> more (one "a") (more (one "b") (one "c"))
-- More (One "a") (More (One "b") (One "c"))
--
-- >>> let left = more (one 1) (one 2)
-- >>> let right = one 3
-- >>> more left right
-- More (More (One 1) (One 2)) (One 3)
--
-- ==== Properties
--
-- * **Non-empty result**: Always produces a non-empty collection
-- * **Structure preservation**: Input collections become subtrees
-- * **Associative**: @more (more a b) c ≡ more a (more b c)@ (up to structure)
-- * **No element duplication**: All original elements are preserved
--
-- ==== Performance
--
-- * **Time Complexity**: O(1)
-- * **Space Complexity**: O(1) additional space
-- * **Memory**: Single tree node allocation
--
-- @since 0.19.1
more :: OneOrMore a -> OneOrMore a -> OneOrMore a
more =
  More

-- | Apply a function to every element in the collection.
--
-- This function transforms each element in the 'OneOrMore' collection
-- using the provided function, preserving the tree structure while
-- applying the transformation recursively to all nodes.
--
-- ==== Examples
--
-- >>> map (*2) (one 5)
-- One 10
--
-- >>> map show (More (One 1) (One 2))
-- More (One "1") (One "2")
--
-- >>> map (+1) (more (one 1) (more (one 2) (one 3)))
-- More (One 2) (More (One 3) (One 4))
--
-- ==== Properties
--
-- * **Structure preservation**: Tree shape remains unchanged
-- * **Element transformation**: All elements are transformed exactly once
-- * **Functor laws**: Satisfies @map id == id@ and @map (f . g) == map f . map g@
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) where n is the number of elements
-- * **Space Complexity**: O(n) for the new tree structure
-- * **Memory**: New tree constructed with transformed elements
--
-- @since 0.19.1
map :: (a -> b) -> OneOrMore a -> OneOrMore b
map func oneOrMore =
  case oneOrMore of
    One value ->
      One (func value)
    More left right ->
      More (map func left) (map func right)

-- | Deconstruct a collection into head and tail representation.
--
-- This function converts the tree-based 'OneOrMore' structure into a
-- traditional head/tail representation by extracting the first element
-- and collecting all remaining elements into a list.
--
-- The deconstruction follows a left-to-right traversal of the tree,
-- making the leftmost element the head and the remaining elements
-- the tail in tree traversal order.
--
-- ==== Examples
--
-- >>> destruct (\\h t -> h : t) (one "single")
-- ["single"]
--
-- >>> destruct (\\h t -> (h, t)) (more (one 1) (one 2))
-- (1, [2])
--
-- >>> destruct (\\h t -> h : t) (more (one 'a') (more (one 'b') (one 'c')))
-- ['a', 'b', 'c']
--
-- ==== Use Cases
--
-- * Converting to list representation for sequential processing
-- * Pattern matching on head element with tail processing
-- * Integration with list-based algorithms
-- * Extracting elements for external APIs
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) where n is the number of elements
-- * **Space Complexity**: O(n) for the tail list construction
-- * **Memory**: Single traversal with list building
--
-- @since 0.19.1
destruct :: (a -> [a] -> b) -> OneOrMore a -> b
destruct func oneOrMore =
  destructLeft func oneOrMore []

-- | Helper function for 'destruct' that accumulates elements left-to-right.
--
-- This internal function performs the left-to-right traversal needed for
-- 'destruct', accumulating tail elements in the correct order while
-- searching for the leftmost element to use as the head.
--
-- ==== Implementation Details
--
-- Uses continuation-passing style to efficiently build the tail list
-- while maintaining left-to-right ordering of elements.
--
-- @since 0.19.1
destructLeft :: (a -> [a] -> b) -> OneOrMore a -> [a] -> b
destructLeft func oneOrMore xs =
  case oneOrMore of
    One x ->
      func x xs
    More a b ->
      destructLeft func a (destructRight b xs)

-- | Helper function that extracts all elements from a subtree.
--
-- This internal function performs a complete traversal of a 'OneOrMore'
-- subtree, collecting all elements in left-to-right order and prepending
-- them to the provided accumulator list.
--
-- ==== Implementation Details
--
-- Uses tail-recursive pattern with accumulator for efficient list
-- construction without excessive memory allocation.
--
-- @since 0.19.1
destructRight :: OneOrMore a -> [a] -> [a]
destructRight oneOrMore xs =
  case oneOrMore of
    One x ->
      x : xs
    More a b ->
      destructRight a (destructRight b xs)

-- | Extract the first element from two collections.
--
-- This function efficiently extracts the leftmost element from each of
-- two 'OneOrMore' collections, returning them as a pair. This is useful
-- for operations that need to process corresponding elements from
-- parallel data structures.
--
-- ==== Examples
--
-- >>> getFirstTwo (one "a") (one "b")
-- ("a", "b")
--
-- >>> getFirstTwo (more (one 1) (one 2)) (one 10)
-- (1, 10)
--
-- >>> getFirstTwo (one 'x') (more (one 'y') (one 'z'))
-- ('x', 'y')
--
-- ==== Use Cases
--
-- * Parallel processing of two collections
-- * Extracting corresponding elements for comparison
-- * Initialization of algorithms requiring paired data
-- * Sampling from multiple data sources
--
-- ==== Performance
--
-- * **Time Complexity**: O(log n) worst case for deeply nested left structures
-- * **Space Complexity**: O(1)
-- * **Memory**: No additional allocation required
--
-- @since 0.19.1
getFirstTwo :: OneOrMore a -> OneOrMore a -> (a, a)
getFirstTwo left right =
  (getFirstOne left, getFirstOne right)

-- | Extract the first (leftmost) element from a collection.
--
-- This function finds and returns the leftmost element in the tree
-- structure by recursively descending the left branches until it
-- reaches a leaf node.
--
-- ==== Examples
--
-- >>> getFirstOne (one 42)
-- 42
--
-- >>> getFirstOne (more (one "first") (one "second"))
-- "first"
--
-- >>> getFirstOne (more (more (one 1) (one 2)) (one 3))
-- 1
--
-- ==== Use Cases
--
-- * Accessing the primary element without full deconstruction
-- * Sampling from collections
-- * Priority-based element access
-- * Header extraction from structured data
--
-- ==== Performance
--
-- * **Time Complexity**: O(log n) worst case for deeply nested left structures
-- * **Space Complexity**: O(1)
-- * **Memory**: No additional allocation required
--
-- @since 0.19.1
getFirstOne :: OneOrMore a -> a
getFirstOne oneOrMore =
  case oneOrMore of
    One x ->
      x
    More left _ ->
      getFirstOne left

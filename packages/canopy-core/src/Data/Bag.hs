
-- |
-- Module: Data.Bag
-- Description: Efficient bag (multiset) data structure for the Canopy compiler
-- Copyright: (c) 2024 Canopy Contributors
-- License: BSD-3-Clause
--
-- This module provides an efficient bag (multiset) data structure optimized for
-- compiler operations. A bag is an unordered collection that allows duplicates
-- and supports efficient concatenation and mapping operations.
--
-- The 'Bag' type is implemented as a binary tree structure that provides O(1)
-- empty/singleton creation and O(1) concatenation, making it ideal for collecting
-- results during compiler traversals where order doesn't matter but duplicates
-- need to be preserved.
--
-- ==== Key Features
--
-- * **O(1) concatenation** - Efficient combining of bags during tree traversals
-- * **O(1) empty/singleton** - Fast creation of empty bags and single-element bags
-- * **Lazy evaluation** - Tree structure enables deferred computation
-- * **Duplicate preservation** - All elements are maintained, including duplicates
-- * **Order independence** - No guarantees about element ordering (multiset semantics)
--
-- ==== Usage Examples
--
-- @
-- -- Create bags
-- let empty_bag = empty
--     single = one "error"
--     combined = single \`append\` one "warning"
--
-- -- Transform contents
-- let messages = ["parse error", "type error"]
--     bag = fromList id messages
--     prefixed = map ("Error: " <>) bag
--
-- -- Convert to list for processing
-- let all_messages = toList prefixed
--     -- Result: ["Error: parse error", "Error: type error"] (order not guaranteed)
-- @
--
-- ==== Architecture
--
-- The bag is implemented as a simple binary tree with three constructors:
-- * 'Empty' - represents an empty bag
-- * 'One' - holds a single element
-- * 'Two' - combines two sub-bags
--
-- This structure provides optimal performance for the append-heavy workloads
-- common in compiler operations, where intermediate results are frequently
-- combined but rarely accessed individually.
--
-- ==== Performance Characteristics
--
-- * **Creation**: O(1) for empty and singleton bags
-- * **Append**: O(1) for combining any two bags
-- * **Map**: O(n) where n is the number of elements
-- * **ToList**: O(n) with minimal allocation overhead
-- * **FromList**: O(n) with right-associative tree construction
-- * **Space**: O(n) with no additional overhead beyond tree structure
--
-- ==== Comparison with Lists
--
-- Bags are preferable to lists when:
-- * Order doesn't matter
-- * Frequent concatenation is required
-- * Elements may be processed out-of-order
-- * Building results incrementally during traversals
--
-- Lists are preferable when:
-- * Order is significant
-- * Random access is needed
-- * Compatibility with standard list functions required
--
-- @since 0.19.1
module Data.Bag
  ( -- * Bag Type
    Bag (..),

    -- * Construction
    empty,
    one,

    -- * Combination
    append,

    -- * Transformation
    map,

    -- * Conversion
    toList,
    fromList,
  )
where

import qualified Data.List as List
import Prelude hiding (map)

-- | Efficient bag (multiset) data structure.
--
-- A bag is an unordered collection that preserves duplicates and provides
-- O(1) concatenation. It's implemented as a binary tree for optimal
-- performance during compiler traversals.
--
-- ==== Constructors
--
-- * 'Empty' - An empty bag containing no elements
-- * 'One' - A singleton bag containing exactly one element
-- * 'Two' - A bag formed by combining two sub-bags
--
-- ==== Examples
--
-- >>> Empty
-- Empty
--
-- >>> One "hello"
-- One "hello"
--
-- >>> Two (One 1) (One 2)
-- Two (One 1) (One 2)
--
-- @since 0.19.1
data Bag a
  = -- | Empty bag with no elements
    Empty
  | -- | Singleton bag with one element
    One a
  | -- | Combined bag from two sub-bags
    Two (Bag a) (Bag a)

-- | Create an empty bag.
--
-- This is the identity element for the 'append' operation, meaning
-- @append empty x == x@ and @append x empty == x@ for any bag @x@.
--
-- ==== Examples
--
-- >>> empty
-- Empty
--
-- >>> append empty (one "test")
-- One "test"
--
-- >>> toList empty
-- []
--
-- ==== Use Cases
--
-- * Initial value for fold operations over bags
-- * Base case in recursive bag construction
-- * Identity element in monoid operations
--
-- @since 0.19.1
empty :: Bag a
empty =
  Empty

-- | Create a singleton bag containing one element.
--
-- This is the most efficient way to create a bag with a single element,
-- requiring only O(1) time and space.
--
-- ==== Examples
--
-- >>> one "hello"
-- One "hello"
--
-- >>> toList (one 42)
-- [42]
--
-- >>> map (*2) (one 5)
-- One 10
--
-- ==== Use Cases
--
-- * Converting single values to bags for uniform handling
-- * Base case in recursive bag construction algorithms
-- * Efficient single-element collection creation
--
-- @since 0.19.1
one :: a -> Bag a
one =
  One

-- | Combine two bags into a new bag containing all elements from both.
--
-- This operation is O(1) and creates a new tree node that references
-- both input bags. The operation is optimized to avoid unnecessary
-- tree construction when one operand is empty.
--
-- ==== Examples
--
-- >>> append (one 1) (one 2)
-- Two (One 1) (One 2)
--
-- >>> append empty (one "test")
-- One "test"
--
-- >>> append (one "a") empty
-- One "a"
--
-- >>> toList (append (one 1) (one 2))
-- [1, 2]  -- Order not guaranteed
--
-- ==== Properties
--
-- * **Associative**: @append (append a b) c == append a (append b c)@
-- * **Identity**: @append empty x == x@ and @append x empty == x@
-- * **Commutative**: @append a b@ and @append b a@ contain the same elements
--
-- ==== Performance
--
-- * **Time Complexity**: O(1)
-- * **Space Complexity**: O(1) additional space
-- * **Memory**: No copying of existing elements
--
-- @since 0.19.1
append :: Bag a -> Bag a -> Bag a
append left right =
  case (left, right) of
    (other, Empty) ->
      other
    (Empty, other) ->
      other
    (_, _) ->
      Two left right

-- | Apply a function to every element in a bag.
--
-- This function transforms each element in the bag using the provided
-- function, preserving the bag's structure and maintaining all duplicates.
-- The transformation is applied recursively throughout the tree.
--
-- ==== Examples
--
-- >>> map (*2) empty
-- Empty
--
-- >>> map (+1) (one 5)
-- One 6
--
-- >>> map show (Two (One 1) (One 2))
-- Two (One "1") (One "2")
--
-- >>> toList (map length ["hello", "world", "test"])  -- After fromList id
-- [5, 5, 4]  -- Order not guaranteed
--
-- ==== Properties
--
-- * **Preserves structure**: The tree shape remains unchanged
-- * **Preserves duplicates**: All original elements are transformed
-- * **Functor laws**: Satisfies @map id == id@ and @map (f . g) == map f . map g@
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) where n is the number of elements
-- * **Space Complexity**: O(n) for the new bag structure
-- * **Memory**: New tree constructed with transformed elements
--
-- @since 0.19.1
map :: (a -> b) -> Bag a -> Bag b
map func bag =
  case bag of
    Empty ->
      Empty
    One a ->
      One (func a)
    Two left right ->
      Two (map func left) (map func right)

-- | Convert a bag to a list containing all elements.
--
-- This function extracts all elements from the bag and returns them as
-- a list. The order of elements is not guaranteed and may vary between
-- calls or implementations.
--
-- The conversion is performed using an accumulator for efficiency,
-- avoiding intermediate list allocations during traversal.
--
-- ==== Examples
--
-- >>> toList empty
-- []
--
-- >>> toList (one "hello")
-- ["hello"]
--
-- >>> sort (toList (Two (One 1) (One 2)))  -- Need sort due to order uncertainty
-- [1, 2]
--
-- >>> length (toList (fromList id [1, 2, 3, 4, 5]))
-- 5
--
-- ==== Properties
--
-- * **Preserves duplicates**: All elements from the bag are included
-- * **No ordering guarantee**: Element order depends on internal tree structure
-- * **Idempotent size**: @length (toList bag)@ equals the number of elements added
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) where n is the number of elements
-- * **Space Complexity**: O(n) for the result list
-- * **Memory**: Single traversal with accumulator-based construction
--
-- @since 0.19.1
toList :: Bag a -> [a]
toList bag =
  toListHelp bag []

-- | Helper function for 'toList' with accumulator for efficiency.
--
-- This internal function performs a depth-first traversal of the bag
-- tree, accumulating elements in reverse order for optimal performance.
-- The final result maintains all elements but order is implementation-dependent.
--
-- ==== Implementation Details
--
-- Uses continuation-passing style with accumulator to avoid intermediate
-- list construction and enable tail-call optimization.
--
-- @since 0.19.1
toListHelp :: Bag a -> [a] -> [a]
toListHelp bag list =
  case bag of
    Empty ->
      list
    One x ->
      x : list
    Two a b ->
      toListHelp a (toListHelp b list)

-- | Convert a list to a bag by applying a transformation function.
--
-- This function creates a bag from a list, applying the transformation
-- function to each element during construction. The resulting bag will
-- have a right-associative structure based on the list order.
--
-- ==== Examples
--
-- >>> fromList id []
-- Empty
--
-- >>> fromList show [1, 2, 3]
-- Two (One "3") (Two (One "2") (One "1"))  -- Right-associative structure
--
-- >>> toList (fromList (+1) [1, 2, 3])
-- [4, 3, 2]  -- Order reflects construction, not guaranteed
--
-- >>> fromList length ["hello", "world"]
-- Two (One 5) (One 5)  -- Duplicates preserved
--
-- ==== Use Cases
--
-- * Converting compiler error lists to bags for efficient combination
-- * Transforming parse results during list-to-bag conversion
-- * Building bags from external data sources
-- * Initial bag construction with element transformation
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) where n is the input list length
-- * **Space Complexity**: O(n) for the bag structure
-- * **Memory**: Right-associative tree construction with left fold
--
-- @since 0.19.1
fromList :: (a -> b) -> [a] -> Bag b
fromList func list =
  case list of
    [] ->
      Empty
    first : rest ->
      List.foldl' (add func) (One (func first)) rest

-- | Add a transformed element to an existing bag.
--
-- This helper function creates a new singleton bag containing the
-- transformed element and combines it with the existing bag using
-- 'Two' constructor.
--
-- ==== Implementation Details
--
-- Used internally by 'fromList' to build up the bag structure during
-- list traversal. Creates right-associative tree structure.
--
-- @since 0.19.1
add :: (a -> b) -> Bag b -> a -> Bag b
add func bag value =
  Two (One (func value)) bag

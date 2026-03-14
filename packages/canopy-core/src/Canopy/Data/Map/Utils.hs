{-# LANGUAGE TupleSections #-}

-- |
-- Module: Canopy.Data.Map.Utils
-- Description: Utility functions for Map operations in the Canopy compiler
-- Copyright: (c) 2024 Canopy Contributors
-- License: BSD-3-Clause
--
-- This module provides specialized utility functions for working with 'Data.Map'
-- that are commonly needed in compiler operations. These utilities extend the
-- standard 'Data.Map' interface with operations optimized for compiler-specific
-- use cases.
--
-- The functions in this module are designed for:
-- * Building maps from lists with transformation functions
-- * Efficiently testing map contents without full traversal
-- * Transforming nested map structures common in compiler analysis
-- * Inverting and restructuring maps for different access patterns
--
-- ==== Key Features
--
-- * **Efficient construction** - Build maps from keys or values with transformations
-- * **Applicative construction** - Build maps with effectful value generation
-- * **Content testing** - Fast existence checks without extracting values
-- * **Structure transformation** - Invert and restructure nested maps
-- * **Type-safe operations** - All functions preserve key and value type constraints
--
-- ==== Usage Examples
--
-- @
-- -- Build maps from keys with computed values
-- let moduleMap = fromKeys loadModule ["Main", "Utils", "Parser"]
--     -- Result: Map with module names as keys, loaded modules as values
--
-- -- Build maps with effectful value computation
-- result <- fromKeysA validateAndLoad ["file1.hs", "file2.hs"]
-- case result of
--   Left err -> handleError err
--   Right modules -> processModules modules
--
-- -- Test for specific values without extraction
-- when (any isError diagnostics) $
--   reportErrors diagnostics
--
-- -- Transform nested map structures
-- let modulesByType = exchangeKeys filesByModule
--     -- Swap outer/inner keys: Map Module (Map FileType [File])
--     -- becomes: Map FileType (Map Module [File])
-- @
--
-- ==== Architecture
--
-- The utilities are built on top of 'Data.Map' and leverage its internal
-- structure for efficiency. Functions like 'any' access the map's internal
-- tree representation to avoid unnecessary allocations during traversal.
--
-- For nested map operations, the functions use systematic key transformation
-- patterns that preserve all data while reorganizing access patterns to
-- match different query requirements.
--
-- ==== Performance Characteristics
--
-- * **fromKeys/fromValues**: O(n log n) where n is input list length
-- * **fromKeysA**: O(n log n) plus effect computation time
-- * **any**: O(n) worst case, with early termination for True results
-- * **invertMap**: O(n * m) where n is outer map size, m is average inner list size
-- * **exchangeKeys**: O(n * m) for restructuring nested maps
--
-- ==== Use Cases in Compiler
--
-- * **Module mapping** - Associate module names with loaded module data
-- * **Error collection** - Build error maps from validation results
-- * **Dependency analysis** - Transform dependency graphs for different queries
-- * **Symbol table operations** - Restructure symbol tables by different criteria
-- * **Optimization analysis** - Test for optimization opportunities efficiently
--
-- @since 0.19.1
module Canopy.Data.Map.Utils
  ( -- * Map Construction
    fromKeys,
    fromKeysA,
    fromValues,

    -- * Content Testing
    any,

    -- * Structure Transformation
    invertMap,
    exchangeKeys,
  )
where

import qualified Control.Monad as Monad
import qualified Data.Map.Strict as Map
import Data.Map.Internal (Map (..))
import qualified Canopy.Data.NonEmptyList as NE
import Prelude hiding (any)

-- | Build a map from a list of keys using a value generation function.
--
-- This function creates a map by applying the value generation function
-- to each key in the input list. Each key appears exactly once in the
-- result map with its corresponding generated value.
--
-- ==== Examples
--
-- >>> fromKeys show [1, 2, 3]
-- fromList [(1,"1"),(2,"2"),(3,"3")]
--
-- >>> fromKeys length ["hello", "world", "test"]
-- fromList [("hello",5),("test",4),("world",5)]
--
-- >>> fromKeys id ['a', 'b', 'c']
-- fromList [('a','a'),('b','b'),('c','c')]
--
-- ==== Use Cases
--
-- * Building lookup tables with computed values
-- * Creating index maps from element lists
-- * Associating keys with their properties or metadata
-- * Converting lists to maps for efficient lookup
--
-- ==== Error Conditions
--
-- If the input list contains duplicate keys, later occurrences overwrite
-- earlier ones in the resulting map, following standard 'Map.fromList' behavior.
--
-- ==== Performance
--
-- * **Time Complexity**: O(n log n) where n is the length of the input list
-- * **Space Complexity**: O(n) for the resulting map
-- * **Memory**: Single pass construction with logarithmic insertion cost
--
-- @since 0.19.1
fromKeys :: (Ord k) => (k -> v) -> [k] -> Map k v
fromKeys toValue keys =
  Map.fromList (fmap (\k -> (k, toValue k)) keys)

-- | Build a map from keys with effectful value generation.
--
-- This function creates a map by applying an effectful value generation
-- function to each key. The effects are sequenced using the 'Applicative'
-- instance, allowing for operations that may fail or have side effects.
--
-- ==== Examples
--
-- >>> fromKeysA (\\n -> if n > 0 then Just n else Nothing) [1, 2, 3]
-- Just (fromList [(1,1),(2,2),(3,3)])
--
-- >>> fromKeysA (\\n -> if n > 0 then Just n else Nothing) [-1, 2]
-- Nothing
--
-- >>> fromKeysA (\\file -> readFile file) ["config.txt", "data.txt"]  -- IO context
-- -- Returns IO (Map FilePath String) with file contents as values
--
-- ==== Use Cases
--
-- * Loading configuration maps with validation
-- * Building maps from file system operations
-- * Creating maps with database lookups
-- * Validating keys while building the map
--
-- ==== Error Handling
--
-- If any key's value generation fails, the entire operation fails according
-- to the 'Applicative' instance's failure semantics. For 'Maybe', the first
-- 'Nothing' causes the whole operation to return 'Nothing'.
--
-- ==== Performance
--
-- * **Time Complexity**: O(n log n) plus effect computation time
-- * **Space Complexity**: O(n) for the resulting map
-- * **Memory**: Effects are sequenced, not accumulated
--
-- @since 0.19.1
fromKeysA :: (Applicative f, Ord k) => (k -> f v) -> [k] -> f (Map k v)
fromKeysA toValue keys =
  Map.fromList <$> traverse (\k -> (,) k <$> toValue k) keys

-- | Build a map from a list of values using a key generation function.
--
-- This function creates a map by applying the key generation function
-- to each value in the input list. The values become the map values,
-- with keys computed from the values themselves.
--
-- ==== Examples
--
-- >>> fromValues length ["hello", "world", "test", "hi"]
-- fromList [(2,"hi"),(4,"test"),(5,"hello"),(5,"world")]
-- -- Note: "hello" and "world" both have key 5, so "world" overwrites "hello"
--
-- >>> fromValues head [['a', 'b'], ['c'], ['a', 'x']]
-- fromList [('a',['a','x']),('c',['c'])]
-- -- ['a','x'] overwrites ['a','b'] due to duplicate key 'a'
--
-- >>> fromValues id [1, 2, 3, 2]
-- fromList [(1,1),(2,2),(3,3)]
-- -- Duplicate value 2 is preserved with its own key
--
-- ==== Use Cases
--
-- * Creating reverse lookup maps (value to element)
-- * Grouping elements by computed properties
-- * Building indexes for efficient value-based queries
-- * Converting lists to maps for membership testing
--
-- ==== Error Conditions
--
-- If multiple values generate the same key, later values in the list
-- overwrite earlier ones, following standard 'Map.fromList' behavior.
-- This is important when the key function is not injective.
--
-- ==== Performance
--
-- * **Time Complexity**: O(n log n) where n is the length of the input list
-- * **Space Complexity**: O(n) for the resulting map
-- * **Memory**: Single pass construction with logarithmic insertion cost
--
-- @since 0.19.1
fromValues :: (Ord k) => (v -> k) -> [v] -> Map k v
fromValues toKey values =
  Map.fromList (fmap (\v -> (toKey v, v)) values)

-- | Test if any value in the map satisfies the predicate.
--
-- This function efficiently tests whether any value in the map satisfies
-- the given predicate, with early termination as soon as a matching value
-- is found. It accesses the map's internal tree structure for optimal
-- performance without unnecessary allocations.
--
-- ==== Examples
--
-- >>> any (> 5) (Map.fromList [(1, 10), (2, 3), (3, 7)])
-- True
--
-- >>> any even (Map.fromList [('a', 1), ('b', 3), ('c', 5)])
-- False
--
-- >>> any null (Map.fromList [(1, "hello"), (2, ""), (3, "world")])
-- True
--
-- ==== Use Cases
--
-- * Testing for error conditions in compiler diagnostics
-- * Checking for optimization opportunities without extraction
-- * Validating map contents before processing
-- * Early termination in search operations
--
-- ==== Performance
--
-- * **Time Complexity**: O(n) worst case, with early termination
-- * **Space Complexity**: O(1) additional space
-- * **Memory**: No additional allocation during traversal
-- * **Early termination**: Stops immediately upon finding a match
--
-- ==== Implementation Details
--
-- This function is marked INLINE and accesses 'Data.Map.Internal'
-- for direct tree traversal, avoiding the overhead of standard
-- folding operations.
--
-- @since 0.19.1
{-# INLINE any #-}
any :: (v -> Bool) -> Map k v -> Bool
any isGood = go
  where
    go Tip = False
    go (Bin _ _ v l r) = isGood v || go l || go r

-- | Helper function to add outer key to inner key-value pair.
--
-- This internal utility transforms a key-value pair into a triple
-- by prepending an additional key, used in flattening nested map
-- structures.
--
-- ==== Implementation Details
--
-- Used internally by 'flattenMaps' for systematic key transformation
-- during nested map processing.
--
-- @since 0.19.1
addToTuple :: a -> (b, c) -> (a, b, c)
addToTuple k (k1, v) = (k, k1, v)

-- | Flatten a nested map structure into a list of triples.
--
-- This function converts a map of maps into a flat list of triples,
-- where each triple contains the outer key, inner key, and value.
-- This is useful for restructuring nested data for different access patterns.
--
-- ==== Examples
--
-- >>> let nested = Map.fromList [("module1", Map.fromList [("func1", 10), ("func2", 20)]), ("module2", Map.fromList [("func1", 30)])]
-- >>> flattenMaps nested
-- [("module1","func1",10),("module1","func2",20),("module2","func1",30)]
--
-- ==== Use Cases
--
-- * Preprocessing for map structure transformations
-- * Converting nested maps to tabular data
-- * Preparing data for grouping by different criteria
-- * Flattening hierarchical data structures
--
-- ==== Performance
--
-- * **Time Complexity**: O(n * m) where n is outer map size, m is average inner map size
-- * **Space Complexity**: O(n * m) for the result list
-- * **Memory**: Single pass with list construction
--
-- @since 0.19.1
flattenMaps :: Map k0 (Map k1 v) -> [(k0, k1, v)]
flattenMaps nestedMaps = result
  where
    mapAsList = Map.toList nestedMaps
    listOfLists = fmap (\(k, innerMap) -> fmap (addToTuple k) (Map.toList innerMap)) mapAsList
    result = Monad.join listOfLists

-- | Exchange the order of keys in a nested map structure.
--
-- This function transforms a map from @Map k0 (Map k1 v)@ to @Map k1 (Map k0 v)@,
-- effectively swapping the outer and inner key roles. This is useful for
-- changing the primary access pattern of nested data.
--
-- ==== Examples
--
-- >>> let byModule = Map.fromList [("Parser", Map.fromList [("Error", 2), ("Warning", 1)]), ("TypeChecker", Map.fromList [("Error", 3)])]
-- >>> exchangeKeys byModule
-- fromList [("Error", fromList [("Parser", 2), ("TypeChecker", 3)]), ("Warning", fromList [("Parser", 1)])]
--
-- ==== Use Cases
--
-- * Changing query patterns in compiler analysis data
-- * Reorganizing diagnostic information by type vs. module
-- * Restructuring dependency graphs for different traversal needs
-- * Converting between different indexing schemes
--
-- ==== Properties
--
-- * **Preserves all data**: No information is lost during transformation
-- * **Maintains relationships**: All original key-value associations are preserved
-- * **Type safety**: Input and output maintain proper type relationships
--
-- ==== Performance
--
-- * **Time Complexity**: O(n * m * log(k)) where n is outer size, m is inner size, k is result size
-- * **Space Complexity**: O(n * m) for the restructured maps
-- * **Memory**: Requires temporary list construction during restructuring
--
-- @since 0.19.1
exchangeKeys :: (Ord k1, Ord k0) => Map k0 (Map k1 v) -> Map k1 (Map k0 v)
exchangeKeys nestedMap = fmap Map.fromList outerMap
  where
    asTriples = flattenMaps nestedMap
    rearrangedTriples = fmap (\(a, b, c) -> (b, [(a, c)])) asTriples
    outerMap = Map.fromListWith (++) rearrangedTriples

-- | Invert a map containing non-empty lists as values.
--
-- This function inverts a map where each key maps to a non-empty list of values,
-- creating a new map where each value from the original lists becomes a key
-- mapping to a non-empty list of the original keys that contained that value.
--
-- ==== Examples
--
-- >>> let m = Map.fromList [("errors", NE.List "parse" ["type"]), ("warnings", NE.List "unused" [])]
-- >>> invertMap m
-- fromList [("parse", List "errors" []), ("type", List "errors" []), ("unused", List "warnings" [])]
--
-- ==== Use Cases
--
-- * Creating reverse lookup tables for many-to-many relationships
-- * Inverting dependency maps for reverse dependency queries
-- * Building reverse indexes from forward indexes
-- * Converting categorization maps to membership maps
--
-- ==== Properties
--
-- * **Preserves all associations**: Every value-key relationship is maintained
-- * **Handles duplicates**: Multiple keys can map to the same value
-- * **Non-empty guarantee**: Result values are always non-empty lists
-- * **Order independence**: Result doesn't depend on original key ordering
--
-- ==== Performance
--
-- * **Time Complexity**: O(n * m * log(v)) where n is map size, m is average list size, v is unique values
-- * **Space Complexity**: O(n * m) for the inverted structure
-- * **Memory**: Constructs new map with all value-key associations
--
-- @since 0.19.1
invertMap :: (Ord v) => Map k (NE.List v) -> Map v (NE.List k)
invertMap mapOfLists = result
  where
    mapAsList = Map.toList mapOfLists
    listOfLists = fmap (\(k, vs) -> fmap (k,) vs) mapAsList
    listOfLists' = (listOfLists >>= NE.toList)
    swappedList = fmap (\(x, y) -> (y, NE.singleton x)) listOfLists'
    result = Map.fromListWith NE.append swappedList

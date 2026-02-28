
-- | AST.Utils.Binop - Binary operator precedence and associativity utilities
--
-- This module defines the core types and utilities for handling binary operator
-- precedence and associativity in the Canopy compiler. These types are used
-- throughout the compiler for operator parsing, precedence resolution, and
-- code generation.
--
-- The module provides type-safe representations of operator properties that
-- ensure correct operator precedence handling during parsing and semantic
-- analysis phases.
--
-- == Key Features
--
-- * **Type-Safe Precedence** - Precedence levels represented as safe integer wrappers
-- * **Standard Associativity** - Left, right, and non-associative operators
-- * **Binary Serialization** - Efficient serialization for module caching
-- * **Parser Integration** - Direct integration with operator parsing
--
-- == Architecture
--
-- The module defines two core types:
--
-- * 'Precedence' - Integer-based precedence levels with type safety
-- * 'Associativity' - Operator associativity classification
--
-- Both types include Binary instances for efficient serialization and
-- storage in compiled module interfaces.
--
-- == Usage Examples
--
-- === Precedence Definition
--
-- @
-- -- Define operator precedence levels
-- let addPrec = Precedence 6    -- Addition precedence
-- let mulPrec = Precedence 7    -- Multiplication precedence  
-- let expPrec = Precedence 8    -- Exponentiation precedence
-- @
--
-- === Associativity Specification
--
-- @
-- -- Left-associative operators (most arithmetic)
-- let leftAssoc = Left     -- a + b + c = (a + b) + c
--
-- -- Right-associative operators (function composition, power)
-- let rightAssoc = Right   -- a ^ b ^ c = a ^ (b ^ c)
--
-- -- Non-associative operators (comparison)
-- let nonAssoc = Non       -- a < b < c is invalid
-- @
--
-- === Operator Comparison
--
-- @
-- -- Compare operator precedence
-- if mulPrec > addPrec
--   then -- Multiplication binds tighter than addition
--   else -- Addition binds tighter (shouldn't happen)
--
-- -- Check associativity
-- case operatorAssoc of
--   Left -> -- Handle left-associative parsing
--   Right -> -- Handle right-associative parsing  
--   Non -> -- Reject chained non-associative operators
-- @
--
-- == Precedence Levels
--
-- Common Canopy operator precedence levels (higher = tighter binding):
--
-- * 9 - Function application, record access
-- * 8 - Exponentiation (^)
-- * 7 - Multiplication (*), division (/), remainder (%)
-- * 6 - Addition (+), subtraction (-)
-- * 5 - List construction (::)
-- * 4 - Comparison (<, >, <=, >=)
-- * 3 - Equality (==, /=)
-- * 2 - Logical AND (&&)
-- * 1 - Logical OR (||)
-- * 0 - Pipeline (|>), reverse pipeline (<|)
--
-- == Error Handling
--
-- The types in this module are designed to prevent precedence errors:
--
-- * Precedence values are wrapped to prevent raw integer confusion
-- * Associativity is explicitly typed to prevent parsing errors
-- * Binary deserialization includes error handling for corrupted data
--
-- == Performance Characteristics
--
-- * **Precedence Comparison**: O(1) integer comparison
-- * **Associativity Check**: O(1) pattern matching
-- * **Serialization**: O(1) for both precedence and associativity
-- * **Memory Usage**: Minimal overhead with newtype optimization
--
-- == Thread Safety
--
-- All types in this module are immutable and thread-safe. Operator
-- precedence analysis can be performed concurrently without synchronization.
--
-- @since 0.19.1
module AST.Utils.Binop
  ( Precedence (..),
    Associativity (..),
  )
where

import qualified Data.Aeson as Aeson
import Data.Binary
import Prelude hiding (Either (..))

-- BINOP STUFF

-- | Operator precedence level.
--
-- Represents the precedence level of binary operators as a type-safe
-- integer wrapper. Higher values indicate tighter binding (higher precedence).
--
-- Precedence levels determine the order of operations when multiple operators
-- appear in an expression without explicit parentheses. Operators with higher
-- precedence bind more tightly than those with lower precedence.
--
-- ==== Examples
--
-- >>> Precedence 7 > Precedence 6  -- Multiplication > Addition
-- True
--
-- >>> Precedence 4 == Precedence 4  -- Same precedence level
-- True
--
-- @since 0.19.1
newtype Precedence = Precedence Int
  deriving (Eq, Ord, Show)

-- | Operator associativity specification.
--
-- Defines how operators of the same precedence level associate when
-- appearing in chains. This determines how expressions like @a op b op c@
-- are parsed and evaluated.
--
-- @since 0.19.1
data Associativity
  = -- | Left-associative operators.
    --
    -- Operators that associate to the left: @a op b op c@ parses as @(a op b) op c@.
    -- Most arithmetic operators are left-associative (e.g., +, -, *, /).
    --
    -- Examples: @1 + 2 + 3@ becomes @(1 + 2) + 3@
    Left
  | -- | Non-associative operators.
    --
    -- Operators that cannot be chained without explicit parentheses.
    -- Expressions like @a op b op c@ are parse errors for non-associative operators.
    --
    -- Examples: Comparison operators like @<@, @>@ are typically non-associative
    -- to prevent confusing expressions like @1 < 2 < 3@.
    Non
  | -- | Right-associative operators.
    --
    -- Operators that associate to the right: @a op b op c@ parses as @a op (b op c)@.
    -- Function composition and exponentiation are typically right-associative.
    --
    -- Examples: @2 ^ 3 ^ 4@ becomes @2 ^ (3 ^ 4)@, function composition @f << g << h@ becomes @f << (g << h)@
    Right
  deriving (Eq, Show)

-- BINARY

-- | Binary serialization for precedence levels.
--
-- Efficiently serializes and deserializes precedence values for
-- module interface files and compilation caching.
--
-- @since 0.19.1
instance Binary Precedence where
  get =
    fmap Precedence get

  put (Precedence n) =
    put n

-- | Binary serialization for associativity specifications.
--
-- Efficiently serializes and deserializes associativity values with
-- proper error handling for corrupted data.
--
-- @since 0.19.1
instance Binary Associativity where
  get =
    do
      n <- getWord8
      case n of
        0 -> return Left
        1 -> return Non
        2 -> return Right
        _ -> fail ("Associativity: unexpected tag " ++ show n ++ " (expected 0-2). Delete canopy-stuff/ to rebuild.")

  put assoc =
    putWord8 $
      case assoc of
        Left -> 0
        Non -> 1
        Right -> 2

-- AESON JSON INSTANCES

instance Aeson.ToJSON Precedence where
  toJSON (Precedence n) = Aeson.toJSON n

instance Aeson.FromJSON Precedence where
  parseJSON value = Precedence <$> Aeson.parseJSON value

instance Aeson.ToJSON Associativity where
  toJSON assoc = Aeson.String $
    case assoc of
      Left -> "left"
      Non -> "non"
      Right -> "right"

instance Aeson.FromJSON Associativity where
  parseJSON = Aeson.withText "Associativity" $ \txt ->
    case txt of
      "left" -> pure Left
      "non" -> pure Non
      "right" -> pure Right
      _ -> fail ("Unknown associativity: " ++ show txt)

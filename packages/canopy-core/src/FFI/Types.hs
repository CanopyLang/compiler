{-# LANGUAGE OverloadedStrings #-}

-- | Canonical FFI type representation.
--
-- Single source of truth for FFI types used across the compiler —
-- by the JSDoc parser ('Foreign.FFI'), runtime validator generator
-- ('FFI.Validator'), test generator ('Foreign.TestGenerator'), and
-- JavaScript code generator ('Generate.JavaScript').
--
-- @since 0.19.2
module FFI.Types
  ( FFIType (..)

    -- * Domain newtypes for FFI identifiers
  , JsFunctionName(..)
  , PermissionName(..)
  , ResourceName(..)
  )
where

import Data.Text (Text)

-- | FFI type representation shared across all FFI subsystems.
--
-- Represents the type of a value crossing the Canopy/JavaScript boundary.
-- Used for type-safe binding generation, runtime validation, and
-- test code generation.
--
-- @since 0.19.2
data FFIType
  = FFIInt
    -- ^ Integer type (JavaScript Number with integer constraint)
  | FFIFloat
    -- ^ Floating-point type (JavaScript Number)
  | FFIString
    -- ^ String type (JavaScript String)
  | FFIBool
    -- ^ Boolean type (JavaScript Boolean)
  | FFIUnit
    -- ^ Unit type (JavaScript undefined/null)
  | FFIList !FFIType
    -- ^ List type (JavaScript Array with element validation)
  | FFIMaybe !FFIType
    -- ^ Maybe type (JavaScript null | value)
  | FFIResult !FFIType !FFIType
    -- ^ Result error value type (Canopy Result representation)
  | FFITask !FFIType !FFIType
    -- ^ Task error value type (JavaScript Promise-based)
  | FFITuple ![FFIType]
    -- ^ Tuple type (JavaScript object with positional fields)
  | FFIOpaque !Text
    -- ^ Opaque type for custom JavaScript types (e.g., DOMElement)
  | FFIFunctionType ![FFIType] !FFIType
    -- ^ Function type with parameter types and return type
  | FFIRecord ![(Text, FFIType)]
    -- ^ Record type with named fields
  deriving (Eq, Show)

-- | JavaScript function identifier.
--
-- Wraps the raw function name from JSDoc @name annotations to prevent
-- confusion with other text values (module aliases, type annotations, etc.).
--
-- @since 0.19.2
newtype JsFunctionName = JsFunctionName { unJsFunctionName :: Text }
  deriving (Eq, Ord, Show)

-- | Browser permission name (e.g., \"microphone\", \"geolocation\", \"camera\").
--
-- Used in @capability permission annotations to specify which browser
-- permissions an FFI function requires.
--
-- @since 0.19.2
newtype PermissionName = PermissionName { unPermissionName :: Text }
  deriving (Eq, Ord, Show)

-- | Browser resource name (e.g., \"AudioContext\", \"WebGLRenderingContext\").
--
-- Used in @capability init annotations to specify which browser
-- resources must be initialized before an FFI function can be called.
--
-- @since 0.19.2
newtype ResourceName = ResourceName { unResourceName :: Text }
  deriving (Eq, Ord, Show)

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

    -- * Domain newtypes for FFI content
  , JsSourcePath(..)
  , JsSource(..)

    -- * Domain newtypes for FFI bindings
  , FFIFuncName(..)
  , FFITypeAnnotation(..)
  , FFIBinding(..)
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

-- | Path to a JavaScript FFI source file.
--
-- Wraps the relative file path to prevent confusion with file content
-- or other string values in the FFI pipeline.
--
-- @since 0.19.2
newtype JsSourcePath = JsSourcePath { unJsSourcePath :: Text }
  deriving (Eq, Ord, Show)

-- | Content of a JavaScript FFI source file.
--
-- Wraps the raw file content to prevent confusion with file paths
-- or other string values in the FFI pipeline.
--
-- @since 0.19.2
newtype JsSource = JsSource { unJsSource :: Text }
  deriving (Eq, Show)

-- | FFI function name extracted from a JSDoc @name annotation.
--
-- Wraps the Canopy-side function name to prevent confusion with
-- type annotation strings, file paths, or other identifiers.
--
-- @since 0.19.2
newtype FFIFuncName = FFIFuncName { unFFIFuncName :: Text }
  deriving (Eq, Ord, Show)

-- | Canopy type annotation extracted from a JSDoc @canopy-type annotation.
--
-- Wraps the type string (e.g. @"Int -> Int -> Int"@) to prevent confusion
-- with function names, file paths, or other identifiers.
--
-- @since 0.19.2
newtype FFITypeAnnotation = FFITypeAnnotation { unFFITypeAnnotation :: Text }
  deriving (Eq, Show)

-- | A parsed FFI binding pairing a function name with its type annotation.
--
-- Replaces the stringly-typed @(String, String)@ tuples to prevent
-- accidental field swapping between function names and type annotations.
--
-- @since 0.19.2
data FFIBinding = FFIBinding
  { _bindingFuncName :: !FFIFuncName
  , _bindingTypeAnnotation :: !FFITypeAnnotation
  } deriving (Eq, Show)

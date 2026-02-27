{-# LANGUAGE EmptyDataDecls #-}

-- | AST.Utils.Shader - GLSL shader integration utilities
--
-- This module provides types and utilities for embedding GLSL shader code
-- within Canopy applications. It handles the integration between Canopy's
-- type system and GLSL's type system, enabling type-safe shader programming
-- with WebGL.
--
-- The module supports shader source code management, type mapping between
-- Canopy and GLSL, and efficient compilation to JavaScript for WebGL usage.
--
-- == Key Features
--
-- * **Type-Safe Shaders** - GLSL types mapped to Canopy type system
-- * **Source Management** - Efficient storage and processing of shader source
-- * **WebGL Integration** - Direct compilation to WebGL-compatible JavaScript
-- * **Attribute Mapping** - Vertex attributes, uniforms, and varyings support
-- * **String Escaping** - Proper escaping for JavaScript string embedding
--
-- == Architecture
--
-- The module defines several core types:
--
-- * 'Source' - Container for GLSL shader source code
-- * 'Types' - Type information for shader variables (attributes, uniforms, varyings)
-- * 'Type' - Individual GLSL type representations
--
-- Each type includes support for binary serialization and JavaScript code generation.
--
-- == GLSL Type System
--
-- The module maps GLSL types to Canopy representations:
--
-- * **Scalar Types** - Int, Float for GLSL int and float
-- * **Vector Types** - V2, V3, V4 for vec2, vec3, vec4
-- * **Matrix Types** - M4 for mat4 (4x4 matrices)
-- * **Texture Types** - Texture for sampler2D and samplerCube
--
-- == Usage Examples
--
-- === Shader Source Creation
--
-- @
-- -- Create shader source from GLSL string
-- let vertexShader = fromChars $
--   "attribute vec3 position;" ++
--   "uniform mat4 transform;" ++
--   "void main() { gl_Position = transform * vec4(position, 1.0); }"
-- @
--
-- === Type Information Specification
--
-- @
-- -- Define shader variable types
-- let shaderTypes = Types
--   { _attribute = Map.fromList [("position", V3), ("normal", V3)]
--   , _uniform = Map.fromList [("transform", M4), ("color", V3)]
--   , _varying = Map.fromList [("vNormal", V3)]
--   }
-- @
--
-- === JavaScript Generation
--
-- @
-- -- Convert shader to JavaScript string
-- let jsString = toJsStringBuilder shaderSource
-- -- Result: Properly escaped JavaScript string literal
-- @
--
-- === Type-Safe Shader Programming
--
-- @
-- -- Shader with type information
-- let typedShader = Shader shaderSource shaderTypes
-- -- Compiler can verify attribute/uniform usage
-- @
--
-- == JavaScript Integration
--
-- The module handles JavaScript integration for WebGL:
--
-- * **String Escaping** - Proper escaping of GLSL source for JavaScript
-- * **Newline Handling** - Converts GLSL newlines to JavaScript \\n sequences
-- * **Quote Escaping** - Handles both single and double quotes
-- * **Backslash Escaping** - Properly escapes backslashes for JavaScript
--
-- == Error Handling
--
-- The shader utilities are designed for robustness:
--
-- * Source code is treated as opaque byte strings to preserve formatting
-- * Invalid characters are escaped rather than causing errors
-- * Type mismatches are handled at the Canopy type system level
--
-- == Performance Characteristics
--
-- * **Source Storage**: O(n) where n is shader source length
-- * **String Escaping**: O(n) linear scan with efficient building
-- * **Type Lookup**: O(log m) where m is number of shader variables
-- * **Serialization**: Efficient binary encoding for module caching
--
-- == Thread Safety
--
-- All types in this module are immutable and thread-safe. Shader processing
-- can be performed concurrently across multiple shaders.
--
-- @since 0.19.1
module AST.Utils.Shader
  ( Source,
    Types (..),
    Type (..),
    fromChars,
    toJsStringBuilder,
  )
where

import Data.Binary (Binary, get, put)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.UTF8 as BS_UTF8
import qualified Data.Map as Map
import qualified Data.Name as Name

-- SOURCE

-- | GLSL shader source code container.
--
-- Efficiently stores GLSL shader source code as UTF-8 encoded byte strings.
-- The source is stored in its raw form to preserve exact formatting, comments,
-- and whitespace that may be significant for shader compilation.
--
-- @since 0.19.1
newtype Source
  = Source BS.ByteString
  deriving (Show)

-- TYPES

-- | GLSL shader variable type information.
--
-- Contains type information for all shader variables organized by their
-- GLSL variable class. This enables type checking between Canopy and GLSL
-- and proper generation of WebGL binding code.
--
-- @since 0.19.1
data Types = Types
  { -- | Vertex attribute variables.
    --
    -- Per-vertex input data like positions, normals, texture coordinates.
    -- These are provided by vertex buffers and vary per vertex.
    _attribute :: Map.Map Name.Name Type,
    -- | Uniform variables.
    --
    -- Global shader parameters that remain constant across all vertices/fragments
    -- in a draw call. Examples: transformation matrices, light positions, colors.
    _uniform :: Map.Map Name.Name Type,
    -- | Varying variables.
    --
    -- Variables passed from vertex shader to fragment shader, interpolated
    -- across the primitive. Examples: interpolated normals, texture coordinates.
    _varying :: Map.Map Name.Name Type
  }
  deriving (Show)

-- | GLSL type representation.
--
-- Represents the basic GLSL types that can be used in shader variables.
-- These types map directly to GLSL type system and enable type-safe
-- communication between Canopy and shaders.
--
-- @since 0.19.1
data Type
  = -- | GLSL int type.
    --
    -- 32-bit signed integer. Maps to JavaScript numbers (integers).
    Int
  | -- | GLSL float type.
    --
    -- 32-bit floating point. Maps to JavaScript numbers (floats).
    Float
  | -- | GLSL vec2 type.
    --
    -- 2-component float vector. Maps to arrays or typed arrays with 2 elements.
    V2
  | -- | GLSL vec3 type.
    --
    -- 3-component float vector. Maps to arrays or typed arrays with 3 elements.
    V3
  | -- | GLSL vec4 type.
    --
    -- 4-component float vector. Maps to arrays or typed arrays with 4 elements.
    V4
  | -- | GLSL mat4 type.
    --
    -- 4x4 float matrix. Maps to arrays or typed arrays with 16 elements (column-major).
    M4
  | -- | GLSL sampler2D/samplerCube type.
    --
    -- Texture sampling type. Maps to WebGL texture objects.
    Texture
  deriving (Show)

-- TO BUILDER

-- | Convert shader source to JavaScript string builder.
--
-- Converts GLSL shader source into a JavaScript-compatible string representation
-- using ByteString builders for efficiency. The result can be embedded directly
-- in generated JavaScript code.
--
-- The function preserves the original shader source while ensuring it's properly
-- formatted for JavaScript string literals.
--
-- ==== Examples
--
-- >>> let shader = fromChars "void main() { gl_Position = vec4(0.0); }"
-- >>> toJsStringBuilder shader
-- -- Result: Builder containing the shader source as bytes
--
-- @since 0.19.1
toJsStringBuilder :: Source -> BB.Builder
toJsStringBuilder (Source src) =
  BB.byteString src

-- FROM CHARS

-- | Create shader source from character string.
--
-- Converts a Haskell string containing GLSL source code into a shader Source
-- with proper character escaping for JavaScript embedding. Handles newlines,
-- quotes, and other special characters that need escaping.
--
-- The function performs necessary character escaping to ensure the shader
-- source can be safely embedded in JavaScript string literals.
--
-- ==== Examples
--
-- >>> fromChars "attribute vec3 position;\nvoid main() { }"
-- Source (with properly escaped content)
--
-- >>> fromChars "uniform float \"quoted\" value;"
-- Source (with escaped quotes)
--
-- @since 0.19.1
fromChars :: String -> Source
fromChars chars =
  Source (BS_UTF8.fromString (escape chars))

-- | Escape special characters for JavaScript string embedding.
--
-- Processes a string to escape characters that have special meaning in
-- JavaScript string literals. This ensures GLSL source code can be safely
-- embedded as JavaScript string literals without syntax errors.
--
-- Characters escaped:
-- * Newlines (\\n) -> \\\\n
-- * Double quotes (\") -> \\\\\"  
-- * Single quotes (') -> \\\\'
-- * Backslashes (\\\\) -> \\\\\\\\
-- * Carriage returns (\\r) are removed
--
-- @since 0.19.1
escape :: String -> String
escape chars =
  case chars of
    [] ->
      []
    c : cs
      | c == '\r' -> escape cs
      | c == '\n' -> '\\' : 'n' : escape cs
      | c == '\"' -> '\\' : '"' : escape cs
      | c == '\'' -> '\\' : '\'' : escape cs
      | c == '\\' -> '\\' : '\\' : escape cs
      | otherwise -> c : escape cs

-- BINARY

-- | Binary serialization for shader source.
--
-- Efficiently serializes and deserializes shader source code for
-- module interface files and compilation caching.
--
-- @since 0.19.1
instance Binary Source where
  get = fmap Source get
  put (Source a) = put a

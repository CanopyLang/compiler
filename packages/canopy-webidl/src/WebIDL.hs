{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | WebIDL Parser and Canopy FFI Generator
--
-- This module provides a complete WebIDL parser and code generator
-- for creating type-safe Canopy FFI bindings from Mozilla WebIDL specifications.
--
-- = Overview
--
-- The WebIDL system works in three phases:
--
-- 1. **Parse**: Read WebIDL specification files into an AST
-- 2. **Transform**: Convert WebIDL types to Canopy types
-- 3. **Generate**: Produce .can modules and JavaScript runtime
--
-- = Quick Start
--
-- @
-- import qualified WebIDL
-- import qualified WebIDL.Config as Config
--
-- main :: IO ()
-- main = do
--   -- Parse a WebIDL file
--   result <- WebIDL.parseFile "dom.webidl"
--   case result of
--     Left err -> putStrLn ("Parse error: " ++ err)
--     Right defs -> do
--       -- Generate Canopy bindings
--       WebIDL.generate Config.defaultConfig defs
-- @
--
-- = Supported WebIDL Features
--
-- * Interfaces and partial interfaces
-- * Mixins and includes statements
-- * Dictionaries and enums
-- * Operations (methods) with overloading
-- * Attributes (readonly and writable)
-- * Constructors
-- * Extended attributes
-- * Generic types (sequence, Promise, FrozenArray)
-- * Nullable types
-- * Union types
-- * Typedefs and callbacks
--
-- = Type Mapping
--
-- WebIDL types are automatically mapped to Canopy types:
--
-- * @boolean@ → @Bool@
-- * @long@, @short@, @byte@ → @Int@
-- * @float@, @double@ → @Float@
-- * @DOMString@, @USVString@ → @String@
-- * @Promise\<T\>@ → @Task x T@
-- * @T?@ (nullable) → @Maybe T@
-- * @sequence\<T\>@ → @List T@
-- * @record\<K, V\>@ → @Dict K V@
--
-- @since 0.20.0
module WebIDL
  ( -- * Parsing
    parseFile
  , parseText
  , parseFiles

    -- * Code Generation
  , generate
  , generateCanopy
  , generateJavaScript

    -- * Re-exports
  , module WebIDL.AST
  , module WebIDL.Config
  ) where

import Data.Text (Text)
import qualified Data.Text.IO as TIO

import WebIDL.AST
import WebIDL.Config
import qualified WebIDL.Parser as Parser
import qualified WebIDL.Codegen as Codegen


-- | Parse a WebIDL file
--
-- Reads the file and parses its contents into WebIDL definitions.
--
-- ==== Example
--
-- @
-- result <- parseFile "specs/dom.webidl"
-- case result of
--   Left err -> handleError err
--   Right defs -> processDefinitions defs
-- @
parseFile :: FilePath -> IO (Either String Definitions)
parseFile path = do
  content <- TIO.readFile path
  pure (parseText path content)


-- | Parse WebIDL from text
--
-- Parses the given text as WebIDL content.
--
-- ==== Example
--
-- @
-- let idl = "interface Element { attribute DOMString id; };"
-- case parseText "<input>" idl of
--   Left err -> putStrLn err
--   Right defs -> print defs
-- @
parseText :: FilePath -> Text -> Either String Definitions
parseText = Parser.parseWebIDL


-- | Parse multiple WebIDL files
--
-- Parses all given files and combines the definitions.
-- Returns an error if any file fails to parse.
parseFiles :: [FilePath] -> IO (Either String Definitions)
parseFiles paths = do
  results <- traverse parseFile paths
  pure (concat <$> sequence results)


-- | Generate Canopy bindings from WebIDL definitions
--
-- Generates both Canopy source modules (.can files) and
-- JavaScript kernel code based on the configuration.
--
-- ==== Example
--
-- @
-- config <- loadConfig "webidl-config.json"
-- defs <- parseFile "dom.webidl"
-- generate config defs
-- @
generate :: Config -> Definitions -> IO ()
generate config defs = do
  generateCanopy config defs
  generateJavaScript config defs


-- | Generate only Canopy source modules
--
-- Creates .can files for the given definitions.
generateCanopy :: Config -> Definitions -> IO ()
generateCanopy = Codegen.generateCanopyModules


-- | Generate only JavaScript kernel code
--
-- Creates JavaScript files for the runtime FFI.
generateJavaScript :: Config -> Definitions -> IO ()
generateJavaScript = Codegen.generateJavaScriptKernel

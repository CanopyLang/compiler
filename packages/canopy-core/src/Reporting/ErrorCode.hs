{-# LANGUAGE OverloadedStrings #-}

-- | Stable error code registry for the Canopy compiler.
--
-- Every error constructor in the compiler maps to exactly one 'ErrorCode'.
-- Codes are assigned in ranges by phase and never change across versions.
-- This module provides the registry, lookup, and documentation for all
-- error codes.
--
-- == Code ranges
--
-- @
-- E0100-E0199: Parse errors (Reporting.Error.Syntax)
-- E0200-E0299: Import errors (Reporting.Error.Import)
-- E0300-E0399: Name resolution errors (Reporting.Error.Canonicalize)
-- E0400-E0499: Type errors (Reporting.Error.Type)
-- E0500-E0599: Pattern matching errors (Reporting.Error.Pattern)
-- E0600-E0699: Main function errors (Reporting.Error.Main)
-- E0700-E0799: Documentation errors (Reporting.Error.Docs)
-- E0800-E0899: Optimization errors (future)
-- E0900-E0999: Code generation errors (future)
-- @
--
-- @since 0.19.2
module Reporting.ErrorCode
  ( -- * Error code construction
    parseError,
    importError,
    canonError,
    typeError,
    patternError,
    mainError,
    docsError,
    optimizeError,
    generateError,

    -- * Code descriptions
    ErrorInfo (..),
    lookupInfo,

    -- * Formatting
    formatExplanation,
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Reporting.Diagnostic (ErrorCode (..))
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc

-- | Construct a parse error code (E01xx).
parseError :: Int -> ErrorCode
parseError n = ErrorCode (100 + fromIntegral n)

-- | Construct an import error code (E02xx).
importError :: Int -> ErrorCode
importError n = ErrorCode (200 + fromIntegral n)

-- | Construct a canonicalization error code (E03xx).
canonError :: Int -> ErrorCode
canonError n = ErrorCode (300 + fromIntegral n)

-- | Construct a type error code (E04xx).
typeError :: Int -> ErrorCode
typeError n = ErrorCode (400 + fromIntegral n)

-- | Construct a pattern error code (E05xx).
patternError :: Int -> ErrorCode
patternError n = ErrorCode (500 + fromIntegral n)

-- | Construct a main error code (E06xx).
mainError :: Int -> ErrorCode
mainError n = ErrorCode (600 + fromIntegral n)

-- | Construct a docs error code (E07xx).
docsError :: Int -> ErrorCode
docsError n = ErrorCode (700 + fromIntegral n)

-- | Construct an optimization error code (E08xx).
optimizeError :: Int -> ErrorCode
optimizeError n = ErrorCode (800 + fromIntegral n)

-- | Construct a code generation error code (E09xx).
generateError :: Int -> ErrorCode
generateError n = ErrorCode (900 + fromIntegral n)

-- | Information about a specific error code.
data ErrorInfo = ErrorInfo
  { _infoTitle :: !Text,
    _infoSummary :: !Text,
    _infoExplanation :: !Text
  }
  deriving (Eq, Show)

-- | Look up extended documentation for an error code.
--
-- Returns 'Nothing' if the code is not yet documented.
lookupInfo :: ErrorCode -> Maybe ErrorInfo
lookupInfo code = Map.lookup code errorCatalog

-- | Format the full explanation for @canopy explain E0xxx@.
--
-- Produces a colored 'Doc.Doc' with the error title, code, summary,
-- and extended explanation using the Reporting.Doc color system.
formatExplanation :: ErrorCode -> Doc.Doc
formatExplanation code =
  case lookupInfo code of
    Nothing ->
      Doc.stack
        [ Doc.dullcyan (Doc.fromChars ("-- " <> codeStr)),
          "",
          Doc.reflow ("Error " <> codeStr <> " is not yet documented."),
          Doc.reflow "Please report this at https://github.com/quinten/canopy/issues"
        ]
    Just info ->
      Doc.stack
        [ Doc.dullcyan (Doc.fromChars ("-- " <> Text.unpack (_infoTitle info) <> " [" <> codeStr <> "]")),
          "",
          Doc.reflow (Text.unpack (_infoSummary info)),
          "",
          Doc.fromChars (Text.unpack (_infoExplanation info))
        ]
  where
    codeStr = Text.unpack (Diag.errorCodeToText code)

-- | The error catalog with extended documentation per code.
--
-- This is populated incrementally as error codes are assigned.
errorCatalog :: Map.Map ErrorCode ErrorInfo
errorCatalog =
  Map.fromList
    [ -- Parse errors
      ( parseError 0,
        ErrorInfo
          "MODULE NAME UNSPECIFIED"
          "A module file is missing its module declaration."
          "Every Canopy file must start with a module declaration that matches its file path.\n\
          \For example, a file at src/Main.can should start with:\n\
          \\n\
          \    module Main exposing (..)\n\
          \\n\
          \The module name must match the file path exactly."
      ),
      ( parseError 1,
        ErrorInfo
          "MODULE NAME MISMATCH"
          "The module declaration does not match the file path."
          "The module name in the declaration must match the file path.\n\
          \For example, if the file is at src/Page/Home.can, the module\n\
          \declaration must be:\n\
          \\n\
          \    module Page.Home exposing (..)\n\
          \\n\
          \Rename either the file or the module declaration to match."
      ),
      ( parseError 2,
        ErrorInfo
          "UNEXPECTED PORT"
          "A port declaration was found in a non-port module."
          "Port declarations can only appear in modules declared with\n\
          \`port module`. Change your module declaration to:\n\
          \\n\
          \    port module MyModule exposing (..)"
      ),
      ( parseError 10,
        ErrorInfo
          "PARSE ERROR"
          "The parser encountered unexpected syntax."
          "This is a general parse error. Check for:\n\
          \  - Missing parentheses or brackets\n\
          \  - Incorrect indentation\n\
          \  - Reserved words used as identifiers\n\
          \  - Missing operators between expressions"
      ),
      -- Import errors
      ( importError 0,
        ErrorInfo
          "MODULE NOT FOUND"
          "An imported module could not be found."
          "Check that:\n\
          \  1. The module name is spelled correctly\n\
          \  2. The package containing the module is listed in dependencies\n\
          \  3. The source directory containing the module is listed in source-directories\n\
          \\n\
          \Run `canopy install <package>` to add missing dependencies."
      ),
      ( importError 1,
        ErrorInfo
          "AMBIGUOUS IMPORT"
          "Multiple modules with the same name were found."
          "This happens when the same module name exists in multiple packages\n\
          \or source directories. Rename one of the conflicting modules to\n\
          \resolve the ambiguity."
      ),
      -- Type errors
      ( typeError 0,
        ErrorInfo
          "TYPE MISMATCH"
          "An expression has a different type than expected."
          "The compiler found a type mismatch between what was expected\n\
          \and what was actually provided. Common causes:\n\
          \  - Wrong argument type to a function\n\
          \  - Branches of if/case returning different types\n\
          \  - Annotation doesn't match implementation\n\
          \\n\
          \Read the expected and actual types carefully. The error will\n\
          \point to the specific location of the mismatch."
      ),
      ( typeError 1,
        ErrorInfo
          "TYPE MISMATCH IN PATTERN"
          "A pattern has a different type than expected."
          "The type of a pattern does not match what is being matched.\n\
          \This often happens when using the wrong constructor or\n\
          \when pattern matching on the wrong type."
      ),
      ( typeError 2,
        ErrorInfo
          "INFINITE TYPE"
          "A type refers to itself infinitely."
          "The compiler detected a type that would be infinitely recursive.\n\
          \This usually means a function is being applied to itself, or a\n\
          \value is being used in a way that creates a circular type.\n\
          \\n\
          \Add a type annotation to help identify where the issue is."
      ),
      -- Pattern errors
      ( patternError 0,
        ErrorInfo
          "MISSING PATTERNS"
          "A case expression does not cover all possibilities."
          "Every case expression must handle all possible values of the\n\
          \type being matched. Add branches for the missing patterns.\n\
          \\n\
          \If you want to write the implementation later, use Debug.todo\n\
          \as a placeholder."
      ),
      ( patternError 1,
        ErrorInfo
          "REDUNDANT PATTERN"
          "A pattern can never be reached."
          "This pattern will never match because a previous pattern already\n\
          \covers all the cases it would handle. Remove the redundant pattern."
      ),
      -- Main errors
      ( mainError 0,
        ErrorInfo
          "BAD MAIN TYPE"
          "The main value has an unsupported type."
          "The `main` value must be one of:\n\
          \  - Html msg\n\
          \  - Svg msg\n\
          \  - Program flags model msg\n\
          \\n\
          \Change `main` to produce one of these types."
      ),
      ( mainError 1,
        ErrorInfo
          "BAD MAIN"
          "The main value is defined recursively."
          "The `main` value cannot be defined in terms of itself.\n\
          \It must be a simple value without recursion."
      ),
      ( mainError 2,
        ErrorInfo
          "BAD FLAGS"
          "The main program has an invalid flags type."
          "Flags passed to your program from JavaScript must use\n\
          \supported types: Ints, Floats, Bools, Strings, Maybes,\n\
          \Lists, Arrays, tuples, records, and JSON values."
      ),
      -- Canonicalization errors
      ( canonError 0,
        ErrorInfo
          "BAD TYPE ANNOTATION"
          "A type annotation has fewer arguments than the definition."
          "The number of arguments in the type annotation must match\n\
          \the number of arguments in the definition. Add missing\n\
          \arguments to the annotation or remove extra arguments\n\
          \from the definition."
      ),
      ( canonError 1,
        ErrorInfo
          "AMBIGUOUS NAME"
          "A variable name is ambiguous between multiple imports."
          "Multiple imported modules expose a value with this name.\n\
          \Use a qualified name (e.g., Module.name) to disambiguate."
      ),
      ( canonError 5,
        ErrorInfo
          "BAD ARITY"
          "A type or pattern has the wrong number of arguments."
          "Check that you are providing the correct number of type\n\
          \arguments. Each type parameter in the definition needs\n\
          \a corresponding argument at the use site."
      ),
      ( canonError 6,
        ErrorInfo
          "INFIX PROBLEM"
          "Two operators cannot be mixed without parentheses."
          "When using different operators together, you need\n\
          \parentheses to clarify the grouping. For example:\n\
          \\n\
          \    (a + b) * c    -- clear grouping\n\
          \    a + b * c      -- ambiguous"
      ),
      ( canonError 7,
        ErrorInfo
          "DUPLICATE DECLARATION"
          "Two top-level declarations have the same name."
          "Each name in a module must be unique. Rename one of\n\
          \the conflicting declarations."
      ),
      ( canonError 24,
        ErrorInfo
          "NAME NOT FOUND"
          "A referenced name is not in scope."
          "Check that:\n\
          \  1. The name is spelled correctly\n\
          \  2. The module providing it is imported\n\
          \  3. The name is listed in the import's exposing clause"
      ),
      ( canonError 28,
        ErrorInfo
          "RECORD CONSTRUCTOR IN PATTERN"
          "A record type alias constructor was used in a pattern."
          "Record constructors cannot be used in pattern matching.\n\
          \Use record field access or destructuring instead."
      ),
      ( canonError 31,
        ErrorInfo
          "RECURSIVE ALIAS"
          "A type alias refers to itself."
          "Type aliases cannot be recursive. Use a custom type\n\
          \(type with constructors) instead of a type alias for\n\
          \recursive data structures."
      ),
      ( canonError 32,
        ErrorInfo
          "RECURSIVE DECLARATION"
          "A value definition refers to itself without a function."
          "Only functions can be recursive. If you need a recursive\n\
          \value, wrap it in a function."
      ),
      ( canonError 34,
        ErrorInfo
          "SHADOWING"
          "A name shadows a previously defined name."
          "Using the same name in a nested scope hides the outer\n\
          \definition. Rename one of them to avoid confusion."
      ),
      ( canonError 35,
        ErrorInfo
          "TUPLE TOO LARGE"
          "A tuple has more than three elements."
          "Canopy tuples can have at most three elements. Use a\n\
          \record or custom type for more fields."
      ),
      -- Docs errors
      ( docsError 0,
        ErrorInfo
          "NO DOCS"
          "A published module is missing its documentation comment."
          "Every published module must have a documentation comment\n\
          \between the module declaration and the imports.\n\
          \\n\
          \Learn more at <https://package.canopy-lang.org/help/documentation-format>"
      ),
      ( docsError 1,
        ErrorInfo
          "IMPLICIT EXPOSING"
          "A published module uses exposing (..) instead of an explicit list."
          "Published packages must explicitly list what they expose.\n\
          \Replace exposing (..) with an explicit exposing list."
      ),
      -- Import errors (additional)
      ( importError 2,
        ErrorInfo
          "AMBIGUOUS LOCAL IMPORT"
          "A module name appears in multiple source directories."
          "The same module name exists in multiple source-directories.\n\
          \Rename one of the files so each module name is unique."
      ),
      ( importError 3,
        ErrorInfo
          "AMBIGUOUS FOREIGN IMPORT"
          "A module name appears in multiple packages."
          "Multiple packages in your dependencies expose a module\n\
          \with this name. Remove one of the conflicting packages\n\
          \from your dependencies."
      ),
      -- Parse errors (additional)
      ( parseError 3,
        ErrorInfo
          "NO PORTS"
          "A port module has no port declarations."
          "If you declare a module as `port module`, it must contain\n\
          \at least one port declaration."
      ),
      ( parseError 4,
        ErrorInfo
          "NO PORTS IN PACKAGE"
          "A port declaration appears in a published package."
          "Ports are not allowed in published packages. They can only\n\
          \be used in applications."
      ),
      ( parseError 5,
        ErrorInfo
          "NO PORT MODULES IN PACKAGE"
          "A port module appears in a published package."
          "Port modules are not allowed in published packages."
      ),
      -- Lazy import errors
      ( canonError 44,
        ErrorInfo
          "LAZY IMPORT NOT FOUND"
          "A lazy import references a module that does not exist."
          "The module specified in a `lazy import` declaration cannot be found\n\
          \in your dependencies or source directories. Check that:\n\
          \  1. The module name is spelled correctly\n\
          \  2. The package containing the module is listed in dependencies\n\
          \  3. The source file exists in one of your source-directories"
      ),
      ( canonError 45,
        ErrorInfo
          "BAD LAZY IMPORT"
          "A core/stdlib module cannot be lazy-imported."
          "Core modules like Basics, List, Maybe, Result, String, Char, Tuple,\n\
          \Platform, Cmd, and Sub are always loaded eagerly because they are\n\
          \required by every Canopy program. Remove the `lazy` keyword from\n\
          \this import."
      ),
      ( canonError 46,
        ErrorInfo
          "BAD LAZY IMPORT"
          "Lazy imports are not allowed in packages."
          "Lazy imports enable code splitting, which only works in applications.\n\
          \Packages must use regular imports so their code can be bundled\n\
          \correctly by the application that depends on them. Remove the\n\
          \`lazy` keyword from this import."
      ),
      ( canonError 47,
        ErrorInfo
          "BAD LAZY IMPORT"
          "A module cannot lazy-import itself."
          "A module cannot lazily load itself because it is already being loaded.\n\
          \Self-imports are nonsensical. Remove the `lazy` keyword or remove\n\
          \the import entirely."
      ),
      ( canonError 48,
        ErrorInfo
          "BAD LAZY IMPORT"
          "An internal kernel module cannot be lazy-imported."
          "Kernel modules are internal to the Canopy runtime and are always\n\
          \loaded eagerly. They cannot be lazy-imported. Remove the `lazy`\n\
          \keyword from this import."
      )
    ]

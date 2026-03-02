{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Predefined name constants for the Canopy compiler.
--
-- This module provides all predefined name constants used throughout the
-- Canopy compiler. These names represent:
--
-- * Built-in type names (Int, Float, Bool, etc.)
-- * Standard library module and function names
-- * Special compiler-generated names
-- * Platform and runtime-specific identifiers
-- * REPL-specific names
--
-- All constants are created lazily using NOINLINE pragmas to ensure they
-- are shared across the entire compilation process, improving memory usage
-- and performance.
--
-- === Built-in Types
--
-- The module provides constants for all built-in Canopy types like Int, Float,
-- Bool, Char, String, Maybe, Result, List, Array, Dict, and more.
--
-- === Standard Library
--
-- Constants for standard library modules and common functions are provided,
-- including platform-specific names for JavaScript interop and debugging.
--
-- === Usage Examples
--
-- @
-- -- Use predefined type names
-- when (typeName == int) $
--   processIntType
--
-- -- Check for special functions
-- if functionName == _main
--   then compileMainFunction
--   else compileRegularFunction
--
-- -- Work with standard library names
-- let maybeModule = maybe
--     listType = list
-- @
--
-- @since 0.19.1
module Canopy.Data.Name.Constants
  ( -- * Basic Types
    int,
    float,
    bool,
    char,
    string,

    -- * Container Types
    maybe,
    result,
    list,
    array,
    dict,
    tuple,
    jsArray,

    -- * Platform Types
    task,
    router,
    cmd,
    sub,
    platform,
    virtualDom,

    -- * Utility Types
    shader,
    debug,
    debugger,
    bitwise,
    basics,
    capability,

    -- * Test Types
    browserTest,

    -- * Special Names
    utils,
    negate,
    append,
    true,
    false,
    value,
    node,
    program,
    _main,
    _Main,
    dollar,
    identity,
    and_,
    or_,
    not_,

    -- * REPL Names
    replModule,
    replValueToPrint,
  )
where

import Canopy.Data.Name.Core (Name, fromChars)
import Prelude hiding (maybe, negate)

-- BASIC TYPES

{-# NOINLINE int #-}
int :: Name
int = fromChars "Int"

{-# NOINLINE float #-}
float :: Name
float = fromChars "Float"

{-# NOINLINE bool #-}
bool :: Name
bool = fromChars "Bool"

{-# NOINLINE char #-}
char :: Name
char = fromChars "Char"

{-# NOINLINE string #-}
string :: Name
string = fromChars "String"

-- CONTAINER TYPES

{-# NOINLINE maybe #-}
maybe :: Name
maybe = fromChars "Maybe"

{-# NOINLINE result #-}
result :: Name
result = fromChars "Result"

{-# NOINLINE list #-}
list :: Name
list = fromChars "List"

{-# NOINLINE array #-}
array :: Name
array = fromChars "Array"

{-# NOINLINE dict #-}
dict :: Name
dict = fromChars "Dict"

{-# NOINLINE tuple #-}
tuple :: Name
tuple = fromChars "Tuple"

{-# NOINLINE jsArray #-}
jsArray :: Name
jsArray = fromChars "JsArray"

-- PLATFORM TYPES

{-# NOINLINE task #-}
task :: Name
task = fromChars "Task"

{-# NOINLINE router #-}
router :: Name
router = fromChars "Router"

{-# NOINLINE cmd #-}
cmd :: Name
cmd = fromChars "Cmd"

{-# NOINLINE sub #-}
sub :: Name
sub = fromChars "Sub"

{-# NOINLINE platform #-}
platform :: Name
platform = fromChars "Platform"

{-# NOINLINE virtualDom #-}
virtualDom :: Name
virtualDom = fromChars "VirtualDom"

-- UTILITY TYPES

{-# NOINLINE shader #-}
shader :: Name
shader = fromChars "Shader"

{-# NOINLINE debug #-}
debug :: Name
debug = fromChars "Debug"

{-# NOINLINE debugger #-}
debugger :: Name
debugger = fromChars "Debugger"

{-# NOINLINE bitwise #-}
bitwise :: Name
bitwise = fromChars "Bitwise"

{-# NOINLINE basics #-}
basics :: Name
basics = fromChars "Basics"

{-# NOINLINE capability #-}
capability :: Name
capability = fromChars "Capability"

-- TEST TYPES

{-# NOINLINE browserTest #-}
browserTest :: Name
browserTest = fromChars "BrowserTest"

-- SPECIAL NAMES

{-# NOINLINE utils #-}
utils :: Name
utils = fromChars "Utils"

{-# NOINLINE negate #-}
negate :: Name
negate = fromChars "negate"

{-# NOINLINE append #-}
append :: Name
append = fromChars "append"

{-# NOINLINE true #-}
true :: Name
true = fromChars "True"

{-# NOINLINE false #-}
false :: Name
false = fromChars "False"

{-# NOINLINE value #-}
value :: Name
value = fromChars "Value"

{-# NOINLINE node #-}
node :: Name
node = fromChars "Node"

{-# NOINLINE program #-}
program :: Name
program = fromChars "Program"

{-# NOINLINE _main #-}
_main :: Name
_main = fromChars "main"

{-# NOINLINE _Main #-}
_Main :: Name
_Main = fromChars "Main"

{-# NOINLINE dollar #-}
dollar :: Name
dollar = fromChars "$"

{-# NOINLINE identity #-}
identity :: Name
identity = fromChars "identity"

{-# NOINLINE and_ #-}

-- | Name constant for the boolean @and@ function from Basics.
--
-- Used in optimization passes to recognize @&&@ operations for
-- boolean simplification (short-circuit evaluation, constant folding).
--
-- @since 0.19.2
and_ :: Name
and_ = fromChars "and"

{-# NOINLINE or_ #-}

-- | Name constant for the boolean @or@ function from Basics.
--
-- Used in optimization passes to recognize @||@ operations for
-- boolean simplification (short-circuit evaluation, constant folding).
--
-- @since 0.19.2
or_ :: Name
or_ = fromChars "or"

{-# NOINLINE not_ #-}

-- | Name constant for the boolean @not@ function from Basics.
--
-- Used in optimization passes to recognize @not@ applications for
-- double negation elimination.
--
-- @since 0.19.2
not_ :: Name
not_ = fromChars "not"

-- REPL NAMES

{-# NOINLINE replModule #-}
replModule :: Name
replModule = fromChars "Canopy_Repl"

{-# NOINLINE replValueToPrint #-}
replValueToPrint :: Name
replValueToPrint = fromChars "repl_input_value_"

{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Name handling for the Canopy compiler.
--
-- This module provides a unified interface for all name operations in the
-- Canopy compiler. It re-exports functionality from specialized sub-modules:
--
-- * "Data.Name.Core" - Basic name operations and type definitions
-- * "Data.Name.Kernel" - Kernel name processing and type checking
-- * "Data.Name.TypeVariable" - Type variable name generation
-- * "Data.Name.Generation" - Complex name generation and combination
-- * "Data.Name.Constants" - Predefined name constants
--
-- Names in Canopy are represented as UTF-8 encoded byte arrays for efficient
-- memory usage and fast string operations. The Name type is used throughout
-- the compiler for identifiers, module names, type names, and more.
--
-- === Usage Examples
--
-- @
-- -- Basic name operations
-- let name = fromChars "myFunction"
--     chars = toChars name
--
-- -- Check for kernel operations
-- when (isKernel name) $ do
--   let kernelName = getKernel name
--   processKernelOperation kernelName
--
-- -- Generate type variables
-- let typeVar = fromTypeVariableScheme 0  -- "a"
--     indexVar = fromVarIndex 1           -- "_v1"
--
-- -- Use predefined constants
-- when (typeName == int) $
--   applyIntTypeRules
-- @
--
-- @since 0.19.1
module Data.Name
  ( Name,
    CANOPY_NAME,

    -- * Core Operations
    toChars,
    toCanopyString,
    toBuilder,
    fromPtr,
    fromChars,
    hasDot,
    splitDots,

    -- * Kernel Operations
    getKernel,
    isKernel,
    isNumberType,
    isComparableType,
    isAppendableType,
    isCompappendType,

    -- * Type Variable Generation
    fromVarIndex,
    fromTypeVariable,
    fromTypeVariableScheme,

    -- * Name Generation
    fromManyNames,
    fromWords,
    sepBy,

    -- * Predefined Constants
    int,
    float,
    bool,
    char,
    string,
    maybe,
    result,
    list,
    array,
    dict,
    tuple,
    jsArray,
    task,
    router,
    cmd,
    sub,
    platform,
    virtualDom,
    shader,
    debug,
    debugger,
    bitwise,
    basics,
    utils,
    negate,
    true,
    false,
    value,
    node,
    program,
    _main,
    _Main,
    dollar,
    identity,
    replModule,
    replValueToPrint,
  )
where

-- Re-export all functionality from sub-modules

import Data.Name.Constants
import Data.Name.Core
import Data.Name.Generation
import Data.Name.Kernel
import Data.Name.TypeVariable
import Prelude hiding (maybe, negate)

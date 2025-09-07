{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Kernel name processing for the Canopy compiler.
--
-- This module provides functionality for working with kernel names, which are
-- special built-in operations that interface with JavaScript runtime. It handles:
--
-- * Kernel name detection and validation
-- * Kernel name extraction from qualified names
-- * Type checking for special compiler-known types
-- * Prefix matching for built-in type categories
--
-- Kernel names use special prefixes like "Canopy.Kernel." or "Elm.Kernel."
-- to identify JavaScript interop functions and built-in type operations.
--
-- === Usage Examples
--
-- @
-- -- Check if a name is a kernel operation
-- if isKernel someName
--   then let kernelName = getKernel someName
--        in processKernelOperation kernelName
--   else processRegularFunction someName
--
-- -- Check for special type categories
-- when (isNumberType typeName) $
--   applyNumberTypeRules typeName
-- @
--
-- @since 0.19.1
module Data.Name.Kernel
  ( -- * Kernel Operations
    getKernel,
    isKernel,

    -- * Type Checking
    isNumberType,
    isComparableType,
    isAppendableType,
    isCompappendType,
  )
where

import Control.Exception (assert)
import Data.Name.Core (Name)
import qualified Data.Utf8 as Utf8
import GHC.Prim
import GHC.ST (ST (ST), runST)

-- GET KERNEL

getKernel :: Name -> Name
getKernel name@(Utf8.Utf8 ba#) =
  assert (isKernel name) (extractKernelName name ba#)

extractKernelName :: Name -> ByteArray# -> Name
extractKernelName name ba# =
  runST (copyKernelBytes ba# prefixLen#)
  where
    -- "Canopy.Kernel." = 14 chars, "Elm.Kernel." = 11 chars
    !prefixLen# = if Utf8.startsWith prefixKernel name then 14# else 11#

copyKernelBytes :: ByteArray# -> Int# -> ST s Name
copyKernelBytes ba# prefixLen# =
  ST $ \s ->
    case newByteArray# size# s of
      (# s, mba# #) ->
        case copyByteArray# ba# prefixLen# mba# 0# size# s of
          s ->
            case unsafeFreezeByteArray# mba# s of
              (# s, ba# #) -> (# s, Utf8.Utf8 ba# #)
  where
    !size# = sizeofByteArray# ba# -# prefixLen#

-- STARTS WITH

isKernel :: Name -> Bool
isKernel name = Utf8.startsWith prefixKernel name || Utf8.startsWith prefixElmKernel name

isNumberType :: Name -> Bool
isNumberType = Utf8.startsWith prefixNumber

isComparableType :: Name -> Bool
isComparableType = Utf8.startsWith prefixComparable

isAppendableType :: Name -> Bool
isAppendableType = Utf8.startsWith prefixAppendable

isCompappendType :: Name -> Bool
isCompappendType = Utf8.startsWith prefixCompappend

-- PREFIXES

{-# NOINLINE prefixKernel #-}
prefixKernel :: Name
prefixKernel = Utf8.fromChars "Canopy.Kernel."

{-# NOINLINE prefixElmKernel #-}
prefixElmKernel :: Name
prefixElmKernel = Utf8.fromChars "Elm.Kernel."

{-# NOINLINE prefixNumber #-}
prefixNumber :: Name
prefixNumber = Utf8.fromChars "number"

{-# NOINLINE prefixComparable #-}
prefixComparable :: Name
prefixComparable = Utf8.fromChars "comparable"

{-# NOINLINE prefixAppendable #-}
prefixAppendable :: Name
prefixAppendable = Utf8.fromChars "appendable"

{-# NOINLINE prefixCompappend #-}
prefixCompappend :: Name
prefixCompappend = Utf8.fromChars "compappend"

{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Complex name generation for the Canopy compiler.
--
-- This module provides functionality for generating complex names from multiple
-- sources and creating specialized name combinations. It handles:
--
-- * Generation of unique names from multiple input names
-- * Creation of names from raw word sequences
-- * Name combination with separators
-- * Special encoding for JavaScript-compatible identifiers
--
-- Multi-name generation creates unique identifiers by combining names in ways
-- that are valid in JavaScript but not in Canopy, ensuring no conflicts with
-- user-defined names. This is crucial for:
--
-- * Top-level cycle names that must be distinct
-- * Destructuring pattern names like (x,y)
-- * Internal compiler-generated identifiers
--
-- === Usage Examples
--
-- @
-- -- Create unique name from multiple names
-- let names = [fromChars "foo", fromChars "bar", fromChars "baz"]
--     uniqueName = fromManyNames names  -- "_M$foo"
--
-- -- Create name from raw bytes
-- let rawName = fromWords [0x74, 0x65, 0x73, 0x74]  -- "test"
--
-- -- Combine names with separator
-- let name1 = fromChars "Module"
--     name2 = fromChars "function"
--     combined = sepBy 0x2E name1 name2  -- "Module.function"
-- @
--
-- @since 0.19.1
module Data.Name.Generation
  ( -- * Multi-Name Generation
    fromManyNames,

    -- * Raw Name Creation
    fromWords,

    -- * Name Combination
    sepBy,
  )
where

import qualified Data.List as List
import Data.Name.Core (Name)
import qualified Data.Utf8 as Utf8
import GHC.Exts
  ( Int (I#),
  )
import GHC.Prim
import GHC.ST (ST (ST), runST)
import GHC.Word (Word8 (W8#))

-- FROM MANY NAMES
--
-- Creating a unique name by combining all the subnames can create names
-- longer than 256 bytes relatively easily. So instead, the first given name
-- (e.g. foo) is prefixed chars that are valid in JS but not Canopy (e.g. _M$foo)
--
-- This should be a unique name since 0.19 disallows shadowing. It would not
-- be possible for multiple top-level cycles to include values with the same
-- name, so the important thing is to make the cycle name distinct from the
-- normal name. Same logic for destructuring patterns like (x,y)

fromManyNames :: [Name] -> Name
fromManyNames names =
  case names of
    [] -> blank
    -- NOTE: this case is needed for (let _ = Debug.log "x" x in ...)
    -- but maybe unused patterns should be stripped out instead
    Utf8.Utf8 ba# : _ -> buildUniqueNameWithPrefix ba#

buildUniqueNameWithPrefix :: ByteArray# -> Name
buildUniqueNameWithPrefix ba# =
  runST (createPrefixedName ba# len#)
  where
    len# = sizeofByteArray# ba#

createPrefixedName :: ByteArray# -> Int# -> ST s Name
createPrefixedName ba# len# =
  ST $ \s ->
    case newByteArray# (len# +# 3#) s of
      (# s, mba# #) ->
        case writePrefixBytes mba# s of
          s ->
            case copyByteArray# ba# 0# mba# 3# len# s of
              s ->
                case unsafeFreezeByteArray# mba# s of
                  (# s, ba# #) -> (# s, Utf8.Utf8 ba# #)

writePrefixBytes :: MutableByteArray# s -> State# s -> State# s
writePrefixBytes mba# s =
  case writeWord8Array# mba# 0# (wordToWord8# 0x5F## {-_-}) s of
    s ->
      case writeWord8Array# mba# 1# (wordToWord8# 0x4D## {-M-}) s of
        s ->
          writeWord8Array# mba# 2# (wordToWord8# 0x24##) s

{-# NOINLINE blank #-}
blank :: Name
blank =
  fromWords [0x5F, 0x4D, 0x24]

-- FROM WORDS

fromWords :: [Word8] -> Name
fromWords words =
  runST
    ( do
        mba <- newByteArray (List.length words)
        writeWords mba 0 words
        freeze mba
    )

writeWords :: MBA s -> Int -> [Word8] -> ST s ()
writeWords !mba !i words =
  case words of
    [] ->
      return ()
    w : ws ->
      do
        writeWord8 mba i w
        writeWords mba (i + 1) ws

-- SEP BY

sepBy :: Word8 -> Name -> Name -> Name
sepBy (W8# sep#) (Utf8.Utf8 ba1#) (Utf8.Utf8 ba2#) =
  let !len1# = sizeofByteArray# ba1#
      !len2# = sizeofByteArray# ba2#
   in runST
        ( ST $ \s ->
            case newByteArray# (len1# +# len2# +# 1#) s of
              (# s, mba# #) ->
                case copyByteArray# ba1# 0# mba# 0# len1# s of
                  s ->
                    case writeWord8Array# mba# len1# sep# s of
                      s ->
                        case copyByteArray# ba2# 0# mba# (len1# +# 1#) len2# s of
                          s ->
                            case unsafeFreezeByteArray# mba# s of
                              (# s, ba# #) -> (# s, Utf8.Utf8 ba# #)
        )

-- PRIMITIVES

data MBA s
  = MBA# (MutableByteArray# s)

{-# INLINE newByteArray #-}
newByteArray :: Int -> ST s (MBA s)
newByteArray (I# len#) =
  ST $ \s ->
    case newByteArray# len# s of
      (# s, mba# #) -> (# s, MBA# mba# #)

{-# INLINE freeze #-}
freeze :: MBA s -> ST s Name
freeze (MBA# mba#) =
  ST $ \s ->
    case unsafeFreezeByteArray# mba# s of
      (# s, ba# #) -> (# s, Utf8.Utf8 ba# #)

{-# INLINE writeWord8 #-}
writeWord8 :: MBA s -> Int -> Word8 -> ST s ()
writeWord8 (MBA# mba#) (I# offset#) (W8# w#) =
  ST $ \s ->
    case writeWord8Array# mba# offset# w# s of
      s -> (# s, () #)

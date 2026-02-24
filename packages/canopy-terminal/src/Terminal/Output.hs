{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Terminal.Output - Typed output helpers for CLI messages.
--
-- Provides reusable functions for common CLI output patterns such as
-- count-based messages, status lines, and error reports. Eliminates
-- scattered @++ show@ concatenation across terminal modules.
--
-- == Usage
--
-- @
-- import qualified Terminal.Output as Output
--
-- Output.putCount "Found" 5 "FFI module"
-- -- prints: "Found 5 FFI modules"
--
-- Output.putStatus "Generated" "test.can"
-- -- prints: "Generated: test.can"
-- @
--
-- @since 0.19.1
module Terminal.Output
  ( -- * Count Messages
    showCount,
    countWord,

    -- * List Formatting
    joinComma,
  )
where

import qualified Data.List as List

-- | Format a count with a noun, pluralizing automatically.
--
-- >>> showCount 1 "module"
-- "1 module"
--
-- >>> showCount 5 "module"
-- "5 modules"
--
-- @since 0.19.1
showCount :: Int -> String -> String
showCount n noun = show n ++ " " ++ countWord n noun

-- | Pluralize a noun based on the count.
--
-- >>> countWord 1 "file"
-- "file"
--
-- >>> countWord 0 "file"
-- "files"
--
-- @since 0.19.1
countWord :: Int -> String -> String
countWord 1 noun = noun
countWord _ noun = noun ++ "s"

-- | Format a list of strings as a comma-separated string.
--
-- >>> joinComma ["foo", "bar", "baz"]
-- "foo, bar, baz"
--
-- @since 0.19.1
joinComma :: [String] -> String
joinComma = List.intercalate ", "

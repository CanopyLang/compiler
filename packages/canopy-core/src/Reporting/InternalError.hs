{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Internal compiler error reporting.
--
-- Replaces crash-inducing @error@ calls with structured diagnostics
-- that produce helpful output instead of raw Haskell stack traces.
-- When the compiler encounters an invariant violation (a state that
-- "should never happen"), this module ensures the user sees:
--
--   * A clear "INTERNAL COMPILER ERROR" header
--   * The location within the compiler source
--   * A description of what went wrong
--   * A request to report the bug
--
-- == Usage
--
-- Replace every @error "msg"@ with:
--
-- @
-- import qualified Reporting.InternalError as InternalError
--
-- InternalError.report
--   "Optimize.Port.toEncoder"
--   "function type reached port encoder"
--   "This indicates a type checker bug — functions should be rejected before reaching port encoding."
-- @
--
-- @since 0.19.2
module Reporting.InternalError
  ( -- * Types
    InternalError (..),

    -- * Reporting
    report,
    reportPure,
  )
where

import qualified Data.Text as Text
import Data.Text (Text)

-- | Structured internal compiler error.
--
-- Captures the source location within the compiler, a brief description
-- of the invariant violation, and additional context for bug reports.
--
-- @since 0.19.2
data InternalError = InternalError
  { -- | Compiler source location, e.g. @"Optimize.Port.toEncoder"@
    _ieLocation :: !Text,
    -- | Brief description of the invariant violation
    _ieMessage :: !Text,
    -- | Additional context explaining why this should never happen
    _ieContext :: !Text
  }
  deriving (Eq, Show)

-- | Report an internal compiler error to stderr and terminate.
--
-- Produces output like:
--
-- @
-- ══════════════════════════════════════════════════
-- INTERNAL COMPILER ERROR in Optimize.Port.toEncoder
-- ══════════════════════════════════════════════════
--
-- function type reached port encoder
--
-- This indicates a type checker bug — functions should be
-- rejected before reaching port encoding.
--
-- Please report this bug at:
--   https://github.com/canopy-lang/canopy/issues
--
-- Include the source file that triggered this error.
-- ══════════════════════════════════════════════════
-- @
--
-- @since 0.19.2
report :: Text -> Text -> Text -> a
report location message context =
  reportPure (InternalError location message context)

-- | Report from a pre-constructed 'InternalError' value.
--
-- Terminates the program after printing the diagnostic to stderr.
-- Uses 'error' internally so GHC treats this as divergent, but the
-- output is a structured diagnostic instead of a raw stack trace.
--
-- @since 0.19.2
reportPure :: InternalError -> a
reportPure (InternalError location message context) =
  error (Text.unpack rendered)
  where
    rendered =
      Text.concat
        [ separator,
          "\nINTERNAL COMPILER ERROR in ",
          location,
          "\n",
          separator,
          "\n\n",
          message,
          "\n\n",
          context,
          "\n\nPlease report this bug at:",
          "\n  https://github.com/canopy-lang/canopy/issues",
          "\n\nInclude the source file that triggered this error.",
          "\n",
          separator,
          "\n"
        ]
    separator = Text.replicate 50 "═"

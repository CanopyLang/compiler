{-# LANGUAGE OverloadedStrings #-}

-- | Internal compiler error reporting and recovery.
--
-- Provides two layers of internal error handling:
--
-- 1. __Structured crash diagnostics__: 'report' replaces raw @error@ calls
--    with formatted output showing the compiler source location, a
--    description, and instructions for filing a bug report.
--
-- 2. __Graceful recovery__: 'catchInternalError' wraps an 'IO' action so
--    that any 'ErrorCall' thrown by 'report' is caught and returned as a
--    'Left' value instead of terminating the process. This allows the
--    compilation pipeline to produce a user-friendly error message.
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
-- At compilation boundaries, wrap the action:
--
-- @
-- result <- InternalError.catchInternalError (Constrain.constrain mod)
-- case result of
--   Left msg  -> pure (Left (QueryError msg))
--   Right con -> solveConstraints con
-- @
--
-- @since 0.19.2
module Reporting.InternalError
  ( -- * Types
    InternalError (..),

    -- * Reporting
    report,
    reportPure,

    -- * Recovery
    catchInternalError,
    isInternalError,
  )
where

import Control.Exception (ErrorCall (..), catch, throwIO)
import qualified Data.List as List
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
    rendered = formatInternalError location message context

-- | Format an internal error into a structured diagnostic string.
--
-- @since 0.19.2
formatInternalError :: Text -> Text -> Text -> Text
formatInternalError location message context =
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
  where
    separator = Text.replicate 50 "═"

-- RECOVERY

-- | The prefix that 'report' prepends to all internal error messages.
--
-- Used by 'isInternalError' and 'catchInternalError' to distinguish
-- structured internal errors from other 'ErrorCall' exceptions.
--
-- @since 0.19.2
internalErrorPrefix :: String
internalErrorPrefix = Text.unpack (Text.replicate 50 "═" <> "\nINTERNAL COMPILER ERROR in ")

-- | Test whether an 'ErrorCall' message was produced by 'report'.
--
-- Returns 'True' when the message starts with the structured
-- diagnostic header that 'report' generates. Use this to filter
-- internal errors from other exceptions.
--
-- @since 0.19.2
isInternalError :: String -> Bool
isInternalError msg = List.isPrefixOf internalErrorPrefix msg

-- | Run an 'IO' action and catch any 'ErrorCall' thrown by 'report'.
--
-- Returns @Right a@ on success, or @Left errorMessage@ when an
-- internal compiler error is caught. Only catches errors whose
-- message matches the 'report' format; other 'ErrorCall' exceptions
-- are re-thrown.
--
-- This should be used at compilation phase boundaries to prevent
-- a single invariant violation from terminating the entire process.
--
-- @since 0.19.2
catchInternalError :: IO a -> IO (Either Text a)
catchInternalError action =
  fmap Right action `catch` handleErrorCall
  where
    handleErrorCall :: ErrorCall -> IO (Either Text a)
    handleErrorCall (ErrorCallWithLocation msg _)
      | isInternalError msg = pure (Left (Text.pack msg))
    handleErrorCall e = throwIO e

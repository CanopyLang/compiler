{-# LANGUAGE OverloadedStrings #-}

-- | Recoverable internal compiler errors.
--
-- This module provides error types for conditions that were previously
-- handled by 'Reporting.InternalError.report' (which calls 'error' and
-- terminates the process) but are actually recoverable. These are
-- typically dict-lookup failures where a module, name, or type is
-- expected to be in a map but is missing.
--
-- By converting these from crashes to 'Either' values, the compiler
-- produces user-friendly diagnostics instead of Haskell stack traces.
--
-- @since 0.19.2
module Reporting.Error.Internal
  ( RecoverableError (..)
  , toReport
  , lookupOrError
  , lookupOrErrorWith
  ) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text

-- | Errors that were previously crashes but are now recoverable.
--
-- These indicate compiler bugs or unexpected states but produce
-- user-friendly diagnostics instead of process termination.
--
-- @since 0.19.2
data RecoverableError
  = MissingModuleInDict !Text !Text
  | MissingNameInDict !Text !Text
  | MissingTypeInDict !Text !Text !Text
  | InvalidDecisionTree !Text
  | PortValidationFailure !Text !Text
  | PoolStateInconsistency !Text
  | MissingAnnotation !Text !Text
  | KernelLookupFailure !Text !Text
  | InterfaceLookupFailure !Text !Text
  | JsonDecodeInvariant !Text !Text
  deriving (Eq, Show)

-- | Convert a recoverable error to a user-facing report string.
--
-- Produces structured output with the error location, description,
-- and instructions for filing a bug report.
--
-- @since 0.19.2
toReport :: RecoverableError -> Text
toReport err =
  Text.concat
    [ separator
    , "\nINTERNAL COMPILER ERROR (recoverable)\n"
    , separator
    , "\n\n"
    , formatError err
    , "\n\nThis is likely a compiler bug. Please report it at:"
    , "\n  https://github.com/canopy-lang/canopy/issues"
    , "\n\nInclude the source file that triggered this error."
    , "\n"
    , separator
    , "\n"
    ]
  where
    separator = Text.replicate 50 "="

-- | Format a specific error with details.
formatError :: RecoverableError -> Text
formatError = \case
  MissingModuleInDict loc modName ->
    "In " <> loc <> ": Module not found in types dict: " <> modName
  MissingNameInDict loc name ->
    "In " <> loc <> ": Name not found in lookup: " <> name
  MissingTypeInDict loc name modName ->
    "In " <> loc <> ": Type " <> name <> " not found in module " <> modName
  InvalidDecisionTree desc ->
    "Invalid decision tree state: " <> desc
  PortValidationFailure loc name ->
    "In " <> loc <> ": Port validation failure for: " <> name
  PoolStateInconsistency desc ->
    "Type solver pool state inconsistency: " <> desc
  MissingAnnotation loc name ->
    "In " <> loc <> ": Annotation missing for definition: " <> name
  KernelLookupFailure loc desc ->
    "In " <> loc <> ": Kernel module lookup failure: " <> desc
  InterfaceLookupFailure loc desc ->
    "In " <> loc <> ": Interface lookup failure: " <> desc
  JsonDecodeInvariant loc desc ->
    "In " <> loc <> ": JSON decode invariant violation: " <> desc

-- | Safe map lookup that returns an error instead of crashing.
--
-- Replaces the pattern:
--
-- @
-- maybe (InternalError.report loc msg ctx) id (Map.lookup key dict)
-- @
--
-- With:
--
-- @
-- lookupOrError loc key dict
-- @
--
-- @since 0.19.2
lookupOrError
  :: (Ord k, Show k)
  => Text
  -> k
  -> Map.Map k v
  -> Either RecoverableError v
lookupOrError loc key dict =
  maybe
    (Left (MissingNameInDict loc (Text.pack (show key))))
    Right
    (Map.lookup key dict)

-- | Safe map lookup with a custom error constructor.
--
-- @since 0.19.2
lookupOrErrorWith
  :: (Ord k)
  => (Text -> Text -> RecoverableError)
  -> Text
  -> Text
  -> k
  -> Map.Map k v
  -> Either RecoverableError v
lookupOrErrorWith mkError loc keyDesc key dict =
  maybe
    (Left (mkError loc keyDesc))
    Right
    (Map.lookup key dict)

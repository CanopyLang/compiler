{-# LANGUAGE OverloadedStrings #-}

-- | Error recovery infrastructure for partial compilation results.
--
-- When a module has errors in some declarations but not others, recovery
-- allows the compiler to return partial results plus accumulated errors.
-- This is critical for IDE/LSP experience: showing type information for
-- correct bindings while still reporting errors on broken ones.
--
-- == Design
--
-- The key type is @'PartialResult' a@ which carries both a (possibly
-- incomplete) result and a list of errors. Downstream phases can
-- consume partial results by checking whether errors are empty.
--
-- Recovery operates at the declaration level:
--
--   * Parser: catches errors per top-level declaration, skips to next
--   * Type checker: catches errors per binding, continues with remaining
--   * Both accumulate errors rather than failing fast
--
-- @since 0.20.1
module Query.Recovery
  ( -- * Partial Results
    PartialResult (..),
    fromEither,
    isComplete,
    hasErrors,
    partialErrors,
    partialResult,

    -- * Recovery Errors
    RecoveryError (..),

    -- * Recovery Combinators
    recoverMap,
    recoverFold,
    tryRecover,
  )
where

import Data.Text (Text)

-- | A compilation result that may be partial with accumulated errors.
--
-- @since 0.20.1
data PartialResult a = PartialResult
  { _prResult :: !a
    -- ^ The (possibly incomplete) result.
  , _prErrors :: ![RecoveryError]
    -- ^ Errors accumulated during recovery.
  } deriving (Show, Eq)

-- | An error that was recovered from during partial compilation.
--
-- @since 0.20.1
data RecoveryError = RecoveryError
  { _rePhase :: !Text
    -- ^ Compilation phase where the error occurred.
  , _reFile :: !FilePath
    -- ^ Source file path.
  , _reMessage :: !Text
    -- ^ Human-readable error description.
  } deriving (Show, Eq)

-- | Convert an @Either@ to a 'PartialResult'.
--
-- @Left@ becomes a partial result with the fallback value and one error.
-- @Right@ becomes a complete result with no errors.
--
-- @since 0.20.1
fromEither :: a -> Text -> FilePath -> Either Text a -> PartialResult a
fromEither fallback phase file (Left msg) =
  PartialResult fallback [RecoveryError phase file msg]
fromEither _ _ _ (Right result) =
  PartialResult result []

-- | Check if a partial result has no errors.
--
-- @since 0.20.1
isComplete :: PartialResult a -> Bool
isComplete pr = null (_prErrors pr)

-- | Check if a partial result has any errors.
--
-- @since 0.20.1
hasErrors :: PartialResult a -> Bool
hasErrors pr = not (null (_prErrors pr))

-- | Extract only the errors from a partial result.
--
-- @since 0.20.1
partialErrors :: PartialResult a -> [RecoveryError]
partialErrors = _prErrors

-- | Extract the result, ignoring errors.
--
-- @since 0.20.1
partialResult :: PartialResult a -> a
partialResult = _prResult

-- | Map a recoverable function over a list, accumulating errors.
--
-- Each element is processed independently. Failures on one element
-- don't prevent processing of subsequent elements. Failed elements
-- are excluded from the result list.
--
-- @since 0.20.1
recoverMap :: (a -> Either RecoveryError b) -> [a] -> PartialResult [b]
recoverMap f items =
  foldr step (PartialResult [] []) items
  where
    step item (PartialResult results errors) =
      case f item of
        Right result -> PartialResult (result : results) errors
        Left err -> PartialResult results (err : errors)

-- | Fold with error recovery, accumulating both results and errors.
--
-- @since 0.20.1
recoverFold :: (acc -> a -> Either RecoveryError acc) -> acc -> [a] -> PartialResult acc
recoverFold f initial items =
  foldl step (PartialResult initial []) items
  where
    step (PartialResult acc errors) item =
      case f acc item of
        Right acc' -> PartialResult acc' errors
        Left err -> PartialResult acc (err : errors)

-- | Try an operation, returning the fallback on failure with error.
--
-- @since 0.20.1
tryRecover :: a -> Text -> FilePath -> IO (Either Text a) -> IO (PartialResult a)
tryRecover fallback phase file action = do
  result <- action
  pure (fromEither fallback phase file result)

{-# LANGUAGE OverloadedStrings #-}

-- | Pure Task monad for Terminal operations.
--
-- Simple Either-based Task monad for error handling in Terminal commands.
-- Provides IO capabilities with structured error types.
--
-- @since 0.19.1
module Reporting.Task
  ( -- * Task Type
    Task,

    -- * Running Tasks
    run,

    -- * Task Operations
    io,
    eio,
    throw,
    mapError,
    mio,
  )
where

import qualified Control.Monad as Monad
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT, runExceptT, throwE, withExceptT)

-- | Task monad with error type 'e' and result type 'a'.
type Task e a = ExceptT e IO a

-- | Run a Task and return Either error or result.
run :: Task e a -> IO (Either e a)
run = runExceptT

-- | Lift IO action into Task.
io :: IO a -> Task e a
io = liftIO

-- | Convert Either IO into Task.
eio :: e -> IO (Either x a) -> Task e a
eio errConstructor action = do
  result <- liftIO action
  case result of
    Left _ -> throwE errConstructor
    Right value -> pure value

-- | Throw an error in Task.
throw :: e -> Task e a
throw = throwE

-- | Map error type in Task.
mapError :: (e1 -> e2) -> Task e1 a -> Task e2 a
mapError = withExceptT

-- | Run IO action for side effects, ignoring result.
mio :: IO a -> Task e ()
mio action = Monad.void (liftIO action)

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Test generation for FFI functions - Compatibility wrapper
--
-- This module provides backward compatibility by re-exporting
-- the new Canopy-based test generation functionality.

module Foreign.TestGenerator
  ( generateTestSuite
  , TestConfig(..)
  , defaultTestConfig
  ) where

import Foreign.TestGeneratorNew
  ( generateTestSuite
  , TestConfig(..)
  , defaultTestConfig
  )
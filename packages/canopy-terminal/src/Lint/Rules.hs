{-# LANGUAGE OverloadedStrings #-}

-- | Lint rule implementations for the Canopy static analyser.
--
-- This module re-exports all lint rule check functions from their
-- respective sub-modules.  Each rule is a pure function
-- @'AST.Source.Module' -> ['LintWarning']@ that inspects a parsed
-- module and produces zero or more warnings.
--
-- == Sub-modules
--
-- * "Lint.Rules.Helpers" - Shared AST traversal and name collection utilities
-- * "Lint.Rules.Imports" - Unused import detection
-- * "Lint.Rules.Style" - BooleanCase, UnnecessaryParens, MissingTypeAnnotation, InconsistentNaming
-- * "Lint.Rules.Lists" - DropConcatOfLists, UseConsOverConcat, ListAppendInLoop
-- * "Lint.Rules.Scope" - ShadowedVariable, UnusedLetVariable
-- * "Lint.Rules.Safety" - PartialFunction, UnsafeCoerce, UnnecessaryLazyPattern
-- * "Lint.Rules.Complexity" - TooManyArguments, LongFunction, MagicNumber, StringConcatInLoop
--
-- @since 0.19.1
module Lint.Rules
  ( -- * Import Rules
    checkUnusedImport,

    -- * Style Rules
    checkBooleanCase,
    checkUnnecessaryParens,
    checkMissingTypeAnnotation,
    checkInconsistentNaming,

    -- * List Rules
    checkDropConcatOfLists,
    checkUseConsOverConcat,
    checkListAppendInLoop,

    -- * Scope Rules
    checkShadowedVariable,
    checkUnusedLetVariable,

    -- * Safety Rules
    checkPartialFunction,
    checkUnsafeCoerce,
    checkUnnecessaryLazyPattern,

    -- * Complexity Rules
    checkTooManyArguments,
    checkLongFunction,
    checkMagicNumber,
    checkStringConcatInLoop,

    -- * Helpers
    collectUsedNames,
    childExprs,
  )
where

import Lint.Rules.Complexity
  ( checkLongFunction,
    checkMagicNumber,
    checkStringConcatInLoop,
    checkTooManyArguments,
  )
import Lint.Rules.Helpers (childExprs, collectUsedNames)
import Lint.Rules.Imports (checkUnusedImport)
import Lint.Rules.Lists
  ( checkDropConcatOfLists,
    checkListAppendInLoop,
    checkUseConsOverConcat,
  )
import Lint.Rules.Safety
  ( checkPartialFunction,
    checkUnnecessaryLazyPattern,
    checkUnsafeCoerce,
  )
import Lint.Rules.Scope
  ( checkShadowedVariable,
    checkUnusedLetVariable,
  )
import Lint.Rules.Style
  ( checkBooleanCase,
    checkInconsistentNaming,
    checkMissingTypeAnnotation,
    checkUnnecessaryParens,
  )

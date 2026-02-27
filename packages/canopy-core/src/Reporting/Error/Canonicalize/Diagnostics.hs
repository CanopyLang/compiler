{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Canonicalize.Diagnostics - Structured diagnostic builders for canonicalization errors
--
-- This module provides one function per 'Error' constructor that produces a
-- structured 'Diagnostic' value.  Each function takes the fields of its
-- corresponding constructor as individual arguments so that it has no dependency
-- on the 'Error' sum type itself and cannot create a circular import with the
-- parent module.
--
-- The parent module 'Reporting.Error.Canonicalize' is the only caller; it
-- pattern-matches on 'Error' and delegates to these functions.
--
-- Core diagnostics (annotation through patterns) are in
-- "Reporting.Error.Canonicalize.Diagnostics.Core".
-- Extended diagnostics (ports through lazy imports) are in
-- "Reporting.Error.Canonicalize.Diagnostics.Extended".
module Reporting.Error.Canonicalize.Diagnostics
  ( -- * Annotation
    annotationTooShortDiagnostic,
    -- * Ambiguous names
    ambiguousNameDiagnostic,
    -- * Arity
    badArityDiagnostic,
    -- * Operators
    binopDiagnostic,
    -- * Name clashes
    nameClashDiagnostic,
    duplicatePatternMessage,
    -- * Effects
    effectNotFoundDiagnostic,
    effectFunctionNotFoundDiagnostic,
    -- * Exports
    exportDuplicateDiagnostic,
    exportNotFoundDiagnostic,
    exportOpenAliasDiagnostic,
    -- * Imports
    importCtorByNameDiagnostic,
    importNotFoundDiagnostic,
    importOpenAliasDiagnostic,
    importExposingNotFoundDiagnostic,
    -- * Not found
    notFoundDiagnostic,
    addNameSuggestions,
    toNameSuggestion,
    notFoundBinopDiagnostic,
    addBinopSuggestions,
    -- * Patterns
    patternHasRecordCtorDiagnostic,
    -- * Ports
    portPayloadInvalidDiagnostic,
    portPayloadMessage,
    portPayloadKind,
    portPayloadElaboration,
    portTypeInvalidDiagnostic,
    -- * Recursive definitions
    recursiveAliasDiagnostic,
    recursiveDeclDiagnostic,
    recursiveLetDiagnostic,
    -- * Shadowing / tuples
    shadowingDiagnostic,
    tupleLargerThanThreeDiagnostic,
    -- * Type variables
    typeVarsUnboundInUnionDiagnostic,
    typeVarsMessedUpInAliasDiagnostic,
    -- * FFI
    ffiFileNotFoundDiagnostic,
    ffiFileTimeoutDiagnostic,
    ffiParseErrorDiagnostic,
    ffiPathTraversalDiagnostic,
    ffiInvalidTypeDiagnostic,
    ffiMissingAnnotationDiagnostic,
    ffiCircularDependencyDiagnostic,
    ffiTypeNotFoundDiagnostic,
    -- * Lazy imports
    lazyImportNotFoundDiagnostic,
    lazyImportCoreModuleDiagnostic,
    lazyImportInPackageDiagnostic,
    lazyImportSelfDiagnostic,
    lazyImportKernelDiagnostic,
  )
where

import Reporting.Error.Canonicalize.Diagnostics.Core
  ( addBinopSuggestions,
    addNameSuggestions,
    ambiguousNameDiagnostic,
    annotationTooShortDiagnostic,
    badArityDiagnostic,
    binopDiagnostic,
    duplicatePatternMessage,
    effectFunctionNotFoundDiagnostic,
    effectNotFoundDiagnostic,
    exportDuplicateDiagnostic,
    exportNotFoundDiagnostic,
    exportOpenAliasDiagnostic,
    importCtorByNameDiagnostic,
    importExposingNotFoundDiagnostic,
    importNotFoundDiagnostic,
    importOpenAliasDiagnostic,
    nameClashDiagnostic,
    notFoundBinopDiagnostic,
    notFoundDiagnostic,
    patternHasRecordCtorDiagnostic,
    toNameSuggestion,
  )
import Reporting.Error.Canonicalize.Diagnostics.Extended
  ( ffiCircularDependencyDiagnostic,
    ffiFileNotFoundDiagnostic,
    ffiFileTimeoutDiagnostic,
    ffiInvalidTypeDiagnostic,
    ffiMissingAnnotationDiagnostic,
    ffiParseErrorDiagnostic,
    ffiPathTraversalDiagnostic,
    ffiTypeNotFoundDiagnostic,
    lazyImportCoreModuleDiagnostic,
    lazyImportInPackageDiagnostic,
    lazyImportKernelDiagnostic,
    lazyImportNotFoundDiagnostic,
    lazyImportSelfDiagnostic,
    portPayloadElaboration,
    portPayloadInvalidDiagnostic,
    portPayloadKind,
    portPayloadMessage,
    portTypeInvalidDiagnostic,
    recursiveAliasDiagnostic,
    recursiveDeclDiagnostic,
    recursiveLetDiagnostic,
    shadowingDiagnostic,
    tupleLargerThanThreeDiagnostic,
    typeVarsMessedUpInAliasDiagnostic,
    typeVarsUnboundInUnionDiagnostic,
  )

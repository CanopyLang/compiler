{-# LANGUAGE OverloadedStrings #-}

-- | Compiler warnings emitted during compilation.
--
-- @since 0.19.1
module Reporting.Warning
  ( Warning (..),
    Context (..),
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import Data.Text (Text)
import qualified FFI.StaticAnalysis as SA
import qualified Reporting.Annotation as Ann

-- ALL POSSIBLE WARNINGS

data Warning
  = UnusedImport Ann.Region Name.Name
  | UnusedVariable Ann.Region Context Name.Name
  | MissingTypeAnnotation Ann.Region Name.Name Can.Type
  | CapabilityNotice !Text !Text ![Text]
    -- ^ Module name, function name, list of required capabilities
  | FFIUnresolvedType !Text !Text !Text
    -- ^ FFI file path, function name, unresolved type name
  | FFIStaticAnalysis !Text !SA.FFIWarning
    -- ^ FFI file path and the specific static analysis warning
  | FFIUnusedCapability !Text
    -- ^ A capability declared in canopy.json that no FFI function requires
  | FFIMissingCapability !Text !Text !Text
    -- ^ Function name, file path, and capability name not declared in canopy.json
  | FFITypeParseFailure !Text !Text !Text
    -- ^ FFI file path, function name, and unparseable type annotation string
  | FFIJSParseFailure !Text !Text
    -- ^ FFI file path and JavaScript parse error message
  | IntegerOverflow !Int !Int
    -- ^ Line number and the overflowing integer value (exceeds JS MAX_SAFE_INTEGER)
  | DivisionByZero !Int
    -- ^ Line number where constant division by zero was detected
  | UnreachableBranch !Int !Text
    -- ^ Line number and description of the dead branch (e.g., "if True", "if False")
  | PotentialInfiniteRecursion !Text
    -- ^ Function name that appears to recurse without a base case

data Context = Def | Pattern

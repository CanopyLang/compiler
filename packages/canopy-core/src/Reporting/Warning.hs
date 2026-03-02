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

data Context = Def | Pattern

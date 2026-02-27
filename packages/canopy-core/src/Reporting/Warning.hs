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
import qualified Reporting.Annotation as Ann

-- ALL POSSIBLE WARNINGS

data Warning
  = UnusedImport Ann.Region Name.Name
  | UnusedVariable Ann.Region Context Name.Name
  | MissingTypeAnnotation Ann.Region Name.Name Can.Type
  | CapabilityNotice !Text !Text ![Text]
    -- ^ Module name, function name, list of required capabilities

data Context = Def | Pattern

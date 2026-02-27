{-# LANGUAGE OverloadedStrings #-}

module Reporting.Warning
  ( Warning (..),
    Context (..),
  )
where

import qualified AST.Canonical as Can
import qualified Data.Name as Name
import qualified Reporting.Annotation as Ann

-- ALL POSSIBLE WARNINGS

data Warning
  = UnusedImport Ann.Region Name.Name
  | UnusedVariable Ann.Region Context Name.Name
  | MissingTypeAnnotation Ann.Region Name.Name Can.Type

data Context = Def | Pattern

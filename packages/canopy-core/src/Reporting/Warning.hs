{-# LANGUAGE OverloadedStrings #-}

module Reporting.Warning
  ( Warning (..),
    Context (..),
  )
where

import qualified AST.Canonical as Can
import qualified Data.Name as Name
import qualified Reporting.Annotation as A

-- ALL POSSIBLE WARNINGS

data Warning
  = UnusedImport A.Region Name.Name
  | UnusedVariable A.Region Context Name.Name
  | MissingTypeAnnotation A.Region Name.Name Can.Type

data Context = Def | Pattern

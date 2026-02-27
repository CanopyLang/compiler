{-# LANGUAGE OverloadedStrings #-}

module Reporting.Report
  ( Report (..),
  )
where

import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc

-- BUILD REPORTS

data Report = Report
  { _title :: String,
    _region :: Ann.Region,
    _sgstns :: [String],
    _message :: Doc.Doc
  }

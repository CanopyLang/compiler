{-# LANGUAGE OverloadedStrings #-}

module Reporting.Exit.Help
  ( Report,
    report,
    docReport,
    jsonReport,
    compilerDiagnosticReport,
    reportToDoc,
    reportToJson,
    toString,
    toStdout,
    toStderr,
  )
where

import GHC.IO.Handle (hIsTerminalDevice)
import Json.Encode ((==>))
import qualified Json.Encode as Encode
import Reporting.Doc ((<+>))
import qualified Reporting.Doc as Doc
import qualified Reporting.Error as Error
import System.IO (Handle, hPutStr, stderr, stdout)

-- REPORT

data Report
  = DiagnosticReport FilePath Error.Module [Error.Module]
  | Report
      { _title :: String,
        _path :: Maybe FilePath,
        _message :: Doc.Doc
      }

report :: String -> Maybe FilePath -> String -> [Doc.Doc] -> Report
report title path startString others =
  Report title path (Doc.stack (Doc.reflow startString : others))

docReport :: String -> Maybe FilePath -> Doc.Doc -> [Doc.Doc] -> Report
docReport title path startDoc others =
  Report title path (Doc.stack (startDoc : others))

jsonReport :: String -> Maybe FilePath -> Doc.Doc -> Report
jsonReport =
  Report

-- | Create a compiler error report using the structured diagnostic system.
--
-- Produces 'Diagnostic' values for rich output including error codes,
-- source spans, and suggestions.
compilerDiagnosticReport :: FilePath -> Error.Module -> [Error.Module] -> Report
compilerDiagnosticReport =
  DiagnosticReport

-- TO DOC

reportToDoc :: Report -> Doc.Doc
reportToDoc report_ =
  case report_ of
    DiagnosticReport root e es ->
      diagnosticModuleDocs root (e : es)
    Report title maybePath message ->
      formatReportBar title maybePath message

diagnosticModuleDocs :: FilePath -> [Error.Module] -> Doc.Doc
diagnosticModuleDocs root modules =
  Doc.vcat (fmap (Error.toDiagnosticDoc root) modules)

formatReportBar :: String -> Maybe FilePath -> Doc.Doc -> Doc.Doc
formatReportBar title maybePath message =
  Doc.stack [errorBar, message, ""]
  where
    errorBar = Doc.dullcyan ("--" <+> Doc.fromChars title <+> Doc.fromChars errorBarEnd)
    errorBarEnd = maybe (makeDashes (4 + length title)) pathDashes maybePath
    pathDashes path = makeDashes (5 + length title + length path) <> " " <> path
    makeDashes n = replicate (max 1 (80 - n)) '-'

-- TO JSON

reportToJson :: Report -> Encode.Value
reportToJson report_ =
  case report_ of
    DiagnosticReport _ e es ->
      Encode.object
        [ "type" ==> Encode.chars "compile-errors",
          "errors" ==> Encode.list Error.toDiagnosticJson (e : es)
        ]
    Report title maybePath message ->
      Encode.object
        [ "type" ==> Encode.chars "error",
          "path" ==> maybe Encode.null Encode.chars maybePath,
          "title" ==> Encode.chars title,
          "message" ==> Doc.encode message
        ]

-- OUTPUT

toString :: Doc.Doc -> String
toString =
  Doc.toString

toStdout :: Doc.Doc -> IO ()
toStdout = toHandle stdout

toStderr :: Doc.Doc -> IO ()
toStderr = toHandle stderr

toHandle :: Handle -> Doc.Doc -> IO ()
toHandle handle doc =
  do
    isTerminal <- hIsTerminalDevice handle
    if isTerminal
      then Doc.toAnsi handle doc
      else hPutStr handle (toString doc)

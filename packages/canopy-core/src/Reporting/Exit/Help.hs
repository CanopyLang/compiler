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
import qualified Json.Encode as E
import Reporting.Doc ((<+>))
import qualified Reporting.Doc as D
import qualified Reporting.Error as Error
import System.IO (Handle, hPutStr, stderr, stdout)

-- REPORT

data Report
  = DiagnosticReport FilePath Error.Module [Error.Module]
  | Report
      { _title :: String,
        _path :: Maybe FilePath,
        _message :: D.Doc
      }

report :: String -> Maybe FilePath -> String -> [D.Doc] -> Report
report title path startString others =
  Report title path (D.stack (D.reflow startString : others))

docReport :: String -> Maybe FilePath -> D.Doc -> [D.Doc] -> Report
docReport title path startDoc others =
  Report title path (D.stack (startDoc : others))

jsonReport :: String -> Maybe FilePath -> D.Doc -> Report
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

reportToDoc :: Report -> D.Doc
reportToDoc report_ =
  case report_ of
    DiagnosticReport root e es ->
      diagnosticModuleDocs root (e : es)
    Report title maybePath message ->
      formatReportBar title maybePath message

diagnosticModuleDocs :: FilePath -> [Error.Module] -> D.Doc
diagnosticModuleDocs root modules =
  D.vcat (fmap (Error.toDiagnosticDoc root) modules)

formatReportBar :: String -> Maybe FilePath -> D.Doc -> D.Doc
formatReportBar title maybePath message =
  D.stack [errorBar, message, ""]
  where
    errorBar = D.dullcyan ("--" <+> D.fromChars title <+> D.fromChars errorBarEnd)
    errorBarEnd = maybe (makeDashes (4 + length title)) pathDashes maybePath
    pathDashes path = makeDashes (5 + length title + length path) <> " " <> path
    makeDashes n = replicate (max 1 (80 - n)) '-'

-- TO JSON

reportToJson :: Report -> E.Value
reportToJson report_ =
  case report_ of
    DiagnosticReport _ e es ->
      E.object
        [ "type" ==> E.chars "compile-errors",
          "errors" ==> E.list Error.toDiagnosticJson (e : es)
        ]
    Report title maybePath message ->
      E.object
        [ "type" ==> E.chars "error",
          "path" ==> maybe E.null E.chars maybePath,
          "title" ==> E.chars title,
          "message" ==> D.encode message
        ]

-- OUTPUT

toString :: D.Doc -> String
toString =
  D.toString

toStdout :: D.Doc -> IO ()
toStdout = toHandle stdout

toStderr :: D.Doc -> IO ()
toStderr = toHandle stderr

toHandle :: Handle -> D.Doc -> IO ()
toHandle handle doc =
  do
    isTerminal <- hIsTerminalDevice handle
    if isTerminal
      then D.toAnsi handle doc
      else hPutStr handle (toString doc)

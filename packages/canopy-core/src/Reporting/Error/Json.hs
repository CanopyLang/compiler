{-# LANGUAGE OverloadedStrings #-}

module Reporting.Error.Json
  ( toReport,
    FailureToReport (..),
    Context (..),
    Reason (..),
  )
where

import qualified Data.ByteString as BS
import qualified Data.ByteString.UTF8 as BS_UTF8
import qualified Data.NonEmptyList as NE
import Json.Decode (DecodeExpectation (..), Error (..), ParseError (..), Problem (..), StringProblem (..))
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import qualified Reporting.Exit.Help as Help
import qualified Reporting.Render.Code as Code

-- TO REPORT

toReport :: FilePath -> FailureToReport x -> Error x -> Reason -> Help.Report
toReport path ftr err reason =
  case err of
    DecodeProblem bytes problem ->
      problemToReport path ftr (Code.toSource bytes) CRoot problem reason
    ParseProblem bytes parseError ->
      parseErrorToReport path (Code.toSource bytes) parseError reason

newtype Reason
  = ExplicitReason String

because :: Reason -> String -> String
because (ExplicitReason iNeedThings) problem =
  iNeedThings <> (" " <> problem)

-- PARSE ERROR TO REPORT

parseErrorToReport :: FilePath -> Code.Source -> ParseError -> Reason -> Help.Report
parseErrorToReport path source parseError reason =
  let toSnippet title row col (problem, details) =
        let pos = Ann.Position row col
            surroundings = Ann.Region (Ann.Position (max 1 (row - 2)) 1) pos
            region = Ann.Region pos pos
         in Help.jsonReport title (Just path) $
              Code.toSnippet
                source
                surroundings
                (Just region)
                ( Doc.reflow (because reason problem),
                  details
                )
   in case parseError of
        Start row col ->
          toSnippet
            "EXPECTING A VALUE"
            row
            col
            ( "I was expecting to see a JSON value next:",
              Doc.stack
                [ Doc.fillSep
                    [ "Try",
                      "something",
                      "like",
                      Doc.dullyellow "\"this\"",
                      "or",
                      Doc.dullyellow "42",
                      "to",
                      "move",
                      "on",
                      "to",
                      "better",
                      "hints!"
                    ],
                  Doc.toSimpleNote
                    "The JSON specification does not allow trailing commas, so you can sometimes\
                    \ get this error in arrays that have an extra comma at the end. In that case,\
                    \ remove that last comma or add another array entry after it!"
                ]
            )
        ObjectField row col ->
          toSnippet
            "EXTRA COMMA"
            row
            col
            ( "I was partway through parsing a JSON object when I got stuck here:",
              Doc.stack
                [ Doc.fillSep
                    [ "I",
                      "saw",
                      "a",
                      "comma",
                      "right",
                      "before",
                      "I",
                      "got",
                      "stuck",
                      "here,",
                      "so",
                      "I",
                      "was",
                      "expecting",
                      "to",
                      "see",
                      "a",
                      "field",
                      "name",
                      "like",
                      Doc.dullyellow "\"type\"",
                      "or",
                      Doc.dullyellow "\"dependencies\"",
                      "next."
                    ],
                  Doc.reflow
                    "This error is commonly caused by trailing commas in JSON objects. Those are\
                    \ actually disallowed by <https://json.org> so check the previous line for a\
                    \ trailing comma that may need to be deleted.",
                  objectNote
                ]
            )
        ObjectColon row col ->
          toSnippet
            "EXPECTING COLON"
            row
            col
            ( "I was partway through parsing a JSON object when I got stuck here:",
              Doc.stack
                [ Doc.reflow "I was expecting to see a colon next.",
                  objectNote
                ]
            )
        ObjectEnd row col ->
          toSnippet
            "UNFINISHED OBJECT"
            row
            col
            ( "I was partway through parsing a JSON object when I got stuck here:",
              Doc.stack
                [ Doc.reflow "I was expecting to see a comma or a closing curly brace next.",
                  Doc.reflow
                    "Is a comma missing on the previous line? Is an array missing a closing square\
                    \ bracket? It is often something tricky like that!",
                  objectNote
                ]
            )
        ArrayEnd row col ->
          toSnippet
            "UNFINISHED ARRAY"
            row
            col
            ( "I was partway through parsing a JSON array when I got stuck here:",
              Doc.stack
                [ Doc.reflow "I was expecting to see a comma or a closing square bracket next.",
                  Doc.reflow "Is a comma missing on the previous line? It is often something like that!"
                ]
            )
        StringProblem stringProblem row col ->
          case stringProblem of
            BadStringEnd ->
              toSnippet
                "ENDLESS STRING"
                row
                col
                ( "I got to the end of the line without seeing the closing double quote:",
                  Doc.fillSep
                    [ "Strings",
                      "look",
                      "like",
                      Doc.green "\"this\"",
                      "with",
                      "double",
                      "quotes",
                      "on",
                      "each",
                      "end.",
                      "Is",
                      "the",
                      "closing",
                      "double",
                      "quote",
                      "missing",
                      "in",
                      "your",
                      "code?"
                    ]
                )
            BadStringControlChar ->
              toSnippet
                "UNEXPECTED CONTROL CHARACTER"
                row
                col
                ( "I ran into a control character unexpectedly:",
                  Doc.reflow
                    "These are characters that represent tabs, backspaces, newlines, and\
                    \ a bunch of other invisible characters. They all come before 20 in the\
                    \ ASCII range, and they are disallowed by the JSON specificaiton. Maybe\
                    \ a copy/paste added one of these invisible characters to your JSON?"
                )
            BadStringEscapeChar ->
              toSnippet
                "UNKNOWN ESCAPE"
                row
                col
                ( "Backslashes always start escaped characters, but I do not recognize this one:",
                  Doc.stack
                    [ Doc.reflow "Valid escape characters include:",
                      (Doc.dullyellow . Doc.indent 4) . Doc.vcat $ ["\\\"", "\\\\", "\\/", "\\b", "\\f", "\\n", "\\r", "\\t", "\\u003D"],
                      Doc.reflow "Do you want one of those instead? Maybe you need \\\\ to escape a backslash?"
                    ]
                )
            BadStringEscapeHex ->
              toSnippet
                "BAD HEX ESCAPE"
                row
                col
                ( "This is not a valid hex escape:",
                  Doc.fillSep
                    [ "Valid",
                      "hex",
                      "escapes",
                      "in",
                      "JSON",
                      "are",
                      "between",
                      Doc.green "\\u0000",
                      "and",
                      Doc.green "\\uFFFF",
                      "and",
                      "always",
                      "have",
                      "exactly",
                      "four",
                      "digits."
                    ]
                )
        NoLeadingZeros row col ->
          toSnippet
            "BAD NUMBER"
            row
            col
            ( "Numbers cannot start with zeros like this:",
              Doc.reflow "Try deleting the leading zeros?"
            )
        NoFloats row col ->
          toSnippet
            "UNEXPECTED NUMBER"
            row
            col
            ( "I got stuck while trying to parse this number:",
              Doc.reflow
                "I do not accept floating point numbers like 3.1415 right now. That kind\
                \ of JSON value is not needed for any of the uses that Canopy has for now."
            )
        BadEnd row col ->
          toSnippet
            "JSON PROBLEM"
            row
            col
            ( "I was partway through parsing some JSON when I got stuck here:",
              Doc.stack
                [ Doc.reflow
                    "I reached an unexpected point in the JSON. This usually means there is\
                    \ extra content after a complete JSON value, or a missing comma or bracket.",
                  Doc.toSimpleHint
                    "Check that every `{` has a matching `}`, every `[` has a matching `]`,\
                    \ and that there are commas between array elements and object fields."
                ]
            )

objectNote :: Doc.Doc
objectNote =
  Doc.stack
    [ Doc.toSimpleNote "Here is an example of a valid JSON object for reference:",
      Doc.vcat
        [ Doc.indent 4 "{",
          Doc.indent 6 $ Doc.dullyellow "\"name\"" <> ": " <> Doc.dullyellow "\"Tom\"" <> ",",
          Doc.indent 6 $ Doc.dullyellow "\"age\"" <> ": " <> Doc.dullyellow "42",
          Doc.indent 4 "}"
        ],
      Doc.reflow
        "Notice that (1) the field names are in double quotes and (2) there is no\
        \ trailing comma after the last entry. Both are strict requirements in JSON!"
    ]

-- PROBLEM TO REPORT

data Context
  = CRoot
  | CField BS.ByteString Context
  | CIndex Int Context

problemToReport :: FilePath -> FailureToReport x -> Code.Source -> Context -> Problem x -> Reason -> Help.Report
problemToReport path ftr source context problem reason =
  case problem of
    Field field prob ->
      problemToReport path ftr source (CField field context) prob reason
    Index index prob ->
      problemToReport path ftr source (CIndex index context) prob reason
    OneOf p ps ->
      -- NOTE: only displays the deepest problem. This works well for the kind
      -- of JSON used by Canopy, but probably would not work well in general.
      let (NE.List prob _) = NE.sortBy (negate . getMaxDepth) (NE.List p ps)
       in problemToReport path ftr source context prob reason
    Failure region x ->
      _failureToReport ftr path source context region x
    Expecting region expectation ->
      expectationToReport path source context region expectation reason

getMaxDepth :: Problem x -> Int
getMaxDepth problem =
  case problem of
    Field _ prob -> 1 + getMaxDepth prob
    Index _ prob -> 1 + getMaxDepth prob
    OneOf p ps -> maximum (getMaxDepth p : fmap getMaxDepth ps)
    Failure _ _ -> 0
    Expecting _ _ -> 0

newtype FailureToReport x = FailureToReport {_failureToReport :: FilePath -> Code.Source -> Context -> Ann.Region -> x -> Help.Report}

expectationToReport :: FilePath -> Code.Source -> Context -> Ann.Region -> DecodeExpectation -> Reason -> Help.Report
expectationToReport path source context (Ann.Region start end) expectation reason =
  let (Ann.Position sr _) = start
      (Ann.Position er _) = end

      region =
        if sr == er then region else Ann.Region start start

      introduction =
        case context of
          CRoot ->
            "I ran into some trouble here:"
          CField field _ ->
            "I ran into trouble with the value of the \"" <> (BS_UTF8.toString field <> "\" field:")
          CIndex index (CField field _) ->
            "When looking at the \"" <> (BS_UTF8.toString field <> ("\" field, I ran into trouble with the " <> (Doc.intToOrdinal index <> " entry:")))
          CIndex index _ ->
            "I ran into trouble with the " <> (Doc.intToOrdinal index <> " index of this array:")

      toSnippet title aThing =
        Help.jsonReport title (Just path) $
          Code.toSnippet
            source
            region
            Nothing
            ( Doc.reflow (because reason introduction),
              Doc.fillSep (["I", "was", "expecting", "to", "run", "into"] <> aThing)
            )
   in case expectation of
        TObject ->
          toSnippet "EXPECTING OBJECT" ["an", Doc.green "OBJECT" <> "."]
        TArray ->
          toSnippet "EXPECTING ARRAY" ["an", Doc.green "ARRAY" <> "."]
        TString ->
          toSnippet "EXPECTING STRING" ["a", Doc.green "STRING" <> "."]
        TBool ->
          toSnippet "EXPECTING BOOL" ["a", Doc.green "BOOLEAN" <> "."]
        TInt ->
          toSnippet "EXPECTING INT" ["an", Doc.green "INT" <> "."]
        TObjectWith field ->
          toSnippet
            "MISSING FIELD"
            [ "an",
              Doc.green "OBJECT",
              "with",
              "a",
              Doc.green ("\"" <> Doc.fromChars (BS_UTF8.toString field) <> "\""),
              "field."
            ]
        TArrayPair len ->
          toSnippet
            "EXPECTING PAIR"
            [ "an",
              Doc.green "ARRAY",
              "with",
              Doc.green "TWO",
              "entries.",
              "This",
              "array",
              "has",
              Doc.fromInt len,
              if len == 1 then "element." else "elements."
            ]

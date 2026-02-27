{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for module-level constructs.
--
-- This module handles rendering of parse errors for module declarations,
-- imports, exposing lists, and the top-level parse error dispatch.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Module
  ( toParseErrorReport,
    toWeirdEndReport,
    toImportReport,
    toExposingReport,
  )
where

import qualified Data.Char as Char
import Parse.Primitives (Col, Row)
import Parse.Symbol (BadOperator (..))
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import Reporting.Error.Syntax.Declaration
  ( toDeclStartReport,
    toDeclarationsReport,
  )
import Reporting.Error.Syntax.Helpers
  ( toKeywordRegion,
    toRegion,
    toSpaceReport,
  )
import Reporting.Error.Syntax.Types
  ( Exposing (..),
    Module (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Render a module-level parse error.
toParseErrorReport :: Code.Source -> Module -> Report.Report
toParseErrorReport source modul =
  case modul of
    ModuleSpace space row col ->
      toSpaceReport source space row col
    ModuleBadEnd row col ->
      if col == 1
        then toDeclStartReport source row col
        else toWeirdEndReport source row col
    ModuleProblem row col ->
      toModuleProblemReport source row col
    ModuleName row col ->
      toModuleNameReport source row col
    ModuleExposing exposing row col ->
      toExposingReport source exposing row col
    PortModuleProblem row col ->
      toPortModuleProblemReport source row col
    PortModuleName row col ->
      toPortModuleNameReport source row col
    PortModuleExposing exposing row col ->
      toExposingReport source exposing row col
    FFIModuleProblem row col ->
      toFFIModuleProblemReport source row col
    FFIModuleName row col ->
      toFFIModuleNameReport source row col
    FFIModuleExposing exposing row col ->
      toExposingReport source exposing row col
    Effect row col ->
      toEffectReport source row col
    FreshLine row col ->
      toFreshLineReport source row col
    ImportStart row col ->
      toImportReport source row col
    ImportName row col ->
      toImportNameReport source row col
    ImportAs row col ->
      toImportReport source row col
    ImportAlias row col ->
      toImportAliasReport source row col
    ImportExposing row col ->
      toImportReport source row col
    ImportExposingList exposing row col ->
      toExposingReport source exposing row col
    ImportEnd row col ->
      toImportReport source row col
    ImportIndentName row col ->
      toImportReport source row col
    ImportIndentAlias row col ->
      toImportReport source row col
    ImportIndentExposingList row col ->
      toImportIndentExposingListReport source row col
    Infix row col ->
      toInfixReport source row col
    Declarations decl _ _ ->
      toDeclarationsReport source decl

toModuleProblemReport :: Code.Source -> Row -> Col -> Report.Report
toModuleProblemReport source row col =
  let region = toRegion row col
   in Report.Report "UNFINISHED MODULE DECLARATION" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I am parsing an `module` declaration, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "Here are some examples of valid `module` declarations:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "module", "Main", Doc.cyan "exposing", "(..)"],
                      Doc.fillSep [Doc.cyan "module", "Dict", Doc.cyan "exposing", "(Dict, empty, get)"]
                    ],
                Doc.reflow $
                  "I generally recommend using an explicit exposing list. I can skip compiling a bunch\
                  \ of files when the public interface of a module stays the same, so exposing fewer\
                  \ values can help improve compile times!"
              ]
          )

toModuleNameReport :: Code.Source -> Row -> Col -> Report.Report
toModuleNameReport source row col =
  let region = toRegion row col
   in Report.Report "EXPECTING MODULE NAME" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I was parsing an `module` declaration until I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see the module name next, like in these examples:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "module", "Dict", Doc.cyan "exposing", "(..)"],
                      Doc.fillSep [Doc.cyan "module", "Maybe", Doc.cyan "exposing", "(..)"],
                      Doc.fillSep [Doc.cyan "module", "Html.Attributes", Doc.cyan "exposing", "(..)"],
                      Doc.fillSep [Doc.cyan "module", "Json.Decode", Doc.cyan "exposing", "(..)"]
                    ],
                Doc.reflow "Notice that the module names all start with capital letters. That is required!"
              ]
          )

toPortModuleProblemReport :: Code.Source -> Row -> Col -> Report.Report
toPortModuleProblemReport source row col =
  let region = toRegion row col
   in Report.Report "UNFINISHED PORT MODULE DECLARATION" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I am parsing an `port module` declaration, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "Here are some examples of valid `port module` declarations:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "port", Doc.cyan "module", "WebSockets", Doc.cyan "exposing", "(send, listen, keepAlive)"],
                      Doc.fillSep [Doc.cyan "port", Doc.cyan "module", "Maps", Doc.cyan "exposing", "(Location, goto)"]
                    ],
                Doc.link "Note" "Read" "ports" "for more help."
              ]
          )

toPortModuleNameReport :: Code.Source -> Row -> Col -> Report.Report
toPortModuleNameReport source row col =
  let region = toRegion row col
   in Report.Report "EXPECTING MODULE NAME" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I was parsing an `module` declaration until I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see the module name next, like in these examples:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "port", Doc.cyan "module", "WebSockets", Doc.cyan "exposing", "(send, listen, keepAlive)"],
                      Doc.fillSep [Doc.cyan "port", Doc.cyan "module", "Maps", Doc.cyan "exposing", "(Location, goto)"]
                    ],
                Doc.reflow "Notice that the module names start with capital letters. That is required!"
              ]
          )

toFFIModuleProblemReport :: Code.Source -> Row -> Col -> Report.Report
toFFIModuleProblemReport source row col =
  let region = toRegion row col
   in Report.Report "UNFINISHED FFI MODULE DECLARATION" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I am parsing an `ffi module` declaration, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "Here are some examples of valid `ffi module` declarations:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "ffi", Doc.cyan "module", "AudioDemo", Doc.cyan "exposing", "(playTone, stopTone)"],
                      Doc.fillSep [Doc.cyan "ffi", Doc.cyan "module", "WebGL", Doc.cyan "exposing", "(.."]
                    ],
                Doc.link "Note" "Read" "foreign-function-interface" "for more help."
              ]
          )

toFFIModuleNameReport :: Code.Source -> Row -> Col -> Report.Report
toFFIModuleNameReport source row col =
  let region = toRegion row col
   in Report.Report "EXPECTING MODULE NAME" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I was parsing an `ffi module` declaration until I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see a module name like:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "ffi", Doc.cyan "module", Doc.green "AudioDemo", Doc.cyan "exposing", "(..)"],
                      Doc.fillSep [Doc.cyan "ffi", Doc.cyan "module", Doc.green "WebGL", Doc.cyan "exposing", "(Texture, render)"]
                    ],
                Doc.reflow "Notice that the module names start with capital letters. That is required!"
              ]
          )

toEffectReport :: Code.Source -> Row -> Col -> Report.Report
toEffectReport source row col =
  let region = toRegion row col
   in Report.Report "BAD MODULE DECLARATION" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I cannot parse this module declaration:",
            Doc.reflow $
              "This type of module is reserved for the @canopy organization. It is used to\
              \ define certain effects, avoiding building them into the compiler."
          )

toFreshLineReport :: Code.Source -> Row -> Col -> Report.Report
toFreshLineReport source row col =
  let region = toRegion row col
      toBadFirstLineReport keyword =
        Report.Report "TOO MUCH INDENTATION" region [] $
          Code.toSnippet
            source
            region
            Nothing
            ( Doc.reflow ("This `" ++ keyword ++ "` should not have any spaces before it:"),
              Doc.reflow ("Delete the spaces before `" ++ keyword ++ "` until there are none left!")
            )
   in case Code.whatIsNext source row col of
        Code.Keyword "module" -> toBadFirstLineReport "module"
        Code.Keyword "import" -> toBadFirstLineReport "import"
        Code.Keyword "type" -> toBadFirstLineReport "type"
        Code.Keyword "port" -> toBadFirstLineReport "port"
        _ -> toFreshLineWeirdReport source row col

toFreshLineWeirdReport :: Code.Source -> Row -> Col -> Report.Report
toFreshLineWeirdReport source row col =
  let region = toRegion row col
   in Report.Report "SYNTAX PROBLEM" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I got stuck here:",
            Doc.stack
              [ Doc.reflow $
                  "I am not sure what is going on, but I recommend starting a Canopy\
                  \ file with the following lines:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "import", "Html"],
                      "",
                      "main =",
                      "  Html.text " <> Doc.dullyellow "\"Hello!\""
                    ],
                Doc.reflow $
                  "You should be able to copy those lines directly into your file. Check out the\
                  \ examples at <https://canopy-lang.org/examples> for more help getting started!",
                Doc.toSimpleNote "This can also happen when something is indented too much!"
              ]
          )

-- | Render an import parse error.
toImportReport :: Code.Source -> Row -> Col -> Report.Report
toImportReport source row col =
  let region = toRegion row col
   in Report.Report "UNFINISHED IMPORT" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I am partway through parsing an import, but I got stuck here:",
            Doc.stack
              [ Doc.reflow "Here are some examples of valid `import` declarations:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "import", "Html"],
                      Doc.fillSep [Doc.cyan "import", "Html", Doc.cyan "as", "H"],
                      Doc.fillSep [Doc.cyan "import", "Html", Doc.cyan "as", "H", Doc.cyan "exposing", "(..)"],
                      Doc.fillSep [Doc.cyan "import", "Html", Doc.cyan "exposing", "(Html, div, text)"]
                    ],
                Doc.reflow "You are probably trying to import a different module, but try to make it look like one of these examples!",
                Doc.reflowLink "Read" "imports" "to learn more."
              ]
          )

toImportNameReport :: Code.Source -> Row -> Col -> Report.Report
toImportNameReport source row col =
  let region = toRegion row col
   in Report.Report "EXPECTING IMPORT NAME" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I was parsing an `import` until I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see a module name next, like in these examples:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "import", "Dict"],
                      Doc.fillSep [Doc.cyan "import", "Maybe"],
                      Doc.fillSep [Doc.cyan "import", "Html.Attributes", Doc.cyan "as", "A"],
                      Doc.fillSep [Doc.cyan "import", "Json.Decode", Doc.cyan "exposing", "(..)"]
                    ],
                Doc.reflow "Notice that the module names all start with capital letters. That is required!",
                Doc.reflowLink "Read" "imports" "to learn more."
              ]
          )

toImportAliasReport :: Code.Source -> Row -> Col -> Report.Report
toImportAliasReport source row col =
  let region = toRegion row col
   in Report.Report "EXPECTING IMPORT ALIAS" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I was parsing an `import` until I got stuck here:",
            Doc.stack
              [ Doc.reflow "I was expecting to see an alias next, like in these examples:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "import", "Html.Attributes", Doc.cyan "as", "Attr"],
                      Doc.fillSep [Doc.cyan "import", "WebGL.Texture", Doc.cyan "as", "Texture"],
                      Doc.fillSep [Doc.cyan "import", "Json.Decode", Doc.cyan "as", "D"]
                    ],
                Doc.reflow "Notice that the alias always starts with a capital letter. That is required!",
                Doc.reflowLink "Read" "imports" "to learn more."
              ]
          )

toImportIndentExposingListReport :: Code.Source -> Row -> Col -> Report.Report
toImportIndentExposingListReport source row col =
  let region = toRegion row col
   in Report.Report "UNFINISHED IMPORT" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "I was parsing an `import` until I got stuck here:",
            Doc.stack
              [ Doc.reflow $
                  "I was expecting to see the list of exposed values next. For example, here\
                  \ are two ways to expose values from the `Html` module:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "import", "Html", Doc.cyan "exposing", "(..)"],
                      Doc.fillSep [Doc.cyan "import", "Html", Doc.cyan "exposing", "(Html, div, text)"]
                    ],
                Doc.reflow $
                  "I generally recommend the second style. It is more explicit, making it\
                  \ much easier to figure out where values are coming from in large projects!"
              ]
          )

toInfixReport :: Code.Source -> Row -> Col -> Report.Report
toInfixReport source row col =
  let region = toRegion row col
   in Report.Report "BAD INFIX" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow "Something went wrong in this infix operator declaration:",
            Doc.reflow $
              "This feature is used by the @canopy organization to define the\
              \ languages built-in operators."
          )

-- | Render an exposing list parse error.
toExposingReport :: Code.Source -> Exposing -> Row -> Col -> Report.Report
toExposingReport source exposing startRow startCol =
  case exposing of
    ExposingSpace space row col ->
      toSpaceReport source space row col
    ExposingStart row col ->
      toExposingStartReport source startRow startCol row col
    ExposingValue row col ->
      toExposingValueReport source startRow startCol row col
    ExposingOperator row col ->
      toExposingOperatorReport source startRow startCol row col
    ExposingOperatorReserved op row col ->
      toExposingOperatorReservedReport source op startRow startCol row col
    ExposingOperatorRightParen row col ->
      toExposingOperatorRightParenReport source startRow startCol row col
    ExposingEnd row col ->
      toExposingEndReport source startRow startCol row col
    ExposingTypePrivacy row col ->
      toExposingTypePrivacyReport source startRow startCol row col
    ExposingIndentEnd row col ->
      toExposingIndentEndReport source startRow startCol row col
    ExposingIndentValue row col ->
      toExposingIndentValueReport source startRow startCol row col

toExposingStartReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingStartReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I want to parse exposed values, but I am getting stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "Exposed", "values", "are", "always", "surrounded", "by", "parentheses.",
                    "So", "try", "adding", "a", Doc.green "(", "here?"
                  ],
                Doc.toSimpleNote "Here are some valid examples of `exposing` for reference:",
                Doc.indent 4 $
                  Doc.vcat
                    [ Doc.fillSep [Doc.cyan "import", "Html", Doc.cyan "exposing", "(..)"],
                      Doc.fillSep [Doc.cyan "import", "Html", Doc.cyan "exposing", "(Html, div, text)"]
                    ],
                Doc.reflow $
                  "If you are getting tripped up, you can just expose everything for now. It should\
                  \ get easier to make an explicit exposing list as you see more examples in the wild."
              ]
          )

toExposingValueReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingValueReport source startRow startCol row col =
  case Code.whatIsNext source row col of
    Code.Keyword keyword ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I got stuck on this reserved word:",
                Doc.reflow ("It looks like you are trying to expose `" ++ keyword ++ "` but that is a reserved word. Is there a typo?")
              )
    Code.Operator op ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toKeywordRegion row col op
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I got stuck on this symbol:",
                Doc.stack
                  [ Doc.reflow "If you are trying to expose an operator, add parentheses around it like this:",
                    Doc.indent 4 $ Doc.dullyellow (Doc.fromChars op) <> " -> " <> Doc.green ("(" <> Doc.fromChars op <> ")")
                  ]
              )
    _ ->
      let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN EXPOSING" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( Doc.reflow "I got stuck while parsing these exposed values:",
                Doc.stack
                  [ Doc.reflow $
                      "I do not have an exact recommendation, so here are some valid examples\
                      \ of `exposing` for reference:",
                    Doc.indent 4 $
                      Doc.vcat
                        [ Doc.fillSep [Doc.cyan "import", "Html", Doc.cyan "exposing", "(..)"],
                          Doc.fillSep [Doc.cyan "import", "Basics", Doc.cyan "exposing", "(Int, Float, Bool(..), (+), not, sqrt)"]
                        ],
                    Doc.reflow $
                      "These examples show how to expose types, variants, operators, and functions. Everything\
                      \ should be some permutation of these examples, just with different names."
                  ]
              )

toExposingOperatorReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingOperatorReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I just saw an open parenthesis, so I was expecting an operator next:",
            Doc.fillSep
              [ "It", "is", "possible", "to", "expose", "operators,", "so", "I", "was",
                "expecting", "to", "see", "something", "like", Doc.dullyellow "(+)", "or",
                Doc.dullyellow "(|=)", "or", Doc.dullyellow "(||)", "after", "I", "saw",
                "that", "open", "parenthesis."
              ]
          )

toExposingOperatorReservedReport :: Code.Source -> BadOperator -> Row -> Col -> Row -> Col -> Report.Report
toExposingOperatorReservedReport source op startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "RESERVED SYMBOL" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I cannot expose this as an operator:",
            toExposingOperatorReservedHint op
          )

toExposingOperatorReservedHint :: BadOperator -> Doc.Doc
toExposingOperatorReservedHint op =
  case op of
    BadDot -> Doc.reflow "Try getting rid of this entry? Maybe I can give you a better hint after that?"
    BadPipe -> Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow "(||)", "instead?"]
    BadArrow -> Doc.reflow "Try getting rid of this entry? Maybe I can give you a better hint after that?"
    BadEquals -> Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow "(==)", "instead?"]
    BadHasType -> Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow "(::)", "instead?"]

toExposingOperatorRightParenReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingOperatorRightParenReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "It looks like you are exposing an operator, but I got stuck here:",
            Doc.fillSep
              [ "I", "was", "expecting", "to", "see", "the", "closing", "parenthesis",
                "immediately", "after", "the", "operator.", "Try", "adding", "a",
                Doc.green ")", "right", "here?"
              ]
          )

toExposingEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingEndReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I was partway through parsing exposed values, but I got stuck here:",
            Doc.reflow "Maybe there is a comma missing before this?"
          )

toExposingTypePrivacyReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingTypePrivacyReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM EXPOSING CUSTOM TYPE VARIANTS" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "It looks like you are trying to expose the variants of a custom type:",
            Doc.stack
              [ Doc.fillSep
                  [ "You", "need", "to", "write", "something", "like",
                    Doc.dullyellow "Status(..)", "or", Doc.dullyellow "Entity(..)", "though.",
                    "It", "is", "all", "or", "nothing,", "otherwise", "`case`", "expressions",
                    "could", "miss", "a", "variant", "and", "crash!"
                  ],
                Doc.toSimpleNote $
                  "It is often best to keep the variants hidden! If someone pattern matches on\
                  \ the variants, it is a MAJOR change if any new variants are added. Suddenly\
                  \ their `case` expressions do not cover all variants! So if you do not need\
                  \ people to pattern match, keep the variants hidden and expose functions to\
                  \ construct values of this type. This way you can add new variants as a MINOR change!"
              ]
          )

toExposingIndentEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingIndentEndReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I was partway through parsing exposed values, but I got stuck here:",
            Doc.stack
              [ Doc.fillSep
                  [ "I", "was", "expecting", "a", "closing", "parenthesis.",
                    "Try", "adding", "a", Doc.green ")", "right", "here?"
                  ],
                Doc.toSimpleNote $
                  "I can get confused when there is not enough indentation, so if you already\
                  \ have a closing parenthesis, it probably just needs some spaces in front of it."
              ]
          )

toExposingIndentValueReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingIndentValueReport source startRow startCol row col =
  let surroundings = Ann.Region (Ann.Position startRow startCol) (Ann.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( Doc.reflow "I was partway through parsing exposed values, but I got stuck here:",
            Doc.reflow "I was expecting another value to expose."
          )

-- | Render an error when the parser encounters unexpected content near the end.
toWeirdEndReport :: Code.Source -> Row -> Col -> Report.Report
toWeirdEndReport source row col =
  case Code.whatIsNext source row col of
    Code.Keyword keyword ->
      let region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I got stuck on this reserved word:",
                Doc.reflow ("The name `" ++ keyword ++ "` is reserved, so try using a different name?")
              )
    Code.Operator op ->
      let region = toKeywordRegion row col op
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I ran into an unexpected symbol:",
                Doc.reflow $
                  "I was not expecting to see a " ++ op
                    ++ " here. Try deleting it? Maybe\
                       \ I can give a better hint from there?"
              )
    Code.Close term bracket ->
      let region = toRegion row col
       in Report.Report ("UNEXPECTED " ++ map Char.toUpper term) region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow ("I ran into an unexpected " ++ term ++ ":"),
                Doc.reflow ("This " ++ bracket : " does not match up with an earlier open " ++ term ++ ". Try deleting it?")
              )
    Code.Lower c cs ->
      let region = toKeywordRegion row col (c : cs)
       in Report.Report "UNEXPECTED NAME" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I got stuck on this name:",
                Doc.reflow $
                  "It is confusing me a lot! Normally I can give fairly specific hints, but\
                  \ something is really tripping me up this time."
              )
    Code.Upper c cs ->
      let region = toKeywordRegion row col (c : cs)
       in Report.Report "UNEXPECTED NAME" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I got stuck on this name:",
                Doc.reflow $
                  "It is confusing me a lot! Normally I can give fairly specific hints, but\
                  \ something is really tripping me up this time."
              )
    Code.Other maybeChar ->
      toWeirdEndOtherReport source row col maybeChar

toWeirdEndOtherReport :: Code.Source -> Row -> Col -> Maybe Char.Char -> Report.Report
toWeirdEndOtherReport source row col maybeChar =
  let region = toRegion row col
   in case maybeChar of
        Just ';' ->
          Report.Report "UNEXPECTED SEMICOLON" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I got stuck on this semicolon:",
                Doc.stack
                  [ Doc.reflow "Try removing it?",
                    Doc.toSimpleNote $
                      "Some languages require semicolons at the end of each statement. These are\
                      \ often called C-like languages, and they usually share a lot of language design\
                      \ choices. (E.g. side-effects, for loops, etc.) Canopy manages effects with commands\
                      \ and subscriptions instead, so there is no special syntax for \"statements\" and\
                      \ therefore no need to use semicolons to separate them. I think this will make\
                      \ more sense as you work through <https://guide.canopy-lang.org> though!"
                  ]
              )
        Just ',' ->
          Report.Report "UNEXPECTED COMMA" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I got stuck on this comma:",
                Doc.stack
                  [ Doc.reflow "I do not think I am parsing a list or tuple right now. Try deleting the comma?",
                    Doc.toSimpleNote $
                      "If this is supposed to be part of a list, the problem may be a bit earlier.\
                      \ Perhaps the opening [ is missing? Or perhaps some value in the list has an extra\
                      \ closing ] that is making me think the list ended earlier? The same kinds of\
                      \ things could be going wrong if this is supposed to be a tuple."
                  ]
              )
        Just '`' ->
          Report.Report "UNEXPECTED CHARACTER" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I got stuck on this character:",
                Doc.stack
                  [ Doc.reflow $
                      "It is not used for anything in Canopy syntax. It is used for multi-line strings in\
                      \ some languages though, so if you want a string that spans multiple lines, you\
                      \ can use Canopy's multi-line string syntax like this:",
                    Doc.dullyellow $
                      Doc.indent 4 $
                        Doc.vcat
                          [ "\"\"\"",
                            "# Multi-line Strings",
                            "",
                            "- start with triple double quotes",
                            "- write whatever you want",
                            "- no need to escape newlines or double quotes",
                            "- end with triple double quotes",
                            "\"\"\""
                          ],
                    Doc.reflow "Otherwise I do not know what is going on! Try removing the character?"
                  ]
              )
        Just '$' ->
          Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I got stuck on this dollar sign:",
                Doc.reflow $
                  "It is not used for anything in Canopy syntax. Are you coming from a language where\
                  \ dollar signs can be used in variable names? If so, try a name that (1) starts\
                  \ with a letter and (2) only contains letters, numbers, and underscores."
              )
        Just c
          | elem c ['#', '@', '!', '%', '~'] ->
              Report.Report "UNEXPECTED SYMBOL" region [] $
                Code.toSnippet
                  source
                  region
                  Nothing
                  ( Doc.reflow "I got stuck on this symbol:",
                    Doc.reflow "It is not used for anything in Canopy syntax. Try removing it?"
                  )
        _ ->
          Report.Report "SYNTAX PROBLEM" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow "I got stuck here:",
                Doc.reflow $
                  "Whatever I am running into is confusing me a lot! Normally I can give fairly\
                  \ specific hints, but something is really tripping me up this time."
              )

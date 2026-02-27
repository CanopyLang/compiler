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
import qualified Reporting.Annotation as A
import qualified Reporting.Doc as D
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
          ( D.reflow "I am parsing an `module` declaration, but I got stuck here:",
            D.stack
              [ D.reflow "Here are some examples of valid `module` declarations:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "module", "Main", D.cyan "exposing", "(..)"],
                      D.fillSep [D.cyan "module", "Dict", D.cyan "exposing", "(Dict, empty, get)"]
                    ],
                D.reflow $
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
          ( D.reflow "I was parsing an `module` declaration until I got stuck here:",
            D.stack
              [ D.reflow "I was expecting to see the module name next, like in these examples:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "module", "Dict", D.cyan "exposing", "(..)"],
                      D.fillSep [D.cyan "module", "Maybe", D.cyan "exposing", "(..)"],
                      D.fillSep [D.cyan "module", "Html.Attributes", D.cyan "exposing", "(..)"],
                      D.fillSep [D.cyan "module", "Json.Decode", D.cyan "exposing", "(..)"]
                    ],
                D.reflow "Notice that the module names all start with capital letters. That is required!"
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
          ( D.reflow "I am parsing an `port module` declaration, but I got stuck here:",
            D.stack
              [ D.reflow "Here are some examples of valid `port module` declarations:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "port", D.cyan "module", "WebSockets", D.cyan "exposing", "(send, listen, keepAlive)"],
                      D.fillSep [D.cyan "port", D.cyan "module", "Maps", D.cyan "exposing", "(Location, goto)"]
                    ],
                D.link "Note" "Read" "ports" "for more help."
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
          ( D.reflow "I was parsing an `module` declaration until I got stuck here:",
            D.stack
              [ D.reflow "I was expecting to see the module name next, like in these examples:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "port", D.cyan "module", "WebSockets", D.cyan "exposing", "(send, listen, keepAlive)"],
                      D.fillSep [D.cyan "port", D.cyan "module", "Maps", D.cyan "exposing", "(Location, goto)"]
                    ],
                D.reflow "Notice that the module names start with capital letters. That is required!"
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
          ( D.reflow "I am parsing an `ffi module` declaration, but I got stuck here:",
            D.stack
              [ D.reflow "Here are some examples of valid `ffi module` declarations:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "ffi", D.cyan "module", "AudioDemo", D.cyan "exposing", "(playTone, stopTone)"],
                      D.fillSep [D.cyan "ffi", D.cyan "module", "WebGL", D.cyan "exposing", "(.."]
                    ],
                D.link "Note" "Read" "foreign-function-interface" "for more help."
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
          ( D.reflow "I was parsing an `ffi module` declaration until I got stuck here:",
            D.stack
              [ D.reflow "I was expecting to see a module name like:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "ffi", D.cyan "module", D.green "AudioDemo", D.cyan "exposing", "(..)"],
                      D.fillSep [D.cyan "ffi", D.cyan "module", D.green "WebGL", D.cyan "exposing", "(Texture, render)"]
                    ],
                D.reflow "Notice that the module names start with capital letters. That is required!"
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
          ( D.reflow "I cannot parse this module declaration:",
            D.reflow $
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
            ( D.reflow ("This `" ++ keyword ++ "` should not have any spaces before it:"),
              D.reflow ("Delete the spaces before `" ++ keyword ++ "` until there are none left!")
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
          ( D.reflow "I got stuck here:",
            D.stack
              [ D.reflow $
                  "I am not sure what is going on, but I recommend starting a Canopy\
                  \ file with the following lines:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "import", "Html"],
                      "",
                      "main =",
                      "  Html.text " <> D.dullyellow "\"Hello!\""
                    ],
                D.reflow $
                  "You should be able to copy those lines directly into your file. Check out the\
                  \ examples at <https://canopy-lang.org/examples> for more help getting started!",
                D.toSimpleNote "This can also happen when something is indented too much!"
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
          ( D.reflow "I am partway through parsing an import, but I got stuck here:",
            D.stack
              [ D.reflow "Here are some examples of valid `import` declarations:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "import", "Html"],
                      D.fillSep [D.cyan "import", "Html", D.cyan "as", "H"],
                      D.fillSep [D.cyan "import", "Html", D.cyan "as", "H", D.cyan "exposing", "(..)"],
                      D.fillSep [D.cyan "import", "Html", D.cyan "exposing", "(Html, div, text)"]
                    ],
                D.reflow "You are probably trying to import a different module, but try to make it look like one of these examples!",
                D.reflowLink "Read" "imports" "to learn more."
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
          ( D.reflow "I was parsing an `import` until I got stuck here:",
            D.stack
              [ D.reflow "I was expecting to see a module name next, like in these examples:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "import", "Dict"],
                      D.fillSep [D.cyan "import", "Maybe"],
                      D.fillSep [D.cyan "import", "Html.Attributes", D.cyan "as", "A"],
                      D.fillSep [D.cyan "import", "Json.Decode", D.cyan "exposing", "(..)"]
                    ],
                D.reflow "Notice that the module names all start with capital letters. That is required!",
                D.reflowLink "Read" "imports" "to learn more."
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
          ( D.reflow "I was parsing an `import` until I got stuck here:",
            D.stack
              [ D.reflow "I was expecting to see an alias next, like in these examples:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "import", "Html.Attributes", D.cyan "as", "Attr"],
                      D.fillSep [D.cyan "import", "WebGL.Texture", D.cyan "as", "Texture"],
                      D.fillSep [D.cyan "import", "Json.Decode", D.cyan "as", "D"]
                    ],
                D.reflow "Notice that the alias always starts with a capital letter. That is required!",
                D.reflowLink "Read" "imports" "to learn more."
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
          ( D.reflow "I was parsing an `import` until I got stuck here:",
            D.stack
              [ D.reflow $
                  "I was expecting to see the list of exposed values next. For example, here\
                  \ are two ways to expose values from the `Html` module:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "import", "Html", D.cyan "exposing", "(..)"],
                      D.fillSep [D.cyan "import", "Html", D.cyan "exposing", "(Html, div, text)"]
                    ],
                D.reflow $
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
          ( D.reflow "Something went wrong in this infix operator declaration:",
            D.reflow $
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
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I want to parse exposed values, but I am getting stuck here:",
            D.stack
              [ D.fillSep
                  [ "Exposed", "values", "are", "always", "surrounded", "by", "parentheses.",
                    "So", "try", "adding", "a", D.green "(", "here?"
                  ],
                D.toSimpleNote "Here are some valid examples of `exposing` for reference:",
                D.indent 4 $
                  D.vcat
                    [ D.fillSep [D.cyan "import", "Html", D.cyan "exposing", "(..)"],
                      D.fillSep [D.cyan "import", "Html", D.cyan "exposing", "(Html, div, text)"]
                    ],
                D.reflow $
                  "If you are getting tripped up, you can just expose everything for now. It should\
                  \ get easier to make an explicit exposing list as you see more examples in the wild."
              ]
          )

toExposingValueReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingValueReport source startRow startCol row col =
  case Code.whatIsNext source row col of
    Code.Keyword keyword ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toKeywordRegion row col keyword
       in Report.Report "RESERVED WORD" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I got stuck on this reserved word:",
                D.reflow ("It looks like you are trying to expose `" ++ keyword ++ "` but that is a reserved word. Is there a typo?")
              )
    Code.Operator op ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toKeywordRegion row col op
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I got stuck on this symbol:",
                D.stack
                  [ D.reflow "If you are trying to expose an operator, add parentheses around it like this:",
                    D.indent 4 $ D.dullyellow (D.fromChars op) <> " -> " <> D.green ("(" <> D.fromChars op <> ")")
                  ]
              )
    _ ->
      let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
          region = toRegion row col
       in Report.Report "PROBLEM IN EXPOSING" region [] $
            Code.toSnippet
              source
              surroundings
              (Just region)
              ( D.reflow "I got stuck while parsing these exposed values:",
                D.stack
                  [ D.reflow $
                      "I do not have an exact recommendation, so here are some valid examples\
                      \ of `exposing` for reference:",
                    D.indent 4 $
                      D.vcat
                        [ D.fillSep [D.cyan "import", "Html", D.cyan "exposing", "(..)"],
                          D.fillSep [D.cyan "import", "Basics", D.cyan "exposing", "(Int, Float, Bool(..), (+), not, sqrt)"]
                        ],
                    D.reflow $
                      "These examples show how to expose types, variants, operators, and functions. Everything\
                      \ should be some permutation of these examples, just with different names."
                  ]
              )

toExposingOperatorReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingOperatorReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I just saw an open parenthesis, so I was expecting an operator next:",
            D.fillSep
              [ "It", "is", "possible", "to", "expose", "operators,", "so", "I", "was",
                "expecting", "to", "see", "something", "like", D.dullyellow "(+)", "or",
                D.dullyellow "(|=)", "or", D.dullyellow "(||)", "after", "I", "saw",
                "that", "open", "parenthesis."
              ]
          )

toExposingOperatorReservedReport :: Code.Source -> BadOperator -> Row -> Col -> Row -> Col -> Report.Report
toExposingOperatorReservedReport source op startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "RESERVED SYMBOL" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I cannot expose this as an operator:",
            toExposingOperatorReservedHint op
          )

toExposingOperatorReservedHint :: BadOperator -> D.Doc
toExposingOperatorReservedHint op =
  case op of
    BadDot -> D.reflow "Try getting rid of this entry? Maybe I can give you a better hint after that?"
    BadPipe -> D.fillSep ["Maybe", "you", "want", D.dullyellow "(||)", "instead?"]
    BadArrow -> D.reflow "Try getting rid of this entry? Maybe I can give you a better hint after that?"
    BadEquals -> D.fillSep ["Maybe", "you", "want", D.dullyellow "(==)", "instead?"]
    BadHasType -> D.fillSep ["Maybe", "you", "want", D.dullyellow "(::)", "instead?"]

toExposingOperatorRightParenReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingOperatorRightParenReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM IN EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "It looks like you are exposing an operator, but I got stuck here:",
            D.fillSep
              [ "I", "was", "expecting", "to", "see", "the", "closing", "parenthesis",
                "immediately", "after", "the", "operator.", "Try", "adding", "a",
                D.green ")", "right", "here?"
              ]
          )

toExposingEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingEndReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I was partway through parsing exposed values, but I got stuck here:",
            D.reflow "Maybe there is a comma missing before this?"
          )

toExposingTypePrivacyReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingTypePrivacyReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "PROBLEM EXPOSING CUSTOM TYPE VARIANTS" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "It looks like you are trying to expose the variants of a custom type:",
            D.stack
              [ D.fillSep
                  [ "You", "need", "to", "write", "something", "like",
                    D.dullyellow "Status(..)", "or", D.dullyellow "Entity(..)", "though.",
                    "It", "is", "all", "or", "nothing,", "otherwise", "`case`", "expressions",
                    "could", "miss", "a", "variant", "and", "crash!"
                  ],
                D.toSimpleNote $
                  "It is often best to keep the variants hidden! If someone pattern matches on\
                  \ the variants, it is a MAJOR change if any new variants are added. Suddenly\
                  \ their `case` expressions do not cover all variants! So if you do not need\
                  \ people to pattern match, keep the variants hidden and expose functions to\
                  \ construct values of this type. This way you can add new variants as a MINOR change!"
              ]
          )

toExposingIndentEndReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingIndentEndReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I was partway through parsing exposed values, but I got stuck here:",
            D.stack
              [ D.fillSep
                  [ "I", "was", "expecting", "a", "closing", "parenthesis.",
                    "Try", "adding", "a", D.green ")", "right", "here?"
                  ],
                D.toSimpleNote $
                  "I can get confused when there is not enough indentation, so if you already\
                  \ have a closing parenthesis, it probably just needs some spaces in front of it."
              ]
          )

toExposingIndentValueReport :: Code.Source -> Row -> Col -> Row -> Col -> Report.Report
toExposingIndentValueReport source startRow startCol row col =
  let surroundings = A.Region (A.Position startRow startCol) (A.Position row col)
      region = toRegion row col
   in Report.Report "UNFINISHED EXPOSING" region [] $
        Code.toSnippet
          source
          surroundings
          (Just region)
          ( D.reflow "I was partway through parsing exposed values, but I got stuck here:",
            D.reflow "I was expecting another value to expose."
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
              ( D.reflow "I got stuck on this reserved word:",
                D.reflow ("The name `" ++ keyword ++ "` is reserved, so try using a different name?")
              )
    Code.Operator op ->
      let region = toKeywordRegion row col op
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow "I ran into an unexpected symbol:",
                D.reflow $
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
              ( D.reflow ("I ran into an unexpected " ++ term ++ ":"),
                D.reflow ("This " ++ bracket : " does not match up with an earlier open " ++ term ++ ". Try deleting it?")
              )
    Code.Lower c cs ->
      let region = toKeywordRegion row col (c : cs)
       in Report.Report "UNEXPECTED NAME" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow "I got stuck on this name:",
                D.reflow $
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
              ( D.reflow "I got stuck on this name:",
                D.reflow $
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
              ( D.reflow "I got stuck on this semicolon:",
                D.stack
                  [ D.reflow "Try removing it?",
                    D.toSimpleNote $
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
              ( D.reflow "I got stuck on this comma:",
                D.stack
                  [ D.reflow "I do not think I am parsing a list or tuple right now. Try deleting the comma?",
                    D.toSimpleNote $
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
              ( D.reflow "I got stuck on this character:",
                D.stack
                  [ D.reflow $
                      "It is not used for anything in Canopy syntax. It is used for multi-line strings in\
                      \ some languages though, so if you want a string that spans multiple lines, you\
                      \ can use Canopy's multi-line string syntax like this:",
                    D.dullyellow $
                      D.indent 4 $
                        D.vcat
                          [ "\"\"\"",
                            "# Multi-line Strings",
                            "",
                            "- start with triple double quotes",
                            "- write whatever you want",
                            "- no need to escape newlines or double quotes",
                            "- end with triple double quotes",
                            "\"\"\""
                          ],
                    D.reflow "Otherwise I do not know what is going on! Try removing the character?"
                  ]
              )
        Just '$' ->
          Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow "I got stuck on this dollar sign:",
                D.reflow $
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
                  ( D.reflow "I got stuck on this symbol:",
                    D.reflow "It is not used for anything in Canopy syntax. Try removing it?"
                  )
        _ ->
          Report.Report "SYNTAX PROBLEM" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow "I got stuck here:",
                D.reflow $
                  "Whatever I am running into is confusing me a lot! Normally I can give fairly\
                  \ specific hints, but something is really tripping me up this time."
              )

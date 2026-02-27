{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error rendering for literal values.
--
-- This module handles rendering of parse errors for character literals,
-- string literals (including multi-line), escape sequences, numbers,
-- and operator symbols.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Literal
  ( toCharReport,
    toStringReport,
    toEscapeReport,
    toNumberReport,
    toOperatorReport,
  )
where

import qualified Data.Char as Char
import qualified Data.Name as Name
import Numeric (showHex)
import Parse.Primitives (Col, Row)
import Parse.Symbol (BadOperator (..))
import qualified Reporting.Doc as D
import Reporting.Error.Syntax.Helpers
  ( Context,
    Node (NBranch, NCase, NRecord),
    getDefName,
    isWithin,
    noteForCaseError,
    noteForCaseIndentError,
    toRegion,
    toWiderRegion,
  )
import Reporting.Error.Syntax.Types
  ( Char (..),
    Escape (..),
    Number (..),
    String (..),
  )
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Render a character literal parse error.
toCharReport :: Code.Source -> Char -> Row -> Col -> Report.Report
toCharReport source char row col =
  case char of
    CharEndless ->
      let region = toRegion row col
       in Report.Report "MISSING SINGLE QUOTE" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I thought I was parsing a character, but I got to the end of\
                  \ the line without seeing the closing single quote:",
                D.reflow $
                  "Add a closing single quote here!"
              )
    CharEscape escape ->
      toEscapeReport source escape row col
    CharNotString width ->
      let region = toWiderRegion row col width
       in Report.Report "NEEDS DOUBLE QUOTES" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( "The following string uses single quotes:",
                D.stack
                  [ "Please switch to double quotes instead:",
                    D.indent 4 $
                      D.dullyellow "'this'" <> " => " <> D.green "\"this\"",
                    D.toSimpleNote $
                      "Canopy uses double quotes for strings like \"hello\", whereas it uses single\
                      \ quotes for individual characters like 'a' and 'ø'. This distinction helps with\
                      \ code like (String.any (\\c -> c == 'X') \"90210\") where you are inspecting\
                      \ individual characters."
                  ]
              )

-- | Render a string literal parse error.
toStringReport :: Code.Source -> String -> Row -> Col -> Report.Report
toStringReport source string row col =
  case string of
    StringEndless_Single ->
      let region = toRegion row col
       in Report.Report "ENDLESS STRING" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I got to the end of the line without seeing the closing double quote:",
                D.stack
                  [ D.fillSep $
                      [ "Strings",
                        "look",
                        "like",
                        D.green "\"this\"",
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
                      ],
                    D.toSimpleNote $
                      "For a string that spans multiple lines, you can use the multi-line string\
                      \ syntax like this:",
                    D.dullyellow $
                      D.indent 4 $
                        D.vcat $
                          [ "\"\"\"",
                            "# Multi-line Strings",
                            "",
                            "- start with triple double quotes",
                            "- write whatever you want",
                            "- no need to escape newlines or double quotes",
                            "- end with triple double quotes",
                            "\"\"\""
                          ]
                  ]
              )
    StringEndless_Multi ->
      let region = toWiderRegion row col 3
       in Report.Report "ENDLESS STRING" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I cannot find the end of this multi-line string:",
                D.stack
                  [ D.reflow "Add a \"\"\" somewhere after this to end the string.",
                    D.toSimpleNote $
                      "Here is a valid multi-line string for reference:",
                    D.dullyellow $
                      D.indent 4 $
                        D.vcat $
                          [ "\"\"\"",
                            "# Multi-line Strings",
                            "",
                            "- start with triple double quotes",
                            "- write whatever you want",
                            "- no need to escape newlines or double quotes",
                            "- end with triple double quotes",
                            "\"\"\""
                          ]
                  ]
              )
    StringEscape escape ->
      toEscapeReport source escape row col

-- | Render an escape sequence parse error.
toEscapeReport :: Code.Source -> Escape -> Row -> Col -> Report.Report
toEscapeReport source escape row col =
  case escape of
    EscapeUnknown ->
      let region = toWiderRegion row col 2
       in Report.Report "UNKNOWN ESCAPE" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "Backslashes always start escaped characters, but I do not recognize this one:",
                D.stack
                  [ D.reflow $
                      "Valid escape characters include:",
                    D.dullyellow $
                      D.indent 4 $
                        D.vcat $
                          [ "\\n",
                            "\\r",
                            "\\t",
                            "\\\"",
                            "\\\'",
                            "\\\\",
                            "\\u{003D}"
                          ],
                    D.reflow $
                      "Do you want one of those instead? Maybe you need \\\\ to escape a backslash?",
                    D.toSimpleNote $
                      "The last style lets encode ANY character by its Unicode code\
                      \ point. That means \\u{0009} and \\t are the same. You can use\
                      \ that style for anything not covered by the other six escapes!"
                  ]
              )
    BadUnicodeFormat width ->
      let region = toWiderRegion row col width
       in Report.Report "BAD UNICODE ESCAPE" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I ran into an invalid Unicode escape:",
                D.stack
                  [ D.reflow $
                      "Here are some examples of valid Unicode escapes:",
                    D.dullyellow $
                      D.indent 4 $
                        D.vcat $
                          [ "\\u{0041}",
                            "\\u{03BB}",
                            "\\u{6728}",
                            "\\u{1F60A}"
                          ],
                    D.reflow $
                      "Notice that the code point is always surrounded by curly braces.\
                      \ Maybe you are missing the opening or closing curly brace?"
                  ]
              )
    BadUnicodeCode width ->
      let region = toWiderRegion row col width
       in Report.Report "BAD UNICODE ESCAPE" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "This is not a valid code point:",
                D.reflow $
                  "The valid code points are between 0 and 10FFFF inclusive."
              )
    BadUnicodeLength width numDigits badCode ->
      let region = toWiderRegion row col width
       in Report.Report "BAD UNICODE ESCAPE" region [] $
            Code.toSnippet source region Nothing $
              if numDigits < 4
                then
                  ( D.reflow $
                      "Every code point needs at least four digits:",
                    let goodCode = replicate (4 - numDigits) '0' ++ map Char.toUpper (showHex badCode "")
                        suggestion = "\\u{" <> D.fromChars goodCode <> "}"
                     in D.fillSep ["Try", D.green suggestion, "instead?"]
                  )
                else
                  ( D.reflow $
                      "This code point has too many digits:",
                    D.fillSep $
                      [ "Valid",
                        "code",
                        "points",
                        "are",
                        "between",
                        D.green "\\u{0000}",
                        "and",
                        D.green "\\u{10FFFF}" <> ",",
                        "so",
                        "try",
                        "trimming",
                        "any",
                        "leading",
                        "zeros",
                        "until",
                        "you",
                        "have",
                        "between",
                        "four",
                        "and",
                        "six",
                        "digits."
                      ]
                  )

-- | Render a number literal parse error.
toNumberReport :: Code.Source -> Number -> Row -> Col -> Report.Report
toNumberReport source number row col =
  let region = toRegion row col
   in case number of
        NumberEnd ->
          Report.Report "WEIRD NUMBER" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I thought I was reading a number, but I ran into some weird stuff here:",
                D.stack
                  [ D.reflow $
                      "I recognize numbers in the following formats:",
                    D.indent 4 $ D.vcat ["42", "3.14", "6.022e23", "0x002B"],
                    D.reflow $
                      "So is there a way to write it like one of those?"
                  ]
              )
        NumberDot int ->
          Report.Report "WEIRD NUMBER" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "Numbers cannot end with a dot like this:",
                D.fillSep
                  [ "Switching",
                    "to",
                    D.green (D.fromChars (show int)),
                    "or",
                    D.green (D.fromChars (show int ++ ".0")),
                    "will",
                    "work",
                    "though!"
                  ]
              )
        NumberHexDigit ->
          Report.Report "WEIRD HEXIDECIMAL" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I thought I was reading a hexidecimal number until I got here:",
                D.stack
                  [ D.reflow $
                      "Valid hexidecimal digits include 0123456789abcdefABCDEF, so I can\
                      \ only recognize things like this:",
                    D.indent 4 $ D.vcat ["0x2B", "0x002B", "0x00ffb3"]
                  ]
              )
        NumberNoLeadingZero ->
          Report.Report "LEADING ZEROS" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I do not accept numbers with leading zeros:",
                D.stack
                  [ D.reflow $
                      "Just delete the leading zeros and it should work!",
                    D.toSimpleNote $
                      "Some languages let you to specify octal numbers by adding a leading zero.\
                      \ So in C, writing 0111 is the same as writing 73. Some people are used to\
                      \ that, but others probably want it to equal 111. Either path is going to\
                      \ surprise people from certain backgrounds, so Canopy tries to avoid this whole\
                      \ situation."
                  ]
              )

-- | Render a reserved or malformed operator error.
toOperatorReport :: Code.Source -> Context -> BadOperator -> Row -> Col -> Report.Report
toOperatorReport source context operator row col =
  case operator of
    BadDot ->
      let region = toRegion row col
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( "I was not expecting this dot:",
                D.reflow $
                  "Dots are for record access and decimal points, so\
                  \ they cannot float around on their own. Maybe\
                  \ there is some extra whitespace?"
              )
    BadPipe ->
      let region = toRegion row col
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I was not expecting this vertical bar:",
                D.reflow $
                  "Vertical bars should only appear in custom type declarations. Maybe you want || instead?"
              )
    BadArrow ->
      let region = toWiderRegion row col 2
       in Report.Report "UNEXPECTED ARROW" region [] $
            Code.toSnippet source region Nothing $
              if isWithin NCase context
                then
                  ( D.reflow $
                      "I am parsing a `case` expression right now, but this arrow is confusing me:",
                    D.stack
                      [ D.reflow "Maybe the `of` keyword is missing on a previous line?",
                        noteForCaseError
                      ]
                  )
                else
                  if isWithin NBranch context
                    then
                      ( D.reflow $
                          "I am parsing a `case` expression right now, but this arrow is confusing me:",
                        D.stack
                          [ D.reflow $
                              "It makes sense to see arrows around here, so I suspect it is something earlier. Maybe this pattern is indented a bit farther than the previous patterns?",
                            noteForCaseIndentError
                          ]
                      )
                    else
                      ( D.reflow $
                          "I was partway through parsing an expression when I got stuck on this arrow:",
                        D.stack
                          [ "Arrows should only appear in `case` expressions and anonymous functions.\n\
                            \Maybe it was supposed to be a > sign instead?",
                            D.toSimpleNote $
                              "The syntax for anonymous functions is (\\x -> x + 1) so the arguments all appear\
                              \ after the backslash and before the arrow. Maybe a backslash is missing earlier?"
                          ]
                      )
    BadEquals ->
      let region = toRegion row col
       in Report.Report "UNEXPECTED EQUALS" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( D.reflow $
                  "I was not expecting to see this equals sign:",
                D.stack
                  [ D.reflow "Maybe you want == instead? To check if two values are equal?",
                    D.toSimpleNote $
                      if isWithin NRecord context
                        then
                          "Records look like { x = 3, y = 4 } with the equals sign right\
                          \ after the field name. So maybe you forgot a comma?"
                        else case getDefName context of
                          Nothing ->
                            "I may be getting confused by your indentation. I need all definitions to be indented\
                            \ exactly the same amount, so if this is meant to be a new definition, it may have too\
                            \ many spaces in front of it."
                          Just name ->
                            "I may be getting confused by your indentation. I think I am still parsing the `"
                              ++ Name.toChars name
                              ++ "` definition. Is this supposed to be part of a definition\
                                 \ after that? If so, the problem may be a bit before the equals sign. I need all\
                                 \ definitions to be indented exactly the same amount, so the problem may be that\
                                 \ this new definition has too many spaces in front of it."
                  ]
              )
    BadHasType ->
      let region = toRegion row col
       in Report.Report "UNEXPECTED SYMBOL" region [] $
            Code.toSnippet source region Nothing $
              ( D.reflow $
                  "I was not expecting to run into the \"has type\" symbol here:",
                case getDefName context of
                  Nothing ->
                    D.fillSep
                      [ "Maybe",
                        "you",
                        "want",
                        D.green "::",
                        "instead?",
                        "To",
                        "put",
                        "something",
                        "on",
                        "the",
                        "front",
                        "of",
                        "a",
                        "list?"
                      ]
                  Just name ->
                    D.stack
                      [ D.fillSep
                          [ "Maybe",
                            "you",
                            "want",
                            D.green "::",
                            "instead?",
                            "To",
                            "put",
                            "something",
                            "on",
                            "the",
                            "front",
                            "of",
                            "a",
                            "list?"
                          ],
                        D.toSimpleNote $
                          "The single colon is reserved for type annotations and record types, but I think\
                          \ I am parsing the definition of `"
                            ++ Name.toChars name
                            ++ "` right now.",
                        D.toSimpleNote $
                          "I may be getting confused by your indentation. Is this supposed to be part of\
                          \ a type annotation AFTER the `"
                            ++ Name.toChars name
                            ++ "` definition? If so,\
                               \ the problem may be a bit before the \"has type\" symbol. I need all definitions to\
                               \ be exactly aligned (with exactly the same indentation) so the problem may be that\
                               \ this new definition is indented a bit too much."
                      ]
              )


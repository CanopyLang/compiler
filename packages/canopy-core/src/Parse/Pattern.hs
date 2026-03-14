{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE UnboxedTuples #-}

-- | Parse.Pattern — Canopy pattern parser.
--
-- Parses all pattern forms used in case branches, lambda arguments,
-- let-destructures, and function definitions: wildcards, variable
-- bindings, constructor patterns (qualified and unqualified), literals,
-- records, tuples, lists, cons patterns (@::@), and @as@ aliases.
--
-- Two parsers are exported:
--
-- * 'term' — parses a single atomic pattern (no cons or @as@).
-- * 'expression' — parses a full pattern including cons chains and @as@.
--
-- @since 0.19.1
module Parse.Pattern
  ( term,
    expression,
  )
where

import qualified AST.Source as Src
import qualified Data.List as List
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import Foreign.Ptr (plusPtr)
import qualified Parse.Keyword as Keyword
import qualified Parse.Number as Number
import Parse.Primitives (Parser, addEnd, addLocation, getPosition, inContext, oneOf, oneOfWithFallback, word1, word2)
import qualified Parse.Primitives as Parse
import qualified Parse.Space as Space
import qualified Parse.String as String
import qualified Parse.Variable as Var
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError

-- TERM

-- | Parse a single atomic pattern (no @::@ cons or @as@ alias).
--
-- Handles record, tuple, list, and the full set of leaf patterns:
-- wildcard @_@, variable binding, uppercase constructor, integer,
-- string, and character literals.  Used wherever only a non-binary
-- pattern is grammatically valid (function argument positions).
--
-- @since 0.19.1
term :: Parser SyntaxError.Pattern Src.Pattern
term =
  do
    start <- getPosition
    oneOf
      SyntaxError.PStart
      [ record start,
        tuple start,
        list start,
        termHelp start
      ]

termHelp :: Ann.Position -> Parser SyntaxError.Pattern Src.Pattern
termHelp start =
  oneOf
    SyntaxError.PStart
    [ do
        wildcard
        addEnd start Src.PAnything,
      do
        name <- Var.lower SyntaxError.PStart
        addEnd start (Src.PVar name),
      do
        upper <- Var.foreignUpper SyntaxError.PStart
        end <- getPosition
        let region = Ann.Region start end
        return $
          Ann.at start end $
            case upper of
              Var.Unqualified name ->
                Src.PCtor region name []
              Var.Qualified home name ->
                Src.PCtorQual region home name [],
      do
        number <- Number.number SyntaxError.PStart SyntaxError.PNumber
        end <- getPosition
        case number of
          Number.Int int ->
            return (Ann.at start end (Src.PInt int))
          Number.Float float ->
            Parse.Parser $ \(Parse.State _ _ _ _ row col) _ _ cerr _ ->
              let width = fromIntegral (Utf8.size float)
               in cerr row (col - width) (SyntaxError.PFloat width),
      do
        str <- String.string SyntaxError.PStart SyntaxError.PString
        addEnd start (Src.PStr str),
      do
        chr <- String.character SyntaxError.PStart SyntaxError.PChar
        addEnd start (Src.PChr chr)
    ]

-- WILDCARD
--
-- A bare underscore `_` is a wildcard pattern (PAnything).
-- An underscore followed by letters like `_description` is a regular variable (PVar).

wildcard :: Parser SyntaxError.Pattern ()
wildcard =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    if pos == end || Parse.unsafeIndex pos /= 0x5F {- _ -}
      then eerr row col SyntaxError.PStart
      else
        let !newPos = plusPtr pos 1
            !newCol = col + 1
         in if Var.getInnerWidth newPos end > 0
              then
                -- Has characters after underscore - not a wildcard, let Var.lower handle it
                eerr row col SyntaxError.PStart
              else
                let !newState = Parse.State src newPos end indent row newCol
                 in cok () newState

-- RECORDS

record :: Ann.Position -> Parser SyntaxError.Pattern Src.Pattern
record start =
  inContext SyntaxError.PRecord (word1 0x7B {- { -} SyntaxError.PStart) $
    do
      Space.chompAndCheckIndent SyntaxError.PRecordSpace SyntaxError.PRecordIndentOpen
      oneOf
        SyntaxError.PRecordOpen
        [ do
            var <- addLocation (Var.lower SyntaxError.PRecordField)
            Space.chompAndCheckIndent SyntaxError.PRecordSpace SyntaxError.PRecordIndentEnd
            recordHelp start [var],
          do
            word1 0x7D {-}-} SyntaxError.PRecordEnd
            addEnd start (Src.PRecord [])
        ]

recordHelp :: Ann.Position -> [Ann.Located Name.Name] -> Parser SyntaxError.PRecord Src.Pattern
recordHelp start vars =
  oneOf
    SyntaxError.PRecordEnd
    [ do
        word1 0x2C {-,-} SyntaxError.PRecordEnd
        Space.chompAndCheckIndent SyntaxError.PRecordSpace SyntaxError.PRecordIndentField
        var <- addLocation (Var.lower SyntaxError.PRecordField)
        Space.chompAndCheckIndent SyntaxError.PRecordSpace SyntaxError.PRecordIndentEnd
        recordHelp start (var : vars),
      do
        word1 0x7D {-}-} SyntaxError.PRecordEnd
        addEnd start (Src.PRecord (reverse vars))
    ]

-- TUPLES

tuple :: Ann.Position -> Parser SyntaxError.Pattern Src.Pattern
tuple start =
  inContext SyntaxError.PTuple (word1 0x28 {-(-} SyntaxError.PStart) $
    do
      Space.chompAndCheckIndent SyntaxError.PTupleSpace SyntaxError.PTupleIndentExpr1
      oneOf
        SyntaxError.PTupleOpen
        [ do
            (pattern, end) <- Parse.specialize SyntaxError.PTupleExpr expression
            Space.checkIndent end SyntaxError.PTupleIndentEnd
            tupleHelp start pattern [],
          do
            word1 0x29 {-)-} SyntaxError.PTupleEnd
            addEnd start Src.PUnit
        ]

tupleHelp :: Ann.Position -> Src.Pattern -> [Src.Pattern] -> Parser SyntaxError.PTuple Src.Pattern
tupleHelp start firstPattern revPatterns =
  oneOf
    SyntaxError.PTupleEnd
    [ do
        word1 0x2C {-,-} SyntaxError.PTupleEnd
        Space.chompAndCheckIndent SyntaxError.PTupleSpace SyntaxError.PTupleIndentExprN
        (pattern, end) <- Parse.specialize SyntaxError.PTupleExpr expression
        Space.checkIndent end SyntaxError.PTupleIndentEnd
        tupleHelp start firstPattern (pattern : revPatterns),
      do
        word1 0x29 {-)-} SyntaxError.PTupleEnd
        case reverse revPatterns of
          [] ->
            return firstPattern
          secondPattern : otherPatterns ->
            addEnd start (Src.PTuple firstPattern secondPattern otherPatterns)
    ]

-- LIST

list :: Ann.Position -> Parser SyntaxError.Pattern Src.Pattern
list start =
  inContext SyntaxError.PList (word1 0x5B {-[-} SyntaxError.PStart) $
    do
      Space.chompAndCheckIndent SyntaxError.PListSpace SyntaxError.PListIndentOpen
      oneOf
        SyntaxError.PListOpen
        [ do
            (pattern, end) <- Parse.specialize SyntaxError.PListExpr expression
            Space.checkIndent end SyntaxError.PListIndentEnd
            listHelp start [pattern],
          do
            word1 0x5D {-]-} SyntaxError.PListEnd
            addEnd start (Src.PList [])
        ]

listHelp :: Ann.Position -> [Src.Pattern] -> Parser SyntaxError.PList Src.Pattern
listHelp start patterns =
  oneOf
    SyntaxError.PListEnd
    [ do
        word1 0x2C {-,-} SyntaxError.PListEnd
        Space.chompAndCheckIndent SyntaxError.PListSpace SyntaxError.PListIndentExpr
        (pattern, end) <- Parse.specialize SyntaxError.PListExpr expression
        Space.checkIndent end SyntaxError.PListIndentEnd
        listHelp start (pattern : patterns),
      do
        word1 0x5D {-]-} SyntaxError.PListEnd
        addEnd start (Src.PList (reverse patterns))
    ]

-- EXPRESSION

-- | Parse a full pattern expression, including cons chains and @as@ aliases.
--
-- Extends 'term' with right-associative @::@ cons operators and optional
-- trailing @as name@ aliases.  Used in case branches and let-destructures
-- where the richer pattern grammar is allowed.
--
-- @since 0.19.1
expression :: Space.Parser SyntaxError.Pattern Src.Pattern
expression =
  do
    start <- getPosition
    ePart <- exprPart
    exprHelp start [] ePart

exprHelp :: Ann.Position -> [Src.Pattern] -> (Src.Pattern, Ann.Position) -> Space.Parser SyntaxError.Pattern Src.Pattern
exprHelp start revPatterns (pattern, end) =
  oneOfWithFallback
    [ do
        Space.checkIndent end SyntaxError.PIndentStart
        word2 0x3A 0x3A {-::-} SyntaxError.PStart
        Space.chompAndCheckIndent SyntaxError.PSpace SyntaxError.PIndentStart
        ePart <- exprPart
        exprHelp start (pattern : revPatterns) ePart,
      do
        Space.checkIndent end SyntaxError.PIndentStart
        Keyword.as_ SyntaxError.PStart
        Space.chompAndCheckIndent SyntaxError.PSpace SyntaxError.PIndentAlias
        nameStart <- getPosition
        name <- Var.lower SyntaxError.PAlias
        newEnd <- getPosition
        Space.chomp SyntaxError.PSpace
        let alias = Ann.at nameStart newEnd name
        return
          ( Ann.at start newEnd (Src.PAlias (List.foldl' cons pattern revPatterns) alias),
            newEnd
          )
    ]
    ( List.foldl' cons pattern revPatterns,
      end
    )

cons :: Src.Pattern -> Src.Pattern -> Src.Pattern
cons tl hd =
  Ann.merge hd tl (Src.PCons hd tl)

-- EXPRESSION PART

exprPart :: Space.Parser SyntaxError.Pattern Src.Pattern
exprPart =
  oneOf
    SyntaxError.PStart
    [ do
        start <- getPosition
        upper <- Var.foreignUpper SyntaxError.PStart
        end <- getPosition
        exprTermHelp (Ann.Region start end) upper start [],
      do
        eterm@(Ann.At (Ann.Region _ end) _) <- term
        Space.chomp SyntaxError.PSpace
        return (eterm, end)
    ]

exprTermHelp :: Ann.Region -> Var.Upper -> Ann.Position -> [Src.Pattern] -> Space.Parser SyntaxError.Pattern Src.Pattern
exprTermHelp region upper start revArgs =
  do
    end <- getPosition
    Space.chomp SyntaxError.PSpace
    oneOfWithFallback
      [ do
          Space.checkIndent end SyntaxError.PIndentStart
          arg <- term
          exprTermHelp region upper start (arg : revArgs)
      ]
      ( Ann.at start end $
          case upper of
            Var.Unqualified name ->
              Src.PCtor region name (reverse revArgs)
            Var.Qualified home name ->
              Src.PCtorQual region home name (reverse revArgs),
        end
      )

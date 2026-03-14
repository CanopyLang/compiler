{-# LANGUAGE OverloadedStrings #-}

-- | Parse.Type — Canopy type expression parser.
--
-- Parses all type syntax: type variables, qualified and unqualified type
-- constructors with arguments, function types (@->@), unit, tuples, and
-- record types (with optional extension variable).
--
-- Two parsers are exported:
--
-- * 'expression' — parses a complete type, including function arrows.
-- * 'variant' — parses a single custom-type variant (@Ctor Arg1 Arg2@).
--
-- @since 0.19.1
module Parse.Type
  ( expression
  , variant
  )
  where


import qualified Canopy.Data.Name as Name

import qualified AST.Source as Src
import Parse.Primitives (Parser, addLocation, addEnd, getPosition, inContext, specialize, oneOf, oneOfWithFallback, word1, word2)
import qualified Parse.Space as Space
import qualified Parse.Variable as Var
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError



-- TYPE TERMS


term :: Parser SyntaxError.Type Src.Type
term =
  do  start <- getPosition
      oneOf SyntaxError.TStart
        [
          -- types with no arguments (Int, Float, etc.)
          do  upper <- Var.foreignUpper SyntaxError.TStart
              end <- getPosition
              let region = Ann.Region start end
              return . Ann.At region $ (case upper of
                  Var.Unqualified name ->
                    Src.TType region name []

                  Var.Qualified home name ->
                    Src.TTypeQual region home name [])
        ,
          -- type variables
          do  var <- Var.lower SyntaxError.TStart
              addEnd start (Src.TVar var)
        ,
          -- tuples
          inContext SyntaxError.TTuple (word1 0x28 {-(-} SyntaxError.TStart) $
            oneOf SyntaxError.TTupleOpen
              [ do  word1 0x29 {-)-} SyntaxError.TTupleOpen
                    addEnd start Src.TUnit
              , do  Space.chompAndCheckIndent SyntaxError.TTupleSpace SyntaxError.TTupleIndentType1
                    (tipe, end) <- specialize SyntaxError.TTupleType expression
                    Space.checkIndent end SyntaxError.TTupleIndentEnd
                    chompTupleEnd start tipe []
              ]
        ,
          -- records
          inContext SyntaxError.TRecord (word1 0x7B {- { -} SyntaxError.TStart) $
            do  Space.chompAndCheckIndent SyntaxError.TRecordSpace SyntaxError.TRecordIndentOpen
                oneOf SyntaxError.TRecordOpen
                  [ do  word1 0x7D {-}-} SyntaxError.TRecordEnd
                        addEnd start (Src.TRecord [] Nothing)
                  , do  name <- addLocation (Var.lower SyntaxError.TRecordField)
                        Space.chompAndCheckIndent SyntaxError.TRecordSpace SyntaxError.TRecordIndentColon
                        oneOf SyntaxError.TRecordColon
                          [ do  word1 0x7C {-|-} SyntaxError.TRecordColon
                                Space.chompAndCheckIndent SyntaxError.TRecordSpace SyntaxError.TRecordIndentField
                                field <- chompField
                                fields <- chompRecordEnd [field]
                                addEnd start (Src.TRecord fields (Just name))
                          , do  word1 0x3A {-:-} SyntaxError.TRecordColon
                                Space.chompAndCheckIndent SyntaxError.TRecordSpace SyntaxError.TRecordIndentType
                                (tipe, end) <- specialize SyntaxError.TRecordType expression
                                Space.checkIndent end SyntaxError.TRecordIndentEnd
                                fields <- chompRecordEnd [(name, tipe)]
                                addEnd start (Src.TRecord fields Nothing)
                          ]
                  ]
        ]



-- TYPE EXPRESSIONS


-- | Parse a complete type expression, including function arrows.
--
-- Handles the full precedence hierarchy: a leading type constructor
-- application or atomic term, optionally followed by @->@ and a
-- recursive type expression.  Returns the parsed type paired with its
-- end position for indentation tracking.
--
-- @since 0.19.1
expression :: Space.Parser SyntaxError.Type Src.Type
expression =
  do  start <- getPosition
      term1@(tipe1, end1) <-
        oneOf SyntaxError.TStart
          [ app start
          , do  eterm <- term
                end <- getPosition
                Space.chomp SyntaxError.TSpace
                return (eterm, end)
          ]
      oneOfWithFallback
        [ do  Space.checkIndent end1 SyntaxError.TIndentStart -- should never trigger
              word2 0x2D 0x3E {-->-} SyntaxError.TStart -- could just be another type instead
              Space.chompAndCheckIndent SyntaxError.TSpace SyntaxError.TIndentStart
              (tipe2, end2) <- expression
              let tipe = Ann.at start end2 (Src.TLambda tipe1 tipe2)
              return ( tipe, end2 )
        ]
        term1



-- TYPE CONSTRUCTORS


app :: Ann.Position -> Space.Parser SyntaxError.Type Src.Type
app start =
  do  upper <- Var.foreignUpper SyntaxError.TStart
      upperEnd <- getPosition
      Space.chomp SyntaxError.TSpace
      (args, end) <- chompArgs [] upperEnd

      let region = Ann.Region start upperEnd
      let tipe =
            case upper of
              Var.Unqualified name ->
                Src.TType region name args

              Var.Qualified home name ->
                Src.TTypeQual region home name args

      return ( Ann.at start end tipe, end )


chompArgs :: [Src.Type] -> Ann.Position -> Space.Parser SyntaxError.Type [Src.Type]
chompArgs args end =
  oneOfWithFallback
    [ do  Space.checkIndent end SyntaxError.TIndentStart
          arg <- term
          newEnd <- getPosition
          Space.chomp SyntaxError.TSpace
          chompArgs (arg:args) newEnd
    ]
    (reverse args, end)



-- TUPLES


chompTupleEnd :: Ann.Position -> Src.Type -> [Src.Type] -> Parser SyntaxError.TTuple Src.Type
chompTupleEnd start firstType revTypes =
  oneOf SyntaxError.TTupleEnd
    [ do  word1 0x2C {-,-} SyntaxError.TTupleEnd
          Space.chompAndCheckIndent SyntaxError.TTupleSpace SyntaxError.TTupleIndentTypeN
          (tipe, end) <- specialize SyntaxError.TTupleType expression
          Space.checkIndent end SyntaxError.TTupleIndentEnd
          chompTupleEnd start firstType (tipe : revTypes)
    , do  word1 0x29 {-)-} SyntaxError.TTupleEnd
          case reverse revTypes of
            [] ->
              return firstType

            secondType : otherTypes ->
              addEnd start (Src.TTuple firstType secondType otherTypes)
    ]



-- RECORD


type Field = ( Ann.Located Name.Name, Src.Type )


chompRecordEnd :: [Field] -> Parser SyntaxError.TRecord [Field]
chompRecordEnd fields =
  oneOf SyntaxError.TRecordEnd
    [ do  word1 0x2C {-,-} SyntaxError.TRecordEnd
          Space.chompAndCheckIndent SyntaxError.TRecordSpace SyntaxError.TRecordIndentField
          field <- chompField
          chompRecordEnd (field : fields)
    , do  word1 0x7D {-}-} SyntaxError.TRecordEnd
          return (reverse fields)
    ]


chompField :: Parser SyntaxError.TRecord Field
chompField =
  do  name <- addLocation (Var.lower SyntaxError.TRecordField)
      Space.chompAndCheckIndent SyntaxError.TRecordSpace SyntaxError.TRecordIndentColon
      word1 0x3A {-:-} SyntaxError.TRecordColon
      Space.chompAndCheckIndent SyntaxError.TRecordSpace SyntaxError.TRecordIndentType
      (tipe, end) <- specialize SyntaxError.TRecordType expression
      Space.checkIndent end SyntaxError.TRecordIndentEnd
      return (name, tipe)



-- VARIANT


-- | Parse a single custom-type variant declaration.
--
-- Reads an uppercase constructor name followed by zero or more type
-- arguments (each parsed as a non-arrow 'term').  Used by the module
-- parser when processing @type@ declarations.
--
-- @since 0.19.1
variant :: Space.Parser SyntaxError.CustomType (Ann.Located Name.Name, [Src.Type])
variant =
  do  name@(Ann.At (Ann.Region _ nameEnd) _) <- addLocation (Var.upper SyntaxError.CT_Variant)
      Space.chomp SyntaxError.CT_Space
      (args, end) <- specialize SyntaxError.CT_VariantArg (chompArgs [] nameEnd)
      return ( (name, args), end )

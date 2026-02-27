{-# LANGUAGE OverloadedStrings #-}
module Parse.Declaration
  ( Decl(..)
  , declaration
  , infix_
  )
  where


import qualified Data.Name as Name

import qualified AST.Source as Src
import qualified AST.Utils.Binop as Binop
import qualified Parse.Expression as Expr
import qualified Parse.Pattern as Pattern
import qualified Parse.Keyword as Keyword
import qualified Parse.Number as Number
import qualified Parse.Space as Space
import qualified Parse.Symbol as Symbol
import qualified Parse.Type as Type
import qualified Parse.Variable as Var
import Parse.Primitives hiding (State)
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError



-- DECLARATION


data Decl
  = Value (Maybe Src.Comment) (Ann.Located Src.Value)
  | Union (Maybe Src.Comment) (Ann.Located Src.Union)
  | Alias (Maybe Src.Comment) (Ann.Located Src.Alias)
  | Port (Maybe Src.Comment) Src.Port


declaration :: Space.Parser SyntaxError.Decl Decl
declaration =
  do  maybeDocs <- chompDocComment
      start <- getPosition
      oneOf SyntaxError.DeclStart
        [ typeDecl maybeDocs start
        , portDecl maybeDocs
        , valueDecl maybeDocs start
        ]



-- DOC COMMENT


chompDocComment :: Parser SyntaxError.Decl (Maybe Src.Comment)
chompDocComment =
  oneOfWithFallback
    [
      do  docComment <- Space.docComment SyntaxError.DeclStart SyntaxError.DeclSpace
          Space.chomp SyntaxError.DeclSpace
          Space.checkFreshLine SyntaxError.DeclFreshLineAfterDocComment
          return (Just docComment)
    ]
    Nothing



-- DEFINITION and ANNOTATION


{-# INLINE valueDecl #-}
valueDecl :: Maybe Src.Comment -> Ann.Position -> Space.Parser SyntaxError.Decl Decl
valueDecl maybeDocs start =
  do  name <- Var.lower SyntaxError.DeclStart
      end <- getPosition
      specialize (SyntaxError.DeclDef name) $
        do  Space.chompAndCheckIndent SyntaxError.DeclDefSpace SyntaxError.DeclDefIndentEquals
            oneOf SyntaxError.DeclDefEquals
              [
                do  word1 0x3A {-:-} SyntaxError.DeclDefEquals
                    Space.chompAndCheckIndent SyntaxError.DeclDefSpace SyntaxError.DeclDefIndentType
                    (tipe, _) <- specialize SyntaxError.DeclDefType Type.expression
                    Space.checkFreshLine SyntaxError.DeclDefNameRepeat
                    defName <- chompMatchingName name
                    Space.chompAndCheckIndent SyntaxError.DeclDefSpace SyntaxError.DeclDefIndentEquals
                    chompDefArgsAndBody maybeDocs start defName (Just tipe) []
              ,
                chompDefArgsAndBody maybeDocs start (Ann.at start end name) Nothing []
              ]


chompDefArgsAndBody :: Maybe Src.Comment -> Ann.Position -> Ann.Located Name.Name -> Maybe Src.Type -> [Src.Pattern] -> Space.Parser SyntaxError.DeclDef Decl
chompDefArgsAndBody maybeDocs start name tipe revArgs =
  oneOf SyntaxError.DeclDefEquals
    [ do  arg <- specialize SyntaxError.DeclDefArg Pattern.term
          Space.chompAndCheckIndent SyntaxError.DeclDefSpace SyntaxError.DeclDefIndentEquals
          chompDefArgsAndBody maybeDocs start name tipe (arg : revArgs)
    , do  word1 0x3D {-=-} SyntaxError.DeclDefEquals
          Space.chompAndCheckIndent SyntaxError.DeclDefSpace SyntaxError.DeclDefIndentBody
          (body, end) <- specialize SyntaxError.DeclDefBody Expr.expression
          let value = Src.Value name (reverse revArgs) body tipe
          let avalue = Ann.at start end value
          return (Value maybeDocs avalue, end)
    ]


chompMatchingName :: Name.Name -> Parser SyntaxError.DeclDef (Ann.Located Name.Name)
chompMatchingName expectedName =
  let
    (Parse.Parser parserL) = Var.lower SyntaxError.DeclDefNameRepeat
  in
  Parse.Parser $ \state@(Parse.State _ _ _ _ sr sc) cok eok cerr eerr ->
    let
      cokL name newState@(Parse.State _ _ _ _ er ec) =
        if expectedName == name
        then cok (Ann.At (Ann.Region (Ann.Position sr sc) (Ann.Position er ec)) name) newState
        else cerr sr sc (SyntaxError.DeclDefNameMatch name)

      eokL name newState@(Parse.State _ _ _ _ er ec) =
        if expectedName == name
        then eok (Ann.At (Ann.Region (Ann.Position sr sc) (Ann.Position er ec)) name) newState
        else eerr sr sc (SyntaxError.DeclDefNameMatch name)
    in
    parserL state cokL eokL cerr eerr



-- TYPE DECLARATIONS


{-# INLINE typeDecl #-}
typeDecl :: Maybe Src.Comment -> Ann.Position -> Space.Parser SyntaxError.Decl Decl
typeDecl maybeDocs start =
  inContext SyntaxError.DeclType (Keyword.type_ SyntaxError.DeclStart) $
    do  Space.chompAndCheckIndent SyntaxError.DT_Space SyntaxError.DT_IndentName
        oneOf SyntaxError.DT_Name
          [
            inContext SyntaxError.DT_Alias (Keyword.alias_ SyntaxError.DT_Name) $
              do  Space.chompAndCheckIndent SyntaxError.AliasSpace SyntaxError.AliasIndentEquals
                  (name, args) <- chompAliasNameToEquals
                  (tipe, end) <- specialize SyntaxError.AliasBody Type.expression
                  let alias = Ann.at start end (Src.Alias name args tipe)
                  return (Alias maybeDocs alias, end)
          ,
            specialize SyntaxError.DT_Union $
              do  (name, args) <- chompCustomNameToEquals
                  (firstVariant, firstEnd) <- Type.variant
                  (variants, end) <- chompVariants [firstVariant] firstEnd
                  let union = Ann.at start end (Src.Union name args variants)
                  return (Union maybeDocs union, end)
          ]



-- TYPE ALIASES


chompAliasNameToEquals :: Parser SyntaxError.TypeAlias (Ann.Located Name.Name, [Ann.Located Name.Name])
chompAliasNameToEquals =
  do  name <- addLocation (Var.upper SyntaxError.AliasName)
      Space.chompAndCheckIndent SyntaxError.AliasSpace SyntaxError.AliasIndentEquals
      chompAliasNameToEqualsHelp name []


chompAliasNameToEqualsHelp :: Ann.Located Name.Name -> [Ann.Located Name.Name] -> Parser SyntaxError.TypeAlias (Ann.Located Name.Name, [Ann.Located Name.Name])
chompAliasNameToEqualsHelp name args =
  oneOf SyntaxError.AliasEquals
    [ do  arg <- addLocation (Var.lower SyntaxError.AliasEquals)
          Space.chompAndCheckIndent SyntaxError.AliasSpace SyntaxError.AliasIndentEquals
          chompAliasNameToEqualsHelp name (arg:args)
    , do  word1 0x3D {-=-} SyntaxError.AliasEquals
          Space.chompAndCheckIndent SyntaxError.AliasSpace SyntaxError.AliasIndentBody
          return ( name, reverse args )
    ]



-- CUSTOM TYPES


chompCustomNameToEquals :: Parser SyntaxError.CustomType (Ann.Located Name.Name, [Ann.Located Name.Name])
chompCustomNameToEquals =
  do  name <- addLocation (Var.upper SyntaxError.CT_Name)
      Space.chompAndCheckIndent SyntaxError.CT_Space SyntaxError.CT_IndentEquals
      chompCustomNameToEqualsHelp name []


chompCustomNameToEqualsHelp :: Ann.Located Name.Name -> [Ann.Located Name.Name] -> Parser SyntaxError.CustomType (Ann.Located Name.Name, [Ann.Located Name.Name])
chompCustomNameToEqualsHelp name args =
  oneOf SyntaxError.CT_Equals
    [ do  arg <- addLocation (Var.lower SyntaxError.CT_Equals)
          Space.chompAndCheckIndent SyntaxError.CT_Space SyntaxError.CT_IndentEquals
          chompCustomNameToEqualsHelp name (arg:args)
    , do  word1 0x3D {-=-} SyntaxError.CT_Equals
          Space.chompAndCheckIndent SyntaxError.CT_Space SyntaxError.CT_IndentAfterEquals
          return ( name, reverse args )
    ]


chompVariants :: [(Ann.Located Name.Name, [Src.Type])] -> Ann.Position -> Space.Parser SyntaxError.CustomType [(Ann.Located Name.Name, [Src.Type])]
chompVariants variants end =
  oneOfWithFallback
    [ do  Space.checkIndent end SyntaxError.CT_IndentBar
          word1 0x7C {-|-} SyntaxError.CT_Bar
          Space.chompAndCheckIndent SyntaxError.CT_Space SyntaxError.CT_IndentAfterBar
          (variant, newEnd) <- Type.variant
          chompVariants (variant:variants) newEnd
    ]
    (reverse variants, end)



-- PORT


{-# INLINE portDecl #-}
portDecl :: Maybe Src.Comment -> Space.Parser SyntaxError.Decl Decl
portDecl maybeDocs =
  inContext SyntaxError.Port (Keyword.port_ SyntaxError.DeclStart) $
    do  Space.chompAndCheckIndent SyntaxError.PortSpace SyntaxError.PortIndentName
        name <- addLocation (Var.lower SyntaxError.PortName)
        Space.chompAndCheckIndent SyntaxError.PortSpace SyntaxError.PortIndentColon
        word1 0x3A {-:-} SyntaxError.PortColon
        Space.chompAndCheckIndent SyntaxError.PortSpace SyntaxError.PortIndentType
        (tipe, end) <- specialize SyntaxError.PortType Type.expression
        return
          ( Port maybeDocs (Src.Port name tipe)
          , end
          )



-- INFIX


-- INVARIANT: always chomps to a freshline
--
infix_ :: Parser SyntaxError.Module (Ann.Located Src.Infix)
infix_ =
  let
    err = SyntaxError.Infix
    _err _ = SyntaxError.Infix
  in
  do  start <- getPosition
      Keyword.infix_ err
      Space.chompAndCheckIndent _err err
      associativity <-
        oneOf err
          [ Keyword.left_  err >> return Binop.Left
          , Keyword.right_ err >> return Binop.Right
          , Keyword.non_   err >> return Binop.Non
          ]
      Space.chompAndCheckIndent _err err
      precedence <- Number.precedence err
      Space.chompAndCheckIndent _err err
      word1 0x28 {-(-} err
      op <- Symbol.operator err _err
      word1 0x29 {-)-} err
      Space.chompAndCheckIndent _err err
      word1 0x3D {-=-} err
      Space.chompAndCheckIndent _err err
      name <- Var.lower err
      end <- getPosition
      Space.chomp _err
      Space.checkFreshLine err
      return (Ann.at start end (Src.Infix op associativity precedence name))

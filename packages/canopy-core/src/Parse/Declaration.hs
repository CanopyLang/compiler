{-# LANGUAGE OverloadedStrings #-}
module Parse.Declaration
  ( Decl(..)
  , declaration
  , infix_
  )
  where


import qualified Canopy.Data.Name as Name

import AST.Source (GuardAnnotation (..))
import AST.Source (SupertypeBound (..))
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
                    maybeGuard <- chompOptionalGuard
                    Space.checkFreshLine SyntaxError.DeclDefNameRepeat
                    defName <- chompMatchingName name
                    Space.chompAndCheckIndent SyntaxError.DeclDefSpace SyntaxError.DeclDefIndentEquals
                    chompDefArgsAndBody maybeDocs start defName (Just tipe) maybeGuard []
              ,
                chompDefArgsAndBody maybeDocs start (Ann.at start end name) Nothing Nothing []
              ]


-- | Optionally parse a @guards@ clause after a type annotation.
--
-- Syntax: @guards ConstructorName typeArgs...@
--
-- The guard clause narrows the first argument to the specified type
-- when the function is used as an @if@ condition.
--
-- @since 0.20.0
chompOptionalGuard :: Parser SyntaxError.DeclDef (Maybe GuardAnnotation)
chompOptionalGuard =
  oneOfWithFallback
    [ do  Keyword.guards_ SyntaxError.DeclDefEquals
          Space.chompAndCheckIndent SyntaxError.DeclDefSpace SyntaxError.DeclDefIndentType
          (narrowType, _) <- specialize SyntaxError.DeclDefType Type.expression
          return (Just (GuardAnnotation 0 narrowType))
    ]
    Nothing


chompDefArgsAndBody :: Maybe Src.Comment -> Ann.Position -> Ann.Located Name.Name -> Maybe Src.Type -> Maybe GuardAnnotation -> [Src.Pattern] -> Space.Parser SyntaxError.DeclDef Decl
chompDefArgsAndBody maybeDocs start name tipe guard revArgs =
  oneOf SyntaxError.DeclDefEquals
    [ do  arg <- specialize SyntaxError.DeclDefArg Pattern.term
          Space.chompAndCheckIndent SyntaxError.DeclDefSpace SyntaxError.DeclDefIndentEquals
          chompDefArgsAndBody maybeDocs start name tipe guard (arg : revArgs)
    , do  word1 0x3D {-=-} SyntaxError.DeclDefEquals
          Space.chompAndCheckIndent SyntaxError.DeclDefSpace SyntaxError.DeclDefIndentBody
          (body, end) <- specialize SyntaxError.DeclDefBody Expr.expression
          let value = Src.Value name (reverse revArgs) body tipe guard
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
                  (name, args, variances) <- chompAliasNameToEquals
                  maybeBound <- chompOptionalBound
                  (tipe, end) <- specialize SyntaxError.AliasBody Type.expression
                  let alias = Ann.at start end (Src.Alias name args variances tipe maybeBound)
                  return (Alias maybeDocs alias, end)
          ,
            specialize SyntaxError.DT_Union $
              do  (name, args, variances) <- chompCustomNameToEquals
                  (firstVariant, firstEnd) <- Type.variant
                  (variants, end) <- chompVariants [firstVariant] firstEnd
                  let union = Ann.at start end (Src.Union name args variances variants)
                  return (Union maybeDocs union, end)
          ]



-- TYPE ALIASES


chompAliasNameToEquals :: Parser SyntaxError.TypeAlias (Ann.Located Name.Name, [Ann.Located Name.Name], [Src.Variance])
chompAliasNameToEquals =
  do  name <- addLocation (Var.upper SyntaxError.AliasName)
      Space.chompAndCheckIndent SyntaxError.AliasSpace SyntaxError.AliasIndentEquals
      chompAliasNameToEqualsHelp name [] []


chompAliasNameToEqualsHelp :: Ann.Located Name.Name -> [Ann.Located Name.Name] -> [Src.Variance] -> Parser SyntaxError.TypeAlias (Ann.Located Name.Name, [Ann.Located Name.Name], [Src.Variance])
chompAliasNameToEqualsHelp name args variances =
  oneOf SyntaxError.AliasEquals
    [ do  (arg, variance) <- chompVarianceParam SyntaxError.AliasEquals
          Space.chompAndCheckIndent SyntaxError.AliasSpace SyntaxError.AliasIndentEquals
          chompAliasNameToEqualsHelp name (arg:args) (variance:variances)
    , do  word1 0x3D {-=-} SyntaxError.AliasEquals
          Space.chompAndCheckIndent SyntaxError.AliasSpace SyntaxError.AliasIndentBody
          return ( name, reverse args, reverse variances )
    ]



-- VARIANCE PARAMETERS


-- | Parse a type parameter with an optional variance annotation.
--
-- Syntax:
--
--   * @(+varname)@ for covariant
--   * @(-varname)@ for contravariant
--   * @varname@ for invariant (default)
--
-- @since 0.20.0
chompVarianceParam :: (Row -> Col -> x) -> Parser x (Ann.Located Name.Name, Src.Variance)
chompVarianceParam toError =
  oneOf toError
    [ do  word1 0x28 {-(-} toError
          variance <- chompVarianceMarker toError
          arg <- addLocation (Var.lower toError)
          word1 0x29 {-)-} toError
          return (arg, variance)
    , do  arg <- addLocation (Var.lower toError)
          return (arg, Src.Invariant)
    ]


-- | Parse a variance marker: @+@ for covariant, @-@ for contravariant.
--
-- @since 0.20.0
chompVarianceMarker :: (Row -> Col -> x) -> Parser x Src.Variance
chompVarianceMarker toError =
  oneOf toError
    [ do  word1 0x2B {-+-} toError
          return Src.Covariant
    , do  word1 0x2D {---} toError
          return Src.Contravariant
    ]



-- SUPERTYPE BOUNDS


-- | Optionally parse a supertype bound before the type body in a type alias.
--
-- Syntax: @comparable =>@, @appendable =>@, @number =>@, @compappend =>@
--
-- The bound keyword must be followed by @=>@ and then whitespace. If no
-- bound keyword is found, returns 'Nothing' without consuming input.
--
-- @since 0.20.0
chompOptionalBound :: Parser SyntaxError.TypeAlias (Maybe Src.SupertypeBound)
chompOptionalBound =
  oneOfWithFallback
    [ chompBound Keyword.comparable_ ComparableBound,
      chompBound Keyword.appendable_ AppendableBound,
      chompBound Keyword.number_ NumberBound,
      chompBound Keyword.compappend_ CompAppendBound
    ]
    Nothing


-- | Parse a specific bound keyword followed by @=>@ and whitespace.
chompBound :: ((Row -> Col -> SyntaxError.TypeAlias) -> Parser SyntaxError.TypeAlias ()) -> Src.SupertypeBound -> Parser SyntaxError.TypeAlias (Maybe Src.SupertypeBound)
chompBound keywordParser bound =
  do  keywordParser SyntaxError.AliasEquals
      Space.chompAndCheckIndent SyntaxError.AliasSpace SyntaxError.AliasIndentBody
      word2 0x3D 0x3E {-=>-} SyntaxError.AliasEquals
      Space.chompAndCheckIndent SyntaxError.AliasSpace SyntaxError.AliasIndentBody
      return (Just bound)


-- CUSTOM TYPES


chompCustomNameToEquals :: Parser SyntaxError.CustomType (Ann.Located Name.Name, [Ann.Located Name.Name], [Src.Variance])
chompCustomNameToEquals =
  do  name <- addLocation (Var.upper SyntaxError.CT_Name)
      Space.chompAndCheckIndent SyntaxError.CT_Space SyntaxError.CT_IndentEquals
      chompCustomNameToEqualsHelp name [] []


chompCustomNameToEqualsHelp :: Ann.Located Name.Name -> [Ann.Located Name.Name] -> [Src.Variance] -> Parser SyntaxError.CustomType (Ann.Located Name.Name, [Ann.Located Name.Name], [Src.Variance])
chompCustomNameToEqualsHelp name args variances =
  oneOf SyntaxError.CT_Equals
    [ do  (arg, variance) <- chompVarianceParam SyntaxError.CT_Equals
          Space.chompAndCheckIndent SyntaxError.CT_Space SyntaxError.CT_IndentEquals
          chompCustomNameToEqualsHelp name (arg:args) (variance:variances)
    , do  word1 0x3D {-=-} SyntaxError.CT_Equals
          Space.chompAndCheckIndent SyntaxError.CT_Space SyntaxError.CT_IndentAfterEquals
          return ( name, reverse args, reverse variances )
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

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Parse.Module
  ( fromByteString,
    ProjectType (..),
    isKernel,
    chompImports,
    chompImport,
  )
where

import qualified AST.Source as Src
import qualified Canopy.Compiler.Imports as Imports
import qualified Canopy.Package as Pkg
import qualified Data.ByteString as BS
import qualified Data.Name as Name
import qualified Parse.Declaration as Decl
import qualified Parse.Keyword as Keyword
import Parse.Primitives hiding (State, fromByteString)
import qualified Parse.Primitives as P
import qualified Parse.Space as Space
import qualified Parse.Symbol as Symbol
import qualified Parse.Variable as Var
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as E
import qualified Foreign.FFI as FFI
import qualified Parse.String as String
import qualified Canopy.String as ES

-- FROM BYTE STRING

fromByteString :: ProjectType -> BS.ByteString -> Either E.Error Src.Module
fromByteString projectType source =
  case P.fromByteString (chompModule projectType) E.ModuleBadEnd source of
    Right modul -> checkModule projectType modul
    Left err -> Left (E.ParseError err)

-- PROJECT TYPE

data ProjectType
  = Package Pkg.Name
  | Application

isCore :: ProjectType -> Bool
isCore projectType =
  case projectType of
    Package pkg -> Pkg.isCore pkg
    Application -> False

isKernel :: ProjectType -> Bool
isKernel projectType =
  case projectType of
    Package pkg -> Pkg.isKernel pkg
    Application -> False

-- MODULE

data Module = Module
  { _header :: Maybe Header,
    _imports :: [Src.Import],
    _foreignImports :: [Src.ForeignImport],
    _infixes :: [A.Located Src.Infix],
    _decls :: [Decl.Decl]
  }

chompModule :: ProjectType -> Parser E.Module Module
chompModule projectType =
  do
    header <- chompHeader
    (imports, foreignImports) <- chompAllImports (if isCore projectType then [] else Imports.defaults) []
    infixes <- if isKernel projectType then chompInfixes [] else return []
    decls <- specialize E.Declarations $ chompDecls []
    return (Module header imports foreignImports infixes decls)

-- CHECK MODULE

checkModule :: ProjectType -> Module -> Either E.Error Src.Module
checkModule projectType (Module maybeHeader imports foreignImports infixes decls) =
  let (values, unions, aliases, ports) = categorizeDecls [] [] [] [] decls
   in case maybeHeader of
        Just (Header name effects exports docs) ->
          Src.Module (Just name) exports (toDocs docs decls) imports foreignImports values unions aliases infixes
            <$> checkEffects projectType ports effects
        Nothing ->
          Right . Src.Module Nothing (A.At A.one Src.Open) (Src.NoDocs A.one) imports foreignImports values unions aliases infixes $
            ( case ports of
                [] -> Src.NoEffects
                _ : _ -> Src.Ports ports
            )

checkEffects :: ProjectType -> [Src.Port] -> Effects -> Either E.Error Src.Effects
checkEffects projectType ports effects =
  case effects of
    NoEffects region ->
      case ports of
        [] ->
          Right Src.NoEffects
        Src.Port name _ : _ ->
          case projectType of
            Package _ -> Left (E.NoPortsInPackage name)
            Application -> Left (E.UnexpectedPort region)
    Ports region ->
      case projectType of
        Package _ ->
          Left (E.NoPortModulesInPackage region)
        Application ->
          case ports of
            [] -> Left (E.NoPorts region)
            _ : _ -> Right (Src.Ports ports)
    Manager region manager ->
      if isKernel projectType
        then case ports of
          [] -> Right (Src.Manager region manager)
          _ : _ -> Left (E.UnexpectedPort region)
        else Left (E.NoEffectsOutsideKernel region)

categorizeDecls :: [A.Located Src.Value] -> [A.Located Src.Union] -> [A.Located Src.Alias] -> [Src.Port] -> [Decl.Decl] -> ([A.Located Src.Value], [A.Located Src.Union], [A.Located Src.Alias], [Src.Port])
categorizeDecls values unions aliases ports decls =
  case decls of
    [] ->
      (values, unions, aliases, ports)
    decl : otherDecls ->
      case decl of
        Decl.Value _ value -> categorizeDecls (value : values) unions aliases ports otherDecls
        Decl.Union _ union -> categorizeDecls values (union : unions) aliases ports otherDecls
        Decl.Alias _ alias -> categorizeDecls values unions (alias : aliases) ports otherDecls
        Decl.Port _ port_ -> categorizeDecls values unions aliases (port_ : ports) otherDecls

-- TO DOCS

toDocs :: Either A.Region Src.Comment -> [Decl.Decl] -> Src.Docs
toDocs comment decls =
  case comment of
    Right overview ->
      Src.YesDocs overview (getComments decls [])
    Left region ->
      Src.NoDocs region

getComments :: [Decl.Decl] -> [(Name.Name, Src.Comment)] -> [(Name.Name, Src.Comment)]
getComments decls comments =
  case decls of
    [] ->
      comments
    decl : otherDecls ->
      case decl of
        Decl.Value c (A.At _ (Src.Value n _ _ _)) -> getComments otherDecls (addComment c n comments)
        Decl.Union c (A.At _ (Src.Union n _ _)) -> getComments otherDecls (addComment c n comments)
        Decl.Alias c (A.At _ (Src.Alias n _ _)) -> getComments otherDecls (addComment c n comments)
        Decl.Port c (Src.Port n _) -> getComments otherDecls (addComment c n comments)

addComment :: Maybe Src.Comment -> A.Located Name.Name -> [(Name.Name, Src.Comment)] -> [(Name.Name, Src.Comment)]
addComment maybeComment (A.At _ name) comments =
  case maybeComment of
    Just comment -> (name, comment) : comments
    Nothing -> comments

-- FRESH LINES

freshLine :: (Row -> Col -> E.Module) -> Parser E.Module ()
freshLine toFreshLineError =
  do
    Space.chomp E.ModuleSpace
    Space.checkFreshLine toFreshLineError

-- CHOMP DECLARATIONS

chompDecls :: [Decl.Decl] -> Parser E.Decl [Decl.Decl]
chompDecls decls =
  do
    (decl, _) <- Decl.declaration
    oneOfWithFallback
      [ do
          Space.checkFreshLine E.DeclStart
          chompDecls (decl : decls)
      ]
      (reverse (decl : decls))

chompInfixes :: [A.Located Src.Infix] -> Parser E.Module [A.Located Src.Infix]
chompInfixes infixes =
  oneOfWithFallback
    [ do
        binop <- Decl.infix_
        chompInfixes (binop : infixes)
    ]
    infixes

-- MODULE DOC COMMENT

chompModuleDocCommentSpace :: Parser E.Module (Either A.Region Src.Comment)
chompModuleDocCommentSpace =
  do
    (A.At region ()) <- addLocation (freshLine E.FreshLine)
    oneOfWithFallback
      [ do
          docComment <- Space.docComment E.ImportStart E.ModuleSpace
          Space.chomp E.ModuleSpace
          Space.checkFreshLine E.FreshLine
          return (Right docComment)
      ]
      (Left region)

-- HEADER

data Header
  = Header (A.Located Name.Name) Effects (A.Located Src.Exposing) (Either A.Region Src.Comment)

data Effects
  = NoEffects A.Region
  | Ports A.Region
  | Manager A.Region Src.Manager

chompHeader :: Parser E.Module (Maybe Header)
chompHeader =
  do
    freshLine E.FreshLine
    start <- getPosition
    oneOfWithFallback
      [ -- module MyThing exposing (..)
        do
          Keyword.module_ E.ModuleProblem
          effectEnd <- getPosition
          Space.chompAndCheckIndent E.ModuleSpace E.ModuleProblem
          name <- addLocation (Var.moduleName E.ModuleName)
          Space.chompAndCheckIndent E.ModuleSpace E.ModuleProblem
          Keyword.exposing_ E.ModuleProblem
          Space.chompAndCheckIndent E.ModuleSpace E.ModuleProblem
          exports <- addLocation (specialize E.ModuleExposing exposing)
          Just . Header name (NoEffects (A.Region start effectEnd)) exports <$> chompModuleDocCommentSpace,
        -- port module MyThing exposing (..)
        do
          Keyword.port_ E.PortModuleProblem
          Space.chompAndCheckIndent E.ModuleSpace E.PortModuleProblem
          Keyword.module_ E.PortModuleProblem
          effectEnd <- getPosition
          Space.chompAndCheckIndent E.ModuleSpace E.PortModuleProblem
          name <- addLocation (Var.moduleName E.PortModuleName)
          Space.chompAndCheckIndent E.ModuleSpace E.PortModuleProblem
          Keyword.exposing_ E.PortModuleProblem
          Space.chompAndCheckIndent E.ModuleSpace E.PortModuleProblem
          exports <- addLocation (specialize E.PortModuleExposing exposing)
          Just . Header name (Ports (A.Region start effectEnd)) exports <$> chompModuleDocCommentSpace,
        -- effect module MyThing where { command = MyCmd } exposing (..)
        do
          Keyword.effect_ E.Effect
          Space.chompAndCheckIndent E.ModuleSpace E.Effect
          Keyword.module_ E.Effect
          effectEnd <- getPosition
          Space.chompAndCheckIndent E.ModuleSpace E.Effect
          name <- addLocation (Var.moduleName E.ModuleName)
          Space.chompAndCheckIndent E.ModuleSpace E.Effect
          Keyword.where_ E.Effect
          Space.chompAndCheckIndent E.ModuleSpace E.Effect
          manager <- chompManager
          Space.chompAndCheckIndent E.ModuleSpace E.Effect
          Keyword.exposing_ E.Effect
          Space.chompAndCheckIndent E.ModuleSpace E.Effect
          exports <- addLocation (specialize (const E.Effect) exposing)
          Just . Header name (Manager (A.Region start effectEnd) manager) exports <$> chompModuleDocCommentSpace
      ]
      -- default header
      Nothing

chompManager :: Parser E.Module Src.Manager
chompManager =
  do
    word1 0x7B {- { -} E.Effect
    spacesEm
    oneOf
      E.Effect
      [ do
          cmd <- chompCommand
          spacesEm
          oneOf
            E.Effect
            [ do
                word1 0x7D {-}-} E.Effect
                spacesEm
                return (Src.Cmd cmd),
              do
                word1 0x2C {-,-} E.Effect
                spacesEm
                sub <- chompSubscription
                spacesEm
                word1 0x7D {-}-} E.Effect
                spacesEm
                return (Src.Fx cmd sub)
            ],
        do
          sub <- chompSubscription
          spacesEm
          oneOf
            E.Effect
            [ do
                word1 0x7D {-}-} E.Effect
                spacesEm
                return (Src.Sub sub),
              do
                word1 0x2C {-,-} E.Effect
                spacesEm
                cmd <- chompCommand
                spacesEm
                word1 0x7D {-}-} E.Effect
                spacesEm
                return (Src.Fx cmd sub)
            ]
      ]

chompCommand :: Parser E.Module (A.Located Name.Name)
chompCommand =
  do
    Keyword.command_ E.Effect
    spacesEm
    word1 0x3D {-=-} E.Effect
    spacesEm
    addLocation (Var.upper E.Effect)

chompSubscription :: Parser E.Module (A.Located Name.Name)
chompSubscription =
  do
    Keyword.subscription_ E.Effect
    spacesEm
    word1 0x3D {-=-} E.Effect
    spacesEm
    addLocation (Var.upper E.Effect)

spacesEm :: Parser E.Module ()
spacesEm =
  Space.chompAndCheckIndent E.ModuleSpace E.Effect

-- IMPORTS

chompAllImports :: [Src.Import] -> [Src.ForeignImport] -> Parser E.Module ([Src.Import], [Src.ForeignImport])
chompAllImports imports foreignImports =
  oneOfWithFallback
    [ do
        foreignImport_ <- chompForeignImport
        chompAllImports imports (foreignImport_ : foreignImports),
      do
        import_ <- chompImport
        chompAllImports (import_ : imports) foreignImports
    ]
    (reverse imports, reverse foreignImports)

chompImports :: [Src.Import] -> Parser E.Module [Src.Import]
chompImports is =
  oneOfWithFallback
    [ do
        i <- chompImport
        chompImports (i : is)
    ]
    (reverse is)

chompImport :: Parser E.Module Src.Import
chompImport =
  do
    Keyword.import_ E.ImportStart
    Space.chompAndCheckIndent E.ModuleSpace E.ImportIndentName
    name@(A.At (A.Region _ end) _) <- addLocation (Var.moduleName E.ImportName)
    Space.chomp E.ModuleSpace
    oneOf
      E.ImportEnd
      [ do
          Space.checkFreshLine E.ImportEnd
          return $ Src.Import name Nothing (Src.Explicit []),
        do
          Space.checkIndent end E.ImportEnd
          oneOf
            E.ImportAs
            [ chompAs name,
              chompExposing name Nothing
            ]
      ]

chompAs :: A.Located Name.Name -> Parser E.Module Src.Import
chompAs name =
  do
    Keyword.as_ E.ImportAs
    Space.chompAndCheckIndent E.ModuleSpace E.ImportIndentAlias
    alias <- Var.upper E.ImportAlias
    end <- getPosition
    Space.chomp E.ModuleSpace
    oneOf
      E.ImportEnd
      [ do
          Space.checkFreshLine E.ImportEnd
          return $ Src.Import name (Just alias) (Src.Explicit []),
        do
          Space.checkIndent end E.ImportEnd
          chompExposing name (Just alias)
      ]

chompExposing :: A.Located Name.Name -> Maybe Name.Name -> Parser E.Module Src.Import
chompExposing name maybeAlias =
  do
    Keyword.exposing_ E.ImportExposing
    Space.chompAndCheckIndent E.ModuleSpace E.ImportIndentExposingList
    exposed <- specialize E.ImportExposingList exposing
    freshLine E.ImportEnd
    return $ Src.Import name maybeAlias exposed

-- FOREIGN IMPORTS

chompForeignImport :: Parser E.Module Src.ForeignImport
chompForeignImport =
  do
    start <- getPosition
    Keyword.foreign_ E.ImportStart
    Space.chompAndCheckIndent E.ModuleSpace E.ImportIndentName
    Keyword.import_ E.ImportStart
    Space.chompAndCheckIndent E.ModuleSpace E.ImportIndentName
    target <- chompForeignTarget
    Space.chompAndCheckIndent E.ModuleSpace E.ImportIndentAlias
    Keyword.as_ E.ImportAs
    Space.chompAndCheckIndent E.ModuleSpace E.ImportIndentAlias
    alias <- addLocation (Var.upper E.ImportAlias)
    end <- getPosition
    freshLine E.ImportEnd
    let region = A.Region start end
    return $ Src.ForeignImport target alias region

chompForeignTarget :: Parser E.Module FFI.FFITarget
chompForeignTarget =
  oneOf
    E.ImportName
    [ do
        Keyword.javascript_ E.ImportName
        Space.chompAndCheckIndent E.ModuleSpace E.ImportIndentName
        path <- parseStringLiteral E.ImportName
        return (FFI.JavaScriptFFI path)
    ]

parseStringLiteral :: (Row -> Col -> E.Module) -> Parser E.Module String
parseStringLiteral toError =
  do
    esString <- String.string toError (\_ _ _ -> toError 0 0)
    return (ES.toChars esString)

-- LISTING

exposing :: Parser E.Exposing Src.Exposing
exposing =
  do
    word1 0x28 {-(-} E.ExposingStart
    Space.chompAndCheckIndent E.ExposingSpace E.ExposingIndentValue
    oneOf
      E.ExposingValue
      [ do
          word2 0x2E 0x2E {-..-} E.ExposingValue
          Space.chompAndCheckIndent E.ExposingSpace E.ExposingIndentEnd
          word1 0x29 {-)-} E.ExposingEnd
          return Src.Open,
        do
          exposed <- chompExposed
          Space.chompAndCheckIndent E.ExposingSpace E.ExposingIndentEnd
          exposingHelp [exposed]
      ]

exposingHelp :: [Src.Exposed] -> Parser E.Exposing Src.Exposing
exposingHelp revExposed =
  oneOf
    E.ExposingEnd
    [ do
        word1 0x2C {-,-} E.ExposingEnd
        Space.chompAndCheckIndent E.ExposingSpace E.ExposingIndentValue
        exposed <- chompExposed
        Space.chompAndCheckIndent E.ExposingSpace E.ExposingIndentEnd
        exposingHelp (exposed : revExposed),
      do
        word1 0x29 {-)-} E.ExposingEnd
        return (Src.Explicit (reverse revExposed))
    ]

chompExposed :: Parser E.Exposing Src.Exposed
chompExposed =
  do
    start <- getPosition
    oneOf
      E.ExposingValue
      [ do
          name <- Var.lower E.ExposingValue
          end <- getPosition
          return . Src.Lower $ A.at start end name,
        do
          word1 0x28 {-(-} E.ExposingValue
          op <- Symbol.operator E.ExposingOperator E.ExposingOperatorReserved
          word1 0x29 {-)-} E.ExposingOperatorRightParen
          end <- getPosition
          return $ Src.Operator (A.Region start end) op,
        do
          name <- Var.upper E.ExposingValue
          end <- getPosition
          Space.chompAndCheckIndent E.ExposingSpace E.ExposingIndentEnd
          Src.Upper (A.at start end name) <$> privacy
      ]

privacy :: Parser E.Exposing Src.Privacy
privacy =
  oneOfWithFallback
    [ do
        word1 0x28 {-(-} E.ExposingTypePrivacy
        Space.chompAndCheckIndent E.ExposingSpace E.ExposingTypePrivacy
        start <- getPosition
        word2 0x2E 0x2E {-..-} E.ExposingTypePrivacy
        end <- getPosition
        Space.chompAndCheckIndent E.ExposingSpace E.ExposingTypePrivacy
        word1 0x29 {-)-} E.ExposingTypePrivacy
        return $ Src.Public (A.Region start end)
    ]
    Src.Private

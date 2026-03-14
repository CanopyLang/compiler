{-# LANGUAGE OverloadedStrings #-}

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
import qualified Canopy.Data.Name as Name
import qualified Parse.Comment as Comment
import qualified Parse.Declaration as Decl
import qualified Parse.Keyword as Keyword
import Parse.Primitives hiding (State, fromByteString)
import qualified Parse.Primitives as Parse
import qualified Parse.Space as Space
import qualified Parse.Symbol as Symbol
import qualified Parse.Variable as Var
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError
import qualified Foreign.FFI as FFI
import qualified Parse.String as String
import qualified Canopy.String as ES

-- FROM BYTE STRING

fromByteString :: ProjectType -> BS.ByteString -> Either SyntaxError.Error Src.Module
fromByteString projectType source =
  case Parse.fromByteString (chompModule projectType) SyntaxError.ModuleBadEnd source of
    Right modul -> attachComments source (checkModule projectType modul)
    Left err -> Left (SyntaxError.ParseError err)

-- | Attach extracted comments to a parsed module.
--
-- Runs the standalone comment scanner on the raw source bytes and
-- stores the result in the module's '_comments' field. This is a
-- separate pass from the parser to avoid modifying the parser's
-- hot path.
attachComments :: BS.ByteString -> Either SyntaxError.Error Src.Module -> Either SyntaxError.Error Src.Module
attachComments source =
  fmap (\m -> m { Src._comments = Comment.extractComments source })

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
    _infixes :: [Ann.Located Src.Infix],
    _decls :: [Decl.Decl]
  }

chompModule :: ProjectType -> Parser SyntaxError.Module Module
chompModule projectType =
  do
    header <- chompHeader
    case header of
      Just (Header _ (FFI _) _ _) ->
        -- FFI modules allow flexible ordering of imports and declarations
        chompFFIModule projectType header
      _ ->
        -- Regular modules follow strict ordering
        do
          (imports, foreignImports) <- chompAllImports (if isCore projectType then [] else Imports.defaults) []
          infixes <- if isKernel projectType then chompInfixes [] else return []
          decls <- specialize SyntaxError.Declarations $ chompDecls []
          return (Module header imports foreignImports infixes decls)

chompFFIModule :: ProjectType -> Maybe Header -> Parser SyntaxError.Module Module
chompFFIModule projectType header =
  do
    (imports, foreignImports, decls) <- chompFFIContent (if isCore projectType then [] else Imports.defaults) [] []
    infixes <- if isKernel projectType then chompInfixes [] else return []
    return (Module header imports foreignImports infixes decls)

chompFFIContent :: [Src.Import] -> [Src.ForeignImport] -> [Decl.Decl] -> Parser SyntaxError.Module ([Src.Import], [Src.ForeignImport], [Decl.Decl])
chompFFIContent imports foreignImports decls =
  oneOfWithFallback
    [ do
        foreignImport_ <- chompForeignImport
        chompFFIContent imports (foreignImport_ : foreignImports) decls,
      do
        import_ <- chompImport
        chompFFIContent (import_ : imports) foreignImports decls,
      do
        (decl, _) <- specialize SyntaxError.Declarations Decl.declaration
        chompFFIContent imports foreignImports (decl : decls)
    ]
    (reverse imports, reverse foreignImports, reverse decls)

-- CHECK MODULE

checkModule :: ProjectType -> Module -> Either SyntaxError.Error Src.Module
checkModule projectType (Module maybeHeader imports foreignImports infixes decls) =
  let (values, unions, aliases, ports, abilities, impls) = categorizeDecls [] [] [] [] [] [] decls
   in case maybeHeader of
        Just (Header name effects exports docs) ->
          fmap (\eff -> Src.Module (Just name) exports (toDocs docs decls) imports foreignImports values unions aliases infixes eff [] abilities impls)
            (checkEffects projectType ports effects)
        Nothing ->
          Right $
            Src.Module Nothing (Ann.At Ann.one Src.Open) (Src.NoDocs Ann.one) imports foreignImports values unions aliases infixes
              (portsToEffects ports)
              [] abilities impls

-- | Convert a port list to effects for headerless modules.
portsToEffects :: [Src.Port] -> Src.Effects
portsToEffects [] = Src.NoEffects
portsToEffects ps@(_ : _) = Src.Ports ps

checkEffects :: ProjectType -> [Src.Port] -> Effects -> Either SyntaxError.Error Src.Effects
checkEffects projectType ports effects =
  case effects of
    NoEffects region ->
      case ports of
        [] ->
          Right Src.NoEffects
        Src.Port name _ : _ ->
          case projectType of
            Package _ -> Left (SyntaxError.NoPortsInPackage name)
            Application -> Left (SyntaxError.UnexpectedPort region)
    Ports region ->
      case projectType of
        Package _ ->
          Left (SyntaxError.NoPortModulesInPackage region)
        Application ->
          case ports of
            [] -> Left (SyntaxError.NoPorts region)
            _ : _ -> Right (Src.Ports ports)
    FFI region ->
      case projectType of
        Package _ ->
          Left (SyntaxError.NoFFIModulesInPackage region)
        Application ->
          case ports of
            [] -> Right (Src.FFI [])  -- Foreign imports handled separately
            _ : _ -> Left (SyntaxError.UnexpectedPort region)
    Manager region manager ->
      if isKernel projectType
        then case ports of
          [] -> Right (Src.Manager region manager)
          _ : _ -> Left (SyntaxError.UnexpectedPort region)
        else Left (SyntaxError.NoEffectsOutsideKernel region)

categorizeDecls :: [Ann.Located Src.Value] -> [Ann.Located Src.Union] -> [Ann.Located Src.Alias] -> [Src.Port] -> [Ann.Located Src.AbilityDecl] -> [Ann.Located Src.ImplDecl] -> [Decl.Decl] -> ([Ann.Located Src.Value], [Ann.Located Src.Union], [Ann.Located Src.Alias], [Src.Port], [Ann.Located Src.AbilityDecl], [Ann.Located Src.ImplDecl])
categorizeDecls values unions aliases ports abilities impls decls =
  case decls of
    [] ->
      (values, unions, aliases, ports, abilities, impls)
    decl : otherDecls ->
      case decl of
        Decl.Value _ value -> categorizeDecls (value : values) unions aliases ports abilities impls otherDecls
        Decl.Union _ union -> categorizeDecls values (union : unions) aliases ports abilities impls otherDecls
        Decl.Alias _ alias -> categorizeDecls values unions (alias : aliases) ports abilities impls otherDecls
        Decl.Port _ port_ -> categorizeDecls values unions aliases (port_ : ports) abilities impls otherDecls
        Decl.Ability _ ability -> categorizeDecls values unions aliases ports (ability : abilities) impls otherDecls
        Decl.Impl _ impl_ -> categorizeDecls values unions aliases ports abilities (impl_ : impls) otherDecls

-- TO DOCS

toDocs :: Either Ann.Region Src.Comment -> [Decl.Decl] -> Src.Docs
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
        Decl.Value c (Ann.At _ (Src.Value n _ _ _ _)) -> getComments otherDecls (addComment c n comments)
        Decl.Union c (Ann.At _ (Src.Union n _ _ _ _)) -> getComments otherDecls (addComment c n comments)
        Decl.Alias c (Ann.At _ (Src.Alias n _ _ _ _ _)) -> getComments otherDecls (addComment c n comments)
        Decl.Port c (Src.Port n _) -> getComments otherDecls (addComment c n comments)
        Decl.Ability c (Ann.At _ (Src.AbilityDecl n _ _ _)) -> getComments otherDecls (addComment c n comments)
        Decl.Impl _ _ -> getComments otherDecls comments

addComment :: Maybe Src.Comment -> Ann.Located Name.Name -> [(Name.Name, Src.Comment)] -> [(Name.Name, Src.Comment)]
addComment maybeComment (Ann.At _ name) comments =
  case maybeComment of
    Just comment -> (name, comment) : comments
    Nothing -> comments

-- FRESH LINES

freshLine :: (Row -> Col -> SyntaxError.Module) -> Parser SyntaxError.Module ()
freshLine toFreshLineError =
  do
    Space.chomp SyntaxError.ModuleSpace
    Space.checkFreshLine toFreshLineError

-- CHOMP DECLARATIONS

chompDecls :: [Decl.Decl] -> Parser SyntaxError.Decl [Decl.Decl]
chompDecls decls =
  do
    (decl, _) <- Decl.declaration
    oneOfWithFallback
      [ do
          Space.checkFreshLine SyntaxError.DeclStart
          chompDecls (decl : decls)
      ]
      (reverse (decl : decls))

chompInfixes :: [Ann.Located Src.Infix] -> Parser SyntaxError.Module [Ann.Located Src.Infix]
chompInfixes infixes =
  oneOfWithFallback
    [ do
        binop <- Decl.infix_
        chompInfixes (binop : infixes)
    ]
    infixes

-- MODULE DOC COMMENT

chompModuleDocCommentSpace :: Parser SyntaxError.Module (Either Ann.Region Src.Comment)
chompModuleDocCommentSpace =
  do
    (Ann.At region ()) <- addLocation (freshLine SyntaxError.FreshLine)
    oneOfWithFallback
      [ do
          docComment <- Space.docComment SyntaxError.ImportStart SyntaxError.ModuleSpace
          Space.chomp SyntaxError.ModuleSpace
          Space.checkFreshLine SyntaxError.FreshLine
          return (Right docComment)
      ]
      (Left region)

-- HEADER

data Header
  = Header (Ann.Located Name.Name) Effects (Ann.Located Src.Exposing) (Either Ann.Region Src.Comment)

data Effects
  = NoEffects Ann.Region
  | Ports Ann.Region
  | Manager Ann.Region Src.Manager
  | FFI Ann.Region

chompHeader :: Parser SyntaxError.Module (Maybe Header)
chompHeader =
  do
    freshLine SyntaxError.FreshLine
    start <- getPosition
    oneOfWithFallback
      [ -- module MyThing exposing (..)
        do
          Keyword.module_ SyntaxError.ModuleProblem
          effectEnd <- getPosition
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ModuleProblem
          name <- addLocation (Var.moduleName SyntaxError.ModuleName)
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ModuleProblem
          Keyword.exposing_ SyntaxError.ModuleProblem
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ModuleProblem
          exports <- addLocation (specialize SyntaxError.ModuleExposing exposing)
          Just . Header name (NoEffects (Ann.Region start effectEnd)) exports <$> chompModuleDocCommentSpace,
        -- port module MyThing exposing (..)
        do
          Keyword.port_ SyntaxError.PortModuleProblem
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.PortModuleProblem
          Keyword.module_ SyntaxError.PortModuleProblem
          effectEnd <- getPosition
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.PortModuleProblem
          name <- addLocation (Var.moduleName SyntaxError.PortModuleName)
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.PortModuleProblem
          Keyword.exposing_ SyntaxError.PortModuleProblem
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.PortModuleProblem
          exports <- addLocation (specialize SyntaxError.PortModuleExposing exposing)
          Just . Header name (Ports (Ann.Region start effectEnd)) exports <$> chompModuleDocCommentSpace,
        -- ffi module MyThing exposing (..)
        do
          Keyword.ffi_ SyntaxError.FFIModuleProblem
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.FFIModuleProblem
          Keyword.module_ SyntaxError.FFIModuleProblem
          effectEnd <- getPosition
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.FFIModuleProblem
          name <- addLocation (Var.moduleName SyntaxError.FFIModuleName)
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.FFIModuleProblem
          Keyword.exposing_ SyntaxError.FFIModuleProblem
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.FFIModuleProblem
          exports <- addLocation (specialize SyntaxError.FFIModuleExposing exposing)
          Just . Header name (FFI (Ann.Region start effectEnd)) exports <$> chompModuleDocCommentSpace,
        -- effect module MyThing where { command = MyCmd } exposing (..)
        do
          Keyword.effect_ SyntaxError.Effect
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.Effect
          Keyword.module_ SyntaxError.Effect
          effectEnd <- getPosition
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.Effect
          name <- addLocation (Var.moduleName SyntaxError.ModuleName)
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.Effect
          Keyword.where_ SyntaxError.Effect
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.Effect
          manager <- chompManager
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.Effect
          Keyword.exposing_ SyntaxError.Effect
          Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.Effect
          exports <- addLocation (specialize (const SyntaxError.Effect) exposing)
          Just . Header name (Manager (Ann.Region start effectEnd) manager) exports <$> chompModuleDocCommentSpace
      ]
      -- default header
      Nothing

chompManager :: Parser SyntaxError.Module Src.Manager
chompManager =
  do
    word1 0x7B {- { -} SyntaxError.Effect
    spacesEm
    oneOf
      SyntaxError.Effect
      [ do
          cmd <- chompCommand
          spacesEm
          oneOf
            SyntaxError.Effect
            [ do
                word1 0x7D {-}-} SyntaxError.Effect
                spacesEm
                return (Src.Cmd cmd),
              do
                word1 0x2C {-,-} SyntaxError.Effect
                spacesEm
                sub <- chompSubscription
                spacesEm
                word1 0x7D {-}-} SyntaxError.Effect
                spacesEm
                return (Src.Fx cmd sub)
            ],
        do
          sub <- chompSubscription
          spacesEm
          oneOf
            SyntaxError.Effect
            [ do
                word1 0x7D {-}-} SyntaxError.Effect
                spacesEm
                return (Src.Sub sub),
              do
                word1 0x2C {-,-} SyntaxError.Effect
                spacesEm
                cmd <- chompCommand
                spacesEm
                word1 0x7D {-}-} SyntaxError.Effect
                spacesEm
                return (Src.Fx cmd sub)
            ]
      ]

chompCommand :: Parser SyntaxError.Module (Ann.Located Name.Name)
chompCommand =
  do
    Keyword.command_ SyntaxError.Effect
    spacesEm
    word1 0x3D {-=-} SyntaxError.Effect
    spacesEm
    addLocation (Var.upper SyntaxError.Effect)

chompSubscription :: Parser SyntaxError.Module (Ann.Located Name.Name)
chompSubscription =
  do
    Keyword.subscription_ SyntaxError.Effect
    spacesEm
    word1 0x3D {-=-} SyntaxError.Effect
    spacesEm
    addLocation (Var.upper SyntaxError.Effect)

spacesEm :: Parser SyntaxError.Module ()
spacesEm =
  Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.Effect

-- IMPORTS

chompAllImports :: [Src.Import] -> [Src.ForeignImport] -> Parser SyntaxError.Module ([Src.Import], [Src.ForeignImport])
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

chompImports :: [Src.Import] -> Parser SyntaxError.Module [Src.Import]
chompImports is =
  oneOfWithFallback
    [ do
        i <- chompImport
        chompImports (i : is)
    ]
    (reverse is)

chompImport :: Parser SyntaxError.Module Src.Import
chompImport =
  do
    isLazy <- chompLazyKeyword
    Keyword.import_ SyntaxError.ImportStart
    Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ImportIndentName
    name@(Ann.At (Ann.Region _ end) _) <- addLocation (Var.moduleName SyntaxError.ImportName)
    Space.chomp SyntaxError.ModuleSpace
    oneOf
      SyntaxError.ImportEnd
      [ do
          Space.checkFreshLine SyntaxError.ImportEnd
          return $ Src.Import name Nothing (Src.Explicit []) isLazy,
        do
          Space.checkIndent end SyntaxError.ImportEnd
          oneOf
            SyntaxError.ImportAs
            [ chompAs name isLazy,
              chompExposing name Nothing isLazy
            ]
      ]

chompLazyKeyword :: Parser SyntaxError.Module Bool
chompLazyKeyword =
  oneOfWithFallback
    [ do
        Keyword.lazy_ SyntaxError.ImportStart
        Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ImportIndentName
        return True
    ]
    False

chompAs :: Ann.Located Name.Name -> Bool -> Parser SyntaxError.Module Src.Import
chompAs name isLazy =
  do
    Keyword.as_ SyntaxError.ImportAs
    Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ImportIndentAlias
    alias <- Var.upper SyntaxError.ImportAlias
    end <- getPosition
    Space.chomp SyntaxError.ModuleSpace
    oneOf
      SyntaxError.ImportEnd
      [ do
          Space.checkFreshLine SyntaxError.ImportEnd
          return $ Src.Import name (Just alias) (Src.Explicit []) isLazy,
        do
          Space.checkIndent end SyntaxError.ImportEnd
          chompExposing name (Just alias) isLazy
      ]

chompExposing :: Ann.Located Name.Name -> Maybe Name.Name -> Bool -> Parser SyntaxError.Module Src.Import
chompExposing name maybeAlias isLazy =
  do
    Keyword.exposing_ SyntaxError.ImportExposing
    Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ImportIndentExposingList
    exposed <- specialize SyntaxError.ImportExposingList exposing
    freshLine SyntaxError.ImportEnd
    return $ Src.Import name maybeAlias exposed isLazy

-- FOREIGN IMPORTS

chompForeignImport :: Parser SyntaxError.Module Src.ForeignImport
chompForeignImport =
  do
    start <- getPosition
    Keyword.foreign_ SyntaxError.ImportStart
    Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ImportIndentName
    Keyword.import_ SyntaxError.ImportStart
    Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ImportIndentName
    target <- chompForeignTarget
    Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ImportIndentAlias
    Keyword.as_ SyntaxError.ImportAs
    Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ImportIndentAlias
    alias <- addLocation (Var.upper SyntaxError.ImportAlias)
    end <- getPosition
    freshLine SyntaxError.ImportEnd
    let region = Ann.Region start end
    return $ Src.ForeignImport target alias region

chompForeignTarget :: Parser SyntaxError.Module FFI.FFITarget
chompForeignTarget =
  oneOf
    SyntaxError.ImportName
    [ do
        Keyword.javascript_ SyntaxError.ImportName
        Space.chompAndCheckIndent SyntaxError.ModuleSpace SyntaxError.ImportIndentName
        path <- parseStringLiteral SyntaxError.ImportName
        return (FFI.JavaScriptFFI path)
    ]

parseStringLiteral :: (Row -> Col -> SyntaxError.Module) -> Parser SyntaxError.Module String
parseStringLiteral toError =
  do
    esString <- String.string toError (\_ _ _ -> toError 0 0)
    return (ES.toChars esString)

-- LISTING

exposing :: Parser SyntaxError.Exposing Src.Exposing
exposing =
  do
    word1 0x28 {-(-} SyntaxError.ExposingStart
    Space.chompAndCheckIndent SyntaxError.ExposingSpace SyntaxError.ExposingIndentValue
    oneOf
      SyntaxError.ExposingValue
      [ do
          word2 0x2E 0x2E {-..-} SyntaxError.ExposingValue
          Space.chompAndCheckIndent SyntaxError.ExposingSpace SyntaxError.ExposingIndentEnd
          word1 0x29 {-)-} SyntaxError.ExposingEnd
          return Src.Open,
        do
          exposed <- chompExposed
          Space.chompAndCheckIndent SyntaxError.ExposingSpace SyntaxError.ExposingIndentEnd
          exposingHelp [exposed]
      ]

exposingHelp :: [Src.Exposed] -> Parser SyntaxError.Exposing Src.Exposing
exposingHelp revExposed =
  oneOf
    SyntaxError.ExposingEnd
    [ do
        word1 0x2C {-,-} SyntaxError.ExposingEnd
        Space.chompAndCheckIndent SyntaxError.ExposingSpace SyntaxError.ExposingIndentValue
        exposed <- chompExposed
        Space.chompAndCheckIndent SyntaxError.ExposingSpace SyntaxError.ExposingIndentEnd
        exposingHelp (exposed : revExposed),
      do
        word1 0x29 {-)-} SyntaxError.ExposingEnd
        return (Src.Explicit (reverse revExposed))
    ]

chompExposed :: Parser SyntaxError.Exposing Src.Exposed
chompExposed =
  do
    start <- getPosition
    oneOf
      SyntaxError.ExposingValue
      [ do
          name <- Var.lower SyntaxError.ExposingValue
          end <- getPosition
          return . Src.Lower $ Ann.at start end name,
        do
          word1 0x28 {-(-} SyntaxError.ExposingValue
          op <- Symbol.operator SyntaxError.ExposingOperator SyntaxError.ExposingOperatorReserved
          word1 0x29 {-)-} SyntaxError.ExposingOperatorRightParen
          end <- getPosition
          return $ Src.Operator (Ann.Region start end) op,
        do
          name <- Var.upper SyntaxError.ExposingValue
          end <- getPosition
          Space.chompAndCheckIndent SyntaxError.ExposingSpace SyntaxError.ExposingIndentEnd
          Src.Upper (Ann.at start end name) <$> privacy
      ]

privacy :: Parser SyntaxError.Exposing Src.Privacy
privacy =
  oneOfWithFallback
    [ do
        word1 0x28 {-(-} SyntaxError.ExposingTypePrivacy
        Space.chompAndCheckIndent SyntaxError.ExposingSpace SyntaxError.ExposingTypePrivacy
        start <- getPosition
        word2 0x2E 0x2E {-..-} SyntaxError.ExposingTypePrivacy
        end <- getPosition
        Space.chompAndCheckIndent SyntaxError.ExposingSpace SyntaxError.ExposingTypePrivacy
        word1 0x29 {-)-} SyntaxError.ExposingTypePrivacy
        return $ Src.Public (Ann.Region start end)
    ]
    Src.Private

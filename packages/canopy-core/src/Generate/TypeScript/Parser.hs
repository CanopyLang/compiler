{-# LANGUAGE OverloadedStrings #-}

-- | Minimal TypeScript @.d.ts@ declaration parser.
--
-- Parses a subset of TypeScript declaration files sufficient to validate
-- FFI bindings. Supports:
--
--   * @export function name(params): ReturnType@
--   * @export interface Name { fields }@
--   * @export type Name\<A, B\> = Type@
--   * @export const name: Type@
--   * Basic generics, unions, @ReadonlyArray\<T\>@, @Promise\<T\>@
--
-- The parser produces 'TsType' values from "Generate.TypeScript.Types",
-- reusing the existing IR for validation against FFI types.
--
-- @since 0.20.0
module Generate.TypeScript.Parser
  ( -- * Parsing
    parseDtsFile,
    parseDtsDeclarations,

    -- * Types
    DtsExport (..),
  )
where

import qualified Canopy.Data.Name as Name
import qualified Data.Char as Char
import Generate.TypeScript.Types (TsType (..))
import Text.Parsec ((<|>))
import qualified Text.Parsec as Parsec
import Text.Parsec.String (Parser)

-- | A parsed export from a @.d.ts@ file.
--
-- @since 0.20.0
data DtsExport
  = -- | @export function name(params): ReturnType@
    DtsExportFunction !Name.Name ![TsType] !TsType
  | -- | @export interface Name { fields }@
    DtsExportInterface !Name.Name ![(Name.Name, TsType)]
  | -- | @export type Name = Type@
    DtsExportType !Name.Name ![Name.Name] !TsType
  | -- | @export const name: Type@
    DtsExportConst !Name.Name !TsType
  deriving (Eq, Show)

-- | Parse a @.d.ts@ file into a list of exports.
--
-- @since 0.20.0
parseDtsFile :: FilePath -> String -> Either String [DtsExport]
parseDtsFile path content =
  case Parsec.parse dtsFileParser path content of
    Left err -> Left (show err)
    Right exports -> Right exports

-- | Parse declarations from a string (for testing).
--
-- @since 0.20.0
parseDtsDeclarations :: String -> Either String [DtsExport]
parseDtsDeclarations = parseDtsFile "<input>"

-- | Top-level file parser.
dtsFileParser :: Parser [DtsExport]
dtsFileParser = do
  exports <- Parsec.many (skipNonExport >> exportParser)
  Parsec.eof
  return exports

-- | Skip non-export content (comments, blank lines, import statements).
skipNonExport :: Parser ()
skipNonExport = Parsec.skipMany (Parsec.try nonExportLine)
  where
    nonExportLine = do
      Parsec.notFollowedBy (Parsec.try (ws >> Parsec.string "export"))
      Parsec.manyTill Parsec.anyChar (Parsec.try (Parsec.char '\n' >> return ()) <|> Parsec.eof)

-- | Parse a single export declaration.
exportParser :: Parser DtsExport
exportParser = do
  ws
  _ <- Parsec.string "export"
  ws1
  Parsec.try exportFunction
    <|> Parsec.try exportInterface
    <|> Parsec.try exportType
    <|> exportConst

-- | @export function name(params): ReturnType;@
exportFunction :: Parser DtsExport
exportFunction = do
  _ <- Parsec.string "function"
  ws1
  name <- identifier
  typeParams <- Parsec.option [] typeParamList
  _ <- Parsec.char '('
  params <- paramList
  _ <- Parsec.char ')'
  _ <- ws >> Parsec.char ':'
  ws
  retType <- tsType
  _ <- Parsec.optional (Parsec.char ';')
  let paramTypes = map snd params
      funcType = applyTypeParams typeParams paramTypes retType
  return (DtsExportFunction (Name.fromChars name) paramTypes funcType)
  where
    applyTypeParams _ pts rt = rt `seq` pts `seq` rt

-- | @export interface Name { fields }@
exportInterface :: Parser DtsExport
exportInterface = do
  _ <- Parsec.string "interface"
  ws1
  name <- identifier
  _ <- Parsec.optional typeParamList
  ws
  fields <- braces fieldList
  return (DtsExportInterface (Name.fromChars name) fields)

-- | @export type Name\<A, B\> = Type;@
exportType :: Parser DtsExport
exportType = do
  _ <- Parsec.string "type"
  ws1
  name <- identifier
  typeParams <- Parsec.option [] typeParamList
  ws
  _ <- Parsec.char '='
  ws
  body <- tsType
  _ <- Parsec.optional (Parsec.char ';')
  return (DtsExportType (Name.fromChars name) (map (Name.fromChars) typeParams) body)

-- | @export const name: Type;@
exportConst :: Parser DtsExport
exportConst = do
  _ <- Parsec.string "const"
  ws1
  name <- identifier
  _ <- ws >> Parsec.char ':'
  ws
  t <- tsType
  _ <- Parsec.optional (Parsec.char ';')
  return (DtsExportConst (Name.fromChars name) t)

-- | Parse a TypeScript type expression.
tsType :: Parser TsType
tsType = do
  t <- tsTypeAtom
  ws
  Parsec.option t (Parsec.try (unionContinuation t))

-- | Parse a union continuation: @| B | C@
unionContinuation :: TsType -> Parser TsType
unionContinuation first = do
  rest <- Parsec.many1 (Parsec.try (ws >> Parsec.char '|' >> ws >> tsTypeAtom))
  return (TsUnion (first : rest))

-- | Parse a single type atom (without union).
tsTypeAtom :: Parser TsType
tsTypeAtom =
  Parsec.try tsFunction
    <|> Parsec.try tsParenType
    <|> Parsec.try tsObjectType
    <|> tsNamedOrPrimitive

-- | Parse parenthesized type or arrow function: @(p: A) => B@
tsParenType :: Parser TsType
tsParenType = do
  _ <- Parsec.char '('
  ws
  Parsec.try arrowFunction <|> parenGroup
  where
    arrowFunction = do
      params <- paramList
      _ <- Parsec.char ')'
      ws
      _ <- Parsec.string "=>"
      ws
      retType <- tsType
      return (TsFunction (map snd params) retType)
    parenGroup = do
      t <- tsType
      ws
      _ <- Parsec.char ')'
      return t

-- | Parse arrow function type: @(p0: A, p1: B) => C@
tsFunction :: Parser TsType
tsFunction = do
  _ <- Parsec.char '('
  ws
  params <- paramList
  _ <- Parsec.char ')'
  ws
  _ <- Parsec.string "=>"
  ws
  retType <- tsType
  return (TsFunction (map snd params) retType)

-- | Parse object type: @{ readonly field: Type; ... }@
tsObjectType :: Parser TsType
tsObjectType = do
  fields <- braces fieldList
  return (TsObject fields)

-- | Parse a named type, generic, or primitive.
tsNamedOrPrimitive :: Parser TsType
tsNamedOrPrimitive = do
  name <- identifier
  ws
  case name of
    "string" -> return TsString
    "number" -> return TsNumber
    "boolean" -> return TsBoolean
    "void" -> return TsVoid
    "undefined" -> return TsVoid
    "unknown" -> return TsUnknown
    "null" -> return TsVoid
    "ReadonlyArray" -> TsReadonlyArray <$> typeArg
    "Array" -> TsReadonlyArray <$> typeArg
    "Promise" -> do
      inner <- typeArg
      return (TsNamed (Name.fromChars "Promise") [inner])
    _ -> do
      args <- Parsec.option [] (Parsec.try typeArgList)
      return (TsNamed (Name.fromChars name) args)

-- | Parse a single type argument: @\<T\>@
typeArg :: Parser TsType
typeArg = do
  _ <- Parsec.char '<'
  ws
  t <- tsType
  ws
  _ <- Parsec.char '>'
  return t

-- | Parse type argument list: @\<A, B, C\>@
typeArgList :: Parser [TsType]
typeArgList = do
  _ <- Parsec.char '<'
  ws
  types <- Parsec.sepBy1 (ws >> tsType) (ws >> Parsec.char ',')
  ws
  _ <- Parsec.char '>'
  return types

-- | Parse type parameter list: @\<A, B\>@
typeParamList :: Parser [String]
typeParamList = do
  _ <- Parsec.char '<'
  ws
  names <- Parsec.sepBy1 (ws >> identifier) (ws >> Parsec.char ',')
  ws
  _ <- Parsec.char '>'
  return names

-- | Parse function parameter list.
paramList :: Parser [(String, TsType)]
paramList =
  Parsec.sepBy param (ws >> Parsec.char ',' >> ws)

-- | Parse a single parameter: @name: Type@
param :: Parser (String, TsType)
param = do
  ws
  name <- identifier
  ws
  _ <- Parsec.char ':'
  ws
  t <- tsType
  return (name, t)

-- | Parse object fields: @readonly field: Type;@
fieldList :: Parser [(Name.Name, TsType)]
fieldList =
  Parsec.many (Parsec.try field)

-- | Parse a single field.
field :: Parser (Name.Name, TsType)
field = do
  ws
  _ <- Parsec.optional (Parsec.try (Parsec.string "readonly" >> ws1))
  name <- identifier
  ws
  _ <- Parsec.optional (Parsec.char '?')
  _ <- Parsec.char ':'
  ws
  t <- tsType
  ws
  _ <- Parsec.optional (Parsec.char ';')
  ws
  return (Name.fromChars name, t)

-- | Parse braces: @{ content }@
braces :: Parser a -> Parser a
braces p = do
  _ <- Parsec.char '{'
  ws
  result <- p
  ws
  _ <- Parsec.char '}'
  return result

-- | Parse an identifier.
identifier :: Parser String
identifier = do
  first <- Parsec.satisfy (\c -> Char.isAlpha c || c == '_' || c == '$')
  rest <- Parsec.many (Parsec.satisfy (\c -> Char.isAlphaNum c || c == '_' || c == '$'))
  return (first : rest)

-- | Skip whitespace (including newlines).
ws :: Parser ()
ws = Parsec.skipMany (Parsec.satisfy (\c -> c == ' ' || c == '\t' || c == '\n' || c == '\r'))

-- | Skip at least one whitespace character.
ws1 :: Parser ()
ws1 = Parsec.skipMany1 (Parsec.satisfy (\c -> c == ' ' || c == '\t' || c == '\n' || c == '\r'))

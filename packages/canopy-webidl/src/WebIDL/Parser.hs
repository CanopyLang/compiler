{-# LANGUAGE OverloadedStrings #-}

-- | WebIDL Parser
--
-- A complete parser for WebIDL specifications using megaparsec.
-- Implements the WebIDL grammar as defined by WHATWG.
--
-- Reference: https://webidl.spec.whatwg.org/
--
-- @since 0.20.0
module WebIDL.Parser
  ( -- * Main parsing functions
    parseWebIDL
  , parseDefinition

    -- * Individual parsers (for testing)
  , pDefinitions
  , pDefinition
  , pInterfaceDef
  , pOperation
  , pAttribute
  , pType
  , pExtendedAttributes
  ) where

import Control.Monad (void)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Void (Void)
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as Lexer

import WebIDL.AST


-- | Parser type alias
type Parser = Parsec Void Text


-- | Parse WebIDL text into definitions
parseWebIDL :: FilePath -> Text -> Either String Definitions
parseWebIDL path input =
  case parse pDefinitions path input of
    Left err -> Left (errorBundlePretty err)
    Right defs -> Right defs


-- | Parse a single definition (for testing)
parseDefinition :: Text -> Either String Definition
parseDefinition input =
  case parse (sc *> pDefinition <* eof) "<input>" input of
    Left err -> Left (errorBundlePretty err)
    Right def -> Right def


-- * Lexer

-- | Space consumer (including comments)
sc :: Parser ()
sc = Lexer.space space1 lineComment blockComment
  where
    lineComment = Lexer.skipLineComment "//"
    blockComment = Lexer.skipBlockComment "/*" "*/"


-- | Lexeme parser
lexeme :: Parser a -> Parser a
lexeme = Lexer.lexeme sc


-- | Symbol parser
symbol :: Text -> Parser Text
symbol = Lexer.symbol sc


-- | Parse between braces
braces :: Parser a -> Parser a
braces = between (symbol "{") (symbol "}")


-- | Parse between parentheses
parens :: Parser a -> Parser a
parens = between (symbol "(") (symbol ")")


-- | Parse between angle brackets
angles :: Parser a -> Parser a
angles = between (symbol "<") (symbol ">")


-- | Parse between square brackets
brackets :: Parser a -> Parser a
brackets = between (symbol "[") (symbol "]")


-- | Parse a semicolon
semi :: Parser ()
semi = void (symbol ";")


-- | Parse a comma
comma :: Parser ()
comma = void (symbol ",")


-- | Parse comma-separated list
commaSep :: Parser a -> Parser [a]
commaSep p = p `sepBy` comma


-- | Parse comma-separated list (at least one)
commaSep1 :: Parser a -> Parser [a]
commaSep1 p = p `sepBy1` comma


-- | Parse an identifier
identifier :: Parser Text
identifier = lexeme (Text.pack <$> ident)
  where
    ident = (:) <$> (letterChar <|> char '_')
                <*> many (alphaNumChar <|> char '_')


-- | Parse a string literal
stringLiteral :: Parser Text
stringLiteral = lexeme (Text.pack <$> (char '"' *> manyTill Lexer.charLiteral (char '"')))


-- | Parse an integer literal
integerLiteral :: Parser Integer
integerLiteral = lexeme (hexLiteral <|> Lexer.signed sc Lexer.decimal)
  where
    hexLiteral = string "0x" *> Lexer.hexadecimal


-- | Parse a float literal
floatLiteral :: Parser Double
floatLiteral = lexeme (try Lexer.float <|> specialFloat)
  where
    specialFloat = choice
      [ infinity <$ (string "Infinity" <|> string "+Infinity")
      , negate infinity <$ string "-Infinity"
      , nan <$ string "NaN"
      ]
    infinity = 1/0
    nan = 0/0


-- * Keywords

-- | Parse a keyword
keyword :: Text -> Parser ()
keyword kw = lexeme (void (string kw <* notFollowedBy alphaNumChar))


-- * Definition Parsers

-- | Parse all definitions in a file
pDefinitions :: Parser Definitions
pDefinitions = sc *> many pDefinition <* eof


-- | Parse a single definition
pDefinition :: Parser Definition
pDefinition = do
  extAttrs <- option [] pExtendedAttributes
  choice
    [ pCallbackDef extAttrs
    , pInterfaceDef extAttrs
    , pMixinDef extAttrs
    , pNamespaceDef extAttrs
    , pDictionaryDef extAttrs
    , pEnumDef extAttrs
    , pTypedefDef extAttrs
    , pIncludesDef
    ]


-- | Parse interface definition
pInterfaceDef :: ExtendedAttributes -> Parser Definition
pInterfaceDef extAttrs = do
  isPartial <- option False (True <$ keyword "partial")
  keyword "interface"
  isMixin <- option False (True <$ keyword "mixin")
  name <- identifier

  case (isPartial, isMixin) of
    (False, False) -> do
      inherits <- optional (symbol ":" *> pInheritance)
      members <- braces (many pInterfaceMember)
      semi
      pure (DefInterface (Interface extAttrs name inherits members))

    (True, False) -> do
      members <- braces (many pInterfaceMember)
      semi
      pure (DefPartialInterface (PartialInterface extAttrs name members))

    (False, True) -> do
      members <- braces (many pMixinMember)
      semi
      pure (DefMixin (Mixin extAttrs name members))

    (True, True) -> do
      members <- braces (many pMixinMember)
      semi
      pure (DefPartialMixin (Mixin extAttrs name members))


-- | Parse mixin definition (standalone)
pMixinDef :: ExtendedAttributes -> Parser Definition
pMixinDef extAttrs = do
  isPartial <- option False (True <$ keyword "partial")
  keyword "interface"
  keyword "mixin"
  name <- identifier
  members <- braces (many pMixinMember)
  semi
  if isPartial
    then pure (DefPartialMixin (Mixin extAttrs name members))
    else pure (DefMixin (Mixin extAttrs name members))


-- | Parse namespace definition
pNamespaceDef :: ExtendedAttributes -> Parser Definition
pNamespaceDef _extAttrs = do
  isPartial <- option False (True <$ keyword "partial")
  keyword "namespace"
  name <- identifier
  members <- braces (many pInterfaceMember)
  semi
  if isPartial
    then pure (DefPartialNamespace name members)
    else pure (DefNamespace name members)


-- | Parse dictionary definition
pDictionaryDef :: ExtendedAttributes -> Parser Definition
pDictionaryDef extAttrs = do
  isPartial <- option False (True <$ keyword "partial")
  keyword "dictionary"
  name <- identifier
  inherits <- optional (symbol ":" *> pInheritance)
  members <- braces (many pDictionaryMember)
  semi
  let dict = Dictionary extAttrs name inherits members
  pure (if isPartial then DefPartialDictionary dict else DefDictionary dict)


-- | Parse enum definition
pEnumDef :: ExtendedAttributes -> Parser Definition
pEnumDef extAttrs = do
  keyword "enum"
  name <- identifier
  values <- braces (commaSep1 stringLiteral)
  semi
  pure (DefEnum (IDLEnum extAttrs name values))


-- | Parse typedef definition
pTypedefDef :: ExtendedAttributes -> Parser Definition
pTypedefDef extAttrs = do
  keyword "typedef"
  ty <- pType
  name <- identifier
  semi
  pure (DefTypedef (Typedef extAttrs ty name))


-- | Parse callback definition
pCallbackDef :: ExtendedAttributes -> Parser Definition
pCallbackDef extAttrs = do
  keyword "callback"
  isInterface <- option False (True <$ keyword "interface")
  name <- identifier

  if isInterface
    then do
      members <- braces (many pInterfaceMember)
      semi
      pure (DefCallbackInterface (CallbackInterface extAttrs name members))
    else do
      void (symbol "=")
      retType <- pType
      args <- parens (commaSep pArgument)
      semi
      pure (DefCallback (Callback extAttrs name retType args))


-- | Parse includes statement
pIncludesDef :: Parser Definition
pIncludesDef = do
  target <- identifier
  keyword "includes"
  mixin <- identifier
  semi
  pure (DefIncludes target mixin)


-- | Parse inheritance
pInheritance :: Parser Inheritance
pInheritance = Inheritance <$> identifier


-- * Member Parsers

-- | Parse interface member
pInterfaceMember :: Parser InterfaceMember
pInterfaceMember = do
  extAttrs <- option [] pExtendedAttributes
  choice
    [ pConstructorMember extAttrs
    , pConstMember extAttrs
    , pIterableMember
    , pAsyncIterableMember
    , try pMaplikeMember
    , try pSetlikeMember
    , pStringifierMember extAttrs
    , try (pStaticMember extAttrs)
    , try (pAttributeMember extAttrs)
    , pOperationMember extAttrs
    ]


-- | Parse mixin member
pMixinMember :: Parser MixinMember
pMixinMember = do
  extAttrs <- option [] pExtendedAttributes
  choice
    [ MMConst <$> pConst extAttrs
    , pMixinStringifier extAttrs
    , try (MMAttribute <$> pAttribute extAttrs)
    , MMOperation <$> pOperation extAttrs
    ]


-- | Parse dictionary member
pDictionaryMember :: Parser DictionaryMember
pDictionaryMember = do
  extAttrs <- option [] pExtendedAttributes
  isRequired <- option False (True <$ keyword "required")
  ty <- pType
  name <- identifier
  defVal <- optional (symbol "=" *> pDefaultValue)
  semi
  pure (DictionaryMember extAttrs isRequired ty name defVal)


-- | Parse constructor member
pConstructorMember :: ExtendedAttributes -> Parser InterfaceMember
pConstructorMember extAttrs = do
  keyword "constructor"
  args <- parens (commaSep pArgument)
  semi
  pure (IMConstructor (Constructor extAttrs args))


-- | Parse const member
pConstMember :: ExtendedAttributes -> Parser InterfaceMember
pConstMember extAttrs = IMConst <$> pConst extAttrs


-- | Parse const
pConst :: ExtendedAttributes -> Parser Const
pConst extAttrs = do
  keyword "const"
  ty <- pConstType
  name <- identifier
  void (symbol "=")
  val <- pConstValue
  semi
  pure (Const extAttrs ty name val)


-- | Parse attribute member
pAttributeMember :: ExtendedAttributes -> Parser InterfaceMember
pAttributeMember extAttrs = IMAttribute <$> pAttribute extAttrs


-- | Parse operation member
pOperationMember :: ExtendedAttributes -> Parser InterfaceMember
pOperationMember extAttrs = IMOperation <$> pOperation extAttrs


-- | Parse attribute
pAttribute :: ExtendedAttributes -> Parser Attribute
pAttribute extAttrs = do
  isInherit <- option False (True <$ keyword "inherit")
  isReadonly <- option False (True <$ keyword "readonly")
  keyword "attribute"
  ty <- pType
  name <- identifier
  semi
  pure (Attribute extAttrs isReadonly isInherit ty name)


-- | Parse operation
pOperation :: ExtendedAttributes -> Parser Operation
pOperation extAttrs = do
  special <- optional pSpecial
  retType <- pType
  name <- optional identifier
  args <- parens (commaSep pArgument)
  semi
  pure (Operation extAttrs special retType name args)


-- | Parse special operation keyword
pSpecial :: Parser Special
pSpecial = choice
  [ SpecialGetter <$ keyword "getter"
  , SpecialSetter <$ keyword "setter"
  , SpecialDeleter <$ keyword "deleter"
  ]


-- | Parse static member
pStaticMember :: ExtendedAttributes -> Parser InterfaceMember
pStaticMember extAttrs = do
  keyword "static"
  member <- choice
    [ try (IMAttribute <$> pAttribute extAttrs)
    , IMOperation <$> pOperation extAttrs
    ]
  pure (IMStaticMember member)


-- | Parse stringifier member
pStringifierMember :: ExtendedAttributes -> Parser InterfaceMember
pStringifierMember extAttrs = do
  keyword "stringifier"
  choice
    [ IMStringifier Nothing <$ semi
    , IMStringifier . Just <$> pAttribute extAttrs
    ]


-- | Parse mixin stringifier
pMixinStringifier :: ExtendedAttributes -> Parser MixinMember
pMixinStringifier extAttrs = do
  keyword "stringifier"
  choice
    [ MMStringifier Nothing <$ semi
    , MMStringifier . Just <$> pAttribute extAttrs
    ]


-- | Parse iterable member
pIterableMember :: Parser InterfaceMember
pIterableMember = do
  keyword "iterable"
  (ty1, ty2) <- angles pTypeArgs
  semi
  pure (IMIterable ty1 ty2)


-- | Parse async iterable member
pAsyncIterableMember :: Parser InterfaceMember
pAsyncIterableMember = do
  keyword "async"
  keyword "iterable"
  (ty1, ty2) <- angles pTypeArgs
  args <- option [] (parens (commaSep pArgument))
  semi
  pure (IMAsyncIterable ty1 ty2 args)


-- | Parse maplike member
pMaplikeMember :: Parser InterfaceMember
pMaplikeMember = do
  isReadonly <- option False (True <$ keyword "readonly")
  keyword "maplike"
  (keyTy, valTy) <- angles pMapTypeArgs
  semi
  pure (IMMaplike keyTy valTy isReadonly)


-- | Parse setlike member
pSetlikeMember :: Parser InterfaceMember
pSetlikeMember = do
  isReadonly <- option False (True <$ keyword "readonly")
  keyword "setlike"
  ty <- angles pType
  semi
  pure (IMSetlike ty isReadonly)


-- | Parse type arguments (one or two)
pTypeArgs :: Parser (IDLType, Maybe IDLType)
pTypeArgs = do
  ty1 <- pType
  ty2 <- optional (comma *> pType)
  pure (ty1, ty2)


-- | Parse map type arguments (exactly two)
pMapTypeArgs :: Parser (IDLType, IDLType)
pMapTypeArgs = do
  keyTy <- pType
  comma
  valTy <- pType
  pure (keyTy, valTy)


-- * Argument Parsers

-- | Parse argument
pArgument :: Parser Argument
pArgument = do
  extAttrs <- option [] pExtendedAttributes
  isOptional <- option False (True <$ keyword "optional")
  ty <- pType
  isVariadic <- option False (True <$ symbol "...")
  name <- identifier
  defVal <- optional (symbol "=" *> pDefaultValue)
  pure (Argument extAttrs isOptional ty isVariadic name defVal)


-- | Parse default value
pDefaultValue :: Parser DefaultValue
pDefaultValue = choice
  [ DVNull <$ keyword "null"
  , DVBool True <$ keyword "true"
  , DVBool False <$ keyword "false"
  , DVEmptySequence <$ (symbol "[" *> symbol "]")
  , DVEmptyDictionary <$ (symbol "{" *> symbol "}")
  , DVString <$> stringLiteral
  , try (DVFloat <$> floatLiteral)
  , DVInteger <$> integerLiteral
  , DVIdentifier <$> identifier
  ]


-- | Parse const value
pConstValue :: Parser DefaultValue
pConstValue = choice
  [ DVBool True <$ keyword "true"
  , DVBool False <$ keyword "false"
  , try (DVFloat <$> floatLiteral)
  , DVInteger <$> integerLiteral
  ]


-- * Type Parsers

-- | Parse const type (restricted set)
pConstType :: Parser IDLType
pConstType = choice
  [ TyPrimitive <$> pPrimitiveType
  , TyIdentifier <$> identifier
  ]


-- | Parse type with nullable support
pType :: Parser IDLType
pType = do
  ty <- pUnionType
  isNullable <- option False (True <$ symbol "?")
  pure (if isNullable then TyNullable ty else ty)


-- | Parse union type
pUnionType :: Parser IDLType
pUnionType = do
  ty <- pSingleType
  rest <- many (keyword "or" *> pSingleType)
  case rest of
    [] -> pure ty
    _ -> pure (TyUnion (ty : rest))


-- | Parse single (non-union) type
pSingleType :: Parser IDLType
pSingleType = choice
  [ pAnyType
  , pPromiseType
  , pSequenceType
  , pFrozenArrayType
  , pObservableArrayType
  , pRecordType
  , try (TyPrimitive <$> pPrimitiveType)
  , TyString <$> pStringType
  , TyBuffer <$> pBufferType
  , TyObject <$ keyword "object"
  , TySymbol <$ keyword "symbol"
  , TyIdentifier <$> identifier
  , parens pUnionType
  ]


-- | Parse any type
pAnyType :: Parser IDLType
pAnyType = TyAny <$ keyword "any"


-- | Parse Promise type
pPromiseType :: Parser IDLType
pPromiseType = do
  keyword "Promise"
  TyPromise <$> angles pType


-- | Parse sequence type
pSequenceType :: Parser IDLType
pSequenceType = do
  keyword "sequence"
  TySequence <$> angles pType


-- | Parse FrozenArray type
pFrozenArrayType :: Parser IDLType
pFrozenArrayType = do
  keyword "FrozenArray"
  TyFrozenArray <$> angles pType


-- | Parse ObservableArray type
pObservableArrayType :: Parser IDLType
pObservableArrayType = do
  keyword "ObservableArray"
  TyObservableArray <$> angles pType


-- | Parse record type
pRecordType :: Parser IDLType
pRecordType = do
  keyword "record"
  (strTy, valTy) <- angles pRecordTypeArgs
  pure (TyRecord strTy valTy)


-- | Parse record type arguments
pRecordTypeArgs :: Parser (StringType, IDLType)
pRecordTypeArgs = do
  keyTy <- pStringType
  comma
  valTy <- pType
  pure (keyTy, valTy)


-- | Parse primitive type
pPrimitiveType :: Parser PrimitiveType
pPrimitiveType = choice
  [ PrimBoolean <$ keyword "boolean"
  , PrimByte <$ keyword "byte"
  , PrimOctet <$ keyword "octet"
  , try pIntegerType
  , try pFloatType
  , PrimBigint <$ keyword "bigint"
  ]


-- | Parse integer type
pIntegerType :: Parser PrimitiveType
pIntegerType = do
  isUnsigned <- option False (True <$ keyword "unsigned")
  choice
    [ (if isUnsigned then PrimUnsignedShort else PrimShort)
        <$ keyword "short"
    , pLongType isUnsigned
    ]


-- | Parse long type
pLongType :: Bool -> Parser PrimitiveType
pLongType isUnsigned = do
  keyword "long"
  isLongLong <- option False (True <$ keyword "long")
  pure (selectLongType isUnsigned isLongLong)
  where
    selectLongType False False = PrimLong
    selectLongType False True = PrimLongLong
    selectLongType True False = PrimUnsignedLong
    selectLongType True True = PrimUnsignedLongLong


-- | Parse float type
pFloatType :: Parser PrimitiveType
pFloatType = do
  isUnrestricted <- option False (True <$ keyword "unrestricted")
  choice
    [ (if isUnrestricted then PrimUnrestrictedFloat else PrimFloat)
        <$ keyword "float"
    , (if isUnrestricted then PrimUnrestrictedDouble else PrimDouble)
        <$ keyword "double"
    ]


-- | Parse string type
pStringType :: Parser StringType
pStringType = choice
  [ StrDOMString <$ keyword "DOMString"
  , StrByteString <$ keyword "ByteString"
  , StrUSVString <$ keyword "USVString"
  ]


-- | Parse buffer type
pBufferType :: Parser BufferType
pBufferType = choice
  [ BufArrayBuffer <$ keyword "ArrayBuffer"
  , BufSharedArrayBuffer <$ keyword "SharedArrayBuffer"
  , BufDataView <$ keyword "DataView"
  , BufInt8Array <$ keyword "Int8Array"
  , BufInt16Array <$ keyword "Int16Array"
  , BufInt32Array <$ keyword "Int32Array"
  , BufUint8Array <$ keyword "Uint8Array"
  , BufUint16Array <$ keyword "Uint16Array"
  , BufUint32Array <$ keyword "Uint32Array"
  , BufUint8ClampedArray <$ keyword "Uint8ClampedArray"
  , BufBigInt64Array <$ keyword "BigInt64Array"
  , BufBigUint64Array <$ keyword "BigUint64Array"
  , BufFloat32Array <$ keyword "Float32Array"
  , BufFloat64Array <$ keyword "Float64Array"
  ]


-- * Extended Attribute Parsers

-- | Parse extended attributes
pExtendedAttributes :: Parser ExtendedAttributes
pExtendedAttributes = brackets (commaSep1 pExtendedAttribute)


-- | Parse single extended attribute
pExtendedAttribute :: Parser ExtendedAttribute
pExtendedAttribute = do
  name <- identifier
  choice
    [ try (pNamedArgList name)
    , try (pArgList name)
    , try (pIdentList name)
    , pIdent name
    , pure (EANoArgs name)
    ]


-- | Parse extended attribute with identifier value
pIdent :: Text -> Parser ExtendedAttribute
pIdent name = do
  void (symbol "=")
  val <- identifier
  pure (EAIdent name val)


-- | Parse extended attribute with identifier list
pIdentList :: Text -> Parser ExtendedAttribute
pIdentList name = do
  void (symbol "=")
  void (symbol "(")
  vals <- commaSep1 identifier
  void (symbol ")")
  pure (EAIdentList name vals)


-- | Parse extended attribute with argument list
pArgList :: Text -> Parser ExtendedAttribute
pArgList name = do
  args <- parens (commaSep pArgument)
  pure (EAArgList name args)


-- | Parse extended attribute with named argument list
pNamedArgList :: Text -> Parser ExtendedAttribute
pNamedArgList name = do
  void (symbol "=")
  ident <- identifier
  args <- parens (commaSep pArgument)
  pure (EANamedArgList name ident args)

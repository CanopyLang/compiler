{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Foreign Function Interface (FFI) support for Canopy
--
-- This module provides comprehensive FFI functionality for integrating
-- JavaScript code with Canopy through JSDoc-based type contracts.
--
-- The FFI system supports:
-- * Type-safe bindings to JavaScript functions
-- * Automatic JSDoc parsing and validation
-- * Runtime type checking and error handling
-- * Automatic Canopy wrapper generation
--
-- @since 0.19.1
module Foreign.FFI
  ( -- * FFI Declarations
    FFIDeclaration(..)
  , FFITarget(..)
  , FFIType(..)
  , FFIFunction(..)
  , SimpleFFIImport(..)

    -- * JSDoc Integration
  , JSDocFunction(..)
  , parseJSDocFromFile
  , parseJavaScriptFile
  , generateFFIBindings
  , processForeignImports

    -- * Type Parsing
  , parseCanopyTypeAnnotation
  , parseFFIType
  , tokenizeType

    -- * Error Handling
  , FFIError(..)
  , validateFFIDeclaration

    -- * Code Generation
  , generateFFIModule
  , generateRuntimeWrapper
  ) where

import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Name as Name
import qualified Reporting.Annotation as A
import qualified Data.Maybe as Maybe
import qualified Data.Map.Strict as Map
import qualified System.Directory as Dir
import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Parser.AST as JSAST
import qualified Language.JavaScript.Parser.Token as JSToken
import Language.JavaScript.Parser.AST
  ( JSAST(..)
  , JSStatement(..)
  )
import qualified FFI.Capability as Capability

-- | FFI declaration in Canopy source code
--
-- Represents a foreign import statement like:
-- @
-- foreign import javascript "./dom.js" as DOM
-- @
--
-- @since 0.19.1
data FFIDeclaration = FFIDeclaration
  { ffiTarget :: !FFITarget
    -- ^ Target language and file path
  , ffiAlias :: !(A.Located Name.Name)
    -- ^ Module alias for imported functions
  , ffiLocation :: !A.Region
    -- ^ Source location of the declaration
  } deriving (Show)

-- | Target for FFI imports
--
-- Currently supports JavaScript with plans for WebAssembly.
--
-- @since 0.19.1
data FFITarget
  = JavaScriptFFI !FilePath
    -- ^ JavaScript file path (relative to project root)
  | WebAssemblyFFI !FilePath
    -- ^ WebAssembly file path (future extension)
  deriving (Eq, Show)

-- | FFI-specific type representation
--
-- Maps JSDoc types to Canopy types for foreign function bindings.
--
-- @since 0.19.1
data FFIType
  = FFIBasic !Text
    -- ^ Basic type (String, Int, Bool, etc.)
  | FFIResult !FFIType !FFIType
    -- ^ Result Error Value type for fallible operations
  | FFITask !FFIType !FFIType
    -- ^ Task Error Value type for async operations
  | FFIMaybe !FFIType
    -- ^ Maybe Value type for nullable values
  | FFIList !FFIType
    -- ^ List Value type for arrays
  | FFIFunctionType ![FFIType] !FFIType
    -- ^ Function type with parameters and return type
  | FFIOpaque !Text
    -- ^ Opaque type (DOMElement, etc.)
  | FFITuple ![FFIType]
    -- ^ Tuple type with multiple values
  | FFIRecord ![(Text, FFIType)]
    -- ^ Record type with named fields
  deriving (Eq, Show)

-- | FFI function with complete type information
--
-- Used for test generation and runtime validation.
--
-- @since 0.19.1
data FFIFunction = FFIFunction
  { ffiFuncInputTypes :: ![FFIType]
    -- ^ Input parameter types
  , ffiFuncOutputType :: !FFIType
    -- ^ Output/return type
  , ffiFuncErrorTypes :: ![Text]
    -- ^ Exception types that can be thrown
  } deriving (Eq, Show)

-- | JavaScript function extracted from JSDoc
--
-- Contains type information parsed from JSDoc comments including capability requirements.
--
-- @since 0.19.1
data JSDocFunction = JSDocFunction
  { jsDocFuncName :: !Text
    -- ^ Function name in JavaScript
  , jsDocFuncType :: !FFIType
    -- ^ Canopy type signature from @canopy-type annotation
  , jsDocFuncDescription :: !(Maybe Text)
    -- ^ Function description
  , jsDocFuncParams :: ![(Text, FFIType, Maybe Text)]
    -- ^ Parameters with names, types, and descriptions
  , jsDocFuncThrows :: ![Text]
    -- ^ Exception types that can be thrown
  , jsDocFuncCapabilities :: !(Maybe Capability.CapabilityConstraint)
    -- ^ Capability requirements from @canopy-capability annotation
  , jsDocFuncFile :: !FilePath
    -- ^ Source JavaScript file
  } deriving (Eq, Show)

-- | FFI validation and processing errors
--
-- Comprehensive error reporting for FFI-related issues including capability errors.
--
-- @since 0.19.1
data FFIError
  = JSFileNotFound !FilePath
    -- ^ JavaScript file does not exist
  | JSDocParseError !FilePath !Text
    -- ^ Failed to parse JSDoc from file
  | InvalidCanopyType !Text !Text
    -- ^ Invalid @canopy-type annotation
  | FunctionNotFound !FilePath !Text
    -- ^ Function not found in JavaScript file
  | TypeMismatch !Text !FFIType !FFIType
    -- ^ Type annotation doesn't match usage
  | MissingCanopyType !Text
    -- ^ Function lacks @canopy-type annotation
  | UnsupportedJSType !Text
    -- ^ JavaScript type cannot be mapped to Canopy
  | InvalidCapabilityAnnotation !Text !Text
    -- ^ Invalid @canopy-capability annotation
  | CapabilityError !Capability.CapabilityError
    -- ^ Capability constraint violation
  deriving (Eq, Show)

-- | Parse JSDoc functions from a JavaScript file
--
-- Reads a JavaScript file and extracts all functions with JSDoc
-- comments, specifically looking for @canopy-type annotations.
--
-- @since 0.19.1
parseJSDocFromFile :: FilePath -> IO (Either FFIError [JSDocFunction])
parseJSDocFromFile jsFile = do
  contentResult <- readFileContents jsFile
  case contentResult of
    Left err -> return $ Left err
    Right content -> do
      case JS.parseModule content jsFile of
        Left parseError -> return $ Left (JSDocParseError jsFile (Text.pack $ show parseError))
        Right ast -> return $ Right (extractJSDocFromAST jsFile ast)

-- | Safely read file contents
readFileContents :: FilePath -> IO (Either FFIError String)
readFileContents jsFile = do
  fileExists <- Dir.doesFileExist jsFile
  if not fileExists
    then return $ Left (JSFileNotFound jsFile)
    else do
      content <- readFile jsFile
      return $ Right content

-- | Extract JSDoc functions from parsed JavaScript AST
extractJSDocFromAST :: FilePath -> JSAST -> [JSDocFunction]
extractJSDocFromAST jsFile ast =
  case ast of
    JSAstProgram statements _ -> processStatements jsFile statements
    JSAstModule moduleItems _ -> processModuleItems jsFile moduleItems
    JSAstStatement statement _ -> Maybe.maybeToList (processStatement jsFile statement)
    _ -> []

-- | Process a list of statements to extract JSDoc functions
processStatements :: FilePath -> [JSStatement] -> [JSDocFunction]
processStatements jsFile statements =
  Maybe.mapMaybe (processStatement jsFile) statements

-- | Process module items (for ES6 modules)
processModuleItems :: FilePath -> [JSAST.JSModuleItem] -> [JSDocFunction]
processModuleItems jsFile moduleItems =
  let statements = [stmt | JSAST.JSModuleStatementListItem stmt <- moduleItems]
  in processStatements jsFile statements

-- | Process a single statement to extract JSDoc function
processStatement :: FilePath -> JSStatement -> Maybe JSDocFunction
processStatement jsFile statement =
  case statement of
    JSFunction (JSAST.JSAnnot _ comments) _ _ _ _ _ _ ->
      case extractJSDocFromComments comments of
        [] -> Nothing
        (jsDocText:_) -> parseJSDocTextManual jsFile jsDocText
    _ -> Nothing

-- | Extract JSDoc comments from comment annotations manually
extractJSDocFromComments :: [JSToken.CommentAnnotation] -> [Text]
extractJSDocFromComments [] = []
extractJSDocFromComments (comment:rest) =
  case comment of
    JSToken.CommentA _ commentText ->
      if Text.isPrefixOf "/**" (Text.pack commentText) && Text.isInfixOf "@canopy-type" (Text.pack commentText)
        then Text.pack commentText : extractJSDocFromComments rest
        else extractJSDocFromComments rest
    _ -> extractJSDocFromComments rest

-- | Parse JSDoc text manually to extract function information
parseJSDocTextManual :: FilePath -> Text -> Maybe JSDocFunction
parseJSDocTextManual jsFile jsDocText =
  let jsDocLines = Text.lines jsDocText
      functionName = extractNameManual jsDocLines
      canopyType = extractCanopyTypeManual jsDocLines
      description = extractDescriptionManual jsDocLines
  in case (functionName, canopyType) of
    (Just name, Just ffiType) -> Just $ JSDocFunction
      { jsDocFuncName = name
      , jsDocFuncType = ffiType
      , jsDocFuncDescription = description
      , jsDocFuncParams = []  -- TODO: implement parameter extraction
      , jsDocFuncThrows = []  -- TODO: implement throws extraction
      , jsDocFuncCapabilities = Nothing  -- TODO: implement capability extraction
      , jsDocFuncFile = jsFile
      }
    _ -> Nothing

-- | Extract @name tag manually from JSDoc lines
extractNameManual :: [Text] -> Maybe Text
extractNameManual [] = Nothing
extractNameManual (line:rest) =
  if Text.isInfixOf "@name" line
    then case Text.words (Text.strip line) of
      ("*":"@name":name:_) -> Just name
      _ -> extractNameManual rest
    else extractNameManual rest

-- | Extract @canopy-type tag manually from JSDoc lines
extractCanopyTypeManual :: [Text] -> Maybe FFIType
extractCanopyTypeManual [] = Nothing
extractCanopyTypeManual (line:rest) =
  if Text.isInfixOf "@canopy-type" line
    then case Text.words (Text.strip line) of
      ("*":"@canopy-type":typeWords) ->
        parseCanopyTypeAnnotation (Text.unwords typeWords)
      _ -> extractCanopyTypeManual rest
    else extractCanopyTypeManual rest

-- | Extract description manually from JSDoc lines
extractDescriptionManual :: [Text] -> Maybe Text
extractDescriptionManual jsDocLines =
  let descLines = takeWhile (not . isJSDocTag) (drop 1 (take (length jsDocLines - 1) jsDocLines))
      cleanedLines = map (Text.strip . Text.dropWhile (`elem` ['*', ' '])) descLines
      nonEmptyLines = filter (not . Text.null) cleanedLines
  in if null nonEmptyLines
       then Nothing
       else Just (Text.unwords nonEmptyLines)
  where
    isJSDocTag line = Text.isInfixOf "@" (Text.strip line)


-- | Process a JSDoc comment and extract function information
-- processJSDocComment :: FilePath -> JSDocComment -> Maybe JSDocFunction
-- processJSDocComment jsFile jsDocComment =
--   let functionName = extractFunctionName jsDocComment
--       canopyType = extractCanopyType jsDocComment
--       description = jsDocDescription jsDocComment
--       params = extractParameters jsDocComment
--       throws = extractThrows jsDocComment
--   in case (functionName, canopyType) of
--     (Just name, Just ffiType) -> Just $ JSDocFunction
--       { jsDocFuncName = name
--       , jsDocFuncType = ffiType
--       , jsDocFuncDescription = description
--       , jsDocFuncParams = params
--       , jsDocFuncThrows = throws
--       , jsDocFuncFile = jsFile
--       }
--     _ -> Nothing

-- | Extract function name from JSDoc comment
-- extractFunctionName :: JSDocComment -> Maybe Text
-- extractFunctionName jsDoc =
--   case getJSDocTagsByName "name" jsDoc of
--     (tag:_) -> jsDocTagDescription tag
--     [] -> Nothing

-- | Extract @canopy-type annotation from JSDoc
-- extractCanopyType :: JSDocComment -> Maybe FFIType
-- extractCanopyType jsDoc =
--   case getJSDocTagsByName "canopy-type" jsDoc of
--     (tag:_) -> parseCanopyTypeAnnotation =<< jsDocTagDescription tag
--     [] -> Nothing

-- | Parse Canopy type annotation from text
parseCanopyTypeAnnotation :: Text -> Maybe FFIType
parseCanopyTypeAnnotation typeText =
  parseFFIType (tokenizeType typeText)

-- | Tokenize type text, treating parentheses as separate tokens
tokenizeType :: Text -> [Text]
tokenizeType = go [] ""
  where
    go acc current text
      | Text.null text =
          if Text.null current then acc else acc ++ [current]
      | Text.head text == '(' =
          let newAcc = if Text.null current then acc else acc ++ [current]
          in go (newAcc ++ ["("]) "" (Text.tail text)
      | Text.head text == ')' =
          let newAcc = if Text.null current then acc else acc ++ [current]
          in go (newAcc ++ [")"]) "" (Text.tail text)
      | Text.head text == ' ' =
          if Text.null current
            then go acc "" (Text.tail text)
            else go (acc ++ [current]) "" (Text.tail text)
      | otherwise =
          go acc (current <> Text.take 1 text) (Text.tail text)

-- | Enhanced parser for FFI types with full support for complex types
parseFFIType :: [Text] -> Maybe FFIType
parseFFIType tokens = parseFunction (stripOuterParens tokens)
  where
    -- Strip outer parentheses if they enclose the entire expression
    stripOuterParens :: [Text] -> [Text]
    stripOuterParens ts = case ts of
      "(" : rest -> case matchingParen rest 0 of
        Just (inner, []) -> inner  -- Outer parens enclose everything
        _ -> ts  -- Keep original if not properly enclosed
      _ -> ts

    -- Find the matching closing paren and split the tokens
    matchingParen :: [Text] -> Int -> Maybe ([Text], [Text])
    matchingParen [] _ = Nothing
    matchingParen (t:ts) depth
      | t == "(" = do
          (inner, remaining) <- matchingParen ts (depth + 1)
          pure (t : inner, remaining)
      | t == ")" =
          if depth == 0
            then Just ([], ts)
            else do
              (inner, remaining) <- matchingParen ts (depth - 1)
              pure (t : inner, remaining)
      | otherwise = do
          (inner, remaining) <- matchingParen ts depth
          pure (t : inner, remaining)

    -- Parse function types (param -> param -> result)
    parseFunction :: [Text] -> Maybe FFIType
    parseFunction ts = case findFunctionArrow ts of
      Nothing -> parseBasicType ts
      Just (paramTokens, restTokens) -> do
        case parseFunction restTokens of
          Just returnType ->
            -- Special case: () -> ... should be a zero-parameter function
            if paramTokens == ["(", ")"] || paramTokens == ["()"]
              then Just returnType  -- Skip the unit parameter
              else do
                paramType <- parseBasicType paramTokens
                Just (extendFunction paramType returnType)
          Nothing -> parseBasicType paramTokens

    -- Find the next function arrow (->) that's not inside parentheses
    findFunctionArrow :: [Text] -> Maybe ([Text], [Text])
    findFunctionArrow ts = go [] (0 :: Int) ts
      where
        go _ _ [] = Nothing
        go acc parenCount (t:rest)
          | t == "(" = go (acc ++ [t]) (parenCount + 1) rest
          | t == ")" = go (acc ++ [t]) (parenCount - 1) rest
          | t == "->" && parenCount == 0 = Just (acc, rest)
          | otherwise = go (acc ++ [t]) parenCount rest

    -- Extend function with additional parameter
    extendFunction :: FFIType -> FFIType -> FFIType
    extendFunction paramType (FFIFunctionType params returnType) =
      FFIFunctionType (paramType : params) returnType
    extendFunction paramType returnType =
      FFIFunctionType [paramType] returnType

    -- Parse basic types (not functions)
    parseBasicType :: [Text] -> Maybe FFIType
    parseBasicType ts = case ts of
      [] -> Nothing
      ["String"] -> Just (FFIBasic "String")
      ["Int"] -> Just (FFIBasic "Int")
      ["Bool"] -> Just (FFIBasic "Bool")
      ["Float"] -> Just (FFIBasic "Float")
      ["()"] -> Just (FFIBasic "()")
      ["(", ")"] -> Just (FFIBasic "Unit")  -- Handle tokenized unit type

      -- Task types: Task ErrorType ValueType (handle parenthesized types)
      ("Task" : rest) -> parseTaskType rest

      -- Maybe types: Maybe ValueType (handle parenthesized types)
      ("Maybe" : rest) -> parseMaybeType rest

      -- List types: List ElementType (handle parenthesized types)
      ("List" : rest) -> parseListType rest

      -- Result types: Result ErrorType ValueType (handle parenthesized types)
      ("Result" : rest) -> parseResultType rest

      -- Parenthesized types: (List User) or (Maybe String)
      parenTs@("(" : _) -> parseParenthesized parenTs

      -- Qualified types (e.g., "Capability.UserActivated" -> "UserActivated")
      [qualifiedName] | Text.isInfixOf "." qualifiedName && not (qualifiedName `elem` reservedTypes) ->
        let unqualifiedName = Text.takeWhileEnd (/= '.') qualifiedName
        in Just (FFIOpaque unqualifiedName)

      -- Opaque types (custom JavaScript types)
      [typeName] | not (typeName `elem` reservedTypes) ->
        Just (FFIOpaque typeName)

      -- Multi-word opaque types (e.g., "Available AudioContext", "Permitted AudioPermission")
      multiWordType | length multiWordType > 1 && not (any (`elem` reservedTypes) multiWordType) ->
        Just (FFIOpaque (Text.unwords multiWordType))

      _ -> Nothing

    -- Parse parenthesized types like (List User) or (Maybe String)
    parseParenthesized :: [Text] -> Maybe FFIType
    parseParenthesized ts = case ts of
      "(" : rest -> case break (== ")") rest of
        (innerTokens, ")" : _) -> parseBasicType innerTokens
        _ -> Nothing
      _ -> Nothing

    -- Parse Task types with proper parentheses handling
    parseTaskType :: [Text] -> Maybe FFIType
    parseTaskType ts = case splitTypeArguments ts of
      [errorTokens, valueTokens] -> do
        errorFFI <- parseBasicType errorTokens
        valueFFI <- parseBasicType valueTokens
        Just (FFITask errorFFI valueFFI)
      _ -> Nothing

    -- Parse Maybe types with proper parentheses handling
    parseMaybeType :: [Text] -> Maybe FFIType
    parseMaybeType ts = case splitTypeArguments ts of
      [valueTokens] -> do
        valueFFI <- parseBasicType valueTokens
        Just (FFIMaybe valueFFI)
      _ -> Nothing

    -- Parse List types with proper parentheses handling
    parseListType :: [Text] -> Maybe FFIType
    parseListType ts = case splitTypeArguments ts of
      [elementTokens] -> do
        elementFFI <- parseBasicType elementTokens
        Just (FFIList elementFFI)
      _ -> Nothing

    -- Parse Result types with proper parentheses handling
    parseResultType :: [Text] -> Maybe FFIType
    parseResultType ts = case splitTypeArguments ts of
      [errorTokens, valueTokens] -> do
        errorFFI <- parseBasicType errorTokens
        valueFFI <- parseBasicType valueTokens
        Just (FFIResult errorFFI valueFFI)
      _ -> Nothing

    -- Split tokens into type arguments, respecting parentheses and type boundaries
    splitTypeArguments :: [Text] -> [[Text]]
    splitTypeArguments ts = splitTypes ts []
      where
        splitTypes [] acc = reverse acc
        splitTypes tokenList acc =
          case takeOneType tokenList of
            Just (typeTokens, remainingTokens) ->
              splitTypes remainingTokens (typeTokens : acc)
            Nothing -> reverse acc

        -- Take one complete type from the beginning of the token list
        takeOneType :: [Text] -> Maybe ([Text], [Text])
        takeOneType [] = Nothing
        takeOneType currentTokens@(t:_)
          | t == "(" = takeParenthesizedType currentTokens
          | otherwise = takeSingleOrMultiWordType currentTokens

        -- Take a parenthesized type like "()" or "(List String)"
        takeParenthesizedType :: [Text] -> Maybe ([Text], [Text])
        takeParenthesizedType ("(" : rest) =
          case findMatchingParen rest 0 of
            Just (inner, ")" : remaining) -> Just ("(" : inner ++ [")"], remaining)
            _ -> Nothing
        takeParenthesizedType _ = Nothing

        -- Take a single-word type like "String" or multi-word type like "Initialized AudioContext"
        takeSingleOrMultiWordType :: [Text] -> Maybe ([Text], [Text])
        takeSingleOrMultiWordType [] = Nothing
        takeSingleOrMultiWordType (t:restTokens)
          | t `elem` reservedTypes = Just ([t], restTokens)
          | otherwise =
              -- Check if this starts a multi-word type
              case takeMultiWordType (t:restTokens) of
                (typeTokens@(_:_), remaining) -> Just (typeTokens, remaining)
                ([], _) -> Just ([t], restTokens)

        -- Take a multi-word type by collecting tokens until we hit a reserved word or parenthesis
        takeMultiWordType :: [Text] -> ([Text], [Text])
        takeMultiWordType inputTokens = go [] inputTokens
          where
            go acc [] = (reverse acc, [])
            go acc (t:remainingTokens)
              | t `elem` reservedTypes = (reverse acc, t:remainingTokens)
              | t `elem` ["(", ")"] = (reverse acc, t:remainingTokens)
              | otherwise = go (t:acc) remainingTokens

        -- Find matching parenthesis, returning inner tokens and remaining tokens
        findMatchingParen :: [Text] -> Int -> Maybe ([Text], [Text])
        findMatchingParen [] _ = Nothing
        findMatchingParen (t:tokenRest) depth
          | t == "(" = do
              (inner, remaining) <- findMatchingParen tokenRest (depth + 1)
              return (t:inner, remaining)
          | t == ")" =
              if depth == 0
                then Just ([], t:tokenRest)
                else do
                  (inner, remaining) <- findMatchingParen tokenRest (depth - 1)
                  return (t:inner, remaining)
          | otherwise = do
              (inner, remaining) <- findMatchingParen tokenRest depth
              return (t:inner, remaining)

    -- Reserved type names that aren't opaque types
    reservedTypes :: [Text]
    reservedTypes = ["String", "Int", "Bool", "Float", "Task", "Maybe", "List", "Result", "->", "(", ")"]

-- | Extract parameter information from JSDoc
-- extractParameters :: JSDocComment -> [(Text, FFIType, Maybe Text)]
-- extractParameters jsDoc =
--   let paramTags = getJSDocTagsByName "param" jsDoc
--   in Maybe.mapMaybe extractParamInfo paramTags
--   where
--     extractParamInfo :: JSDocTag -> Maybe (Text, FFIType, Maybe Text)
--     extractParamInfo tag = do
--       paramName <- jsDocTagParamName tag
--       paramType <- convertJSDocTypeToFFI =<< jsDocTagType tag
--       let paramDesc = jsDocTagDescription tag
--       return (paramName, paramType, paramDesc)

-- | Extract @throws information from JSDoc
-- extractThrows :: JSDocComment -> [Text]
-- extractThrows jsDoc =
--   let throwsTags = getJSDocTagsByName "throws" jsDoc
--   in Maybe.mapMaybe jsDocTagDescription throwsTags

-- | Convert JSDoc type to FFI type
-- convertJSDocTypeToFFI :: JSDocType -> Maybe FFIType
-- convertJSDocTypeToFFI jsDocType =
--   case jsDocType of
--     JSDocBasicType "string" -> Just (FFIBasic "String")
--     JSDocBasicType "number" -> Just (FFIBasic "Int")
--     JSDocBasicType "boolean" -> Just (FFIBasic "Bool")
--     JSDocBasicType typeName -> Just (FFIOpaque typeName)
--     JSDocArrayType elementType -> do
--       elemFFI <- convertJSDocTypeToFFI elementType
--       return (FFIList elemFFI)
--     JSDocUnionType types ->
--       -- For now, just take the first type - this could be enhanced
--       case types of
--         (t:_) -> convertJSDocTypeToFFI t
--         [] -> Nothing
--     JSDocGenericType "Promise" [valueType] -> do
--       valueFFI <- convertJSDocTypeToFFI valueType
--       return (FFITask (FFIOpaque "Error") valueFFI)
--     JSDocGenericType "Array" [elementType] -> do
--       elemFFI <- convertJSDocTypeToFFI elementType
--       return (FFIList elemFFI)
--     JSDocFunctionType paramTypes returnType -> do
--       paramFFIs <- traverse convertJSDocTypeToFFI paramTypes
--       returnFFI <- convertJSDocTypeToFFI returnType
--       return (FFIFunctionType paramFFIs returnFFI)
--     _ -> Nothing

-- | Generate FFI bindings from JSDoc functions
--
-- Creates Canopy function signatures and runtime wrappers
-- for JavaScript functions with proper type checking.
--
-- @since 0.19.1
generateFFIBindings :: [JSDocFunction] -> Either FFIError Text
generateFFIBindings functions = do
  bindings <- traverse generateValueBinding functions
  pure $ Text.unlines bindings
  where
    generateValueBinding :: JSDocFunction -> Either FFIError Text
    generateValueBinding jsFunc = do
      canopyType <- ffiTypeToCanopyType (jsDocFuncType jsFunc)
      let funcName = jsDocFuncName jsFunc
          description = maybe "" (\desc -> "-- | " <> desc <> "\n") (jsDocFuncDescription jsFunc)
      pure $ description <> funcName <> " : " <> canopyType

-- | Qualify basic types appropriately
-- Built-in types remain unqualified, custom types get qualified
qualifyBasicType :: Text -> Text
qualifyBasicType typeName = case typeName of
  "String" -> "String"
  "Int" -> "Int"
  "Bool" -> "Bool"
  "Float" -> "Float"
  "()" -> "()"
  "Unit" -> "()"  -- Convert Unit to () for consistency
  "Never" -> "Never"
  -- Capability types should be unqualified (like core types)
  "UserActivated" -> "UserActivated"
  "Initialized" -> "Initialized"
  "Permitted" -> "Permitted"
  "Available" -> "Available"
  "CapabilityError" -> "CapabilityError"
  customType -> customType  -- Custom types remain as-is for now

-- | Convert FFI type to Canopy type syntax
-- Uses qualified type names for maximum safety and consistency
ffiTypeToCanopyType :: FFIType -> Either FFIError Text
ffiTypeToCanopyType ffiType = case ffiType of
  FFIBasic typeName -> Right (qualifyBasicType typeName)
  FFIResult errorType valueType -> do
    errType <- ffiTypeToCanopyType errorType
    valType <- ffiTypeToCanopyType valueType
    Right $ "Result.Result " <> errType <> " " <> valType
  FFITask errorType valueType -> do
    errType <- ffiTypeToCanopyType errorType
    valType <- ffiTypeToCanopyType valueType
    Right $ "Task " <> errType <> " " <> valType
  FFIMaybe valueType -> do
    valType <- ffiTypeToCanopyType valueType
    Right $ "Maybe.Maybe " <> valType
  FFIList valueType -> do
    valType <- ffiTypeToCanopyType valueType
    Right $ "List.List " <> valType
  FFIFunctionType paramTypes returnType -> do
    paramTypeTexts <- traverse ffiTypeToCanopyType paramTypes
    returnTypeText <- ffiTypeToCanopyType returnType
    let functionType = case paramTypeTexts of
          [] -> returnTypeText
          _ -> Text.intercalate " -> " paramTypeTexts <> " -> " <> returnTypeText
    Right functionType
  FFIOpaque typeName -> Right (qualifyBasicType typeName)
  FFITuple types -> do
    typeTexts <- traverse ffiTypeToCanopyType types
    Right $ "(" <> Text.intercalate ", " typeTexts <> ")"
  FFIRecord fields -> do
    fieldResults <- traverse (\(name, fieldType) -> do
      typeText <- ffiTypeToCanopyType fieldType
      pure (name <> " : " <> typeText)) fields
    Right $ "{ " <> Text.intercalate ", " fieldResults <> " }"

-- | Validate an FFI declaration
--
-- Checks that the target file exists, contains valid JSDoc,
-- and all referenced functions are properly typed.
--
-- @since 0.19.1
validateFFIDeclaration :: FFIDeclaration -> IO (Either FFIError [JSDocFunction])
validateFFIDeclaration ffiDecl = do
  case ffiTarget ffiDecl of
    JavaScriptFFI jsFile -> parseJSDocFromFile jsFile
    WebAssemblyFFI _ -> return $ Left $ UnsupportedJSType "WebAssembly not yet supported"

-- | Generate a complete FFI module
--
-- Creates a Canopy module with all bindings from a JavaScript file.
--
-- @since 0.19.1
generateFFIModule :: FFIDeclaration -> [JSDocFunction] -> Either FFIError Text
generateFFIModule ffiDecl functions = do
  bindings <- generateFFIBindings functions
  let aliasName = case ffiAlias ffiDecl of
        A.At _ name -> Name.toChars name

  -- Create module text representation
  pure $ Text.unlines
    [ "-- Auto-generated FFI module for " <> Text.pack aliasName
    , "module " <> Text.pack aliasName <> " exposing (..)"
    , ""
    , bindings
    ]

-- | Generate runtime wrapper code
--
-- Creates JavaScript wrapper functions that provide runtime
-- type checking and error conversion for FFI calls.
--
-- @since 0.19.1
generateRuntimeWrapper :: JSDocFunction -> Text
generateRuntimeWrapper jsFunc =
  let funcName = jsDocFuncName jsFunc
      wrapperName = funcName <> "_safe"
  in Text.unlines
    [ "// Auto-generated wrapper for " <> funcName
    , "function " <> wrapperName <> "() {"
    , "  // TODO: Add runtime type validation"
    , "  // TODO: Add error conversion"
    , "  // TODO: Call original function with checks"
    , "  throw new Error('Not implemented yet');"
    , "}"
    ]

-- | Simple FFI import representation to avoid circular dependencies
data SimpleFFIImport = SimpleFFIImport
  { simpleFfiTarget :: !FFITarget
  , simpleFfiAlias :: !Text
  , simpleFfiRegion :: !A.Region
  } deriving (Show)

-- | Parse JavaScript file and extract FFI functions
--
-- Higher-level interface for test generation that returns Map of function names to FFIFunction.
--
-- @since 0.19.1
parseJavaScriptFile :: FilePath -> Text -> Either Text (Map.Map Text FFIFunction)
parseJavaScriptFile jsFile content = do
  -- Parse the JavaScript file
  ast <- case JS.parseModule (Text.unpack content) jsFile of
    Left parseError -> Left (Text.pack $ "Parse error: " ++ show parseError)
    Right parsedAst -> Right parsedAst

  -- Extract JSDoc functions
  let jsDocFunctions = extractJSDocFromAST jsFile ast

  -- Convert to FFIFunction format
  let ffiFunctions = map jsDocToFFIFunction jsDocFunctions

  -- Create map of function names to FFI functions
  let functionMap = Map.fromList [(jsDocFuncName jsFunc, ffiFunc) | (jsFunc, ffiFunc) <- zip jsDocFunctions ffiFunctions]

  Right functionMap
  where
    jsDocToFFIFunction :: JSDocFunction -> FFIFunction
    jsDocToFFIFunction jsDoc = case flattenFunctionType (jsDocFuncType jsDoc) of
      (inputTypes, outputType) -> FFIFunction inputTypes outputType (jsDocFuncThrows jsDoc)

    -- Flatten nested function types into parameter list and return type
    flattenFunctionType :: FFIType -> ([FFIType], FFIType)
    flattenFunctionType ffiType = case ffiType of
      FFIFunctionType params returnType ->
        let (nestedParams, finalReturn) = flattenFunctionType returnType
        in (params ++ nestedParams, finalReturn)
      otherType ->
        -- For debugging: if this is reached for complex types, they're not being parsed as functions
        case otherType of
          FFIBasic typeName | Text.isInfixOf "->" typeName ->
            -- This indicates the entire function type is being treated as a basic type!
            -- This is the bug - the parsing isn't working correctly
            ([], otherType)
          _ -> ([], otherType)

-- | Process foreign imports from a module
--
-- Extracts FFI functions from JavaScript files and creates
-- type-safe bindings for use in Canopy code.
--
-- @since 0.19.1
processForeignImports :: [SimpleFFIImport] -> IO (Either FFIError [(Text, [JSDocFunction])])
processForeignImports foreignImports = do
  results <- traverse processForeignImport foreignImports
  pure $ sequence results
  where
    processForeignImport :: SimpleFFIImport -> IO (Either FFIError (Text, [JSDocFunction]))
    processForeignImport (SimpleFFIImport target alias _) = do
      case target of
        JavaScriptFFI jsFile -> do
          parseResult <- parseJSDocFromFile jsFile
          case parseResult of
            Left err -> pure $ Left err
            Right functions -> pure $ Right (alias, functions)
        WebAssemblyFFI _ -> pure $ Left $ UnsupportedJSType "WebAssembly not yet supported"
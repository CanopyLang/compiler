{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

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
  , JsFunctionName(..)
  , PermissionName(..)
  , ResourceName(..)
  , BindingMode(..)

    -- * JSDoc Integration
  , JSDocFunction(..)
  , parseJSDocFromFile
  , parseJavaScriptFile
  , generateFFIBindings
  , processForeignImports

    -- * Type Parsing
  , parseCanopyTypeAnnotation

    -- * Error Handling
  , FFIError(..)
  , validateFFIDeclaration

  ) where

import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Text.Encoding as TextEnc
import qualified Canopy.Data.Name as Name
import qualified FFI.TypeParser as TypeParser
import qualified Reporting.Annotation as Ann
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
import FFI.Types (FFIType (..), JsFunctionName(..), PermissionName(..), ResourceName(..), BindingMode(..))

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
  , ffiAlias :: !(Ann.Located Name.Name)
    -- ^ Module alias for imported functions
  , ffiLocation :: !Ann.Region
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

-- FFIType is imported from FFI.Types (single source of truth)

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
  { jsDocFuncName :: !JsFunctionName
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
  , jsDocFuncBindMode :: !BindingMode
    -- ^ Binding mode from @canopy-bind annotation
  , jsDocFuncCanopyName :: !(Maybe Text)
    -- ^ Optional Canopy-side name override from @canopy-name annotation
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
    JSToken.CommentA _ commentBytes ->
      let commentText = TextEnc.decodeUtf8Lenient commentBytes
      in if Text.isPrefixOf "/**" commentText && Text.isInfixOf "@canopy-type" commentText
           then commentText : extractJSDocFromComments rest
           else extractJSDocFromComments rest
    _ -> extractJSDocFromComments rest

-- | Parse JSDoc text manually to extract function information
parseJSDocTextManual :: FilePath -> Text -> Maybe JSDocFunction
parseJSDocTextManual jsFile jsDocText =
  let jsDocLines = Text.lines jsDocText
      functionName = extractNameManual jsDocLines
      canopyType = extractCanopyTypeManual jsDocLines
      description = extractDescriptionManual jsDocLines
      params = extractParamsManual jsDocLines
      throws = extractThrowsManual jsDocLines
      capabilities = extractCapabilityManual jsDocLines
      bindMode = extractBindModeManual jsDocLines
      canopyName = extractCanopyNameManual jsDocLines
  in case (functionName, canopyType) of
    (Just name, Just ffiType) -> Just $ JSDocFunction
      { jsDocFuncName = JsFunctionName name
      , jsDocFuncType = ffiType
      , jsDocFuncDescription = description
      , jsDocFuncParams = params
      , jsDocFuncThrows = throws
      , jsDocFuncCapabilities = capabilities
      , jsDocFuncFile = jsFile
      , jsDocFuncBindMode = bindMode
      , jsDocFuncCanopyName = canopyName
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


-- | Extract @param tags from JSDoc lines.
--
-- Parses lines like: @param {Type} name - description
extractParamsManual :: [Text] -> [(Text, FFIType, Maybe Text)]
extractParamsManual = foldr extractParam []
  where
    extractParam line acc
      | Text.isInfixOf "@param" (Text.strip line) = parseParamLine line ++ acc
      | otherwise = acc
    parseParamLine line =
      case Text.words (Text.strip line) of
        ("*":"@param":rest) -> parseParamWords rest
        _ -> []
    parseParamWords (typeBraced:name:rest)
      | Just ffiType <- parseCanopyTypeAnnotation (Text.dropAround isBrace typeBraced) =
          [(name, ffiType, descFromRest rest)]
    parseParamWords _ = []
    isBrace c = c == '{' || c == '}'
    descFromRest [] = Nothing
    descFromRest ("-":ws) = Just (Text.unwords ws)
    descFromRest ws = Just (Text.unwords ws)

-- | Extract @throws tags from JSDoc lines.
--
-- Parses lines like: @throws {ErrorType} description
extractThrowsManual :: [Text] -> [Text]
extractThrowsManual = foldr extractThrow []
  where
    extractThrow line acc
      | Text.isInfixOf "@throws" (Text.strip line) = parseThrowLine line ++ acc
      | otherwise = acc
    parseThrowLine line =
      case Text.words (Text.strip line) of
        ("*":"@throws":rest) -> [Text.unwords rest]
        _ -> []

-- | Extract @capability tag from JSDoc lines.
--
-- Parses lines like: @capability permission microphone
extractCapabilityManual :: [Text] -> Maybe Capability.CapabilityConstraint
extractCapabilityManual [] = Nothing
extractCapabilityManual (line:rest)
  | Text.isInfixOf "@capability" (Text.strip line) = parseCapabilityLine line
  | otherwise = extractCapabilityManual rest
  where
    parseCapabilityLine l =
      case Text.words (Text.strip l) of
        ("*":"@capability":"permission":perm:_) -> Just (Capability.PermissionRequired (PermissionName perm))
        ("*":"@capability":"user-activation":_) -> Just Capability.UserActivationRequired
        ("*":"@capability":"init":resource:_) -> Just (Capability.InitializationRequired (ResourceName resource))
        ("*":"@capability":"availability":feature:_) -> Just (Capability.AvailabilityRequired feature)
        _ -> Nothing

-- | Extract @canopy-bind annotation from JSDoc lines.
--
-- Parses lines like:
-- @* \@canopy-bind method addEventListener@
-- @* \@canopy-bind get currentTime@
extractBindModeManual :: [Text] -> BindingMode
extractBindModeManual [] = FunctionCall
extractBindModeManual (line:rest)
  | Text.isInfixOf "@canopy-bind" (Text.strip line) =
      Maybe.fromMaybe (extractBindModeManual rest) (parseBindModeLine line)
  | otherwise = extractBindModeManual rest

-- | Parse a @canopy-bind annotation line into a BindingMode.
parseBindModeLine :: Text -> Maybe BindingMode
parseBindModeLine line =
  case Text.words (Text.strip line) of
    ("*":"@canopy-bind":"method":name:_) -> Just (MethodCall name)
    ("*":"@canopy-bind":"get":name:_) -> Just (PropertyGet name)
    ("*":"@canopy-bind":"set":name:_) -> Just (PropertySet name)
    ("*":"@canopy-bind":"new":name:_) -> Just (ConstructorCall name)
    _ -> Nothing

-- | Extract @canopy-name annotation from JSDoc lines.
--
-- Parses lines like: @* \@canopy-name setOscillatorFrequency@
extractCanopyNameManual :: [Text] -> Maybe Text
extractCanopyNameManual [] = Nothing
extractCanopyNameManual (line:rest)
  | Text.isInfixOf "@canopy-name" (Text.strip line) =
      case Text.words (Text.strip line) of
        ("*":"@canopy-name":name:_) -> Just name
        _ -> extractCanopyNameManual rest
  | otherwise = extractCanopyNameManual rest

-- | Parse Canopy type annotation from text.
--
-- Delegates to the unified parser in "FFI.TypeParser".
parseCanopyTypeAnnotation :: Text -> Maybe FFIType
parseCanopyTypeAnnotation = TypeParser.parseType

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
      let funcName = unJsFunctionName (jsDocFuncName jsFunc)
          description = maybe "" (\desc -> "-- | " <> desc <> "\n") (jsDocFuncDescription jsFunc)
      pure $ description <> funcName <> " : " <> canopyType

-- | Qualify basic types appropriately
-- Built-in types remain unqualified, custom types are passed through
-- and validated by the type system
qualifyBasicType :: Text -> Text
qualifyBasicType typeName = case typeName of
  "String" -> "String"
  "Int" -> "Int"
  "Bool" -> "Bool"
  "Float" -> "Float"
  "()" -> "()"
  "Unit" -> "()"  -- Convert Unit to () for consistency
  "Never" -> "Never"
  -- All other types (including capabilities) are passed through
  -- The type system validates whether they exist
  customType -> customType

-- | Convert FFI type to Canopy type syntax
-- Uses qualified type names for maximum safety and consistency
ffiTypeToCanopyType :: FFIType -> Either FFIError Text
ffiTypeToCanopyType ffiType = case ffiType of
  FFIInt -> Right "Basics.Int"
  FFIFloat -> Right "Basics.Float"
  FFIString -> Right "String.String"
  FFIBool -> Right "Basics.Bool"
  FFIUnit -> Right "()"
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
    Right $ "( " <> Text.intercalate ", " typeTexts <> " )"
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

-- | Simple FFI import representation to avoid circular dependencies
data SimpleFFIImport = SimpleFFIImport
  { simpleFfiTarget :: !FFITarget
  , simpleFfiAlias :: !Text
  , simpleFfiRegion :: !Ann.Region
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
  let functionMap = Map.fromList [(unJsFunctionName (jsDocFuncName jsFunc), ffiFunc) | (jsFunc, ffiFunc) <- zip jsDocFunctions ffiFunctions]

  Right functionMap
  where
    jsDocToFFIFunction :: JSDocFunction -> FFIFunction
    jsDocToFFIFunction jsDoc = case flattenFunctionType (jsDocFuncType jsDoc) of
      (inputTypes, outputType) -> FFIFunction inputTypes outputType (jsDocFuncThrows jsDoc)

    -- Flatten nested function types into parameter list and return type
    --
    -- This function takes potentially nested FFIFunction structures and
    -- flattens them into a single parameter list and return type.
    -- Example: FFIFunction [A] (FFIFunction [B] C) becomes ([A, B], C)
    flattenFunctionType :: FFIType -> ([FFIType], FFIType)
    flattenFunctionType = \case
      FFIFunctionType params returnType ->
        let (nestedParams, finalReturn) = flattenFunctionType returnType
        in (params ++ nestedParams, finalReturn)
      otherType -> ([], otherType)

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
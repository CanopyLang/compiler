{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Canonicalize.Module.FFI - FFI processing for Canopy modules
--
-- This module handles all FFI-related functionality for module canonicalization,
-- including loading JavaScript files, parsing type annotations, and building
-- the FFI environment. It is a sub-module of "Canonicalize.Module" and is
-- re-exported from there.
--
-- Users should import "Canonicalize.Module" rather than this module directly.
--
-- @since 0.19.1
module Canonicalize.Module.FFI
  ( loadFFIContent,
    loadFFIContentWithRoot,
    addFFIToEnvPure,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Environment as Env
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Exception (SomeException, catch)
import Data.List (intercalate, isPrefixOf, isInfixOf)
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Foreign.FFI as FFI
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified System.FilePath as FP
import System.FilePath ((</>))

-- RESULT TYPE ALIAS

type Result i w a =
  Result.Result i w Error.Error a

-- | Load FFI content from foreign imports in the IO monad
--
-- This function reads JavaScript files referenced in foreign imports
-- and returns a map of file paths to their content. This should be called
-- before canonicalization to avoid threading issues.
--
-- @since 0.19.1
loadFFIContent :: [Src.ForeignImport] -> IO (Map String String)
loadFFIContent = loadFFIContentWithRoot "."

-- | Load FFI content with explicit root directory for path resolution.
--
-- Validates paths before reading to prevent path traversal attacks.
loadFFIContentWithRoot :: FilePath -> [Src.ForeignImport] -> IO (Map String String)
loadFFIContentWithRoot rootDir foreignImports = do
  results <- traverse loadSingleFFI foreignImports
  return $ Map.fromList (concat results)
  where
    loadSingleFFI :: Src.ForeignImport -> IO [(String, String)]
    loadSingleFFI (Src.ForeignImport (FFI.JavaScriptFFI jsPath) _alias _region) =
      case validateFFIPath jsPath of
        Left _ -> return []
        Right validPath -> do
          result <- loadFFIFileWithTimeout (rootDir </> validPath) validPath
          either (const (return [])) (\c -> return [(validPath, c)]) result
    loadSingleFFI _ = return []

-- | Validate an FFI source file path for safety.
--
-- Rejects absolute paths, path traversal (..), null bytes,
-- and non-JavaScript extensions.
validateFFIPath :: FilePath -> Either String FilePath
validateFFIPath path
  | FP.isAbsolute path =
      Left "FFI source path must be relative"
  | ".." `elem` FP.splitDirectories path =
      Left "FFI source path cannot contain '..'"
  | '\0' `elem` path =
      Left "FFI source path contains null byte"
  | not (FP.takeExtension path `elem` [".js", ".mjs"]) =
      Left "FFI source path must end in .js or .mjs"
  | otherwise = Right (FP.normalise path)

-- | Load FFI file with error handling.
loadFFIFileWithTimeout :: FilePath -> String -> IO (Either String String)
loadFFIFileWithTimeout fullPath _jsPath = do
  result <- try (readFile fullPath)
  case result of
    Left (_ :: SomeException) -> return (Left "File not found")
    Right content -> return (Right content)
  where
    try :: IO a -> IO (Either SomeException a)
    try action = (Right <$> action) `catch` (return . Left)

-- | Add FFI functions to environment using pre-loaded content (pure).
--
-- Processes all FFI imports sequentially, threading the updated
-- environment through each import so all foreign functions are available.
addFFIToEnvPure :: Env.Env -> [Src.ForeignImport] -> Map String String -> Result i [w] Env.Env
addFFIToEnvPure env [] _ffiContentMap = Result.ok env
addFFIToEnvPure env (fi : rest) ffiContentMap =
  addOneFFI env fi >>= \updatedEnv -> addFFIToEnvPure updatedEnv rest ffiContentMap
  where
    addOneFFI currentEnv (Src.ForeignImport (FFI.JavaScriptFFI jsPath) alias region) =
      case validateFFIPath jsPath of
        Left reason -> Result.throw (Error.FFIPathTraversal region jsPath reason)
        Right validPath -> processFFIImport currentEnv validPath alias region ffiContentMap
    addOneFFI _currentEnv (Src.ForeignImport (FFI.WebAssemblyFFI _wasmPath) _alias region) =
      Result.throw (Error.FFIParseError region "WebAssembly" "WebAssembly FFI is not yet supported")

-- Process single FFI import with comprehensive error handling
processFFIImport :: Env.Env -> FilePath -> Ann.Located Name.Name -> Ann.Region -> Map String String -> Result i [w] Env.Env
processFFIImport env jsPath alias region ffiContentMap =
  let aliasName = Ann.toValue alias
      home = Env._home env
      ffiModuleName = ModuleName.Canonical (ModuleName._package home) aliasName
  in case Map.lookup jsPath ffiContentMap of
       Nothing -> Result.throw (Error.FFIFileNotFound region jsPath)
       Just jsContent -> parseAndAddFFI env ffiModuleName aliasName jsPath region jsContent

-- Parse FFI content and add to environment with validation
parseAndAddFFI :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> Ann.Region -> String -> Result i [w] Env.Env
parseAndAddFFI env ffiModuleName aliasName jsPath region jsContent =
  case parseJavaScriptContentPure jsContent (Name.toChars aliasName) of
    Left err -> Result.throw (Error.FFIParseError region jsPath err)
    Right functions -> validateAndAddFunctions env ffiModuleName aliasName jsPath region functions

-- Validate and add FFI functions to environment
validateAndAddFunctions :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> Ann.Region -> [(String, String)] -> Result i [w] Env.Env
validateAndAddFunctions env ffiModuleName aliasName jsPath region functions =
  case validateFFIFunctions jsPath region functions of
    Left err -> Result.throw err
    Right validFunctions -> addParsedFunctionsToEnv env ffiModuleName aliasName jsPath region validFunctions

-- Validate FFI functions have proper type annotations
validateFFIFunctions :: FilePath -> Ann.Region -> [(String, String)] -> Either Error.Error [(String, String)]
validateFFIFunctions jsPath region functions =
  traverse (validateSingleFunction jsPath region) functions

-- Validate single FFI function signature
validateSingleFunction :: FilePath -> Ann.Region -> (String, String) -> Either Error.Error (String, String)
validateSingleFunction jsPath region (fname, typeStr) =
  if null typeStr
    then Left (Error.FFIMissingAnnotation region jsPath (Name.fromChars fname))
    else Right (fname, typeStr)

-- | Parse JavaScript content purely without IO operations
--
-- This replaces the problematic parseJavaScriptFile function that used
-- unsafePerformIO for file reading.
--
-- @since 0.19.1
parseJavaScriptContentPure :: String -> String -> Either String [(String, String)]
parseJavaScriptContentPure jsContent _alias =
  Right (extractFunctionsWithTypes (lines jsContent))

-- Extract functions with their @canopy-type annotations
-- Now properly handles JSDoc comments with @name and @canopy-type annotations
extractFunctionsWithTypes :: [String] -> [(String, String)]
extractFunctionsWithTypes [] = []
extractFunctionsWithTypes inputLines = extractFromJSDocBlocks inputLines

-- Extract functions from JSDoc comment blocks
extractFromJSDocBlocks :: [String] -> [(String, String)]
extractFromJSDocBlocks [] = []
extractFromJSDocBlocks (line:rest)
  | isJSDocStart line =
      let (commentBlock, remaining) = takeJSDocBlock (line:rest)
          mbFunction = parseJSDocBlock commentBlock
      in case mbFunction of
           Just func -> func : extractFromJSDocBlocks remaining
           Nothing -> extractFromJSDocBlocks remaining
  | otherwise = extractFromJSDocBlocks rest

-- Check if line starts a JSDoc comment
isJSDocStart :: String -> Bool
isJSDocStart line =
  let trimmed = dropWhile (`elem` (" \t" :: String)) line
  in "/**" `isPrefixOf` trimmed

-- Take a complete JSDoc comment block
takeJSDocBlock :: [String] -> ([String], [String])
takeJSDocBlock [] = ([], [])
takeJSDocBlock (line:rest) =
  if isJSDocEnd line
    then ([line], rest)
    else let (block, remaining) = takeJSDocBlock rest
         in (line:block, remaining)

-- Check if line ends a JSDoc comment
isJSDocEnd :: String -> Bool
isJSDocEnd line = "*/" `isInfixOf` line

-- Parse a JSDoc comment block to extract function name and type
parseJSDocBlock :: [String] -> Maybe (String, String)
parseJSDocBlock commentLines = do
  functionName <- findNameAnnotation commentLines
  canopyType <- findCanopyTypeAnnotation commentLines
  pure (functionName, canopyType)

-- Find @name annotation in JSDoc block
findNameAnnotation :: [String] -> Maybe String
findNameAnnotation [] = Nothing
findNameAnnotation (line:rest) =
  case parseNameAnnotation line of
    Just name -> Just name
    Nothing -> findNameAnnotation rest

-- Find @canopy-type annotation in JSDoc block
findCanopyTypeAnnotation :: [String] -> Maybe String
findCanopyTypeAnnotation [] = Nothing
findCanopyTypeAnnotation (line:rest) =
  case parseCanopyTypeAnnotation line of
    Just typeStr -> Just typeStr
    Nothing -> findCanopyTypeAnnotation rest

-- Parse @name annotation from a line
parseNameAnnotation :: String -> Maybe String
parseNameAnnotation line =
  let trimmed = dropWhile (`elem` (" *" :: String)) line
  in if ("@name " :: String) `isPrefixOf` trimmed
     then Just (strip (drop (length ("@name " :: String)) trimmed))
     else Nothing

-- Strip leading and trailing whitespace
strip :: String -> String
strip = dropWhileEnd (`elem` (" \t\n\r" :: String)) . dropWhile (`elem` (" \t\n\r" :: String))
  where
    dropWhileEnd predicate xs = foldr (\x acc -> if predicate x && null acc then [] else x:acc) [] xs

-- Parse @canopy-type annotation from a line
parseCanopyTypeAnnotation :: String -> Maybe String
parseCanopyTypeAnnotation line =
  let trimmed = dropWhile (`elem` (" *" :: String)) line
  in if ("@canopy-type " :: String) `isPrefixOf` trimmed
     then Just (drop (length ("@canopy-type " :: String)) trimmed)
     else Nothing

-- DYNAMIC FUNCTION ENVIRONMENT GENERATION
addParsedFunctionsToEnv :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> Ann.Region -> [(String, String)] -> Result i [w] Env.Env
addParsedFunctionsToEnv env ffiModuleName aliasName jsPath region functions = do
  let homeModuleName = Env._home env
  processedFunctions <- traverse (processParsedFunction env ffiModuleName homeModuleName jsPath region) functions
  let (vars, qVars) = buildDynamicEnvironment aliasName processedFunctions
      newVars = List.foldl' (\acc (name, var) -> Map.insert name var acc) (Env._vars env) vars
      newQVars = Map.insertWith Map.union aliasName qVars (Env._q_vars env)
      newEnv = env { Env._vars = newVars, Env._q_vars = newQVars }
  Result.ok newEnv

-- Process a single parsed function (name, typeString) into Canopy types
processParsedFunction :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> FilePath -> Ann.Region -> (String, String) -> Result i [w] (String, Can.Annotation, Env.Var)
processParsedFunction env ffiModuleName homeModuleName jsPath region (functionName, typeString) = do
  canopyType <- parseTypeStringWithHome env ffiModuleName homeModuleName jsPath region functionName typeString
  let annotation = Can.Forall Map.empty canopyType
      var = Env.Foreign ffiModuleName annotation
  Result.ok (functionName, annotation, var)

-- Build the dynamic environment from processed functions with proper qualified name registration
buildDynamicEnvironment :: Name.Name -> [(String, Can.Annotation, Env.Var)] -> ([(Name.Name, Env.Var)], Map.Map Name.Name (Env.Info Can.Annotation))
buildDynamicEnvironment aliasName processedFunctions =
  let ffiModuleName = ModuleName.Canonical Pkg.dummyName aliasName
      vars = []
      qVars = buildQualifiedVars ffiModuleName processedFunctions
  in (vars, qVars)

-- Build qualified vars map for FFI functions (Module.functionName syntax)
buildQualifiedVars :: ModuleName.Canonical -> [(String, Can.Annotation, Env.Var)] -> Map.Map Name.Name (Env.Info Can.Annotation)
buildQualifiedVars ffiModuleName processedFunctions =
  Map.fromList (List.map toQualifiedEntry processedFunctions)
  where
    toQualifiedEntry (fname, annotation, _) =
      (Name.fromChars fname, Env.Specific ffiModuleName annotation)

-- Parse type string with home module context for custom type resolution
-- ffiModuleName is used as fallback for unknown opaque types (FFI-specific types)
parseTypeStringWithHome :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> FilePath -> Ann.Region -> String -> String -> Result i [w] Can.Type
parseTypeStringWithHome env ffiModuleName homeModuleName jsPath region functionName typeStr =
  case parseTypeTokensWithHome env ffiModuleName homeModuleName (tokenizeCanopyType (Text.pack typeStr)) of
    Just canopyType -> Result.ok canopyType
    Nothing -> Result.throw (Error.FFIInvalidType region jsPath (Name.fromChars functionName) ("Failed to parse type: " ++ typeStr))

-- Tokenize Canopy type string correctly, handling multi-word types
-- Splits by top-level arrows (respecting parentheses and braces), then tokenizes each segment
tokenizeCanopyType :: Text.Text -> [String]
tokenizeCanopyType typeText =
  let arrowSegments = splitArrowsRespectingParens typeText
      nonEmptySegments = filter (not . Text.null . Text.strip) arrowSegments
      tokenizedSegments = map (tokenizeTypeSegment . Text.strip) nonEmptySegments
  in case tokenizedSegments of
       [] -> []
       [singleSegment] -> singleSegment
       multipleSegments -> List.intercalate ["->"] multipleSegments

-- | Split a type string by @->@ arrows at the top level only.
--
-- Parenthesized and braced groups are treated as atomic, so arrows
-- inside @(Browser -> Expectation)@ or @{ a : Int -> String }@ are preserved.
splitArrowsRespectingParens :: Text.Text -> [Text.Text]
splitArrowsRespectingParens input = go [] "" (0 :: Int) (Text.unpack input)
  where
    go :: [Text.Text] -> String -> Int -> String -> [Text.Text]
    go acc current _ [] =
      reverse (Text.pack current : acc)
    go acc current depth ('(' : cs) =
      go acc (current ++ "(") (depth + 1) cs
    go acc current depth ('{' : cs) =
      go acc (current ++ "{") (depth + 1) cs
    go acc current depth (')' : cs) =
      go acc (current ++ ")") (max 0 (depth - 1)) cs
    go acc current depth ('}' : cs) =
      go acc (current ++ "}") (max 0 (depth - 1)) cs
    go acc current 0 ('-' : '>' : cs) =
      go (Text.pack current : acc) "" 0 cs
    go acc current depth (c : cs) =
      go acc (current ++ [c]) depth cs

-- Tokenize a single type segment into words, preserving parenthesized expressions
tokenizeTypeSegment :: Text.Text -> [String]
tokenizeTypeSegment segment =
  go [] "" (0 :: Int) (Text.unpack segment)
  where
    go acc current _depth [] =
      if null current then reverse acc else reverse (current : acc)
    go acc current depth (c:cs)
      | c == '(' = go acc (current ++ "(") (depth + 1) cs
      | c == ')' =
          let newCurrent = current ++ ")"
          in if depth == 1
               then go (newCurrent : acc) "" (depth - 1) cs
               else go acc newCurrent (depth - 1) cs
      | c == ' ' && depth == 0 =
          if null current
            then go acc "" 0 cs
            else go (current : acc) "" 0 cs
      | otherwise = go acc (current ++ [c]) depth cs

-- Split tokens at top-level arrow (not inside parentheses)
splitAtArrow :: [String] -> Maybe ([String], [String])
splitAtArrow tokens =
  go tokens 0 []
  where
    go :: [String] -> Int -> [String] -> Maybe ([String], [String])
    go [] _ _ = Nothing
    go ("(" : rest) depth acc = go rest (depth + 1) (acc ++ ["("])
    go (")" : rest) depth acc = go rest (depth - 1) (acc ++ [")"])
    go ("->" : rest) 0 acc = Just (acc, rest)
    go ("->" : rest) depth acc = go rest depth (acc ++ ["->"])
    go (t : rest) depth acc = go rest depth (acc ++ [t])

-- Parse type tokens with home module context for custom type resolution
-- ffiModuleName is used as fallback for unknown opaque types (FFI-specific types)
parseTypeTokensWithHome :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> [String] -> Maybe Can.Type
parseTypeTokensWithHome env ffiModuleName homeModuleName tokens =
  case tokens of
    [] -> Nothing
    [typeName] -> Just (parseBasicTypeWithHome env ffiModuleName homeModuleName typeName)
    ["(", ")"] -> Just Can.TUnit
    _ -> case splitAtArrow tokens of
      Just (leftTokens, rightTokens) ->
        case (parseComplexTypeWithHome env ffiModuleName homeModuleName leftTokens, parseTypeTokensWithHome env ffiModuleName homeModuleName rightTokens) of
          (Just leftType, Just restType) -> Just (Can.TLambda leftType restType)
          _ -> Nothing
      Nothing -> parseComplexTypeWithHome env ffiModuleName homeModuleName tokens

-- Parse one complete type from the beginning of the token list
-- Returns (parsed type, remaining tokens)
-- ffiModuleName is used as fallback for unknown opaque types
parseOneType :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> [String] -> Maybe (Can.Type, [String])
parseOneType _env _ffiModuleName _homeModuleName [] = Nothing
parseOneType _env _ffiModuleName _homeModuleName ["(", ")"] = Just (Can.TUnit, [])
parseOneType env ffiModuleName homeModuleName ("Task" : rest) = do
  (errorType, rest1) <- parseOneType env ffiModuleName homeModuleName rest
  (resultType, rest2) <- parseOneType env ffiModuleName homeModuleName rest1
  let taskAlias = Can.TAlias
        ModuleName.task
        (Name.fromChars "Task")
        [(Name.fromChars "x", errorType), (Name.fromChars "a", resultType)]
        (Can.Filled (Can.TType ModuleName.platform (Name.fromChars "Task") [errorType, resultType]))
  return (taskAlias, rest2)
parseOneType env ffiModuleName homeModuleName ("Result" : rest) = do
  (errorType, rest1) <- parseOneType env ffiModuleName homeModuleName rest
  (valueType, rest2) <- parseOneType env ffiModuleName homeModuleName rest1
  let resultAlias = Can.TAlias
        ModuleName.result
        (Name.fromChars "Result")
        [(Name.fromChars "e", errorType), (Name.fromChars "a", valueType)]
        (Can.Filled (Can.TType ModuleName.result (Name.fromChars "Result") [errorType, valueType]))
  return (resultAlias, rest2)
parseOneType env ffiModuleName homeModuleName ("List" : rest) = do
  (elementType, rest1) <- parseOneType env ffiModuleName homeModuleName rest
  let listAlias = Can.TAlias
        ModuleName.list
        (Name.fromChars "List")
        [(Name.fromChars "a", elementType)]
        (Can.Filled (Can.TType ModuleName.list (Name.fromChars "List") [elementType]))
  return (listAlias, rest1)
parseOneType env ffiModuleName homeModuleName ("Maybe" : rest) = do
  (valueType, rest1) <- parseOneType env ffiModuleName homeModuleName rest
  let maybeAlias = Can.TAlias
        ModuleName.maybe
        (Name.fromChars "Maybe")
        [(Name.fromChars "a", valueType)]
        (Can.Filled (Can.TType ModuleName.maybe (Name.fromChars "Maybe") [valueType]))
  return (maybeAlias, rest1)
parseOneType env ffiModuleName homeModuleName ("Capability.Initialized" : rest) = do
  (paramType, rest1) <- parseOneType env ffiModuleName homeModuleName rest
  let capabilityModule = case homeModuleName of
        ModuleName.Canonical pkg _ -> ModuleName.Canonical pkg (Name.fromChars "Capability")
  return (Can.TType capabilityModule (Name.fromChars "Initialized") [paramType], rest1)
parseOneType env ffiModuleName homeModuleName ("Capability.Permitted" : rest) = do
  (paramType, rest1) <- parseOneType env ffiModuleName homeModuleName rest
  let capabilityModule = case homeModuleName of
        ModuleName.Canonical pkg _ -> ModuleName.Canonical pkg (Name.fromChars "Capability")
  return (Can.TType capabilityModule (Name.fromChars "Permitted") [paramType], rest1)
parseOneType env ffiModuleName homeModuleName ("Capability.Available" : rest) = do
  (paramType, rest1) <- parseOneType env ffiModuleName homeModuleName rest
  let capabilityModule = case homeModuleName of
        ModuleName.Canonical pkg _ -> ModuleName.Canonical pkg (Name.fromChars "Capability")
  return (Can.TType capabilityModule (Name.fromChars "Available") [paramType], rest1)
parseOneType env ffiModuleName homeModuleName ("(" : rest) = do
  let (tupleTokens, afterParen) = span (/= ")") rest
  case afterParen of
    (")" : remaining) -> do
      let elements = splitTupleTokens tupleTokens
      parsedElements <- mapM (parseOneType env ffiModuleName homeModuleName) elements
      let types = map fst parsedElements
      case types of
        [] -> Just (Can.TUnit, remaining)
        [single] -> Just (single, remaining)
        [first, second] -> Just (Can.TTuple first second Nothing, remaining)
        [first, second, third] -> Just (Can.TTuple first second (Just third), remaining)
        _ -> Nothing
    _ -> Nothing
  where
    splitTupleTokens :: [String] -> [[String]]
    splitTupleTokens toks =
      let go :: [String] -> Int -> [String] -> [[String]] -> [[String]]
          go [] _ acc result = if null acc then result else result ++ [reverse acc]
          go ("," : ts) 0 acc result = go ts 0 [] (result ++ [reverse acc])
          go ("(" : ts) depth acc result = go ts (depth + 1) ("(" : acc) result
          go (")" : ts) depth acc result = go ts (depth - 1) (")" : acc) result
          go (t : ts) depth acc result = go ts depth (t : acc) result
      in go toks (0 :: Int) [] []
parseOneType env ffiModuleName homeModuleName (t : rest) = Just (parseBasicTypeWithHome env ffiModuleName homeModuleName t, rest)

-- | Parse complex types with home module context.
--
-- Returns Nothing when the tokens cannot be parsed into a valid type,
-- allowing callers to report proper errors instead of silently degrading.
-- ffiModuleName is used as fallback for unknown opaque types
parseComplexTypeWithHome :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> [String] -> Maybe Can.Type
parseComplexTypeWithHome env ffiModuleName homeModuleName tokens =
  case parseOneType env ffiModuleName homeModuleName tokens of
    Just (tipe, _) -> Just tipe
    Nothing -> Nothing

-- Parse basic type names with home module context for custom types
-- Uses env to look up imported types and resolve them to their defining module
-- ffiModuleName is used as fallback for unknown opaque types (FFI-specific types)
parseBasicTypeWithHome :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> String -> Can.Type
parseBasicTypeWithHome env ffiModuleName homeModuleName typeName =
  let trimmedName = dropWhileEnd (== ' ') (dropWhile (== ' ') typeName)
      dropWhileEnd predicate xs = foldr (\x acc -> if predicate x && null acc then [] else x:acc) [] xs
      isTuple = isTupleString trimmedName
      unparenthesized = case trimmedName of
        "()" -> "()"
        ('(' : rest) | not (null rest) && last rest == ')' -> init rest
        other -> other
      isComplexType = ' ' `elem` unparenthesized && unparenthesized /= "()" && not isTuple
  in if isTuple
       then parseTupleString env ffiModuleName homeModuleName trimmedName
       else if isComplexType
         then maybe (Can.TType ffiModuleName (Name.fromChars trimmedName) [])
                id
                (parseComplexTypeWithHome env ffiModuleName homeModuleName (tokenizeTypeSegment (Text.pack unparenthesized)))
         else resolveBasicType env ffiModuleName homeModuleName trimmedName unparenthesized

-- Resolve a basic (non-complex, non-tuple) type by name
resolveBasicType :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> String -> String -> Can.Type
resolveBasicType env ffiModuleName homeModuleName trimmedName unparenthesized =
  case unparenthesized of
    "Int" -> Can.TType ModuleName.basics (Name.fromChars "Int") []
    "Float" -> Can.TType ModuleName.basics (Name.fromChars "Float") []
    "Bool" -> Can.TType ModuleName.basics (Name.fromChars "Bool") []
    "String" -> Can.TType ModuleName.string (Name.fromChars "String") []
    "()" -> Can.TUnit
    "Unit" -> Can.TUnit
    "Task" -> Can.TType ModuleName.task (Name.fromChars "Task") []
    "Result" -> Can.TType ModuleName.result (Name.fromChars "Result") []
    "List" -> Can.TType ModuleName.list (Name.fromChars "List") []
    "Maybe" -> Can.TType ModuleName.maybe (Name.fromChars "Maybe") []
    tupleStr | isTupleString tupleStr ->
      parseTupleString env ffiModuleName homeModuleName tupleStr
    [ch] | ch >= 'a' && ch <= 'z' ->
      Can.TType homeModuleName (Name.fromChars trimmedName) []
    qualifiedType | '.' `elem` qualifiedType ->
      resolveQualifiedType env ffiModuleName homeModuleName qualifiedType
    customType ->
      if customType == "String"
        then Can.TType ModuleName.string (Name.fromChars "String") []
        else resolveCustomType env ffiModuleName customType

-- Resolve a module-qualified type like "Capability.CapabilityError"
resolveQualifiedType :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> String -> Can.Type
resolveQualifiedType env ffiModuleName homeModuleName qualifiedType =
  let parts = splitOn '.' qualifiedType
      moduleParts = init parts
      typeNamePart = last parts
      moduleNameStr = intercalate "." moduleParts
      qualifierName = Name.fromChars moduleNameStr
      typeNameObj = Name.fromChars typeNamePart
      maybeQualifiedTypeInfo = do
        innerMap <- Map.lookup qualifierName (Env._q_types env)
        Map.lookup typeNameObj innerMap
      fallbackModule = case homeModuleName of
        ModuleName.Canonical pkg _ -> ModuleName.Canonical pkg qualifierName
  in case maybeQualifiedTypeInfo of
       Just info -> resolveTypeFromInfo fallbackModule typeNameObj (Just info)
       Nothing -> Can.TType fallbackModule typeNameObj []

-- Resolve a custom unqualified type using the environment
resolveCustomType :: Env.Env -> ModuleName.Canonical -> String -> Can.Type
resolveCustomType env ffiModuleName customType =
  let typeNameObj = Name.fromChars customType
      maybeTypeInfo = Map.lookup typeNameObj (Env._types env)
  in resolveTypeFromInfo ffiModuleName typeNameObj maybeTypeInfo

-- Resolve a type from its environment Info entry
resolveTypeFromInfo :: ModuleName.Canonical -> Name.Name -> Maybe (Env.Info Env.Type) -> Can.Type
resolveTypeFromInfo fallback tname Nothing =
  Can.TType fallback tname []
resolveTypeFromInfo _fallback tname (Just (Env.Specific _defMod (Env.Alias _arity home argNames aliasedType))) =
  Can.TAlias home tname (zip argNames []) (Can.Holey aliasedType)
resolveTypeFromInfo _fallback tname (Just (Env.Specific _defMod (Env.Union _arity home))) =
  Can.TType home tname []
resolveTypeFromInfo _fallback tname (Just (Env.Ambiguous defMod _)) =
  Can.TType defMod tname []

-- Helper: split a string on a delimiter character
splitOn :: Char -> String -> [String]
splitOn _ [] = []
splitOn delim str =
  let (first, rest) = break (== delim) str
  in first : case rest of
               [] -> []
               (_:xs) -> splitOn delim xs

-- Check if a type string represents a tuple
isTupleString :: String -> Bool
isTupleString str =
  let trimmed = dropWhile (== ' ') str
  in case trimmed of
       ('(' : rest) ->
         let inner = takeWhile (/= ')') rest
         in ',' `elem` inner
       _ -> False

-- Parse a tuple string like "(Float, Float)" into a Can.TTuple
-- For 4+ element tuples, constructs nested pairs: (a,b,c,d) -> ((a,b),(c,d))
-- ffiModuleName is used as fallback for unknown opaque types
parseTupleString :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> String -> Can.Type
parseTupleString env ffiModuleName homeModuleName str =
  let trimmed = dropWhile (== ' ') str
      withoutParens = case trimmed of
                        ('(' : rest) -> takeWhile (/= ')') rest
                        other -> other
      elements = splitByComma withoutParens
      parsedElements = map (parseBasicTypeWithHome env ffiModuleName homeModuleName . trim) elements
  in buildTupleType parsedElements
  where
    trim = dropWhile (== ' ') . reverse . dropWhile (== ' ') . reverse
    splitByComma s = go [] [] s
      where
        go acc current [] = reverse (reverse current : acc)
        go acc current (',' : cs) = go (reverse current : acc) [] cs
        go acc current (c : cs) = go acc (c : current) cs

-- Build tuple type, handling 4+ elements with nested pairs
buildTupleType :: [Can.Type] -> Can.Type
buildTupleType [] = Can.TUnit
buildTupleType [single] = single
buildTupleType [first, second] = Can.TTuple first second Nothing
buildTupleType [first, second, third] = Can.TTuple first second (Just third)
buildTupleType types =
  let midpoint = length types `div` 2
      (leftTypes, rightTypes) = splitAt midpoint types
      leftTuple = buildTupleType leftTypes
      rightTuple = buildTupleType rightTypes
  in Can.TTuple leftTuple rightTuple Nothing

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
    extractCapabilityWarnings,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Environment as Env
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import Data.List (isPrefixOf, isInfixOf)
import Data.Maybe (mapMaybe)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.List as List
import qualified Data.Text as Text
import qualified FFI.TypeParser as TypeParser
import FFI.Types (JsSourcePath (..), JsSource (..), FFIBinding (..), FFIFuncName (..), FFITypeAnnotation (..))
import qualified Foreign.FFI as FFI
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning
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
loadFFIContent :: [Src.ForeignImport] -> IO (Map JsSourcePath JsSource)
loadFFIContent = loadFFIContentWithRoot "."

-- | Load FFI content with explicit root directory for path resolution.
--
-- Validates paths before reading to prevent path traversal attacks.
-- Returns errors for invalid paths or unreadable files so callers
-- get clear diagnostics instead of silent empty maps.
loadFFIContentWithRoot :: FilePath -> [Src.ForeignImport] -> IO (Map JsSourcePath JsSource)
loadFFIContentWithRoot rootDir foreignImports = do
  results <- traverse (loadSingleFFI rootDir) foreignImports
  return (Map.fromList (concat results))

-- | Load a single FFI file, returning empty list on validation or IO failure.
--
-- Path validation errors and file read errors are logged but do not
-- abort compilation — the missing content will be caught later by
-- 'addFFIToEnvPure' which produces a structured 'FFIFileNotFound' error.
loadSingleFFI :: FilePath -> Src.ForeignImport -> IO [(JsSourcePath, JsSource)]
loadSingleFFI rootDir (Src.ForeignImport (FFI.JavaScriptFFI jsPath) _alias _region) =
  case validateFFIPath jsPath of
    Left _reason -> return []
    Right validPath -> do
      result <- loadFFIFile (rootDir </> validPath)
      either (const (return [])) (\content -> return [(JsSourcePath validPath, JsSource content)]) result
loadSingleFFI _ _ = return []

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

-- | Load an FFI JavaScript file, catching only IO exceptions.
--
-- Returns a descriptive error message preserving the real IO error
-- (e.g. permission denied, encoding error) instead of a generic
-- "File not found" for all failures.
loadFFIFile :: FilePath -> IO (Either String String)
loadFFIFile fullPath =
  (Right <$> readFile fullPath) `Exception.catch` handleIOError
  where
    handleIOError :: IOException -> IO (Either String String)
    handleIOError err = return (Left (show err))

-- | Add FFI functions to environment using pre-loaded content (pure).
--
-- Processes all FFI imports sequentially, threading the updated
-- environment through each import so all foreign functions are available.
addFFIToEnvPure :: Env.Env -> [Src.ForeignImport] -> Map JsSourcePath JsSource -> Result i [Warning.Warning] Env.Env
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
processFFIImport :: Env.Env -> FilePath -> Ann.Located Name.Name -> Ann.Region -> Map JsSourcePath JsSource -> Result i [Warning.Warning] Env.Env
processFFIImport env jsPath alias region ffiContentMap =
  let aliasName = Ann.toValue alias
      home = Env._home env
      ffiModuleName = ModuleName.Canonical (ModuleName._package home) aliasName
  in case Map.lookup (JsSourcePath jsPath) ffiContentMap of
       Nothing -> Result.throw (Error.FFIFileNotFound region jsPath)
       Just (JsSource jsContent) -> parseAndAddFFI env ffiModuleName aliasName jsPath region jsContent

-- Parse FFI content and add to environment with validation
parseAndAddFFI :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> Ann.Region -> String -> Result i [Warning.Warning] Env.Env
parseAndAddFFI env ffiModuleName aliasName jsPath region jsContent =
  case parseJavaScriptContentPure jsContent (Name.toChars aliasName) of
    Left err -> Result.throw (Error.FFIParseError region jsPath err)
    Right bindings -> validateAndAddFunctions env ffiModuleName aliasName jsPath region bindings

-- Validate and add FFI functions to environment
validateAndAddFunctions :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> Ann.Region -> [FFIBinding] -> Result i [Warning.Warning] Env.Env
validateAndAddFunctions env ffiModuleName aliasName jsPath region bindings =
  case validateFFIFunctions jsPath region bindings of
    Left err -> Result.throw err
    Right validBindings -> addParsedFunctionsToEnv env ffiModuleName aliasName jsPath region validBindings

-- Validate FFI functions have proper type annotations
validateFFIFunctions :: FilePath -> Ann.Region -> [FFIBinding] -> Either Error.Error [FFIBinding]
validateFFIFunctions jsPath region =
  traverse (validateSingleFunction jsPath region)

-- Validate single FFI function signature
validateSingleFunction :: FilePath -> Ann.Region -> FFIBinding -> Either Error.Error FFIBinding
validateSingleFunction jsPath region binding =
  if null (unFFITypeAnnotation (_bindingTypeAnnotation binding))
    then Left (Error.FFIMissingAnnotation region jsPath (Name.fromChars (unFFIFuncName (_bindingFuncName binding))))
    else Right binding

-- | Parse JavaScript content purely without IO operations
--
-- This replaces the problematic parseJavaScriptFile function that used
-- unsafePerformIO for file reading.
--
-- @since 0.19.1
parseJavaScriptContentPure :: String -> String -> Either String [FFIBinding]
parseJavaScriptContentPure jsContent _alias =
  Right (extractFunctionsWithTypes (lines jsContent))

-- Extract functions with their @canopy-type annotations
-- Now properly handles JSDoc comments with @name and @canopy-type annotations
extractFunctionsWithTypes :: [String] -> [FFIBinding]
extractFunctionsWithTypes [] = []
extractFunctionsWithTypes inputLines = extractFromJSDocBlocks inputLines

-- Extract functions from JSDoc comment blocks
extractFromJSDocBlocks :: [String] -> [FFIBinding]
extractFromJSDocBlocks [] = []
extractFromJSDocBlocks (line:rest)
  | isJSDocStart line =
      let (commentBlock, remaining) = takeJSDocBlock (line:rest)
          mbBinding = parseJSDocBlock commentBlock
      in case mbBinding of
           Just binding -> binding : extractFromJSDocBlocks remaining
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
parseJSDocBlock :: [String] -> Maybe FFIBinding
parseJSDocBlock commentLines = do
  functionName <- findNameAnnotation commentLines
  canopyType <- findCanopyTypeAnnotation commentLines
  pure (FFIBinding (FFIFuncName functionName) (FFITypeAnnotation canopyType))

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
addParsedFunctionsToEnv :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> Ann.Region -> [FFIBinding] -> Result i [Warning.Warning] Env.Env
addParsedFunctionsToEnv env ffiModuleName aliasName jsPath region bindings = do
  let homeModuleName = Env._home env
  processedFunctions <- traverse (processParsedFunction env ffiModuleName homeModuleName jsPath region) bindings
  let (vars, qVars) = buildDynamicEnvironment aliasName processedFunctions
      newVars = List.foldl' (\acc (name, var) -> Map.insert name var acc) (Env._vars env) vars
      newQVars = Map.insertWith Map.union aliasName qVars (Env._q_vars env)
      newEnv = env { Env._vars = newVars, Env._q_vars = newQVars }
  Result.ok newEnv

-- Process a single parsed FFI binding into Canopy types
processParsedFunction :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> FilePath -> Ann.Region -> FFIBinding -> Result i [Warning.Warning] (String, Can.Annotation, Env.Var)
processParsedFunction env ffiModuleName homeModuleName jsPath region binding = do
  let funcName = _bindingFuncName binding
      typeAnnotation = _bindingTypeAnnotation binding
  canopyType <- parseTypeStringWithHome env ffiModuleName homeModuleName jsPath region funcName typeAnnotation
  let annotation = Can.Forall Map.empty canopyType
      var = Env.Foreign ffiModuleName annotation
  Result.ok (unFFIFuncName funcName, annotation, var)

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

-- | Parse type string with home module context for custom type resolution.
--
-- Uses the unified 'FFI.TypeParser' to parse the type string into
-- 'FFIType', then converts to 'Can.Type' using environment-aware
-- resolution. Emits warnings for opaque types that cannot be found
-- in the environment.
parseTypeStringWithHome :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> FilePath -> Ann.Region -> FFIFuncName -> FFITypeAnnotation -> Result i [Warning.Warning] Can.Type
parseTypeStringWithHome env ffiModuleName homeModuleName jsPath region funcName typeAnnotation =
  case TypeParser.parseType (Text.pack (unFFITypeAnnotation typeAnnotation)) of
    Just ffiType ->
      let canType = ffiTypeToCanonical env ffiModuleName homeModuleName ffiType
          unresolvedNames = collectUnresolved env ffiType
       in warnUnresolved jsPath funcName unresolvedNames
            >> Result.ok canType
    Nothing ->
      Result.throw (Error.FFIInvalidType region jsPath (Name.fromChars (unFFIFuncName funcName)) ("Failed to parse type: " ++ unFFITypeAnnotation typeAnnotation))

-- | Emit warnings for each unresolved opaque type name.
warnUnresolved :: FilePath -> FFIFuncName -> [Text.Text] -> Result i [Warning.Warning] ()
warnUnresolved _ _ [] = Result.ok ()
warnUnresolved jsPath funcName (name : rest) = do
  Result.warn (Warning.FFIUnresolvedType (Text.pack jsPath) (Text.pack (unFFIFuncName funcName)) name)
  warnUnresolved jsPath funcName rest

-- | Collect opaque type names that cannot be resolved in the environment.
collectUnresolved :: Env.Env -> FFI.FFIType -> [Text.Text]
collectUnresolved env = go
  where
    go ffiType = case ffiType of
      FFI.FFIInt -> []
      FFI.FFIFloat -> []
      FFI.FFIString -> []
      FFI.FFIBool -> []
      FFI.FFIUnit -> []
      FFI.FFIList inner -> go inner
      FFI.FFIMaybe inner -> go inner
      FFI.FFIResult e v -> go e ++ go v
      FFI.FFITask e v -> go e ++ go v
      FFI.FFIFunctionType params ret -> concatMap go params ++ go ret
      FFI.FFITuple types -> concatMap go types
      FFI.FFIRecord fields -> concatMap (go . snd) fields
      FFI.FFIOpaque name -> checkOpaque (Text.unpack name)

    checkOpaque name
      -- Single lowercase letter = type variable, always OK
      | [ch] <- name, ch >= 'a' && ch <= 'z' = []
      -- Qualified name: check in qualified types map
      | '.' `elem` name = checkQualified name
      -- Unqualified name: check in types map
      | otherwise = checkUnqualified name

    checkQualified qualifiedName =
      case splitInitLast (splitOnDot qualifiedName) of
        Nothing -> [Text.pack qualifiedName]
        Just (moduleParts, typeNamePart) ->
          let qualifierName = Name.fromChars (concatWithDots moduleParts)
              typeNameObj = Name.fromChars typeNamePart
              found = maybe False (Map.member typeNameObj) (Map.lookup qualifierName (Env._q_types env))
           in [Text.pack qualifiedName | not found]

    checkUnqualified customType =
      let typeNameObj = Name.fromChars customType
       in [Text.pack customType | not (Map.member typeNameObj (Env._types env))]

-- FFI TYPE TO CANONICAL CONVERSION

-- | Convert an 'FFIType' to a canonical 'Can.Type'.
--
-- Uses the environment to resolve custom type names to their
-- defining modules. Built-in types (Int, String, etc.) are mapped
-- to their well-known canonical module names.
ffiTypeToCanonical :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> FFI.FFIType -> Can.Type
ffiTypeToCanonical env ffiMod homeMod ffiType = case ffiType of
  FFI.FFIInt -> Can.TType ModuleName.basics (Name.fromChars "Int") []
  FFI.FFIFloat -> Can.TType ModuleName.basics (Name.fromChars "Float") []
  FFI.FFIString -> Can.TType ModuleName.string (Name.fromChars "String") []
  FFI.FFIBool -> Can.TType ModuleName.basics (Name.fromChars "Bool") []
  FFI.FFIUnit -> Can.TUnit

  FFI.FFIList inner ->
    makeAlias ModuleName.list "List" [("a", inner)]

  FFI.FFIMaybe inner ->
    makeAlias ModuleName.maybe "Maybe" [("a", inner)]

  FFI.FFIResult errTy valTy ->
    makeAlias ModuleName.result "Result" [("e", errTy), ("a", valTy)]

  FFI.FFITask errTy valTy ->
    makeTaskAlias errTy valTy

  FFI.FFIFunctionType params retTy ->
    foldr (\p acc -> Can.TLambda (recur p) acc) (recur retTy) params

  FFI.FFITuple types ->
    convertTuple (map recur types)

  FFI.FFIOpaque name ->
    resolveOpaqueName env ffiMod homeMod (Text.unpack name)

  FFI.FFIRecord fields ->
    Can.TRecord (Map.fromList (map convertField fields)) Nothing
  where
    recur = ffiTypeToCanonical env ffiMod homeMod

    makeAlias modName typeName argPairs =
      let canArgs = map (\(n, t) -> (Name.fromChars n, recur t)) argPairs
          innerTypes = map snd canArgs
       in Can.TAlias
            modName
            (Name.fromChars typeName)
            canArgs
            (Can.Filled (Can.TType modName (Name.fromChars typeName) innerTypes))

    makeTaskAlias errTy valTy =
      let canErr = recur errTy
          canVal = recur valTy
       in Can.TAlias
            ModuleName.task
            (Name.fromChars "Task")
            [(Name.fromChars "x", canErr), (Name.fromChars "a", canVal)]
            (Can.Filled (Can.TType ModuleName.platform (Name.fromChars "Task") [canErr, canVal]))

    convertField (name, ffiTy) =
      (Name.fromChars (Text.unpack name), Can.FieldType 0 (recur ffiTy))

-- | Convert tuple types, handling Canopy's 2/3-element tuple limit.
convertTuple :: [Can.Type] -> Can.Type
convertTuple [] = Can.TUnit
convertTuple [single] = single
convertTuple [a, b] = Can.TTuple a b Nothing
convertTuple [a, b, c] = Can.TTuple a b (Just c)
convertTuple types =
  let mid = length types `div` 2
      (left, right) = splitAt mid types
   in Can.TTuple (convertTuple left) (convertTuple right) Nothing

-- | Resolve an opaque type name using the environment.
resolveOpaqueName :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> String -> Can.Type
resolveOpaqueName env ffiMod homeMod name = case name of
  [ch] | ch >= 'a' && ch <= 'z' ->
    Can.TType homeMod (Name.fromChars name) []
  _ | '.' `elem` name ->
    resolveQualifiedName env homeMod name
  _ -> resolveUnqualifiedName env ffiMod name

-- | Resolve a qualified type name like "Capability.CapabilityError".
resolveQualifiedName :: Env.Env -> ModuleName.Canonical -> String -> Can.Type
resolveQualifiedName env homeMod qualifiedName =
  case splitInitLast (splitOnDot qualifiedName) of
    Nothing -> Can.TType homeMod (Name.fromChars qualifiedName) []
    Just (moduleParts, typeNamePart) ->
      let qualifierName = Name.fromChars (concatWithDots moduleParts)
          typeNameObj = Name.fromChars typeNamePart
          maybeInfo = do
            innerMap <- Map.lookup qualifierName (Env._q_types env)
            Map.lookup typeNameObj innerMap
          fallbackModule = case homeMod of
            ModuleName.Canonical pkg _ -> ModuleName.Canonical pkg qualifierName
       in resolveTypeFromInfo fallbackModule typeNameObj maybeInfo

-- | Resolve an unqualified custom type using the environment.
resolveUnqualifiedName :: Env.Env -> ModuleName.Canonical -> String -> Can.Type
resolveUnqualifiedName env ffiMod customType =
  let typeNameObj = Name.fromChars customType
      maybeInfo = Map.lookup typeNameObj (Env._types env)
   in resolveTypeFromInfo ffiMod typeNameObj maybeInfo

-- | Resolve a type from its environment Info entry.
resolveTypeFromInfo :: ModuleName.Canonical -> Name.Name -> Maybe (Env.Info Env.Type) -> Can.Type
resolveTypeFromInfo fallback tname Nothing =
  Can.TType fallback tname []
resolveTypeFromInfo _fallback tname (Just (Env.Specific _defMod (Env.Alias _arity home argNames aliasedType))) =
  Can.TAlias home tname (zip argNames []) (Can.Holey aliasedType)
resolveTypeFromInfo _fallback tname (Just (Env.Specific _defMod (Env.Union _arity home))) =
  Can.TType home tname []
resolveTypeFromInfo _fallback tname (Just (Env.Ambiguous defMod _)) =
  Can.TType defMod tname []

-- | Split a string on dots.
splitOnDot :: String -> [String]
splitOnDot [] = []
splitOnDot str =
  let (first, rest) = break (== '.') str
   in first : case rest of
        [] -> []
        (_ : xs) -> splitOnDot xs

-- | Safely split a list into init and last, returning Nothing for empty lists.
splitInitLast :: [a] -> Maybe ([a], a)
splitInitLast [] = Nothing
splitInitLast [x] = Just ([], x)
splitInitLast (x : xs) =
  fmap (\(rest, final) -> (x : rest, final)) (splitInitLast xs)

-- | Join strings with dots.
concatWithDots :: [String] -> String
concatWithDots [] = ""
concatWithDots [x] = x
concatWithDots (x : xs) = x ++ "." ++ concatWithDots xs

-- CAPABILITY WARNING EXTRACTION

-- | Extract capability warnings from pre-loaded FFI content.
--
-- Scans each FFI file's JSDoc blocks for @capability annotations and
-- produces a 'Warning.CapabilityNotice' for each function that declares
-- required capabilities. This gives users compile-time feedback about
-- which browser permissions or resources their FFI imports require.
--
-- @since 0.19.2
extractCapabilityWarnings :: Name.Name -> Map JsSourcePath JsSource -> [Warning.Warning]
extractCapabilityWarnings aliasName ffiContentMap =
  concatMap (extractFromFile moduleName) (Map.toList ffiContentMap)
  where
    moduleName = Text.pack (Name.toChars aliasName)

-- | Extract capability warnings from a single FFI file.
extractFromFile :: Text.Text -> (JsSourcePath, JsSource) -> [Warning.Warning]
extractFromFile moduleName (_, JsSource content) =
  concatMap (blockToWarning moduleName) (parseCapabilityBlocks (lines content))

-- | Parse JSDoc blocks that contain both @name and @capability annotations.
parseCapabilityBlocks :: [String] -> [(String, [String])]
parseCapabilityBlocks [] = []
parseCapabilityBlocks (line:rest)
  | isJSDocStart line =
      let (commentBlock, remaining) = takeJSDocBlock (line:rest)
      in case parseCapabilityBlock commentBlock of
           Just cap -> cap : parseCapabilityBlocks remaining
           Nothing -> parseCapabilityBlocks remaining
  | otherwise = parseCapabilityBlocks rest

-- | Parse a JSDoc block for function name and capability annotations.
parseCapabilityBlock :: [String] -> Maybe (String, [String])
parseCapabilityBlock commentLines = do
  functionName <- findNameAnnotation commentLines
  let capabilities = findAllCapabilities commentLines
  if null capabilities then Nothing else Just (functionName, capabilities)

-- | Find all @capability annotations in a JSDoc block.
findAllCapabilities :: [String] -> [String]
findAllCapabilities = mapMaybe parseCapabilityAnnotation

-- | Parse a @capability annotation from a single line.
parseCapabilityAnnotation :: String -> Maybe String
parseCapabilityAnnotation line =
  let trimmed = dropWhile (`elem` (" *" :: String)) line
  in if ("@capability " :: String) `isPrefixOf` trimmed
     then Just (strip (drop (length ("@capability " :: String)) trimmed))
     else Nothing

-- | Convert a parsed capability block into a warning.
blockToWarning :: Text.Text -> (String, [String]) -> [Warning.Warning]
blockToWarning moduleName (funcName, capabilities) =
  [Warning.CapabilityNotice moduleName (Text.pack funcName) (map Text.pack capabilities)]

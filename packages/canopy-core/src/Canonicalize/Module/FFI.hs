{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE LambdaCase #-}
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
import qualified Canopy.PathValidation as PathValidation
import qualified Data.Char as Char
import Control.Exception (IOException)
import qualified Control.Exception as Exception
import Data.Maybe (mapMaybe)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified FFI.StaticAnalysis as SA
import qualified FFI.TypeParser as TypeParser
import FFI.Types (JsSourcePath (..), JsSource (..), FFIBinding (..), FFIFuncName (..), FFITypeAnnotation (..), CapabilityName (..), BindingMode (..))
import qualified Foreign.FFI as FFI
import qualified Language.JavaScript.Parser as JSParser
import qualified Language.JavaScript.Parser.AST as JSAST
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
      either (const (return [])) (\content -> return [(JsSourcePath (Text.pack validPath), JsSource content)]) result
loadSingleFFI _ _ = return []

-- | Validate an FFI source file path for safety.
--
-- Delegates generic filesystem checks (absolute path, traversal,
-- null bytes) to 'PathValidation.validatePath', then applies the
-- FFI-specific constraint that the file must be a JavaScript file.
--
-- @since 0.19.2
validateFFIPath :: FilePath -> Either String FilePath
validateFFIPath path =
  either pathErrorToString checkExtension (PathValidation.validatePath path)

-- | Convert a generic 'PathValidation.PathError' to a user-facing message.
pathErrorToString :: PathValidation.PathError -> Either String a
pathErrorToString (PathValidation.PathAbsolute _) =
  Left "FFI source path must be relative"
pathErrorToString (PathValidation.PathTraversal _) =
  Left "FFI source path cannot contain '..'"
pathErrorToString (PathValidation.PathNullByte _) =
  Left "FFI source path contains null byte"

-- | Verify the file has a JavaScript extension.
checkExtension :: FilePath -> Either String FilePath
checkExtension path
  | FP.takeExtension path `elem` [".js", ".mjs"] = Right path
  | otherwise = Left "FFI source path must end in .js or .mjs"

-- | Load an FFI JavaScript file, catching only IO exceptions.
--
-- Returns a descriptive error message preserving the real IO error
-- (e.g. permission denied, encoding error) instead of a generic
-- "File not found" for all failures.
loadFFIFile :: FilePath -> IO (Either String Text.Text)
loadFFIFile fullPath =
  (Right <$> TextIO.readFile fullPath) `Exception.catch` handleIOError
  where
    handleIOError :: IOException -> IO (Either String Text.Text)
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
  in case Map.lookup (JsSourcePath (Text.pack jsPath)) ffiContentMap of
       Nothing -> Result.throw (Error.FFIFileNotFound region jsPath)
       Just (JsSource jsContent) -> parseAndAddFFI env ffiModuleName aliasName jsPath region jsContent

-- Parse FFI content and add to environment with validation
parseAndAddFFI :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> Ann.Region -> Text.Text -> Result i [Warning.Warning] Env.Env
parseAndAddFFI env ffiModuleName aliasName jsPath region jsContent =
  case parseJavaScriptContentPure jsContent (Name.toChars aliasName) of
    Left err -> Result.throw (Error.FFIParseError region jsPath err)
    Right bindings -> do
      emitStaticAnalysisWarnings jsPath jsContent bindings
      validateAndAddFunctions env ffiModuleName aliasName jsPath region bindings

-- | Run static analysis on the JavaScript source and emit warnings.
--
-- Parses the JavaScript with @language-javascript@ to get the AST, then
-- runs 'SA.analyzeFFIFile' against the declared type annotations. Each
-- warning is emitted through the 'Result' monad so it reaches the user
-- without blocking compilation.
--
-- @since 0.20.0
emitStaticAnalysisWarnings :: FilePath -> Text.Text -> [FFIBinding] -> Result i [Warning.Warning] ()
emitStaticAnalysisWarnings jsPath jsContent bindings =
  case JSParser.parseModule (Text.unpack jsContent) jsPath of
    Left _ -> Result.ok ()
    Right ast ->
      let stmts = extractStatements ast
          declaredTypes = buildDeclaredTypeMap bindings
          analysis = SA.analyzeFFIFile stmts declaredTypes
          pathText = Text.pack jsPath
       in traverse_ (emitOneWarning pathText) (SA._analysisWarnings analysis)

-- | Extract top-level statements from a parsed JavaScript AST.
extractStatements :: JSAST.JSAST -> [JSAST.JSStatement]
extractStatements (JSAST.JSAstProgram stmts _) = stmts
extractStatements (JSAST.JSAstModule items _) =
  [stmt | JSAST.JSModuleStatementListItem stmt <- items]
extractStatements (JSAST.JSAstStatement stmt _) = [stmt]
extractStatements _ = []

-- | Build a map of declared FFI types from parsed bindings.
buildDeclaredTypeMap :: [FFIBinding] -> Map.Map Text.Text FFI.FFIType
buildDeclaredTypeMap = Map.fromList . concatMap bindingToType
  where
    bindingToType binding =
      case TypeParser.parseType (unFFITypeAnnotation (_bindingTypeAnnotation binding)) of
        Just ffiType -> [(unFFIFuncName (_bindingFuncName binding), ffiType)]
        Nothing -> []

-- | Emit a single static analysis warning through the Result monad.
emitOneWarning :: Text.Text -> SA.FFIWarning -> Result i [Warning.Warning] ()
emitOneWarning path warning = Result.warn (Warning.FFIStaticAnalysis path warning)

-- | Traverse a list, executing an action for each element and discarding results.
traverse_ :: (a -> Result i [Warning.Warning] ()) -> [a] -> Result i [Warning.Warning] ()
traverse_ _ [] = Result.ok ()
traverse_ f (x : xs) = f x >> traverse_ f xs

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
  if Text.null (unFFITypeAnnotation (_bindingTypeAnnotation binding))
    then Left (Error.FFIMissingAnnotation region jsPath (Name.fromChars (Text.unpack (unFFIFuncName (_bindingFuncName binding)))))
    else Right binding

-- | Parse JavaScript content purely without IO operations
--
-- This replaces the problematic parseJavaScriptFile function that used
-- unsafePerformIO for file reading.
--
-- @since 0.19.1
parseJavaScriptContentPure :: Text.Text -> String -> Either String [FFIBinding]
parseJavaScriptContentPure jsContent _alias =
  Right (extractFunctionsWithTypes (Text.lines jsContent))

-- Extract functions with their @canopy-type annotations
-- Now properly handles JSDoc comments with @name and @canopy-type annotations
extractFunctionsWithTypes :: [Text.Text] -> [FFIBinding]
extractFunctionsWithTypes [] = []
extractFunctionsWithTypes inputLines = extractFromJSDocBlocks inputLines

-- Extract functions from JSDoc comment blocks
extractFromJSDocBlocks :: [Text.Text] -> [FFIBinding]
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
isJSDocStart :: Text.Text -> Bool
isJSDocStart line =
  Text.isPrefixOf "/**" (Text.stripStart line)

-- Take a complete JSDoc comment block
takeJSDocBlock :: [Text.Text] -> ([Text.Text], [Text.Text])
takeJSDocBlock [] = ([], [])
takeJSDocBlock (line:rest) =
  if isJSDocEnd line
    then ([line], rest)
    else let (block, remaining) = takeJSDocBlock rest
         in (line:block, remaining)

-- Check if line ends a JSDoc comment
isJSDocEnd :: Text.Text -> Bool
isJSDocEnd line = Text.isInfixOf "*/" line

-- Parse a JSDoc comment block to extract function name, type, capabilities, bind mode, and canopy name
parseJSDocBlock :: [Text.Text] -> Maybe FFIBinding
parseJSDocBlock commentLines = do
  functionName <- findNameAnnotation commentLines
  canopyType <- findCanopyTypeAnnotation commentLines
  let capabilities = findCapabilityPermissions commentLines
      bindMode = findBindingMode commentLines
      canopyName = findCanopyName commentLines
  pure (FFIBinding (FFIFuncName functionName) (FFITypeAnnotation canopyType) capabilities bindMode canopyName)

-- | Find all @capability permission annotations in a JSDoc block.
--
-- Extracts permission names from lines like:
-- @\@capability permission microphone@
findCapabilityPermissions :: [Text.Text] -> [CapabilityName]
findCapabilityPermissions = mapMaybe parsePermissionAnnotation

-- | Parse a @capability permission annotation from a single line.
parsePermissionAnnotation :: Text.Text -> Maybe CapabilityName
parsePermissionAnnotation line =
  case Text.stripPrefix "@capability permission " (stripJSDocLeader line) of
    Just rest -> Just (CapabilityName (Text.strip rest))
    Nothing -> Nothing

-- | Find @canopy-bind annotation in a JSDoc block.
--
-- Parses lines like:
-- @\@canopy-bind method addEventListener@
-- @\@canopy-bind get currentTime@
-- @\@canopy-bind set volume@
-- @\@canopy-bind new AudioContext@
findBindingMode :: [Text.Text] -> BindingMode
findBindingMode [] = FunctionCall
findBindingMode (line:rest) =
  case parseBindingModeAnnotation line of
    Just mode -> mode
    Nothing -> findBindingMode rest

-- | Parse a @canopy-bind annotation from a single line.
parseBindingModeAnnotation :: Text.Text -> Maybe BindingMode
parseBindingModeAnnotation line =
  case Text.stripPrefix "@canopy-bind " (stripJSDocLeader line) of
    Just rest -> parseBindMode (Text.words (Text.strip rest))
    Nothing -> Nothing

-- | Parse binding mode from the words after @canopy-bind.
parseBindMode :: [Text.Text] -> Maybe BindingMode
parseBindMode ["method", name] = Just (MethodCall name)
parseBindMode ["get", name] = Just (PropertyGet name)
parseBindMode ["set", name] = Just (PropertySet name)
parseBindMode ["new", name] = Just (ConstructorCall name)
parseBindMode _ = Nothing

-- | Find @canopy-name annotation in a JSDoc block.
--
-- Parses lines like: @\@canopy-name setOscillatorFrequency@
findCanopyName :: [Text.Text] -> Maybe Text.Text
findCanopyName [] = Nothing
findCanopyName (line:rest) =
  case parseCanopyNameAnnotation line of
    Just name -> Just name
    Nothing -> findCanopyName rest

-- | Parse a @canopy-name annotation from a single line.
parseCanopyNameAnnotation :: Text.Text -> Maybe Text.Text
parseCanopyNameAnnotation line =
  case Text.stripPrefix "@canopy-name " (stripJSDocLeader line) of
    Just rest -> validateCanopyName (Text.strip rest)
    Nothing -> Nothing

-- | Validate a Canopy name is a valid identifier.
validateCanopyName :: Text.Text -> Maybe Text.Text
validateCanopyName t
  | Text.null t = Nothing
  | validFirst (Text.head t) && Text.all validRest (Text.tail t) = Just t
  | otherwise = Nothing
  where
    validFirst c = Char.isLower c || c == '_'
    validRest c = Char.isAlphaNum c || c == '_'

-- Find @name annotation in JSDoc block
findNameAnnotation :: [Text.Text] -> Maybe Text.Text
findNameAnnotation [] = Nothing
findNameAnnotation (line:rest) =
  case parseNameAnnotation line of
    Just name -> Just name
    Nothing -> findNameAnnotation rest

-- Find @canopy-type annotation in JSDoc block
findCanopyTypeAnnotation :: [Text.Text] -> Maybe Text.Text
findCanopyTypeAnnotation [] = Nothing
findCanopyTypeAnnotation (line:rest) =
  case parseCanopyTypeAnnotation line of
    Just typeStr -> Just typeStr
    Nothing -> findCanopyTypeAnnotation rest

-- | Parse @name annotation from a line.
--
-- Rejects names that contain characters unsafe for JavaScript
-- identifiers (e.g., @;@, @}@, @\"@, @'@, newlines). Only
-- alphanumeric characters, underscores, and dollar signs are
-- allowed, preventing injection via crafted annotations.
--
-- @since 0.19.2
parseNameAnnotation :: Text.Text -> Maybe Text.Text
parseNameAnnotation line =
  case Text.stripPrefix "@name " (stripJSDocLeader line) of
    Just rest -> validateJsName (Text.strip rest)
    Nothing -> Nothing
  where
    validateJsName t
      | Text.null t = Nothing
      | validFirst (Text.head t) && Text.all validRest (Text.tail t) = Just t
      | otherwise = Nothing
    validFirst c = Char.isAlpha c || c == '_' || c == '$'
    validRest c = Char.isAlphaNum c || c == '_' || c == '$'

-- | Strip leading whitespace and JSDoc asterisks from a line.
stripJSDocLeader :: Text.Text -> Text.Text
stripJSDocLeader = Text.dropWhile (\c -> c == ' ' || c == '*')

-- Parse @canopy-type annotation from a line
parseCanopyTypeAnnotation :: Text.Text -> Maybe Text.Text
parseCanopyTypeAnnotation line =
  Text.stripPrefix "@canopy-type " (stripJSDocLeader line)

-- DYNAMIC FUNCTION ENVIRONMENT GENERATION

-- | Add FFI functions to the environment with auto opaque type inference.
--
-- Two-pass approach:
-- 1. Collect unresolved opaque types from all bindings and inject them
-- 2. Process functions against the enriched environment
addParsedFunctionsToEnv :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> Ann.Region -> [FFIBinding] -> Result i [Warning.Warning] Env.Env
addParsedFunctionsToEnv env ffiModuleName aliasName jsPath region bindings = do
  let envWithOpaques = injectAutoOpaqueTypes env ffiModuleName bindings
      homeModuleName = Env._home envWithOpaques
  processedFunctions <- traverse (processParsedFunction envWithOpaques ffiModuleName homeModuleName jsPath region) bindings
  let (vars, qVars) = buildDynamicEnvironment aliasName processedFunctions
      newVars = List.foldl' (\acc (name, var) -> Map.insert name var acc) (Env._vars envWithOpaques) vars
      newQVars = Map.insertWith Map.union aliasName qVars (Env._q_vars envWithOpaques)
      newEnv = envWithOpaques { Env._vars = newVars, Env._q_vars = newQVars }
  Result.ok newEnv

-- | Inject auto opaque type definitions for unresolved types in FFI annotations.
--
-- Collects all type names from @canopy-type annotations, filters out
-- those already defined in the environment (or built-in), and creates
-- opaque type entries (Union 0) for the remaining ones.
injectAutoOpaqueTypes :: Env.Env -> ModuleName.Canonical -> [FFIBinding] -> Env.Env
injectAutoOpaqueTypes env ffiModuleName bindings =
  let opaqueNames = collectOpaqueTypeNames bindings
      unresolvedNames = filter (isUnresolvedType env) opaqueNames
      newTypeEntries = List.map (makeOpaqueEntry ffiModuleName) unresolvedNames
      updatedTypes = List.foldl' insertType (Env._types env) newTypeEntries
   in env { Env._types = updatedTypes }

-- | Collect all opaque type names from FFI binding annotations.
collectOpaqueTypeNames :: [FFIBinding] -> [Text.Text]
collectOpaqueTypeNames = List.nub . concatMap extractOpaqueNames

-- | Extract opaque type names from a single binding's type annotation.
extractOpaqueNames :: FFIBinding -> [Text.Text]
extractOpaqueNames binding =
  case TypeParser.parseType (unFFITypeAnnotation (_bindingTypeAnnotation binding)) of
    Just ffiType -> collectOpaqueFromType ffiType
    Nothing -> []

-- | Recursively collect opaque type names from an FFI type.
collectOpaqueFromType :: FFI.FFIType -> [Text.Text]
collectOpaqueFromType = \case
  FFI.FFIInt -> []
  FFI.FFIFloat -> []
  FFI.FFIString -> []
  FFI.FFIBool -> []
  FFI.FFIUnit -> []
  FFI.FFIList inner -> collectOpaqueFromType inner
  FFI.FFIMaybe inner -> collectOpaqueFromType inner
  FFI.FFIResult e v -> collectOpaqueFromType e ++ collectOpaqueFromType v
  FFI.FFITask e v -> collectOpaqueFromType e ++ collectOpaqueFromType v
  FFI.FFIFunctionType params ret -> concatMap collectOpaqueFromType params ++ collectOpaqueFromType ret
  FFI.FFITuple types -> concatMap collectOpaqueFromType types
  FFI.FFIRecord fields -> concatMap (collectOpaqueFromType . snd) fields
  FFI.FFIOpaque name -> [name | isOpaqueCandidate name]

-- | Check if a type name is a candidate for auto opaque inference.
--
-- Type variables (single lowercase letter) and built-in types are excluded.
isOpaqueCandidate :: Text.Text -> Bool
isOpaqueCandidate name
  | Text.null name = False
  | Text.length name == 1 && Char.isLower (Text.head name) = False
  | name `elem` builtinTypeNames = False
  | otherwise = True

-- | Built-in type names that should not be auto-created as opaque.
builtinTypeNames :: [Text.Text]
builtinTypeNames = ["Int", "Float", "String", "Bool", "Unit", "Never"]

-- | Check if a type name is not already defined in the environment.
isUnresolvedType :: Env.Env -> Text.Text -> Bool
isUnresolvedType env name =
  let nameObj = Name.fromChars (Text.unpack name)
   in not (Map.member nameObj (Env._types env))

-- | Create an opaque type entry for the environment.
makeOpaqueEntry :: ModuleName.Canonical -> Text.Text -> (Name.Name, Env.Info Env.Type)
makeOpaqueEntry ffiModuleName name =
  let nameObj = Name.fromChars (Text.unpack name)
   in (nameObj, Env.Specific ffiModuleName (Env.Union 0 ffiModuleName))

-- | Insert a type entry into the types map without overwriting existing entries.
insertType :: Map Name.Name (Env.Info Env.Type) -> (Name.Name, Env.Info Env.Type) -> Map Name.Name (Env.Info Env.Type)
insertType types (name, info) =
  Map.insertWith (\_ existing -> existing) name info types

-- | Determine the Canopy-side name for an FFI binding.
--
-- Uses @canopy-name if present, otherwise the JS function name.
effectiveCanopyName :: FFIBinding -> Text.Text
effectiveCanopyName binding =
  maybe (unFFIFuncName (_bindingFuncName binding)) id (_bindingCanopyName binding)

-- Process a single parsed FFI binding into Canopy types
processParsedFunction :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> FilePath -> Ann.Region -> FFIBinding -> Result i [Warning.Warning] (Text.Text, Can.Annotation, Env.Var)
processParsedFunction env ffiModuleName homeModuleName jsPath region binding = do
  let funcName = _bindingFuncName binding
      typeAnnotation = _bindingTypeAnnotation binding
      capabilities = _bindingCapabilities binding
      canopyName = effectiveCanopyName binding
  canopyType <- parseTypeStringWithHome env ffiModuleName homeModuleName jsPath region funcName typeAnnotation
  let typeWithCaps = prependCapabilities capabilities canopyType
      annotation = Can.Forall Map.empty typeWithCaps
      var = Env.Foreign ffiModuleName annotation
  Result.ok (canopyName, annotation, var)

-- | Prepend @Capability X ->@ parameters for each capability requirement.
--
-- Given @[\"microphone\", \"geolocation\"]@ and a base type @T@, produces
-- @Capability Microphone -> Capability Geolocation -> T@.
prependCapabilities :: [CapabilityName] -> Can.Type -> Can.Type
prependCapabilities caps baseType =
  foldr prependOneCapability baseType caps

-- | Prepend a single @Capability X ->@ to a type.
prependOneCapability :: CapabilityName -> Can.Type -> Can.Type
prependOneCapability (CapabilityName capName) innerType =
  Can.TLambda (capabilityType capName) innerType

-- | Build the canonical type @Capability X@ for a given permission name.
--
-- Maps permission names like @\"microphone\"@ to phantom types like @Microphone@,
-- producing @Capability Microphone@ as a canonical type.
capabilityType :: Text.Text -> Can.Type
capabilityType permissionName =
  Can.TType ModuleName.capability (Name.fromChars "Capability")
    [Can.TType ModuleName.capability (permissionToTypeName permissionName) []]

-- | Map a permission string to its corresponding phantom type name.
--
-- @\"microphone\"@ becomes @\"Microphone\"@, @\"screen-capture\"@ becomes
-- @\"ScreenCapture\"@, etc.
permissionToTypeName :: Text.Text -> Name.Name
permissionToTypeName = Name.fromChars . Text.unpack . toPascalCase

-- | Convert a kebab-case or lowercase permission name to PascalCase.
toPascalCase :: Text.Text -> Text.Text
toPascalCase = Text.concat . fmap capitalizeFirst . Text.splitOn "-"

-- | Capitalize the first character of a text value.
capitalizeFirst :: Text.Text -> Text.Text
capitalizeFirst t =
  maybe t (\(c, rest) -> Text.cons (Char.toUpper c) rest) (Text.uncons t)

-- | Build the dynamic environment from processed functions.
--
-- Registers FFI functions both as qualified vars (Alias.func) and as
-- unqualified vars (func) for auto-binding. This eliminates the need
-- for manual @functionName = FFI.functionName@ wrapper lines.
buildDynamicEnvironment :: Name.Name -> [(Text.Text, Can.Annotation, Env.Var)] -> ([(Name.Name, Env.Var)], Map.Map Name.Name (Env.Info Can.Annotation))
buildDynamicEnvironment aliasName processedFunctions =
  let ffiModuleName = ModuleName.Canonical Pkg.dummyName aliasName
      vars = buildUnqualifiedVars processedFunctions
      qVars = buildQualifiedVars ffiModuleName processedFunctions
  in (vars, qVars)

-- | Build unqualified variable bindings for auto-binding.
--
-- Each FFI function is available directly by name without requiring
-- an explicit @functionName = FFI.functionName@ delegation line.
buildUnqualifiedVars :: [(Text.Text, Can.Annotation, Env.Var)] -> [(Name.Name, Env.Var)]
buildUnqualifiedVars = List.map toUnqualifiedEntry
  where
    toUnqualifiedEntry (fname, _, var) =
      (Name.fromChars (Text.unpack fname), var)

-- Build qualified vars map for FFI functions (Module.functionName syntax)
buildQualifiedVars :: ModuleName.Canonical -> [(Text.Text, Can.Annotation, Env.Var)] -> Map.Map Name.Name (Env.Info Can.Annotation)
buildQualifiedVars ffiModuleName processedFunctions =
  Map.fromList (List.map toQualifiedEntry processedFunctions)
  where
    toQualifiedEntry (fname, annotation, _) =
      (Name.fromChars (Text.unpack fname), Env.Specific ffiModuleName annotation)

-- | Parse type string with home module context for custom type resolution.
--
-- Uses the unified 'FFI.TypeParser' to parse the type string into
-- 'FFIType', then converts to 'Can.Type' using environment-aware
-- resolution. Emits warnings for opaque types that cannot be found
-- in the environment.
parseTypeStringWithHome :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> FilePath -> Ann.Region -> FFIFuncName -> FFITypeAnnotation -> Result i [Warning.Warning] Can.Type
parseTypeStringWithHome env ffiModuleName homeModuleName jsPath region funcName typeAnnotation =
  case TypeParser.parseType (unFFITypeAnnotation typeAnnotation) of
    Just ffiType ->
      let canType = ffiTypeToCanonical env ffiModuleName homeModuleName ffiType
          unresolvedNames = collectUnresolved env ffiType
       in warnUnresolved jsPath funcName unresolvedNames
            >> Result.ok canType
    Nothing ->
      Result.throw (Error.FFIInvalidType region jsPath (Name.fromChars (Text.unpack (unFFIFuncName funcName))) ("Failed to parse type: " ++ Text.unpack (unFFITypeAnnotation typeAnnotation)))

-- | Emit warnings for each unresolved opaque type name.
warnUnresolved :: FilePath -> FFIFuncName -> [Text.Text] -> Result i [Warning.Warning] ()
warnUnresolved _ _ [] = Result.ok ()
warnUnresolved jsPath funcName (name : rest) = do
  Result.warn (Warning.FFIUnresolvedType (Text.pack jsPath) (unFFIFuncName funcName) name)
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
  concatMap (blockToWarning moduleName) (parseCapabilityBlocks (Text.lines content))

-- | Parse JSDoc blocks that contain both @name and @capability annotations.
parseCapabilityBlocks :: [Text.Text] -> [(Text.Text, [Text.Text])]
parseCapabilityBlocks [] = []
parseCapabilityBlocks (line:rest)
  | isJSDocStart line =
      let (commentBlock, remaining) = takeJSDocBlock (line:rest)
      in case parseCapabilityBlock commentBlock of
           Just cap -> cap : parseCapabilityBlocks remaining
           Nothing -> parseCapabilityBlocks remaining
  | otherwise = parseCapabilityBlocks rest

-- | Parse a JSDoc block for function name and capability annotations.
parseCapabilityBlock :: [Text.Text] -> Maybe (Text.Text, [Text.Text])
parseCapabilityBlock commentLines = do
  functionName <- findNameAnnotation commentLines
  let capabilities = findAllCapabilities commentLines
  if null capabilities then Nothing else Just (functionName, capabilities)

-- | Find all @capability annotations in a JSDoc block.
findAllCapabilities :: [Text.Text] -> [Text.Text]
findAllCapabilities = mapMaybe parseCapabilityAnnotation

-- | Parse a @capability annotation from a single line.
parseCapabilityAnnotation :: Text.Text -> Maybe Text.Text
parseCapabilityAnnotation line =
  fmap Text.strip (Text.stripPrefix "@capability " (stripJSDocLeader line))

-- | Convert a parsed capability block into a warning.
blockToWarning :: Text.Text -> (Text.Text, [Text.Text]) -> [Warning.Warning]
blockToWarning moduleName (funcName, capabilities) =
  [Warning.CapabilityNotice moduleName funcName capabilities]

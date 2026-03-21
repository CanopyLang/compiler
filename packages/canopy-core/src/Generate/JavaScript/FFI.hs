{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | FFI code generation for the Canopy compiler.
--
-- This module is responsible for generating JavaScript FFI content,
-- function bindings, and runtime validators. It handles:
--
-- * Emitting raw FFI JavaScript source into the bundle
-- * Generating curried function bindings for Canopy<->JS interop
-- * Producing runtime type validators when strict mode is enabled
-- * Parsing \@canopy-type annotations from JSDoc comments
--
-- The 'FFIInfo' type carries all data needed to emit FFI JavaScript
-- code without relying on global state or MVars.
--
-- WARNING: NO HARDCODING OF FFI FILE PATHS!
-- All FFI file paths MUST come from the actual foreign import statements
-- in the source code, NOT hardcoded values.
--
-- @since 0.19.2
module Generate.JavaScript.FFI
  ( -- * Types
    FFIInfo (..),
    ffiFilePath,
    ffiContent,
    ffiAlias,
    ExtractedFFI (..),

    -- * Generation
    extractFFIAliases,
    generateFFIContent,
    generateFFIValidators,

    -- * Internal (exported for testing and ESM)
    extractCanopyTypeFunctions,
    extractFFIFunctions,
    extractInternalNames,
    extractCanopyType,
    findFunctionName,
    isValidJsIdentifier,
    sanitizeForIdent,
    escapeJsString,
    trim,
  )
where

import qualified AST.Optimized as Opt
import qualified Data.Char as Char
import Control.Lens (Lens', (.~), (&))
import qualified Data.Binary as Binary
import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified FFI.TypeParser as TypeParser
import qualified Generate.JavaScript.FFI.Minify as FFIMinify
import qualified Generate.JavaScript.FFI.Registry as FFIRegistry
import FFI.Types (BindingMode (..))
import qualified FFI.Validator as Validator
import qualified Generate.Mode as Mode
import System.FilePath (takeBaseName)

-- | Graph of optimized global definitions.
type Graph = Map Opt.Global Opt.Node

-- FFI INFO TYPE

-- | FFI information for JavaScript generation.
--
-- Carries everything needed to emit FFI JavaScript code in the bundle
-- without relying on global storage.  'FilePath' clarifies path semantics,
-- 'Text' captures Unicode source content, and 'Name.Name' preserves the
-- alias that appeared in the @foreign import@ declaration.
data FFIInfo = FFIInfo
  { _ffiFilePath :: !FilePath     -- ^ Path to the JavaScript file
  , _ffiContent  :: !Text.Text    -- ^ Content of the JavaScript file
  , _ffiAlias    :: !Name.Name    -- ^ Alias used in the import statement
  } deriving (Eq, Show)

-- | Manual 'Binary' instance to avoid depending on orphan instances for
-- 'Text' and to use the project-standard 'Utf8' serialisation for 'Name'.
instance Binary.Binary FFIInfo where
  put (FFIInfo path content alias) = do
    Binary.put path
    Binary.put (TextEnc.encodeUtf8 content)
    Binary.put alias
  get = do
    path <- Binary.get
    contentBytes <- Binary.get
    alias <- Binary.get
    return (FFIInfo path (TextEnc.decodeUtf8 contentBytes) alias)

-- | Lens for '_ffiFilePath' field of 'FFIInfo'.
ffiFilePath :: Lens' FFIInfo FilePath
ffiFilePath f s = fmap (\x -> s { _ffiFilePath = x }) (f (_ffiFilePath s))

-- | Lens for '_ffiContent' field of 'FFIInfo'.
ffiContent :: Lens' FFIInfo Text.Text
ffiContent f s = fmap (\x -> s { _ffiContent = x }) (f (_ffiContent s))

-- | Lens for '_ffiAlias' field of 'FFIInfo'.
ffiAlias :: Lens' FFIInfo Name.Name
ffiAlias f s = fmap (\x -> s { _ffiAlias = x }) (f (_ffiAlias s))

-- EXTRACTED FFI TYPE

-- | Extracted FFI function info from JSDoc annotations.
data ExtractedFFI = ExtractedFFI
  { _extractedName :: !Text.Text
    -- ^ Function name (from @name annotation or JS function declaration)
  , _extractedType :: !Text.Text
    -- ^ Type annotation from @canopy-type
  , _extractedMode :: !BindingMode
    -- ^ Binding mode from @canopy-bind
  , _extractedCanopyName :: !(Maybe Text.Text)
    -- ^ Optional Canopy-side name override
  , _extractedJSName :: !(Maybe Text.Text)
    -- ^ Original JS function name when @name annotation overrides it
  } deriving (Eq, Show)

-- | Lens for '_extractedJSName' field of 'ExtractedFFI'.
extractedJSName :: Lens' ExtractedFFI (Maybe Text.Text)
extractedJSName f s = fmap (\x -> s { _extractedJSName = x }) (f (_extractedJSName s))

-- EXTRACT FFI ALIASES

-- | Extract FFI alias names from FFI info map.
--
-- Used to identify which module names correspond to FFI modules vs application modules.
-- FFI modules use direct JavaScript access, while application modules use qualified names.
--
-- @since 0.19.1
extractFFIAliases :: Map String FFIInfo -> Set Name.Name
extractFFIAliases ffiInfos =
  Set.fromList (map _ffiAlias (Map.elems ffiInfos))

-- GENERATE FFI CONTENT

-- | Generate FFI JavaScript content to include in bundle.
--
-- Receives FFI information directly through the compilation pipeline
-- instead of using global storage, eliminating MVar deadlock issues.
-- When FFI strict mode is enabled, also generates runtime validators.
--
-- Cross-FFI dependency resolution: scans all FFI files' content for
-- @_@-prefixed internal references (e.g. @_Json_unwrap@) and ensures
-- any such name defined in one FFI file is re-exported globally even
-- if Canopy code never calls it directly. This is required because
-- FFI files can reference helpers from other FFI files using the
-- conventional @_Module_name@ naming scheme.
generateFFIContent
  :: Mode.Mode
  -> Graph
  -> Map String FFIInfo
  -> Map Name.Name (Set Name.Name)
  -> Builder
generateFFIContent mode graph ffiInfos usedFuncs =
  if Map.null ffiInfos
     then mempty
     else mconcat parts <> validators
  where
    fileRegistries = buildAliasRegistries ffiInfos
    initialSeeds = computeInitialSeeds ffiInfos usedFuncs fileRegistries
    resolvedNeeded = FFIRegistry.closeFFICrossFileDeps fileRegistries initialSeeds
    parts =
      [ "\n// FFI JavaScript content and bindings\n"
      ]
        ++ Map.foldrWithKey (formatFFIWithBindings mode graph usedFuncs fileRegistries resolvedNeeded) [] ffiInfos
    validators =
      if Mode.isFFIStrict mode
        then generateFFIValidators mode ffiInfos
        else mempty

-- | Build per-file FFI registries for all FFI files.
--
-- Keyed by file path (not alias name) to avoid collisions when multiple
-- modules share the same FFI alias (e.g. Platform, Platform.Cmd, and
-- Platform.Sub all use PlatformFFI but import different JS files).
buildAliasRegistries
  :: Map String FFIInfo
  -> Map String (Map FFIRegistry.FFIBlockId FFIRegistry.FFIBlock)
buildAliasRegistries ffiInfos =
  Map.map (\info -> FFIRegistry.buildFFIRegistry (_ffiContent info)) ffiInfos

-- | Compute initial seed blocks per file from used function tracking.
--
-- Keyed by file path to match the per-file registries, avoiding alias
-- collisions when multiple modules share the same FFI alias name.
computeInitialSeeds
  :: Map String FFIInfo
  -> Map Name.Name (Set Name.Name)
  -> Map String (Map FFIRegistry.FFIBlockId FFIRegistry.FFIBlock)
  -> Map String (Set FFIRegistry.FFIBlockId)
computeInitialSeeds ffiInfos usedFuncs fileRegistries =
  Map.mapWithKey computeForFile ffiInfos
  where
    computeForFile filePath info =
      let alias = _ffiAlias info
          functions = extractFFIFunctions (Text.lines (_ffiContent info))
          neededNames = Map.findWithDefault Set.empty alias usedFuncs
          neededFunctions = filterNeededFunctions functions neededNames
          reg = Map.findWithDefault Map.empty filePath fileRegistries
       in computeSeedBlocks reg neededFunctions

-- GENERATE FFI VALIDATORS

-- | Generate FFI validators for all function return types.
--
-- Uses the 'Mode' to derive 'ValidatorConfig', enabling CLI control
-- over strict mode and debug verbosity in generated validators.
--
-- @since 0.19.2
generateFFIValidators :: Mode.Mode -> Map String FFIInfo -> Builder
generateFFIValidators mode ffiInfos =
  if Map.null ffiInfos
     then mempty
     else mconcat parts
  where
    config = modeToValidatorConfig mode

    parts =
      [ "\n// FFI type validators (generated by canopy)\n" ]
        ++ Map.foldrWithKey collectValidators [] ffiInfos

    collectValidators :: String -> FFIInfo -> [Builder] -> [Builder]
    collectValidators _key info acc =
      let functions = extractCanopyTypeFunctions (Text.lines (_ffiContent info))
          validatorBuilders = concatMap (generateValidatorForFunction config) functions
      in validatorBuilders ++ acc

-- | Generate a validator builder for a single FFI function.
generateValidatorForFunction :: Validator.ValidatorConfig -> (Text.Text, Text.Text) -> [Builder]
generateValidatorForFunction config (_funcName, typeStr) =
  case Validator.parseReturnType typeStr of
    Just returnType ->
      [BB.byteString (TextEnc.encodeUtf8 (Validator.generateAllValidators config returnType))]
    Nothing -> []

-- | Derive a 'ValidatorConfig' from the compilation 'Mode'.
--
-- Maps CLI flags to validator configuration:
--
-- * Strict mode is always on when validators are generated
--   (the on\/off is handled by 'Mode.isFFIStrict')
-- * Debug mode is controlled by @--ffi-debug@
--
-- @since 0.19.2
modeToValidatorConfig :: Mode.Mode -> Validator.ValidatorConfig
modeToValidatorConfig mode =
  Validator.ValidatorConfig
    { Validator._configStrictMode = True
    , Validator._configValidateOpaque = False
    , Validator._configDebugMode = Mode.isFFIDebug mode
    }

-- FORMAT FFI FILE CONTENT

-- | Format FFI file content for inclusion using FFIInfo.
_formatFFIFileFromInfo :: String -> Text.Text -> [Builder] -> [Builder]
_formatFFIFileFromInfo path content acc =
  ("\n// From " <> BB.stringUtf8 path <> "\n")
    : BB.byteString (TextEnc.encodeUtf8 content)
    : "\n"
    : acc

-- | Emit FFI file content wrapped in an IIFE, followed by its bindings.
--
-- Wraps each FFI file in an Immediately Invoked Function Expression to
-- isolate its declarations from other FFI files. This prevents collisions
-- when multiple FFI files define functions with the same name (e.g. both
-- char.js and string.js define @toLower@).
--
-- The IIFE returns an object mapping each annotated function name to its
-- value. Bindings then reference @_AliasIIFE.funcName@ instead of bare
-- @funcName@, giving each FFI file its own namespace while preserving
-- access to runtime globals like @_Utils_chr@ and @F2@.
--
-- Uses pre-computed registries and resolved needed blocks from
-- 'closeFFICrossFileDeps' for precise cross-file dependency resolution.
formatFFIWithBindings
  :: Mode.Mode
  -> Graph
  -> Map Name.Name (Set Name.Name)
  -> Map String (Map FFIRegistry.FFIBlockId FFIRegistry.FFIBlock)
  -> Map String (Set FFIRegistry.FFIBlockId)
  -> String
  -> FFIInfo
  -> [Builder]
  -> [Builder]
formatFFIWithBindings mode graph usedFuncs fileRegistries resolvedNeeded _key info acc
  | not (isValidJsIdentifier aliasStr) = acc
  | otherwise =
      wrappedContent (reExports ++ bindingsSection ++ acc)
  where
    path = _ffiFilePath info
    contentText = _ffiContent info
    alias = _ffiAlias info
    aliasStr = Name.toChars alias
    iifeVar = "_" <> sanitizeForIdent (takeBaseName path) <> "_" <> aliasStr <> "IIFE"
    iifeVarText = Text.pack iifeVar
    functions = extractFFIFunctions (Text.lines contentText)
    jsNames = List.map jsReferenceName functions

    -- Tree-shake: determine which functions are actually needed
    neededFuncNames = Map.findWithDefault Set.empty alias usedFuncs
    neededFunctions = filterNeededFunctions functions neededFuncNames

    -- Use pre-computed per-file registry and resolved needed blocks
    ffiRegistry = Map.findWithDefault Map.empty path fileRegistries
    allNeeded = Map.findWithDefault Set.empty path resolvedNeeded

    -- Emit only needed content if tree-shaking found blocks;
    -- fall back to full content if registry found nothing
    treeShaken = Map.null ffiRegistry || Set.null allNeeded
    isProd = case mode of Mode.Prod {} -> True; _ -> False
    rawContent =
      if treeShaken
        then TextEnc.encodeUtf8 contentText
        else materializeFFI (FFIRegistry.emitNeededBlocks ffiRegistry allNeeded)
    minifiedContent =
      if isProd
        then FFIMinify.stripDebugBranches (FFIMinify.minifyFFI rawContent)
        else rawContent
    ffiContent' = BB.byteString minifiedContent

    -- Only export names that exist in needed blocks
    neededInternalNames =
      if treeShaken
        then extractInternalNames (Text.lines contentText)
        else filterNeededInternals (extractInternalNames (Text.lines contentText)) ffiRegistry allNeeded
    allExportNames =
      if treeShaken
        then jsNames ++ neededInternalNames
        else List.map jsReferenceName neededFunctions ++ neededInternalNames
    returnObj = buildIIFEReturnObj allExportNames

    wrappedContent rest =
      ("\n// From " <> BB.stringUtf8 path <> " (IIFE-isolated)\n")
        : ("var " <> BB.stringUtf8 iifeVar <> " = (function() {\n")
        : ffiContent'
        : ("\nreturn " <> returnObj <> ";\n")
        : "})();\n"
        : rest
    reExports = List.map (reExportInternal iifeVar) neededInternalNames
                  ++ kernelReExports aliasStr iifeVar neededFunctions
    iifeFunctions = List.map (iifeExtractedFFI iifeVarText) neededFunctions
    bindings = concatMap (generateFFIBinding mode graph path aliasStr) iifeFunctions
    bindingsSection =
      case bindings of
        [] -> []
        _ ->
          ("\n// Bindings for " <> BB.stringUtf8 path <> "\n")
            : ("var " <> BB.stringUtf8 aliasStr <> " = " <> BB.stringUtf8 aliasStr <> " || {};\n")
            : List.map (<> "\n") bindings ++ ["\n"]

-- | Filter extracted FFI functions to only those actually used.
filterNeededFunctions :: [ExtractedFFI] -> Set Name.Name -> [ExtractedFFI]
filterNeededFunctions functions neededNames =
  if Set.null neededNames
    then functions
    else List.filter isNeeded functions
  where
    isNeeded ef =
      let canopyName = effectiveName ef
          jsName = jsReferenceName ef
       in Set.member (Name.fromChars (Text.unpack canopyName)) neededNames
            || Set.member (Name.fromChars (Text.unpack jsName)) neededNames

-- | Compute seed block IDs from needed function names.
computeSeedBlocks
  :: Map FFIRegistry.FFIBlockId FFIRegistry.FFIBlock
  -> [ExtractedFFI]
  -> Set FFIRegistry.FFIBlockId
computeSeedBlocks reg functions =
  Set.filter (\bid -> Map.member bid reg) candidates
  where
    candidates = Set.fromList
      [ FFIRegistry.FFIBlockId (TextEnc.encodeUtf8 name)
      | ef <- functions
      , name <- [_extractedName ef, jsReferenceName ef]
      ]

-- | Filter internal names to only those in needed blocks.
--
-- An internal name is included when:
--
--   * Its block is in the set of needed blocks (@needed@), OR
--   * It has no block in the registry (not tree-shakeable)
--
-- Cross-FFI dependencies are handled upstream by 'closeFFICrossFileDeps',
-- which adds the necessary blocks to the needed set before this runs.
filterNeededInternals
  :: [Text.Text]
  -> Map FFIRegistry.FFIBlockId FFIRegistry.FFIBlock
  -> Set FFIRegistry.FFIBlockId
  -> [Text.Text]
filterNeededInternals names reg needed =
  List.filter isInNeeded names
  where
    isInNeeded name =
      let bid = FFIRegistry.FFIBlockId (TextEnc.encodeUtf8 name)
       in Set.member bid needed
            || not (Map.member bid reg)

-- | Generate kernel-style re-exports for @\@name@-annotated FFI functions.
--
-- When an FFI alias ends with @\"FFI\"@ (e.g. @VirtualDomFFI@), the codegen
-- may reference functions using the kernel naming convention
-- @_ModuleName_funcName@ (e.g. @_VirtualDom_init@). This function emits
-- re-exports from the IIFE to create those global bindings.
--
-- @since 0.19.2
kernelReExports :: String -> String -> [ExtractedFFI] -> [Builder]
kernelReExports aliasStr iifeVar functions =
  case stripFFISuffix aliasStr of
    Nothing -> []
    Just kernelBase ->
      concatMap (mkKernelReExport kernelBase iifeVar) functions

-- | Strip the @\"FFI\"@ suffix from an alias name.
stripFFISuffix :: String -> Maybe String
stripFFISuffix s =
  fmap Text.unpack (Text.stripSuffix "FFI" (Text.pack s))

-- | Emit a single kernel re-export for an FFI function.
mkKernelReExport :: String -> String -> ExtractedFFI -> [Builder]
mkKernelReExport kernelBase iifeVar ef =
  let funcName = Text.unpack (jsReferenceName ef)
      kernelName = "_" <> kernelBase <> "_" <> funcName
      iifeRef = iifeVar <> "." <> funcName
   in ["var " <> BB.stringUtf8 kernelName <> " = " <> BB.stringUtf8 iifeRef <> ";\n"]

-- | Re-export an internal @_@-prefixed name from the IIFE to global scope.
--
-- Produces @var _Json_unwrap = _JsonFFIIIFE._Json_unwrap;@ so that other
-- FFI files can reference these conventionally-scoped helper functions.
reExportInternal :: String -> Text.Text -> Builder
reExportInternal iifeVar name =
  "var " <> nameB <> " = " <> BB.stringUtf8 iifeVar <> "." <> nameB <> ";\n"
  where
    nameB = BB.byteString (TextEnc.encodeUtf8 name)

-- | Build the IIFE return object mapping names to their values.
--
-- Produces @{ name1: name1, name2: name2, ... }@ for all names
-- (both annotated FFI functions and internal @_@-prefixed helpers).
buildIIFEReturnObj :: [Text.Text] -> Builder
buildIIFEReturnObj names =
  "{ " <> entries <> " }"
  where
    entries = mconcat (List.intersperse ", " (List.map mkEntry names))
    mkEntry n =
      let b = BB.byteString (TextEnc.encodeUtf8 n)
       in b <> ": " <> b

-- | Extract @_@-prefixed top-level function\/var names from FFI content.
--
-- These are internal helper functions that follow the Elm kernel naming
-- convention (@_Module_name@) and may be referenced by other FFI files.
-- They need to be re-exported to global scope after IIFE wrapping.
extractInternalNames :: [Text.Text] -> [Text.Text]
extractInternalNames = extractFromLines
  where
    extractFromLines [] = []
    extractFromLines (line:rest)
      | "function _" `Text.isPrefixOf` trimmed =
          maybe id (:) (extractFuncName trimmed) (extractFromLines rest)
      | "var _" `Text.isPrefixOf` trimmed =
          maybe id (:) (extractVarDeclName trimmed) (extractFromLines rest)
      | otherwise = extractFromLines rest
      where
        trimmed = Text.stripStart line
    extractFuncName s =
      let after = Text.drop 9 s
          name = Text.takeWhile isIdentChar after
       in if Text.length name > 1 then Just name else Nothing
    extractVarDeclName s =
      let after = Text.drop 4 s
          name = Text.takeWhile isIdentChar after
       in if "_" `Text.isPrefixOf` name && Text.length name > 1
            then Just name
            else Nothing
    isIdentChar c =
      c == '_' || c == '$'
        || (c >= 'a' && c <= 'z')
        || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9')

-- PARSE CANOPY TYPE ANNOTATIONS

-- | Update an 'ExtractedFFI' to reference through the IIFE namespace.
--
-- Sets the JS reference name to @_AliasIIFE.originalName@ so bindings
-- access the function through the IIFE's returned object.
iifeExtractedFFI :: Text.Text -> ExtractedFFI -> ExtractedFFI
iifeExtractedFFI iifeVar ef =
  ef & extractedJSName .~ Just qualifiedName
  where
    qualifiedName = iifeVar <> "." <> jsReferenceName ef

-- | Extract functions that have \@canopy-type annotations from JavaScript source lines.
--
-- Operates on 'Text' lines directly to avoid intermediate @[Char]@
-- allocation from the FFI content.
--
-- @since 0.19.2
extractCanopyTypeFunctions :: [Text.Text] -> [(Text.Text, Text.Text)]
extractCanopyTypeFunctions = List.map toSimple . extractFFIFunctions
  where
    toSimple ef = (effectiveName ef, _extractedType ef)

-- | Get the effective Canopy-side name for an extracted FFI function.
effectiveName :: ExtractedFFI -> Text.Text
effectiveName ef =
  maybe (_extractedName ef) id (_extractedCanopyName ef)

-- | Get the actual JS function name to reference on the RHS of bindings.
--
-- When @\@name@ overrides the primary name, the original JS function name
-- is stored in '_extractedJSName'. Falls back to '_extractedName' when
-- no override exists (the name IS the JS function name).
jsReferenceName :: ExtractedFFI -> Text.Text
jsReferenceName ef =
  maybe (_extractedName ef) id (_extractedJSName ef)

-- | Extract full FFI function information from JavaScript source lines.
extractFFIFunctions :: [Text.Text] -> [ExtractedFFI]
extractFFIFunctions [] = []
extractFFIFunctions allLines@(_:_) =
  extractFromBlocks allLines

-- | Extract FFI functions from JSDoc blocks in source lines.
extractFromBlocks :: [Text.Text] -> [ExtractedFFI]
extractFromBlocks [] = []
extractFromBlocks (line:rest)
  | isJSDocStart line =
      let (block, remaining) = takeJSDocBlock (line:rest)
       in case parseFFIBlock block rest of
            Just ef -> ef : extractFromBlocks remaining
            Nothing -> extractFromBlocks remaining
  | otherwise = extractFromBlocks rest

-- | Check if a line starts a JSDoc comment.
isJSDocStart :: Text.Text -> Bool
isJSDocStart line = "/**" `Text.isPrefixOf` Text.stripStart line

-- | Take a complete JSDoc block and the remaining lines.
takeJSDocBlock :: [Text.Text] -> ([Text.Text], [Text.Text])
takeJSDocBlock [] = ([], [])
takeJSDocBlock (line:rest)
  | "*/" `Text.isInfixOf` line = ([line], rest)
  | otherwise =
      let (block, remaining) = takeJSDocBlock rest
       in (line:block, remaining)

-- | Parse a JSDoc block into an ExtractedFFI.
--
-- When @\@name@ is present, uses it as the primary name and stores the
-- JS function name separately in '_extractedJSName' so code generation
-- can reference the actual JS function on the RHS of bindings.
parseFFIBlock :: [Text.Text] -> [Text.Text] -> Maybe ExtractedFFI
parseFFIBlock block followingLines = do
  canopyType <- findAnnotationInBlock "@canopy-type " block
  let bindMode = parseBlockBindMode block
      canopyName = findAnnotationInBlock "@canopy-name " block
      jsFuncName = findFunctionName followingLines
      nameAnnotation = findAnnotationInBlock "@name " block
  funcName <- nameAnnotation <|> jsFuncName
  let jsName = case nameAnnotation of
        Just _ -> jsFuncName
        Nothing -> Nothing
  Just (ExtractedFFI funcName canopyType bindMode canopyName jsName)

-- | Find a specific annotation value in a JSDoc block.
findAnnotationInBlock :: Text.Text -> [Text.Text] -> Maybe Text.Text
findAnnotationInBlock _ [] = Nothing
findAnnotationInBlock tag (line:rest) =
  let stripped = stripJSDocLeader line
   in case Text.stripPrefix tag stripped of
        Just value -> Just (Text.strip value)
        Nothing -> findAnnotationInBlock tag rest

-- | Strip JSDoc leader characters from a line.
stripJSDocLeader :: Text.Text -> Text.Text
stripJSDocLeader = Text.dropWhile (\c -> c == ' ' || c == '*')

-- | Parse binding mode from a JSDoc block.
parseBlockBindMode :: [Text.Text] -> BindingMode
parseBlockBindMode [] = FunctionCall
parseBlockBindMode (line:rest) =
  case findAnnotationInBlock "@canopy-bind " [line] of
    Just value -> parseBindModeText value
    Nothing -> parseBlockBindMode rest

-- | Parse binding mode from the text after @canopy-bind.
parseBindModeText :: Text.Text -> BindingMode
parseBindModeText txt =
  case Text.words txt of
    ["method", name] -> MethodCall name
    ["get", name] -> PropertyGet name
    ["set", name] -> PropertySet name
    ["new", name] -> ConstructorCall name
    _ -> FunctionCall

-- | Alternative combinator for Maybe.
(<|>) :: Maybe a -> Maybe a -> Maybe a
(<|>) (Just x) _ = Just x
(<|>) Nothing y = y

-- | Extract \@canopy-type annotation from a single line.
--
-- Uses 'Text.isInfixOf' (O(n) with fast string matching) instead of
-- the previous 'List.isInfixOf' (O(n*m) on @[Char]@).
--
-- @since 0.19.2
extractCanopyType :: Text.Text -> Maybe Text.Text
extractCanopyType line
  | " * @canopy-type " `Text.isInfixOf` line =
      fmap Text.strip (Text.stripPrefix "@canopy-type " (Text.dropWhile (/= '@') line))
  | otherwise = Nothing

-- | Find the JS function\/variable name in the lines following a JSDoc block.
--
-- Handles these patterns:
--
--   * @function name(...)@
--   * @async function name(...)@
--   * @var name = ...@ (for F2-wrapped or expression-assigned functions)
--
-- Stops scanning at the next JSDoc block (@\/**@) to avoid finding
-- inner function declarations from unrelated code.
--
-- @since 0.19.2
findFunctionName :: [Text.Text] -> Maybe Text.Text
findFunctionName [] = Nothing
findFunctionName (line:rest)
  | isJSDocStart trimmed = Nothing
  | "function " `Text.isPrefixOf` stripped = extractNameAfterFunction stripped
  | "var " `Text.isPrefixOf` trimmed = extractVarName trimmed
  | otherwise = findFunctionName rest
  where
    trimmed = Text.strip line
    stripped = stripAsyncPrefix trimmed
    stripAsyncPrefix s
      | "async " `Text.isPrefixOf` s = Text.strip (Text.drop 6 s)
      | otherwise = s
    extractNameAfterFunction s =
      let after = Text.strip (Text.dropWhile (/= ' ') s)
          name = Text.takeWhile (\c -> c /= '(' && c /= ' ') after
       in if Text.null name then findFunctionName rest else Just name
    extractVarName s =
      let after = Text.strip (Text.drop 4 s)
          name = Text.takeWhile (\c -> c /= ' ' && c /= '=') after
       in if Text.null name then findFunctionName rest else Just name

-- GENERATE FUNCTION BINDINGS

-- | Generate JavaScript binding for an extracted FFI function.
--
-- Validates that the function name is a safe JavaScript identifier
-- before generating any code. For binding modes other than FunctionCall,
-- generates inline JavaScript expressions (method calls, property access,
-- constructor invocations) instead of delegating to a JS function.
--
-- @since 0.20.0
generateFFIBinding :: Mode.Mode -> Graph -> String -> String -> ExtractedFFI -> [Builder]
generateFFIBinding mode _graph _filePath alias ef
  | not (isValidJsIdentifier canopyName) = []
  | otherwise =
      case _extractedMode ef of
        FunctionCall -> generateFunctionCallBinding mode alias ef
        MethodCall methodName -> generateMethodBinding alias ef methodName
        PropertyGet propName -> generatePropertyGetBinding alias ef propName
        PropertySet propName -> generatePropertySetBinding alias ef propName
        ConstructorCall className -> generateConstructorBinding alias ef className
  where
    canopyName = Text.unpack (effectiveName ef)

-- | Generate binding for a standard function call.
generateFunctionCallBinding :: Mode.Mode -> String -> ExtractedFFI -> [Builder]
generateFunctionCallBinding mode alias ef =
  let canopyNameText = effectiveName ef
      canopyName = Text.unpack canopyNameText
      canopyTypeText = _extractedType ef
      arity = maybe 0 TypeParser.countArity (TypeParser.parseType canopyTypeText)
      jsVarB = BB.stringUtf8 ("$author$project$" ++ alias ++ "$" ++ canopyName)
      aliasB = BB.stringUtf8 alias
      canopyNameB = BB.byteString (TextEnc.encodeUtf8 canopyNameText)
      jsNameB = BB.byteString (TextEnc.encodeUtf8 (jsReferenceName ef))
      callPathB = "'" <> escapeJsString (Text.pack alias <> "." <> canopyNameText) <> "'"
   in if Mode.isFFIStrict mode
        then generateValidatedBinding jsVarB aliasB canopyNameB jsNameB arity canopyTypeText callPathB
        else generateSimpleBinding jsVarB aliasB canopyNameB jsNameB arity

-- | Generate binding for a method call: @obj.method(args)@.
generateMethodBinding :: String -> ExtractedFFI -> Text.Text -> [Builder]
generateMethodBinding alias ef methodName =
  let canopyNameText = effectiveName ef
      canopyName = Text.unpack canopyNameText
      arity = maybe 0 TypeParser.countArity (TypeParser.parseType (_extractedType ef))
      jsVarB = BB.stringUtf8 ("$author$project$" ++ alias ++ "$" ++ canopyName)
      aliasB = BB.stringUtf8 alias
      nameB = BB.byteString (TextEnc.encodeUtf8 canopyNameText)
      methodB = BB.byteString (TextEnc.encodeUtf8 methodName)
      args = map (\i -> "_" <> BB.intDec i) [0 .. arity - 1]
      argList = mconcat (List.intersperse ", " args)
      restArgs = mconcat (List.intersperse ", " (drop 1 args))
      body = "_0." <> methodB <> "(" <> restArgs <> ")"
      funcExpr = wrapArity arity ("function(" <> argList <> ") { return " <> body <> "; }")
   in ["var " <> jsVarB <> " = " <> funcExpr <> ";", aliasB <> "." <> nameB <> " = " <> jsVarB <> ";"]

-- | Generate binding for a property getter: @obj.propName@.
generatePropertyGetBinding :: String -> ExtractedFFI -> Text.Text -> [Builder]
generatePropertyGetBinding alias ef propName =
  let canopyNameText = effectiveName ef
      canopyName = Text.unpack canopyNameText
      jsVarB = BB.stringUtf8 ("$author$project$" ++ alias ++ "$" ++ canopyName)
      aliasB = BB.stringUtf8 alias
      nameB = BB.byteString (TextEnc.encodeUtf8 canopyNameText)
      propB = BB.byteString (TextEnc.encodeUtf8 propName)
      body = "_0." <> propB
      funcExpr = "function(_0) { return " <> body <> "; }"
   in ["var " <> jsVarB <> " = " <> funcExpr <> ";", aliasB <> "." <> nameB <> " = " <> jsVarB <> ";"]

-- | Generate binding for a property setter: @obj.propName = val@.
generatePropertySetBinding :: String -> ExtractedFFI -> Text.Text -> [Builder]
generatePropertySetBinding alias ef propName =
  let canopyNameText = effectiveName ef
      canopyName = Text.unpack canopyNameText
      jsVarB = BB.stringUtf8 ("$author$project$" ++ alias ++ "$" ++ canopyName)
      aliasB = BB.stringUtf8 alias
      nameB = BB.byteString (TextEnc.encodeUtf8 canopyNameText)
      propB = BB.byteString (TextEnc.encodeUtf8 propName)
      body = "_0." <> propB <> " = _1"
      funcExpr = wrapArity 2 ("function(_0, _1) { " <> body <> "; }")
   in ["var " <> jsVarB <> " = " <> funcExpr <> ";", aliasB <> "." <> nameB <> " = " <> jsVarB <> ";"]

-- | Generate binding for a constructor call: @new ClassName(args)@.
generateConstructorBinding :: String -> ExtractedFFI -> Text.Text -> [Builder]
generateConstructorBinding alias ef className =
  let canopyNameText = effectiveName ef
      canopyName = Text.unpack canopyNameText
      arity = maybe 0 TypeParser.countArity (TypeParser.parseType (_extractedType ef))
      jsVarB = BB.stringUtf8 ("$author$project$" ++ alias ++ "$" ++ canopyName)
      aliasB = BB.stringUtf8 alias
      nameB = BB.byteString (TextEnc.encodeUtf8 canopyNameText)
      classB = BB.byteString (TextEnc.encodeUtf8 className)
      args = map (\i -> "_" <> BB.intDec i) [0 .. arity - 1]
      argList = mconcat (List.intersperse ", " args)
      body = "new " <> classB <> "(" <> argList <> ")"
      funcExpr = wrapArity arity ("function(" <> argList <> ") { return " <> body <> "; }")
   in ["var " <> jsVarB <> " = " <> funcExpr <> ";", aliasB <> "." <> nameB <> " = " <> jsVarB <> ";"]

-- | Wrap a function expression with F<N>() for currying when arity > 1.
wrapArity :: Int -> Builder -> Builder
wrapArity arity funcExpr
  | arity <= 1 = funcExpr
  | otherwise = "F" <> BB.intDec arity <> "(" <> funcExpr <> ")"

-- | Generate simple binding without validation.
--
-- Uses the JS function name (@jsNameB@) on the RHS to reference the actual
-- function defined in the FFI file, and the Canopy name (@canopyNameB@) for
-- the namespace property key.
--
-- @since 0.19.2
generateSimpleBinding :: Builder -> Builder -> Builder -> Builder -> Int -> [Builder]
generateSimpleBinding jsVarB aliasB canopyNameB jsNameB arity =
  let rawName = if arity > 1 then "(" <> jsNameB <> ".f||" <> jsNameB <> ")" else jsNameB
      wrapper = if arity <= 1 then mempty else "F" <> BB.intDec arity <> "("
      closing = if arity <= 1 then mempty else ")"
      namespaceBinding = aliasB <> "." <> canopyNameB <> " = " <> wrapper <> rawName <> closing <> ";"
  in ["var " <> jsVarB <> " = " <> wrapper <> rawName <> closing <> ";", namespaceBinding]

-- | Generate binding with runtime validation wrapper.
--
-- All name parameters are pre-converted to 'Builder' at the call site.
-- The @canopyNameB@ is used for the namespace property key, while
-- @jsNameB@ is used on the RHS to reference the actual JS function
-- (which may be IIFE-qualified like @_AliasIIFE.funcName@).
generateValidatedBinding :: Builder -> Builder -> Builder -> Builder -> Int -> Text.Text -> Builder -> [Builder]
generateValidatedBinding jsVarB aliasB canopyNameB jsNameB arity canopyType callPathB =
  let args = if arity <= 0 then [] else map (\i -> "_" <> BB.intDec i) [0 .. arity - 1]
      argList = mconcat (List.intersperse ", " args)
      returnType = extractReturnType canopyType
      validatorExpr = typeToValidator returnType
      rawFunc = if arity > 1 then "(" <> jsNameB <> ".f||" <> jsNameB <> ")" else jsNameB
      wrappedCall = rawFunc <> "(" <> argList <> ")"
      validatedCall = validatorExpr <> "(" <> wrappedCall <> ", " <> callPathB <> ")"
      funcBody = "function(" <> argList <> ") { return " <> validatedCall <> "; }"
      wrapper = if arity <= 1 then mempty else "F" <> BB.intDec arity <> "("
      closing = if arity <= 1 then mempty else ")"
      binding = "var " <> jsVarB <> " = " <> wrapper <> funcBody <> closing <> ";"
      namespaceBinding = aliasB <> "." <> canopyNameB <> " = " <> jsVarB <> ";"
  in [binding, namespaceBinding]

-- TYPE VALIDATORS

-- | Extract return type from a function type signature.
--
-- For @"Int -> String -> Bool"@, returns @"Bool"@.
-- For non-function types, returns the whole type string.
-- Uses 'Text' to avoid intermediate @[Char]@ allocation.
--
-- @since 0.19.2
extractReturnType :: Text.Text -> Text.Text
extractReturnType typeStr =
  let tokens = Text.words typeStr
      arrowIndices = findArrowIndices tokens 0 []
  in if null arrowIndices
       then typeStr
       else Text.unwords (drop (maximum arrowIndices + 1) tokens)
  where
    findArrowIndices :: [Text.Text] -> Int -> [Int] -> [Int]
    findArrowIndices [] _ acc = acc
    findArrowIndices (t:ts) idx acc
      | t == "->" = findArrowIndices ts (idx + 1) (idx : acc)
      | otherwise = findArrowIndices ts (idx + 1) acc

-- | Convert a type string to a @$validate@ Builder expression.
--
-- Uses 'Text' input to avoid intermediate @[Char]@ allocation.
--
-- @since 0.19.2
typeToValidator :: Text.Text -> Builder
typeToValidator typeStr =
  case Validator.parseFFIType typeStr of
    Just ffiType -> ffiTypeToValidator ffiType
    Nothing -> "$validate.Any"

-- | Convert FFIType to $validate expression as a Builder.
ffiTypeToValidator :: Validator.FFIType -> Builder
ffiTypeToValidator ffiType = case ffiType of
  Validator.FFIInt -> "$validate.Int"
  Validator.FFIFloat -> "$validate.Float"
  Validator.FFIString -> "$validate.String"
  Validator.FFIBool -> "$validate.Bool"
  Validator.FFIUnit -> "$validate.Unit"
  Validator.FFIList inner ->
    "$validate.List(" <> ffiTypeToValidator inner <> ")"
  Validator.FFIMaybe inner ->
    "$validate.Maybe(" <> ffiTypeToValidator inner <> ")"
  Validator.FFIResult errType valType ->
    "$validate.Result(" <> ffiTypeToValidator errType <> ", " <> ffiTypeToValidator valType <> ")"
  Validator.FFITask errType valType ->
    "$validate.Task(" <> ffiTypeToValidator errType <> ", " <> ffiTypeToValidator valType <> ")"
  Validator.FFITuple types ->
    "$validate.Tuple(" <> mconcat (List.intersperse ", " (map ffiTypeToValidator types)) <> ")"
  Validator.FFITypeVar _ ->
    "$validate.Any"
  Validator.FFIOpaque name _ ->
    "$validate.Opaque('" <> BB.byteString (TextEnc.encodeUtf8 name) <> "')"
  Validator.FFIFunctionType _ _ ->
    "$validate.Function"
  Validator.FFIRecord fields ->
    "$validate.Record([" <> fieldList <> "])"
    where
      fieldList = mconcat (List.intersperse ", " (map emitField fields))
      emitField (name, fieldTy) =
        "['" <> BB.byteString (TextEnc.encodeUtf8 name) <> "', " <> ffiTypeToValidator fieldTy <> "]"

-- UTILITIES

-- | Materialize a 'Builder' to a strict 'ByteString'.
materializeFFI :: Builder -> ByteString
materializeFFI = BL.toStrict . BB.toLazyByteString

-- | Trim leading and trailing whitespace from text.
--
-- Uses 'Text.strip' for O(n) whitespace removal without intermediate
-- @[Char]@ allocation.
--
-- @since 0.19.2
trim :: Text.Text -> Text.Text
trim = Text.strip

-- | Check whether a string is a valid JavaScript identifier.
--
-- Valid identifiers start with a letter, underscore, or dollar sign,
-- and subsequent characters may also include digits. This is used
-- as a defense-in-depth check for FFI names injected into generated
-- JavaScript code.
--
-- @since 0.19.2
isValidJsIdentifier :: String -> Bool
isValidJsIdentifier (c : cs) = isValidFirst c && all isValidRest cs
  where
    isValidFirst x = Char.isAlpha x || x == '_' || x == '$'
    isValidRest x = Char.isAlphaNum x || x == '_' || x == '$'
isValidJsIdentifier [] = False

-- | Replace every character not valid in a JS identifier with @_@.
--
-- Used to turn a file basename (e.g. @\"platform-cmd\"@) into a safe fragment
-- for an IIFE variable name, ensuring that multiple FFI files sharing the
-- same alias still receive distinct variable names.
--
-- @since 0.19.2
sanitizeForIdent :: String -> String
sanitizeForIdent = map (\c -> if Char.isAlphaNum c || c == '_' then c else '_')

-- | Escape text for safe inclusion in a JavaScript string literal.
--
-- Produces a 'Builder' directly, avoiding intermediate @[Char]@ allocation.
-- Escapes all characters that could break out of or corrupt a JS string:
--
-- * Backslash (@\\@) -- escape character itself
-- * Single quote (@\'@) -- string delimiter
-- * Double quote (@\"@) -- defense-in-depth for double-quoted contexts
-- * Newline (@\\n@) -- line terminator
-- * Carriage return (@\\r@) -- line terminator
-- * Null byte (@\\0@) -- string terminator in some engines
-- * U+2028 LINE SEPARATOR -- JS line terminator (pre-ES2019)
-- * U+2029 PARAGRAPH SEPARATOR -- JS line terminator (pre-ES2019)
--
-- @since 0.19.2
escapeJsString :: Text.Text -> Builder
escapeJsString = Text.foldl' (\b c -> b <> escapeJsChar c) mempty

escapeJsChar :: Char -> Builder
escapeJsChar '\\' = "\\\\"
escapeJsChar '\'' = "\\'"
escapeJsChar '"' = "\\\""
escapeJsChar '\n' = "\\n"
escapeJsChar '\r' = "\\r"
escapeJsChar '\0' = "\\0"
escapeJsChar '\x2028' = "\\u2028"
escapeJsChar '\x2029' = "\\u2029"
escapeJsChar c = BB.charUtf8 c

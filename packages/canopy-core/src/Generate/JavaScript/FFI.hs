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
import qualified Data.ByteString.Char8 as BS8
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified FFI.TypeParser as TypeParser
import qualified Generate.JavaScript.Builder as JS
import Generate.JavaScript.Builder (Expr, Stmt, stmtToJS, noAnnot, spaceAnnot, leadingSpaceAnnot)
import qualified Generate.JavaScript.FFI.Minify as FFIMinify
import qualified Generate.JavaScript.FFI.Registry as FFIRegistry
import qualified Generate.JavaScript.Name as JsName
import qualified Language.JavaScript.Parser.AST as JSAST
import qualified Language.JavaScript.Pretty.Printer as JSPrint
import qualified Language.JavaScript.Process.Minify as JSMinify
import qualified Blaze.ByteString.Builder as Blaze
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
    fileResults = buildAliasRegistries ffiInfos
    fileRegistries = Map.map FFIRegistry._frrRegistry fileResults
    initialSeeds = computeInitialSeeds ffiInfos usedFuncs fileRegistries
    resolvedNeeded = FFIRegistry.closeFFICrossFileDeps fileRegistries initialSeeds
    parts =
      [ "\n// FFI JavaScript content and bindings\n"
      ]
        ++ Map.foldrWithKey (formatFFIWithBindings mode graph usedFuncs fileResults resolvedNeeded) [] ffiInfos
    validators =
      if Mode.isFFIStrict mode
        then generateFFIValidators mode ffiInfos usedFuncs
        else mempty

-- | Build per-file FFI registry results for all FFI files.
--
-- Keyed by file path (not alias name) to avoid collisions when multiple
-- modules share the same FFI alias (e.g. Platform, Platform.Cmd, and
-- Platform.Sub all use PlatformFFI but import different JS files).
--
-- Each result carries both the per-block registry (for tree-shaking) and
-- the full AST (for the non-tree-shaken emit path), produced from a
-- single parse per file.
buildAliasRegistries
  :: Map String FFIInfo
  -> Map String FFIRegistry.FFIRegistryResult
buildAliasRegistries =
  Map.map (\info -> FFIRegistry.buildFFIRegistryFull (_ffiContent info))

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

-- | Generate deduplicated FFI validators for used function return types.
--
-- Only generates validators for functions that are actually used
-- (from 'usedFuncs'). Validators for shared sub-types (e.g. 'String',
-- 'Int') are emitted exactly once regardless of how many functions
-- reference them.
--
-- When 'usedFuncs' is empty (no usage tracking active), falls back to
-- generating validators for all exported functions in the file.
--
-- @since 0.20.3
generateFFIValidators
  :: Mode.Mode
  -> Map String FFIInfo
  -> Map Name.Name (Set Name.Name)
  -> Builder
generateFFIValidators mode ffiInfos usedFuncs =
  if Map.null ffiInfos
     then mempty
     else "\n// FFI type validators (generated by canopy)\n"
            <> BB.byteString (TextEnc.encodeUtf8 (Validator.generateAllValidatorsDeduped config allReturnTypes))
  where
    config = modeToValidatorConfig mode
    allReturnTypes = Map.foldr collectReturnTypes [] ffiInfos
    collectReturnTypes info acc =
      let alias = _ffiAlias info
          neededNames = Map.findWithDefault Set.empty alias usedFuncs
          functions = extractCanopyTypeFunctions (Text.lines (_ffiContent info))
          filtered = if Map.null usedFuncs || Set.null neededNames
                     then functions
                     else List.filter (isUsed neededNames . fst) functions
       in [rt | (_, ts) <- filtered, Just rt <- [Validator.parseReturnType ts]] ++ acc
    isUsed neededNames nm =
      Set.member (Name.fromChars (Text.unpack nm)) neededNames

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
-- Uses pre-computed registry results and resolved needed blocks from
-- 'closeFFICrossFileDeps' for precise cross-file dependency resolution.
--
-- All content emission is AST-based. The only place raw 'Text' is encoded
-- directly is when the JS file failed to parse (empty '_frrFullAST'), in
-- which case we have no AST and must fall back to the raw source bytes.
formatFFIWithBindings
  :: Mode.Mode
  -> Graph
  -> Map Name.Name (Set Name.Name)
  -> Map String FFIRegistry.FFIRegistryResult
  -> Map String (Set FFIRegistry.FFIBlockId)
  -> String
  -> FFIInfo
  -> [Builder]
  -> [Builder]
formatFFIWithBindings mode graph usedFuncs fileResults resolvedNeeded _key info acc
  | not (isValidJsIdentifier aliasStr) = acc
  -- Skip this entire FFI file when none of its functions are reachable from
  -- the entry point(s). This is only applied when tracking isActive (i.e.
  -- usedFuncs is non-empty); an empty map means "unknown" and includes all.
  --
  -- Exception: kernel-bridging FFI files (alias ends with "FFI", e.g.
  -- "JsonFFI") must never be skipped even when tracking shows zero hits.
  -- Their compiled Canopy callers emit Opt.VarRuntime references that
  -- bypass the global-graph tracker, so computeFFIUsage never adds them
  -- to usedFuncs. Any such file present in ffiInfos is a genuine
  -- dependency; omitting it produces "_Json_decodeField is not defined".
  | Set.null neededFuncNames && not (Map.null usedFuncs) && not hasKernelReExports = acc
  | otherwise =
      wrappedContent (reExports ++ bindingsSection ++ acc)
  where
    path = _ffiFilePath info
    contentText = _ffiContent info
    alias = _ffiAlias info
    aliasStr = Name.toChars alias
    hasKernelReExports = case stripFFISuffix aliasStr of { Just _ -> True; Nothing -> False }
    iifeVar = "_" <> sanitizeForIdent (takeBaseName path) <> "_" <> aliasStr <> "IIFE"
    iifeVarText = Text.pack iifeVar
    functions = extractFFIFunctions (Text.lines contentText)
    jsNames = List.map jsReferenceName functions

    -- Tree-shake: determine which functions are actually needed
    neededFuncNames = Map.findWithDefault Set.empty alias usedFuncs
    filteredFunctions = filterNeededFunctions functions neededFuncNames
    -- When the alias-level filter matches nothing in THIS specific file (because
    -- the alias is shared across multiple FFI files, e.g. PlatformFFI is shared
    -- by platform.js, platform-cmd.js and platform-sub.js), fall back to ALL
    -- functions in the file.  The guard above already ensured that the file as a
    -- whole is reachable (neededFuncNames is non-empty); an empty filteredFunctions
    -- just means none of this file's exports happened to match the tracked set,
    -- which occurs for kernel-only FFI files whose functions are referenced via
    -- Opt.VarKernel rather than through the regular global-reference tracker.
    neededFunctions = if null filteredFunctions then functions else filteredFunctions

    -- Extract per-file registry result and resolved needed blocks
    emptyResult = FFIRegistry.FFIRegistryResult Map.empty []
    result = Map.findWithDefault emptyResult path fileResults
    ffiRegistry = FFIRegistry._frrRegistry result
    fullAST = FFIRegistry._frrFullAST result
    allNeeded = Map.findWithDefault Set.empty path resolvedNeeded

    -- Decide between tree-shaken (per-block) and full-file (complete AST) paths
    treeShaken = Map.null ffiRegistry || Set.null allNeeded
    isProd = case mode of Mode.Prod {} -> True; _ -> False

    -- For the tree-shaken path: apply debug elimination to selected blocks, render.
    -- For the full-file path: render the complete parsed AST.
    -- The ONLY place raw Text enters the output is when the file failed to parse
    -- (fullAST is empty), meaning we genuinely have no AST available.
    processedRegistry =
      if isProd
        then Map.map applyDebugStrip ffiRegistry
        else ffiRegistry
    applyDebugStrip block =
      FFIRegistry.FFIBlock
        (FFIMinify.stripDebugBranches (FFIRegistry._fbStatements block))
        (FFIRegistry._fbJSDoc block)
        (FFIRegistry._fbDeps block)
        (FFIRegistry._fbAllFreeVars block)
        (FFIRegistry._fbOrder block)

    -- Only export names that exist in needed blocks
    neededInternalNames =
      if treeShaken
        then extractInternalNames (Text.lines contentText)
        else filterNeededInternals (extractInternalNames (Text.lines contentText)) ffiRegistry allNeeded
    allExportNames =
      if treeShaken
        then jsNames ++ neededInternalNames
        else List.map jsReferenceName neededFunctions ++ neededInternalNames

    -- Build the IIFE body statements.
    -- When the registry is empty (parse failure), fullAST is also empty and we
    -- fall back to raw text for the FFI content. Otherwise we use AST.
    -- For treeShaken: use fullAST, apply debug strip if needed.
    -- For non-treeShaken: processedRegistry already has debug stripping applied per-block.
    hasParsedAST = not (null fullAST) || not (Map.null ffiRegistry)

    iifeBodyStmts
      | not hasParsedAST = []   -- parse failure: handled by text fallback
      | treeShaken       = if isProd then FFIMinify.stripDebugBranches fullAST else fullAST
      | otherwise        = FFIRegistry.collectNeededStatements processedRegistry allNeeded

    -- Return expression: { name1: name1, ... }
    returnJSStmt = stmtToJS (JS.Return (buildIIFEReturnExpr allExportNames))

    -- var _iifeVar = (function() { body; return {...}; })();
    iifeJSStmt = buildIIFEJSVarStmt (BS8.pack iifeVar) (iifeBodyStmts ++ [returnJSStmt])
    iifeProgram = JSAST.JSAstProgram [iifeJSStmt] JSAST.JSNoAnnot
    iifeProgram' = if isProd then JSMinify.minifyJS iifeProgram else iifeProgram

    -- Post-IIFE: re-exports, namespace init, bindings — all as JS.Stmt then unified JSAST
    iifeJsName   = JsName.fromBuilder (BB.stringUtf8 iifeVar)
    aliasJsName  = JsName.fromBuilder (BB.stringUtf8 aliasStr)
    iifeFunctions = List.map (iifeExtractedFFI iifeVarText) neededFunctions
    bindingJsStmts = concatMap (generateFFIBinding mode graph path aliasStr) iifeFunctions
    reExportJsStmts =
      List.map (reExportInternalStmt iifeJsName) neededInternalNames
        ++ kernelReExportJsStmts aliasStr iifeJsName neededFunctions
    nsJsStmt = [namespaceInitStmt aliasJsName | not (null bindingJsStmts)]
    allPostJsStmts = reExportJsStmts ++ nsJsStmt ++ bindingJsStmts
    postProgram = JSAST.JSAstProgram (map stmtToJS allPostJsStmts) JSAST.JSNoAnnot
    postProgram' = if isProd then JSMinify.minifyJS postProgram else postProgram

    renderProg p = BB.lazyByteString (Blaze.toLazyByteString (JSPrint.renderJS p))

    -- Assemble final output builders
    wrappedContent rest
      | not hasParsedAST =
          -- Parse failure fallback: use text-based IIFE wrapping
          ("\n// From " <> BB.stringUtf8 path <> " (IIFE-isolated)\n")
            : ("var " <> BB.stringUtf8 iifeVar <> " = (function() {\n")
            : BB.byteString (TextEnc.encodeUtf8 contentText)
            : ("\nreturn " <> buildIIFEReturnObjFallback allExportNames <> ";\n")
            : "})();\n"
            : rest
      | otherwise =
          ("\n// From " <> BB.stringUtf8 path <> " (IIFE-isolated)\n")
            : renderProg iifeProgram'
            : "\n"
            : rest

    reExports = []   -- handled inside allPostJsStmts
    bindingsSection =
      if null allPostJsStmts
        then []
        else [ "\n// Bindings for " <> BB.stringUtf8 path <> "\n"
             , renderProg postProgram'
             , "\n"
             ]


-- | Filter extracted FFI functions to only those actually used.
--
-- Returns an empty list when 'neededNames' is empty — the caller is
-- responsible for deciding whether to skip the file entirely. This
-- changed from the previous "empty set means include all" fallback,
-- which was a workaround for the old 'Map.empty' usedFuncs argument.
filterNeededFunctions :: [ExtractedFFI] -> Set Name.Name -> [ExtractedFFI]
filterNeededFunctions functions neededNames =
  List.filter isNeeded functions
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

-- | Generate kernel-style re-export statements for @\@name@-annotated FFI functions.
--
-- When an FFI alias ends with @\"FFI\"@ (e.g. @VirtualDomFFI@), the codegen
-- may reference functions using the kernel naming convention
-- @_ModuleName_funcName@ (e.g. @_VirtualDom_init@). This function emits
-- re-exports from the IIFE to create those global bindings.
--
-- @since 0.19.2
kernelReExportJsStmts :: String -> JsName.Name -> [ExtractedFFI] -> [Stmt]
kernelReExportJsStmts aliasStr iifeJsName functions =
  case stripFFISuffix aliasStr of
    Nothing -> []
    Just kernelBase ->
      concatMap (mkKernelReExportStmt kernelBase iifeJsName) functions

-- | Strip the @\"FFI\"@ suffix from an alias name.
stripFFISuffix :: String -> Maybe String
stripFFISuffix s =
  fmap Text.unpack (Text.stripSuffix "FFI" (Text.pack s))

-- | Emit a single kernel re-export statement for an FFI function.
--
-- Produces @var _Module_funcName = _AliasIIFE.funcName;@ as a 'Stmt'.
mkKernelReExportStmt :: String -> JsName.Name -> ExtractedFFI -> [Stmt]
mkKernelReExportStmt kernelBase iifeJsName ef =
  let funcNameText = jsReferenceName ef
      kernelJsName = JsName.fromBuilder (BB.stringUtf8 ("_" ++ kernelBase ++ "_" ++ Text.unpack funcNameText))
      funcJsName   = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 funcNameText))
   in [JS.Var kernelJsName (JS.Access (JS.Ref iifeJsName) funcJsName)]

-- | Build a 'Stmt' re-exporting an internal @_@-prefixed name from the IIFE.
--
-- Produces @var _Json_unwrap = _JsonFFIIIFE._Json_unwrap;@ so that other
-- FFI files can reference these conventionally-scoped helper functions.
reExportInternalStmt :: JsName.Name -> Text.Text -> Stmt
reExportInternalStmt iifeJsName name =
  JS.Var nameJsName (JS.Access (JS.Ref iifeJsName) nameJsName)
  where
    nameJsName = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 name))

-- | Build the IIFE return object expression: @{ name1: name1, name2: name2, ... }@.
buildIIFEReturnExpr :: [Text.Text] -> Expr
buildIIFEReturnExpr names =
  JS.Object
    [ (n, JS.Ref n)
    | name <- names
    , let n = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 name))
    ]

-- | Text-based IIFE return object for the parse-failure fallback path.
--
-- Only used when the FFI file could not be parsed into an AST, which is a
-- rare error condition. All normal paths use 'buildIIFEReturnExpr'.
buildIIFEReturnObjFallback :: [Text.Text] -> Builder
buildIIFEReturnObjFallback names =
  "{ " <> entries <> " }"
  where
    entries = mconcat (List.intersperse ", " (List.map mkEntry names))
    mkEntry n =
      let b = BB.byteString (TextEnc.encodeUtf8 n)
       in b <> ": " <> b

-- | Build a namespace initialisation statement: @var Alias = Alias || {};@
namespaceInitStmt :: JsName.Name -> Stmt
namespaceInitStmt aliasJsName =
  JS.Var aliasJsName (JS.Infix JS.OpOr (JS.Ref aliasJsName) (JS.Object []))

-- | Build the @var _iifeVar = (function() { body })();@ JSStatement.
--
-- Constructs the IIFE wrapper directly in the @language-javascript@ AST so
-- that the IIFE body (which may include pre-parsed registry statements) and
-- the generated bindings can be rendered as a single unified program subject
-- to minification.
buildIIFEJSVarStmt :: BS8.ByteString -> [JSAST.JSStatement] -> JSAST.JSStatement
buildIIFEJSVarStmt iifeVarBS bodyStmts =
  JSAST.JSVariable noAnnot
    (JSAST.JSLOne (JSAST.JSVarInitExpression
      (JSAST.JSIdentifier leadingSpaceAnnot iifeVarBS)
      (JSAST.JSVarInit spaceAnnot iifeCallExpr)))
    (JSAST.JSSemi noAnnot)
  where
    iifeFuncExpr = JSAST.JSFunctionExpression
      leadingSpaceAnnot JSAST.JSIdentNone noAnnot JSAST.JSLNil noAnnot
      (JSAST.JSBlock noAnnot bodyStmts noAnnot)
    iifeCallExpr = JSAST.JSCallExpression
      (JSAST.JSExpressionParen noAnnot iifeFuncExpr noAnnot)
      noAnnot JSAST.JSLNil noAnnot

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

-- | Build a 'JsName.Name' for an FFI argument: @_0@, @_1@, ...
ffiArgName :: Int -> JsName.Name
ffiArgName i = JsName.fromBuilder ("_" <> BB.intDec i)

-- | Build the global binding variable name: @$author$project$Alias$func@.
ffiVarName :: String -> String -> JsName.Name
ffiVarName alias canopyName =
  JsName.fromBuilder (BB.stringUtf8 ("$author$project$" ++ alias ++ "$" ++ canopyName))

-- | Build a simple (unvalidated) function value expression.
--
-- For arity > 1 wraps @(fn.f||fn)@ with @F<N>()@ for Canopy's currying
-- protocol. For arity <= 1 references the function directly.
buildSimpleExpr :: JsName.Name -> Int -> Expr
buildSimpleExpr jsRefName arity
  | arity > 1 =
      wrapArityExpr arity
        (JS.Infix JS.OpOr
          (JS.Access (JS.Ref jsRefName) (JsName.fromBuilder "f"))
          (JS.Ref jsRefName))
  | otherwise = JS.Ref jsRefName

-- | Build a validated function value expression using @$validate.*@ wrappers.
--
-- Arity 0 (value): validates the value directly.
-- Arity >= 1 (function): wraps the call in a function that validates the result.
buildValidatedExpr :: JsName.Name -> Int -> Text.Text -> Text.Text -> Expr
buildValidatedExpr jsRefName arity canopyType callPath =
  let validatorE = typeToValidatorExpr (extractReturnType canopyType)
      callPathE  = JS.String (BB.byteString (TextEnc.encodeUtf8 callPath))
  in if arity <= 0
     then JS.Call validatorE [JS.Ref jsRefName, callPathE]
     else
       let args     = map ffiArgName [0 .. arity - 1]
           rawFunc
             | arity > 1 =
                 JS.Infix JS.OpOr
                   (JS.Access (JS.Ref jsRefName) (JsName.fromBuilder "f"))
                   (JS.Ref jsRefName)
             | otherwise = JS.Ref jsRefName
           inner    = JS.Call rawFunc (map JS.Ref args)
           validated = JS.Call validatorE [inner, callPathE]
           funcE    = JS.Function Nothing args [JS.Return validated]
       in wrapArityExpr arity funcE

-- | Emit the two canonical binding statements: var decl + namespace assignment.
makeBindingStmts :: JsName.Name -> JsName.Name -> JsName.Name -> Expr -> [Stmt]
makeBindingStmts varName aliasJsName propJsName valueExpr =
  [ JS.Var varName valueExpr
  , JS.ExprStmt (JS.Assign (JS.LDot (JS.Ref aliasJsName) propJsName) (JS.Ref varName))
  ]

-- | Generate JavaScript AST statements for an extracted FFI function binding.
--
-- Validates that the function name is a safe JavaScript identifier
-- before generating any code. For binding modes other than 'FunctionCall',
-- generates inline JavaScript expressions (method calls, property access,
-- constructor invocations) instead of delegating to a JS function.
--
-- @since 0.20.4
generateFFIBinding :: Mode.Mode -> Graph -> String -> String -> ExtractedFFI -> [Stmt]
generateFFIBinding mode _graph _filePath alias ef
  | not (isValidJsIdentifier canopyName) = []
  | otherwise =
      case _extractedMode ef of
        FunctionCall          -> generateFunctionCallBinding mode alias ef
        MethodCall methodName -> generateMethodBinding alias ef methodName
        PropertyGet propName  -> generatePropertyGetBinding alias ef propName
        PropertySet propName  -> generatePropertySetBinding alias ef propName
        ConstructorCall cls   -> generateConstructorBinding alias ef cls
  where
    canopyName = Text.unpack (effectiveName ef)

-- | Generate binding statements for a standard function call.
generateFunctionCallBinding :: Mode.Mode -> String -> ExtractedFFI -> [Stmt]
generateFunctionCallBinding mode alias ef =
  makeBindingStmts varName aliasJsName canopyJsName valueExpr
  where
    canopyNameText = effectiveName ef
    canopyName     = Text.unpack canopyNameText
    canopyTypeText = _extractedType ef
    arity          = maybe 0 TypeParser.countArity (TypeParser.parseType canopyTypeText)
    varName        = ffiVarName alias canopyName
    aliasJsName    = JsName.fromBuilder (BB.stringUtf8 alias)
    canopyJsName   = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 canopyNameText))
    jsRefName      = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 (jsReferenceName ef)))
    callPath       = Text.pack alias <> "." <> canopyNameText
    valueExpr
      | Mode.isFFIStrict mode = buildValidatedExpr jsRefName arity canopyTypeText callPath
      | otherwise             = buildSimpleExpr jsRefName arity

-- | Generate binding statements for a method call: @obj.method(args)@.
generateMethodBinding :: String -> ExtractedFFI -> Text.Text -> [Stmt]
generateMethodBinding alias ef methodName =
  makeBindingStmts varName aliasJsName nameJsName funcExpr
  where
    canopyNameText = effectiveName ef
    canopyName     = Text.unpack canopyNameText
    arity          = maybe 0 TypeParser.countArity (TypeParser.parseType (_extractedType ef))
    varName        = ffiVarName alias canopyName
    aliasJsName    = JsName.fromBuilder (BB.stringUtf8 alias)
    nameJsName     = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 canopyNameText))
    methodJsName   = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 methodName))
    args           = map ffiArgName [0 .. arity - 1]
    body           = JS.Call (JS.Access (JS.Ref (ffiArgName 0)) methodJsName) (map JS.Ref (drop 1 args))
    funcExpr       = wrapArityExpr arity (JS.Function Nothing args [JS.Return body])

-- | Generate binding statements for a property getter: @obj.propName@.
generatePropertyGetBinding :: String -> ExtractedFFI -> Text.Text -> [Stmt]
generatePropertyGetBinding alias ef propName =
  makeBindingStmts varName aliasJsName nameJsName funcExpr
  where
    canopyNameText = effectiveName ef
    canopyName     = Text.unpack canopyNameText
    varName        = ffiVarName alias canopyName
    aliasJsName    = JsName.fromBuilder (BB.stringUtf8 alias)
    nameJsName     = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 canopyNameText))
    propJsName     = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 propName))
    arg0           = ffiArgName 0
    funcExpr       = JS.Function Nothing [arg0] [JS.Return (JS.Access (JS.Ref arg0) propJsName)]

-- | Generate binding statements for a property setter: @obj.propName = val@.
generatePropertySetBinding :: String -> ExtractedFFI -> Text.Text -> [Stmt]
generatePropertySetBinding alias ef propName =
  makeBindingStmts varName aliasJsName nameJsName funcExpr
  where
    canopyNameText = effectiveName ef
    canopyName     = Text.unpack canopyNameText
    varName        = ffiVarName alias canopyName
    aliasJsName    = JsName.fromBuilder (BB.stringUtf8 alias)
    nameJsName     = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 canopyNameText))
    propJsName     = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 propName))
    arg0           = ffiArgName 0
    arg1           = ffiArgName 1
    assignBody     = JS.ExprStmt (JS.Assign (JS.LDot (JS.Ref arg0) propJsName) (JS.Ref arg1))
    funcExpr       = wrapArityExpr 2 (JS.Function Nothing [arg0, arg1] [assignBody])

-- | Generate binding statements for a constructor call: @new ClassName(args)@.
generateConstructorBinding :: String -> ExtractedFFI -> Text.Text -> [Stmt]
generateConstructorBinding alias ef className =
  makeBindingStmts varName aliasJsName nameJsName funcExpr
  where
    canopyNameText = effectiveName ef
    canopyName     = Text.unpack canopyNameText
    arity          = maybe 0 TypeParser.countArity (TypeParser.parseType (_extractedType ef))
    varName        = ffiVarName alias canopyName
    aliasJsName    = JsName.fromBuilder (BB.stringUtf8 alias)
    nameJsName     = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 canopyNameText))
    classJsName    = JsName.fromBuilder (BB.byteString (TextEnc.encodeUtf8 className))
    args           = map ffiArgName [0 .. arity - 1]
    body           = JS.New (JS.Ref classJsName) (map JS.Ref args)
    funcExpr       = wrapArityExpr arity (JS.Function Nothing args [JS.Return body])

-- | Wrap a function expression with @F\<N\>()@ for Canopy's currying protocol.
wrapArityExpr :: Int -> Expr -> Expr
wrapArityExpr arity funcExpr
  | arity <= 1 = funcExpr
  | otherwise  = JS.Call (JS.Ref (JsName.makeF arity)) [funcExpr]

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

-- | Convert a type string to a @$validate.*@ 'Expr' AST node.
--
-- Uses 'Text' input to avoid intermediate @[Char]@ allocation.
--
-- @since 0.20.4
typeToValidatorExpr :: Text.Text -> Expr
typeToValidatorExpr typeStr =
  case Validator.parseFFIType typeStr of
    Just ffiType -> ffiTypeToValidatorExpr ffiType
    Nothing      -> JS.Access validateRef (JsName.fromBuilder "Any")
  where
    validateRef = JS.Ref (JsName.fromBuilder (BB.stringUtf8 "$validate"))

-- | Convert an 'FFIType' to its @$validate.*@ 'Expr' AST node.
ffiTypeToValidatorExpr :: Validator.FFIType -> Expr
ffiTypeToValidatorExpr ffiType =
  let ref  = JS.Ref (JsName.fromBuilder (BB.stringUtf8 "$validate"))
      prop name = JS.Access ref (JsName.fromBuilder name)
      call name args = JS.Call (prop name) args
  in case ffiType of
    Validator.FFIInt               -> prop "Int"
    Validator.FFIFloat             -> prop "Float"
    Validator.FFIString            -> prop "String"
    Validator.FFIBool              -> prop "Bool"
    Validator.FFIUnit              -> prop "Unit"
    Validator.FFIList inner        -> call "List"   [ffiTypeToValidatorExpr inner]
    Validator.FFIMaybe inner       -> call "Maybe"  [ffiTypeToValidatorExpr inner]
    Validator.FFIResult e v        -> call "Result" [ffiTypeToValidatorExpr e, ffiTypeToValidatorExpr v]
    Validator.FFITask e v          -> call "Task"   [ffiTypeToValidatorExpr e, ffiTypeToValidatorExpr v]
    Validator.FFITuple ts          -> call "Tuple"  (map ffiTypeToValidatorExpr ts)
    Validator.FFITypeVar _         -> prop "Any"
    Validator.FFIFunctionType _ _  -> prop "Function"
    Validator.FFIOpaque name _     ->
      call "Opaque" [JS.String (BB.byteString (TextEnc.encodeUtf8 name))]
    Validator.FFIRecord fields     ->
      call "Record" [JS.Array (map emitField fields)]
      where
        emitField (name, ty) =
          JS.Array [ JS.String (BB.byteString (TextEnc.encodeUtf8 name))
                   , ffiTypeToValidatorExpr ty
                   ]

-- UTILITIES

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

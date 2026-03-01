{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | JavaScript generation for the Canopy compiler
--
-- WARNING: NO HARDCODING OF FFI FILE PATHS!
-- All FFI file paths MUST come from the actual foreign import statements
-- in the source code, NOT hardcoded values. This allows the FFI system
-- to work with ANY project structure and ANY file paths.
--
-- @since 0.19.1
module Generate.JavaScript
  ( generate,
    generateForRepl,
    generateForReplEndpoint,
    FFIInfo(..),
    ffiFilePath,
    ffiContent,
    ffiAlias,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Data.Char as Char
import Control.Lens (makeLenses)
import qualified Data.Binary as Binary
import qualified Canopy.Kernel as Kernel
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe
import qualified Canopy.Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified FFI.TypeParser as TypeParser
import qualified FFI.Validator as Validator
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.JavaScript.FFIRuntime as FFIRuntime
import qualified Generate.JavaScript.Functions as Functions
import qualified Generate.JavaScript.Kernel as Kernel_
import qualified Generate.JavaScript.Minify as Minify
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.SourceMap as SourceMap
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import qualified Reporting.InternalError as InternalError
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer
import Prelude hiding (cycle, print)

-- GENERATE

type Graph = Map Opt.Global Opt.Node

type Mains = Map ModuleName.Canonical Opt.Main

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

makeLenses ''FFIInfo

-- | Extract FFI alias names from FFI info map.
--
-- Used to identify which module names correspond to FFI modules vs application modules.
-- FFI modules use direct JavaScript access, while application modules use qualified names.
--
-- @since 0.19.1
extractFFIAliases :: Map String FFIInfo -> Set Name.Name
extractFFIAliases ffiInfos =
  Set.fromList (map _ffiAlias (Map.elems ffiInfos))

-- | Generate FFI JavaScript content to include in bundle.
--
-- Receives FFI information directly through the compilation pipeline
-- instead of using global storage, eliminating MVar deadlock issues.
-- When FFI strict mode is enabled, also generates runtime validators.
generateFFIContent :: Mode.Mode -> Graph -> Map String FFIInfo -> Builder
generateFFIContent mode graph ffiInfos =
  if Map.null ffiInfos
     then mempty
     else mconcat parts <> validators
  where
    parts =
      [ "\n// FFI JavaScript content from external files\n" ]
        ++ Map.foldrWithKey formatFFIFileFromInfo [] ffiInfos
        ++ [ "\n// FFI function bindings\n" ]
        ++ Map.foldrWithKey (generateFFIBindingsFromInfo mode graph) [] ffiInfos
    validators =
      if Mode.isFFIStrict mode
        then generateFFIValidators mode ffiInfos
        else mempty

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
      let contentStr = Text.unpack (_ffiContent info)
          functions = extractCanopyTypeFunctions (lines contentStr)
          validatorBuilders = concatMap (generateValidatorForFunction config) functions
      in validatorBuilders ++ acc

-- | Generate a validator builder for a single FFI function.
generateValidatorForFunction :: Validator.ValidatorConfig -> (String, String) -> [Builder]
generateValidatorForFunction config (_funcName, typeStr) =
  case Validator.parseReturnType (Text.pack typeStr) of
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

-- | Format FFI file content for inclusion using FFIInfo.
formatFFIFileFromInfo :: String -> FFIInfo -> [Builder] -> [Builder]
formatFFIFileFromInfo _key info acc =
  ("\n// From " <> BB.stringUtf8 (_ffiFilePath info) <> "\n")
    : BB.byteString (TextEnc.encodeUtf8 (_ffiContent info))
    : "\n"
    : acc

-- | Generate JavaScript variable bindings for FFI functions using FFIInfo with proper aliases.
generateFFIBindingsFromInfo :: Mode.Mode -> Graph -> String -> FFIInfo -> [Builder] -> [Builder]
generateFFIBindingsFromInfo mode graph _key info acc
  | not (isValidJsIdentifier alias) = acc
  | otherwise =
      case extractFFIFunctionBindings mode graph path contentStr alias of
        [] -> acc
        bindings ->
          ("\n// Bindings for " <> BB.stringUtf8 path <> "\n")
            : ("var " <> BB.stringUtf8 alias <> " = " <> BB.stringUtf8 alias <> " || {};\n")
            : map (<> "\n") bindings ++ ["\n"] ++ acc
  where
    path = _ffiFilePath info
    contentStr = Text.unpack (_ffiContent info)
    alias = Name.toChars (_ffiAlias info)

-- | Extract and generate bindings for FFI functions from JavaScript content.
extractFFIFunctionBindings :: Mode.Mode -> Graph -> String -> String -> String -> [Builder]
extractFFIFunctionBindings mode graph path content alias =
  concatMap (generateFunctionBinding mode graph path alias) functions
  where
    functions = extractCanopyTypeFunctions (lines content)

-- Extract functions that have @canopy-type annotations
extractCanopyTypeFunctions :: [String] -> [(String, String)]
extractCanopyTypeFunctions [] = []
extractCanopyTypeFunctions (line:rest) =
  case extractCanopyType line of
    Just canopyType ->
      case findFunctionName rest of
        Just funcName -> (funcName, canopyType) : extractCanopyTypeFunctions rest
        Nothing -> extractCanopyTypeFunctions rest
    Nothing -> extractCanopyTypeFunctions rest

-- Extract @canopy-type annotation from a line
extractCanopyType :: String -> Maybe String
extractCanopyType line =
  if " * @canopy-type " `List.isInfixOf` line
    then case dropWhile (/= '@') line of
      ('@':'c':'a':'n':'o':'p':'y':'-':'t':'y':'p':'e':' ':typeStr) -> Just (trim typeStr)
      _ -> Nothing
    else Nothing

-- Find the function name in the following lines.
-- Handles both @function name(...)@ and @async function name(...)@.
findFunctionName :: [String] -> Maybe String
findFunctionName [] = Nothing
findFunctionName (line:rest) =
  let trimmed = trim line
      stripped = stripAsyncPrefix trimmed
  in if "function " `List.isPrefixOf` stripped
       then extractNameAfterFunction stripped
       else if "*/" `List.isInfixOf` line
         then findFunctionName rest
         else findFunctionName rest
  where
    stripAsyncPrefix s
      | "async " `List.isPrefixOf` s = trim (drop 6 s)
      | otherwise = s
    extractNameAfterFunction s =
      case dropWhile (/= ' ') s of
        (' ':after) ->
          case takeWhile (\c -> c /= '(' && c /= ' ') (trim after) of
            "" -> findFunctionName rest
            name -> Just name
        _ -> findFunctionName rest

-- | Generate JavaScript binding for a single function as Builders.
--
-- Validates that the function name is a safe JavaScript identifier
-- before generating any code. Invalid names are silently skipped,
-- preventing injection via crafted @\@name@ annotations.
--
-- @since 0.19.2
generateFunctionBinding :: Mode.Mode -> Graph -> String -> String -> (String, String) -> [Builder]
generateFunctionBinding mode _graph _filePath alias (funcName, canopyType)
  | not (isValidJsIdentifier funcName) = []
  | otherwise =
      let arity = maybe 0 TypeParser.countArity (TypeParser.parseType (Text.pack canopyType))
          jsVarName = "$author$project$" ++ alias ++ "$" ++ funcName
          callPath = "'" ++ escapeJsString (alias ++ "." ++ funcName) ++ "'"
      in if Mode.isFFIStrict mode
           then generateValidatedBinding jsVarName alias funcName arity canopyType callPath
           else generateSimpleBinding jsVarName alias funcName arity

-- | Generate simple binding without validation.
generateSimpleBinding :: String -> String -> String -> Int -> [Builder]
generateSimpleBinding jsVarName alias funcName arity =
  let jsVarB = BB.stringUtf8 jsVarName
      aliasB = BB.stringUtf8 alias
      funcNameB = BB.stringUtf8 funcName
      wrapper = if arity <= 1 then mempty else "F" <> BB.intDec arity <> "("
      closing = if arity <= 1 then mempty else ")"
      namespaceBinding = aliasB <> "." <> funcNameB <> " = " <> wrapper <> funcNameB <> closing <> ";"
  in ["var " <> jsVarB <> " = " <> wrapper <> funcNameB <> closing <> ";", namespaceBinding]

-- | Generate binding with runtime validation wrapper.
generateValidatedBinding :: String -> String -> String -> Int -> String -> String -> [Builder]
generateValidatedBinding jsVarName alias funcName arity canopyType callPath =
  let jsVarB = BB.stringUtf8 jsVarName
      aliasB = BB.stringUtf8 alias
      funcNameB = BB.stringUtf8 funcName
      callPathB = BB.stringUtf8 callPath
      args = if arity <= 0 then [] else map (\i -> "_" <> BB.intDec i) [0 .. arity - 1]
      argList = mconcat (List.intersperse ", " args)
      returnType = extractReturnType canopyType
      validatorExpr = typeToValidator returnType
      wrappedCall = funcNameB <> "(" <> argList <> ")"
      validatedCall = validatorExpr <> "(" <> wrappedCall <> ", " <> callPathB <> ")"
      funcBody = "function(" <> argList <> ") { return " <> validatedCall <> "; }"
      wrapper = if arity <= 1 then mempty else "F" <> BB.intDec arity <> "("
      closing = if arity <= 1 then mempty else ")"
      binding = "var " <> jsVarB <> " = " <> wrapper <> funcBody <> closing <> ";"
      namespaceBinding = aliasB <> "." <> funcNameB <> " = " <> jsVarB <> ";"
  in [binding, namespaceBinding]

-- | Extract return type from a function type signature.
extractReturnType :: String -> String
extractReturnType typeStr =
  let tokens = words typeStr
      arrowIndices = findArrowIndices tokens 0 []
  in if null arrowIndices
       then typeStr
       else unwords (drop (maximum arrowIndices + 1) tokens)
  where
    findArrowIndices :: [String] -> Int -> [Int] -> [Int]
    findArrowIndices [] _ acc = acc
    findArrowIndices (t:ts) idx acc
      | t == "->" = findArrowIndices ts (idx + 1) (idx : acc)
      | otherwise = findArrowIndices ts (idx + 1) acc

-- | Convert a type string to a $validate Builder expression.
typeToValidator :: String -> Builder
typeToValidator typeStr =
  case Validator.parseFFIType (Text.pack typeStr) of
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
  Validator.FFIOpaque name ->
    "$validate.Opaque('" <> BB.byteString (TextEnc.encodeUtf8 name) <> "')"
  Validator.FFIFunctionType _ _ ->
    "$validate.Function"
  Validator.FFIRecord _ ->
    "$validate.Record"

-- | Trim leading and trailing whitespace from a string.
trim :: String -> String
trim = List.dropWhileEnd isSpace . dropWhile isSpace
  where
    isSpace c = c `elem` [' ', '\t', '\n', '\r']

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

-- | Escape a string for safe inclusion in a JavaScript single-quoted literal.
--
-- Escapes backslashes and single quotes to prevent string breakout
-- when constructing JS string literals for FFI call paths.
--
-- @since 0.19.2
escapeJsString :: String -> String
escapeJsString = concatMap escapeJsChar
  where
    escapeJsChar '\\' = "\\\\"
    escapeJsChar '\'' = "\\'"
    escapeJsChar '\n' = "\\n"
    escapeJsChar '\r' = "\\r"
    escapeJsChar c = [c]

generate :: Mode.Mode -> Opt.GlobalGraph -> Mains -> Map String FFIInfo -> (Builder, Maybe SourceMap.SourceMap)
generate inputMode (Opt.GlobalGraph rawGraph _ sourceLocs) mains ffiInfos =
  let ffiAliases = extractFFIAliases ffiInfos
      (graph, mode) = case inputMode of
        Mode.Prod fields elmCompat ffiUnsafe ffiDbg _ _ ->
          let minified = Minify.minifyGraph rawGraph
              pool = StringPool.buildPool minified
           in (minified, Mode.Prod fields elmCompat ffiUnsafe ffiDbg pool ffiAliases)
        Mode.Dev debugTypes elmCompat ffiUnsafe ffiDbg _ ->
          (rawGraph, Mode.Dev debugTypes elmCompat ffiUnsafe ffiDbg ffiAliases)
      baseState = Map.foldrWithKey (addMain mode graph) (emptyState sourceLocs) mains
      shouldInclude global =
        not (Kernel_.isDebugger global && not (Mode.isDebug mode))
      filteredGraph = Map.filterWithKey (\global _ -> shouldInclude global) graph
      state = Map.foldlWithKey' (\s global _ -> addGlobal mode graph s global) baseState filteredGraph
      header = if Mode.isElmCompatible mode
               then "(function(scope){\n'use strict';\n"
               else "(function(scope){'use strict';\n"
      debuggerStub = "var _Debugger_unsafeCoerce = function(value) { return value; };\n"
      poolDecls = StringPool.poolDeclarations (Mode.stringPool mode)
      jsBuilder =
        header
          <> debuggerStub
          <> generateFFIContent mode graph ffiInfos
          <> Functions.functions
          <> FFIRuntime.embeddedRuntimeForMode mode
          <> perfNote mode
          <> poolDecls
          <> stateToBuilder state
          <> Kernel_.toMainExports mode mains
          <> "\nif (typeof global !== 'undefined') { global.Canopy = scope['Canopy']; global.Elm = scope['Elm']; }"
          <> "\n}(typeof window !== 'undefined' ? window : this));"
      sourceMap = buildSourceMap mode state
   in (jsBuilder, sourceMap)


addMain :: Mode.Mode -> Graph -> ModuleName.Canonical -> Opt.Main -> State -> State
addMain mode graph home _ state =
  addGlobal mode graph state (Opt.Global home "main")

perfNote :: Mode.Mode -> Builder
perfNote mode =
  case mode of
    Mode.Prod {} ->
      mempty
    Mode.Dev Nothing elmCompatible _ _ _ ->
      let optimizeUrl = if elmCompatible
                        then "https://canopy-lang.org/0.19.1/optimize"
                        else Doc.makeNakedLink "optimize"
      in JS.stmtToBuilder $
           JS.ExprStmtWithSemi $
             JS.Call
               (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "warn"))
               [ JS.String $
                   "Compiled in DEV mode. Follow the advice at "
                     <> BB.stringUtf8 optimizeUrl
                     <> " for better performance and smaller assets."
               ]
    Mode.Dev (Just _) elmCompatible _ _ _ ->
      let optimizeUrl = if elmCompatible
                        then "https://canopy-lang.org/0.19.1/optimize"
                        else Doc.makeNakedLink "optimize"
      in JS.stmtToBuilder $
           JS.ExprStmtWithSemi $
             JS.Call
               (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "warn"))
               [ JS.String $
                   "Compiled in DEBUG mode. Follow the advice at "
                     <> BB.stringUtf8 optimizeUrl
                     <> " for better performance and smaller assets."
               ]

-- GENERATE FOR REPL
generateForRepl :: Bool -> Localizer.Localizer -> Opt.GlobalGraph -> ModuleName.Canonical -> Name.Name -> Can.Annotation -> Builder
generateForRepl ansi localizer (Opt.GlobalGraph graph _ _) home name (Can.Forall _ tipe) =
  let mode = Mode.Dev Nothing True False False Set.empty
      debugState = addGlobal mode graph (emptyState Map.empty) (Opt.Global ModuleName.debug "toString")
      evalState = addGlobal mode graph debugState (Opt.Global home name)
      processExceptionHandler = JS.stmtToBuilder $
        JS.ExprStmt $
          JS.Call
            (JS.Access (JS.Ref (JsName.fromLocal "process")) (JsName.fromLocal "on"))
            [ JS.String "uncaughtException",
              JS.Function Nothing [JsName.fromLocal "err"] [
                JS.ExprStmt $ JS.Call
                  (JS.Access
                    (JS.Access (JS.Ref (JsName.fromLocal "process")) (JsName.fromLocal "stderr"))
                    (JsName.fromLocal "write"))
                  [ JS.Infix JS.OpAdd
                      (JS.Call
                        (JS.Access (JS.Ref (JsName.fromLocal "err")) (JsName.fromLocal "toString"))
                        [])
                      (JS.String "\\n")
                  ],
                JS.ExprStmt $ JS.Call
                  (JS.Access (JS.Ref (JsName.fromLocal "process")) (JsName.fromLocal "exit"))
                  [JS.Int 1]
              ]
            ]
   in processExceptionHandler
        <> Functions.functions
        <> stateToBuilder evalState
        <> print ansi localizer home name tipe

print :: Bool -> Localizer.Localizer -> ModuleName.Canonical -> Name.Name -> Can.Type -> Builder
print ansi localizer home name tipe =
  let value = JS.Ref (JsName.fromGlobal home name)
      toString = JS.Ref (JsName.fromKernel Name.debug "toAnsiString")
      tipeDoc = RT.canToDoc localizer RT.None tipe
      boolValue = if ansi then JS.Bool True else JS.Bool False
      valueVar = JS.Var (JsName.fromLocal "_value") $
        JS.Call toString [boolValue, value]
      typeVar = JS.Var (JsName.fromLocal "_type") $
        JS.String $ BB.stringUtf8 (show (Doc.toString tipeDoc))
      printFunc = JS.FunctionStmt (JsName.fromLocal "_print") [JsName.fromLocal "t"] [
        JS.ExprStmt $ JS.Call
          (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "log"))
          [ JS.Infix JS.OpAdd
              (JS.Ref (JsName.fromLocal "_value"))
              (JS.If boolValue
                (JS.Infix JS.OpAdd
                  (JS.Infix JS.OpAdd (JS.String "\\x1b[90m") (JS.Ref (JsName.fromLocal "t")))
                  (JS.String "\\x1b[0m"))
                (JS.Ref (JsName.fromLocal "t")))
          ]
        ]
      lengthCondition = JS.Infix JS.OpGe
        (JS.Infix JS.OpAdd
          (JS.Infix JS.OpAdd
            (JS.Access (JS.Ref (JsName.fromLocal "_value")) (JsName.fromLocal "length"))
            (JS.Int 3))
          (JS.Access (JS.Ref (JsName.fromLocal "_type")) (JsName.fromLocal "length")))
        (JS.Int 80)
      newlineCondition = JS.Infix JS.OpGe
        (JS.Call
          (JS.Access (JS.Ref (JsName.fromLocal "_type")) (JsName.fromLocal "indexOf"))
          [JS.String "\\n"])
        (JS.Int 0)
      condition = JS.Infix JS.OpOr lengthCondition newlineCondition
      ifStmt = JS.IfStmt condition
        (JS.ExprStmt $ JS.Call
          (JS.Ref (JsName.fromLocal "_print"))
          [ JS.Infix JS.OpAdd
              (JS.String "\\n    : ")
              (JS.Call
                (JS.Access
                  (JS.Call
                    (JS.Access (JS.Ref (JsName.fromLocal "_type")) (JsName.fromLocal "split"))
                    [JS.String "\\n"])
                  (JsName.fromLocal "join"))
                [JS.String "\\n      "])
          ])
        (JS.ExprStmt $ JS.Call
          (JS.Ref (JsName.fromLocal "_print"))
          [ JS.Infix JS.OpAdd (JS.String " : ") (JS.Ref (JsName.fromLocal "_type")) ]
        )
   in JS.stmtToBuilder $ JS.Block [valueVar, typeVar, printFunc, ifStmt]

-- GENERATE FOR REPL ENDPOINT

generateForReplEndpoint :: Localizer.Localizer -> Opt.GlobalGraph -> ModuleName.Canonical -> Maybe Name.Name -> Can.Annotation -> Builder
generateForReplEndpoint localizer (Opt.GlobalGraph graph _ _) home maybeName (Can.Forall _ tipe) =
  let name = Data.Maybe.fromMaybe Name.replValueToPrint maybeName
      mode = Mode.Dev Nothing True False False Set.empty
      debugState = addGlobal mode graph (emptyState Map.empty) (Opt.Global ModuleName.debug "toString")
      evalState = addGlobal mode graph debugState (Opt.Global home name)
   in Functions.functions
        <> stateToBuilder evalState
        <> postMessage localizer home maybeName tipe

postMessage :: Localizer.Localizer -> ModuleName.Canonical -> Maybe Name.Name -> Can.Type -> Builder
postMessage localizer home maybeName tipe =
  let name = Data.Maybe.fromMaybe Name.replValueToPrint maybeName
      value = JS.Ref (JsName.fromGlobal home name)
      toString = JS.Ref (JsName.fromKernel Name.debug "toAnsiString")
      tipeDoc = RT.canToDoc localizer RT.None tipe
      nameField = case maybeName of
        Nothing -> JS.Null
        Just n -> JS.String (Name.toBuilder n)
      messageObj = JS.Object
        [ (JsName.fromLocal "name", nameField),
          (JsName.fromLocal "value", JS.Call toString [JS.Bool True, value]),
          (JsName.fromLocal "type", JS.String $ BB.stringUtf8 (show (Doc.toString tipeDoc)))
        ]
      postMessageCall = JS.ExprStmt $
        JS.Call
          (JS.Access (JS.Ref (JsName.fromLocal "self")) (JsName.fromLocal "postMessage"))
          [messageObj]
   in JS.stmtToBuilder postMessageCall

-- GRAPH TRAVERSAL STATE

data State = State
  { _revKernels :: [Builder],
    _revBuilders :: [Builder],
    _seenGlobals :: Set Opt.Global,
    _seenKernelChunks :: Set ByteString,
    _outputLine :: !Int,
    _sourceMapMappings :: ![SourceMap.Mapping],
    _sourceLocations :: Map Opt.Global Ann.Region
  }

emptyState :: Map Opt.Global Ann.Region -> State
emptyState locs =
  State mempty [] Set.empty Set.empty 0 [] locs

stateToBuilder :: State -> Builder
stateToBuilder (State revKernels revBuilders _ _ _ _ _) =
  prependBuilders revKernels (prependBuilders revBuilders mempty)

prependBuilders :: [Builder] -> Builder -> Builder
prependBuilders revBuilders monolith =
  List.foldl' (flip (<>)) monolith revBuilders

-- ADD DEPENDENCIES

addGlobal :: Mode.Mode -> Graph -> State -> Opt.Global -> State
addGlobal mode graph state@(State revKernels builders seen seenChunks outLine smMappings srcLocs) global =
  if Set.member global seen
    then state
    else
      addGlobalHelp mode graph global $
        State revKernels builders (Set.insert global seen) seenChunks outLine smMappings srcLocs

filterEssentialDeps :: Mode.Mode -> Set Opt.Global -> Set Opt.Global
filterEssentialDeps mode deps =
  if Mode.isDebug mode
    then deps
    else Set.filter (not . Kernel_.isDebugger) deps

addGlobalHelp :: Mode.Mode -> Graph -> Opt.Global -> State -> State
addGlobalHelp mode graph currentGlobal state =
  let Opt.Global globalHome _ = currentGlobal
      pkg = ModuleName._package globalHome
      isFFIModule = Pkg._author pkg == Pkg._author Pkg.dummyName
                 && Pkg._project pkg == Pkg._project Pkg.dummyName
                 && Map.notMember currentGlobal graph
  in if Kernel_.isDebugger currentGlobal && not (Mode.isDebug mode)
     then state
     else if isFFIModule
     then state
     else continueAddGlobal mode graph currentGlobal state

continueAddGlobal :: Mode.Mode -> Graph -> Opt.Global -> State -> State
continueAddGlobal mode graph currentGlobal state =
  let addDeps deps someState =
        let filteredDeps = filterEssentialDeps mode deps
        in Set.foldl' (addGlobal mode graph) someState filteredDeps
      globalInGraph = resolveGlobal graph currentGlobal
  in dispatchNode mode graph currentGlobal addDeps globalInGraph state

resolveGlobal :: Graph -> Opt.Global -> Opt.Node
resolveGlobal graph currentGlobal =
  case Map.lookup currentGlobal graph of
    Just x -> x
    Nothing -> resolveAltGlobal graph currentGlobal

resolveAltGlobal :: Graph -> Opt.Global -> Opt.Node
resolveAltGlobal graph currentGlobal =
  let Opt.Global globalHome globalName = currentGlobal
      currentPkg = ModuleName._package globalHome
      moduleName = ModuleName._module globalHome
      isKernelModule = "Kernel." `List.isPrefixOf` Name.toChars moduleName
      isKernelPkg = Pkg._project currentPkg == Pkg._project Pkg.kernel
      (altPkg, altModuleName) = computeAltPkg currentPkg moduleName isKernelModule isKernelPkg
      altGlobalHome = ModuleName.Canonical altPkg altModuleName
      altGlobal = Opt.Global altGlobalHome globalName
  in case Map.lookup altGlobal graph of
       Just x -> x
       Nothing -> reportMissingGlobal graph currentGlobal altGlobal

computeAltPkg :: Pkg.Name -> Name.Name -> Bool -> Bool -> (Pkg.Name, Name.Name)
computeAltPkg currentPkg moduleName isKernelModule isKernelPkg
  | Pkg._author currentPkg == Pkg.elm && Pkg._project currentPkg == Pkg._project Pkg.core && isKernelModule =
      let kernelName = drop 7 (Name.toChars moduleName)
          kernelPkg = Pkg.Name Pkg.elm (Pkg._project Pkg.kernel)
      in (kernelPkg, Name.fromChars kernelName)
  | isKernelPkg && Pkg._author currentPkg == Pkg.elm =
      let kernelModuleName = "Kernel." ++ Name.toChars moduleName
      in (Pkg.core, Name.fromChars kernelModuleName)
  | isKernelPkg && Pkg._author currentPkg == Pkg.canopy =
      (Pkg.Name Pkg.elm (Pkg._project Pkg.kernel), moduleName)
  | otherwise = (currentPkg, moduleName)

reportMissingGlobal :: Graph -> Opt.Global -> Opt.Global -> Opt.Node
reportMissingGlobal graph currentGlobal altGlobal =
  InternalError.report
    "Generate.JavaScript.reportMissingGlobal"
    (Text.pack msg)
    (Text.pack ctx)
  where
    allKeys = Map.keys graph
    msg = "Missing global: " <> show currentGlobal <> ", also tried: " <> show altGlobal
    ctx = "Total keys: " <> show (length allKeys) <> ", first 20: " <> show (take 20 allKeys)

dispatchNode :: Mode.Mode -> Graph -> Opt.Global -> (Set Opt.Global -> State -> State) -> Opt.Node -> State -> State
dispatchNode mode graph currentGlobal addDeps globalInGraph state =
  case globalInGraph of
    Opt.Define expr deps ->
      addStmt (emitMapping currentGlobal (addDeps deps state)) (var currentGlobal (Expr.generate mode expr))
    Opt.DefineTailFunc argNames body deps ->
      addStmt (emitMapping currentGlobal (addDeps deps state))
        (let (Opt.Global _ name) = currentGlobal
             home = case currentGlobal of Opt.Global h _ -> h
         in JS.Var (JsName.fromGlobal home name) (Expr.generateTailDefExpr mode name argNames body))
    Opt.Ctor index arity ->
      addStmt (emitMapping currentGlobal state) (var currentGlobal (Expr.generateCtor mode currentGlobal index arity))
    Opt.Link linkedGlobal ->
      addGlobal mode graph state linkedGlobal
    Opt.Cycle names values functions deps ->
      let cycleStmt = Kernel_.generateCycle mode currentGlobal names values functions
          baseState = emitMapping currentGlobal (addDeps deps state)
      in case cycleStmt of
           JS.Block stmts -> List.foldl' addStmt baseState stmts
           stmt -> addStmt baseState stmt
    Opt.Manager effectsType ->
      generateManager mode graph currentGlobal effectsType state
    Opt.Kernel chunks deps ->
      addKernelChunks mode currentGlobal (addDeps deps state) chunks
    Opt.Enum index ->
      addStmt (emitMapping currentGlobal state) (Kernel_.generateEnum mode currentGlobal index)
    Opt.Box ->
      addStmt (emitMapping currentGlobal (addGlobal mode graph state Kernel_.identity)) (Kernel_.generateBox mode currentGlobal)
    Opt.PortIncoming decoder deps ->
      addStmt (emitMapping currentGlobal (addDeps deps state)) (Kernel_.generatePort mode currentGlobal "incomingPort" decoder)
    Opt.PortOutgoing encoder deps ->
      addStmt (emitMapping currentGlobal (addDeps deps state)) (Kernel_.generatePort mode currentGlobal "outgoingPort" encoder)

addKernelChunks :: Mode.Mode -> Opt.Global -> State -> [Kernel.Chunk] -> State
addKernelChunks mode currentGlobal (State revKernels revBuilders seen seenChunks outLine smMappings srcLocs) chunks =
  let kernelCode = Kernel_.generateKernel mode chunks
      kernelBytes = BL.toStrict (BB.toLazyByteString kernelCode)
  in if Set.member kernelBytes seenChunks
     then State revKernels revBuilders (Set.insert currentGlobal seen) seenChunks outLine smMappings srcLocs
     else State (kernelCode : revKernels) revBuilders (Set.insert currentGlobal seen) (Set.insert kernelBytes seenChunks) (outLine + countNewlinesBS kernelBytes) smMappings srcLocs

addStmt :: State -> JS.Stmt -> State
addStmt state stmt =
  addBuilder state (JS.stmtToBuilder stmt)

addBuilder :: State -> Builder -> State
addBuilder (State revKernels revBuilders seen seenChunks outLine smMappings srcLocs) builder =
  State revKernels (builder : revBuilders) seen seenChunks (outLine + countNewlines builder) smMappings srcLocs

-- | Count newline bytes in a Builder by materializing it.
--
-- Prefer 'countNewlinesBS' when the bytes are already materialized
-- to avoid double allocation.
countNewlines :: Builder -> Int
countNewlines b =
  countNewlinesBS (BL.toStrict (BB.toLazyByteString b))

-- | Count newline bytes in a strict ByteString.
--
-- O(n) single-pass scan using 'BS.count'. Used by 'addKernelChunks'
-- where the kernel bytes are already materialized for deduplication.
countNewlinesBS :: ByteString -> Int
countNewlinesBS =
  BS.count 0x0A

-- | Emit a source map mapping for a global before generating its JS.
emitMapping :: Opt.Global -> State -> State
emitMapping global state =
  case Map.lookup global (_sourceLocations state) of
    Nothing -> state
    Just region -> emitMappingForRegion region state

-- | Build a mapping from a source region.
emitMappingForRegion :: Ann.Region -> State -> State
emitMappingForRegion (Ann.Region (Ann.Position srcLine srcCol) _) state =
  let mapping = SourceMap.Mapping
        { SourceMap._mGenLine = _outputLine state
        , SourceMap._mGenCol = 0
        , SourceMap._mSrcIndex = 0
        , SourceMap._mSrcLine = fromIntegral srcLine - 1
        , SourceMap._mSrcCol = fromIntegral srcCol - 1
        , SourceMap._mNameIndex = Nothing
        }
   in state { _sourceMapMappings = mapping : _sourceMapMappings state }

-- | Build a SourceMap from accumulated state (dev mode only).
buildSourceMap :: Mode.Mode -> State -> Maybe SourceMap.SourceMap
buildSourceMap mode state =
  case mode of
    Mode.Prod {} -> Nothing
    Mode.Dev _ _ _ _ _ ->
      let sm = SourceMap.empty "canopy.js"
       in Just sm { SourceMap._smMappings = _sourceMapMappings state }

var :: Opt.Global -> Expr.Code -> JS.Stmt
var (Opt.Global home name) code =
  JS.Var (JsName.fromGlobal home name) (Expr.codeToExpr code)

-- GENERATE MANAGER

generateManager :: Mode.Mode -> Graph -> Opt.Global -> Opt.EffectsType -> State -> State
generateManager mode graph (Opt.Global home@(ModuleName.Canonical _ moduleName) _) effectsType state =
  let managerLVar =
        JS.LBracket
          (JS.Ref (JsName.fromKernel Name.platform "effectManagers"))
          (JS.String (Name.toBuilder moduleName))
      (deps, args, stmts) =
        Kernel_.generateManagerHelp home effectsType
      createManager =
        (JS.ExprStmt . JS.Assign managerLVar $ JS.Call (JS.Ref (JsName.fromKernel Name.platform "createManager")) args)
   in List.foldl' addStmt (List.foldl' (addGlobal mode graph) state deps) (createManager : stmts)

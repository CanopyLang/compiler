{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | JavaScript generation for the Canopy compiler
--
-- ⚠️  CRITICAL RULE: NO HARDCODING OF FFI FILE PATHS! ⚠️
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
import Control.Lens (makeLenses)
import qualified Data.Binary as Binary
import qualified Canopy.Kernel as K
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Index as Index
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Maybe
import qualified Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Utf8 as Utf8
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.JavaScript.Functions as Functions
import qualified Generate.JavaScript.Minify as Minify
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import qualified Reporting.Doc as D
import qualified Reporting.InternalError as InternalError
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as L
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
    Binary.put (Text.unpack content)
    Binary.put alias
  get = do
    path <- Binary.get
    contentStr <- Binary.get
    alias <- Binary.get
    return (FFIInfo path (Text.pack contentStr) alias)

makeLenses ''FFIInfo

-- | Generate FFI JavaScript content to include in bundle.
--
-- Receives FFI information directly through the compilation pipeline
-- instead of using global storage, eliminating MVar deadlock issues.
generateFFIContent :: Graph -> Map String FFIInfo -> Builder
generateFFIContent graph ffiInfos =
  if Map.null ffiInfos
     then mempty
     else mconcat (map B.stringUtf8 parts)
  where
    parts =
      [ "\n// FFI JavaScript content from external files\n" ]
        ++ Map.foldrWithKey formatFFIFileFromInfo [] ffiInfos
        ++ [ "\n// FFI function bindings\n" ]
        ++ Map.foldrWithKey (generateFFIBindingsFromInfo graph) [] ffiInfos

-- | Format FFI file content for inclusion using FFIInfo.
formatFFIFileFromInfo :: String -> FFIInfo -> [String] -> [String]
formatFFIFileFromInfo _key info acc =
  [ "\n// From " ++ _ffiFilePath info ++ "\n"
  , Text.unpack (_ffiContent info)
  , "\n"
  ] ++ acc

-- | Generate JavaScript variable bindings for FFI functions using FFIInfo with proper aliases.
generateFFIBindingsFromInfo :: Graph -> String -> FFIInfo -> [String] -> [String]
generateFFIBindingsFromInfo graph _key info acc =
  let path = _ffiFilePath info
      content = Text.unpack (_ffiContent info)
      alias = Name.toChars (_ffiAlias info)
  in case extractFFIFunctionBindings graph path content alias of
    [] -> acc
    bindings ->
      ("\n// Bindings for " ++ path ++ "\n")
        : ("var " ++ alias ++ " = " ++ alias ++ " || {};\n")
        : map (++ "\n") bindings ++ ["\n"] ++ acc

-- | Extract and generate bindings for FFI functions from JavaScript content.
extractFFIFunctionBindings :: Graph -> String -> String -> String -> [String]
extractFFIFunctionBindings graph path content alias =
  concatMap (generateFunctionBinding graph path alias) functions
  where
    functions = extractCanopyTypeFunctions (lines content)

-- Extract functions that have @canopy-type annotations
extractCanopyTypeFunctions :: [String] -> [(String, String)]  -- [(functionName, canopyType)]
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

-- Find the function name in the following lines
findFunctionName :: [String] -> Maybe String
findFunctionName [] = Nothing
findFunctionName (line:rest) =
  if "function " `List.isPrefixOf` trim line
    then case dropWhile (/= ' ') (trim line) of
      (' ':rest') -> case takeWhile (\c -> c /= '(' && c /= ' ') (trim rest') of
        "" -> findFunctionName rest
        name -> Just name
      _ -> findFunctionName rest
    else if "*/" `List.isInfixOf` line
      then findFunctionName rest  -- Continue past comment end
      else findFunctionName rest

-- Generate JavaScript binding for a single function
generateFunctionBinding :: Graph -> String -> String -> (String, String) -> [String]
generateFunctionBinding _graph _filePath alias (funcName, canopyType) =
  let arity = countArrows canopyType
      wrapper = if arity <= 1 then "" else "F" ++ show arity ++ "("
      closing = if arity <= 1 then "" else ")"
      -- Use the actual alias from the import statement instead of hardcoded "Math"
      jsVarName = "$author$project$" ++ alias ++ "$" ++ funcName
      -- Create namespace object using the correct alias
      namespaceBinding = alias ++ "." ++ funcName ++ " = " ++ wrapper ++ funcName ++ closing ++ ";"
  in ["var " ++ jsVarName ++ " = " ++ wrapper ++ funcName ++ closing ++ ";", namespaceBinding]

-- Count arrows in a type signature to determine arity (only function parameter arrows)
-- Uses the same tokenization logic as the FFI parser to handle multi-word types correctly
countArrows :: String -> Int
countArrows typeStr =
  let tokens = tokenizeCanopyType (Text.pack typeStr)
      result = countFunctionArrows tokens
  in result
  where
    -- Tokenize the same way as the FFI parser to handle multi-word types
    tokenizeCanopyType :: Text.Text -> [Text.Text]
    tokenizeCanopyType typeText = filter (not . Text.null) (go [] "" typeText)
      where
        go :: [Text.Text] -> Text.Text -> Text.Text -> [Text.Text]
        go acc current text
          | Text.null text = if Text.null current then acc else acc ++ [current]
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

    -- Count arrows that represent function parameters (not arrows inside types)
    countFunctionArrows :: [Text.Text] -> Int
    countFunctionArrows tokens = go tokens (0 :: Int) (0 :: Int)
      where
        go [] _parenCount arrowCount = arrowCount
        go (token:rest) parenCount arrowCount
          | token == "(" = go rest (parenCount + 1) arrowCount
          | token == ")" = go rest (parenCount - 1) arrowCount
          | token == "->" && parenCount == 0 = go rest parenCount (arrowCount + 1)
          | otherwise = go rest parenCount arrowCount

-- | Trim leading and trailing whitespace from a string.
trim :: String -> String
trim = List.dropWhileEnd isSpace . dropWhile isSpace
  where
    isSpace c = c `elem` [' ', '\t', '\n', '\r']

generate :: Mode.Mode -> Opt.GlobalGraph -> Mains -> Map String FFIInfo -> Builder
generate inputMode (Opt.GlobalGraph rawGraph _) mains ffiInfos =
  let (graph, mode) = case inputMode of
        Mode.Prod fields elmCompat _ ->
          let minified = Minify.minifyGraph rawGraph
              pool = StringPool.buildPool minified
           in (minified, Mode.Prod fields elmCompat pool)
        Mode.Dev _ _ -> (rawGraph, inputMode)
      baseState = Map.foldrWithKey (addMain mode graph) emptyState mains
      shouldInclude global =
        not (isDebugger global && not (Mode.isDebug mode))
      filteredGraph = Map.filterWithKey (\global _ -> shouldInclude global) graph
      state = Map.foldlWithKey' (\s global _ -> addGlobal mode graph s global) baseState filteredGraph
      header = if Mode.isElmCompatible mode
               then "(function(scope){\n'use strict';\n"
               else "(function(scope){'use strict';\n"
      debuggerStub = "var _Debugger_unsafeCoerce = function(value) { return value; };\n"
      poolDecls = StringPool.poolDeclarations (Mode.stringPool mode)
   in header
        <> debuggerStub
        <> generateFFIContent graph ffiInfos
        <> Functions.functions
        <> perfNote mode
        <> poolDecls
        <> stateToBuilder state
        <> toMainExports mode mains
        <> "\n}(typeof window !== 'undefined' ? window : this));"


addMain :: Mode.Mode -> Graph -> ModuleName.Canonical -> Opt.Main -> State -> State
addMain mode graph home _ state =
  addGlobal mode graph state (Opt.Global home "main")

perfNote :: Mode.Mode -> Builder
perfNote mode =
  case mode of
    Mode.Prod {} ->
      mempty
    Mode.Dev Nothing elmCompatible ->
      -- Always include console.warn in dev mode to match Elm behavior
      -- Use explicit semicolon annotation to ensure semicolon is added
      let optimizeUrl = if elmCompatible
                        then "https://elm-lang.org/0.19.1/optimize"
                        else D.makeNakedLink "optimize"
      in JS.stmtToBuilder $
           JS.ExprStmtWithSemi $
             JS.Call
               (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "warn"))
               [ JS.String $
                   "Compiled in DEV mode. Follow the advice at "
                     <> B.stringUtf8 optimizeUrl
                     <> " for better performance and smaller assets."
               ]
    Mode.Dev (Just _) elmCompatible ->
      -- Always include console.warn in dev mode to match Elm behavior
      -- Use explicit semicolon annotation to ensure semicolon is added
      let optimizeUrl = if elmCompatible
                        then "https://elm-lang.org/0.19.1/optimize"
                        else D.makeNakedLink "optimize"
      in JS.stmtToBuilder $
           JS.ExprStmtWithSemi $
             JS.Call
               (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "warn"))
               [ JS.String $
                   "Compiled in DEBUG mode. Follow the advice at "
                     <> B.stringUtf8 optimizeUrl
                     <> " for better performance and smaller assets."
               ]

-- Note: Comprehensive runtime functions removed due to unused warnings.
-- These can be re-added when actually needed for Elm compatibility.

-- GENERATE FOR REPL
generateForRepl :: Bool -> L.Localizer -> Opt.GlobalGraph -> ModuleName.Canonical -> Name.Name -> Can.Annotation -> Builder
generateForRepl ansi localizer (Opt.GlobalGraph graph _) home name (Can.Forall _ tipe) =
  let mode = Mode.Dev Nothing True  -- Default to elm-compatible for REPL
      debugState = addGlobal mode graph emptyState (Opt.Global ModuleName.debug "toString")
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

print :: Bool -> L.Localizer -> ModuleName.Canonical -> Name.Name -> Can.Type -> Builder
print ansi localizer home name tipe =
  let value = JS.Ref (JsName.fromGlobal home name)
      toString = JS.Ref (JsName.fromKernel Name.debug "toAnsiString")
      tipeDoc = RT.canToDoc localizer RT.None tipe
      boolValue = if ansi then JS.Bool True else JS.Bool False

      -- var _value = toString(bool, value);
      valueVar = JS.Var (JsName.fromLocal "_value") $
        JS.Call toString [boolValue, value]

      -- var _type = "type string";
      typeVar = JS.Var (JsName.fromLocal "_type") $
        JS.String $ B.stringUtf8 (show (D.toString tipeDoc))

      -- function _print(t) { console.log(_value + (ansi ? '\x1b[90m' + t + '\x1b[0m' : t)); }
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

      -- Condition: _value.length + 3 + _type.length >= 80 || _type.indexOf('\n') >= 0
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

      -- if/else statement
      ifStmt = JS.IfStmt condition
        -- _print('\n    : ' + _type.split('\n').join('\n      '));
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
        -- _print(' : ' + _type);
        (JS.ExprStmt $ JS.Call
          (JS.Ref (JsName.fromLocal "_print"))
          [ JS.Infix JS.OpAdd (JS.String " : ") (JS.Ref (JsName.fromLocal "_type")) ]
        )
   in JS.stmtToBuilder $ JS.Block [valueVar, typeVar, printFunc, ifStmt]

-- GENERATE FOR REPL ENDPOINT

generateForReplEndpoint :: L.Localizer -> Opt.GlobalGraph -> ModuleName.Canonical -> Maybe Name.Name -> Can.Annotation -> Builder
generateForReplEndpoint localizer (Opt.GlobalGraph graph _) home maybeName (Can.Forall _ tipe) =
  let name = Data.Maybe.fromMaybe Name.replValueToPrint maybeName
      mode = Mode.Dev Nothing True  -- Default to elm-compatible for REPL
      debugState = addGlobal mode graph emptyState (Opt.Global ModuleName.debug "toString")
      evalState = addGlobal mode graph debugState (Opt.Global home name)
   in Functions.functions
        <> stateToBuilder evalState
        <> postMessage localizer home maybeName tipe

postMessage :: L.Localizer -> ModuleName.Canonical -> Maybe Name.Name -> Can.Type -> Builder
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
          (JsName.fromLocal "type", JS.String $ B.stringUtf8 (show (D.toString tipeDoc)))
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
    _seenKernelChunks :: Set ByteString
  }

emptyState :: State
emptyState =
  State mempty [] Set.empty Set.empty

stateToBuilder :: State -> Builder
stateToBuilder (State revKernels revBuilders _ _) =
  prependBuilders revKernels (prependBuilders revBuilders mempty)

prependBuilders :: [Builder] -> Builder -> Builder
prependBuilders revBuilders monolith =
  List.foldl' (flip (<>)) monolith revBuilders

-- ADD DEPENDENCIES

addGlobal :: Mode.Mode -> Graph -> State -> Opt.Global -> State
addGlobal mode graph state@(State revKernels builders seen seenChunks) global =
  if Set.member global seen
    then state
    else
      addGlobalHelp mode graph global $
        State revKernels builders (Set.insert global seen) seenChunks

-- | Filter dependencies to exclude debugger modules in production mode
filterEssentialDeps :: Mode.Mode -> Set Opt.Global -> Set Opt.Global
filterEssentialDeps mode deps =
  if Mode.isDebug mode
    then deps
    else Set.filter (not . isDebugger) deps


addGlobalHelp :: Mode.Mode -> Graph -> Opt.Global -> State -> State
addGlobalHelp mode graph currentGlobal state =
  let Opt.Global globalHome _ = currentGlobal
      pkg = ModuleName._package globalHome
  in if isDebugger currentGlobal && not (Mode.isDebug mode)
     then state
     -- Skip FFI functions - they're handled by expression generation
     else if Pkg._author pkg == Pkg._author Pkg.dummyName && Pkg._project pkg == Pkg._project Pkg.dummyName
     then state
     else continueAddGlobal mode graph currentGlobal state

continueAddGlobal :: Mode.Mode -> Graph -> Opt.Global -> State -> State
continueAddGlobal mode graph currentGlobal state =
  let addDeps deps someState =
        let filteredDeps = filterEssentialDeps mode deps
        in Set.foldl' (addGlobal mode graph) someState filteredDeps
      globalInGraph = case Map.lookup currentGlobal graph of
        Just x -> x
        Nothing ->
          -- Try alternative package/module name (elm/core Kernel.* vs elm/kernel * vs canopy/kernel *)
          let Opt.Global globalHome globalName = currentGlobal
              currentPkg = ModuleName._package globalHome
              moduleName = ModuleName._module globalHome

              -- Check if this is a Kernel.* module in elm/core
              isKernelModule = "Kernel." `List.isPrefixOf` Name.toChars moduleName
              isKernelPkg = Pkg._project currentPkg == Pkg._project Pkg.kernel

              (altPkg, altModuleName) =
                if Pkg._author currentPkg == Pkg.elm && Pkg._project currentPkg == Pkg._project Pkg.core && isKernelModule
                then -- Map elm/core Kernel.* -> elm/kernel *
                     let kernelName = drop 7 (Name.toChars moduleName)
                         kernelPkg = Pkg.Name Pkg.elm (Pkg._project Pkg.kernel)
                     in (kernelPkg, Name.fromChars kernelName)
                else if isKernelPkg && Pkg._author currentPkg == Pkg.elm
                then -- Map elm/kernel * -> elm/core Kernel.*
                     let kernelModuleName = "Kernel." ++ Name.toChars moduleName
                     in (Pkg.core, Name.fromChars kernelModuleName)
                else if isKernelPkg && Pkg._author currentPkg == Pkg.canopy
                then -- Map canopy/kernel * -> elm/kernel * (Canopy kernel references resolve to elm kernel artifacts)
                     (Pkg.Name Pkg.elm (Pkg._project Pkg.kernel), moduleName)
                else (currentPkg, moduleName)

              altGlobalHome = ModuleName.Canonical altPkg altModuleName
              altGlobal = Opt.Global altGlobalHome globalName
          in case Map.lookup altGlobal graph of
               Just x -> x
               Nothing ->
                 -- Check if this is an FFI module (author/project package)
                 if Pkg._author currentPkg == Pkg._author Pkg.dummyName && Pkg._project currentPkg == Pkg._project Pkg.dummyName
                 then InternalError.report
                   "Generate.JavaScript.checkedMerge"
                   "FFI function found — this should be handled by expression generation"
                   "A foreign-function global was encountered during graph merging, but FFI globals must be resolved during expression generation, not graph merging."
                 else let allKeys = Map.keys graph
                          listRelated = filter (\(Opt.Global home name) ->
                            let modName = ModuleName._module home
                            in "List" `List.isInfixOf` Name.toChars modName || "List" `List.isInfixOf` Name.toChars name) allKeys
                          dollarKeys = filter (\(Opt.Global _ name) -> Name.toChars name == "$") allKeys
                          elmCoreKeys = filter (\(Opt.Global home _) ->
                            let pkg = ModuleName._package home
                            in Pkg._author pkg == Pkg.elm && Pkg._project pkg == Pkg._project Pkg.core) allKeys
                          errorMsg = "\n=== GLOBALHELP DEBUG ===\n" <>
                                   "Missing: " <> show currentGlobal <> "\n" <>
                                   "Also tried: " <> show altGlobal <> "\n" <>
                                   "Total keys: " <> show (length allKeys) <> "\n" <>
                                   "List-related: " <> show listRelated <> "\n" <>
                                   "$ globals: " <> show dollarKeys <> "\n" <>
                                   "elm/core count: " <> show (length elmCoreKeys) <> "\n" <>
                                   "First 20: " <> show (take 20 allKeys) <> "\n" <>
                                   "========================"
                      in error errorMsg
   in case globalInGraph of
        Opt.Define expr deps ->
          addStmt
            (addDeps deps state)
            ( var currentGlobal (Expr.generate mode expr)
            )
        Opt.DefineTailFunc argNames body deps ->
          addStmt
            (addDeps deps state)
            ( let (Opt.Global _ name) = currentGlobal
               in JS.Var (JsName.fromGlobal (case currentGlobal of Opt.Global home _ -> home) name) (Expr.generateTailDefExpr mode name argNames body)
            )
        Opt.Ctor index arity ->
          addStmt
            state
            ( var currentGlobal (Expr.generateCtor mode currentGlobal index arity)
            )
        Opt.Link linkedGlobal ->
          addGlobal mode graph state linkedGlobal
        Opt.Cycle names values functions deps ->
          let cycleStmt = generateCycle mode currentGlobal names values functions
              baseState = addDeps deps state
          in case cycleStmt of
               JS.Block stmts -> List.foldl' addStmt baseState stmts
               stmt -> addStmt baseState stmt
        Opt.Manager effectsType ->
          generateManager mode graph currentGlobal effectsType state
        Opt.Kernel chunks deps ->
          let State revKernels revBuilders seen seenChunks = addDeps deps state
              kernelCode = generateKernel mode chunks
              kernelBytes = BL.toStrict (B.toLazyByteString kernelCode)
          in if Set.member kernelBytes seenChunks
             then State revKernels revBuilders (Set.insert currentGlobal seen) seenChunks
             else State (kernelCode : revKernels) revBuilders (Set.insert currentGlobal seen) (Set.insert kernelBytes seenChunks)
        Opt.Enum index ->
          addStmt
            state
            ( generateEnum mode currentGlobal index
            )
        Opt.Box ->
          addStmt
            (addGlobal mode graph state identity)
            ( generateBox mode currentGlobal
            )
        Opt.PortIncoming decoder deps ->
          addStmt
            (addDeps deps state)
            ( generatePort mode currentGlobal "incomingPort" decoder
            )
        Opt.PortOutgoing encoder deps ->
          addStmt
            (addDeps deps state)
            ( generatePort mode currentGlobal "outgoingPort" encoder
            )

addStmt :: State -> JS.Stmt -> State
addStmt state stmt =
  addBuilder state (JS.stmtToBuilder stmt)

addBuilder :: State -> Builder -> State
addBuilder (State revKernels revBuilders seen seenChunks) builder =
  State revKernels (builder : revBuilders) seen seenChunks

var :: Opt.Global -> Expr.Code -> JS.Stmt
var (Opt.Global home name) code =
  JS.Var (JsName.fromGlobal home name) (Expr.codeToExpr code)

isDebugger :: Opt.Global -> Bool
isDebugger (Opt.Global (ModuleName.Canonical _ home) _) =
  home == Name.debugger

-- GENERATE CYCLES

generateCycle :: Mode.Mode -> Opt.Global -> [Name.Name] -> [(Name.Name, Opt.Expr)] -> [Opt.Def] -> JS.Stmt
generateCycle mode (Opt.Global home _) names values functions =
  let functionStmts = fmap (generateCycleFunc mode home) functions
      safeStmts = fmap (generateSafeCycle mode home) values
      realStmts = case fmap (generateRealCycle home) values of
        [] -> []
        realBlock@(_ : _) ->
          case mode of
            Mode.Prod {} ->
              realBlock
            Mode.Dev _ _ ->
              [(JS.Try (JS.Block realBlock) JsName.dollar . JS.Throw) . JS.String $
                ( "Some top-level definitions from `" <> Name.toBuilder (ModuleName._module home) <> "` are causing infinite recursion:\\n"
                    <> drawCycle names
                    <> "\\n\\nThese errors are very tricky, so read "
                    <> B.stringUtf8 (D.makeNakedLink "bad-recursion")
                    <> " to learn how to fix it!"
                )]
      allStmts = functionStmts ++ safeStmts ++ realStmts
  in case allStmts of
       [singleStmt] -> singleStmt
       _ -> JS.Block allStmts

generateCycleFunc :: Mode.Mode -> ModuleName.Canonical -> Opt.Def -> JS.Stmt
generateCycleFunc mode home def =
  case def of
    Opt.Def name expr ->
      JS.Var (JsName.fromGlobal home name) (Expr.codeToExpr (Expr.generate mode expr))
    Opt.TailDef name args expr ->
      JS.Var (JsName.fromGlobal home name) (Expr.generateTailDefExpr mode name args expr)

generateSafeCycle :: Mode.Mode -> ModuleName.Canonical -> (Name.Name, Opt.Expr) -> JS.Stmt
generateSafeCycle mode home (name, expr) =
  JS.FunctionStmt (JsName.fromCycle home name) [] $
    Expr.codeToStmtList (Expr.generate mode expr)

generateRealCycle :: ModuleName.Canonical -> (Name.Name, expr) -> JS.Stmt
generateRealCycle home (name, _) =
  let safeName = JsName.fromCycle home name
      realName = JsName.fromGlobal home name
   in JS.Block
        [ JS.Var realName (JS.Call (JS.Ref safeName) []),
          JS.ExprStmt . JS.Assign (JS.LRef safeName) $ JS.Function Nothing [] [JS.Return (JS.Ref realName)]
        ]

drawCycle :: [Name.Name] -> Builder
drawCycle names =
  let topLine = "\\n  ┌─────┐"
      nameLine name = "\\n  │    " <> Name.toBuilder name
      midLine = "\\n  │     ↓"
      bottomLine = "\\n  └─────┘"
   in mconcat (topLine : (List.intersperse midLine (fmap nameLine names) <> [bottomLine]))

-- GENERATE KERNEL

generateKernel :: Mode.Mode -> [K.Chunk] -> Builder
generateKernel mode = List.foldr (addChunk mode) mempty

addChunk :: Mode.Mode -> K.Chunk -> Builder -> Builder
addChunk mode chunk builder =
  case chunk of
    K.JS javascript ->
      B.byteString javascript <> builder
    K.CanopyVar home name ->
      JsName.toBuilder (JsName.fromGlobal home name) <> builder
    K.JsVar home name ->
      JsName.toBuilder (JsName.fromKernel home name) <> builder
    K.CanopyField name ->
      JsName.toBuilder (Expr.generateField mode name) <> builder
    K.JsField int ->
      JsName.toBuilder (JsName.fromInt int) <> builder
    K.JsEnum int ->
      B.intDec int <> builder
    K.Debug ->
      case mode of
        Mode.Dev _ elmCompatible ->
          if elmCompatible
            then builder               -- Elm dev: debug functions are used (clean)
            else builder               -- Canopy dev: use debug functions
        Mode.Prod {} ->
          "_UNUSED" <> builder
    K.Prod ->
      case mode of
        Mode.Dev _ elmCompatible ->
          if elmCompatible
            then "_UNUSED" <> builder  -- Elm dev: prod functions marked unused
            else "_UNUSED" <> builder  -- Canopy dev: prod functions marked unused
        Mode.Prod {} ->
          builder

-- GENERATE ENUM

generateEnum :: Mode.Mode -> Opt.Global -> Index.ZeroBased -> JS.Stmt
generateEnum mode global@(Opt.Global home name) index =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ ->
        Expr.codeToExpr (Expr.generateCtor mode global index 0)
      Mode.Prod {} ->
        JS.Int (Index.toMachine index)

-- GENERATE BOX

generateBox :: Mode.Mode -> Opt.Global -> JS.Stmt
generateBox mode global@(Opt.Global home name) =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ ->
        Expr.codeToExpr (Expr.generateCtor mode global Index.first 1)
      Mode.Prod {} ->
        JS.Ref (JsName.fromGlobal ModuleName.basics Name.identity)

{-# NOINLINE identity #-}
identity :: Opt.Global
identity =
  Opt.Global ModuleName.basics Name.identity

-- GENERATE PORTS

generatePort :: Mode.Mode -> Opt.Global -> Name.Name -> Opt.Expr -> JS.Stmt
generatePort mode (Opt.Global home name) makePort converter =
  JS.Var (JsName.fromGlobal home name) $
    JS.Call
      (JS.Ref (JsName.fromKernel Name.platform makePort))
      [ JS.String (Name.toBuilder name),
        Expr.codeToExpr (Expr.generate mode converter)
      ]

-- GENERATE MANAGER

generateManager :: Mode.Mode -> Graph -> Opt.Global -> Opt.EffectsType -> State -> State
generateManager mode graph (Opt.Global home@(ModuleName.Canonical _ moduleName) _) effectsType state =
  let managerLVar =
        JS.LBracket
          (JS.Ref (JsName.fromKernel Name.platform "effectManagers"))
          (JS.String (Name.toBuilder moduleName))

      (deps, args, stmts) =
        generateManagerHelp home effectsType

      createManager =
        (JS.ExprStmt . JS.Assign managerLVar $ JS.Call (JS.Ref (JsName.fromKernel Name.platform "createManager")) args)
   in List.foldl' addStmt (List.foldl' (addGlobal mode graph) state deps) (createManager : stmts)

generateLeaf :: ModuleName.Canonical -> Name.Name -> JS.Stmt
generateLeaf home@(ModuleName.Canonical _ moduleName) name =
  JS.Var (JsName.fromGlobal home name) $
    JS.Call leaf [JS.String (Name.toBuilder moduleName)]

{-# NOINLINE leaf #-}
leaf :: JS.Expr
leaf =
  JS.Ref (JsName.fromKernel Name.platform "leaf")

generateManagerHelp :: ModuleName.Canonical -> Opt.EffectsType -> ([Opt.Global], [JS.Expr], [JS.Stmt])
generateManagerHelp home effectsType =
  let ref name = JS.Ref (JsName.fromGlobal home name)
      dep = Opt.Global home
   in case effectsType of
        Opt.Cmd ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "cmdMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", ref "cmdMap"],
            [generateLeaf home "command"]
          )
        Opt.Sub ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "subMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", JS.Int 0, ref "subMap"],
            [generateLeaf home "subscription"]
          )
        Opt.Fx ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "cmdMap", dep "subMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", ref "cmdMap", ref "subMap"],
            [ generateLeaf home "command",
              generateLeaf home "subscription"
            ]
          )

-- MAIN EXPORTS

toMainExports :: Mode.Mode -> Mains -> Builder
toMainExports mode mains =
  let export = JsName.fromKernel Name.platform "export"
      exports = generateExports mode (Map.foldrWithKey addToTrie emptyTrie mains)
   in JsName.toBuilder export <> "(" <> exports <> ");"
        <> "scope['Canopy'] = scope['Elm'];"

generateExports :: Mode.Mode -> Trie -> Builder
generateExports mode (Trie maybeMain subs) =
  let starter end =
        case maybeMain of
          Nothing ->
            "{"
          Just (home, main) ->
            "{'init':"
              <> JS.exprToBuilder (Expr.generateMain mode home main)
              <> end
   in case Map.toList subs of
        [] ->
          starter "" <> "}"
        (name, subTrie) : otherSubTries ->
          starter ","
            <> "'"
            <> Utf8.toBuilder name
            <> "':"
            <> generateExports mode subTrie
            <> List.foldl' (addSubTrie mode) "}" otherSubTries

addSubTrie :: Mode.Mode -> Builder -> (Name.Name, Trie) -> Builder
addSubTrie mode end (name, trie) =
  ",'" <> Utf8.toBuilder name <> "':" <> generateExports mode trie <> end

-- BUILD TRIES

data Trie = Trie
  { _main :: Maybe (ModuleName.Canonical, Opt.Main),
    _subs :: Map Name.Name Trie
  }

emptyTrie :: Trie
emptyTrie =
  Trie Nothing Map.empty

addToTrie :: ModuleName.Canonical -> Opt.Main -> Trie -> Trie
addToTrie home@(ModuleName.Canonical _ moduleName) main trie =
  merge trie $ segmentsToTrie home (Name.splitDots moduleName) main

segmentsToTrie :: ModuleName.Canonical -> [Name.Name] -> Opt.Main -> Trie
segmentsToTrie home segments main =
  case segments of
    [] ->
      Trie (Just (home, main)) Map.empty
    segment : otherSegments ->
      Trie Nothing (Map.singleton segment (segmentsToTrie home otherSegments main))

merge :: Trie -> Trie -> Trie
merge (Trie main1 subs1) (Trie main2 subs2) =
  Trie
    (checkedMerge main1 main2)
    (Map.unionWith merge subs1 subs2)

checkedMerge :: Maybe a -> Maybe a -> Maybe a
checkedMerge a b =
  case (a, b) of
    (Nothing, main) ->
      main
    (main, Nothing) ->
      main
    (Just _, Just _) ->
      InternalError.report
        "Generate.JavaScript.checkedMerge"
        "cannot have two modules with the same name"
        "Module names must be unique across the entire compilation unit. This indicates a bug in the module graph construction."
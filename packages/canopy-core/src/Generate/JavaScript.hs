{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE OverloadedStrings #-}

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

    -- * Re-exported from Generate.JavaScript.FFI
    FFIInfo(..),
    ffiFilePath,
    ffiContent,
    ffiAlias,
    extractFFIAliases,
    generateFFIContent,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
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
import qualified Canopy.Data.Utf8 as Utf8
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import Generate.JavaScript.FFI
  ( FFIInfo (..),
    extractFFIAliases,
    ffiAlias,
    ffiContent,
    ffiFilePath,
    generateFFIContent,
  )
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

-- TYPES

-- | Graph of optimized global definitions.
type Graph = Map Opt.Global Opt.Node

-- | Map of main entry points per module.
type Mains = Map ModuleName.Canonical Opt.Main

-- GENERATE

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
      isKernelModule = Utf8.startsWith kernelDotPrefix moduleName
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
      let kernelPkg = Pkg.Name Pkg.elm (Pkg._project Pkg.kernel)
      in (kernelPkg, Utf8.dropBytes 7 moduleName)
  | isKernelPkg && Pkg._author currentPkg == Pkg.elm =
      (Pkg.core, Name.fromChars ("Kernel." ++ Name.toChars moduleName))
  | isKernelPkg && Pkg._author currentPkg == Pkg.canopy =
      (Pkg.Name Pkg.elm (Pkg._project Pkg.kernel), moduleName)
  | otherwise = (currentPkg, moduleName)

-- | The @\"Kernel.\"@ prefix used to identify kernel modules during
-- alt-global resolution. Cached as a top-level constant to avoid
-- repeated allocation.
--
-- @since 0.19.2
{-# NOINLINE kernelDotPrefix #-}
kernelDotPrefix :: Name.Name
kernelDotPrefix = Name.fromChars "Kernel."

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

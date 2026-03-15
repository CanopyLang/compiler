{-# LANGUAGE BangPatterns #-}
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

    -- * Re-exported from Generate.JavaScript.FFI
    FFIInfo(..),
    ffiFilePath,
    ffiContent,
    ffiAlias,
    extractFFIAliases,
    generateFFIContent,

    -- * Re-exported from Generate.JavaScript.Coverage
    Coverage.CoverageMap(..),
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
import qualified Generate.JavaScript.Coverage as Coverage
import qualified Generate.JavaScript.Ability as Ability
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
import qualified Generate.JavaScript.Runtime as Runtime
import qualified Generate.JavaScript.Functions as Functions
import qualified Generate.JavaScript.Kernel as Kernel_
import qualified Generate.JavaScript.Minify as Minify
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.Runtime.Names as KN
import qualified Generate.JavaScript.SourceMap as SourceMap
import qualified Generate.JavaScript.StringPool as StringPool
import Control.Lens (makeLenses, (&), (%~), (.~), (^.))
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

-- GRAPH TRAVERSAL STATE

data State = State
  { _revKernels :: [Builder],
    _revBuilders :: [Builder],
    _seenGlobals :: Set Opt.Global,
    _seenKernelChunks :: Set ByteString,
    _outputLine :: !Int,
    _sourceMapMappings :: ![SourceMap.Mapping],
    _sourceLocations :: Map Opt.Global Ann.Region,
    _trackLines :: !Bool,
    _coverageBaseIds :: Map Opt.Global Int
  }

makeLenses ''State

-- GENERATE

generate :: Mode.Mode -> Opt.GlobalGraph -> Mains -> Map String FFIInfo -> (Builder, Maybe SourceMap.SourceMap, Maybe Coverage.CoverageMap)
generate inputMode (Opt.GlobalGraph rawGraph _ sourceLocs) mains ffiInfos =
  let ffiAliases = extractFFIAliases ffiInfos
      (graph, mode) = case inputMode of
        Mode.Prod fields elmCompat ffiUnsafe ffiDbg _ _ ->
          let minified = Minify.minifyGraph rawGraph
              pool = StringPool.buildPool minified
           in (minified, Mode.Prod fields elmCompat ffiUnsafe ffiDbg pool ffiAliases)
        Mode.Dev debugTypes elmCompat ffiUnsafe ffiDbg _ cov ->
          (rawGraph, Mode.Dev debugTypes elmCompat ffiUnsafe ffiDbg ffiAliases cov)
      shouldTrackLines = case mode of Mode.Dev {} -> True; Mode.Prod {} -> False
      covIds = if Mode.isCoverage mode then Coverage.computeBaseIds graph else Map.empty
      baseState = Map.foldrWithKey (addMain mode graph) (emptyState shouldTrackLines sourceLocs covIds) mains
      shouldInclude global =
        not (Kernel_.isDebugger global && not (Mode.isDebug mode))
      filteredGraph = Map.filterWithKey (\global _ -> shouldInclude global) graph
      state = Map.foldlWithKey' (\s global _ -> addGlobal mode graph s global) baseState filteredGraph
      header = if Mode.isElmCompatible mode
               then "(function(scope){\n'use strict';\n"
               else "(function(scope){'use strict';\n"
      debuggerStub = "var _Debugger_unsafeCoerce = function(value) { return value; };\n"
      poolDecls = StringPool.poolDeclarations (Mode.stringPool mode)
      coveragePreamble = if Mode.isCoverage mode then Coverage.coverageRuntimePreamble else mempty
      jsBuilder =
        header
          <> debuggerStub
          <> Functions.functions
          <> Runtime.embeddedRuntimeForMode mode
          <> FFIRuntime.embeddedRuntimeForMode mode
          <> coveragePreamble
          <> generateFFIContent mode graph ffiInfos Map.empty
          <> perfNote mode
          <> poolDecls
          <> stateToBuilder state
          <> Kernel_.toMainExports mode mains
          <> "\nif (typeof global !== 'undefined') { global.Canopy = scope['Canopy']; global.Elm = scope['Elm']; }"
          <> "\n}(typeof window !== 'undefined' ? window : this));"
      sourceMap = buildSourceMap mode state
      coverageMap = if Mode.isCoverage mode
                    then Just (Coverage.buildCoverageMap graph sourceLocs)
                    else Nothing
   in (jsBuilder, sourceMap, coverageMap)


addMain :: Mode.Mode -> Graph -> ModuleName.Canonical -> Opt.Main -> State -> State
addMain mode graph home _ state =
  addGlobal mode graph state (Opt.Global home "main")

perfNote :: Mode.Mode -> Builder
perfNote mode =
  case mode of
    Mode.Prod {} ->
      mempty
    Mode.Dev Nothing elmCompatible _ _ _ _ ->
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
    Mode.Dev (Just _) elmCompatible _ _ _ _ ->
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
  let mode = Mode.Dev Nothing True False False Set.empty False
      debugState = addGlobal mode graph (emptyState False Map.empty Map.empty) (Opt.Global ModuleName.debug "toString")
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
      toString = JS.Ref KN.debugToAnsiString
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
      mode = Mode.Dev Nothing True False False Set.empty False
      debugState = addGlobal mode graph (emptyState False Map.empty Map.empty) (Opt.Global ModuleName.debug "toString")
      evalState = addGlobal mode graph debugState (Opt.Global home name)
   in Functions.functions
        <> stateToBuilder evalState
        <> postMessage localizer home maybeName tipe

postMessage :: Localizer.Localizer -> ModuleName.Canonical -> Maybe Name.Name -> Can.Type -> Builder
postMessage localizer home maybeName tipe =
  let name = Data.Maybe.fromMaybe Name.replValueToPrint maybeName
      value = JS.Ref (JsName.fromGlobal home name)
      toString = JS.Ref KN.debugToAnsiString
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

-- | Create initial codegen state.
--
-- When 'trackLines' is 'True', newlines are counted per-statement
-- for source map line tracking (dev mode). When 'False', counting
-- is skipped entirely to avoid double materialization (prod mode).
emptyState :: Bool -> Map Opt.Global Ann.Region -> Map Opt.Global Int -> State
emptyState doTrackLines locs covIds =
  State mempty [] Set.empty Set.empty 0 [] locs doTrackLines covIds

stateToBuilder :: State -> Builder
stateToBuilder state =
  prependBuilders (state ^. revKernels) (prependBuilders (state ^. revBuilders) mempty)

prependBuilders :: [Builder] -> Builder -> Builder
prependBuilders builders monolith =
  List.foldl' (flip (<>)) monolith builders

-- ADD DEPENDENCIES

addGlobal :: Mode.Mode -> Graph -> State -> Opt.Global -> State
addGlobal mode graph state global =
  if Set.member global (state ^. seenGlobals)
    then state
    else addGlobalHelp mode graph global (state & seenGlobals %~ Set.insert global)

filterEssentialDeps :: Mode.Mode -> Set Opt.Global -> Set Opt.Global
filterEssentialDeps mode deps =
  if Mode.isDebug mode
    then deps
    else Set.filter (not . Kernel_.isDebugger) deps

addGlobalHelp :: Mode.Mode -> Graph -> Opt.Global -> State -> State
addGlobalHelp mode graph currentGlobal state =
  let Opt.Global globalHome globalName = currentGlobal
      moduleName = ModuleName._module globalHome
      currentPkg = ModuleName._package globalHome
      isFFIModule = Mode.isFFIAlias mode moduleName
                 && Map.notMember currentGlobal graph
      isKernelPhantom = globalName == Name.dollar
                     && Pkg._project currentPkg == Pkg._project Pkg.kernel
                     && Map.notMember currentGlobal graph
  in if Kernel_.isDebugger currentGlobal && not (Mode.isDebug mode)
     then state
     else if isFFIModule || isKernelPhantom
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
      alts = computeAltPkgs currentPkg moduleName isKernelModule isKernelPkg
      altGlobals = [Opt.Global (ModuleName.Canonical p m) globalName | (p, m) <- alts]
  in findFirstGlobal graph currentGlobal altGlobals

-- | Try each alt global in order, returning the first match.
findFirstGlobal :: Graph -> Opt.Global -> [Opt.Global] -> Opt.Node
findFirstGlobal graph currentGlobal [] =
  reportMissingGlobal graph currentGlobal currentGlobal
findFirstGlobal graph currentGlobal (alt : rest) =
  case Map.lookup alt graph of
    Just x -> x
    Nothing -> findFirstGlobal graph currentGlobal rest

-- | Compute alternative (package, moduleName) pairs for a kernel global.
--
-- Returns all possible mappings to try, in priority order. This handles
-- the canopy\/elm author duality for kernel modules.
computeAltPkgs :: Pkg.Name -> Name.Name -> Bool -> Bool -> [(Pkg.Name, Name.Name)]
computeAltPkgs currentPkg moduleName isKernelModule isKernelPkg
  | Pkg._author currentPkg == Pkg.elm && Pkg._project currentPkg == Pkg._project Pkg.core && isKernelModule =
      let kernelPkg = Pkg.Name Pkg.elm (Pkg._project Pkg.kernel)
          strippedName = Utf8.dropBytes 7 moduleName
      in [(kernelPkg, strippedName), (Pkg.kernel, strippedName)]
  | isKernelPkg && Pkg._author currentPkg == Pkg.elm =
      [(Pkg.kernel, moduleName), (Pkg.core, Name.fromChars ("Kernel." ++ Name.toChars moduleName))]
  | isKernelPkg && Pkg._author currentPkg == Pkg.canopy && isKernelModule =
      let strippedName = Utf8.dropBytes 7 moduleName
          elmKernelPkg = Pkg.Name Pkg.elm (Pkg._project Pkg.kernel)
      in [(elmKernelPkg, strippedName), (elmKernelPkg, moduleName)]
  | isKernelPkg && Pkg._author currentPkg == Pkg.canopy =
      let elmKernelPkg = Pkg.Name Pkg.elm (Pkg._project Pkg.kernel)
      in [(elmKernelPkg, moduleName)]
  | otherwise = []

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
      let baseState = emitMapping currentGlobal (addDeps deps state)
          code = if Mode.isCoverage mode
                 then covDefineCode mode currentGlobal expr state
                 else Expr.generate mode expr
       in addStmt baseState (var currentGlobal code)
    Opt.DefineTailFunc argNames body deps ->
      let baseState = emitMapping currentGlobal (addDeps deps state)
          (Opt.Global home name) = currentGlobal
          expr = if Mode.isCoverage mode
                 then covTailFuncExpr mode currentGlobal argNames body state
                 else Expr.generateTailDefExpr mode name argNames body
       in addStmt baseState (JS.Var (JsName.fromGlobal home name) expr)
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
    Opt.AbilityDict _ ->
      state
    Opt.ImplDict abilityName methods deps ->
      addStmt (emitMapping currentGlobal (addDeps deps state)) (Ability.generateImplDict mode currentGlobal abilityName methods)

-- | Generate coverage-instrumented code for a Define node.
covDefineCode :: Mode.Mode -> Opt.Global -> Opt.Expr -> State -> Expr.Code
covDefineCode mode currentGlobal expr state =
  case Map.lookup currentGlobal (state ^. coverageBaseIds) of
    Nothing -> Expr.generate mode expr
    Just baseId ->
      let (code, _nextId) = Expr.generateCov mode baseId expr
       in code

-- | Generate coverage-instrumented expression for a DefineTailFunc node.
covTailFuncExpr :: Mode.Mode -> Opt.Global -> [Name.Name] -> Opt.Expr -> State -> JS.Expr
covTailFuncExpr mode currentGlobal argNames body state =
  case Map.lookup currentGlobal (state ^. coverageBaseIds) of
    Nothing -> Expr.generateTailDefExpr mode name argNames body
    Just baseId -> Expr.generateCovTailDefExpr mode baseId name argNames body
  where
    (Opt.Global _ name) = currentGlobal

addKernelChunks :: Mode.Mode -> Opt.Global -> State -> [Kernel.Chunk] -> State
addKernelChunks mode currentGlobal state chunks =
  let kernelCode = Kernel_.generateKernel mode chunks
      kernelBytes = BL.toStrict (BB.toLazyByteString kernelCode)
      stateWithGlobal = state & seenGlobals %~ Set.insert currentGlobal
  in if Set.member kernelBytes (state ^. seenKernelChunks)
     then stateWithGlobal
     else addKernelChunksNew kernelCode kernelBytes stateWithGlobal

addKernelChunksNew :: Builder -> ByteString -> State -> State
addKernelChunksNew kernelCode kernelBytes state =
  let newLine = if state ^. trackLines then state ^. outputLine + countNewlinesBS kernelBytes else state ^. outputLine
  in state
       & revKernels %~ (kernelCode :)
       & seenKernelChunks %~ Set.insert kernelBytes
       & outputLine .~ newLine

addStmt :: State -> JS.Stmt -> State
addStmt state stmt =
  addBuilder state (JS.stmtToBuilder stmt)

addBuilder :: State -> Builder -> State
addBuilder state builder =
  let newLine = if state ^. trackLines then state ^. outputLine + countNewlines builder else state ^. outputLine
  in state
       & revBuilders %~ (builder :)
       & outputLine .~ newLine

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
  case Map.lookup global (state ^. sourceLocations) of
    Nothing -> state
    Just region -> emitMappingForRegion region state

-- | Build a mapping from a source region.
emitMappingForRegion :: Ann.Region -> State -> State
emitMappingForRegion (Ann.Region (Ann.Position srcLine srcCol) _) state =
  let mapping = SourceMap.Mapping
        { SourceMap._mGenLine = state ^. outputLine
        , SourceMap._mGenCol = 0
        , SourceMap._mSrcIndex = 0
        , SourceMap._mSrcLine = fromIntegral srcLine - 1
        , SourceMap._mSrcCol = fromIntegral srcCol - 1
        , SourceMap._mNameIndex = Nothing
        }
   in state & sourceMapMappings %~ (mapping :)

-- | Build a SourceMap from accumulated state (dev mode only).
buildSourceMap :: Mode.Mode -> State -> Maybe SourceMap.SourceMap
buildSourceMap mode state =
  case mode of
    Mode.Prod {} -> Nothing
    Mode.Dev _ _ _ _ _ _ ->
      let sm = SourceMap.empty "canopy.js"
       in Just sm { SourceMap._smMappings = state ^. sourceMapMappings }

var :: Opt.Global -> Expr.Code -> JS.Stmt
var (Opt.Global home name) code =
  JS.Var (JsName.fromGlobal home name) (Expr.codeToExpr code)

-- GENERATE MANAGER

generateManager :: Mode.Mode -> Graph -> Opt.Global -> Opt.EffectsType -> State -> State
generateManager mode graph (Opt.Global home@(ModuleName.Canonical _ moduleName) _) effectsType state =
  let managerLVar =
        JS.LBracket
          (JS.Ref KN.platformEffectManagers)
          (JS.String (Name.toBuilder moduleName))
      (deps, args, stmts) =
        Kernel_.generateManagerHelp home effectsType
      createManager =
        (JS.ExprStmt . JS.Assign managerLVar $ JS.Call (JS.Ref KN.platformCreateManager) args)
   in List.foldl' addStmt (List.foldl' (addGlobal mode graph) state deps) (createManager : stmts)

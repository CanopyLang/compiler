{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Generate.JavaScript.CodeSplit.Generate — Per-chunk JavaScript generation
--
-- Orchestrates the complete code-splitting pipeline:
--
--   1. Analyze the global graph to produce a 'ChunkGraph'.
--   2. Generate JavaScript for each chunk using the existing traversal
--      machinery from "Generate.JavaScript".
--   3. Compute content hashes and filenames.
--   4. Produce the manifest and embed the chunk runtime.
--
-- The entry chunk receives the standard IIFE wrapper, runtime functions
-- (F2-F9, A2-A9), the chunk loader runtime, manifest assignment, and all
-- eagerly-loaded globals.  Lazy and shared chunks are wrapped in
-- @__canopy_register@ calls.
--
-- @since 0.19.2
module Generate.JavaScript.CodeSplit.Generate
  ( generateChunks,
    generateForChunk,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Kernel as K
import qualified Canopy.ModuleName as ModuleName
import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy as BL
import Data.Word (Word8)
import qualified Data.Index as Index
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Name (Name)
import qualified Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.JavaScript.Functions as Functions
import qualified Generate.JavaScript.Minify as Minify
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.CodeSplit.Manifest as Manifest
import qualified Generate.JavaScript.CodeSplit.Runtime as Runtime
import Generate.JavaScript.CodeSplit.Types
  ( Chunk (..),
    ChunkGraph (..),
    ChunkId (..),
    ChunkKind (..),
    ChunkOutput (..),
    SplitConfig,
    SplitOutput (..),
  )
import qualified Generate.JavaScript.CodeSplit.Analyze as Analyze
import qualified Generate.JavaScript.SourceMap as SourceMap
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import qualified Reporting.Annotation as A
import qualified Reporting.InternalError as InternalError
import Prelude hiding (cycle, print)

-- | Type alias matching Generate.JavaScript convention.
type Graph = Map Opt.Global Opt.Node

-- | Type alias for main entry points.
type Mains = Map ModuleName.Canonical Opt.Main

-- | Generate all chunks from the split configuration and global graph.
--
-- This is the top-level entry point for code-split JavaScript generation.
-- When no lazy imports exist the result contains a single entry chunk.
--
-- @since 0.19.2
generateChunks ::
  Mode.Mode ->
  Opt.GlobalGraph ->
  Mains ->
  Map String a ->
  SplitConfig ->
  SplitOutput
generateChunks inputMode globalGraph@(Opt.GlobalGraph rawGraph _ _) mains _ffiInfos config =
  SplitOutput
    { _soChunks = outputs,
      _soManifest = Manifest.generateManifest outputs
    }
  where
    (graph, mode) = prepareGraph inputMode rawGraph
    chunkGraph = Analyze.analyze config globalGraph mains
    entryOut = generateEntryChunk mode graph mains chunkGraph
    lazyOuts = map (generateLazyChunk mode graph chunkGraph) (_cgLazy chunkGraph)
    sharedOuts = map (generateSharedChunk mode graph chunkGraph) (_cgShared chunkGraph)
    outputs = entryOut : lazyOuts ++ sharedOuts

-- | Prepare the graph: minify in prod mode.
prepareGraph :: Mode.Mode -> Graph -> (Graph, Mode.Mode)
prepareGraph inputMode rawGraph =
  case inputMode of
    Mode.Prod fields elmCompat ffiUnsafe _ ffiAliases ->
      let minified = Minify.minifyGraph rawGraph
          pool = StringPool.buildPool minified
       in (minified, Mode.Prod fields elmCompat ffiUnsafe pool ffiAliases)
    Mode.Dev _ _ _ _ -> (rawGraph, inputMode)

-- | Generate JavaScript for the globals in a single chunk.
--
-- Reuses the same DFS traversal as "Generate.JavaScript" but restricts
-- to the globals assigned to the given chunk.  Globals belonging to
-- other chunks are skipped — they are accessed via @__canopy_load@.
--
-- @since 0.19.2
generateForChunk ::
  Mode.Mode ->
  Graph ->
  Set Opt.Global ->
  Map Opt.Global A.Region ->
  (Builder, [SourceMap.Mapping])
generateForChunk mode graph chunkGlobals srcLocs =
  (stateToBuilder finalState, _stMappings finalState)
  where
    initState = emptyTraversalState srcLocs
    finalState = Set.foldl' (addGlobalForChunk mode graph chunkGlobals) initState chunkGlobals

-- | Generate the entry chunk.
generateEntryChunk :: Mode.Mode -> Graph -> Mains -> ChunkGraph -> ChunkOutput
generateEntryChunk mode graph mains chunkGraph =
  ChunkOutput
    { _coChunkId = _chunkId entry,
      _coKind = EntryChunk,
      _coBuilder = jsBuilder,
      _coHash = hash,
      _coFilename = Manifest.chunkFilename EntryChunk (_chunkId entry) hash
    }
  where
    entry = _cgEntry chunkGraph
    srcLocs = Map.empty
    (bodyBuilder, _mappings) = generateForChunk mode graph (_chunkGlobals entry) srcLocs
    header =
      if Mode.isElmCompatible mode
        then "(function(scope){\n'use strict';\n"
        else "(function(scope){'use strict';\n"
    poolDecls = StringPool.poolDeclarations (Mode.stringPool mode)
    manifestAssign = Manifest.generateManifestAssignment []
    jsBuilder =
      header
        <> Functions.functions
        <> Runtime.chunkRuntime
        <> manifestAssign
        <> poolDecls
        <> bodyBuilder
        <> toMainExports mode mains
        <> "\n}(typeof window !== 'undefined' ? window : this));"
    hash = Manifest.contentHash jsBuilder

-- | Generate a lazy chunk wrapped in __canopy_register.
generateLazyChunk :: Mode.Mode -> Graph -> ChunkGraph -> Chunk -> ChunkOutput
generateLazyChunk mode graph _chunkGraph chunk =
  ChunkOutput
    { _coChunkId = _chunkId chunk,
      _coKind = LazyChunk,
      _coBuilder = jsBuilder,
      _coHash = hash,
      _coFilename = Manifest.chunkFilename LazyChunk (_chunkId chunk) hash
    }
  where
    srcLocs = Map.empty
    (bodyBuilder, _mappings) = generateForChunk mode graph (_chunkGlobals chunk) srcLocs
    ChunkId cidText = _chunkId chunk
    exports = generateChunkExports mode (_chunkGlobals chunk)
    jsBuilder =
      "__canopy_register(\""
        <> B.stringUtf8 (Text.unpack cidText)
        <> "\", function() {\n"
        <> bodyBuilder
        <> "return {"
        <> exports
        <> "};\n});\n"
    hash = Manifest.contentHash jsBuilder

-- | Generate a shared chunk wrapped in __canopy_register.
generateSharedChunk :: Mode.Mode -> Graph -> ChunkGraph -> Chunk -> ChunkOutput
generateSharedChunk mode graph _chunkGraph chunk =
  ChunkOutput
    { _coChunkId = _chunkId chunk,
      _coKind = SharedChunk,
      _coBuilder = jsBuilder,
      _coHash = hash,
      _coFilename = Manifest.chunkFilename SharedChunk (_chunkId chunk) hash
    }
  where
    srcLocs = Map.empty
    (bodyBuilder, _mappings) = generateForChunk mode graph (_chunkGlobals chunk) srcLocs
    ChunkId cidText = _chunkId chunk
    exports = generateChunkExports mode (_chunkGlobals chunk)
    jsBuilder =
      "__canopy_register(\""
        <> B.stringUtf8 (Text.unpack cidText)
        <> "\", function() {\n"
        <> bodyBuilder
        <> "return {"
        <> exports
        <> "};\n});\n"
    hash = Manifest.contentHash jsBuilder

-- | Generate export mapping for a chunk's globals.
--
-- Produces @'$var_name': $var_name, ...@ for each global in the chunk.
generateChunkExports :: Mode.Mode -> Set Opt.Global -> Builder
generateChunkExports _mode globals =
  mconcat (List.intersperse "," (map exportGlobal (Set.toList globals)))
  where
    exportGlobal (Opt.Global home name) =
      let jsName = JsName.fromGlobal home name
       in "'" <> JsName.toBuilder jsName <> "':" <> JsName.toBuilder jsName

-- GRAPH TRAVERSAL STATE (mirrors Generate.JavaScript.State)

-- | Traversal state for per-chunk code generation.
data TraversalState = TraversalState
  { _stRevKernels :: ![Builder],
    _stRevBuilders :: ![Builder],
    _stSeen :: !(Set Opt.Global),
    _stSeenKernelChunks :: !(Set ByteString),
    _stOutputLine :: !Int,
    _stMappings :: ![SourceMap.Mapping],
    _stSourceLocs :: !(Map Opt.Global A.Region)
  }

-- | Empty traversal state.
emptyTraversalState :: Map Opt.Global A.Region -> TraversalState
emptyTraversalState locs =
  TraversalState mempty [] Set.empty Set.empty 0 [] locs

-- | Convert traversal state to a Builder.
stateToBuilder :: TraversalState -> Builder
stateToBuilder (TraversalState revKernels revBuilders _ _ _ _ _) =
  prependBuilders revKernels (prependBuilders revBuilders mempty)

-- | Fold builders in reverse order.
prependBuilders :: [Builder] -> Builder -> Builder
prependBuilders revBs monolith =
  List.foldl' (flip (<>)) monolith revBs

-- | Add a global to the traversal state, restricted to chunk membership.
addGlobalForChunk ::
  Mode.Mode -> Graph -> Set Opt.Global -> TraversalState -> Opt.Global -> TraversalState
addGlobalForChunk mode graph chunkGlobals state global
  | Set.member global (_stSeen state) = state
  | not (Set.member global chunkGlobals) = state
  | otherwise =
      addGlobalHelp mode graph chunkGlobals global $
        state {_stSeen = Set.insert global (_stSeen state)}

-- | Process a single global node.
addGlobalHelp ::
  Mode.Mode -> Graph -> Set Opt.Global -> Opt.Global -> TraversalState -> TraversalState
addGlobalHelp mode graph chunkGlobals currentGlobal state =
  case Map.lookup currentGlobal graph of
    Nothing -> state
    Just node -> emitNode mode graph chunkGlobals currentGlobal node state

-- | Emit JavaScript for a graph node.
emitNode ::
  Mode.Mode ->
  Graph ->
  Set Opt.Global ->
  Opt.Global ->
  Opt.Node ->
  TraversalState ->
  TraversalState
emitNode mode graph chunkGlobals currentGlobal node state =
  case node of
    Opt.Define expr deps ->
      addStmt (addDeps deps state) (varStmt currentGlobal (Expr.generate mode expr))
    Opt.DefineTailFunc argNames body deps ->
      addStmt (addDeps deps state) (tailFuncStmt mode currentGlobal argNames body)
    Opt.Ctor index arity ->
      addStmt state (varStmt currentGlobal (Expr.generateCtor mode currentGlobal index arity))
    Opt.Link linkedGlobal ->
      addGlobalForChunk mode graph chunkGlobals state linkedGlobal
    Opt.Cycle names values functions deps ->
      emitCycle mode currentGlobal names values functions (addDeps deps state)
    Opt.Manager effectsType ->
      emitManager mode graph chunkGlobals currentGlobal effectsType state
    Opt.Kernel chunks deps ->
      emitKernel mode chunks (addDeps deps state) currentGlobal
    Opt.Enum index ->
      addStmt state (emitEnum mode currentGlobal index)
    Opt.Box ->
      addStmt state (emitBox mode currentGlobal)
    Opt.PortIncoming decoder deps ->
      addStmt (addDeps deps state) (emitPort mode currentGlobal "incomingPort" decoder)
    Opt.PortOutgoing encoder deps ->
      addStmt (addDeps deps state) (emitPort mode currentGlobal "outgoingPort" encoder)
  where
    addDeps deps st =
      Set.foldl' (addGlobalForChunk mode graph chunkGlobals) st deps

-- | Build a var statement for a global.
varStmt :: Opt.Global -> Expr.Code -> JS.Stmt
varStmt (Opt.Global home name) code =
  JS.Var (JsName.fromGlobal home name) (Expr.codeToExpr code)

-- | Build a tail function var statement.
tailFuncStmt :: Mode.Mode -> Opt.Global -> [Name] -> Opt.Expr -> JS.Stmt
tailFuncStmt mode (Opt.Global home name) argNames body =
  JS.Var (JsName.fromGlobal home name) (Expr.generateTailDefExpr mode name argNames body)

-- | Emit cycle code.
emitCycle ::
  Mode.Mode -> Opt.Global -> [Name] -> [(Name, Opt.Expr)] -> [Opt.Def] -> TraversalState -> TraversalState
emitCycle mode (Opt.Global home _) _names values functions state =
  List.foldl' addStmt state allStmts
  where
    functionStmts = fmap (generateCycleFunc mode home) functions
    safeStmts = fmap (generateSafeCycle mode home) values
    realStmts = fmap (generateRealCycle home) values
    allStmts = functionStmts ++ safeStmts ++ realStmts

-- | Generate a cycle function statement.
generateCycleFunc :: Mode.Mode -> ModuleName.Canonical -> Opt.Def -> JS.Stmt
generateCycleFunc mode home def =
  case def of
    Opt.Def name expr ->
      JS.Var (JsName.fromGlobal home name) (Expr.codeToExpr (Expr.generate mode expr))
    Opt.TailDef name args expr ->
      JS.Var (JsName.fromGlobal home name) (Expr.generateTailDefExpr mode name args expr)

-- | Generate safe cycle initialization.
generateSafeCycle :: Mode.Mode -> ModuleName.Canonical -> (Name, Opt.Expr) -> JS.Stmt
generateSafeCycle mode home (name, expr) =
  JS.FunctionStmt (JsName.fromCycle home name) [] $
    Expr.codeToStmtList (Expr.generate mode expr)

-- | Generate real cycle assignment.
generateRealCycle :: ModuleName.Canonical -> (Name, expr) -> JS.Stmt
generateRealCycle home (name, _) =
  JS.Block
    [ JS.Var realName (JS.Call (JS.Ref safeName) []),
      JS.ExprStmt . JS.Assign (JS.LRef safeName) $ JS.Function Nothing [] [JS.Return (JS.Ref realName)]
    ]
  where
    safeName = JsName.fromCycle home name
    realName = JsName.fromGlobal home name

-- | Emit manager code.
emitManager ::
  Mode.Mode ->
  Graph ->
  Set Opt.Global ->
  Opt.Global ->
  Opt.EffectsType ->
  TraversalState ->
  TraversalState
emitManager mode graph chunkGlobals (Opt.Global home@(ModuleName.Canonical _ moduleName) _) effectsType state =
  List.foldl' addStmt depsState (createManager : leafStmts)
  where
    (deps, args, leafStmts) = managerHelp home effectsType
    depsState = List.foldl' (addGlobalForChunk mode graph chunkGlobals) state deps
    managerLVar =
      JS.LBracket
        (JS.Ref (JsName.fromKernel Name.platform "effectManagers"))
        (JS.String (Name.toBuilder moduleName))
    createManager =
      JS.ExprStmt . JS.Assign managerLVar $
        JS.Call (JS.Ref (JsName.fromKernel Name.platform "createManager")) args

-- | Manager helper: compute deps, args, and leaf stmts.
managerHelp :: ModuleName.Canonical -> Opt.EffectsType -> ([Opt.Global], [JS.Expr], [JS.Stmt])
managerHelp home effectsType =
  let ref n = JS.Ref (JsName.fromGlobal home n)
      dep = Opt.Global home
   in case effectsType of
        Opt.Cmd ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "cmdMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", ref "cmdMap"],
            [emitLeaf home "command"]
          )
        Opt.Sub ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "subMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", JS.Int 0, ref "subMap"],
            [emitLeaf home "subscription"]
          )
        Opt.Fx ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "cmdMap", dep "subMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", ref "cmdMap", ref "subMap"],
            [emitLeaf home "command", emitLeaf home "subscription"]
          )

-- | Generate leaf statement for effect manager.
emitLeaf :: ModuleName.Canonical -> Name -> JS.Stmt
emitLeaf home@(ModuleName.Canonical _ moduleName) name =
  JS.Var (JsName.fromGlobal home name) $
    JS.Call (JS.Ref (JsName.fromKernel Name.platform "leaf")) [JS.String (Name.toBuilder moduleName)]

-- | Emit kernel code.
emitKernel :: Mode.Mode -> [K.Chunk] -> TraversalState -> Opt.Global -> TraversalState
emitKernel mode chunks state currentGlobal =
  let kernelCode = generateKernel mode chunks
      kernelBytes = BL.toStrict (B.toLazyByteString kernelCode)
   in if Set.member kernelBytes (_stSeenKernelChunks state)
        then state {_stSeen = Set.insert currentGlobal (_stSeen state)}
        else
          state
            { _stRevKernels = kernelCode : _stRevKernels state,
              _stSeen = Set.insert currentGlobal (_stSeen state),
              _stSeenKernelChunks = Set.insert kernelBytes (_stSeenKernelChunks state),
              _stOutputLine = _stOutputLine state + countNewlines kernelCode
            }

-- | Generate kernel JavaScript.
generateKernel :: Mode.Mode -> [K.Chunk] -> Builder
generateKernel mode = List.foldr (addKernelChunk mode) mempty

-- | Add a single kernel chunk to the builder.
addKernelChunk :: Mode.Mode -> K.Chunk -> Builder -> Builder
addKernelChunk mode chunk builder =
  case chunk of
    K.JS javascript -> B.byteString javascript <> builder
    K.CanopyVar home name -> JsName.toBuilder (JsName.fromGlobal home name) <> builder
    K.JsVar home name -> JsName.toBuilder (JsName.fromKernel home name) <> builder
    K.CanopyField name -> JsName.toBuilder (Expr.generateField mode name) <> builder
    K.JsField int -> JsName.toBuilder (JsName.fromInt int) <> builder
    K.JsEnum int -> B.intDec int <> builder
    K.Debug -> handleDebugChunk mode builder
    K.Prod -> handleProdChunk mode builder

-- | Handle debug kernel chunk.
handleDebugChunk :: Mode.Mode -> Builder -> Builder
handleDebugChunk mode builder =
  case mode of
    Mode.Dev _ _ _ _ -> builder
    Mode.Prod {} -> "_UNUSED" <> builder

-- | Handle prod kernel chunk.
handleProdChunk :: Mode.Mode -> Builder -> Builder
handleProdChunk mode builder =
  case mode of
    Mode.Dev _ _ _ _ -> "_UNUSED" <> builder
    Mode.Prod {} -> builder

-- | Emit enum statement.
emitEnum :: Mode.Mode -> Opt.Global -> Index.ZeroBased -> JS.Stmt
emitEnum mode global@(Opt.Global home name) index =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ _ _ -> Expr.codeToExpr (Expr.generateCtor mode global index 0)
      Mode.Prod {} -> JS.Int (Index.toMachine index)

-- | Emit box statement.
emitBox :: Mode.Mode -> Opt.Global -> JS.Stmt
emitBox mode global@(Opt.Global home name) =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ _ _ -> Expr.codeToExpr (Expr.generateCtor mode global Index.first 1)
      Mode.Prod {} -> JS.Ref (JsName.fromGlobal ModuleName.basics Name.identity)

-- | Emit port statement.
emitPort :: Mode.Mode -> Opt.Global -> Name -> Opt.Expr -> JS.Stmt
emitPort mode (Opt.Global home name) makePort converter =
  JS.Var (JsName.fromGlobal home name) $
    JS.Call
      (JS.Ref (JsName.fromKernel Name.platform makePort))
      [ JS.String (Name.toBuilder name),
        Expr.codeToExpr (Expr.generate mode converter)
      ]

-- | Add a statement to the traversal state.
addStmt :: TraversalState -> JS.Stmt -> TraversalState
addStmt state stmt =
  addBuilder state (JS.stmtToBuilder stmt)

-- | Add a builder to the traversal state.
addBuilder :: TraversalState -> Builder -> TraversalState
addBuilder state builder =
  state
    { _stRevBuilders = builder : _stRevBuilders state,
      _stOutputLine = _stOutputLine state + countNewlines builder
    }

-- | Count newline bytes in a Builder.
countNewlines :: Builder -> Int
countNewlines b =
  BL.foldl' countNL 0 (B.toLazyByteString b)
  where
    countNL :: Int -> Word8 -> Int
    countNL !acc 0x0A = acc + 1
    countNL !acc _ = acc

-- MAIN EXPORTS (duplicated from Generate.JavaScript for chunk-level use)

-- | Generate main export code.
toMainExports :: Mode.Mode -> Mains -> Builder
toMainExports mode mains =
  let export = JsName.fromKernel Name.platform "export"
      exports = generateExports mode (Map.foldrWithKey addToTrie emptyTrie mains)
   in JsName.toBuilder export <> "(" <> exports <> ");"
        <> "scope['Canopy'] = scope['Elm'];"

-- | Generate nested export object.
generateExports :: Mode.Mode -> Trie -> Builder
generateExports mode (Trie maybeMain subs) =
  let starter end =
        case maybeMain of
          Nothing -> "{"
          Just (home, main) ->
            "{'init':"
              <> JS.exprToBuilder (Expr.generateMain mode home main)
              <> end
   in case Map.toList subs of
        [] -> starter "" <> "}"
        (name, subTrie) : otherSubTries ->
          starter ","
            <> "'"
            <> Name.toBuilder name
            <> "':"
            <> generateExports mode subTrie
            <> List.foldl' (addSubTrie mode) "}" otherSubTries

-- | Add a sub-trie to exports.
addSubTrie :: Mode.Mode -> Builder -> (Name, Trie) -> Builder
addSubTrie mode end (name, trie) =
  ",'" <> Name.toBuilder name <> "':" <> generateExports mode trie <> end

-- | Trie for organizing module exports.
data Trie = Trie
  { _triMain :: !(Maybe (ModuleName.Canonical, Opt.Main)),
    _triSubs :: !(Map Name Trie)
  }

-- | Empty trie.
emptyTrie :: Trie
emptyTrie = Trie Nothing Map.empty

-- | Add a module to the trie.
addToTrie :: ModuleName.Canonical -> Opt.Main -> Trie -> Trie
addToTrie home@(ModuleName.Canonical _ moduleName) main trie =
  mergeTrie trie (segmentsToTrie home (Name.splitDots moduleName) main)

-- | Build a trie from name segments.
segmentsToTrie :: ModuleName.Canonical -> [Name] -> Opt.Main -> Trie
segmentsToTrie home segments main =
  case segments of
    [] -> Trie (Just (home, main)) Map.empty
    segment : rest -> Trie Nothing (Map.singleton segment (segmentsToTrie home rest main))

-- | Merge two tries.
mergeTrie :: Trie -> Trie -> Trie
mergeTrie (Trie main1 subs1) (Trie main2 subs2) =
  Trie (mergeMain main1 main2) (Map.unionWith mergeTrie subs1 subs2)

-- | Merge main entries (at most one should be present).
mergeMain :: Maybe a -> Maybe a -> Maybe a
mergeMain Nothing b = b
mergeMain a Nothing = a
mergeMain (Just _) (Just _) =
  InternalError.report
    "Generate.JavaScript.CodeSplit.Generate.mergeMain"
    "cannot have two modules with the same name"
    "Module names must be unique."

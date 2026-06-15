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

    -- * Tree-shaker root scan (testing)
    -- | Exposed for "Unit.Generate.TreeShakeRootsTest". These scan the
    -- already-generated output bytes for kernel runtime references and F\/A
    -- arity helpers so the tree-shaker's roots match what the output actually
    -- emits — guarding against the @F7 is not defined@ /
    -- @_Platform_export is not defined@ regression in native IIFE bundles.
    scanRuntimeIdents,
    scanArities,
    generatedIdentTokens,
    arityToken,
    isIdentByte,
    isKernelIdent,

    -- * Re-exported from Generate.JavaScript.Runtime.Registry (testing)
    -- | Re-exported so "Unit.Generate.TreeShakeRootsTest" can name the
    -- 'Registry.RuntimeId' result type of 'scanRuntimeIdents' and assert the
    -- registry-closure invariants without depending on the otherwise-hidden
    -- @Generate.JavaScript.Runtime.Registry@ module.
    Registry.RuntimeId(..),
    Registry.allIds,
    Registry.closeDeps,
    Registry.lookupDef,

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
import Data.Word (Word8)
import qualified Data.Text as Text
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Coverage as Coverage
import qualified Generate.JavaScript.Ability as Ability
import qualified Generate.JavaScript.Expression as Expr
import Generate.JavaScript.FFI
  ( FFIInfo (..),
    extractFFIAliases,
    extractCanopyTypeFunctions,
    ffiAlias,
    ffiContent,
    ffiFilePath,
    generateFFIContent,
  )
import qualified FFI.TypeParser as TypeParser
import qualified Generate.JavaScript.FFI.Registry as FFIRegistry
import qualified Generate.JavaScript.FFIRuntime as FFIRuntime
import qualified Generate.JavaScript.HermesShim as HermesShim
import qualified Generate.JavaScript.Runtime as Runtime
import qualified Generate.JavaScript.Runtime.Registry as Registry
import qualified Generate.JavaScript.Functions as Functions
import qualified Generate.TreeShake as TreeShake
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
    _coverageBaseIds :: Map Opt.Global Int,
    -- Source map: distinct source modules → their @sources@ array index, accumulated as
    -- mappings are emitted so each mapping records WHICH module its original position is in
    -- (dev mode only; empty under @--optimize@).
    _smSrcIndices :: Map ModuleName.Canonical Int
  }

makeLenses ''State

-- GENERATE

generate :: Mode.Mode -> Opt.GlobalGraph -> Mains -> Map String FFIInfo -> (Builder, Maybe SourceMap.SourceMap, Maybe Coverage.CoverageMap)
generate inputMode globalGraph@(Opt.GlobalGraph rawGraph _ sourceLocs) mains ffiInfos =
  let ffiAliases = extractFFIAliases ffiInfos
      (graph, mode) = case inputMode of
        Mode.Prod fields elmCompat ffiUnsafe ffiDbg _ _ _ ->
          let -- Assign GLOBAL short names first (rawGraph and the locally-minified
              -- graph share the same Global keys, so the map is identical either
              -- way). The set of assigned global short names is then RESERVED
              -- during local minification so a function-local @var a@ can never
              -- shadow a referenced top-level global @a@ (the two share one
              -- single-letter namespace) — which would otherwise read an
              -- uninitialised local instead of the global and crash.
              globalRenameMap = Minify.buildGlobalRenameMap ffiAliases rawGraph reachable
              reservedGlobals = Set.fromList (Map.elems globalRenameMap)
              minified = Minify.minifyGraph reservedGlobals rawGraph
              pool = StringPool.buildPool minified
           in (minified, Mode.Prod fields elmCompat ffiUnsafe ffiDbg pool ffiAliases globalRenameMap)
        Mode.Dev debugTypes elmCompat ffiUnsafe ffiDbg _ cov ->
          (rawGraph, Mode.Dev debugTypes elmCompat ffiUnsafe ffiDbg ffiAliases cov)
      shouldTrackLines = case mode of Mode.Dev {} -> True; Mode.Prod {} -> False
      covIds = if Mode.isCoverage mode then Coverage.computeBaseIds graph else Map.empty
      -- Pre-compute reachable globals once; used for both FFI and runtime deps.
      reachable = TreeShake.reachableGlobals globalGraph mains
      -- Pre-compute FFI usage at AST level before code generation.
      -- Uses reachableGlobals to find all FFI-alias globals reachable from main
      -- without inspecting the generated Builder during traversal.
      usedFFIFuncs = computeFFIUsage ffiAliases rawGraph reachable
      -- Pre-compute runtime deps from the Opt AST — eliminates the Phase 2
      -- materialization of innerContent for byte-level scanning.
      (rawNeededRuntime, astArities) = collectRuntimeDeps rawGraph reachable
      -- Also scan FFI file content for _Module_name references (e.g. _Basics_e)
      -- that only appear inside embedded FFI files and not in the Canopy AST.
      ffiRuntimeDeps = collectFFIRuntimeDeps ffiInfos
      -- Scan FFI files for direct F2-F9 / A2-A9 usage (e.g. F6(...) in list.js).
      -- These bypass the Canopy optimizer and are invisible to collectRuntimeDeps.
      ffiArities = collectFFIArities ffiInfos
      -- Runtime + arity references emitted by the code GENERATOR itself — absent from the
      -- optimized AST — would otherwise be dropped by the tree-shaker. The canonical cases:
      -- the program-export call `_Platform_export({...})` that 'Kernel_.toMainExports'
      -- appends to 'innerContent', and the `F7`/`A3` arity helpers called by emitted
      -- runtime functions like `_Json_map6`. Effect-manager glue is the same shape and only
      -- survives today via a hand-written seed ('managerRuntimeIds'). Rather than hand-seed
      -- each such symbol (a fragile whack-a-mole that silently regresses to a runtime
      -- ReferenceError), we make the tree-shaker's roots match the ACTUAL generated output:
      -- materialize the generated content + the emitted runtime, and scan BOTH for kernel
      -- identifiers and arity helpers. What ships is then exactly what the output
      -- references — correct by construction, for every current and future generated ref.
      innerBytes = BL.toStrict (BB.toLazyByteString innerContent)
      generatedRuntimeDeps = scanRuntimeIdents innerBytes
      neededRuntime = Registry.closeDeps (rawNeededRuntime <> ffiRuntimeDeps <> generatedRuntimeDeps)
      runtimeBytes = BL.toStrict (BB.toLazyByteString (Runtime.emitNeeded mode neededRuntime))
      neededArities = astArities <> ffiArities <> scanArities innerBytes <> scanArities runtimeBytes
      -- Traverse only from entry points — dead code is never visited.
      state = Map.foldrWithKey (addMain mode graph) (emptyState shouldTrackLines sourceLocs covIds) mains
      header = if Mode.isElmCompatible mode
               then "(function(scope){\n'use strict';\n"
               else "(function(scope){'use strict';\n"
      debuggerStub = "var _Debugger_unsafeCoerce = function(value) { return value; };\n"
      -- CMP-10: Hermes stdlib shims for the native (Hermes) bundle target.
      -- This IIFE bundle IS the native bundle the Hermes host loads (the web
      -- path uses the separate ESM emitter), so the shim is spliced here. It is
      -- a no-op shape under a full engine (Node/V8) — it normalises Intl/Date and
      -- gates unsupported RegExp features only when the divergence is present —
      -- so the SAME bundle is identical under the Node conformance baseline and
      -- under Hermes. Emitted right after the debugger stub, before any FFI/user
      -- content can observe Intl/Date/RegExp. Its newline count flows into
      -- 'genLineBase' via 'innerPreamble' -> 'bundlePrefix', keeping the dev
      -- source map aligned (CMP-6).
      hermesShim = HermesShim.hermesShimPreamble
      poolDecls = StringPool.poolDeclarations (Mode.stringPool mode)
      coveragePreamble = if Mode.isCoverage mode then Coverage.coverageRuntimePreamble else mempty
      -- Phase 1: generate all non-runtime content inside the IIFE.
      -- This is everything except the F/A arity helpers and the Canopy runtime.
      --
      -- 'innerPreamble' is everything emitted INSIDE the IIFE before the
      -- traversal output ('stateToBuilder state'). Split out so its newline
      -- count can feed the source-map generated-line base (see 'genLineBase').
      innerPreamble =
        debuggerStub
          <> hermesShim
          <> generateFFIContent mode graph ffiInfos usedFFIFuncs
          <> perfNote mode
          <> poolDecls
          <> coveragePreamble
      innerContent =
        innerPreamble
          <> stateToBuilder state
          <> Kernel_.toMainExports mode mains
          <> "\nif (typeof global !== 'undefined') { global.Canopy = scope['Canopy']; global.Elm = scope['Elm']; }"
          <> "\n}(typeof window !== 'undefined' ? window : this));"
      -- Everything in the final bundle that precedes the IIFE header through the
      -- start of the traversal output ('stateToBuilder state'), in byte order:
      -- the IIFE header, the F/A arity helpers, the Canopy runtime, the
      -- FFI-runtime preamble, and the inner preamble. Source-map mappings record
      -- generated lines relative to the START of the traversal output (State
      -- begins at outputLine 0), so the whole bundle map must be shifted down by
      -- the newline count of this prefix — otherwise every dev red-box line is
      -- off by the entire runtime (CMP-6).
      bundlePrefix =
        header
          <> Functions.generateConditionalFunctions neededArities
          <> BB.byteString runtimeBytes
          <> FFIRuntime.scanAndEmitRuntime mode (BB.byteString innerBytes)
          <> innerPreamble
      genLineBase =
        if shouldTrackLines
          then countNewlines bundlePrefix
          else 0
      jsBuilder =
        header
          <> Functions.generateConditionalFunctions neededArities
          <> BB.byteString runtimeBytes
          <> FFIRuntime.scanAndEmitRuntime mode (BB.byteString innerBytes)
          <> BB.byteString innerBytes
      sourceMap = buildSourceMap genLineBase mode state
      coverageMap = if Mode.isCoverage mode
                    then Just (Coverage.buildCoverageMap graph sourceLocs)
                    else Nothing
   in (jsBuilder, sourceMap, coverageMap)


addMain :: Mode.Mode -> Graph -> ModuleName.Canonical -> Opt.Main -> State -> State
addMain mode graph home _ state =
  addGlobal mode graph state (Opt.Global home "main")

-- | Compute which FFI functions are reachable from the entry points.
--
-- Scans the set of reachable globals produced by 'TreeShake.reachableGlobals'
-- and extracts the FFI-alias globals: those whose module name is a known FFI
-- alias and which are absent from the compiled graph (i.e., they are
-- references into a foreign JS file, not compiled Canopy definitions).
--
-- This runs at AST level before code generation, keeping FFI tree-shaking
-- decisions out of the code-generator state.
--
-- @since 0.19.3
computeFFIUsage
  :: Set Name.Name
  -> Graph
  -> Set Opt.Global
  -> Map Name.Name (Set Name.Name)
computeFFIUsage ffiAliases graph reachable =
  Set.foldl' addIfFFI Map.empty reachable
  where
    addIfFFI acc global@(Opt.Global home name) =
      let moduleName = ModuleName._module home
      in if Set.member moduleName ffiAliases && Map.notMember global graph
         then Map.insertWith Set.union moduleName (Set.singleton name) acc
         else acc

-- | Compute needed runtime functions and F\/A arities from the reachable Opt AST.
--
-- Replaces the Phase 2 byte-scan of the generated 'Builder'. Walks every
-- reachable 'Opt.Node' to find:
--
--   * 'Opt.VarRuntime' references — converted to 'Registry.RuntimeId'
--   * Multi-argument 'Opt.Function' definitions — arity from 'length args'
--   * Multi-argument 'Opt.Call' applications — arity from 'length args'
--
-- An arity @n@ (2–9) is needed when any 'Opt.Function' has @n@ parameters
-- (causes @Fn(function(...) {...})@) or any 'Opt.Call' has @n@ arguments
-- (causes @An(f, ...)@). Both use the same arity set.
--
-- @since 0.20.4
collectRuntimeDeps
  :: Graph
  -> Set Opt.Global
  -> (Set Registry.RuntimeId, Set Int)
collectRuntimeDeps graph = foldMap (nodeDeps graph) . Set.toList

-- | Walk a single node, collecting runtime refs and needed arities.
nodeDeps :: Graph -> Opt.Global -> (Set Registry.RuntimeId, Set Int)
nodeDeps graph global =
  maybe mempty nodeExprDeps (Map.lookup global graph)

-- | Extract runtime deps from a node variant.
--
-- 'Opt.Kernel' chunks are scanned for 'Kernel.JsVar' entries so that
-- runtime constants referenced only from kernel code (e.g. @_Basics_e@,
-- @_Basics_pi@) are included by the tree-shaker even when no user-code
-- 'Opt.VarRuntime' reference exists.
nodeExprDeps :: Opt.Node -> (Set Registry.RuntimeId, Set Int)
nodeExprDeps node =
  case node of
    Opt.Define expr _               -> exprDeps expr
    Opt.DefineTailFunc _ expr _     -> exprDeps expr
    Opt.Cycle _ vals fns _          -> foldMap (exprDeps . snd) vals <> foldMap defDeps fns
    Opt.PortIncoming expr _         -> exprDeps expr
    Opt.PortOutgoing expr _         -> exprDeps expr
    Opt.ImplDict _ methods _        -> foldMap exprDeps (Map.elems methods)
    Opt.Kernel chunks _             -> (foldMap kernelChunkRuntimeId chunks, Set.empty)
    -- Effect managers bypass the normal Opt.VarRuntime tracking path: they emit
    -- _Platform_createManager, _Platform_effectManagers, and _Platform_leaf
    -- directly as JS.Ref nodes inside the statements generated by generateManager
    -- and generateManagerHelp/generateLeaf. We derive the needed runtime IDs by
    -- re-running those generators with a dummy home and walking the resulting JS
    -- AST — so this automatically picks up any future runtime refs added there.
    Opt.Manager effectsType         ->
      (managerRuntimeIds effectsType, Set.empty)
    -- Constructor nodes carry their arity; generateCtor wraps them in F<arity>,
    -- so the corresponding F/A helpers must be emitted by the tree shaker.
    Opt.Ctor _ arity                -> arityDep arity
    -- Link, Enum, and Box carry no runtime deps of their own.
    -- Link targets are already in the reachable set via TreeShake.reachableGlobals.
    -- Enum has arity 0 and Box has arity 1, neither requiring F/A wrappers.
    Opt.Link _                      -> mempty
    Opt.Enum _                      -> mempty
    Opt.Box                         -> mempty

-- | Collect runtime deps from a single kernel chunk.
--
-- Only 'Kernel.JsVar' contributes runtime deps; other chunk kinds are
-- raw JS or Canopy-level references that don't map to registry entries.
kernelChunkRuntimeId :: Kernel.Chunk -> Set Registry.RuntimeId
kernelChunkRuntimeId chunk =
  case chunk of
    Kernel.JsVar home name -> Set.singleton (Registry.runtimeIdFromKernel home name)
    _                      -> Set.empty

-- | Derive the runtime IDs needed by an effect manager node by actually running
-- the JS generators ('generateManager' + 'generateManagerHelp') with a dummy
-- home module and walking the produced JS AST for kernel 'JS.Ref' nodes.
--
-- Using a dummy home is safe because 'generateManagerHelp' only uses the home
-- to produce Canopy-global refs (via 'JsName.fromGlobal'), which start with
-- @$@ and are filtered out by 'jsNameToRuntimeId'. The runtime refs
-- (@_Platform_createManager@, @_Platform_effectManagers@, @_Platform_leaf@)
-- come from the @KN.*@ constants and are independent of the home module.
--
-- This approach is automatic: if 'generateManagerHelp' or 'generateManager'
-- ever add references to new runtime functions, they are included here without
-- any manual updates.
managerRuntimeIds :: Opt.EffectsType -> Set Registry.RuntimeId
managerRuntimeIds effectsType =
  let (_, args, stmts) = Kernel_.generateManagerHelp dummyHome effectsType
      -- Reproduce the createManager statement from generateManager
      lvar   = JS.LBracket (JS.Ref KN.platformEffectManagers) (JS.String "x")
      create = JS.ExprStmtWithSemi (JS.Assign lvar (JS.Call (JS.Ref KN.platformCreateManager) args))
  in foldMap jsStmtRuntimeIds (create : stmts)
  where
    dummyHome = ModuleName.Canonical Pkg.core Name.platform

-- | Walk a JS statement, collecting 'Registry.RuntimeId's for every kernel
-- runtime 'JS.Ref' encountered. Kernel refs have the form @_Module_name@.
jsStmtRuntimeIds :: JS.Stmt -> Set Registry.RuntimeId
jsStmtRuntimeIds = \case
  JS.Block ss            -> foldMap jsStmtRuntimeIds ss
  JS.ExprStmt e          -> jsExprRuntimeIds e
  JS.ExprStmtWithSemi e  -> jsExprRuntimeIds e
  JS.IfStmt c t e        -> jsExprRuntimeIds c <> jsStmtRuntimeIds t <> jsStmtRuntimeIds e
  JS.Switch e cs         -> jsExprRuntimeIds e <> foldMap jsCaseRuntimeIds cs
  JS.While e s           -> jsExprRuntimeIds e <> jsStmtRuntimeIds s
  JS.Labelled _ s        -> jsStmtRuntimeIds s
  JS.Try t _ c           -> jsStmtRuntimeIds t <> jsStmtRuntimeIds c
  JS.Throw e             -> jsExprRuntimeIds e
  JS.Return e            -> jsExprRuntimeIds e
  JS.Var _ e             -> jsExprRuntimeIds e
  JS.Vars ps             -> foldMap (jsExprRuntimeIds . snd) ps
  JS.Const _ e           -> jsExprRuntimeIds e
  JS.ConstPure _ e       -> jsExprRuntimeIds e
  JS.FunctionStmt _ _ ss -> foldMap jsStmtRuntimeIds ss
  JS.EmptyStmt           -> Set.empty
  JS.Break _             -> Set.empty
  JS.Continue _          -> Set.empty

-- | Walk a JS expression, collecting kernel runtime 'Registry.RuntimeId's.
jsExprRuntimeIds :: JS.Expr -> Set Registry.RuntimeId
jsExprRuntimeIds = \case
  JS.Ref name        -> jsNameToRuntimeId name
  JS.Array es        -> foldMap jsExprRuntimeIds es
  JS.Object fs       -> foldMap (jsExprRuntimeIds . snd) fs
  JS.Access e _      -> jsExprRuntimeIds e
  JS.Index e i       -> jsExprRuntimeIds e <> jsExprRuntimeIds i
  JS.Prefix _ e      -> jsExprRuntimeIds e
  JS.Infix _ a b     -> jsExprRuntimeIds a <> jsExprRuntimeIds b
  JS.If c t e        -> jsExprRuntimeIds c <> jsExprRuntimeIds t <> jsExprRuntimeIds e
  JS.Assign lv e     -> jsLvalueRuntimeIds lv <> jsExprRuntimeIds e
  JS.Call f es       -> jsExprRuntimeIds f <> foldMap jsExprRuntimeIds es
  JS.Function _ _ ss -> foldMap jsStmtRuntimeIds ss
  JS.New e es        -> jsExprRuntimeIds e <> foldMap jsExprRuntimeIds es
  _                  -> Set.empty

-- | Walk an LValue for kernel runtime refs.
jsLvalueRuntimeIds :: JS.LValue -> Set Registry.RuntimeId
jsLvalueRuntimeIds = \case
  JS.LRef name     -> jsNameToRuntimeId name
  JS.LDot e _      -> jsExprRuntimeIds e
  JS.LBracket e i  -> jsExprRuntimeIds e <> jsExprRuntimeIds i

-- | Walk a case arm for kernel runtime refs.
jsCaseRuntimeIds :: JS.Case -> Set Registry.RuntimeId
jsCaseRuntimeIds = \case
  JS.Case e ss  -> jsExprRuntimeIds e <> foldMap jsStmtRuntimeIds ss
  JS.Default ss -> foldMap jsStmtRuntimeIds ss

-- | Convert a 'JsName.Name' to a 'Registry.RuntimeId' if it is a kernel
-- runtime name — i.e. matches the pattern @_[A-Z][^_]*_...@ (e.g.
-- @_Platform_leaf@, @_Basics_eq@). Canopy-compiled global names start with
-- @$@ and are ignored.
jsNameToRuntimeId :: JsName.Name -> Set Registry.RuntimeId
jsNameToRuntimeId jsName =
  let bs = BL.toStrict (BB.toLazyByteString (JsName.toBuilder jsName))
  in if BS.length bs > 3
       && BS.index bs 0 == 0x5F        -- '_'
       && BS.index bs 1 >= 0x41        -- 'A'
       && BS.index bs 1 <= 0x5A        -- 'Z'
     then Set.singleton (Registry.RuntimeId bs)
     else Set.empty

-- | Extract runtime references from FFI files using the parsed JavaScript AST.
--
-- When FFI files are embedded in the IIFE bundle, they may reference runtime
-- constants (e.g. @_Basics_e@, @_Basics_pi@) that never appear as
-- 'Opt.VarRuntime' in the Canopy AST. This function parses each FFI file
-- into a JavaScript AST via 'FFIRegistry.buildFFIRegistryFull', extracts
-- all free identifiers using scope-aware analysis, and filters for
-- kernel-style tokens matching @_[A-Z]..._...@.
--
-- All FFI files are processed regardless of whether they are included in
-- the bundle; entries not in the registry are ignored by 'Registry.closeDeps'.
collectFFIRuntimeDeps :: Map String FFIInfo -> Set Registry.RuntimeId
collectFFIRuntimeDeps =
  foldMap collectFromFFI . Map.elems
  where
    collectFromFFI info =
      let result = FFIRegistry.buildFFIRegistryFull (_ffiContent info)
          blocks = Map.elems (FFIRegistry._frrRegistry result)
          allFreeVars = foldMap FFIRegistry._fbAllFreeVars blocks
      in Set.fromList
           [ Registry.RuntimeId ident
           | ident <- Set.toList allFreeVars
           , isKernelIdent ident
           ]

-- | Check if a 'ByteString' identifier matches the kernel pattern @_[A-Z]..._...@.
--
-- Kernel runtime identifiers follow the convention @_Module_name@ where
-- @Module@ starts with an uppercase letter and a second underscore separates
-- the module from the function name. This filter is applied to free variables
-- extracted from the parsed FFI JavaScript AST.
isKernelIdent :: ByteString -> Bool
isKernelIdent bs =
  BS.length bs > 3
    && BS.index bs 0 == 0x5F
    && BS.index bs 1 >= 0x41
    && BS.index bs 1 <= 0x5A
    && Data.Maybe.isJust (BS.elemIndex 0x5F (BS.drop 2 bs))

-- | Tokenize already-generated JavaScript on identifier boundaries.
--
-- The optimized-AST walk ('collectRuntimeDeps' / 'collectFFIArities') cannot see
-- references the code generator emits directly into the output — the program-export
-- call @_Platform_export({...})@ from 'Kernel.toMainExports', and the @F7@/@A3@ arity
-- helpers used by emitted runtime functions like @_Json_map6@. Scanning the final
-- bytes for those tokens makes the tree-shaker's roots match what the output actually
-- references, for every current and future generated reference.
generatedIdentTokens :: ByteString -> [ByteString]
generatedIdentTokens = BS.splitWith (not . isIdentByte)

-- | Kernel runtime references (@_[A-Z]..._...@) in generated output. Tokens that are
-- not registry entries are harmlessly ignored by 'Registry.closeDeps', so the only
-- effect is that no referenced runtime symbol can be missed.
scanRuntimeIdents :: ByteString -> Set Registry.RuntimeId
scanRuntimeIdents bytes =
  Set.fromList
    [ Registry.RuntimeId tok
    | tok <- generatedIdentTokens bytes
    , isKernelIdent tok
    ]

-- | Currying-helper arities (@F2@..@F9@ / @A2@..@A9@) referenced in generated output,
-- so the helper definitions emitted by 'Functions.generateConditionalFunctions' cover
-- what the output — including the emitted runtime functions — actually calls.
scanArities :: ByteString -> Set Int
scanArities bytes =
  Set.fromList [ n | tok <- generatedIdentTokens bytes, Just n <- [arityToken tok] ]

-- | Recognize an @F<n>@ or @A<n>@ helper token (@n@ in 2..9), returning the arity.
arityToken :: ByteString -> Maybe Int
arityToken tok
  | BS.length tok == 2
  , h <- BS.index tok 0
  , h == 0x46 || h == 0x41 -- 'F' or 'A'
  , d <- BS.index tok 1
  , d >= 0x32 && d <= 0x39 -- '2'..'9'
  = Just (fromIntegral (d - 0x30))
  | otherwise = Nothing

-- | True for bytes that may appear inside a JavaScript identifier (@[A-Za-z0-9_$]@).
isIdentByte :: Word8 -> Bool
isIdentByte b =
  (b >= 0x30 && b <= 0x39) -- 0-9
    || (b >= 0x41 && b <= 0x5A) -- A-Z
    || (b >= 0x61 && b <= 0x7A) -- a-z
    || b == 0x5F -- _
    || b == 0x24 -- $

-- | Collect arity requirements from FFI @\@canopy-type@ annotations.
--
-- FFI JavaScript files declare function arities through type annotations
-- (e.g. @\@canopy-type Int -> Int -> Int -> Int -> Int -> Int -> Int@ declares
-- arity 6). The code generator wraps these in @F\<arity\>@ wrappers, so the
-- tree shaker must emit the corresponding F\/A helpers.
--
-- This function parses the @\@canopy-type@ annotations from each FFI file
-- using the same 'TypeParser' infrastructure that code generation uses,
-- ensuring the arity detection stays in sync with the code generator.
collectFFIArities :: Map String FFIInfo -> Set Int
collectFFIArities =
  foldMap extractArities . Map.elems
  where
    extractArities info =
      let typePairs = extractCanopyTypeFunctions (Text.lines (_ffiContent info))
      in Set.fromList
           [ arity
           | (_, typeAnnotation) <- typePairs
           , Just parsedType <- [TypeParser.parseType typeAnnotation]
           , let arity = TypeParser.countArity parsedType
           , arity >= 2 && arity <= 9
           ]

-- | Collect runtime deps from a definition.
defDeps :: Opt.Def -> (Set Registry.RuntimeId, Set Int)
defDeps (Opt.Def _ expr)         = exprDeps expr
defDeps (Opt.TailDef _ _ expr)   = exprDeps expr

-- | Collect runtime deps from an expression (exhaustive structural walk).
--
-- Each case that generates a direct 'JS.Ref' to a 'KN.*' runtime constant
-- in 'Expression.generateJsExpr' (bypassing 'Opt.VarRuntime') must add the
-- corresponding 'Registry.RuntimeId' here. The 'KN.*' constants used below
-- are the same ones 'Expression.hs' uses, so they stay in sync automatically
-- when renamed. If you add a new direct 'KN.*' ref in Expression.hs for an
-- Opt.* node, add the matching runtime dep here.
exprDeps :: Opt.Expr -> (Set Registry.RuntimeId, Set Int)
exprDeps expr =
  case expr of
    Opt.VarRuntime home name ->
      (Set.singleton (Registry.runtimeIdFromKernel home name), Set.empty)
    Opt.Function args body ->
      arityDep (length args) <> exprDeps body
    Opt.Call func args ->
      arityDep (length args) <> exprDeps func <> foldMap exprDeps args
    Opt.If branches final ->
      foldMap (\(c, b) -> exprDeps c <> exprDeps b) branches <> exprDeps final
    Opt.Let def body ->
      defDeps def <> exprDeps body
    Opt.Destruct _ body ->
      exprDeps body
    Opt.Case _ _ decider jumps ->
      deciderDeps decider <> foldMap (exprDeps . snd) jumps
    Opt.ArithBinop _ l r ->
      exprDeps l <> exprDeps r
    Opt.TailCall _ pairs ->
      foldMap (exprDeps . snd) pairs
    Opt.Access rec _ ->
      exprDeps rec
    -- Expression.hs emits JS.Ref KN.utilsUpdate for record updates.
    Opt.Update rec fields ->
      (jsNameToRuntimeId KN.utilsUpdate, Set.empty)
      <> exprDeps rec
      <> foldMap exprDeps (Map.elems fields)
    Opt.Record fields ->
      foldMap exprDeps (Map.elems fields)
    -- Expression.hs emits KN.listNil / KN.listCons for 0-2 element lists,
    -- and KN.listFromArray for 3+ element lists.
    Opt.List entries ->
      listExprDeps entries <> foldMap exprDeps entries
    -- Expression.hs emits KN.utilsTuple2 or KN.utilsTuple3 for tuples.
    Opt.Tuple a b Nothing ->
      (jsNameToRuntimeId KN.utilsTuple2, Set.empty) <> exprDeps a <> exprDeps b
    Opt.Tuple a b (Just c) ->
      (jsNameToRuntimeId KN.utilsTuple3, Set.empty) <> exprDeps a <> exprDeps b <> exprDeps c
    -- Expression.hs emits KN.utilsTuple0 for Unit in Dev mode.
    -- Conservative: always include it so tree-shaking is correct in all modes.
    Opt.Unit ->
      (jsNameToRuntimeId KN.utilsTuple0, Set.empty)
    -- Expression.hs emits KN.utilsChr for Char literals in Dev mode.
    Opt.Chr _ ->
      (jsNameToRuntimeId KN.utilsChr, Set.empty)
    -- Expression.hs emits KN.debugTodo / KN.debugTodoCase for Debug.todo calls.
    Opt.VarDebug _ _ _ _ ->
      ( jsNameToRuntimeId KN.debugTodo <> jsNameToRuntimeId KN.debugTodoCase
      , Set.empty
      )
    _ ->
      mempty

-- | Derive the runtime IDs needed for a list literal, mirroring 'Expression.generateList'.
-- Empty and short lists inline 'Cons'/'Nil'; longer lists use 'fromArray'.
listExprDeps :: [Opt.Expr] -> (Set Registry.RuntimeId, Set Int)
listExprDeps entries =
  case length entries of
    0 -> (jsNameToRuntimeId KN.listNil, Set.empty)
    1 -> (jsNameToRuntimeId KN.listCons <> jsNameToRuntimeId KN.listNil, Set.empty)
    2 -> (jsNameToRuntimeId KN.listCons <> jsNameToRuntimeId KN.listNil, Set.empty)
    _ -> (jsNameToRuntimeId KN.listFromArray, Set.empty)

-- | Emit the arity dep for a curried call\/function with @n@ arguments.
--
-- Returns the singleton arity set when @n@ is in [2..9] (uses @Fn@\/@An@),
-- and 'mempty' otherwise (falls back to curried single-arg calls).
arityDep :: Int -> (Set Registry.RuntimeId, Set Int)
arityDep n
  | n >= 2 && n <= 9 = (Set.empty, Set.singleton n)
  | otherwise        = mempty

-- | Collect runtime deps from a decision tree.
deciderDeps :: Opt.Decider Opt.Choice -> (Set Registry.RuntimeId, Set Int)
deciderDeps decider =
  case decider of
    Opt.Leaf choice             -> choiceDeps choice
    Opt.Chain _ success failure -> deciderDeps success <> deciderDeps failure
    Opt.FanOut _ tests fallback ->
      foldMap (deciderDeps . snd) tests <> deciderDeps fallback

-- | Collect runtime deps from a pattern-match choice.
choiceDeps :: Opt.Choice -> (Set Registry.RuntimeId, Set Int)
choiceDeps (Opt.Inline e) = exprDeps e
choiceDeps (Opt.Jump _)   = mempty

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
  State mempty [] Set.empty Set.empty 0 [] locs doTrackLines covIds Map.empty

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
     else if isKernelPhantom
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
      let code = if Mode.isCoverage mode
                 then covDefineCode mode currentGlobal expr state
                 else Expr.generate mode expr
          stmt = var mode currentGlobal code
          baseState = emitMappingCol (defNameGenCol mode currentGlobal stmt) currentGlobal (addDeps deps state)
       in addStmt baseState stmt
    Opt.DefineTailFunc argNames body deps ->
      let (Opt.Global _ name) = currentGlobal
          expr = if Mode.isCoverage mode
                 then covTailFuncExpr mode currentGlobal argNames body state
                 else Expr.generateTailDefExpr mode name argNames body
          stmt = JS.Var (Mode.defName mode currentGlobal) expr
          baseState = emitMappingCol (defNameGenCol mode currentGlobal stmt) currentGlobal (addDeps deps state)
       in addStmt baseState stmt
    Opt.Ctor index arity ->
      let stmt = var mode currentGlobal (Expr.generateCtor mode currentGlobal index arity)
       in addStmt (emitMappingCol (defNameGenCol mode currentGlobal stmt) currentGlobal state) stmt
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
      let stmt = Kernel_.generateEnum mode currentGlobal index
       in addStmt (emitMappingCol (defNameGenCol mode currentGlobal stmt) currentGlobal state) stmt
    Opt.Box ->
      let stmt = Kernel_.generateBox mode currentGlobal
       in addStmt (emitMappingCol (defNameGenCol mode currentGlobal stmt) currentGlobal (addGlobal mode graph state Kernel_.identity)) stmt
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

-- | Emit a source map mapping for a global before generating its JS, with the
-- def's generated COLUMN left at 0 (the start of its generated line).
--
-- Used for node shapes whose emitted JS does not begin with a @var \<defName\>@
-- prefix — cycles, ports, and ability impl-dicts — where there is no single
-- well-defined "def name column" to point at; a line-precise (column-0) mapping
-- is the honest answer for those. The @var@-shaped defs (Define, DefineTailFunc,
-- Ctor, Enum, Box) use 'emitMappingCol' to record the def name's true column.
--
-- The global carries its home module, which becomes the mapping's @sources@
-- entry so a symbolicated frame names the right @.can@ module (not just a line).
emitMapping :: Opt.Global -> State -> State
emitMapping = emitMappingCol 0

-- | Like 'emitMapping', but records an explicit generated COLUMN for the def
-- (CMP-7A). The column is the 0-based byte offset, within the def's generated
-- line, at which the def's emitted name begins — so a dev red-box resolves to
-- the right def + column, not merely the right line. Every emitted statement is
-- newline-terminated, so a def's statement always starts at column 0 of its
-- generated line; the meaningful, def-distinguishing column is therefore the
-- offset of the def NAME within that statement (e.g. 4 for @var \<name\>@,
-- after the @"var "@ prefix), computed by 'defNameGenCol'.
emitMappingCol :: Int -> Opt.Global -> State -> State
emitMappingCol genCol global@(Opt.Global home _) state =
  case Map.lookup global (state ^. sourceLocations) of
    Nothing -> state
    Just region -> emitMappingForRegion genCol home region state

-- | Build a mapping from a source region, recording the source module's @sources@ index
-- (assigned on first sight, reused thereafter) and the def's generated column.
emitMappingForRegion :: Int -> ModuleName.Canonical -> Ann.Region -> State -> State
emitMappingForRegion genCol home (Ann.Region (Ann.Position srcLine srcCol) _) state =
  let (srcIndex, state') = resolveSrcIndex home state
      mapping = SourceMap.Mapping
        { SourceMap._mGenLine = state' ^. outputLine
        , SourceMap._mGenCol = genCol
        , SourceMap._mSrcIndex = srcIndex
        , SourceMap._mSrcLine = fromIntegral srcLine - 1
        , SourceMap._mSrcCol = fromIntegral srcCol - 1
        , SourceMap._mNameIndex = Nothing
        }
   in state' & sourceMapMappings %~ (mapping :)

-- | The 0-based generated column at which a @var \<defName\>@ statement places
-- the def name, computed from the actual rendered statement rather than a
-- hard-coded constant — so it stays correct if the pretty-printer's prefix
-- (e.g. @"var "@) ever changes.
--
-- Every traversal statement is newline-terminated (and the inner preamble ends
-- with a newline), so the statement begins at column 0 of its generated line;
-- the def name's column is then simply its byte offset within the rendered
-- statement. We locate it by searching the rendered bytes for the def name's
-- identifier bytes (which are unique within a @var \<name\> = ...@ prefix). If
-- the name cannot be located (defensive — should not happen for a @var@-shaped
-- def), we fall back to column 0, degrading to the prior line-only behavior.
--
-- Source maps are Dev-only, so this returns 0 immediately in Prod (and whenever
-- line tracking is off): there is no map to carry the column, and the extra
-- statement render is pure waste under @--optimize@.
defNameGenCol :: Mode.Mode -> Opt.Global -> JS.Stmt -> Int
defNameGenCol mode global stmt =
  case mode of
    Mode.Prod {} -> 0
    Mode.Dev {} ->
      let nameBytes = BL.toStrict (BB.toLazyByteString (JsName.toBuilder (Mode.defName mode global)))
          stmtBytes = BL.toStrict (BB.toLazyByteString (JS.stmtToBuilder stmt))
       in case BS.breakSubstring nameBytes stmtBytes of
            (prefix, match)
              | BS.null match -> 0
              | otherwise     -> BS.length prefix

-- | The @sources@-array index for a module: reuse the existing one, or assign the next.
resolveSrcIndex :: ModuleName.Canonical -> State -> (Int, State)
resolveSrcIndex home state =
  case Map.lookup home (state ^. smSrcIndices) of
    Just idx -> (idx, state)
    Nothing  ->
      let idx = Map.size (state ^. smSrcIndices)
       in (idx, state & smSrcIndices %~ Map.insert home idx)

-- | Build a SourceMap from accumulated state (dev mode only). Populates @sources@ from the
-- modules seen during emission so each VLQ @srcIndex@ resolves to a @.can@ module name;
-- @sourcesContent@ is left empty (the host symbolicates to file:line, not inline text).
--
-- 'genLineBase' is the number of generated lines emitted BEFORE the traversal
-- output in the final bundle (IIFE header + F\/A arity helpers + runtime + FFI
-- runtime + inner preamble). State's 'outputLine' starts at 0 and counts only
-- the traversal output, so every recorded mapping is relative to the start of
-- that output. Adding 'genLineBase' to each @genLine@ re-bases the whole map to
-- the bundle's true byte layout — without it, every dev red-box line is off by
-- the entire prepended runtime (CMP-6).
buildSourceMap :: Int -> Mode.Mode -> State -> Maybe SourceMap.SourceMap
buildSourceMap genLineBase mode state =
  case mode of
    Mode.Prod {} -> Nothing
    Mode.Dev _ _ _ _ _ _ ->
      let orderedSources = map fst (List.sortOn snd (Map.toList (state ^. smSrcIndices)))
          sourcePaths = map renderModulePath orderedSources
          rebasedMappings = map rebase (state ^. sourceMapMappings)
          sm = SourceMap.empty "canopy.js"
       in Just sm { SourceMap._smMappings = rebasedMappings
                  , SourceMap._smSources = sourcePaths
                  , SourceMap._smSourcesContent = map (const Text.empty) sourcePaths
                  }
  where
    rebase m = m { SourceMap._mGenLine = SourceMap._mGenLine m + genLineBase }
    renderModulePath home =
      ModuleName.toChars (ModuleName._module home) <> ".can"

var :: Mode.Mode -> Opt.Global -> Expr.Code -> JS.Stmt
var mode global code =
  JS.Var (Mode.defName mode global) (Expr.codeToExpr code)

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

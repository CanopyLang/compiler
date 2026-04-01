{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | ESM (ES Module) code generation backend.
--
-- Generates one ES module file per Canopy module, a shared runtime module,
-- and an entry point. This is a parallel backend to the IIFE generator in
-- "Generate.JavaScript" — it reuses the same expression code generation
-- ('Expr.generate') and name mangling ('JsName.fromGlobal') but produces
-- @import@\/@export@ statements instead of a single IIFE bundle.
--
-- = Architecture
--
-- The ESM backend partitions the flat 'Opt.GlobalGraph' into per-module
-- buckets, then generates:
--
--   * @canopy-runtime.js@ — all runtime primitives as ESM exports
--   * @Author.Project.Module.js@ — one file per Canopy module
--   * @ffi\/Alias.js@ — one file per FFI import
--   * @main.js@ — entry point that imports and starts the app
--
-- The same mangled names (@$author$project$Module$func@) are used in
-- both IIFE and ESM modes, so 'Expr.generate' output is format-agnostic.
--
-- All ESM constructs (imports, exports, @const@ declarations) are built
-- via the 'JS.ModuleItem' AST and rendered through @language-javascript@.
--
-- @since 0.20.0
module Generate.JavaScript.ESM
  ( generate,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.ESM.FFI as ESMFFI
import qualified Generate.JavaScript.ESM.HMR as HMR
import qualified Generate.JavaScript.ESM.Runtime as ESMRuntime
import Generate.JavaScript.ESM.Types (ESMOutput (..))
import qualified Generate.JavaScript.Ability as Ability
import qualified Generate.JavaScript.Expression as Expr
import Generate.JavaScript.FFI (FFIInfo (..))
import qualified Generate.JavaScript.Kernel as Kernel_
import qualified Generate.JavaScript.Minify as Minify
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.Runtime.Names as KN
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Prelude hiding (cycle)

-- | Map of main entry points per module.
type Mains = Map ModuleName.Canonical Opt.Main

-- | Graph of optimized global definitions.
type Graph = Map Opt.Global Opt.Node

-- | Generate complete ESM output from a global graph.
--
-- This is the main entry point for ESM code generation. It partitions
-- the global graph by module, generates per-module ES module files,
-- a shared runtime module, FFI modules, and an entry point.
--
-- @since 0.20.0
generate :: Mode.Mode -> Opt.GlobalGraph -> Mains -> Map String FFIInfo -> ESMOutput
generate inputMode (Opt.GlobalGraph rawGraph _ _) mains ffiInfos =
  ESMOutput
    { _eoRuntime = ESMRuntime.generateRuntime mode,
      _eoModules = generateAllModules mode graph mains reachable,
      _eoFFIModules = generateAllFFI ffiInfos,
      _eoEntry = generateEntryPoint mains,
      _eoTypeDefs = Map.empty
    }
  where
    (graph, mode) = prepareGraph inputMode rawGraph ffiInfos
    reachable = collectReachableGlobals mode graph mains

-- | Prepare the graph and mode, applying minification in prod.
prepareGraph ::
  Mode.Mode ->
  Graph ->
  Map String FFIInfo ->
  (Graph, Mode.Mode)
prepareGraph inputMode rawGraph ffiInfos =
  case inputMode of
    Mode.Prod fields elmCompat ffiUnsafe ffiDbg _ _ _ ->
      let minified = Minify.minifyGraph rawGraph
          pool = StringPool.buildPool minified
          ffiAliases = extractFFIAliases ffiInfos
       in (minified, Mode.Prod fields elmCompat ffiUnsafe ffiDbg pool ffiAliases Map.empty)
    Mode.Dev debugTypes elmCompat ffiUnsafe ffiDbg _ cov ->
      let ffiAliases = extractFFIAliases ffiInfos
       in (rawGraph, Mode.Dev debugTypes elmCompat ffiUnsafe ffiDbg ffiAliases cov)

-- | Extract FFI alias names from FFI info map.
extractFFIAliases :: Map String FFIInfo -> Set Name.Name
extractFFIAliases ffiInfos =
  Set.fromList (map _ffiAlias (Map.elems ffiInfos))

-- REACHABILITY ANALYSIS

-- | Collect all globals reachable from mains via dependency traversal.
--
-- This mirrors the graph traversal in "Generate.JavaScript" but only
-- collects the set of reachable globals without generating code.
collectReachableGlobals :: Mode.Mode -> Graph -> Mains -> Set Opt.Global
collectReachableGlobals mode graph mains =
  Map.foldlWithKey' (\s home _ -> addReachable mode graph s (Opt.Global home "main")) Set.empty mains

-- | Recursively add a global and its dependencies to the reachable set.
addReachable :: Mode.Mode -> Graph -> Set Opt.Global -> Opt.Global -> Set Opt.Global
addReachable mode graph seen global
  | Set.member global seen = seen
  | Kernel_.isDebugger global && not (Mode.isDebug mode) = seen
  | otherwise =
      case Map.lookup global graph of
        Nothing -> seen
        Just node ->
          let seen' = Set.insert global seen
              deps = nodeDeps node
              filteredDeps = filterDebugDeps mode deps
           in Set.foldl' (addReachable mode graph) seen' filteredDeps

-- | Extract dependency globals from a node.
nodeDeps :: Opt.Node -> Set Opt.Global
nodeDeps (Opt.Define _ deps) = deps
nodeDeps (Opt.DefineTailFunc _ _ deps) = deps
nodeDeps (Opt.Ctor _ _) = Set.empty
nodeDeps (Opt.Enum _) = Set.empty
nodeDeps Opt.Box = Set.empty
nodeDeps (Opt.Link g) = Set.singleton g
nodeDeps (Opt.Cycle _ _ _ deps) = deps
nodeDeps (Opt.Manager _) = Set.empty
nodeDeps (Opt.Kernel _ deps) = deps
nodeDeps (Opt.PortIncoming _ deps) = deps
nodeDeps (Opt.PortOutgoing _ deps) = deps
nodeDeps (Opt.AbilityDict _) = Set.empty
nodeDeps (Opt.ImplDict _ _ deps) = deps

-- | Filter out debugger dependencies unless debug mode is on.
filterDebugDeps :: Mode.Mode -> Set Opt.Global -> Set Opt.Global
filterDebugDeps mode deps
  | Mode.isDebug mode = deps
  | otherwise = Set.filter (not . Kernel_.isDebugger) deps

-- PER-MODULE GENERATION

-- | Generate ES module files for all reachable modules.
generateAllModules ::
  Mode.Mode ->
  Graph ->
  Mains ->
  Set Opt.Global ->
  Map ModuleName.Canonical Builder
generateAllModules mode graph mains reachable =
  Map.mapWithKey (generateModule mode mains graph reachable) moduleNodes
  where
    moduleNodes = groupByModule reachable graph

-- | Group reachable globals by their home module.
groupByModule ::
  Set Opt.Global ->
  Graph ->
  Map ModuleName.Canonical (Map Name.Name (Opt.Global, Opt.Node))
groupByModule reachable graph =
  Set.foldl' insertGlobal Map.empty reachable
  where
    insertGlobal acc global@(Opt.Global home name) =
      case Map.lookup global graph of
        Nothing -> acc
        Just node ->
          Map.alter (Just . addEntry name global node) home acc
    addEntry name global node Nothing = Map.singleton name (global, node)
    addEntry name global node (Just m) = Map.insert name (global, node) m

-- | Generate a single ES module file.
--
-- In dev mode, uses the formatted pretty printer for readable output
-- and injects HMR support for TEA modules.
-- In prod mode, uses the compact printer for minimal output.
generateModule ::
  Mode.Mode ->
  Mains ->
  Graph ->
  Set Opt.Global ->
  ModuleName.Canonical ->
  Map Name.Name (Opt.Global, Opt.Node) ->
  Builder
generateModule mode mains _graph reachable home entries =
  renderModule mode (commentItems ++ importItems ++ definitionItems ++ exportItems ++ hmrItems)
  where
    commentItems = [JS.RawJS (moduleComment home)]
    importItems = buildImportItems reachable home entries
    definitionItems = buildDefinitionItems mode entries
    exportItems = buildExportItems entries
    hmrItems = HMR.generateHMRItems mode mains home

-- | Render module items using the appropriate printer for the mode.
renderModule :: Mode.Mode -> [JS.ModuleItem] -> Builder
renderModule (Mode.Dev {}) = JS.moduleToFormattedBuilder
renderModule (Mode.Prod {}) = JS.moduleToBuilder

-- | Generate module header comment.
moduleComment :: ModuleName.Canonical -> Builder
moduleComment home =
  "// " <> canonicalToFilename home <> "\n\
  \// Auto-generated by the Canopy compiler. Do not edit.\n\n"

-- IMPORT GENERATION

-- | Build import items for a module.
--
-- Includes a bare runtime import and named imports for each
-- cross-module dependency, grouped by source module.
buildImportItems ::
  Set Opt.Global ->
  ModuleName.Canonical ->
  Map Name.Name (Opt.Global, Opt.Node) ->
  [JS.ModuleItem]
buildImportItems reachable home entries =
  JS.ImportBare "'./canopy-runtime.js'"
    : map buildCrossModuleImport (Map.toAscList grouped)
  where
    allDeps = collectAllDeps entries
    externalDeps = Set.filter (isExternal home) (Set.intersection reachable allDeps)
    grouped = groupDepsByModule externalDeps

-- | Collect all dependency globals from module entries.
collectAllDeps :: Map Name.Name (Opt.Global, Opt.Node) -> Set Opt.Global
collectAllDeps entries =
  Map.foldl' (\acc (_, node) -> Set.union acc (nodeDeps node)) Set.empty entries

-- | Check if a global is from a different module.
isExternal :: ModuleName.Canonical -> Opt.Global -> Bool
isExternal home (Opt.Global depHome _) = depHome /= home

-- | Group dependency globals by their home module.
groupDepsByModule :: Set Opt.Global -> Map ModuleName.Canonical (Set Opt.Global)
groupDepsByModule =
  Set.foldl' insertDep Map.empty
  where
    insertDep acc global@(Opt.Global home _) =
      Map.alter (Just . maybe (Set.singleton global) (Set.insert global)) home acc

-- | Build a single cross-module import item.
buildCrossModuleImport :: (ModuleName.Canonical, Set Opt.Global) -> JS.ModuleItem
buildCrossModuleImport (srcModule, globals) =
  JS.ImportNamed
    (map globalToJsName (Set.toAscList globals))
    (canonicalToPathBs srcModule)

-- | Convert a global to its mangled JS 'JsName.Name'.
globalToJsName :: Opt.Global -> JsName.Name
globalToJsName (Opt.Global home name) =
  JsName.fromGlobal home name

-- DEFINITION GENERATION

-- | Build definition items for all module entries.
buildDefinitionItems ::
  Mode.Mode ->
  Map Name.Name (Opt.Global, Opt.Node) ->
  [JS.ModuleItem]
buildDefinitionItems mode entries =
  concatMap (dispatchNodeESM mode) (Map.elems entries)

-- | Dispatch code generation for a node, producing 'ModuleItem' values.
--
-- Mirrors 'Generate.JavaScript.dispatchNode' but emits @const@ instead
-- of @var@ and adds @\/\*#__PURE__\*\/@ annotations for tree shaking.
dispatchNodeESM :: Mode.Mode -> (Opt.Global, Opt.Node) -> [JS.ModuleItem]
dispatchNodeESM mode (global, node) =
  case node of
    Opt.Define expr _deps ->
      [JS.ModuleStmt (JS.ConstPure globalName (Expr.codeToExpr (Expr.generate mode expr)))]
    Opt.DefineTailFunc argNames body _deps ->
      [JS.ModuleStmt (JS.ConstPure globalName (Expr.generateTailDefExpr mode name argNames body))]
    Opt.Ctor index arity ->
      [JS.ModuleStmt (JS.ConstPure globalName (Expr.codeToExpr (Expr.generateCtor mode global index arity)))]
    Opt.Link linkedGlobal ->
      [JS.ModuleStmt (JS.Const globalName (JS.Ref (globalToJsName linkedGlobal)))]
    Opt.Cycle names values functions _deps ->
      [JS.ModuleStmt (varToConst (Kernel_.generateCycle mode global names values functions))]
    Opt.Manager effectsType ->
      map JS.ModuleStmt (managerStmts mode global effectsType)
    Opt.Kernel chunks _deps ->
      [JS.RawJS (Kernel_.generateKernel mode chunks)]
    Opt.Enum index ->
      [JS.ModuleStmt (varToConst (Kernel_.generateEnum mode global index))]
    Opt.Box ->
      [JS.ModuleStmt (varToConst (Kernel_.generateBox mode global))]
    Opt.PortIncoming decoder _deps ->
      [JS.ModuleStmt (varToConst (Kernel_.generatePort mode global "incomingPort" decoder))]
    Opt.PortOutgoing encoder _deps ->
      [JS.ModuleStmt (varToConst (Kernel_.generatePort mode global "outgoingPort" encoder))]
    Opt.AbilityDict _ ->
      []
    Opt.ImplDict abilityName methods _deps ->
      [JS.ModuleStmt (varToConst (Ability.generateImplDict mode global abilityName methods))]
  where
    Opt.Global home name = global
    globalName = JsName.fromGlobal home name

-- | Convert top-level @var@ declarations to @const@ for ESM output.
--
-- Kernel helper functions ('Kernel_.generateEnum', etc.) emit @var@
-- because the IIFE backend requires it. In ESM mode we prefer @const@
-- for module-level declarations.
varToConst :: JS.Stmt -> JS.Stmt
varToConst (JS.Var name expr) = JS.Const name expr
varToConst (JS.Block stmts) = JS.Block (map varToConst stmts)
varToConst other = other

-- | Generate effect manager statements for ESM.
managerStmts :: Mode.Mode -> Opt.Global -> Opt.EffectsType -> [JS.Stmt]
managerStmts _mode (Opt.Global home _) effectsType =
  createManager : stmts
  where
    (_deps, args, stmts) = Kernel_.generateManagerHelp home effectsType
    managerLVar =
      JS.LBracket
        (JS.Ref KN.platformEffectManagers)
        (JS.String (Name.toBuilder (ModuleName._module home)))
    createManager =
      JS.ExprStmt (JS.Assign managerLVar (JS.Call (JS.Ref KN.platformCreateManager) args))

-- EXPORT GENERATION

-- | Build export items for a module.
buildExportItems ::
  Map Name.Name (Opt.Global, Opt.Node) ->
  [JS.ModuleItem]
buildExportItems entries
  | Map.null entries = []
  | otherwise =
      [JS.ExportLocals (map entryJsName (Map.elems entries))]

-- | Get the JS name for a module entry.
entryJsName :: (Opt.Global, Opt.Node) -> JsName.Name
entryJsName (Opt.Global home name, _) =
  JsName.fromGlobal home name

-- FFI MODULE GENERATION

-- | Generate ESM modules for all FFI files.
generateAllFFI :: Map String FFIInfo -> Map String Builder
generateAllFFI =
  Map.map generateSingleFFI

-- | Generate a single FFI ESM module.
generateSingleFFI :: FFIInfo -> Builder
generateSingleFFI (FFIInfo _path content alias) =
  ESMFFI.generateFFIModule content (Name.toChars alias)

-- ENTRY POINT GENERATION

-- | Generate @main.js@ that imports and starts the application.
--
-- Imports the main function from the appropriate module and calls
-- the platform initialization function based on the 'Opt.Main' variant.
-- Always uses formatted output since entry points should be readable.
generateEntryPoint :: Mains -> Builder
generateEntryPoint mains
  | Map.null mains = "// No main functions found.\n"
  | otherwise =
      JS.moduleToFormattedBuilder entryItems
  where
    entryItems =
      JS.RawJS entryComment
        : JS.ImportBare "'./canopy-runtime.js'"
        : concatMap mainImportAndInit (Map.toAscList mains)

-- | Entry point header comment.
entryComment :: Builder
entryComment =
  "// main.js — Canopy application entry point\n\
  \// Auto-generated by the Canopy compiler. Do not edit.\n\n"

-- | Generate import and init items for a single main entry.
mainImportAndInit :: (ModuleName.Canonical, Opt.Main) -> [JS.ModuleItem]
mainImportAndInit (home, mainType) =
  [ JS.ImportNamed [mainJsName] (canonicalToPathBs home)
  , JS.ModuleStmt (JS.ExprStmtWithSemi (JS.Call (JS.Ref initName) [JS.Ref mainJsName]))
  ]
  where
    mainJsName = JsName.fromGlobal home ("main" :: Name.Name)
    initName = initFunctionName mainType

-- | Get the platform initialization function name based on main type.
initFunctionName :: Opt.Main -> JsName.Name
initFunctionName Opt.Static = KN.platformWorker
initFunctionName (Opt.Dynamic _ _ _) = KN.platformWorker
initFunctionName Opt.TestMain = KN.platformWorker
initFunctionName Opt.BrowserTestMain = KN.platformWorker

-- UTILITIES

-- | Convert a canonical module name to a flat filename.
--
-- @ModuleName.Canonical (Pkg.Name \"author\" \"project\") \"Module.Sub\"@
-- becomes @\"Author.Project.Module.Sub.js\"@
canonicalToFilename :: ModuleName.Canonical -> Builder
canonicalToFilename (ModuleName.Canonical (Pkg.Name author project) moduleName) =
  BB.stringUtf8 (Utf8.toChars author)
    <> "."
    <> BB.stringUtf8 (Utf8.toChars project)
    <> "."
    <> BB.stringUtf8 (Name.toChars moduleName)
    <> ".js"

-- | Convert a canonical module name to a quoted path 'ByteString'.
--
-- Returns @\'.\/Author.Project.Module.js\'@ with quotes included,
-- suitable for use as a module specifier in import declarations.
canonicalToPathBs :: ModuleName.Canonical -> ByteString
canonicalToPathBs home =
  LBS.toStrict (BB.toLazyByteString ("'./" <> canonicalToFilename home <> "'"))

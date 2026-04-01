{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Function-level runtime registry for tree-shaking.
--
-- Splits the monolithic Canopy runtime into individually addressable
-- definitions. Each definition has its JS AST statements, automatically
-- computed dependencies on other runtime functions, and tracked F\/A arity
-- usage.
--
-- The registry is built lazily from the embedded runtime quasi-quote by:
--
--   1. Parsing the quasi-quoted string via @language-javascript@ AST
--   2. Grouping into 'BlockGroup's (one per top-level declaration)
--   3. Computing inter-function dependencies via scope-aware free-variable
--      analysis (same machinery used for FFI tree-shaking)
--   4. Tracking F2\/F3\/… and A2\/A3\/… usage via 'JSAnalysis.aritiesInGroup'
--
-- Definitions are stored as @[JSStatement]@ AST nodes. Rendering to
-- 'Builder' only happens at final emit time, enabling prod-mode
-- transformations (debug-branch elimination, minification) without
-- re-parsing.
--
-- @since 0.20.4
module Generate.JavaScript.Runtime.Registry
  ( -- * Types
    RuntimeId (..),
    RuntimeDef (..),

    -- * Registry
    registry,
    allIds,
    lookupDef,

    -- * Tree-shaking
    closeDeps,
    topoEmit,

    -- * Construction
    runtimeIdFromKernel,

    -- * ESM export name lists (AST-derived, no byte scanning)
    exportedRuntimeNames,
    exportedRuntimeSymbols,
    hmrSymbols,

    -- * Raw content (for ESM symbol scanning)
    rawRuntimeContent,
  )
where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Blaze.ByteString.Builder as Blaze
import qualified Data.ByteString.Lazy as BL
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified Canopy.Data.Name as Name
import qualified Generate.JavaScript.FFI.JSAnalysis as JSAnalysis
import qualified Language.JavaScript.Parser.AST as JSAST
import qualified Language.JavaScript.Pretty.Printer as JSPrint
import Language.JavaScript.Process.Minify (minifyJS)
import Text.RawString.QQ (r)

-- TYPES

-- | Unique identifier for a runtime function — the full JS global name
-- (e.g., @\"_Utils_eq\"@, @\"_List_Nil\"@, @\"_Scheduler_succeed\"@).
--
-- @since 0.20.1
newtype RuntimeId = RuntimeId {_ridName :: ByteString}
  deriving (Eq, Ord, Show)

-- | A single runtime function definition with dependency metadata.
--
-- Stores AST statements rather than rendered bytes so that production-mode
-- transformations (debug-branch elimination, minification) can operate on
-- the AST directly without re-parsing. Rendering happens once at final
-- emit time.
--
-- @since 0.20.4
data RuntimeDef = RuntimeDef
  { -- | AST statements for this definition.
    _rdStatements :: ![JSAST.JSStatement],
    -- | Preceding JSDoc comment text, if any (raw lines including @\/**@).
    _rdJSDoc :: !(Maybe Text.Text),
    -- | Direct dependencies on other runtime functions.
    _rdDeps :: !(Set RuntimeId),
    -- | F\/A arities used (e.g., @{2}@ if @F2(...)@ appears in the source).
    _rdFArities :: !(Set Int),
    -- | Original position in the monolithic runtime (for stable sort tiebreaker).
    _rdOrder :: !Int
  }
  deriving (Show)

-- REGISTRY

-- | Complete registry of all runtime functions.
--
-- Built lazily on first access by parsing the monolithic runtime source.
-- Subsequent accesses reuse the cached result (top-level CAF).
--
-- @since 0.20.1
{-# NOINLINE registry #-}
registry :: Map RuntimeId RuntimeDef
registry = buildRegistry

-- | All runtime function IDs.
--
-- Useful for full (non-tree-shaken) emission or backwards compatibility.
--
-- @since 0.20.1
{-# NOINLINE allIds #-}
allIds :: Set RuntimeId
allIds = Map.keysSet registry

-- | Look up a runtime definition by ID.
--
-- @since 0.20.1
lookupDef :: RuntimeId -> Maybe RuntimeDef
lookupDef rid = Map.lookup rid registry

-- TREE-SHAKING

-- | Compute the transitive closure of runtime dependencies.
--
-- Given a seed set of needed runtime functions, repeatedly expands
-- by adding each function's direct dependencies until no new functions
-- are discovered. The result includes the seed set itself.
--
-- @since 0.20.1
closeDeps :: Set RuntimeId -> Set RuntimeId
closeDeps seeds = go Set.empty seeds
  where
    go visited pending
      | Set.null pending = visited
      | otherwise =
          let new = Set.difference pending visited
              visited' = Set.union visited new
              directDeps = foldMap depsOf (Set.toList new)
           in go visited' directDeps
    depsOf rid =
      maybe Set.empty _rdDeps (Map.lookup rid registry)

-- | Emit needed runtime functions in topological order.
--
-- Dependencies are emitted before the functions that reference them.
-- Uses original position as tiebreaker for deterministic output.
-- Circular dependencies between @function@ declarations are safe
-- due to JavaScript hoisting.
--
-- When @isProd@ is 'True', 'minifyJS' is applied before rendering each
-- definition to strip all whitespace and comments.
--
-- @since 0.20.4
topoEmit :: Bool -> Set RuntimeId -> Builder
topoEmit isProd needed =
  foldMap emitOne (topoSort needed)
  where
    emitOne rid = maybe mempty (renderRuntimeDef isProd) (Map.lookup rid registry)

-- | Render a 'RuntimeDef' to a 'Builder', including any JSDoc prefix.
--
-- When @isProd@ is 'True', applies 'minifyJS' before rendering.
renderRuntimeDef :: Bool -> RuntimeDef -> Builder
renderRuntimeDef isProd def =
  foldMap renderJSDoc (_rdJSDoc def)
  <> renderStatements isProd (_rdStatements def)
  <> "\n"

-- | Render JSDoc text to 'Builder'.
renderJSDoc :: Text.Text -> Builder
renderJSDoc doc = BB.byteString (TextEnc.encodeUtf8 doc)

-- | Render a list of 'JSStatement' nodes to 'Builder' via the pretty-printer.
--
-- When @isProd@ is 'True', applies 'minifyJS' to strip whitespace and comments.
renderStatements :: Bool -> [JSAST.JSStatement] -> Builder
renderStatements isProd stmts =
  BB.lazyByteString
    (Blaze.toLazyByteString
      (JSPrint.renderJS ast'))
  where
    ast  = JSAST.JSAstProgram stmts JSAST.JSNoAnnot
    ast' = if isProd then minifyJS ast else ast

-- | Topological sort: dependencies before dependents.
--
-- Standard DFS-based algorithm. Original line position is used as a
-- tiebreaker so output order matches the known-working monolithic layout.
topoSort :: Set RuntimeId -> [RuntimeId]
topoSort needed =
  snd (List.foldl' visit (Set.empty, []) orderedInput)
  where
    orderedInput = sortByOrder (Set.toList needed)
    visit (visited, acc) rid
      | Set.member rid visited = (visited, acc)
      | otherwise =
          let deps = maybe Set.empty _rdDeps (Map.lookup rid registry)
              relevantDeps = Set.intersection deps needed
              (visited', acc') =
                List.foldl' visit (Set.insert rid visited, acc) (sortByOrder (Set.toList relevantDeps))
           in (visited', rid : acc')
    sortByOrder =
      List.sortOn (\rid -> maybe maxBound _rdOrder (Map.lookup rid registry))

-- CONSTRUCTION

-- | Construct a 'RuntimeId' from a kernel module name and function name.
--
-- Maps @(\"Utils\", \"eq\")@ to @RuntimeId \"_Utils_eq\"@, matching the
-- naming convention used by 'Generate.JavaScript.Name.fromKernel'.
--
-- @since 0.20.1
runtimeIdFromKernel :: Name.Name -> Name.Name -> RuntimeId
runtimeIdFromKernel home name =
  RuntimeId (BS8.pack ("_" ++ Name.toChars home ++ "_" ++ Name.toChars name))

-- ESM EXPORT NAMES

-- | All declared runtime symbol names in original source order.
--
-- Derived from the registry via AST analysis — no byte scanning.
-- Includes only the base runtime symbols (e.g. @_Utils_eq@, @_List_Nil@).
-- Currying helpers (F\/F2–F9\/A2–A9) and FFI runtime symbols are separate.
-- Used by 'Generate.JavaScript.ESM.Runtime' to build the export list.
--
-- @since 0.20.5
exportedRuntimeNames :: [ByteString]
exportedRuntimeNames =
  map _ridName (List.sortOn orderOf (Map.keys registry))
  where
    orderOf rid = maybe maxBound _rdOrder (Map.lookup rid registry)

-- | The complete set of all symbols exported by @canopy-runtime.js@.
--
-- Includes base runtime symbols, currying helpers (F, F2–F9, A2–A9),
-- FFI runtime namespace objects (\$canopy, \$validate, \$smart, \$env),
-- and the debug flag. Used by 'Generate.JavaScript.ESM.FFI' to
-- determine which free variables in an FFI file must be imported.
--
-- @since 0.20.5
exportedRuntimeSymbols :: Set ByteString
exportedRuntimeSymbols =
  Set.fromList (map _ridName (Map.keys registry))
    `Set.union` Set.fromList curryingSymbols
    `Set.union` Set.fromList ffiRuntimeSymbols
    `Set.union` Set.fromList hmrSymbols
    `Set.union` Set.singleton "__canopy_debug"

-- | Currying helper symbol names (F, F2–F9, A2–A9).
curryingSymbols :: [ByteString]
curryingSymbols =
  "F" : concatMap (\n -> [BS8.pack ('F' : show n), BS8.pack ('A' : show n)]) [2..9 :: Int]

-- | FFI runtime namespace object names declared by 'Generate.JavaScript.FFIRuntime'.
ffiRuntimeSymbols :: [ByteString]
ffiRuntimeSymbols = ["$canopy", "$validate", "$smart", "$env"]

-- | HMR helper symbol names injected in dev mode.
hmrSymbols :: [ByteString]
hmrSymbols =
  [ "_Platform_currentModel", "_Platform_currentStepper"
  , "_Platform_getModel", "_Platform_hotSwap"
  , "_Platform_trackModel", "_Platform_trackStepper"
  ]

-- RAW CONTENT

-- | The raw monolithic runtime as a 'Builder'.
--
-- Exposed for use by 'Generate.JavaScript.ESM.Runtime' which needs to
-- scan the full content for top-level declarations to build its export list.
--
-- @since 0.20.1
rawRuntimeContent :: Builder
rawRuntimeContent = embeddedRuntimeContent

-- INTERNAL: REGISTRY BUILDING

-- | Build the complete registry from the embedded runtime source.
--
-- Converts the embedded quasi-quoted runtime to 'Text', parses it into
-- 'JSAnalysis.BlockGroup's, then builds per-definition entries using the
-- same AST-based machinery used for FFI tree-shaking.
--
-- Falls back to an empty registry on parse failure; all callers degrade
-- gracefully by emitting the full runtime in that case.
buildRegistry :: Map RuntimeId RuntimeDef
buildRegistry =
  case JSAnalysis.parseAllGroups runtimeText of
    Nothing                 -> Map.empty
    Just (_, groups)        -> buildFromGroups runtimeText groups
  where
    runtimeText = TextEnc.decodeUtf8 (BL.toStrict (BB.toLazyByteString embeddedRuntimeContent))

-- | Build the registry map from a parsed list of block groups.
buildFromGroups :: Text.Text -> [JSAnalysis.BlockGroup] -> Map RuntimeId RuntimeDef
buildFromGroups content groups =
  Map.union primaryMap aliasMap
  where
    textLines    = Text.lines content
    allNames     = Set.fromList (concatMap JSAnalysis.groupDeclNames groups)
    starts       = List.map (walkBackJSDocText textLines . JSAnalysis._bgLine) groups
    primaryMap   = Map.fromList (zipWith (mkEntry textLines allNames) groups starts)
    aliasMap     = buildAliasMap primaryMap groups

-- | Build a single registry entry for a block group.
mkEntry
  :: [Text.Text]
  -> Set ByteString
  -> JSAnalysis.BlockGroup
  -> Int
  -> (RuntimeId, RuntimeDef)
mkEntry textLines allNames g start =
  (RuntimeId (JSAnalysis._bgName g), mkDefFromGroup g allNames jsDoc start)
  where
    docLineCount = JSAnalysis._bgLine g - start
    jsDocLines   = List.take docLineCount (List.drop start textLines)
    jsDocText    = Text.unlines jsDocLines
    jsDoc        = if docLineCount > 0 then Just jsDocText else Nothing

-- | Create a 'RuntimeDef' from a parsed group using AST-based analysis.
mkDefFromGroup
  :: JSAnalysis.BlockGroup -> Set ByteString -> Maybe Text.Text -> Int -> RuntimeDef
mkDefFromGroup g allNames jsDoc order =
  RuntimeDef stmts jsDoc deps arities order
  where
    stmts         = JSAnalysis._bgStatements g
    selfName      = JSAnalysis._bgName g
    localFreeVars = JSAnalysis.freeVarsInGroup allNames stmts
    deps          = Set.map RuntimeId (Set.delete selfName localFreeVars)
    arities       = JSAnalysis.aritiesInGroup stmts

-- | Build alias entries for comma-separated @var@ declarations.
buildAliasMap
  :: Map RuntimeId RuntimeDef -> [JSAnalysis.BlockGroup] -> Map RuntimeId RuntimeDef
buildAliasMap primaryMap groups =
  Map.fromList (concatMap mkAliases groups)
  where
    mkAliases g =
      case JSAnalysis.groupDeclNames g of
        (primary : aliases) ->
          maybe [] (mkAliasEntries aliases) (Map.lookup (RuntimeId primary) primaryMap)
        [] -> []
    mkAliasEntries aliases def =
      [ (RuntimeId alias, def)
      | alias <- aliases
      , not (Map.member (RuntimeId alias) primaryMap)
      ]

-- INTERNAL: JSDOC WALK-BACK (TEXT-BASED)

-- | Walk backwards from a declaration line to find where its JSDoc starts.
--
-- Returns the 0-indexed line at which the JSDoc comment (or other immediately
-- preceding comments\/blank lines) begins, so that the block content includes
-- the full documentation block.
--
-- @*\/@ on its own line is treated as a hard stop: the closing delimiter of a
-- block comment (@\/* ... *\/@) is not included in the JSDoc. The embedded
-- runtime uses only single-line @\/** ... *\/@ JSDoc, so a standalone @*\/@
-- always belongs to a section\/block comment rather than a declaration JSDoc.
walkBackJSDocText :: [Text.Text] -> Int -> Int
walkBackJSDocText _ 0 = 0
walkBackJSDocText allLines declIdx = go (declIdx - 1)
  where
    go idx
      | idx < 0   = 0
      | otherwise =
          let line     = allLines List.!! idx
              stripped = Text.dropWhile (== ' ') line
           in if Text.isPrefixOf "*/" stripped
                then idx + 1   -- stop before the */; never include block-comment closers
                else if isLineComment stripped || Text.null (Text.strip line)
                then go (idx - 1)
                else idx + 1
    isLineComment l =
      Text.isPrefixOf "/**" l
        || Text.isPrefixOf "/*" l
        || Text.isPrefixOf " *" l
        || Text.isPrefixOf "* " l
        || Text.isPrefixOf "*\n" l
        || Text.isPrefixOf "//" l
        || l == "*"

-- INTERNAL: EMBEDDED RUNTIME CONTENT

-- | The full embedded Canopy runtime as a raw quasi-quoted string.
--
-- This is identical to what was previously in "Generate.JavaScript.Runtime".
-- It is parsed at initialization to build the registry.
embeddedRuntimeContent :: Builder
embeddedRuntimeContent = BB.stringUtf8 [r|

// ============================================================
// Canopy Runtime (embedded compiler infrastructure)
// ============================================================

// ============================================================
// CROSS-PACKAGE COMPATIBILITY
// ============================================================
//
// runtime.js references a few functions defined in other FFI files
// (json.js, jsarray.js). Those files use function declarations which
// are hoisted, so these aliases resolve correctly even though
// runtime.js appears earlier in the bundle.

// _Json_wrap and _Json_unwrap are function declarations in json.js (hoisted).
// _Json_runHelp is also a function declaration in json.js (hoisted).
// We define _Json_run here because json.js exposes it as 'run' (FFI binding
// name) rather than '_Json_run'.
/** @canopy-type Json.Decoder a -> Json.Value -> Result Json.Error a */
var _Json_run = F2(function(decoder, value) {
	return _Json_runHelp(decoder, _Json_unwrap(value));
});

// _Json_errorToString is a compiled Canopy function. Provide a fallback
// for the rare case where flag decoding fails during _Platform_initialize.
/** @canopy-type Json.Error -> String */
function _Json_errorToString(error) {
	return '<json decode error>';
}

// _Array_toList is needed by Debug.toString (debug mode only).
// Elm Arrays store data in a tree; the leaf array is in .d field.
/** @canopy-type Array a -> List a */
function _Array_toList(array) {
	return _List_fromArray(array.d || []);
}


// ============================================================
// COMMON TYPE CONSTRUCTORS
// ============================================================
//
// Shared constructors used across multiple FFI files.
// Debug mode uses string tags; prod uses integer tags.

/** @canopy-type a -> Maybe a */
function _Maybe_Just(a) { return { $: __canopy_debug ? 'Just' : 0, a: a }; }
/** @canopy-type Maybe a */
var _Maybe_Nothing = { $: __canopy_debug ? 'Nothing' : 1 };
/** @canopy-type Maybe a -> Bool */
function _Maybe_isJust(m) { return m.$ === (__canopy_debug ? 'Just' : 0); }

/** @canopy-type a -> Result x a */
function _Result_Ok(a) { return { $: __canopy_debug ? 'Ok' : 0, a: a }; }
/** @canopy-type x -> Result x a */
function _Result_Err(a) { return { $: __canopy_debug ? 'Err' : 1, a: a }; }
/** @canopy-type Result x a -> Bool */
function _Result_isOk(r) { return r.$ === (__canopy_debug ? 'Ok' : 0); }

/** @canopy-type Never -> a */
function _Basics_never(_) { /* unreachable by design */ }


// ============================================================
// JSON DECODER PRIMITIVES (early availability for cross-package FFI)
// ============================================================
// These must be defined before any FFI IIFE that references them
// (e.g., file.js uses _Json_decodePrim before json.js IIFE loads).
// The json.js IIFE will override these with its own definitions.

/** @canopy-type Int */
var _Json_PRIM = 2;
/** @canopy-type (Json.Value -> a) -> Json.Decoder a */
var _Json_decodePrim = function(decoder) { return { $: _Json_PRIM, __decoder: decoder }; };


// ============================================================
// DICT / SET HELPERS
// ============================================================

/** @canopy-type Dict comparable v -> List ( comparable, v ) */
function _Dict_toList(dict) {
	return _Dict_toListHelp(dict, _List_Nil);
}
/** @canopy-type Dict comparable v -> List ( comparable, v ) -> List ( comparable, v ) */
function _Dict_toListHelp(dict, list) {
	if (dict.$ === (__canopy_debug ? 'RBEmpty_elm_builtin' : -2)) return list;
	list = _Dict_toListHelp(dict.e, list);
	list = _List_Cons(_Utils_Tuple2(dict.b, dict.c), list);
	return _Dict_toListHelp(dict.d, list);
}

/** @canopy-type Set comparable -> List comparable */
function _Set_toList(set) {
	return _Set_toListHelp(set.a, _List_Nil);
}
/** @canopy-type Set comparable -> List comparable -> List comparable */
function _Set_toListHelp(set, list) {
	if (set.$ === (__canopy_debug ? 'RBEmpty_elm_builtin' : -2)) return list;
	list = _Set_toListHelp(set.e, list);
	list = _List_Cons(set.b, list);
	return _Set_toListHelp(set.d, list);
}


// ============================================================
// UTILS
// ============================================================


// EQUALITY

/** @canopy-type a -> a -> Bool */
function _Utils_eq(x, y)
{
	for (
		var pair, stack = [], isEqual = _Utils_eqHelp(x, y, 0, stack);
		isEqual && (pair = stack.pop());
		isEqual = _Utils_eqHelp(pair.a, pair.b, 0, stack)
		)
	{}

	return isEqual;
}

/** @canopy-type a -> a -> Int -> List ( a, a ) -> Bool */
function _Utils_eqHelp(x, y, depth, stack)
{
	if (x === y)
	{
		return true;
	}

	if (typeof x !== 'object' || x === null || typeof y !== 'object' || y === null)
	{
		typeof x === 'function' && _Debug_crash(5);
		return false;
	}

	if (x instanceof String)
	{
		return x.valueOf() === y.valueOf();
	}

	if (depth > 100)
	{
		stack.push(_Utils_Tuple2(x,y));
		return true;
	}

	if (__canopy_debug)
	{
		if (x.$ === 'Set_elm_builtin')
		{
			x = _Set_toList(x);
			y = _Set_toList(y);
		}
		if (x.$ === 'RBNode_elm_builtin' || x.$ === 'RBEmpty_elm_builtin')
		{
			x = _Dict_toList(x);
			y = _Dict_toList(y);
		}
	}
	else
	{
		if (x.$ < 0)
		{
			x = _Dict_toList(x);
			y = _Dict_toList(y);
		}
	}

	if (typeof DataView === "function" && x instanceof DataView) {
		var length = x.byteLength;

		if (y.byteLength !== length) {
			return false;
		}

		for (var i = 0; i < length; ++i) {
			if (x.getUint8(i) !== y.getUint8(i)) {
				return false;
			}
		}
	}

	for (var key in x)
	{
		if (!Object.prototype.hasOwnProperty.call(x, key)) continue;
		if (!_Utils_eqHelp(x[key], y[key], depth + 1, stack))
		{
			return false;
		}
	}
	return true;
}

/** @canopy-type a -> a -> Bool */
var _Utils_equal = F2(_Utils_eq);
/** @canopy-type a -> a -> Bool */
var _Utils_notEqual = F2(function(a, b) { return !_Utils_eq(a,b); });



// COMPARISONS

// Code in Generate/JavaScript.hs, Basics.js, and List.js depends on
// the particular integer values assigned to LT, EQ, and GT.

/** @canopy-type comparable -> comparable -> Int */
function _Utils_cmp(x, y, ord)
{
	if (typeof x !== 'object')
	{
		return x === y ? /*EQ*/ 0 : x < y ? /*LT*/ -1 : /*GT*/ 1;
	}

	if (__canopy_debug)
	{
		if (x instanceof String)
		{
			var a = x.valueOf();
			var b = y.valueOf();
			return a === b ? 0 : a < b ? -1 : 1;
		}
	}

	if (__canopy_debug ? x.$[0] === '#' : typeof x.$ === 'undefined')
	{
		return (ord = _Utils_cmp(x.a, y.a))
			? ord
			: (ord = _Utils_cmp(x.b, y.b))
				? ord
				: _Utils_cmp(x.c, y.c);
	}

	// traverse conses until end of a list or a mismatch
	if (!x.b && !y.b && typeof x.$ === 'undefined' && !__canopy_debug)
	{
		return 0;
	}
	if (__canopy_debug && !x.b && x.$ !== '::' && x.$ !== '[]')
	{
		throw new Error('Canopy runtime: _Utils_cmp called on non-comparable object');
	}
	for (; x.b && y.b && !(ord = _Utils_cmp(x.a, y.a)); x = x.b, y = y.b) {} // WHILE_CONSES
	return ord || (x.b ? /*GT*/ 1 : y.b ? /*LT*/ -1 : /*EQ*/ 0);
}

/** @canopy-type comparable -> comparable -> Bool */
var _Utils_lt = F2(function(a, b) { return _Utils_cmp(a, b) < 0; });
/** @canopy-type comparable -> comparable -> Bool */
var _Utils_le = F2(function(a, b) { return _Utils_cmp(a, b) < 1; });
/** @canopy-type comparable -> comparable -> Bool */
var _Utils_gt = F2(function(a, b) { return _Utils_cmp(a, b) > 0; });
/** @canopy-type comparable -> comparable -> Bool */
var _Utils_ge = F2(function(a, b) { return _Utils_cmp(a, b) >= 0; });

/** @canopy-type comparable -> comparable -> Order */
var _Utils_compare = F2(function(x, y)
{
	var n = _Utils_cmp(x, y);
	return n < 0 ? _Basics_LT : n ? _Basics_GT : _Basics_EQ;
});


// COMMON VALUES

/** @canopy-type () */
var _Utils_Tuple0 = __canopy_debug ? { $: '#0' } : 0;

/** @canopy-type a -> b -> ( a, b ) */
function _Utils_Tuple2(a, b) { return __canopy_debug ? { $: '#2', a: a, b: b } : { a: a, b: b }; }

/** @canopy-type a -> b -> c -> ( a, b, c ) */
function _Utils_Tuple3(a, b, c) { return __canopy_debug ? { $: '#3', a: a, b: b, c: c } : { a: a, b: b, c: c }; }

/** @canopy-type String -> Char */
function _Utils_chr(c) { return __canopy_debug ? new String(c) : c; }


// RECORDS

/** @canopy-type record -> record -> record */
function _Utils_update(oldRecord, updatedFields)
{
	var newRecord = {};

	for (var key in oldRecord)
	{
		newRecord[key] = oldRecord[key];
	}

	for (var key in updatedFields)
	{
		newRecord[key] = updatedFields[key];
	}

	return newRecord;
}


// APPEND

/** @canopy-type appendable -> appendable -> appendable */
var _Utils_append = F2(_Utils_ap);

/** @canopy-type appendable -> appendable -> appendable */
function _Utils_ap(xs, ys)
{
	// append Strings
	if (typeof xs === 'string')
	{
		return xs + ys;
	}

	// append Lists
	if (!xs.b)
	{
		return ys;
	}
	var root = _List_Cons(xs.a, ys);
	xs = xs.b
	for (var curr = root; xs.b; xs = xs.b) // WHILE_CONS
	{
		curr = curr.b = _List_Cons(xs.a, ys);
	}
	return root;
}


// ============================================================
// LIST (code generator primitives)
// ============================================================


/** @canopy-type List a */
var _List_Nil = __canopy_debug ? { $: '[]' } : { $: 0 };

/** @canopy-type a -> List a -> List a */
function _List_Cons(hd, tl) { return __canopy_debug ? { $: '::', a: hd, b: tl } : { $: 1, a: hd, b: tl }; }

/** @canopy-type a -> List a -> List a */
var _List_cons = F2(_List_Cons);

/** @canopy-type Array a -> List a */
function _List_fromArray(arr)
{
	var out = _List_Nil;
	for (var i = arr.length; i--; )
	{
		out = _List_Cons(arr[i], out);
	}
	return out;
}

/** @canopy-type List a -> Array a */
function _List_toArray(xs)
{
	for (var out = []; xs.b; xs = xs.b) // WHILE_CONS
	{
		out.push(xs.a);
	}
	return out;
}


// ============================================================
// BASICS (compiler built-ins)
// ============================================================

/** @canopy-type Order */
var _Basics_LT = __canopy_debug ? { $: 'LT' } : 0;
/** @canopy-type Order */
var _Basics_EQ = __canopy_debug ? { $: 'EQ' } : 1;
/** @canopy-type Order */
var _Basics_GT = __canopy_debug ? { $: 'GT' } : 2;

// Math operators — curried wrappers for partially-applied uses
/** @canopy-type number -> number -> number */
var _Basics_add = F2(function(a, b) { return a + b; });
/** @canopy-type number -> number -> number */
var _Basics_sub = F2(function(a, b) { return a - b; });
/** @canopy-type number -> number -> number */
var _Basics_mul = F2(function(a, b) { return a * b; });
/** @canopy-type Float -> Float -> Float */
var _Basics_fdiv = F2(function(a, b) { return a / b; });
/** @canopy-type Int -> Int -> Int */
var _Basics_idiv = F2(function(a, b) { return (a / b) | 0; });
/** @canopy-type number -> number -> number */
var _Basics_pow = F2(Math.pow);

/** @canopy-type Int -> Int -> Int */
var _Basics_remainderBy = F2(function(b, a) { return a % b; });

/** @canopy-type Int -> Int -> Int */
var _Basics_modBy = F2(function(modulus, x)
{
	var answer = x % modulus;
	return modulus === 0
		? _Debug_crash(11)
		:
	((answer > 0 && modulus < 0) || (answer < 0 && modulus > 0))
		? answer + modulus
		: answer;
});

/** @canopy-type Float */
var _Basics_pi = Math.PI;
/** @canopy-type Float */
var _Basics_e = Math.E;
/** @canopy-type Float -> Float */
var _Basics_cos = Math.cos;
/** @canopy-type Float -> Float */
var _Basics_sin = Math.sin;
/** @canopy-type Float -> Float */
var _Basics_tan = Math.tan;
/** @canopy-type Float -> Float */
var _Basics_acos = Math.acos;
/** @canopy-type Float -> Float */
var _Basics_asin = Math.asin;
/** @canopy-type Float -> Float */
var _Basics_atan = Math.atan;
/** @canopy-type Float -> Float -> Float */
var _Basics_atan2 = F2(Math.atan2);

/** @canopy-type Int -> Float */
function _Basics_toFloat(x) { return x; }
/** @canopy-type Float -> Int */
function _Basics_truncate(n) { return n | 0; }
/** @canopy-type Float -> Bool */
function _Basics_isInfinite(n) { return n === Infinity || n === -Infinity; }

/** @canopy-type Float -> Int */
var _Basics_ceiling = Math.ceil;
/** @canopy-type Float -> Int */
var _Basics_floor = Math.floor;
/** @canopy-type Float -> Int */
var _Basics_round = Math.round;
/** @canopy-type Float -> Float */
var _Basics_sqrt = Math.sqrt;
/** @canopy-type Float -> Float */
var _Basics_log = Math.log;
/** @canopy-type Float -> Bool */
var _Basics_isNaN = isNaN;

/** @canopy-type Bool -> Bool */
function _Basics_not(bool) { return !bool; }
/** @canopy-type Bool -> Bool -> Bool */
var _Basics_and = F2(function(a, b) { return a && b; });
/** @canopy-type Bool -> Bool -> Bool */
var _Basics_or  = F2(function(a, b) { return a || b; });
/** @canopy-type Bool -> Bool -> Bool */
var _Basics_xor = F2(function(a, b) { return a !== b; });


// ============================================================
// DEBUG (code generator primitives)
// ============================================================


/** @canopy-type String -> a -> a */
var _Debug_log = __canopy_debug
	? F2(function(tag, value)
	{
		console.log(tag + ': ' + _Debug_toString(value));
		return value;
	})
	: F2(function(tag, value)
	{
		return value;
	});

/** @canopy-type String -> Region -> String -> a */
function _Debug_todo(moduleName, region)
{
	return function(message) {
		_Debug_crash(8, moduleName, region, message);
	};
}

/** @canopy-type String -> Region -> a -> String -> b */
function _Debug_todoCase(moduleName, region, value)
{
	return function(message) {
		_Debug_crash(9, moduleName, region, value, message);
	};
}

/** @canopy-type a -> String */
var _Debug_toString = __canopy_debug
	? function(value) { return _Debug_toAnsiString(false, value); }
	: function(value) { return '<internals>'; };

/** @canopy-type Bool -> a -> String */
function _Debug_toAnsiString(ansi, value)
{
	if (typeof value === 'function')
	{
		return _Debug_internalColor(ansi, '<function>');
	}

	if (typeof value === 'boolean')
	{
		return _Debug_ctorColor(ansi, value ? 'True' : 'False');
	}

	if (typeof value === 'number')
	{
		return _Debug_numberColor(ansi, value + '');
	}

	if (value instanceof String)
	{
		return _Debug_charColor(ansi, "'" + _Debug_addSlashes(value, true) + "'");
	}

	if (typeof value === 'string')
	{
		return _Debug_stringColor(ansi, '"' + _Debug_addSlashes(value, false) + '"');
	}

	if (typeof value === 'object' && '$' in value)
	{
		var tag = value.$;

		if (typeof tag === 'number')
		{
			return _Debug_internalColor(ansi, '<internals>');
		}

		if (tag[0] === '#')
		{
			var output = [];
			for (var k in value)
			{
				if (k === '$') continue;
				output.push(_Debug_toAnsiString(ansi, value[k]));
			}
			return '(' + output.join(',') + ')';
		}

		if (tag === 'Set_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Set')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, _Set_toList(value));
		}

		if (tag === 'RBNode_elm_builtin' || tag === 'RBEmpty_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Dict')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, _Dict_toList(value));
		}

		if (tag === 'Array_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Array')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, _Array_toList(value));
		}

		if (tag === '::' || tag === '[]')
		{
			var output = '[';

			value.b && (output += _Debug_toAnsiString(ansi, value.a), value = value.b)

			for (; value.b; value = value.b) // WHILE_CONS
			{
				output += ',' + _Debug_toAnsiString(ansi, value.a);
			}
			return output + ']';
		}

		var output = '';
		for (var i in value)
		{
			if (i === '$') continue;
			var str = _Debug_toAnsiString(ansi, value[i]);
			var c0 = str[0];
			var parenless = c0 === '{' || c0 === '(' || c0 === '[' || c0 === '<' || c0 === '"' || str.indexOf(' ') < 0;
			output += ' ' + (parenless ? str : '(' + str + ')');
		}
		return _Debug_ctorColor(ansi, tag) + output;
	}

	if (typeof DataView === 'function' && value instanceof DataView)
	{
		return _Debug_stringColor(ansi, '<' + value.byteLength + ' bytes>');
	}

	if (typeof File !== 'undefined' && value instanceof File)
	{
		return _Debug_internalColor(ansi, '<' + value.name + '>');
	}

	if (typeof value === 'object')
	{
		var output = [];
		for (var key in value)
		{
			var field = key[0] === '_' ? key.slice(1) : key;
			output.push(_Debug_fadeColor(ansi, field) + ' = ' + _Debug_toAnsiString(ansi, value[key]));
		}
		if (output.length === 0)
		{
			return '{}';
		}
		return '{ ' + output.join(', ') + ' }';
	}

	return _Debug_internalColor(ansi, '<internals>');
}

/** @canopy-type String -> Bool -> String */
function _Debug_addSlashes(str, isChar)
{
	var s = str
		.replace(/\\/g, '\\\\')
		.replace(/\n/g, '\\n')
		.replace(/\t/g, '\\t')
		.replace(/\r/g, '\\r')
		.replace(/\v/g, '\\v')
		.replace(/\0/g, '\\0');

	if (isChar)
	{
		return s.replace(/\'/g, '\\\'');
	}
	else
	{
		return s.replace(/\"/g, "\\\"");
	}
}

/** @canopy-type Bool -> String -> String */
function _Debug_ctorColor(ansi, string)
{
	return ansi ? '\x1b[96m' + string + '\x1b[0m' : string;
}

/** @canopy-type Bool -> String -> String */
function _Debug_numberColor(ansi, string)
{
	return ansi ? '\x1b[95m' + string + '\x1b[0m' : string;
}

/** @canopy-type Bool -> String -> String */
function _Debug_stringColor(ansi, string)
{
	return ansi ? '\x1b[93m' + string + '\x1b[0m' : string;
}

/** @canopy-type Bool -> String -> String */
function _Debug_charColor(ansi, string)
{
	return ansi ? '\x1b[92m' + string + '\x1b[0m' : string;
}

/** @canopy-type Bool -> String -> String */
function _Debug_fadeColor(ansi, string)
{
	return ansi ? '\x1b[37m' + string + '\x1b[0m' : string;
}

/** @canopy-type Bool -> String -> String */
function _Debug_internalColor(ansi, string)
{
	return ansi ? '\x1b[36m' + string + '\x1b[0m' : string;
}

/** @canopy-type Int -> String */
function _Debug_toHexDigit(n)
{
	return String.fromCharCode(n < 10 ? 48 + n : 55 + n);
}

/** @canopy-type Int -> a */
var _Debug_crash = __canopy_debug
	? function(identifier, fact1, fact2, fact3, fact4)
	{
		switch(identifier)
		{
			case 0:
				throw new Error('What node should I take over? In JavaScript I need something like:\n\n    Elm.Main.init({\n        node: document.getElementById("elm-node")\n    })\n\nYou need to do this with any Browser.sandbox or Browser.element program.');

			case 1:
				throw new Error('Browser.application programs cannot handle URLs like this:\n\n    ' + document.location.href + '\n\nWhat is the root? The root of your file system? Try looking at this program with `elm reactor` or some other server.');

			case 2:
				var jsonErrorString = fact1;
				throw new Error('Problem with the flags given to your Elm program on initialization.\n\n' + jsonErrorString);

			case 3:
				var portName = fact1;
				throw new Error('There can only be one port named `' + portName + '`, but your program has multiple.');

			case 4:
				var portName = fact1;
				var problem = fact2;
				throw new Error('Trying to send an unexpected type of value through port `' + portName + '`:\n' + problem);

			case 5:
				throw new Error('Trying to use `(==)` on functions.\nThere is no way to know if functions are "the same" in the Elm sense.\nRead more about this at https://package.elm-lang.org/packages/elm/core/latest/Basics#== which describes why it is this way and what the better version will look like.');

			case 6:
				var moduleName = fact1;
				throw new Error('Your page is loading multiple Elm scripts with a module named ' + moduleName + '. Maybe a duplicate script is getting loaded accidentally? If not, rename one of them so I know which is which!');

			case 8:
				var moduleName = fact1;
				var region = fact2;
				var message = fact3;
				throw new Error('TODO in module `' + moduleName + '` ' + _Debug_regionToString(region) + '\n\n' + message);

			case 9:
				var moduleName = fact1;
				var region = fact2;
				var value = fact3;
				var message = fact4;
				throw new Error(
					'TODO in module `' + moduleName + '` from the `case` expression '
					+ _Debug_regionToString(region) + '\n\nIt received the following value:\n\n    '
					+ _Debug_toString(value).replace('\n', '\n    ')
					+ '\n\nBut the branch that handles it says:\n\n    ' + message.replace('\n', '\n    ')
				);

			case 10:
				throw new Error('Bug in https://github.com/elm/virtual-dom/issues');

			case 11:
				throw new Error('Cannot perform mod 0. Division by zero error.');
		}
	}
	: function(identifier)
	{
		throw new Error('https://github.com/elm/core/blob/1.0.0/hints/' + identifier + '.md');
	};

/** @canopy-type Region -> String */
function _Debug_regionToString(region)
{
	if (region.start.line === region.end.line)
	{
		return 'on line ' + region.start.line;
	}
	return 'on lines ' + region.start.line + ' through ' + region.end.line;
}


// ============================================================
// PROCESS (timer-based sleep)
// ============================================================


/** @canopy-type Float -> Task x () */
function _Process_sleep(time)
{
	return _Scheduler_binding(function(callback) {
		var id = setTimeout(function() {
			callback(_Scheduler_succeed(_Utils_Tuple0));
		}, time);

		return function() { clearTimeout(id); };
	});
}


// ============================================================
// SCHEDULER
// ============================================================

// Task discriminant tags
/** @canopy-type Int */
var _Scheduler_SUCCEED  = 0;
/** @canopy-type Int */
var _Scheduler_FAIL     = 1;
/** @canopy-type Int */
var _Scheduler_BINDING  = 2;
/** @canopy-type Int */
var _Scheduler_AND_THEN = 3;
/** @canopy-type Int */
var _Scheduler_ON_ERROR = 4;
/** @canopy-type Int */
var _Scheduler_RECEIVE  = 5;


// TASKS

/** @canopy-type a -> Task x a */
function _Scheduler_succeed(value)
{
	return {
		$: _Scheduler_SUCCEED,
		__value: value
	};
}

/** @canopy-type x -> Task x a */
function _Scheduler_fail(error)
{
	return {
		$: _Scheduler_FAIL,
		__value: error
	};
}

/** @canopy-type ((Task x a -> ()) -> Maybe (() -> ())) -> Task x a */
function _Scheduler_binding(callback)
{
	return {
		$: _Scheduler_BINDING,
		__callback: callback,
		__kill: null
	};
}

/** @canopy-type (a -> Task x b) -> Task x a -> Task x b */
var _Scheduler_andThen = F2(function(callback, task)
{
	return {
		$: _Scheduler_AND_THEN,
		__callback: callback,
		__task: task
	};
});

/** @canopy-type (x -> Task y a) -> Task x a -> Task y a */
var _Scheduler_onError = F2(function(callback, task)
{
	return {
		$: _Scheduler_ON_ERROR,
		__callback: callback,
		__task: task
	};
});

/** @canopy-type (msg -> Task x a) -> Task x a */
function _Scheduler_receive(callback)
{
	return {
		$: _Scheduler_RECEIVE,
		__callback: callback
	};
}


// PROCESSES

/** @canopy-type Int */
var _Scheduler_guid = 0;

/** @canopy-type Task x a -> Process */
function _Scheduler_rawSpawn(task)
{
	var proc = {
		$: 0,
		__id: (_Scheduler_guid = (_Scheduler_guid + 1) % 9007199254740991),
		__root: task,
		__stack: null,
		__mailbox: []
	};

	_Scheduler_enqueue(proc);

	return proc;
}

/** @canopy-type Task x a -> Task y Process */
function _Scheduler_spawn(task)
{
	return _Scheduler_binding(function(callback) {
		callback(_Scheduler_succeed(_Scheduler_rawSpawn(task)));
	});
}

/** @canopy-type Process -> msg -> () */
function _Scheduler_rawSend(proc, msg)
{
	proc.__mailbox.push(msg);
	_Scheduler_enqueue(proc);
}

/** @canopy-type Process -> msg -> Task x () */
var _Scheduler_send = F2(function(proc, msg)
{
	return _Scheduler_binding(function(callback) {
		_Scheduler_rawSend(proc, msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});

/** @canopy-type Process -> Task x () */
function _Scheduler_kill(proc)
{
	return _Scheduler_binding(function(callback) {
		var task = proc.__root;
		if (task.$ === _Scheduler_BINDING && task.__kill)
		{
			task.__kill();
		}

		proc.__root = null;
		proc.__stack = null;
		proc.__mailbox = [];

		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
}


/* STEP PROCESSES

type alias Process =
  { $ : tag
  , id : unique_id
  , root : Task
  , stack : null | { $: SUCCEED | FAIL, a: callback, b: stack }
  , mailbox : [msg]
  }

*/


/** @canopy-type Bool */
var _Scheduler_working = false;
/** @canopy-type List Process */
var _Scheduler_queue = [];


/** @canopy-type Process -> () */
function _Scheduler_enqueue(proc)
{
	_Scheduler_queue.push(proc);
	if (_Scheduler_working)
	{
		return;
	}
	_Scheduler_working = true;
	try
	{
		while (proc = _Scheduler_queue.shift())
		{
			_Scheduler_step(proc);
		}
	}
	finally
	{
		_Scheduler_working = false;
	}
}


/** @canopy-type Process -> () */
function _Scheduler_step(proc)
{
	while (proc.__root)
	{
		var rootTag = proc.__root.$;
		if (rootTag === _Scheduler_SUCCEED || rootTag === _Scheduler_FAIL)
		{
			while (proc.__stack && proc.__stack.$ !== rootTag)
			{
				proc.__stack = proc.__stack.__rest;
			}
			if (!proc.__stack)
			{
				return;
			}
			proc.__root = proc.__stack.__callback(proc.__root.__value);
			proc.__stack = proc.__stack.__rest;
		}
		else if (rootTag === _Scheduler_BINDING)
		{
			proc.__root.__kill = proc.__root.__callback(function(newRoot) {
				proc.__root = newRoot;
				_Scheduler_enqueue(proc);
			});
			return;
		}
		else if (rootTag === _Scheduler_RECEIVE)
		{
			if (proc.__mailbox.length === 0)
			{
				return;
			}
			proc.__root = proc.__root.__callback(proc.__mailbox.shift());
		}
		else // if (rootTag === _Scheduler_AND_THEN || rootTag === _Scheduler_ON_ERROR)
		{
			proc.__stack = {
				$: rootTag === _Scheduler_AND_THEN ? _Scheduler_SUCCEED : _Scheduler_FAIL,
				__callback: proc.__root.__callback,
				__rest: proc.__stack
			};
			proc.__root = proc.__root.__task;
		}
	}
}


// ============================================================
// PLATFORM
// ============================================================

// Effect bag discriminant tags
/** @canopy-type Int */
var _Platform_SELF = 0;
/** @canopy-type Int */
var _Platform_LEAF = 1;
/** @canopy-type Int */
var _Platform_NODE = 2;
/** @canopy-type Int */
var _Platform_MAP  = 3;


// PROGRAMS


/** @canopy-type { init : flags -> ( model, Cmd msg ), update : msg -> model -> ( model, Cmd msg ), subscriptions : model -> Sub msg } -> Json.Decoder flags -> () -> flags -> Program flags model msg */
var _Platform_worker = F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.init,
		impl.update,
		impl.subscriptions,
		function() { return function() {} }
	);
});



// INITIALIZE A PROGRAM


/** @canopy-type Json.Decoder flags -> flags -> (flags -> ( model, Cmd msg )) -> (msg -> model -> ( model, Cmd msg )) -> (model -> Sub msg) -> ((msg -> ()) -> model -> (model -> () -> ())) -> { ports : ports } */
function _Platform_initialize(flagDecoder, args, init, update, subscriptions, stepperBuilder)
{
	var result = A2(_Json_run, flagDecoder, _Json_wrap(args ? args['flags'] : undefined));
	_Result_isOk(result) || _Debug_crash(2, __canopy_debug ? _Json_errorToString(result.a) : undefined);
	var managers = {};
	var initPair = init(result.a);
	var model = initPair.a;
	var stepper = stepperBuilder(sendToApp, model);
	var ports = _Platform_setupEffects(managers, sendToApp);

	function sendToApp(msg, viewMetadata)
	{
		var pair = A2(update, msg, model);
		stepper(model = pair.a, viewMetadata);
		_Platform_enqueueEffects(managers, pair.b, subscriptions(model));
	}

	_Platform_enqueueEffects(managers, initPair.b, subscriptions(model));

	return ports ? { ports: ports } : {};
}



// TRACK PRELOADS


/** @canopy-type Set String */
var _Platform_preload = new Set();


/** @canopy-type String -> () */
function _Platform_registerPreload(url)
{
	_Platform_preload.add(url);
}



// EFFECT MANAGERS


/** @canopy-type Dict String EffectManager */
var _Platform_effectManagers = {};


/** @canopy-type Dict String EffectManager -> (msg -> ()) -> Maybe (Dict String Port) */
function _Platform_setupEffects(managers, sendToApp)
{
	var ports;

	// setup all necessary effect managers
	for (var key in _Platform_effectManagers)
	{
		var manager = _Platform_effectManagers[key];

		if (manager.__portSetup)
		{
			ports = ports || {};
			ports[key] = manager.__portSetup(key, sendToApp);
		}

		managers[key] = _Platform_instantiateManager(manager, sendToApp);
	}

	return ports;
}


/** @canopy-type Task Never state -> (Router msg -> List cmd -> List sub -> state -> Task Never state) -> (Router msg -> self -> state -> Task Never state) -> (cmd -> cmd) -> (sub -> sub) -> EffectManager */
function _Platform_createManager(init, onEffects, onSelfMsg, cmdMap, subMap)
{
	return {
		__init: init,
		__onEffects: onEffects,
		__onSelfMsg: onSelfMsg,
		__cmdMap: cmdMap,
		__subMap: subMap
	};
}


/** @canopy-type EffectManager -> (msg -> ()) -> Process */
function _Platform_instantiateManager(info, sendToApp)
{
	var router = {
		__sendToApp: sendToApp,
		__selfProcess: undefined
	};

	var onEffects = info.__onEffects;
	var onSelfMsg = info.__onSelfMsg;
	var cmdMap = info.__cmdMap;
	var subMap = info.__subMap;

	function loop(state)
	{
		return A2(_Scheduler_andThen, loop, _Scheduler_receive(function(msg)
		{
			var value = msg.a;

			if (msg.$ === _Platform_SELF)
			{
				return A3(onSelfMsg, router, value, state);
			}

			return cmdMap && subMap
				? A4(onEffects, router, value.__cmds, value.__subs, state)
				: A3(onEffects, router, cmdMap ? value.__cmds : value.__subs, state);
		}));
	}

	return router.__selfProcess = _Scheduler_rawSpawn(A2(_Scheduler_andThen, loop, info.__init));
}



// ROUTING


/** @canopy-type Router msg -> msg -> Task x () */
var _Platform_sendToApp = F2(function(router, msg)
{
	return _Scheduler_binding(function(callback)
	{
		router.__sendToApp(msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});


/** @canopy-type Router msg -> msg -> Task x () */
var _Platform_sendToSelf = F2(function(router, msg)
{
	return A2(_Scheduler_send, router.__selfProcess, {
		$: _Platform_SELF,
		a: msg
	});
});



// BAGS


/** @canopy-type String -> a -> Cmd msg */
function _Platform_leaf(home)
{
	return function(value)
	{
		return {
			$: _Platform_LEAF,
			__home: home,
			__value: value
		};
	};
}


/** @canopy-type List (Cmd msg) -> Cmd msg */
function _Platform_batch(list)
{
	return {
		$: _Platform_NODE,
		__bags: list
	};
}


/** @canopy-type (a -> msg) -> Cmd a -> Cmd msg */
var _Platform_map = F2(function(tagger, bag)
{
	return {
		$: _Platform_MAP,
		__func: tagger,
		__bag: bag
	}
});



// PIPE BAGS INTO EFFECT MANAGERS

/** @canopy-type List { managers : Dict String Process, cmdBag : Cmd msg, subBag : Sub msg } */
var _Platform_effectsQueue = [];
/** @canopy-type Bool */
var _Platform_effectsActive = false;


/** @canopy-type Dict String Process -> Cmd msg -> Sub msg -> () */
function _Platform_enqueueEffects(managers, cmdBag, subBag)
{
	_Platform_effectsQueue.push({ __managers: managers, __cmdBag: cmdBag, __subBag: subBag });

	if (_Platform_effectsActive) return;

	_Platform_effectsActive = true;
	try
	{
		for (var fx; fx = _Platform_effectsQueue.shift(); )
		{
			_Platform_dispatchEffects(fx.__managers, fx.__cmdBag, fx.__subBag);
		}
	}
	finally
	{
		_Platform_effectsActive = false;
	}
}


/** @canopy-type Dict String Process -> Cmd msg -> Sub msg -> () */
function _Platform_dispatchEffects(managers, cmdBag, subBag)
{
	var effectsDict = {};
	_Platform_gatherEffects(true, cmdBag, effectsDict, null);
	_Platform_gatherEffects(false, subBag, effectsDict, null);

	for (var home in managers)
	{
		_Scheduler_rawSend(managers[home], {
			$: 'fx',
			a: effectsDict[home] || { __cmds: _List_Nil, __subs: _List_Nil }
		});
	}
}


/** @canopy-type Bool -> Cmd msg -> Dict String { cmds : List cmd, subs : List sub } -> List (a -> msg) -> () */
function _Platform_gatherEffects(isCmd, bag, effectsDict, taggers)
{
	switch (bag.$)
	{
		case _Platform_LEAF:
			var home = bag.__home;
			var effect = _Platform_toEffect(isCmd, home, taggers, bag.__value);
			effectsDict[home] = _Platform_insert(isCmd, effect, effectsDict[home]);
			return;

		case _Platform_NODE:
			for (var list = bag.__bags; list.b; list = list.b) // WHILE_CONS
			{
				_Platform_gatherEffects(isCmd, list.a, effectsDict, taggers);
			}
			return;

		case _Platform_MAP:
			_Platform_gatherEffects(isCmd, bag.__bag, effectsDict, {
				__tagger: bag.__func,
				__rest: taggers
			});
			return;
	}
}


/** @canopy-type Bool -> String -> List (a -> msg) -> a -> cmd */
function _Platform_toEffect(isCmd, home, taggers, value)
{
	function applyTaggers(x)
	{
		for (var temp = taggers; temp; temp = temp.__rest)
		{
			x = temp.__tagger(x);
		}
		return x;
	}

	var map = isCmd
		? _Platform_effectManagers[home].__cmdMap
		: _Platform_effectManagers[home].__subMap;

	return A2(map, applyTaggers, value)
}


/** @canopy-type Bool -> cmd -> { cmds : List cmd, subs : List sub } -> { cmds : List cmd, subs : List sub } */
function _Platform_insert(isCmd, newEffect, effects)
{
	effects = effects || { __cmds: _List_Nil, __subs: _List_Nil };

	isCmd
		? (effects.__cmds = _List_Cons(newEffect, effects.__cmds))
		: (effects.__subs = _List_Cons(newEffect, effects.__subs));

	return effects;
}



// PORTS


/** @canopy-type String -> () */
function _Platform_checkPortName(name)
{
	if (_Platform_effectManagers[name])
	{
		_Debug_crash(3, name)
	}
}



// OUTGOING PORTS


/** @canopy-type String -> (a -> Json.Value) -> (a -> Cmd msg) */
function _Platform_outgoingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		__cmdMap: _Platform_outgoingPortMap,
		__converter: converter,
		__portSetup: _Platform_setupOutgoingPort
	};
	return _Platform_leaf(name);
}


/** @canopy-type (a -> msg) -> a -> a */
var _Platform_outgoingPortMap = F2(function(tagger, value) { return value; });


/** @canopy-type String -> { subscribe : (Json.Value -> ()) -> (), unsubscribe : (Json.Value -> ()) -> () } */
function _Platform_setupOutgoingPort(name)
{
	var subs = [];
	var converter = _Platform_effectManagers[name].__converter;

	// CREATE MANAGER

	var init = _Process_sleep(0);

	_Platform_effectManagers[name].__init = init;
	_Platform_effectManagers[name].__onEffects = F3(function(router, cmdList, state)
	{
		for ( ; cmdList.b; cmdList = cmdList.b) // WHILE_CONS
		{
			// grab a separate reference to subs in case unsubscribe is called
			var currentSubs = subs;
			var value = _Json_unwrap(converter(cmdList.a));
			for (var i = 0; i < currentSubs.length; i++)
			{
				currentSubs[i](value);
			}
		}
		return init;
	});

	// PUBLIC API

	function subscribe(callback)
	{
		if (typeof callback !== 'function')
		{
			throw new Error('Trying to subscribe an invalid callback on port `' + name + '`');
		}

		subs.push(callback);
	}

	function unsubscribe(callback)
	{
		// copy subs into a new array in case unsubscribe is called within a
		// subscribed callback
		subs = subs.slice();
		var index = subs.indexOf(callback);
		if (index >= 0)
		{
			subs.splice(index, 1);
		}
	}

	return {
		subscribe: subscribe,
		unsubscribe: unsubscribe
	};
}



// INCOMING PORTS


/** @canopy-type String -> Json.Decoder a -> (a -> msg) -> Sub msg */
function _Platform_incomingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		__subMap: _Platform_incomingPortMap,
		__converter: converter,
		__portSetup: _Platform_setupIncomingPort
	};
	return _Platform_leaf(name);
}


/** @canopy-type (a -> msg) -> (Json.Value -> a) -> Json.Value -> msg */
var _Platform_incomingPortMap = F2(function(tagger, finalTagger)
{
	return function(value)
	{
		return tagger(finalTagger(value));
	};
});


/** @canopy-type String -> (msg -> ()) -> { send : Json.Value -> () } */
function _Platform_setupIncomingPort(name, sendToApp)
{
	var subs = _List_Nil;
	var converter = _Platform_effectManagers[name].__converter;

	// CREATE MANAGER

	var init = _Scheduler_succeed(null);

	_Platform_effectManagers[name].__init = init;
	_Platform_effectManagers[name].__onEffects = F3(function(router, subList, state)
	{
		subs = subList;
		return init;
	});

	// PUBLIC API

	function send(incomingValue)
	{
		var result = A2(_Json_run, converter, _Json_wrap(incomingValue));

		_Result_isOk(result) || _Debug_crash(4, name, result.a);

		var value = result.a;
		for (var temp = subs; temp.b; temp = temp.b) // WHILE_CONS
		{
			sendToApp(temp.a(value));
		}
	}

	return { send: send };
}



// EXPORT ELM MODULES

/** @canopy-type a -> () */
function _Platform_export(exports)
{
	if (__canopy_debug)
	{
		scope['Elm']
			? _Platform_mergeExportsDebug('Elm', scope['Elm'], exports)
			: scope['Elm'] = exports;
	}
	else
	{
		scope['Elm']
			? _Platform_mergeExportsProd(scope['Elm'], exports)
			: scope['Elm'] = exports;
	}
}


/** @canopy-type a -> a -> () */
function _Platform_mergeExportsProd(obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6)
				: _Platform_mergeExportsProd(obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}


/** @canopy-type String -> a -> a -> () */
function _Platform_mergeExportsDebug(moduleName, obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6, moduleName)
				: _Platform_mergeExportsDebug(moduleName + '.' + name, obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}

// CAPABILITY GRANT (phantom type value — compile-time enforcement only)
// fromKernel "Kernel.Capability" "grant" produces _Kernel_Capability_grant
/** @canopy-type Capability */
var _Kernel_Capability_grant = 0;

// ============================================================
// End Canopy Runtime
// ============================================================

|]

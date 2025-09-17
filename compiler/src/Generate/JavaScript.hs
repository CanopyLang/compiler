{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Generate.JavaScript
  ( generate,
    generateForRepl,
    generateForReplEndpoint,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Kernel as K
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Exception (Exception, throw)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import qualified Data.Index as Index
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Maybe
import qualified Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Utf8 as Utf8
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.JavaScript.Functions as Functions
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.Mode as Mode
import qualified Reporting.Doc as D
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as L
import Prelude hiding (cycle, print)
import Text.RawString.QQ (r)

-- GENERATE

type Graph = Map Opt.Global Opt.Node

type Mains = Map ModuleName.Canonical Opt.Main

generate :: Mode.Mode -> Opt.GlobalGraph -> Mains -> Builder
generate mode (Opt.GlobalGraph graph _) mains =
  let baseState = Map.foldrWithKey (addMain mode graph) emptyState mains
      -- In elm-compatible mode, ensure core kernel functions are included
      state = case mode of
        Mode.Dev _ True -> addElmCoreKernels mode graph baseState
        _ -> baseState
      headerNewline = if Mode.isElmCompatible mode then "\n" else ""
   in "(function(scope){\n'use strict';" <> headerNewline
        <> Functions.functions
        <> perfNote mode
        <> comprehensiveRuntime mode
        <> stateToBuilder state
        <> toMainExports mode mains
        <> "}(this));"

-- | Force inclusion of elm/core kernel functions in elm-compatible mode
addElmCoreKernels :: Mode.Mode -> Graph -> State -> State
addElmCoreKernels mode graph state =
  -- Add kernel functions that Elm always includes
  let coreKernels = [
        -- Basics kernel functions
        Opt.Global (ModuleName.Canonical Pkg.core "Basics") "add",
        Opt.Global (ModuleName.Canonical Pkg.core "Basics") "sub",
        Opt.Global (ModuleName.Canonical Pkg.core "Basics") "mul",
        Opt.Global (ModuleName.Canonical Pkg.core "Basics") "fdiv",
        Opt.Global (ModuleName.Canonical Pkg.core "Basics") "idiv",
        -- Utils kernel functions
        Opt.Global (ModuleName.Canonical Pkg.core "Utils") "eq",
        Opt.Global (ModuleName.Canonical Pkg.core "Utils") "cmp"
      ]
  in List.foldl' (\s global ->
       case Map.lookup global graph of
         Just _ -> addGlobal mode graph s global
         Nothing -> s  -- Skip if not in graph
     ) state coreKernels

addMain :: Mode.Mode -> Graph -> ModuleName.Canonical -> Opt.Main -> State -> State
addMain mode graph home _ state =
  addGlobal mode graph state (Opt.Global home "main")

perfNote :: Mode.Mode -> Builder
perfNote mode =
  case mode of
    Mode.Prod _ _ ->
      mempty
    Mode.Dev Nothing _ ->
      -- Always include console.warn in dev mode to match Elm behavior
      -- Use explicit semicolon annotation to ensure semicolon is added
      JS.stmtToBuilder $
        JS.ExprStmtWithSemi $
          JS.Call
            (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "warn"))
            [ JS.String $
                "Compiled in DEV mode. Follow the advice at "
                  <> B.stringUtf8 (D.makeNakedLink "optimize")
                  <> " for better performance and smaller assets."
            ]
    Mode.Dev (Just _) _ ->
      -- Always include console.warn in dev mode to match Elm behavior
      -- Use explicit semicolon annotation to ensure semicolon is added
      JS.stmtToBuilder $
        JS.ExprStmtWithSemi $
          JS.Call
            (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "warn"))
            [ JS.String $
                "Compiled in DEBUG mode. Follow the advice at "
                  <> B.stringUtf8 (D.makeNakedLink "optimize")
                  <> " for better performance and smaller assets."
            ]

-- COMPREHENSIVE RUNTIME
--
-- This implements Elm-compatible runtime inclusion strategy.
-- Instead of dependency-based inclusion, we include a comprehensive
-- set of core runtime functions that Elm always provides.

comprehensiveRuntime :: Mode.Mode -> Builder
comprehensiveRuntime mode =
  case mode of
    Mode.Dev _ True ->  -- Only include comprehensive runtime in elm-compatible dev mode
      generateElmCompatibleRuntime
    _ ->
      mempty

-- Generate the core runtime functions that Elm always includes
generateElmCompatibleRuntime :: Builder
generateElmCompatibleRuntime =
  utilityFunctions
  <> equalityFunctions
  <> comparisonFunctions
  <> mathFunctions
  <> stringFunctions
  <> listFunctions
  <> debugFunctions
  <> jsonFunctions
  <> basicsFunctions

utilityFunctions :: Builder
utilityFunctions = [r|

// UTILITY FUNCTIONS

function _Utils_Tuple2(a, b) { return { $: '#2', a: a, b: b }; }
function _Utils_Tuple3(a, b, c) { return { $: '#3', a: a, b: b, c: c }; }
function _Utils_chr(c) { return { $: '#chr', valueOf: function() { return c; } }; }
function _Utils_update(oldRecord, updatedFields) {
  var newRecord = {};
  for (var key in oldRecord) { newRecord[key] = oldRecord[key]; }
  for (var key in updatedFields) { newRecord[key] = updatedFields[key]; }
  return newRecord;
}

|]

equalityFunctions :: Builder
equalityFunctions = [r|

// EQUALITY

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

function _Utils_eqHelp(x, y, depth, stack)
{
	if (x === y)
	{
		return true;
	}

	if (typeof x !== 'object' || x === null || y === null)
	{
		typeof x === 'function' && _Debug_crash(5);
		return false;
	}

	if (depth > 100)
	{
		stack.push(_Utils_Tuple2(x,y));
		return true;
	}

	/**/
	if (x.$ === 'Set_elm_builtin')
	{
		x = $elm$core$Set$toList(x);
		y = $elm$core$Set$toList(y);
	}
	if (x.$ === 'RBNode_elm_builtin' || x.$ === 'RBEmpty_elm_builtin')
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	/**_UNUSED/
	if (x.$ < 0)
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	for (var key in x)
	{
		if (!_Utils_eqHelp(x[key], y[key], depth + 1, stack))
		{
			return false;
		}
	}
	return true;
}

var _Utils_equal = F2(_Utils_eq);
var _Utils_notEqual = F2(function(a, b) { return !_Utils_eq(a,b); });

|]

comparisonFunctions :: Builder
comparisonFunctions =
  "// COMPARISON\n\
  \function _Utils_cmp(x, y, ord)\n\
  \{\n\
  \\tif (typeof x !== 'object')\n\
  \\t{\n\
  \\t\treturn x === y ? /*EQ*/ 0 : x < y ? /*LT*/ -1 : /*GT*/ 1;\n\
  \\t}\n\
  \\n\
  \\t/*\n\
  \\t * If x and y are both objects, we need to compare their tags and values.\n\
  \\t */\n\
  \\tif (x.$ !== y.$)\n\
  \\t{\n\
  \\t\treturn x.$ < y.$ ? -1 : 1;\n\
  \\t}\n\
  \\n\
  \\tfor (var idx = 0, xs = x.a, ys = y.a; idx < xs.length; idx++)\n\
  \\t{\n\
  \\t\tvar ord = _Utils_cmp(xs[idx], ys[idx]);\n\
  \\t\tif (ord !== 0) return ord;\n\
  \\t}\n\
  \\treturn xs.length - ys.length;\n\
  \}\n\
  \\n\
  \var _Utils_lt = F2(function(a, b) { return _Utils_cmp(a, b) < 0; });\n\
  \var _Utils_le = F2(function(a, b) { return _Utils_cmp(a, b) < 1; });\n\
  \var _Utils_gt = F2(function(a, b) { return _Utils_cmp(a, b) > 0; });\n\
  \var _Utils_ge = F2(function(a, b) { return _Utils_cmp(a, b) > -1; });\n\
  \var _Utils_compare = F2(_Utils_cmp);\n\n"

mathFunctions :: Builder
mathFunctions =
  "// MATH\n\
  \var _Basics_add = F2(function(a, b) { return a + b; });\n\
  \var _Basics_sub = F2(function(a, b) { return a - b; });\n\
  \var _Basics_mul = F2(function(a, b) { return a * b; });\n\
  \var _Basics_fdiv = F2(function(a, b) { return a / b; });\n\
  \var _Basics_idiv = F2(function(a, b) { return (a / b) | 0; });\n\
  \var _Basics_pow = F2(Math.pow);\n\
  \var _Basics_remainderBy = F2(function(b, a) { return a % b; });\n\
  \var _Basics_modBy = F2(function(modulus, x) {\n\
  \\tvar answer = x % modulus;\n\
  \\treturn modulus === 0 ? _Debug_crash(11) :\n\
  \\t\t((answer > 0 && modulus < 0) || (answer < 0 && modulus > 0)) ? answer + modulus : answer;\n\
  \});\n\
  \var _Basics_log = Math.log;\n\
  \var _Basics_isInfinite = function(n) { return n === Infinity || n === -Infinity; };\n\
  \var _Basics_isNaN = isNaN;\n\
  \var _Basics_sqrt = Math.sqrt;\n\
  \var _Basics_negate = function(n) { return -n; };\n\
  \var _Basics_abs = Math.abs;\n\
  \var _Basics_clamp = F3(function(lo, hi, n) { return n < lo ? lo : n > hi ? hi : n; });\n\
  \var _Basics_min = F2(Math.min);\n\
  \var _Basics_max = F2(Math.max);\n\n"

stringFunctions :: Builder
stringFunctions =
  "// STRINGS\n\
  \var _String_cons = F2(function(chr, str) { return chr + str; });\n\
  \function _String_fromNumber(number) { return number + ''; }\n\
  \function _String_fromChar(char) { return char; }\n\
  \var _String_uncons = F2(function(str) {\n\
  \\tvar hd = str.charAt(0);\n\
  \\treturn hd ? $elm$core$Maybe$Just(_Utils_Tuple2(hd, str.slice(1))) : $elm$core$Maybe$Nothing;\n\
  \});\n\n"

listFunctions :: Builder
listFunctions =
  "// LIST UTILS\n\
  \var _List_Nil = { $: '[]' };\n\
  \function _List_Nil_UNUSED() { return { $: '[]' }; }\n\
  \var _List_Cons = F2(function(hd, tl) { return { $: '::', a: hd, b: tl }; });\n\
  \function _List_Cons_UNUSED(hd) { return function(tl) { return { $: '::', a: hd, b: tl }; }; }\n\
  \\n\
  \var _List_cons = F2(_List_Cons);\n\
  \\n\
  \function _List_fromArray(arr)\n\
  \{\n\
  \\tvar out = _List_Nil;\n\
  \\tfor (var i = arr.length; i--; )\n\
  \\t{\n\
  \\t\tout = _List_Cons(arr[i], out);\n\
  \\t}\n\
  \\treturn out;\n\
  \}\n\
  \\n\
  \function _List_toArray(xs)\n\
  \{\n\
  \\tfor (var out = []; xs.$ === '::'; xs = xs.b) // WHILE_CONS\n\
  \\t{\n\
  \\t\tout.push(xs.a);\n\
  \\t}\n\
  \\treturn out;\n\
  \}\n\n"

debugFunctions :: Builder
debugFunctions =
  "// DEBUG\n\
  \function _Debug_crash(identifier)\n\
  \{\n\
  \\tthrow new Error('https://github.com/elm/core/blob/1.0.0/hints/' + identifier + '.md');\n\
  \}\n\
  \\n\
  \function _Debug_crash_UNUSED(identifier, fact1, fact2, fact3, fact4)\n\
  \{\n\
  \\tswitch(identifier)\n\
  \\t{\n\
  \\t\tcase 0:\n\
  \\t\t\tthrow new Error('What node should I take over? In JavaScript I need something like:\\n\\n    Elm.Main.init(\\n        { node: document.getElementById(\"elm-node\") }\\n    )\\n\\nYou need to do this with any Browser.* or Browser.application program.');\n\
  \\n\
  \\t\tcase 1:\n\
  \\t\t\tthrow new Error('Browser.application programs cannot handle URLs like this:\\n\\n    ' + document.location.href + '\\n\\nWhat is the root? The root of your file system? Try looking at this program with `canopy reactor` or some other local server.');\n\
  \\n\
  \\t\tcase 2:\n\
  \\t\t\tvar jsonErrorString = fact1;\n\
  \\t\t\tthrow new Error('Problem with the flags given to your Elm program on initialization.\\n\\n' + jsonErrorString);\n\
  \\n\
  \\t\tcase 3:\n\
  \\t\t\tvar portName = fact1;\n\
  \\t\t\tthrow new Error('There can only be one port named `' + portName + '`, but your program has multiple.');\n\
  \\n\
  \\t\tcase 4:\n\
  \\t\t\tvar portName = fact1;\n\
  \\t\t\tvar problem = fact2;\n\
  \\t\t\tthrow new Error('Trying to send an unexpected type of value through port `' + portName + '`:\\n' + problem);\n\
  \\n\
  \\t\tcase 5:\n\
  \\t\t\tthrow new Error('Trying to use `(==)` on functions.\\nThere is no way to know if functions are \"the same\" in the Elm sense.\\nRead more about this at https://package.canopy-lang.org/packages/canopy/core/latest/Basics#== which describes why it is this way and what the better version will look like.');\n\
  \\n\
  \\t\tcase 6:\n\
  \\t\t\tvar moduleName = fact1;\n\
  \\t\t\tthrow new Error('Your page is loading multiple Elm scripts with a module named ' + moduleName + '. Maybe a duplicate script is getting loaded accidentally? If not, rename one of them so I know which is which!');\n\
  \\n\
  \\t\tcase 8:\n\
  \\t\t\tvar moduleName = fact1;\n\
  \\t\t\tvar region = fact2;\n\
  \\t\t\tvar value = fact3;\n\
  \\t\t\tthrow new Error('TODO in module `' + moduleName + '` ' + _Debug_regionToString(region) + '\\n\\n' + value);\n\
  \\n\
  \\t\tcase 9:\n\
  \\t\t\tvar moduleName = fact1;\n\
  \\t\t\tvar region = fact2;\n\
  \\t\t\tthrow new Error('TODO in module `' + moduleName + '` from the `case` expression ' + _Debug_regionToString(region) + '\\n\\nIt received a value outside the range of the `case`. Add another branch to account for it or use a `default` branch to ignore it.');\n\
  \\n\
  \\t\tcase 10:\n\
  \\t\t\tthrow new Error('Bug in https://github.com/elm/virtual-dom/issues');\n\
  \\n\
  \\t\tcase 11:\n\
  \\t\t\tthrow new Error('Cannot perform mod 0. Division by zero error.');\n\
  \\t}\n\
  \}\n\n"

jsonFunctions :: Builder
jsonFunctions =
  "// JSON\n\
  \function _Json_succeed(msg)\n\
  \{\n\
  \\treturn {\n\
  \\t\t$: 0,\n\
  \\t\ta: msg\n\
  \\t};\n\
  \}\n\
  \\n\
  \function _Json_fail(msg)\n\
  \{\n\
  \\treturn {\n\
  \\t\t$: 1,\n\
  \\t\ta: msg\n\
  \\t};\n\
  \}\n\
  \\n\
  \function _Json_decodePrim(decoder)\n\
  \{\n\
  \\treturn { $: 1, b: decoder };\n\
  \}\n\
  \\n\
  \var _Json_decodeInt = _Json_decodePrim(function(value) {\n\
  \\treturn (typeof value !== 'number') ? _Json_expecting('an INT', value) :\n\
  \\t\t(-2147483647 < value && value < 2147483647 && (value | 0) === value) ? $elm$core$Result$Ok(value) :\n\
  \\t\t(isFinite(value) && !(value % 1)) ? $elm$core$Result$Ok(value) :\n\
  \\t\t_Json_expecting('an INT', value);\n\
  \});\n\n"

basicsFunctions :: Builder
basicsFunctions =
  "// BASICS\n\
  \function _Basics_append(xs, ys)\n\
  \{\n\
  \\t// append String/Text\n\
  \\tif (typeof xs === \"string\")\n\
  \\t{\n\
  \\t\treturn xs + ys;\n\
  \\t}\n\
  \\n\
  \\t// append List\n\
  \\tif (!xs.b)\n\
  \\t{\n\
  \\t\treturn ys;\n\
  \\t}\n\
  \\tvar root = _List_Cons(xs.a, _List_Nil);\n\
  \\tvar curr = root;\n\
  \\txs = xs.b;\n\
  \\twhile (xs.b)\n\
  \\t{\n\
  \\t\tcurr = curr.b = _List_Cons(xs.a, _List_Nil);\n\
  \\t\txs = xs.b;\n\
  \\t}\n\
  \\tcurr.b = _List_Cons(xs.a, ys);\n\
  \\treturn root;\n\
  \}\n\
  \var _Basics_apL = F2(_Basics_append);\n\
  \var _Basics_apR = F3(function(f, b, a) { return f(a, b); });\n\n"

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
    _seenGlobals :: Set Opt.Global
  }

emptyState :: State
emptyState =
  State mempty [] Set.empty

stateToBuilder :: State -> Builder
stateToBuilder (State revKernels revBuilders _) =
  prependBuilders revKernels (prependBuilders revBuilders mempty)

prependBuilders :: [Builder] -> Builder -> Builder
prependBuilders revBuilders monolith =
  List.foldl' (flip (<>)) monolith revBuilders

-- ADD DEPENDENCIES

addGlobal :: Mode.Mode -> Graph -> State -> Opt.Global -> State
addGlobal mode graph state@(State revKernels builders seen) global =
  if Set.member global seen
    then state
    else
      addGlobalHelp mode graph global $
        State revKernels builders (Set.insert global seen)

data MyException = MyException String
  deriving (Show)

instance Exception MyException

addGlobalHelp :: Mode.Mode -> Graph -> Opt.Global -> State -> State
addGlobalHelp mode graph currentGlobal state =
  let addDeps deps someState =
        Set.foldl' (addGlobal mode graph) someState deps
      Opt.Global globalCanonical globalName = currentGlobal
      canonicalPkgName = ModuleName._package globalCanonical
      global = Opt.Global (globalCanonical {ModuleName._package = canonicalPkgName}) globalName
      globalInGraph = case Map.lookup global graph of
        Just x -> x
        Nothing -> throw (MyException ("addGlobalHelp: this was graph keys " <> (show (Map.keys graph) <> (" and this was old global " <> (show currentGlobal <> (" and this was new global: " <> show global))))))
   in case globalInGraph of
        Opt.Define expr deps ->
          addStmt
            (addDeps deps state)
            ( var global (Expr.generate mode expr)
            )
        Opt.DefineTailFunc argNames body deps ->
          addStmt
            (addDeps deps state)
            ( let (Opt.Global _ name) = global
               in JS.Var (JsName.fromGlobal (case global of Opt.Global home _ -> home) name) (Expr.generateTailDefExpr mode name argNames body)
            )
        Opt.Ctor index arity ->
          addStmt
            state
            ( var global (Expr.generateCtor mode global index arity)
            )
        Opt.Link linkedGlobal ->
          addGlobal mode graph state linkedGlobal
        Opt.Cycle names values functions deps ->
          let cycleStmt = generateCycle mode global names values functions
              baseState = addDeps deps state
          in case cycleStmt of
               JS.Block stmts -> List.foldl' addStmt baseState stmts
               stmt -> addStmt baseState stmt
        Opt.Manager effectsType ->
          generateManager mode graph global effectsType state
        Opt.Kernel chunks deps ->
          if isDebugger global && not (Mode.isDebug mode)
            then state
            else addKernel (addDeps deps state) (generateKernel mode chunks)
        Opt.Enum index ->
          addStmt
            state
            ( generateEnum mode global index
            )
        Opt.Box ->
          addStmt
            (addGlobal mode graph state identity)
            ( generateBox mode global
            )
        Opt.PortIncoming decoder deps ->
          addStmt
            (addDeps deps state)
            ( generatePort mode global "incomingPort" decoder
            )
        Opt.PortOutgoing encoder deps ->
          addStmt
            (addDeps deps state)
            ( generatePort mode global "outgoingPort" encoder
            )

addStmt :: State -> JS.Stmt -> State
addStmt state stmt =
  addBuilder state (JS.stmtToBuilder stmt)

addBuilder :: State -> Builder -> State
addBuilder (State revKernels revBuilders seen) builder =
  State revKernels (builder : revBuilders) seen

addKernel :: State -> Builder -> State
addKernel (State revKernels revBuilders seen) kernel =
  State (kernel : revKernels) revBuilders seen

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
            Mode.Prod _ _ ->
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
        Mode.Prod _ _ ->
          "_UNUSED" <> builder
    K.Prod ->
      case mode of
        Mode.Dev _ elmCompatible ->
          if elmCompatible
            then "_UNUSED" <> builder  -- Elm dev: prod functions marked unused
            else "_UNUSED" <> builder  -- Canopy dev: prod functions marked unused
        Mode.Prod _ _ ->
          builder

-- GENERATE ENUM

generateEnum :: Mode.Mode -> Opt.Global -> Index.ZeroBased -> JS.Stmt
generateEnum mode global@(Opt.Global home name) index =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ ->
        Expr.codeToExpr (Expr.generateCtor mode global index 0)
      Mode.Prod _ _ ->
        JS.Int (Index.toMachine index)

-- GENERATE BOX

generateBox :: Mode.Mode -> Opt.Global -> JS.Stmt
generateBox mode global@(Opt.Global home name) =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ ->
        Expr.codeToExpr (Expr.generateCtor mode global Index.first 1)
      Mode.Prod _ _ ->
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
      error "cannot have two modules with the same name"

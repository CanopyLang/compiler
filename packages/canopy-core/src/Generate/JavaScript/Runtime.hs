{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Embedded Canopy Runtime
--
-- This module provides the core runtime primitives that the Canopy code
-- generator references directly by global name (@_Utils_eq@, @_List_Nil@,
-- @_Basics_add@, @_Scheduler_succeed@, @_Platform_worker@, etc.).
--
-- The runtime is embedded directly in every compiled JavaScript bundle,
-- following the same pattern as "Generate.JavaScript.Functions" (F\/A helpers)
-- and "Generate.JavaScript.FFIRuntime" (validation helpers).
--
-- = Sections
--
-- * Utils — equality, comparison, tuples, records, append
-- * List — Nil, Cons, fromArray, toArray
-- * Basics — LT\/EQ\/GT constructors, arithmetic operators
-- * Debug — crash, todo, todoCase, toString, log
-- * Scheduler — cooperative task scheduler
-- * Platform — program init, effect managers, ports, exports
-- * Process — sleep (timer-based task)
--
-- = Debug\/Prod Mode
--
-- The runtime uses @__canopy_debug@ (emitted before the runtime content)
-- to select between debug representations (string tags like @\"Just\"@)
-- and prod representations (integer tags like @0@).
--
-- @since 0.20.0
module Generate.JavaScript.Runtime
  ( -- * Runtime embedding
    embeddedRuntimeForMode
  ) where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Generate.Mode as Mode
import Text.RawString.QQ (r)

-- | Emit the full Canopy runtime, preceded by the @__canopy_debug@ declaration.
--
-- In dev mode: @var __canopy_debug = true;@ followed by the runtime.
-- In prod mode: @var __canopy_debug = false;@ followed by the runtime.
embeddedRuntimeForMode :: Mode.Mode -> Builder
embeddedRuntimeForMode mode =
  modeDeclaration mode <> embeddedRuntime
  where
    modeDeclaration :: Mode.Mode -> Builder
    modeDeclaration (Mode.Dev {}) = "var __canopy_debug = true;\n"
    modeDeclaration (Mode.Prod {}) = "var __canopy_debug = false;\n"

-- | Full embedded Canopy runtime.
--
-- Source: @packages\/canopy\/core\/external\/runtime.js@
embeddedRuntime :: Builder
embeddedRuntime = BB.stringUtf8 [r|

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
var _Json_run = F2(function(decoder, value) {
	return _Json_runHelp(decoder, _Json_unwrap(value));
});

// _Json_errorToString is a compiled Canopy function. Provide a fallback
// for the rare case where flag decoding fails during _Platform_initialize.
function _Json_errorToString(error) {
	return '<json decode error>';
}

// _Array_toList is needed by Debug.toString (debug mode only).
// Elm Arrays store data in a tree; the leaf array is in .d field.
function _Array_toList(array) {
	return _List_fromArray(array.d || []);
}


// ============================================================
// COMMON TYPE CONSTRUCTORS
// ============================================================
//
// Shared constructors used across multiple FFI files.
// Debug mode uses string tags; prod uses integer tags.

function _Maybe_Just(a) { return { $: __canopy_debug ? 'Just' : 0, a: a }; }
var _Maybe_Nothing = { $: __canopy_debug ? 'Nothing' : 1 };
function _Maybe_isJust(m) { return m.$ === (__canopy_debug ? 'Just' : 0); }

function _Result_Ok(a) { return { $: __canopy_debug ? 'Ok' : 0, a: a }; }
function _Result_Err(a) { return { $: __canopy_debug ? 'Err' : 1, a: a }; }
function _Result_isOk(r) { return r.$ === (__canopy_debug ? 'Ok' : 0); }

function _Basics_never(_) { /* unreachable by design */ }


// ============================================================
// JSON DECODER PRIMITIVES (used across packages)
// ============================================================

var _Json_PRIM = 2;
function _Json_decodePrim(decoder) { return { $: _Json_PRIM, __decoder: decoder }; }


// ============================================================
// DICT / SET HELPERS
// ============================================================

function _Dict_toList(dict) {
	return _Dict_toListHelp(dict, _List_Nil);
}
function _Dict_toListHelp(dict, list) {
	if (dict.$ === (__canopy_debug ? 'RBEmpty_elm_builtin' : -2)) return list;
	list = _Dict_toListHelp(dict.e, list);
	list = _List_Cons(_Utils_Tuple2(dict.b, dict.c), list);
	return _Dict_toListHelp(dict.d, list);
}

function _Set_toList(set) {
	return _Set_toListHelp(set.a, _List_Nil);
}
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
		if (!_Utils_eqHelp(x[key], y[key], depth + 1, stack))
		{
			return false;
		}
	}
	return true;
}

var _Utils_equal = F2(_Utils_eq);
var _Utils_notEqual = F2(function(a, b) { return !_Utils_eq(a,b); });



// COMPARISONS

// Code in Generate/JavaScript.hs, Basics.js, and List.js depends on
// the particular integer values assigned to LT, EQ, and GT.

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
	for (; x.b && y.b && !(ord = _Utils_cmp(x.a, y.a)); x = x.b, y = y.b) {} // WHILE_CONSES
	return ord || (x.b ? /*GT*/ 1 : y.b ? /*LT*/ -1 : /*EQ*/ 0);
}

var _Utils_lt = F2(function(a, b) { return _Utils_cmp(a, b) < 0; });
var _Utils_le = F2(function(a, b) { return _Utils_cmp(a, b) < 1; });
var _Utils_gt = F2(function(a, b) { return _Utils_cmp(a, b) > 0; });
var _Utils_ge = F2(function(a, b) { return _Utils_cmp(a, b) >= 0; });

var _Utils_compare = F2(function(x, y)
{
	var n = _Utils_cmp(x, y);
	return n < 0 ? _Basics_LT : n ? _Basics_GT : _Basics_EQ;
});


// COMMON VALUES

var _Utils_Tuple0 = __canopy_debug ? { $: '#0' } : 0;

function _Utils_Tuple2(a, b) { return __canopy_debug ? { $: '#2', a: a, b: b } : { a: a, b: b }; }

function _Utils_Tuple3(a, b, c) { return __canopy_debug ? { $: '#3', a: a, b: b, c: c } : { a: a, b: b, c: c }; }

function _Utils_chr(c) { return __canopy_debug ? new String(c) : c; }


// RECORDS

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

var _Utils_append = F2(_Utils_ap);

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


var _List_Nil = __canopy_debug ? { $: '[]' } : { $: 0 };

function _List_Cons(hd, tl) { return __canopy_debug ? { $: '::', a: hd, b: tl } : { $: 1, a: hd, b: tl }; }

var _List_cons = F2(_List_Cons);

function _List_fromArray(arr)
{
	var out = _List_Nil;
	for (var i = arr.length; i--; )
	{
		out = _List_Cons(arr[i], out);
	}
	return out;
}

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

var _Basics_LT = __canopy_debug ? { $: 'LT' } : 0;
var _Basics_EQ = __canopy_debug ? { $: 'EQ' } : 1;
var _Basics_GT = __canopy_debug ? { $: 'GT' } : 2;

// Math operators — curried wrappers for partially-applied uses
var _Basics_add = F2(function(a, b) { return a + b; });
var _Basics_sub = F2(function(a, b) { return a - b; });
var _Basics_mul = F2(function(a, b) { return a * b; });
var _Basics_fdiv = F2(function(a, b) { return a / b; });
var _Basics_idiv = F2(function(a, b) { return (a / b) | 0; });
var _Basics_pow = F2(Math.pow);

var _Basics_remainderBy = F2(function(b, a) { return a % b; });

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

var _Basics_pi = Math.PI;
var _Basics_e = Math.E;
var _Basics_cos = Math.cos;
var _Basics_sin = Math.sin;
var _Basics_tan = Math.tan;
var _Basics_acos = Math.acos;
var _Basics_asin = Math.asin;
var _Basics_atan = Math.atan;
var _Basics_atan2 = F2(Math.atan2);

function _Basics_toFloat(x) { return x; }
function _Basics_truncate(n) { return n | 0; }
function _Basics_isInfinite(n) { return n === Infinity || n === -Infinity; }

var _Basics_ceiling = Math.ceil;
var _Basics_floor = Math.floor;
var _Basics_round = Math.round;
var _Basics_sqrt = Math.sqrt;
var _Basics_log = Math.log;
var _Basics_isNaN = isNaN;

function _Basics_not(bool) { return !bool; }
var _Basics_and = F2(function(a, b) { return a && b; });
var _Basics_or  = F2(function(a, b) { return a || b; });
var _Basics_xor = F2(function(a, b) { return a !== b; });


// ============================================================
// DEBUG (code generator primitives)
// ============================================================


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

function _Debug_todo(moduleName, region)
{
	return function(message) {
		_Debug_crash(8, moduleName, region, message);
	};
}

function _Debug_todoCase(moduleName, region, value)
{
	return function(message) {
		_Debug_crash(9, moduleName, region, value, message);
	};
}

var _Debug_toString = __canopy_debug
	? function(value) { return _Debug_toAnsiString(false, value); }
	: function(value) { return '<internals>'; };

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
		return s.replace(/\"/g, '\\"');
	}
}

function _Debug_ctorColor(ansi, string)
{
	return ansi ? '\x1b[96m' + string + '\x1b[0m' : string;
}

function _Debug_numberColor(ansi, string)
{
	return ansi ? '\x1b[95m' + string + '\x1b[0m' : string;
}

function _Debug_stringColor(ansi, string)
{
	return ansi ? '\x1b[93m' + string + '\x1b[0m' : string;
}

function _Debug_charColor(ansi, string)
{
	return ansi ? '\x1b[92m' + string + '\x1b[0m' : string;
}

function _Debug_fadeColor(ansi, string)
{
	return ansi ? '\x1b[37m' + string + '\x1b[0m' : string;
}

function _Debug_internalColor(ansi, string)
{
	return ansi ? '\x1b[36m' + string + '\x1b[0m' : string;
}

function _Debug_toHexDigit(n)
{
	return String.fromCharCode(n < 10 ? 48 + n : 55 + n);
}

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

function _Debug_regionToString(region)
{
	if (region.__$start.__$line === region.__$end.__$line)
	{
		return 'on line ' + region.__$start.__$line;
	}
	return 'on lines ' + region.__$start.__$line + ' through ' + region.__$end.__$line;
}


// ============================================================
// PROCESS (timer-based sleep)
// ============================================================


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
var _Scheduler_SUCCEED  = 0;
var _Scheduler_FAIL     = 1;
var _Scheduler_BINDING  = 2;
var _Scheduler_AND_THEN = 3;
var _Scheduler_ON_ERROR = 4;
var _Scheduler_RECEIVE  = 5;


// TASKS

function _Scheduler_succeed(value)
{
	return {
		$: _Scheduler_SUCCEED,
		__value: value
	};
}

function _Scheduler_fail(error)
{
	return {
		$: _Scheduler_FAIL,
		__value: error
	};
}

function _Scheduler_binding(callback)
{
	return {
		$: _Scheduler_BINDING,
		__callback: callback,
		__kill: null
	};
}

var _Scheduler_andThen = F2(function(callback, task)
{
	return {
		$: _Scheduler_AND_THEN,
		__callback: callback,
		__task: task
	};
});

var _Scheduler_onError = F2(function(callback, task)
{
	return {
		$: _Scheduler_ON_ERROR,
		__callback: callback,
		__task: task
	};
});

function _Scheduler_receive(callback)
{
	return {
		$: _Scheduler_RECEIVE,
		__callback: callback
	};
}


// PROCESSES

var _Scheduler_guid = 0;

function _Scheduler_rawSpawn(task)
{
	var proc = {
		$: 0,
		__id: _Scheduler_guid++,
		__root: task,
		__stack: null,
		__mailbox: []
	};

	_Scheduler_enqueue(proc);

	return proc;
}

function _Scheduler_spawn(task)
{
	return _Scheduler_binding(function(callback) {
		callback(_Scheduler_succeed(_Scheduler_rawSpawn(task)));
	});
}

function _Scheduler_rawSend(proc, msg)
{
	proc.__mailbox.push(msg);
	_Scheduler_enqueue(proc);
}

var _Scheduler_send = F2(function(proc, msg)
{
	return _Scheduler_binding(function(callback) {
		_Scheduler_rawSend(proc, msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});

function _Scheduler_kill(proc)
{
	return _Scheduler_binding(function(callback) {
		var task = proc.__root;
		if (task.$ === _Scheduler_BINDING && task.__kill)
		{
			task.__kill();
		}

		proc.__root = null;

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


var _Scheduler_working = false;
var _Scheduler_queue = [];


function _Scheduler_enqueue(proc)
{
	_Scheduler_queue.push(proc);
	if (_Scheduler_working)
	{
		return;
	}
	_Scheduler_working = true;
	while (proc = _Scheduler_queue.shift())
	{
		_Scheduler_step(proc);
	}
	_Scheduler_working = false;
}


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
var _Platform_SELF = 0;
var _Platform_LEAF = 1;
var _Platform_NODE = 2;
var _Platform_MAP  = 3;


// PROGRAMS


var _Platform_worker = F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.__$init,
		impl.__$update,
		impl.__$subscriptions,
		function() { return function() {} }
	);
});



// INITIALIZE A PROGRAM


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


var _Platform_preload;


function _Platform_registerPreload(url)
{
	_Platform_preload.add(url);
}



// EFFECT MANAGERS


var _Platform_effectManagers = {};


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


var _Platform_sendToApp = F2(function(router, msg)
{
	return _Scheduler_binding(function(callback)
	{
		router.__sendToApp(msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});


var _Platform_sendToSelf = F2(function(router, msg)
{
	return A2(_Scheduler_send, router.__selfProcess, {
		$: _Platform_SELF,
		a: msg
	});
});



// BAGS


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


function _Platform_batch(list)
{
	return {
		$: _Platform_NODE,
		__bags: list
	};
}


var _Platform_map = F2(function(tagger, bag)
{
	return {
		$: _Platform_MAP,
		__func: tagger,
		__bag: bag
	}
});



// PIPE BAGS INTO EFFECT MANAGERS

var _Platform_effectsQueue = [];
var _Platform_effectsActive = false;


function _Platform_enqueueEffects(managers, cmdBag, subBag)
{
	_Platform_effectsQueue.push({ __managers: managers, __cmdBag: cmdBag, __subBag: subBag });

	if (_Platform_effectsActive) return;

	_Platform_effectsActive = true;
	for (var fx; fx = _Platform_effectsQueue.shift(); )
	{
		_Platform_dispatchEffects(fx.__managers, fx.__cmdBag, fx.__subBag);
	}
	_Platform_effectsActive = false;
}


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


function _Platform_insert(isCmd, newEffect, effects)
{
	effects = effects || { __cmds: _List_Nil, __subs: _List_Nil };

	isCmd
		? (effects.__cmds = _List_Cons(newEffect, effects.__cmds))
		: (effects.__subs = _List_Cons(newEffect, effects.__subs));

	return effects;
}



// PORTS


function _Platform_checkPortName(name)
{
	if (_Platform_effectManagers[name])
	{
		_Debug_crash(3, name)
	}
}



// OUTGOING PORTS


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


var _Platform_outgoingPortMap = F2(function(tagger, value) { return value; });


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


var _Platform_incomingPortMap = F2(function(tagger, finalTagger)
{
	return function(value)
	{
		return tagger(finalTagger(value));
	};
});


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

// ============================================================
// End Canopy Runtime
// ============================================================

|]

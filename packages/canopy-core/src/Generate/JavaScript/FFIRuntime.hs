{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Embedded FFI Runtime for Canopy
--
-- This module provides the FFI runtime helpers that are embedded directly
-- into compiled JavaScript output. This eliminates the need for external
-- npm dependencies like @canopy/ffi-runtime.
--
-- = Embedded Modules
--
-- * @$canopy@ - Type-safe constructors for Canopy ADTs (Ok, Err, Just, Nothing, toList, etc.)
-- * @$validate@ - Runtime type validators for FFI boundaries
-- * @$smart@ - Smart validation with coercion detection
-- * @$env@ - Environment and capability detection
--
-- = Usage
--
-- The runtime is automatically included in every compiled output.
-- JavaScript FFI code can use these helpers directly:
--
-- @
-- // In external/audio.js
-- function createContext() {
--   try {
--     const ctx = new AudioContext();
--     return $canopy.Ok(ctx);
--   } catch (e) {
--     return $canopy.Err(e.message);
--   }
-- }
-- @
--
-- = Size
--
-- The embedded runtime adds approximately:
-- * Unminified: ~8KB
-- * Minified: ~3.2KB
-- * Gzipped: ~1.6KB
--
-- @since 0.20.0
module Generate.JavaScript.FFIRuntime
  ( -- * Full runtime
    embeddedRuntime

    -- * Individual modules
  , embeddedMarshal
  , embeddedValidate
  , embeddedSmart
  , embeddedEnvironment

    -- * Conditional inclusion
  , embeddedRuntimeForMode

    -- * Minimal validators for unsafe mode
  , embeddedValidateMinimal

    -- * Scan-based inclusion
  , scanAndEmitRuntime
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Generate.Mode as Mode
import Text.RawString.QQ (r)

-- | Full embedded FFI runtime.
--
-- Includes all modules: $canopy, $validate, $smart, $env.
-- This is included in every compiled output.
embeddedRuntime :: Builder
embeddedRuntime =
  runtimeHeader
    <> embeddedMarshal
    <> embeddedValidate
    <> embeddedSmart
    <> embeddedEnvironment
    <> runtimeFooter

-- | Runtime header comment
runtimeHeader :: Builder
runtimeHeader = BB.stringUtf8 [r|

// ============================================================
// Canopy FFI Runtime (embedded - no npm install required)
// ============================================================

|]

-- | Runtime footer
runtimeFooter :: Builder
runtimeFooter = BB.stringUtf8 [r|

// ============================================================
// End Canopy FFI Runtime
// ============================================================

|]

-- | Conditional runtime based on compilation mode.
--
-- By default, FFI validation is enabled. Use --ffi-unsafe to disable.
-- - ffiUnsafe=False (default): Include full runtime with smart validation
-- - ffiUnsafe=True (--ffi-unsafe): Include minimal runtime without validation
embeddedRuntimeForMode :: Mode.Mode -> Builder
embeddedRuntimeForMode mode =
  case mode of
    Mode.Dev _ _ False _ _ _ ->  -- ffiUnsafe=False, validation ENABLED (default)
      embeddedRuntime
    Mode.Dev _ _ True _ _ _ ->  -- ffiUnsafe=True, minimal validation
      embeddedMarshal <> embeddedValidateMinimal <> embeddedEnvironment
    Mode.Prod _ _ False _ _ _ ->  -- ffiUnsafe=False, validation ENABLED (default)
      embeddedRuntime
    Mode.Prod _ _ True _ _ _ ->  -- ffiUnsafe=True, minimal validation
      embeddedMarshal <> embeddedValidateMinimal

-- | Scan-based FFI runtime inclusion.
--
-- Scans the generated FFI + app content for references to @$canopy.@,
-- @$validate.@, @$smart.@, and @$env.@ and only emits the runtime
-- modules that are actually used. This avoids shipping ~16KB of unused
-- runtime for apps that don't need validation or environment detection.
scanAndEmitRuntime :: Mode.Mode -> Builder -> Builder
scanAndEmitRuntime mode contentBuilder =
  runtimeHeader <> modules <> runtimeFooter
  where
    content = materializeBuilder contentBuilder
    needsCanopy = BS.isInfixOf "$canopy." content
    needsValidate = BS.isInfixOf "$validate." content
    needsSmart = BS.isInfixOf "$smart." content
    needsEnv = BS.isInfixOf "$env." content
    modules =
      (if needsCanopy then embeddedMarshal else mempty)
        <> conditionalValidate needsValidate
        <> conditionalSmart needsSmart
        <> conditionalEnv needsEnv
    conditionalValidate needed = case mode of
      Mode.Dev _ _ False _ _ _ -> if needed then embeddedValidate else mempty
      Mode.Prod _ _ False _ _ _ -> if needed then embeddedValidate else mempty
      _ -> mempty
    conditionalSmart needed = case mode of
      Mode.Dev _ _ False _ _ _ -> if needed then embeddedSmart else mempty
      Mode.Prod _ _ False _ _ _ -> if needed then embeddedSmart else mempty
      _ -> mempty
    conditionalEnv needed = case mode of
      Mode.Dev _ _ _ _ _ _ -> if needed then embeddedEnvironment else mempty
      _ -> mempty

-- | Materialize a 'Builder' to a strict 'ByteString' for scanning.
materializeBuilder :: Builder -> ByteString
materializeBuilder = BL.toStrict . BB.toLazyByteString

-- | Marshalling helpers ($canopy)
--
-- Type-safe constructors for Canopy algebraic data types.
-- Eliminates manual construction of @{$:'Ok',a:v}@ objects.
embeddedMarshal :: Builder
embeddedMarshal = BB.stringUtf8 [r|
// $canopy - Type marshalling helpers
var $canopy = {
  // Result constructors
  /** @canopy-type a -> Result x a */
  Ok: function(a) { return { $: 'Ok', a: a }; },
  /** @canopy-type x -> Result x a */
  Err: function(a) { return { $: 'Err', a: a }; },

  // Maybe constructors
  /** @canopy-type a -> Maybe a */
  Just: function(a) { return { $: 'Just', a: a }; },
  /** @canopy-type Maybe a */
  Nothing: Object.freeze({ $: 'Nothing' }),

  // Convert nullable to Maybe
  /** @canopy-type a -> Maybe a */
  fromNullable: function(v) {
    return v == null ? { $: 'Nothing' } : { $: 'Just', a: v };
  },

  // List conversion (Array <-> Canopy List)
  /** @canopy-type Array a -> List a */
  toList: function(arr) {
    var r = { $: '[]' };
    for (var i = arr.length - 1; i >= 0; i--) {
      r = { $: '::', a: arr[i], b: r };
    }
    return r;
  },

  /** @canopy-type List a -> Array a */
  fromList: function(l) {
    var r = [];
    while (l && l.$ === '::') {
      r.push(l.a);
      l = l.b;
    }
    return r;
  },

  // Map over a Canopy List
  /** @canopy-type (a -> b) -> List a -> List b */
  mapList: function(f, l) {
    var arr = [];
    while (l && l.$ === '::') {
      arr.push(f(l.a));
      l = l.b;
    }
    var r = { $: '[]' };
    for (var i = arr.length - 1; i >= 0; i--) {
      r = { $: '::', a: arr[i], b: r };
    }
    return r;
  },

  // Task/Promise helpers
  /** @canopy-type a -> Task x (Result x a) */
  taskOk: function(a) {
    return Promise.resolve({ $: 'Ok', a: a });
  },

  /** @canopy-type x -> Task x (Result x a) */
  taskErr: function(a) {
    return Promise.resolve({ $: 'Err', a: String(a) });
  },

  /** @canopy-type Promise a -> Task String (Result String a) */
  wrapPromise: function(p) {
    return p.then(
      function(a) { return { $: 'Ok', a: a }; },
      function(e) { return { $: 'Err', a: String(e) }; }
    );
  },

  // Initialized state wrappers
  /** @canopy-type a -> InitState a */
  Fresh: function(a) { return { $: 'Fresh', a: a }; },
  /** @canopy-type a -> InitState a */
  Running: function(a) { return { $: 'Running', a: a }; },
  /** @canopy-type a -> InitState a */
  Suspended: function(a) { return { $: 'Suspended', a: a }; },
  /** @canopy-type a -> InitState a */
  Closed: function(a) { return { $: 'Closed', a: a }; },

  // Tuple helpers
  /** @canopy-type a -> b -> ( a, b ) */
  tuple2: function(a, b) { return { a: a, b: b }; },
  /** @canopy-type a -> b -> c -> ( a, b, c ) */
  tuple3: function(a, b, c) { return { a: a, b: b, c: c }; },

  // Unwrap helpers
  /** @canopy-type { a : a } -> a */
  unwrap: function(w) { return w.a; },
  /** @canopy-type Result x a -> Maybe a */
  unwrapOk: function(r) { return r.$ === 'Ok' ? r.a : null; },
  /** @canopy-type Maybe a -> Maybe a */
  unwrapJust: function(m) { return m.$ === 'Just' ? m.a : null; },

  // Type checks
  /** @canopy-type Result x a -> Bool */
  isOk: function(r) { return r.$ === 'Ok'; },
  /** @canopy-type Result x a -> Bool */
  isErr: function(r) { return r.$ === 'Err'; },
  /** @canopy-type Maybe a -> Bool */
  isJust: function(m) { return m.$ === 'Just'; },
  /** @canopy-type Maybe a -> Bool */
  isNothing: function(m) { return m.$ === 'Nothing'; }
};

|]

-- | Type validators ($validate)
--
-- Runtime type checking at FFI boundaries.
-- Used when --ffi-strict is enabled.
embeddedValidate :: Builder
embeddedValidate = BB.stringUtf8 [r|
// $validate - Runtime type validators
var $validate = {
  // Primitive validators
  /** @canopy-type a -> String -> Int */
  Int: function(v, p) {
    if (typeof v !== 'number') {
      throw new Error('FFI type error at ' + p + ': expected Int, got ' + typeof v);
    }
    if (!Number.isInteger(v)) {
      throw new Error('FFI type error at ' + p + ': expected Int, got Float (' + v + ')');
    }
    if (v < -9007199254740991 || v > 9007199254740991) {
      throw new Error('FFI type error at ' + p + ': integer overflow');
    }
    return v;
  },

  /** @canopy-type a -> String -> Float */
  Float: function(v, p) {
    if (typeof v !== 'number') {
      throw new Error('FFI type error at ' + p + ': expected Float, got ' + typeof v);
    }
    if (!Number.isFinite(v)) {
      throw new Error('FFI type error at ' + p + ': expected finite Float, got ' + v);
    }
    return v;
  },

  /** @canopy-type a -> String -> String */
  String: function(v, p) {
    if (typeof v !== 'string') {
      throw new Error('FFI type error at ' + p + ': expected String, got ' + typeof v);
    }
    return v;
  },

  /** @canopy-type a -> String -> Bool */
  Bool: function(v, p) {
    if (typeof v !== 'boolean') {
      throw new Error('FFI type error at ' + p + ': expected Bool, got ' + typeof v);
    }
    return v;
  },

  // Composite validators
  /** @canopy-type (a -> String -> b) -> a -> String -> List b */
  List: function(f) {
    return function(v, p) {
      // If already a Canopy linked list (returned by internal FFI like List.cons),
      // pass through directly without conversion.
      // Debug builds use string tags ('[]', '::'); optimized builds use numeric (0, 1).
      if (typeof v === 'object' && v !== null && (v.$ === '[]' || v.$ === '::' || v.$ === 0 || v.$ === 1)) {
        return v;
      }
      if (!Array.isArray(v)) {
        throw new Error('FFI type error at ' + p + ': expected Array, got ' + typeof v);
      }
      var validated = v.map(function(e, i) { return f(e, p + '[' + i + ']'); });
      var list = { $: '[]' };
      for (var i = validated.length - 1; i >= 0; i--) {
        list = { $: '::', a: validated[i], b: list };
      }
      return list;
    };
  },

  /** @canopy-type (a -> String -> b) -> a -> String -> Maybe b */
  Maybe: function(f) {
    return function(v, p) {
      // Canopy ADT Maybe (DEV mode: string tags, PROD mode: integer tags)
      if (typeof v === 'object' && v !== null && '$' in v) {
        if (v.$ === 'Nothing' || v.$ === 0) { return v; }
        if (v.$ === 'Just' || v.$ === 1) { return { $: v.$, a: f(v.a, p) }; }
      }
      // JS-native nullable: null/undefined -> Nothing, value -> Just
      if (v == null) { return { $: 'Nothing' }; }
      return { $: 'Just', a: f(v, p) };
    };
  },

  /** @canopy-type (a -> String -> x) -> (a -> String -> b) -> a -> String -> Result x b */
  Result: function(errV, okV) {
    return function(v, p) {
      if (typeof v !== 'object' || v === null || !Object.prototype.hasOwnProperty.call(v, '$')) {
        throw new Error('FFI type error at ' + p + ': expected Result object with $ tag');
      }
      if (v.$ === 'Ok') {
        return { $: 'Ok', a: okV(v.a, p + '.Ok') };
      }
      if (v.$ === 'Err') {
        return { $: 'Err', a: errV(v.a, p + '.Err') };
      }
      throw new Error('FFI type error at ' + p + ': invalid Result tag: ' + v.$);
    };
  },

  /** @canopy-type (a -> String -> x) -> (a -> String -> b) -> a -> String -> Task x b */
  Task: function(errV, okV) {
    return function(v, p) {
      // Already a Canopy scheduler task (numeric $ tag: 0=SUCCEED, 1=FAIL, 2=BINDING, etc.).
      // Pass through unchanged — the scheduler protocol handles it directly.
      if (typeof v === 'object' && v !== null && typeof v.$ === 'number') {
        return v;
      }
      // Native Promise: wrap into a Canopy BINDING task using the correct scheduler
      // field names (__callback, __kill, __value) as defined in runtime.js.
      if (typeof v === 'object' && v !== null && typeof v.then === 'function') {
        return {
          $: 2,
          __callback: function(callback) {
            v.then(
              function(ok) {
                try { callback({ $: 0, __value: okV(ok, p + '.then') }); }
                catch (e) { callback({ $: 1, __value: errV(String(e), p + '.validation') }); }
              },
              function(err) {
                try { callback({ $: 1, __value: errV(err, p + '.catch') }); }
                catch (e) { callback({ $: 1, __value: String(e) }); }
              }
            );
            return null;
          },
          __kill: null
        };
      }
      throw new Error('FFI type error at ' + p + ': expected Task or Promise');
    };
  },

  /** @canopy-type List (a -> String -> b) -> a -> String -> tuple */
  Tuple: function() {
    var validators = Array.prototype.slice.call(arguments);
    return function(v, p) {
      if (!Array.isArray(v)) {
        throw new Error('FFI type error at ' + p + ': expected Tuple (Array)');
      }
      if (v.length !== validators.length) {
        throw new Error('FFI type error at ' + p + ': expected Tuple of ' + validators.length + ' elements, got ' + v.length);
      }
      var validated = validators.map(function(f, i) { return f(v[i], p + '[' + i + ']'); });
      if (validated.length === 2) { return { a: validated[0], b: validated[1] }; }
      if (validated.length === 3) { return { a: validated[0], b: validated[1], c: validated[2] }; }
      return validated;
    };
  },

  // Record validator (field presence + type checking)
  /** @canopy-type List (String, Validator) -> a -> String -> a */
  Record: function(fields) {
    return function(v, p) {
      if (typeof v !== 'object' || v === null || Array.isArray(v)) {
        throw new Error('FFI type error at ' + p + ': expected Record, got ' + (v === null ? 'null' : typeof v));
      }
      for (var i = 0; i < fields.length; i++) {
        var name = fields[i][0];
        var validator = fields[i][1];
        if (!Object.prototype.hasOwnProperty.call(v, name)) {
          throw new Error('FFI type error at ' + p + ': missing field "' + name + '"');
        }
        validator(v[name], p + '.' + name);
      }
      return v;
    };
  },

  // Opaque type validator (null/undefined + optional instanceof check)
  /** @canopy-type String -> Maybe Constructor -> a -> String -> a */
  Opaque: function(name, ctor) {
    return function(v, p) {
      if (v == null) {
        throw new Error('FFI type error at ' + p + ': expected ' + name + ', got ' + (v === null ? 'null' : 'undefined'));
      }
      if (ctor && !(v instanceof ctor)) {
        throw new Error('FFI type error at ' + p + ': expected ' + name + ' instance');
      }
      return v;
    };
  },

  // Function validator
  /** @canopy-type a -> String -> (a -> b) */
  Function: function(v, p) {
    if (typeof v !== 'function') {
      throw new Error('FFI type error at ' + p + ': expected Function, got ' + typeof v);
    }
    return v;
  },

  // Unit validator (always passes)
  /** @canopy-type a -> String -> () */
  Unit: function(v, p) { return v; },

  // Type variable validator (rejects undefined)
  /** @canopy-type a -> String -> a */
  Any: function(v, p) {
    if (typeof v === 'undefined') {
      throw new Error('FFI type error at ' + p + ': got undefined');
    }
    return v;
  }
};

|]

-- | Smart validation with coercion detection ($smart)
--
-- Detects JavaScript type coercion issues like "5" + 3 = "53".
embeddedSmart :: Builder
embeddedSmart = BB.stringUtf8 [r|
// $smart - Smart validation with coercion detection
var $smart = {
  // Validation level: 'disabled', 'permissive', 'strict', 'smart', 'paranoid'
  /** @canopy-type String */
  level: 'smart',

  /** @canopy-type String -> () */
  setLevel: function(l) { $smart.level = l; },

  // Smart Int validator with coercion detection
  /** @canopy-type a -> String -> Int */
  Int: function(v, p) {
    if ($smart.level === 'disabled') return v;

    // Detect numeric string coercion
    if (typeof v === 'string') {
      var n = Number(v);
      if (!isNaN(n)) {
        var msg = 'FFI coercion at ' + p + ': string "' + v + '" would coerce to ' + n;
        if ($smart.level === 'permissive') {
          console.warn(msg + '. Use parseInt() explicitly.');
          return Math.floor(n);
        }
        throw new Error(msg + '. Use parseInt() explicitly.');
      }
    }

    // Detect NaN from failed coercion
    if (typeof v === 'number' && Number.isNaN(v)) {
      throw new Error('FFI coercion error at ' + p + ': got NaN (invalid coercion)');
    }

    return $validate.Int(v, p);
  },

  // Smart Float validator
  /** @canopy-type a -> String -> Float */
  Float: function(v, p) {
    if ($smart.level === 'disabled') return v;

    if (typeof v === 'string') {
      var n = Number(v);
      if (!isNaN(n)) {
        var msg = 'FFI coercion at ' + p + ': string "' + v + '" would coerce to ' + n;
        if ($smart.level === 'permissive') {
          console.warn(msg + '. Use parseFloat() explicitly.');
          return n;
        }
        throw new Error(msg + '. Use parseFloat() explicitly.');
      }
    }

    if (typeof v === 'number' && !Number.isFinite(v)) {
      var msg = 'FFI constraint at ' + p + ': got ' + (Number.isNaN(v) ? 'NaN' : (v > 0 ? 'Infinity' : '-Infinity'));
      if ($smart.level === 'permissive') {
        console.warn(msg);
        return v;
      }
      throw new Error(msg);
    }

    return $validate.Float(v, p);
  },

  // Smart String validator
  /** @canopy-type a -> String -> String */
  String: function(v, p) {
    if ($smart.level === 'disabled') return v;

    if (typeof v === 'number') {
      var msg = 'FFI coercion at ' + p + ': number ' + v + ' would coerce to string';
      if ($smart.level === 'permissive') {
        console.warn(msg + '. Use String() explicitly.');
        return String(v);
      }
      throw new Error(msg + '. Use String() explicitly.');
    }

    return $validate.String(v, p);
  },

  // Detect coercion in binary operations
  /** @canopy-type String -> a -> a -> a -> String -> () */
  detectCoercion: function(op, a, b, result, p) {
    if ($smart.level === 'disabled') return;

    // Detect string concatenation when addition was intended
    if (op === '+' && typeof result === 'string') {
      if (typeof a === 'number' || typeof b === 'number') {
        var msg = 'FFI coercion at ' + p + ': ' + JSON.stringify(a) + ' + ' + JSON.stringify(b) + ' = "' + result + '"';
        if ($smart.level === 'permissive') {
          console.warn(msg + ' (string concat instead of addition)');
        } else {
          throw new Error(msg + ' - possible unintended string concatenation');
        }
      }
    }

    // Detect NaN result
    if (typeof result === 'number' && Number.isNaN(result)) {
      var msg = 'FFI coercion at ' + p + ': ' + a + ' ' + op + ' ' + b + ' = NaN';
      if ($smart.level === 'permissive') {
        console.warn(msg);
      } else {
        throw new Error(msg);
      }
    }
  }
};

|]

-- | Environment and capability detection ($env)
--
-- Detects runtime environment and checks for browser capabilities.
embeddedEnvironment :: Builder
embeddedEnvironment = BB.stringUtf8 [r|
// $env - Environment and capability detection
var $env = {
  // Runtime detection
  /** @canopy-type Bool */
  isBrowser: typeof window !== 'undefined' && typeof document !== 'undefined',
  /** @canopy-type Bool */
  isNode: typeof process !== 'undefined' && process.versions && process.versions.node != null,
  /** @canopy-type Bool */
  isDeno: typeof Deno !== 'undefined',
  /** @canopy-type Bool */
  isBun: typeof Bun !== 'undefined',
  /** @canopy-type Bool */
  isWebWorker: typeof self !== 'undefined' && typeof importScripts === 'function' && typeof window === 'undefined',

  /** @canopy-type () -> String */
  getRuntime: function() {
    if ($env.isBun) return 'bun';
    if ($env.isDeno) return 'deno';
    if ($env.isNode) return 'node';
    if ($env.isWebWorker) return 'worker';
    if ($env.isBrowser) return 'browser';
    return 'unknown';
  },

  // Security context
  /** @canopy-type () -> Bool */
  isSecureContext: function() {
    if (typeof window !== 'undefined' && window.isSecureContext !== undefined) {
      return window.isSecureContext;
    }
    return true; // Non-browser assumed secure
  },

  // User activation (required for audio, fullscreen, clipboard, etc.)
  /** @canopy-type () -> Bool */
  hasUserActivation: function() {
    if (typeof navigator !== 'undefined' && navigator.userActivation) {
      return navigator.userActivation.isActive;
    }
    return true; // Non-browser: assume available
  },

  /** @canopy-type () -> Bool */
  hasBeenActivated: function() {
    if (typeof navigator !== 'undefined' && navigator.userActivation) {
      return navigator.userActivation.hasBeenActive;
    }
    return true;
  },

  // API availability checks
  /** @canopy-type () -> Bool */
  hasAudioContext: function() {
    return typeof AudioContext !== 'undefined' || typeof webkitAudioContext !== 'undefined';
  },

  /** @canopy-type () -> Bool */
  hasWebGL: function() {
    if (typeof document === 'undefined') return false;
    try {
      var c = document.createElement('canvas');
      return !!(c.getContext('webgl') || c.getContext('experimental-webgl'));
    } catch (e) { return false; }
  },

  /** @canopy-type () -> Bool */
  hasWebGL2: function() {
    if (typeof document === 'undefined') return false;
    try {
      return !!document.createElement('canvas').getContext('webgl2');
    } catch (e) { return false; }
  },

  /** @canopy-type () -> Bool */
  hasWebGPU: function() {
    return typeof navigator !== 'undefined' && 'gpu' in navigator;
  },

  /** @canopy-type () -> Bool */
  hasServiceWorker: function() {
    return typeof navigator !== 'undefined' && 'serviceWorker' in navigator;
  },

  /** @canopy-type () -> Bool */
  hasClipboard: function() {
    return typeof navigator !== 'undefined' && 'clipboard' in navigator;
  },

  /** @canopy-type () -> Bool */
  hasGeolocation: function() {
    return typeof navigator !== 'undefined' && 'geolocation' in navigator;
  },

  /** @canopy-type () -> Bool */
  hasNotifications: function() {
    return typeof Notification !== 'undefined';
  },

  /** @canopy-type () -> Bool */
  hasMediaDevices: function() {
    return typeof navigator !== 'undefined' && navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function';
  },

  /** @canopy-type () -> Bool */
  hasWebCrypto: function() {
    return typeof crypto !== 'undefined' && crypto.subtle;
  },

  /** @canopy-type () -> Bool */
  hasIndexedDB: function() {
    return typeof indexedDB !== 'undefined';
  },

  /** @canopy-type () -> Bool */
  hasLocalStorage: function() {
    try { return typeof localStorage !== 'undefined' && localStorage !== null; }
    catch (e) { return false; }
  },

  // Permission queries
  /** @canopy-type String -> Task x String */
  queryPermission: function(name) {
    if (typeof navigator === 'undefined' || !navigator.permissions) {
      return Promise.resolve('unavailable');
    }
    return navigator.permissions.query({ name: name })
      .then(function(r) { return r.state; })
      .catch(function() { return 'unavailable'; });
  },

  /** @canopy-type () -> String */
  getNotificationPermission: function() {
    if (typeof Notification === 'undefined') return 'unavailable';
    return Notification.permission;
  }
};

|]

-- | Minimal validators for --ffi-unsafe mode.
--
-- Only includes primitive type checks (Int, Float, String, Bool, Unit)
-- to catch the most common FFI type errors. Composite types (List, Maybe,
-- Result, Task, Record, Opaque) become passthroughs, preserving the
-- performance benefit of unsafe mode while catching trivial type mismatches.
--
-- @since 0.20.0
embeddedValidateMinimal :: Builder
embeddedValidateMinimal = BB.stringUtf8 [r|
// $validate - Minimal validators (--ffi-unsafe mode)
var $validate = {
  Int: function(v, p) {
    if (typeof v !== 'number') {
      throw new Error('FFI type error at ' + p + ': expected Int, got ' + typeof v);
    }
    if (!Number.isInteger(v)) {
      throw new Error('FFI type error at ' + p + ': expected Int, got Float (' + v + ')');
    }
    return v;
  },
  Float: function(v, p) {
    if (typeof v !== 'number') {
      throw new Error('FFI type error at ' + p + ': expected Float, got ' + typeof v);
    }
    if (!Number.isFinite(v)) {
      throw new Error('FFI type error at ' + p + ': expected finite Float, got ' + v);
    }
    return v;
  },
  String: function(v, p) {
    if (typeof v !== 'string') {
      throw new Error('FFI type error at ' + p + ': expected String, got ' + typeof v);
    }
    return v;
  },
  Bool: function(v, p) {
    if (typeof v !== 'boolean') {
      throw new Error('FFI type error at ' + p + ': expected Bool, got ' + typeof v);
    }
    return v;
  },
  Unit: function(v, p) { return v; },
  List: function(f) { return function(v, p) { return v; }; },
  Maybe: function(f) { return function(v, p) { return v; }; },
  Result: function(e, o) { return function(v, p) { return v; }; },
  Task: function(e, o) { return function(v, p) { return v; }; },
  Tuple: function() { return function(v, p) { return v; }; },
  Record: function(f) { return function(v, p) { return v; }; },
  Opaque: function(n, c) { return function(v, p) { return v; }; },
  Function: function(v, p) { return v; },
  Any: function(v, p) { return v; }
};

|]

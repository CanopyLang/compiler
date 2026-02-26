{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -Wall #-}

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
  ) where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
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
runtimeHeader = B.stringUtf8 [r|

// ============================================================
// Canopy FFI Runtime (embedded - no npm install required)
// ============================================================

|]

-- | Runtime footer
runtimeFooter :: Builder
runtimeFooter = B.stringUtf8 [r|

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
    Mode.Dev _ _ False _ ->  -- ffiUnsafe=False, validation ENABLED (default)
      embeddedRuntime
    Mode.Dev _ _ True _ ->  -- ffiUnsafe=True, validation DISABLED
      embeddedMarshal <> embeddedEnvironment  -- Basic runtime in dev
    Mode.Prod _ _ False _ _ ->  -- ffiUnsafe=False, validation ENABLED (default)
      embeddedRuntime
    Mode.Prod _ _ True _ _ ->  -- ffiUnsafe=True, validation DISABLED
      embeddedMarshal  -- Minimal runtime in prod

-- | Marshalling helpers ($canopy)
--
-- Type-safe constructors for Canopy algebraic data types.
-- Eliminates manual construction of @{$:'Ok',a:v}@ objects.
embeddedMarshal :: Builder
embeddedMarshal = B.stringUtf8 [r|
// $canopy - Type marshalling helpers
var $canopy = {
  // Result constructors
  Ok: function(a) { return { $: 'Ok', a: a }; },
  Err: function(a) { return { $: 'Err', a: a }; },

  // Maybe constructors
  Just: function(a) { return { $: 'Just', a: a }; },
  Nothing: Object.freeze({ $: 'Nothing' }),

  // Convert nullable to Maybe
  fromNullable: function(v) {
    return v == null ? { $: 'Nothing' } : { $: 'Just', a: v };
  },

  // List conversion (Array <-> Canopy List)
  toList: function(arr) {
    var r = { $: '[]' };
    for (var i = arr.length - 1; i >= 0; i--) {
      r = { $: '::', a: arr[i], b: r };
    }
    return r;
  },

  fromList: function(l) {
    var r = [];
    while (l && l.$ === '::') {
      r.push(l.a);
      l = l.b;
    }
    return r;
  },

  // Map over a Canopy List
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
  taskOk: function(a) {
    return Promise.resolve({ $: 'Ok', a: a });
  },

  taskErr: function(a) {
    return Promise.resolve({ $: 'Err', a: String(a) });
  },

  wrapPromise: function(p) {
    return p.then(
      function(a) { return { $: 'Ok', a: a }; },
      function(e) { return { $: 'Err', a: String(e) }; }
    );
  },

  // Initialized state wrappers
  Fresh: function(a) { return { $: 'Fresh', a: a }; },
  Running: function(a) { return { $: 'Running', a: a }; },
  Suspended: function(a) { return { $: 'Suspended', a: a }; },
  Closed: function(a) { return { $: 'Closed', a: a }; },

  // Tuple helpers
  tuple2: function(a, b) { return { a: a, b: b }; },
  tuple3: function(a, b, c) { return { a: a, b: b, c: c }; },

  // Unwrap helpers
  unwrap: function(w) { return w.a; },
  unwrapOk: function(r) { return r.$ === 'Ok' ? r.a : null; },
  unwrapJust: function(m) { return m.$ === 'Just' ? m.a : null; },

  // Type checks
  isOk: function(r) { return r.$ === 'Ok'; },
  isErr: function(r) { return r.$ === 'Err'; },
  isJust: function(m) { return m.$ === 'Just'; },
  isNothing: function(m) { return m.$ === 'Nothing'; }
};

|]

-- | Type validators ($validate)
--
-- Runtime type checking at FFI boundaries.
-- Used when --ffi-strict is enabled.
embeddedValidate :: Builder
embeddedValidate = B.stringUtf8 [r|
// $validate - Runtime type validators
var $validate = {
  // Primitive validators
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

  Float: function(v, p) {
    if (typeof v !== 'number') {
      throw new Error('FFI type error at ' + p + ': expected Float, got ' + typeof v);
    }
    if (Number.isNaN(v)) {
      throw new Error('FFI type error at ' + p + ': got NaN');
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

  // Composite validators
  List: function(f) {
    return function(v, p) {
      if (!Array.isArray(v)) {
        throw new Error('FFI type error at ' + p + ': expected Array, got ' + typeof v);
      }
      return v.map(function(e, i) { return f(e, p + '[' + i + ']'); });
    };
  },

  Maybe: function(f) {
    return function(v, p) {
      if (v == null) {
        return { $: 'Nothing' };
      }
      return { $: 'Just', a: f(v, p) };
    };
  },

  Result: function(errV, okV) {
    return function(v, p) {
      if (typeof v !== 'object' || v === null || !('$' in v)) {
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

  Task: function(errV, okV) {
    return function(v, p) {
      if (typeof v !== 'object' || v === null || typeof v.then !== 'function') {
        throw new Error('FFI type error at ' + p + ': expected Promise');
      }
      return {
        $: 2,
        b: function(callback) {
          v.then(
            function(ok) { callback({ $: 0, a: okV(ok, p + '.then') }); },
            function(err) { callback({ $: 1, a: errV(err, p + '.catch') }); }
          );
          return null;
        },
        c: null
      };
    };
  },

  Tuple: function() {
    var validators = Array.prototype.slice.call(arguments);
    return function(v, p) {
      if (!Array.isArray(v)) {
        throw new Error('FFI type error at ' + p + ': expected Tuple (Array)');
      }
      if (v.length !== validators.length) {
        throw new Error('FFI type error at ' + p + ': expected Tuple of ' + validators.length + ' elements, got ' + v.length);
      }
      return validators.map(function(f, i) { return f(v[i], p + '[' + i + ']'); });
    };
  },

  // Opaque type validator (optional instanceof check)
  Opaque: function(name, ctor) {
    return function(v, p) {
      if (ctor && !(v instanceof ctor)) {
        throw new Error('FFI type error at ' + p + ': expected ' + name + ' instance');
      }
      return v;
    };
  },

  // Function validator
  Function: function(v, p) {
    if (typeof v !== 'function') {
      throw new Error('FFI type error at ' + p + ': expected Function, got ' + typeof v);
    }
    return v;
  },

  // Unit validator (always passes)
  Unit: function(v, p) { return v; },

  // Identity validator (for opaque types without checks)
  Any: function(v, p) { return v; }
};

|]

-- | Smart validation with coercion detection ($smart)
--
-- Detects JavaScript type coercion issues like "5" + 3 = "53".
embeddedSmart :: Builder
embeddedSmart = B.stringUtf8 [r|
// $smart - Smart validation with coercion detection
var $smart = {
  // Validation level: 'disabled', 'permissive', 'strict', 'smart', 'paranoid'
  level: 'smart',

  setLevel: function(l) { $smart.level = l; },

  // Smart Int validator with coercion detection
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
      var msg = 'FFI constraint at ' + p + ': got ' + (v > 0 ? 'Infinity' : '-Infinity');
      if ($smart.level === 'permissive') {
        console.warn(msg);
        return v;
      }
      if ($smart.level !== 'paranoid') return v;
      throw new Error(msg);
    }

    return $validate.Float(v, p);
  },

  // Smart String validator
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
embeddedEnvironment = B.stringUtf8 [r|
// $env - Environment and capability detection
var $env = {
  // Runtime detection
  isBrowser: typeof window !== 'undefined' && typeof document !== 'undefined',
  isNode: typeof process !== 'undefined' && process.versions && process.versions.node != null,
  isDeno: typeof Deno !== 'undefined',
  isBun: typeof Bun !== 'undefined',
  isWebWorker: typeof self !== 'undefined' && typeof importScripts === 'function' && typeof window === 'undefined',

  getRuntime: function() {
    if ($env.isBun) return 'bun';
    if ($env.isDeno) return 'deno';
    if ($env.isNode) return 'node';
    if ($env.isWebWorker) return 'worker';
    if ($env.isBrowser) return 'browser';
    return 'unknown';
  },

  // Security context
  isSecureContext: function() {
    if (typeof window !== 'undefined' && window.isSecureContext !== undefined) {
      return window.isSecureContext;
    }
    return true; // Non-browser assumed secure
  },

  // User activation (required for audio, fullscreen, clipboard, etc.)
  hasUserActivation: function() {
    if (typeof navigator !== 'undefined' && navigator.userActivation) {
      return navigator.userActivation.isActive;
    }
    return true; // Non-browser: assume available
  },

  hasBeenActivated: function() {
    if (typeof navigator !== 'undefined' && navigator.userActivation) {
      return navigator.userActivation.hasBeenActive;
    }
    return true;
  },

  // API availability checks
  hasAudioContext: function() {
    return typeof AudioContext !== 'undefined' || typeof webkitAudioContext !== 'undefined';
  },

  hasWebGL: function() {
    if (typeof document === 'undefined') return false;
    try {
      var c = document.createElement('canvas');
      return !!(c.getContext('webgl') || c.getContext('experimental-webgl'));
    } catch (e) { return false; }
  },

  hasWebGL2: function() {
    if (typeof document === 'undefined') return false;
    try {
      return !!document.createElement('canvas').getContext('webgl2');
    } catch (e) { return false; }
  },

  hasWebGPU: function() {
    return typeof navigator !== 'undefined' && 'gpu' in navigator;
  },

  hasServiceWorker: function() {
    return typeof navigator !== 'undefined' && 'serviceWorker' in navigator;
  },

  hasClipboard: function() {
    return typeof navigator !== 'undefined' && 'clipboard' in navigator;
  },

  hasGeolocation: function() {
    return typeof navigator !== 'undefined' && 'geolocation' in navigator;
  },

  hasNotifications: function() {
    return typeof Notification !== 'undefined';
  },

  hasMediaDevices: function() {
    return typeof navigator !== 'undefined' && navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function';
  },

  hasWebCrypto: function() {
    return typeof crypto !== 'undefined' && crypto.subtle;
  },

  hasIndexedDB: function() {
    return typeof indexedDB !== 'undefined';
  },

  hasLocalStorage: function() {
    try { return typeof localStorage !== 'undefined' && localStorage !== null; }
    catch (e) { return false; }
  },

  // Permission queries
  queryPermission: function(name) {
    if (typeof navigator === 'undefined' || !navigator.permissions) {
      return Promise.resolve('unavailable');
    }
    return navigator.permissions.query({ name: name })
      .then(function(r) { return r.state; })
      .catch(function() { return 'unavailable'; });
  },

  getNotificationPermission: function() {
    if (typeof Notification === 'undefined') return 'unavailable';
    return Notification.permission;
  }
};

|]

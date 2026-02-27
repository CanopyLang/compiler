{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Generate.JavaScript.CodeSplit.Runtime — Chunk loader runtime
--
-- Emits the ~40-line JavaScript runtime that supports dynamic chunk loading.
-- The runtime provides three functions:
--
--   * @__canopy_register(id, factory)@ — registers a chunk's factory function
--     so that synchronous resolution works when all chunks are bundled.
--   * @__canopy_load(id)@ — synchronous load if already registered, otherwise
--     creates a @\<script\>@ element and returns a Promise.
--   * @__canopy_prefetch(id)@ — preloads a chunk without executing it.
--
-- The runtime is only emitted inside the entry chunk when code splitting is
-- active.  When no lazy imports exist the runtime is omitted entirely and
-- generated output is identical to the legacy single-file path.
--
-- @since 0.19.2
module Generate.JavaScript.CodeSplit.Runtime
  ( chunkRuntime,
  )
where

import Data.ByteString.Builder (Builder)
import Text.RawString.QQ (r)

-- | JavaScript runtime for the chunk loading system.
--
-- Injected into the entry chunk immediately after the standard Canopy
-- runtime functions (F2-F9, A2-A9).  The manifest variable is populated
-- by "Generate.JavaScript.CodeSplit.Manifest" during code generation.
--
-- The runtime is designed to be minimal and self-contained with no
-- external dependencies beyond standard browser APIs.
--
-- @since 0.19.2
chunkRuntime :: Builder
chunkRuntime =
  [r|
var __canopy_chunks = {};
var __canopy_loaded = {};
var __canopy_manifest = {};
function __canopy_register(id, factory) {
  __canopy_chunks[id] = factory;
}
function __canopy_load(id) {
  if (__canopy_loaded[id]) return __canopy_loaded[id];
  if (__canopy_chunks[id]) {
    __canopy_loaded[id] = __canopy_chunks[id]();
    return __canopy_loaded[id];
  }
  return new Promise(function(resolve, reject) {
    var s = document.createElement('script');
    s.src = __canopy_manifest[id];
    s.onload = function() {
      if (__canopy_chunks[id]) {
        __canopy_loaded[id] = __canopy_chunks[id]();
        resolve(__canopy_loaded[id]);
      } else {
        reject(new Error('Chunk ' + id + ' did not register'));
      }
    };
    s.onerror = function() {
      reject(new Error('Failed to load chunk ' + id));
    };
    document.head.appendChild(s);
  });
}
function __canopy_prefetch(id) {
  if (__canopy_chunks[id] || __canopy_loaded[id]) return;
  var link = document.createElement('link');
  link.rel = 'prefetch';
  link.as = 'script';
  link.href = __canopy_manifest[id];
  document.head.appendChild(link);
}
|]

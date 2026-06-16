{-# LANGUAGE OverloadedStrings #-}

-- | Native bundle assembly (CMP-5): @canopy make --target native@.
--
-- == Why this module exists
--
-- The Canopy native host (Hermes/JSI) loads a single self-contained JS bundle.
-- That bundle is the SAME IIFE the web reuse path produces — it carries the
-- Hermes stdlib shims (CMP-10), the runtime, the tree-shaken user program, and
-- the @_Platform_export({'Main': ...})@ program export — PLUS two host-facing
-- pieces the web bundle does not need:
--
--   1. the @__canopy_boot(rootTag, flags)@ entry hook the host's JSI installer
--      calls (see @host/shared/cpp/CanopyFabric.cpp@), and the small set of ABI
--      globals it depends on; and
--   2. the source map, carried IN-BUNDLE as @globalThis.__canopy_sourcemap@,
--      because bare Hermes cannot fetch a sibling @.map@ to symbolicate a frame.
--
-- Historically the native build tool ASSEMBLED this by hand: it ran
-- @canopy make --output-format=iife@, then string-spliced the boot hook and a
-- JSON-escaped copy of the map onto the end of the emitted JS, and re-emitted a
-- @sourceMappingURL@ comment. That splice is brittle in exactly the way the
-- CMP-5 plan calls out: the boot hook is hand-maintained out-of-tree, and the
-- map is detached from the bytes it describes — any change to the emitted
-- prologue (a new shim, a runtime helper) silently shifts every generated line
-- while the inlined map stays put, so a red-box points at the wrong @.can@ line.
--
-- This module folds that assembly INTO the compiler. It consumes the IIFE
-- 'Builder' and the 'SourceMap.SourceMap' that 'Generate.JavaScript.generate'
-- produced TOGETHER (so the map already describes the IIFE's true byte layout,
-- CMP-6/CMP-7A), and appends the boot hook + ABI fallbacks + inline map. The
-- appended trailer comes strictly AFTER the IIFE, so it cannot move any mapped
-- generated line — the map stays aligned to the final bytes by construction,
-- which is the property the old hand-splice could not guarantee.
--
-- == The seam (ratified per the plan note)
--
-- /Compiler owns/ JS + map + boot hook (+ .hbc downstream). /Host owns/
-- manifest, assets, Fabric codegen, deploy. This module is the compiler side of
-- that line: it emits the booted JS and the in-bundle map, and NOTHING about
-- packaging, hashing, or the native module ABI implementation (that lives in
-- @package/external/native.js@ on the host side and is embedded as ordinary FFI
-- by the normal codegen path — the boot hook here only REACHES it).
--
-- @since 0.20.9
module Generate.JavaScript.NativeBundle
  ( -- * Assembly
    assemble
  , assembleWith
  , assembleBuilder
  , MapDisposition (..)
  , dispositionFor

    -- * Pieces (exposed for testing)
  , bootHook
  , inlineSourceMap
  , sourceMappingRef
  , escapeJsString
  ) where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import qualified Generate.JavaScript.SourceMap as SourceMap

-- | Assemble the final native bundle from the IIFE JS and its (optional) map,
-- returning the booted JS 'Builder' and the map 'Builder' to write alongside.
--
-- The returned JS is, in byte order:
--
--   1. the IIFE bundle exactly as 'Generate.JavaScript.generate' emitted it
--      (Hermes shims + runtime + program + @_Platform_export@);
--   2. the @__canopy_boot@ hook + ABI fallbacks ('bootHook'); and
--   3. the in-bundle map assignment ('inlineSourceMap') and a
--      @sourceMappingURL@ comment ('sourceMappingRef') — both present only when
--      a map exists (dev builds; 'Nothing' under @--optimize@).
--
-- The second 'Builder' of the pair is the standalone @.js.map@ JSON to write to
-- disk (also dev-only). It is byte-identical to the JSON inlined in (3), so a
-- host can symbolicate from either the in-bundle copy (bare Hermes) or the
-- sibling file (a tool that can read it) and get the same answer.
--
-- The map is /unchanged/ from the input: every trailer line is appended AFTER
-- the IIFE, so no mapped generated line moves and no re-shift is needed — the
-- exact property the old hand-splice could not hold.
assemble
  :: FilePath
  -- ^ the bundle's own file name, for the @sourceMappingURL=@ comment
  -> Builder
  -- ^ the IIFE bundle from 'Generate.JavaScript.generate'
  -> Maybe SourceMap.SourceMap
  -- ^ its source map ('Nothing' when no map was produced)
  -> (Builder, Maybe Builder)
assemble bundleName iife maybeMap =
  assembleWith InlineMap bundleName iife maybeMap

-- | How the source map travels with the bundle (CMP-8b).
--
-- The map is decoupled from Dev\/Prod: it is the DISPOSITION, not the build
-- mode, that decides how it ships. Both shapes write the standalone @.js.map@
-- and the @sourceMappingURL@ comment; they differ only in whether the JSON is
-- ALSO inlined into the bundle bytes.
data MapDisposition
  = -- | Dev: inline @globalThis.__canopy_sourcemap@ AND write the sibling
    -- @.js.map@. Bare Hermes symbolicates from the in-bundle copy; tools that
    -- read sibling maps use the file. Both copies are byte-identical.
    InlineMap
  | -- | Prod (CMP-8b): write the sibling @.js.map@ and emit the
    -- @sourceMappingURL@ comment, but do NOT inline the JSON. The map is
    -- ARCHIVED OUT-OF-BAND — a release crash on a device is still symbolicatable
    -- by a service that pulls the @.map@, without paying the map's bytes (often
    -- larger than the minified bundle) in the shipped APK. This is the size
    -- budget the CMP-8b plan calls for: @--optimize@ no longer DROPS the map, it
    -- MOVES it out of the bundle.
    ArchiveMap
  deriving (Eq, Show)

-- | The disposition for a build: 'InlineMap' for a dev build, 'ArchiveMap' for
-- an optimized one. A small helper so the caller expresses intent
-- (@dispositionFor isOptimized@) rather than naming the constructor.
dispositionFor :: Bool -> MapDisposition
dispositionFor isOptimized = if isOptimized then ArchiveMap else InlineMap

-- | 'assemble' generalised over the map 'MapDisposition' (CMP-8b).
--
-- The returned JS is the IIFE, then the boot hook, then the map trailer per the
-- disposition:
--
--   * 'InlineMap': inline assignment + @sourceMappingURL@ (dev);
--   * 'ArchiveMap': @sourceMappingURL@ only — the JSON is NOT inlined (prod).
--
-- The standalone @.js.map@ 'Builder' (the second component) is returned for BOTH
-- dispositions when a map exists, since both archive the map to disk; it is
-- 'Nothing' only when there is no map at all.
assembleWith
  :: MapDisposition
  -> FilePath
  -> Builder
  -> Maybe SourceMap.SourceMap
  -> (Builder, Maybe Builder)
assembleWith disposition bundleName iife maybeMap =
  ( assembleBuilder disposition bundleName iife maybeMap
  , fmap SourceMap.toBuilder maybeMap
  )

-- | The JS-only half of 'assembleWith': the booted bundle 'Builder'.
--
-- Kept separate so callers that only need the JS (e.g. a golden that snapshots
-- the bundle text, or a host that already has the map) need not re-serialize the
-- map. 'assembleWith' delegates here for its first component.
assembleBuilder
  :: MapDisposition
  -> FilePath
  -> Builder
  -> Maybe SourceMap.SourceMap
  -> Builder
assembleBuilder disposition bundleName iife maybeMap =
  iife
    <> bootHook
    <> mapTrailer
  where
    mapTrailer =
      case maybeMap of
        Nothing -> mempty
        Just sm ->
          case disposition of
            -- Dev: the map travels inside the bundle (bare Hermes can't fetch a
            -- sibling) PLUS a sourceMappingURL for tools that read siblings.
            InlineMap -> inlineSourceMap sm <> sourceMappingRef bundleName
            -- Prod (CMP-8b): the map is archived to the sibling .js.map only.
            -- We still emit sourceMappingURL so a symbolication service can find
            -- it, but the JSON itself stays OUT of the shipped bytes.
            ArchiveMap -> sourceMappingRef bundleName

-- | The native boot hook + ABI fallbacks, appended after the IIFE.
--
-- @__canopy_boot(rootTag, flags)@ is the single entry the host's JSI installer
-- invokes after evaluating the bundle (see @host/shared/cpp/CanopyFabric.cpp@'s
-- @runtime.global().getProperty(runtime, "__canopy_boot")@). It bridges the
-- frozen ABI to the program export the IIFE installed: the IIFE's
-- @_Platform_export({'Main': ...})@ publishes the compiled module under the
-- @Elm@ global (with @Canopy@ aliased to it), so the hook resolves
-- @g.Elm.Main@ (falling back through @g.scope.Elm@ for the @window@/@this@
-- scope shape the IIFE closes over) and calls its @init({node, flags})@ — the
-- native analog of @Browser.element@'s mount.
--
-- The fallback chain (@g.Canopy || (g.scope && g.scope.Canopy)@, then the @Elm@
-- back-compat alias) is the ABI fallback the plan names: the IIFE assigns
-- @scope['Canopy']@ (canonical) + @scope['Elm']@ (alias) where @scope@ is
-- @window@/@this@, and on a bare Hermes/JSI global neither @window@ nor a
-- pre-existing @global@ alias is guaranteed, so the hook tolerates both the
-- direct-global and the scoped-global shapes rather than assuming one.
--
-- This is emitted UNCONDITIONALLY (dev and @--optimize@): the host always boots
-- through it; only the map trailer is dev-gated.
bootHook :: Builder
bootHook =
  BB.stringUtf8 $
    unlines
      [ ""
      , "// GENERATED by canopy make --target native — native boot hook (CMP-5)."
      , "(function (g) {"
      , "  g.__canopy_boot = function (rootTag, flags) {"
      , "    var canopy = g.Canopy || (g.scope && g.scope.Canopy) || g.Elm || (g.scope && g.scope.Elm);"
      , "    if (!canopy || !canopy.Main) {"
      , "      throw new Error('canopy: compiled module Main not found on global Canopy');"
      , "    }"
      , "    return canopy.Main.init({ node: rootTag, flags: flags });"
      , "  };"
      , "})(typeof globalThis !== 'undefined' ? globalThis : this);"
      ]

-- | The in-bundle source map assignment.
--
-- Bare Hermes cannot fetch a sibling @.map@, so the map travels inside the
-- bundle as a JSON string on @globalThis.__canopy_sourcemap@, which the host's
-- symbolicator (@_Native_symbolicate@ in @package/external/native.js@) parses to
-- turn @canopy.bundle.js:LINE:COL@ frames into @Module.can:LINE@. The value is
-- the SAME map JSON written to the sibling @.js.map@ (see 'assemble'), escaped
-- as a JS string literal so it is a single self-contained assignment.
inlineSourceMap :: SourceMap.SourceMap -> Builder
inlineSourceMap sm =
  BB.stringUtf8 "globalThis.__canopy_sourcemap = \""
    <> escapeJsString (renderMap sm)
    <> BB.stringUtf8 "\";\n"

-- | The @sourceMappingURL@ comment, pointing at the sibling @.js.map@.
--
-- Tools that DO read sibling maps (a desktop debugger, a symbolication service)
-- use this; bare Hermes ignores it and uses the in-bundle copy instead. The name
-- is the bundle's own filename with @.map@ appended, matching the file
-- 'assemble' hands back.
sourceMappingRef :: FilePath -> Builder
sourceMappingRef bundleName =
  BB.stringUtf8 ("//# sourceMappingURL=" <> takeFileName bundleName <> ".map\n")

-- | The map serialized to its JSON 'BL.ByteString', for inlining as a JS string.
renderMap :: SourceMap.SourceMap -> BL.ByteString
renderMap = BB.toLazyByteString . SourceMap.toBuilder

-- | Escape a 'BL.ByteString' (the map JSON) for embedding inside a
-- double-quoted JS string literal.
--
-- The map JSON is plain ASCII (it is itself JSON-escaped by
-- 'SourceMap.toBuilder'), so only @\\@ and @"@ — and, defensively, the control
-- characters a stray byte could introduce — need escaping. Backslash MUST be
-- escaped first/together so an already-escaped @\\n@ inside the JSON becomes
-- @\\\\n@ (a literal backslash-n in the JS string, which @JSON.parse@ then reads
-- back as @\\n@), never a real newline that would break the assignment across
-- lines.
escapeJsString :: BL.ByteString -> Builder
escapeJsString = BLC.foldr (\c acc -> escapeJsChar c <> acc) mempty

-- | Escape one character for a double-quoted JS string literal.
escapeJsChar :: Char -> Builder
escapeJsChar c =
  case c of
    '\\' -> BB.stringUtf8 "\\\\"
    '"'  -> BB.stringUtf8 "\\\""
    '\n' -> BB.stringUtf8 "\\n"
    '\r' -> BB.stringUtf8 "\\r"
    '\t' -> BB.stringUtf8 "\\t"
    _    -> BB.charUtf8 c

-- | The final path component of a file name (no @System.FilePath@ dependency,
-- to keep this module free of platform-path concerns — the bundle name is a
-- plain emitted filename, always @/@-or-bare).
takeFileName :: FilePath -> FilePath
takeFileName = reverse . takeWhile (\c -> c /= '/' && c /= '\\') . reverse

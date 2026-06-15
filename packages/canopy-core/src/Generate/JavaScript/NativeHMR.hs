{-# LANGUAGE OverloadedStrings #-}

-- | Fast Refresh codegen for the native (Hermes\/JSI) IIFE bundle (CMP-9).
--
-- == Why this module exists
--
-- The web reuse path already has Hot Module Replacement: 'Generate.JavaScript.ESM.HMR'
-- emits, per @.can@ module, an @import.meta.hot.accept@ boundary plus a
-- @__MODEL_HASH__@ structural hash of the Model type, and the Vite dev server
-- hot-swaps @init@\/@update@\/@view@\/@subscriptions@ in place while preserving
-- the live Model — UNLESS the Model type changed shape, in which case the hash
-- mismatches and Vite falls back to a full reload.
--
-- The native target ships a single self-contained IIFE (see
-- 'Generate.JavaScript.NativeBundle'), not a graph of ESM modules. There is no
-- @import.meta.hot@ on bare Hermes, and the dev host (DEV-4's JNI reload, the
-- iOS dev loop) drives reload itself over ONE Hermes runtime via the seam in
-- @package\/external\/native.js@ (@__canopy_captureState@ \/ @__canopy_teardown@
-- \/ @__canopy_remount@). That seam's true-state-preserving Fast Refresh
-- (DEV-8) gates preserve-vs-reset on a structural Model type-hash it reads off
-- the host global as @__canopy_model_typehash@ — an emission no compiler lane
-- has produced yet (the DEV-8 harness injects it by hand today). CMP-9 is the
-- compiler side: emit that hash, AND the format-agnostic per-module accept
-- boundary the host consumes, INTO the native IIFE.
--
-- == What it emits (dev only)
--
-- Inside the IIFE, AFTER @_Platform_export@ has published the program (so the
-- accept boundary can reach @init@\/@update@\/@view@\/@subscriptions@), this
-- module appends, gated to dev exactly like 'ESM.HMR':
--
--   1. @globalThis.__canopy_model_typehash@ — the structural hash of the Model
--      type, as a string. This is the LOAD-BEARING DEV-8 emission: the host's
--      @_Native_modelTypehash()@ reads this exact global and @String()@s it, so
--      a reload's captured-vs-reloaded hash equality decides preserve-vs-reset.
--      Reusing 'HMR.hashCanType' keeps the native hash bit-identical to the ESM
--      one for the same Model type, so the two HMR paths can never disagree.
--
--   2. @__canopy_hmr.register(moduleId, members, modelHash)@ — the
--      format-agnostic per-module accept\/boundary hook the plan names. It
--      records the boundary's @{init, update, view, subscriptions}@ members and
--      its @modelHash@ in a moduleId-keyed table, and exposes
--      @__canopy_hmr.accept(moduleId, nextMembers, nextModelHash)@: the host's
--      re-eval entry. @accept@ reuses the SAME hash for the model-compat gate —
--      equal hash hot-swaps the members in place and returns @true@ (preserve);
--      a changed hash leaves the boundary untouched and returns @false@ so the
--      host falls back to a fresh init (the DEV-8 \"Model changed\" reset). The
--      @__canopy_hmr@ runtime object itself is installed once, idempotently, so
--      a re-evaluated bundle re-registers against the same table.
--
-- Under @--optimize@ (a release bundle) NOTHING here is emitted — Fast Refresh
-- is a dev-only affordance, exactly as 'ESM.HMR' returns @[]@ in prod — so the
-- shipped native bytes are unchanged and the host seam's @_Native_modelTypehash@
-- correctly reads @null@ (no global), keeping the seam inert in production.
--
-- == The moduleId for the native IIFE
--
-- ESM HMR is per-@.can@-file: each module is its own re-eval boundary. The
-- native IIFE has ONE re-eval boundary — the whole bundle — so the moduleId is
-- the MAIN module's canonical name (e.g. @\"Main\"@). That is the granularity
-- the host reloads at (it re-evals the whole bundle and re-boots), so a single
-- registration keyed by the main module is exactly the boundary table the host
-- needs; a future multi-boundary IIFE can register more without changing this
-- shape.
--
-- @since 0.20.11
module Generate.JavaScript.NativeHMR
  ( -- * Emission
    generateNativeHMR

    -- * Pieces (exposed for testing)
  , hmrRuntime
  , modelTypehashGlobal
  , registerCall
  , moduleIdFor
  , modelHashHex
  ) where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Word (Word32)
import qualified Generate.JavaScript.ESM.HMR as HMR
import qualified Generate.Mode as Mode

-- | Emit the native Fast Refresh codegen for a bundle's mains (CMP-9).
--
-- Returns the JS 'Builder' appended INSIDE the IIFE, after @_Platform_export@.
-- It is the concatenation of:
--
--   * the @__canopy_hmr@ runtime object (idempotently installed), then
--   * for the main module: the @__canopy_model_typehash@ global + the
--     @__canopy_hmr.register(...)@ boundary registration.
--
-- Emits 'mempty' for: production mode (@--optimize@ — Fast Refresh is dev-only,
-- mirroring 'HMR.generateHMRItems'), a bundle with no @Dynamic@ main (a headless
-- worker has no Model to preserve), or no main at all. So the web\/prod native
-- bytes are unchanged, and the only growth is in a dev native bundle that has a
-- TEA program — exactly the bundle the dev host reloads.
--
-- @since 0.20.11
generateNativeHMR
  :: Mode.Mode
  -> Map ModuleName.Canonical Opt.Main
  -> Builder
generateNativeHMR mode mains =
  case mode of
    Mode.Prod {} -> mempty
    Mode.Dev {} ->
      case dynamicMains mains of
        [] -> mempty
        boundaries -> hmrRuntime <> foldMap boundaryEmit boundaries

-- | The @Dynamic@ (TEA) mains, each paired with its module name and Model hash.
--
-- A @Static@ main (a headless program with no Model) carries no Model to
-- preserve across a reload, so it is excluded — there is nothing for Fast
-- Refresh to gate on, exactly as 'HMR.generateForMain' emits @[]@ for it.
dynamicMains
  :: Map ModuleName.Canonical Opt.Main
  -> [(ModuleName.Canonical, Word32)]
dynamicMains mains =
  [ (home, HMR.hashCanType modelType)
  | (home, Opt.Dynamic modelType _ _) <- Map.toList mains
  ]

-- | Emit the per-boundary pieces: the model-typehash global + the register call.
boundaryEmit :: (ModuleName.Canonical, Word32) -> Builder
boundaryEmit (home, hash) =
  modelTypehashGlobal hash <> registerCall home hash

-- | The structural Model type-hash, as the host-facing hex string global.
--
-- This is the DEV-8 load-bearing emission. The host's @_Native_modelTypehash()@
-- (in @package\/external\/native.js@) reads @g.__canopy_model_typehash@ and
-- @String()@s it; a reload compares the captured (old-bundle) value against the
-- re-evaluated (new-bundle) value with @===@ to decide preserve-vs-reset. We set
-- it on @globalThis@ (the host reads it off the host global) as the SAME hex the
-- @register@ call carries, so the two never disagree.
modelTypehashGlobal :: Word32 -> Builder
modelTypehashGlobal hash =
  "\nglobalThis.__canopy_model_typehash = \"" <> modelHashHex hash <> "\";\n"

-- | The @__canopy_hmr.register(moduleId, members, modelHash)@ boundary call.
--
-- @members@ is the live @{init, update, view, subscriptions}@ object pulled off
-- the just-exported program (@scope['Elm'].<Module>@ — the same global
-- @_Platform_export@ published, reached through the IIFE's @scope@). The host's
-- re-eval entry (@__canopy_hmr.accept@) hot-swaps these in place on a matching
-- @modelHash@. We pass the members as a thunk-free object literal of property
-- reads so an absent member (a program without @subscriptions@) lands as
-- @undefined@ rather than throwing.
registerCall :: ModuleName.Canonical -> Word32 -> Builder
registerCall home hash =
  "__canopy_hmr.register("
    <> "\"" <> moduleIdFor home <> "\", "
    <> programMembers home <> ", "
    <> "\"" <> modelHashHex hash <> "\""
    <> ");\n"

-- | The @{init, update, view, subscriptions}@ members object for a boundary.
--
-- Read off the exported program object under @scope['Elm']@ (the global
-- @_Platform_export@ installs, with @Canopy@ aliased to it). Each member is a
-- guarded property read so a member the program does not define is @undefined@,
-- not a @TypeError@. The members live on the program's @init@-returned app, but
-- the program functions @update@\/@view@\/@subscriptions@ are the ones the host
-- swaps; we expose the program object itself so the host's @accept@ can re-pull
-- whichever members it hot-swaps.
programMembers :: ModuleName.Canonical -> Builder
programMembers home =
  "{ \"program\": " <> programRef home <> " }"

-- | A defensive reference to the exported program object for a module.
--
-- @scope['Elm']@ is where @_Platform_export@ publishes (see
-- 'Generate.JavaScript.Kernel.toMainExports'); the program nests under its
-- module-name path (e.g. @scope['Elm']['Main']@). We resolve the top-level
-- module segment only (the boundary the host reloads is the whole program), and
-- guard every hop so a shape the IIFE did not publish yields @undefined@ rather
-- than throwing inside the register call.
programRef :: ModuleName.Canonical -> Builder
programRef home =
  let topSegment = topModuleSegment home
   in "(scope && scope['Elm'] && scope['Elm']['" <> topSegment <> "'])"

-- | The moduleId for a boundary: the module's full canonical name (dotted).
--
-- The native IIFE's re-eval boundary is the whole bundle, addressed by its main
-- module, so the moduleId is the human-readable module name (e.g. @\"Main\"@,
-- @\"Pages.Home\"@) — stable across reloads of the same program and unique per
-- main, which is all the host's boundary table needs.
moduleIdFor :: ModuleName.Canonical -> Builder
moduleIdFor home =
  Name.toBuilder (ModuleName._module home)

-- | The TOP dotted segment of a module name (e.g. @Pages.Home@ -> @Pages@).
--
-- @_Platform_export@ nests a dotted module under each segment as an object path
-- (@Elm.Pages.Home@), so the top-level object lives at the first segment. The
-- boundary we register is that top-level program object; the host re-pulls the
-- members it swaps from there.
topModuleSegment :: ModuleName.Canonical -> Builder
topModuleSegment home =
  let full = Name.toChars (ModuleName._module home)
   in BB.stringUtf8 (takeWhile (/= '.') full)

-- | The model hash as a fixed 8-digit lowercase hex string.
--
-- 'BB.word32Hex' renders the minimal-width hex (no leading zeros), which is
-- exactly what 'ESM.HMR' inlines into @__MODEL_HASH__@, so the native string is
-- byte-identical to the ESM one for the same Model type — the two HMR paths
-- agree by construction.
modelHashHex :: Word32 -> Builder
modelHashHex = BB.word32Hex

-- | The @__canopy_hmr@ Fast Refresh runtime, installed once on the host global.
--
-- This is the format-agnostic core the plan calls for: a small boundary table
-- ('register') plus the model-compat gate ('accept') that REUSES the same
-- structural model hash the ESM path uses. It is idempotent — a re-evaluated
-- bundle (the host re-evals the whole IIFE on reload) finds @__canopy_hmr@
-- already installed and keeps the existing table, so registrations survive the
-- re-eval the host drives.
--
-- @accept(moduleId, nextMembers, nextModelHash)@ is the host's re-eval entry:
--
--   * an UNKNOWN moduleId (never registered) → register it fresh, return @true@
--     (nothing to preserve, so accept it);
--   * a KNOWN moduleId with an EQUAL @modelHash@ → swap the members in place,
--     keep the recorded hash, return @true@ (preserve — the DEV-8 win);
--   * a KNOWN moduleId with a CHANGED @modelHash@ → leave the boundary untouched
--     and return @false@, the signal the host falls back to a fresh init on (the
--     DEV-8 \"Model changed\" reset). We do NOT mutate the table on a reject, so
--     a host that retries with the same shape still sees the old boundary.
--
-- The runtime touches only its own global; it never reaches into the compiler
-- kernel, exactly like the rest of the native HMR surface.
hmrRuntime :: Builder
hmrRuntime =
  BB.stringUtf8 $
    unlines
      [ ""
      , "// GENERATED by canopy make --target native — Fast Refresh runtime (CMP-9)."
      , "(function (g) {"
      , "  if (g.__canopy_hmr) { return; }"
      , "  var boundaries = {};"
      , "  g.__canopy_hmr = {"
      , "    register: function (moduleId, members, modelHash) {"
      , "      boundaries[moduleId] = { members: members, modelHash: modelHash };"
      , "      return true;"
      , "    },"
      , "    accept: function (moduleId, nextMembers, nextModelHash) {"
      , "      var prev = boundaries[moduleId];"
      , "      if (!prev) {"
      , "        boundaries[moduleId] = { members: nextMembers, modelHash: nextModelHash };"
      , "        return true;"
      , "      }"
      , "      if (prev.modelHash !== nextModelHash) {"
      , "        return false;"
      , "      }"
      , "      prev.members = nextMembers;"
      , "      return true;"
      , "    },"
      , "    boundary: function (moduleId) {"
      , "      return boundaries[moduleId] || null;"
      , "    }"
      , "  };"
      , "})(typeof globalThis !== 'undefined' ? globalThis : this);"
      ]

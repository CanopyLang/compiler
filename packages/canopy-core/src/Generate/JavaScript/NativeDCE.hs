{-# LANGUAGE OverloadedStrings #-}

-- | Native dead-code elimination + browser-global gating (CMP-8b).
--
-- == Why this module exists
--
-- The native (Hermes/JSI) bundle is the SAME IIFE the web reuse path compiles
-- (see 'Generate.JavaScript.NativeBundle'). That IIFE bakes in the @canopy/html@
-- + @canopy/virtual-dom@ kernel, which — being written for the browser — carries
-- a handful of @window@ / @document@ references. Most are GUARDED probes
-- (@typeof document !== 'undefined' ? document : {}@) that are inert off a
-- browser, but two are UNGUARDED real accesses the tree-shaker cannot drop
-- because they sit inside otherwise-reachable kernel functions:
--
--   * @window.addEventListener@ / @window.removeEventListener@ — the
--     passive-event-listener feature probe, run once at module-eval time
--     (wrapped in @try/catch@, so it would throw-and-swallow a
--     @ReferenceError: window is not defined@ on bare Hermes); and
--   * @document.body@ — the event-delegation root fallback in
--     @_VirtualDom_ensureDelegated@, a code path the native host never enters
--     (it installs its own delegation root) but whose mere PRESENCE references
--     @document@.
--
-- On a full engine (Node/V8/web) @window@ and @document@ exist, so these are
-- harmless. On bare Hermes neither global exists, so the bundle carries
-- free identifiers: a latent @ReferenceError@ the instant any of those dead
-- paths runs (and an unsymbolicatable crash, since CMP-8b is also where the
-- prod source map comes back — see 'Generate.JavaScript.NativeBundle').
--
-- == What this module does
--
-- It is the COMPILER side of the CMP-8b mandate "gate/stub browser-only
-- RuntimeDefs (@window@/@document@) for Hermes via an allowlist":
--
--   1. 'allowedBrowserGlobals' / 'browserStubAllowlist' name the EXACT browser
--      surface the native-dead kernel code is permitted to touch — an allowlist,
--      not a wildcard, so a NEW unguarded browser reference (a kernel that
--      starts calling @window.location@, say) is caught by 'unstubbedRefs'
--      instead of silently shipping a fresh free identifier.
--   2. 'browserGlobalStub' emits a tiny, dependency-free preamble that, ONLY
--      when the global is absent (Hermes), installs benign no-op @window@ /
--      @document@ objects exposing exactly the allowlisted members. Under a full
--      engine the real globals already exist and the stub is a no-op, so the
--      SAME bundle behaves identically on Node (the conformance baseline) and on
--      Hermes — the invariant 'Generate.JavaScript.HermesShim' also holds.
--   3. 'unstubbedRefs' is the static assertion the test suite keys off:
--      given the bundle text, it reports any @window.X@ / @document.X@ access
--      whose @X@ is NOT on the allowlist — i.e. a browser reference the stub
--      does not cover, which would crash on Hermes. The native gate fails on a
--      non-empty result.
--
-- The stub is gated so it is emitted ONLY for the native target — the web ESM
-- path runs in a real browser and must not have its @window@/@document@ shadowed
-- by a stub.
--
-- @since 0.20.10
module Generate.JavaScript.NativeDCE
  ( -- * Browser-global allowlist
    allowedBrowserGlobals,
    browserStubAllowlist,
    BrowserGlobal (..),

    -- * Stub preamble
    browserGlobalStub,
    browserStubSource,
    stubMarkerName,

    -- * Static gate (testing / CI)
    unstubbedRefs,
    isAllowed,
  )
where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import Data.List (isPrefixOf, nub, sort)

-- | A browser global the native bundle is permitted to reference, together with
-- the exact member names the kernel touches on it.
--
-- An entry @(window, [addEventListener, removeEventListener])@ means: the native
-- bundle may reference @window.addEventListener@ and @window.removeEventListener@
-- and NOTHING else on @window@. Anything outside this list is, by construction,
-- an unstubbed reference the gate must reject.
--
-- @since 0.20.10
data BrowserGlobal = BrowserGlobal
  { -- | The global identifier, e.g. @"window"@ or @"document"@.
    bgName :: String,
    -- | The allowlisted member names accessed on it (the @X@ in @name.X@).
    bgMembers :: [String]
  }
  deriving (Eq, Show)

-- | The browser-global allowlist: the EXACT @window@/@document@ surface the
-- native-dead kernel code references, and therefore the surface the stub
-- provides. Derived from the unguarded references actually present in the
-- assembled @canopy/html@ + @canopy/virtual-dom@ native bundle:
--
--   * @window.addEventListener@ / @window.removeEventListener@ — passive-event
--     feature probe (module-eval, @try/catch@-wrapped);
--   * @document.body@ — event-delegation root fallback (native-dead path).
--
-- Guarded probes (@typeof window !== 'undefined' ? window : this@,
-- @typeof document !== 'undefined' ? document : {}@) are NOT in this list and
-- need no stub: they already resolve safely to @this@/@{}@ on Hermes. Only
-- UNGUARDED member accesses need a stubbed target, which is what this allowlist
-- enumerates.
--
-- Keeping this as an explicit, reviewed list (rather than scanning the bundle at
-- build time and stubbing whatever it finds) is the point: a new unguarded
-- browser reference is a deliberate decision that must extend this list AND the
-- stub, and 'unstubbedRefs' fails the build until it does.
--
-- @since 0.20.10
allowedBrowserGlobals :: [BrowserGlobal]
allowedBrowserGlobals =
  [ BrowserGlobal "window" ["addEventListener", "removeEventListener"],
    BrowserGlobal
      "document"
      [ "body",
        "location", -- @_Browser_application@'s URL error path (native-dead).
        "addEventListener",
        "removeEventListener",
        "createElement",
        "createTextNode"
      ]
  ]

-- | The allowlist flattened to @(global, member)@ pairs, for membership tests.
--
-- @since 0.20.10
browserStubAllowlist :: [(String, String)]
browserStubAllowlist =
  [ (bgName bg, m) | bg <- allowedBrowserGlobals, m <- bgMembers bg ]

-- | Whether a @global.member@ access is on the allowlist (and therefore covered
-- by 'browserGlobalStub').
--
-- @since 0.20.10
isAllowed :: String -> String -> Bool
isAllowed global member = (global, member) `elem` browserStubAllowlist

-- | The marker object the stub installs on the global, mirroring
-- 'Generate.JavaScript.HermesShim.shimMarkerName'. The host + the native gate
-- read @globalThis.__canopy_dom_stub@ to learn whether (and which) browser
-- globals were stubbed on this engine.
--
-- @since 0.20.10
stubMarkerName :: String
stubMarkerName = "__canopy_dom_stub"

-- | The browser-global stub preamble, ready to splice into the native bundle.
--
-- Emitted (native target only) AFTER the Hermes shim and BEFORE any FFI/user
-- content, so the @window@/@document@ stubs exist before the kernel's
-- module-eval feature probe ('window.addEventListener') runs. Newline-terminated.
--
-- @since 0.20.10
browserGlobalStub :: Builder
browserGlobalStub = BB.stringUtf8 browserStubSource

-- | The stub source. One self-contained, idempotent IIFE.
--
-- DESIGN:
--
--   * It binds the same global the bundle binds (@globalThis@ → @global@ →
--     @this@), matching the Hermes shim and runtime preamble.
--   * For each allowlisted global, it installs a stub ONLY when the global is
--     absent (@typeof g.window === 'undefined'@) — so a full engine's real
--     @window@/@document@ is never shadowed and the bundle is behaviour-
--     identical on Node and Hermes.
--   * Each stubbed member is a benign no-op: methods return @undefined@,
--     @document.body@ is a stub element whose @addEventListener@ is also a
--     no-op (the delegation-root fallback calls @root.addEventListener@). This
--     turns a would-be @ReferenceError@ into a silent no-op on the native-dead
--     path, which is correct: those paths do nothing on the native host anyway.
--   * It records which globals it stubbed on @globalThis.__canopy_dom_stub@.
--
-- This is INTENTIONALLY tiny: it is not a DOM polyfill, only enough to keep the
-- allowlisted dead references from throwing on bare Hermes.
--
-- @since 0.20.10
browserStubSource :: String
browserStubSource =
  unlines
    [ "(function () {",
      "  var g = (typeof globalThis !== 'undefined') ? globalThis",
      "        : (typeof global !== 'undefined') ? global",
      "        : (typeof window !== 'undefined') ? window : this;",
      "  if (g." ++ stubMarkerName ++ ") { return; }",
      "  var marker = { stubbedWindow: false, stubbedDocument: false };",
      "  g." ++ stubMarkerName ++ " = marker;",
      "  // A no-op event target: addEventListener/removeEventListener do nothing.",
      "  // Used for both the window stub and document.body so the native-dead",
      "  // delegation/feature-probe paths resolve instead of throwing on Hermes.",
      "  function noopTarget() {",
      "    return {",
      "      addEventListener: function () {},",
      "      removeEventListener: function () {}",
      "    };",
      "  }",
      "  // Stub `window` as the global ITSELF (exactly as a real browser, where",
      "  // window === the global object), NOT as a distinct noopTarget. The bundle's",
      "  // IIFE binds its export scope as `(typeof window !== 'undefined' ? window : this)`,",
      "  // so a SEPARATE window object would make the first eval export onto `this`/globalThis",
      "  // but every later re-eval (a hot reload re-runs the whole bundle) bind `scope` to that",
      "  // distinct window -- onto which the host's reset of globalThis.Canopy has no effect -- and",
      "  // re-exporting Main there trips the duplicate-module guard. Aliasing window to the global",
      "  // keeps `scope` a single stable object so reload re-evals stay idempotent (CMP-5 reload).",
      "  if (typeof g.window === 'undefined') {",
      "    if (typeof g.addEventListener === 'undefined') { g.addEventListener = function () {}; }",
      "    if (typeof g.removeEventListener === 'undefined') { g.removeEventListener = function () {}; }",
      "    g.window = g;",
      "    marker.stubbedWindow = true;",
      "  }",
      "  if (typeof g.document === 'undefined') {",
      "    var body = noopTarget();",
      "    g.document = {",
      "      body: body,",
      "      // location.href backs _Browser_application's URL error path, which",
      "      // is native-dead but textually present; an empty href keeps it inert.",
      "      location: { href: '' },",
      "      addEventListener: function () {},",
      "      removeEventListener: function () {},",
      "      // createElement/createTextNode are never reached on the native host",
      "      // (the JSI renderer owns node creation), but are allowlisted so a",
      "      // stray reference degrades to an inert node rather than a crash.",
      "      createElement: function () { return noopTarget(); },",
      "      createTextNode: function () { return {}; }",
      "    };",
      "    marker.stubbedDocument = true;",
      "  }",
      "}());"
    ]

-- | Static gate: the @global.member@ accesses in the given bundle text that are
-- NOT on the allowlist (and so are not covered by 'browserGlobalStub').
--
-- A non-empty result means the bundle references a browser global the stub does
-- not provide — a free identifier that would crash on bare Hermes — and the
-- native codegen gate fails on it.
--
-- It scans for @window.<ident>@ and @document.<ident>@ member accesses and keeps
-- those whose member is not allowlisted, IGNORING:
--
--   * guarded probes of the bare identifier (@typeof window@,
--     @window : this@) — those carry no @.member@ and are safe;
--   * occurrences INSIDE string literals (e.g. the @document.getElementById@
--     mentioned in a @canopy/html@ error message) — a string mention is not a
--     reference. We approximate "inside a string" by skipping any @window.@ /
--     @document.@ whose member is immediately followed by content that, together
--     with the surrounding quote run, looks like prose; concretely we drop
--     members that are not a plausible JS identifier-access (handled by the
--     identifier scan) and de-duplicate. The remaining set is the real
--     unstubbed-access surface.
--
-- The scan is deliberately conservative source inspection (no JS parse), in the
-- same spirit as 'Generate.JavaScript.HermesShim.regexUnsupportedReason'. It is
-- a GATE, not a transform: its job is to FAIL on an unexpected reference, and a
-- conservative over-report (flagging something safe) is a louder, safer failure
-- than an under-report.
--
-- @since 0.20.10
unstubbedRefs :: String -> [(String, String)]
unstubbedRefs bundle =
  nub (sort [ ref | ref <- scanAccesses bundle, not (uncurry isAllowed ref) ])

-- | All @window.<ident>@ / @document.<ident>@ member accesses in the text,
-- skipping mentions inside string/error-message literals.
scanAccesses :: String -> [(String, String)]
scanAccesses = go False '\0' '\0'
  where
    -- 'inStr' tracks whether we are inside a '/"/` string literal; 'q' is the
    -- opening quote so we close on the matching one; 'prev' is the previous
    -- (non-string) char, used to require a left word boundary so @_window.x@ or
    -- @mywindow.x@ do not false-match the @window@ global. We do not handle
    -- escapes specially — a member access never appears immediately after a
    -- backslash — which keeps this a simple, robust single pass.
    go :: Bool -> Char -> Char -> String -> [(String, String)]
    go _ _ _ [] = []
    go True q _ (c : rest)
      | c == q = go False '\0' c rest
      | otherwise = go True q c rest
    go False _ prev s@(c : rest)
      | c == '\'' || c == '"' || c == '`' = go True c c rest
      | not (isIdentChar prev),
        Just (global, member, after) <- matchAccess s =
          (global, member) : go False '\0' (lastChar member) after
      | otherwise = go False '\0' c rest

    lastChar [] = '\0'
    lastChar xs = last xs

-- | If the string STARTS with @window.<ident>@ or @document.<ident>@ (a real
-- member access, not a bare guarded identifier), return the global, the member,
-- and the remainder after the member.
matchAccess :: String -> Maybe (String, String, String)
matchAccess s =
  tryGlobal "window" s `orElse` tryGlobal "document" s
  where
    orElse a@(Just _) _ = a
    orElse Nothing b = b

-- | Match @<global>.<ident>@ at the head of the string, ensuring the global is a
-- WORD boundary on its left is the caller's responsibility (we only match at
-- positions the scanner steps to, and a member access like @_window.x@ would
-- have the scanner already inside the identifier — but to be safe we require the
-- char before is not an identifier char by only being called at scan positions).
tryGlobal :: String -> String -> Maybe (String, String, String)
tryGlobal global s
  | global `isPrefixOf` s =
      case drop (length global) s of
        ('.' : rest) ->
          let (member, after) = span isIdentChar rest
           in if null member then Nothing else Just (global, member, after)
        _ -> Nothing
  | otherwise = Nothing

-- | JS identifier characters (enough to delimit a member name).
isIdentChar :: Char -> Bool
isIdentChar c =
  (c >= 'a' && c <= 'z')
    || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9')
    || c == '_'
    || c == '$'

{-# LANGUAGE OverloadedStrings #-}

-- | Hermes standard-library shims for the native (Hermes) bundle target (CMP-10).
--
-- == Why this module exists
--
-- The validated Canopy web path runs the IIFE bundle under a full
-- browser/Node JS engine. The native path runs the SAME bundle under
-- Hermes (the React-Native engine Canopy/native links). Hermes is a
-- conforming ES engine for the language core, but its standard library
-- diverges from Node/V8 in three places the Canopy stdlib actually
-- touches — and every divergence is a SILENT correctness bug, not a crash:
--
--   [@Intl@]   Hermes ships WITHOUT @Intl@ on its default build. The only
--              @Intl@ surface the Canopy stdlib uses is
--              @Intl.DateTimeFormat().resolvedOptions().timeZone@ — the IANA
--              zone-name probe in @canopy/time@'s @Time.getZoneName@. On
--              Hermes @Intl@ is @undefined@, so that probe throws and
--              @getZoneName@ silently degrades to the (also-wrong, see below)
--              numeric offset. Anything richer than the timeZone probe
--              (number/currency/date formatting) is OUT OF SCOPE: the plan is
--              explicit — "scope Intl to exactly what @canopy/time@ + common
--              formatting expose; error on the rest." So the shim installs a
--              minimal @Intl@ that answers the timeZone probe and THROWS a
--              clear, identifiable error for every other use rather than
--              returning a wrong-but-plausible value.
--
--   [@Date@ timezone]
--              Hermes has no embedded timezone database. @getTimezoneOffset()@
--              returns @0@ (UTC) on Hermes regardless of the device zone, so a
--              user in @Europe/Berlin@ who calls @Time.here@ gets a UTC zone on
--              native but a +120 zone on web — the canonical "passes on the dev
--              box, wrong on the user's device" divergence. The shim cannot
--              manufacture a timezone database, so it does the honest thing: it
--              EXPOSES the divergence as a queryable capability flag
--              (@__canopy_hermes.hasLocalTimeZone@) the host can surface, and
--              keeps @getTimezoneOffset@ deterministic so the conformance
--              harness can pin it.
--
--   [@RegExp@] Hermes's regex engine historically lacks lookbehind
--              (@(?<=)@/@(?<!)@) and Unicode-property escapes (@\\p{...}@).
--              Under Node these compile and match; under Hermes they either
--              throw at construction or — worse — match differently. The shim
--              wraps @RegExp@ so an unsupported feature is a LOUD, identifiable
--              @Error@ at construction time on BOTH engines (so the web/test
--              run catches it too), never a silent mismatch on device.
--
-- == What ships
--
-- 'hermesShimPreamble' is a pure-JS string spliced into the native bundle's
-- preamble (see 'Generate.JavaScript.JavaScript.generate', native target).
-- It is idempotent, dependency-free, and a NO-OP shape under a full engine
-- (Node/V8): the @Intl@/@Date@ globals are only touched when the divergence
-- is actually present, so the SAME bundle behaves identically under Node (the
-- conformance baseline) and under Hermes. The @RegExp@ feature gate is the one
-- behaviour applied on both engines — by design, so an unsupported pattern
-- fails in CI (Node) instead of only on a device.
--
-- The marker object @globalThis.__canopy_hermes@ records which shims engaged,
-- giving the host and the conformance suite a single introspection point.
--
-- @since 0.20.8
module Generate.JavaScript.HermesShim
  ( -- * Preamble emission
    hermesShimPreamble,
    hermesShimSource,

    -- * Introspection (testing / host)
    shimMarkerName,
    unsupportedIntlSentinel,
    unsupportedRegexSentinel,
  )
where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB

-- | The native-bundle Hermes shim, ready to splice into the bundle preamble.
--
-- Emitted immediately after the @__canopy_debug@ runtime declaration and
-- before any FFI/user content, so @Intl@/@Date@/@RegExp@ are normalised before
-- the first stdlib call can observe them. Newline-terminated.
--
-- @since 0.20.8
hermesShimPreamble :: Builder
hermesShimPreamble = BB.stringUtf8 hermesShimSource

-- | The global marker object the shim installs. Host + conformance suite read
-- @globalThis.__canopy_hermes@ to learn which shims engaged and to query the
-- timezone capability.
--
-- @since 0.20.8
shimMarkerName :: String
shimMarkerName = "__canopy_hermes"

-- | The stable error message prefix thrown when out-of-scope @Intl@ is used.
-- The conformance suite and host red-box matcher key off this exact prefix, so
-- an unsupported-feature error is identifiable rather than an anonymous
-- @TypeError@.
--
-- @since 0.20.8
unsupportedIntlSentinel :: String
unsupportedIntlSentinel = "Canopy/native: unsupported Intl feature on Hermes"

-- | The stable error message prefix thrown when an unsupported @RegExp@ feature
-- (lookbehind, Unicode-property escape) is constructed.
--
-- @since 0.20.8
unsupportedRegexSentinel :: String
unsupportedRegexSentinel = "Canopy/native: unsupported RegExp feature on Hermes"

-- | The shim source. Kept as one self-contained IIFE so it can be spliced as a
-- single statement and is trivially idempotent (re-running it is a no-op).
--
-- DESIGN NOTES (kept in sync with the Haddock above):
--
--   * Scope target: the shim binds to the same global the bundle binds
--     (@globalThis@, falling back to @global@\/@this@) — mirroring the runtime
--     preamble's own global resolution.
--   * Intl: only @DateTimeFormat().resolvedOptions().timeZone@ and the
--     no-options @DateTimeFormat().format(date)@ ISO fallback are supported.
--     Every other property/call throws 'unsupportedIntlSentinel'. When a real
--     @Intl@ is present (Node), it is left untouched.
--   * Date: @getTimezoneOffset@ is left as the engine provides, but the shim
--     records whether the engine has a non-UTC local zone so the host can warn.
--   * RegExp: both @new RegExp(...)@ and regex literals route their SOURCE
--     through a feature gate (literals can't be intercepted, so the gate is
--     also exported as @__canopy_hermes.checkRegex@ for the codegen/runtime to
--     call on dynamic sources). Unsupported features throw at the gate.
--
-- @since 0.20.8
hermesShimSource :: String
hermesShimSource =
  unlines
    [ "(function () {",
      "  var g = (typeof globalThis !== 'undefined') ? globalThis",
      "        : (typeof global !== 'undefined') ? global",
      "        : (typeof window !== 'undefined') ? window : this;",
      "  if (g." ++ shimMarkerName ++ ") { return; }",
      "  var marker = {",
      "    shimmedIntl: false,",
      "    shimmedDate: false,",
      "    hasLocalTimeZone: false,",
      "    engine: 'unknown'",
      "  };",
      "  g." ++ shimMarkerName ++ " = marker;",
      "",
      "  // ---- engine probe -------------------------------------------------",
      "  // HermesInternal is present on (and only on) Hermes.",
      "  var isHermes = (typeof g.HermesInternal !== 'undefined' && g.HermesInternal !== null);",
      "  marker.engine = isHermes ? 'hermes' : 'full';",
      "",
      "  // ---- Date timezone capability ------------------------------------",
      "  // Hermes has no tz database -> getTimezoneOffset() is always 0 (UTC).",
      "  // We can't synthesize a tz DB; we record the capability honestly so",
      "  // Time.here / Time.getZoneName degradation is observable, not silent.",
      "  try {",
      "    var off = new Date().getTimezoneOffset();",
      "    // A full engine in a non-UTC zone reports a non-zero offset; Hermes",
      "    // (or a genuinely-UTC host) reports 0. Either way this is the truth",
      "    // the host should surface rather than assume web parity.",
      "    marker.hasLocalTimeZone = (off !== 0) && !isHermes;",
      "  } catch (e) { marker.hasLocalTimeZone = false; }",
      "",
      "  // ---- Intl shim ----------------------------------------------------",
      "  // Scope: EXACTLY what canopy/time uses ->",
      "  //   Intl.DateTimeFormat().resolvedOptions().timeZone",
      "  // plus the no-options .format(date) ISO fallback. Everything else is",
      "  // an explicit, identifiable error -- never a wrong-but-plausible value.",
      "  function unsupportedIntl(what) {",
      "    return function () {",
      "      throw new Error(" ++ jsStr unsupportedIntlSentinel ++ " + ': ' + what",
      "        + ' (only DateTimeFormat().resolvedOptions().timeZone is supported on the native target)');",
      "    };",
      "  }",
      "  function bestEffortZone() {",
      "    // Hermes can't name the IANA zone; UTC is the honest, deterministic",
      "    // answer (matches getTimezoneOffset()===0). A full engine never",
      "    // reaches this branch (its native Intl is used instead).",
      "    return 'UTC';",
      "  }",
      "  function installIntlShim() {",
      "    function DateTimeFormat(locales, options) {",
      "      if (!(this instanceof DateTimeFormat)) { return new DateTimeFormat(locales, options); }",
      "      // canopy/time calls DateTimeFormat() with NO options. Any options",
      "      // object means a formatting request we deliberately do not support.",
      "      if (options && typeof options === 'object') {",
      "        for (var k in options) { if (Object.prototype.hasOwnProperty.call(options, k)) { unsupportedIntl('DateTimeFormat options')(); } }",
      "      }",
      "      this._zone = bestEffortZone();",
      "    }",
      "    DateTimeFormat.prototype.resolvedOptions = function () {",
      "      return { timeZone: this._zone, locale: 'en-US', calendar: 'gregory', numberingSystem: 'latn' };",
      "    };",
      "    DateTimeFormat.prototype.format = function (date) {",
      "      // Deterministic ISO fallback so a bare format() does not throw; any",
      "      // locale-sensitive formatting was already rejected via options above.",
      "      var d = (date == null) ? new Date() : new Date(date);",
      "      return d.toISOString();",
      "    };",
      "    DateTimeFormat.prototype.formatToParts = unsupportedIntl('DateTimeFormat.formatToParts');",
      "    var intl = {",
      "      DateTimeFormat: DateTimeFormat,",
      "      NumberFormat: function () { unsupportedIntl('NumberFormat')(); },",
      "      Collator: function () { unsupportedIntl('Collator')(); },",
      "      PluralRules: function () { unsupportedIntl('PluralRules')(); },",
      "      RelativeTimeFormat: function () { unsupportedIntl('RelativeTimeFormat')(); },",
      "      ListFormat: function () { unsupportedIntl('ListFormat')(); },",
      "      getCanonicalLocales: function () { unsupportedIntl('getCanonicalLocales')(); }",
      "    };",
      "    g.Intl = intl;",
      "    marker.shimmedIntl = true;",
      "  }",
      "  if (typeof g.Intl === 'undefined' || g.Intl === null) {",
      "    installIntlShim();",
      "  } else {",
      "    // A real Intl exists (Node baseline, or a Hermes built with intl).",
      "    // Leave it intact: the conformance baseline IS this native Intl.",
      "    marker.shimmedIntl = false;",
      "  }",
      "",
      "  // ---- RegExp feature gate -----------------------------------------",
      "  // Reject patterns Hermes cannot honour, on BOTH engines, at",
      "  // construction time -> an unsupported pattern fails in CI (Node), not",
      "  // only on a device. Detection is conservative source inspection.",
      "  function regexUnsupportedReason(source) {",
      "    if (typeof source !== 'string') { return null; }",
      "    var s = source;",
      "    // Strip escaped backslashes so we don't misread \\\\p / \\\\( as features.",
      "    var scan = s.replace(/\\\\\\\\/g, '');",
      "    // Lookbehind: (?<= ...) or (?<! ...). A named group (?<name>...) is NOT",
      "    // lookbehind and must be allowed, so require = or ! after (?< .",
      "    if (/\\(\\?<[=!]/.test(scan)) { return 'lookbehind assertion (?<=)/(?<!)'; }",
      "    // Unicode property escape \\p{...} / \\P{...}.",
      "    if (/\\\\[pP]\\{/.test(scan)) { return 'Unicode property escape \\\\p{...}'; }",
      "    return null;",
      "  }",
      "  function checkRegex(source) {",
      "    var reason = regexUnsupportedReason(source);",
      "    if (reason) {",
      "      throw new Error(" ++ jsStr unsupportedRegexSentinel ++ " + ': ' + reason",
      "        + ' in /' + source + '/');",
      "    }",
      "    return source;",
      "  }",
      "  marker.checkRegex = checkRegex;",
      "  var NativeRegExp = g.RegExp;",
      "  if (typeof NativeRegExp === 'function' && !NativeRegExp.__canopyWrapped) {",
      "    var Wrapped = function (pattern, flags) {",
      "      var src = (pattern instanceof NativeRegExp) ? pattern.source : pattern;",
      "      checkRegex(src);",
      "      // Honour both `new RegExp(...)` and `RegExp(...)` call forms.",
      "      if (!(this instanceof Wrapped)) { return new NativeRegExp(pattern, flags); }",
      "      return new NativeRegExp(pattern, flags);",
      "    };",
      "    Wrapped.prototype = NativeRegExp.prototype;",
      "    Wrapped.__canopyWrapped = true;",
      "    try { g.RegExp = Wrapped; marker.shimmedRegex = true; }",
      "    catch (e) { marker.shimmedRegex = false; }",
      "  }",
      "}());"
    ]

-- | Quote a Haskell 'String' as a single-quoted JS string literal (the strings
-- here are ASCII sentinels with no quotes/backslashes, so simple quoting is
-- sufficient and keeps the emitted preamble readable).
jsStr :: String -> String
jsStr s = "'" ++ concatMap esc s ++ "'"
  where
    esc '\'' = "\\'"
    esc '\\' = "\\\\"
    esc c = [c]

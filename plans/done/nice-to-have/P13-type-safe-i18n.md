# Plan 13: Type-Safe Internationalization

## Priority: MEDIUM — Tier 3
## Status: Library COMPLETE (10 source files, 14 test files — runtime i18n fully implemented; compile-time validation not started)
## Effort: 2-3 weeks (reduced from 3-4 — library foundation exists)
## Depends on: Stable compiler

## What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| `canopy/i18n` | stdlib package (10 source files, 14 test files) | COMPLETE — runtime i18n library |
| Translation loading | `canopy/i18n` | COMPLETE — JSON translation file parsing |
| ICU MessageFormat | `canopy/i18n` | COMPLETE — plural forms, interpolation, select |
| Intl API bindings | `canopy/i18n` | COMPLETE — number/date/currency formatting via browser Intl |
| Locale detection | `canopy/i18n` | COMPLETE — browser language detection |

The `canopy/i18n` package provides a full runtime i18n system: load translations from JSON, format messages with ICU MessageFormat (plurals, select, interpolation), format numbers/dates/currencies via the browser Intl API, and detect the user's locale.

What does NOT exist: compile-time validation. Missing translations, interpolation mismatches, and invalid plural forms are all runtime errors discovered by users, not compile errors discovered by developers.

## What Remains

### Phase 1: Translation File Parsing and Validation (Week 1)

New compiler pre-pass that reads translation JSON files and validates consistency:

- Parse ICU MessageFormat syntax from all locale files
- Extract keys, interpolation variables, and plural forms per locale
- **Missing key across locales = compile error**: if `en.json` has `"greeting"` but `nl.json` does not, the build fails
- **Interpolation variable mismatch = compile error**: if `en.json` uses `{name}` but `nl.json` uses `{nombre}`, the build fails
- **Invalid plural forms = compile error**: Arabic requires 6 CLDR plural forms; if only 3 are provided, the build fails

This validation layer sits on top of the existing `canopy/i18n` runtime. It does not replace the runtime — it ensures the runtime data is correct before the program runs.

### Phase 2: Typed Module Generation (Week 2)

Generate a typed Canopy module from translation files:

- Simple strings become `String` values: `navHome : String`
- Parameterized strings become functions: `greeting : { name : String } -> String`
- Plural forms become functions with `Int` parameter and locale-aware selection: `itemsCount : { count : Int } -> String`
- Dead translation keys (defined in JSON but never referenced in source) produce a compile warning

The generated module uses the existing `canopy/i18n` runtime underneath. The types are a compile-time wrapper ensuring correct usage.

### Phase 3: Per-Locale Code Splitting (Week 3)

- Instead of bundling all locales into one file, split translation strings per locale
- Only load the active locale's strings at runtime
- Locale change triggers re-render of affected text nodes
- Integration with CanopyKit router for locale-prefixed routes (`/en/about`, `/nl/over-ons`)

Configuration in `canopy.json`:

```json
{
  "i18n": {
    "defaultLocale": "en",
    "locales": ["en", "nl", "de", "fr"],
    "translationsDir": "translations"
  }
}
```

## Dependencies

- `canopy/i18n` (10 source files, 14 test files) — provides the runtime; compiler adds the validation layer
- Compiler pre-pass — new module for translation file parsing and module generation
- CanopyKit — optional integration for locale-based routing and code splitting

## Risks

- **ICU MessageFormat complexity**: Full ICU syntax includes `select`, `selectordinal`, and nested expressions. Start with simple interpolation and plurals (which the existing library already handles); add advanced features incrementally.
- **Bundle size**: Per-locale code splitting solves this but adds build complexity. The fallback (all locales in one bundle) works for apps with few locales.
- **Translation workflow**: Developers and translators use different tools. The compiler validates JSON files, but integrating with translation management platforms (Crowdin, Lokalise) is out of scope for this plan.

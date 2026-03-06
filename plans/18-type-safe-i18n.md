# Plan 18: Type-Safe Internationalization

## Priority: MEDIUM — Tier 3
## Effort: 3-4 weeks
## Depends on: Stable compiler

## Problem

i18n in web applications is error-prone:
- Missing translations discovered at runtime (or by users)
- Interpolation variable mismatches (`{name}` in English, `{nombre}` in Spanish)
- Plural rules wrong for specific locales
- Dead translation keys accumulate

The compiler can eliminate all of these.

## Solution: Translations as Types

### Translation Files

```json
// translations/en.json
{
  "greeting": "Hello, {name}!",
  "items.count": "{count, plural, =0 {No items} =1 {One item} other {{count} items}}",
  "nav.home": "Home",
  "nav.about": "About",
  "errors.notFound": "Page {path} was not found"
}

// translations/nl.json
{
  "greeting": "Hallo, {name}!",
  "items.count": "{count, plural, =0 {Geen items} =1 {Eén item} other {{count} items}}",
  "nav.home": "Home",
  "nav.about": "Over ons",
  "errors.notFound": "Pagina {path} is niet gevonden"
}
```

### Generated Module

The compiler reads translation files and generates a typed Canopy module:

```canopy
-- Generated: I18n.can (DO NOT EDIT)
module I18n exposing (..)

{-| Greeting message. Requires: name (String) -}
greeting : { name : String } -> String

{-| Item count with plural forms. Requires: count (Int) -}
itemsCount : { count : Int } -> String

{-| Navigation: Home -}
navHome : String

{-| Navigation: About -}
navAbout : String

{-| Error: page not found. Requires: path (String) -}
errorsNotFound : { path : String } -> String
```

### Usage

```canopy
view model =
    div []
        [ h1 [] [ text (I18n.greeting { name = model.user.name }) ]
        , p [] [ text (I18n.itemsCount { count = List.length model.items }) ]
        , nav []
            [ a [ href "/" ] [ text I18n.navHome ]
            , a [ href "/about" ] [ text I18n.navAbout ]
            ]
        ]
```

### Compile-Time Checks

**Missing translation = compile error:**
```
── MISSING TRANSLATION ──────────────── translations/nl.json

The key "errors.notFound" exists in translations/en.json but is missing
from translations/nl.json.

Add this key to translations/nl.json:

    "errors.notFound": "Pagina {path} is niet gevonden"
```

**Wrong interpolation variables = compile error:**
```
── INTERPOLATION MISMATCH ──────────────── translations/nl.json

The key "greeting" has different interpolation variables across locales:

    en.json: "Hello, {name}!"         → variables: name
    nl.json: "Hallo, {nombre}!"       → variables: nombre

All locales must use the same variable names. Did you mean {name}?
```

**Dead translation key = compile warning:**
```
── UNUSED TRANSLATION ──────────────── translations/en.json

The key "old.feature.title" is defined in translations/en.json but never
used in any Canopy source file.

Remove it or use it:

    I18n.oldFeatureTitle
```

**Plural rule validation:**
```
── INVALID PLURAL FORM ──────────────── translations/ar.json

Arabic requires 6 plural forms (zero, one, two, few, many, other) but
"items.count" only defines 3.

Missing forms: two, few, many

See CLDR plural rules: https://cldr.unicode.org/index/cldr-spec/plural-rules
```

## Implementation

### Phase 1: Translation file parsing (Week 1)
- Parse ICU MessageFormat syntax from JSON translation files
- Extract keys, interpolation variables, plural forms
- Validate consistency across locale files

### Phase 2: Module generation (Week 2)
- Generate typed Canopy module from translation files
- Simple strings → `String` values
- Parameterized strings → functions with record parameter
- Plural forms → functions with Int parameter + locale-aware selection
- Run generation as a compiler pre-pass

### Phase 3: Compile-time validation (Week 3)
- Missing keys across locales → compile error
- Interpolation variable mismatches → compile error
- Invalid plural forms → compile error (validated against CLDR)
- Unused keys → compile warning

### Phase 4: Runtime locale switching (Week 4)
- Locale selection at runtime (browser language, user preference)
- Generated module includes all locales, selects at runtime
- OR: code-split per locale (only load the active locale's strings)
- Locale change triggers re-render of affected text nodes

## Integration with CanopyKit

```canopy
-- canopy.json
{
  "i18n": {
    "defaultLocale": "en",
    "locales": ["en", "nl", "de", "fr"],
    "translationsDir": "translations"
  }
}
```

CanopyKit generates the I18n module on build and watches for translation file changes during development.

## Risks

- **ICU MessageFormat complexity**: Full ICU syntax is complex (select, selectordinal, nested). Start with simple interpolation and plurals; add advanced features later.
- **Bundle size**: Including all locales in one bundle can be large. Code splitting per locale is the solution but adds complexity.

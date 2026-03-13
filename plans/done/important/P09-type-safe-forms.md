# Plan 09: Type-Safe Forms

## Priority: CRITICAL -- Tier 1
## Effort: 3-4 weeks remaining (revised 2026-03-11, down from 4-5 weeks)
## Depends on: Plan 03 (packages -- COMPLETE)
## Completion: ~50%

---

## Status Summary (2026-03-11 deep audit)

The core form library exists as `canopy/form` (v1.0.0) with 4 source modules and 5
test modules (~6,558 lines total including tests). Applicative form composition,
validation, field state tracking, TEA integration, and headless rendering are all
implemented. What remains is compiler-level features (schema-driven code generation,
compile-time validation rules) and advanced patterns (multi-step wizards, dynamic
field lists, server-side validation).

### What EXISTS (verified via source inspection)

#### canopy/form (v1.0.0, ~6,558 lines total)

**Source modules:**

| Module | Lines | Description |
|--------|-------|-------------|
| `Form.can` | 679 | Core form type with applicative composition (`succeed`/`append`/`andThen`), `optional`, `disable`, `map`, `section`, TEA integration (`Model`/`Msg`/`init`/`update`), `fill`/`submit`, submission lifecycle (`setSubmitting`/`setSubmitted`/`setFailed`), server error injection (`addErrors`/`clearErrors`), bulk operations (`reset`/`setValues`) |
| `Form/Field.can` | 501 | Field types: text, textarea, password, email, number, checkbox, select, radio, with label/placeholder/default value configuration |
| `Form/Validate.can` | 504 | Composable validators: `required`, `requiredBool`, `minLength`, `maxLength`, `pattern` (regex), `email`, `url`, `int`, `float`, `min`, `max`, `between`, `oneOf`, `all`, `custom`, `fromMaybe`, `fromResult`, `map`, `andThen`, `mapError` |
| `Form/View.can` | 374 | Headless view helpers: renders `FilledField` metadata into accessible HTML with label/error/input association, supports custom renderers |

**Test modules (4,500 lines):**

| Test Module | Lines | Coverage |
|-------------|-------|----------|
| `Test/Form.can` | 988 | Applicative composition, fill/submit, validation strategy, optional fields |
| `Test/Field.can` | 908 | All field types, default values, configuration |
| `Test/Validate.can` | 733 | All validators, composition with andThen/oneOf/all, edge cases |
| `Test/View.can` | 1,048 | HTML rendering, accessibility attributes, error display |
| `Test/Integration.can` | 823 | End-to-end form lifecycle: init -> input -> blur -> submit |

**Key capabilities already implemented:**
- Applicative form composition: `Form.succeed Record |> Form.append field1 |> Form.append field2`
- Dependent validation via `Form.andThen` (e.g., password confirmation)
- Per-field state tracking: `pristine`, `touched`, `disabled`, `value`
- Three validation strategies: `ValidateOnSubmit`, `ValidateOnBlur`, `ValidateOnChange`
- Submission lifecycle: `Idle -> Submitting -> Submitted | Failed`
- Server-side error injection: `addErrors` merges server errors with client validation
- Headless rendering: `Form/View.can` provides accessible defaults, fully customizable
- Form sections for visual grouping
- Pre-population via `setValues`

### What does NOT work (verified)

1. **No schema-driven code generation.** The original plan called for defining a form schema and having the compiler derive UI, validation, and serialization. The current library is purely runtime -- forms are built manually with applicative combinators. No compiler plugin or code generator exists.

2. **No compile-time validation rules.** Validation rules are runtime strings (e.g., `"This field is required"`). The compiler does not verify that all fields in a record are covered by the form, or that field types match validator input types beyond normal type checking.

3. **No `Form.decodeBody` for server-side validation.** The original plan called for the same form schema to validate API request bodies in CanopyKit routes. No server-side form decoding exists.

4. **No multi-step wizard.** The original plan included `Form.wizard` for multi-step forms. Not implemented.

5. **No dynamic field lists.** The original plan included `Form.list` for repeatable field groups (e.g., add/remove line items). Not implemented.

6. **No file upload support.** No file input field type or upload progress tracking.

7. **No JSON schema generation.** The original plan called for generating JSON Schema from form definitions for API documentation. Not implemented.

8. **No `Form.matchesField` cross-field validation in Field module.** `Form.andThen` supports cross-field validation at the form level, but there is no built-in `matchesField` validator that references another field's value. The workaround exists (use `andThen` with a tuple), but it is more verbose than the plan described.

---

## Problem

Forms are the most common pain point in web development. Canopy should make forms trivial: define the schema once, get validation, accessible UI, and server-side validation automatically. The current library provides good runtime primitives but lacks the compiler-level integration that would make Canopy forms truly differentiated.

## What the Original Plan Called For vs. What Exists

| Feature | Status | Notes |
|---------|--------|-------|
| Form type with applicative composition | DONE | `Form.succeed` + `Form.append` |
| Field types (text, email, password, etc.) | DONE | `Form/Field.can` with 8+ field types |
| Built-in validators (required, minLength, email, etc.) | DONE | `Form/Validate.can` with 16+ validators |
| Validator composition (andThen, oneOf, all) | DONE | Full combinator library |
| Field state tracking (dirty/touched/pristine) | DONE | Per-field in `Form.Model` |
| Validation strategies (onSubmit/onBlur/onChange) | DONE | `ValidateOnSubmit`, `ValidateOnBlur`, `ValidateOnChange` |
| Submission lifecycle | DONE | `Idle -> Submitting -> Submitted \| Failed` |
| Server error injection | DONE | `addErrors`/`clearErrors` |
| Headless rendering with accessible HTML | DONE | `Form/View.can` |
| Schema-driven auto-generated UI | NOT DONE | Compiler-level feature |
| Compile-time field coverage checking | NOT DONE | Compiler-level feature |
| `Form.decodeBody` for server-side validation | NOT DONE | CanopyKit integration |
| Multi-step wizard (`Form.wizard`) | NOT DONE | Library extension |
| Dynamic field lists (`Form.list`) | NOT DONE | Library extension |
| Cross-field `matchesField` validator | PARTIAL | Possible via `andThen`, no built-in helper |
| File upload with progress | NOT DONE | Library extension |
| JSON schema generation | NOT DONE | Tooling feature |

---

## Remaining Work

### Phase 1: Library extensions -- dynamic fields and wizards (1 week)

**Work needed:**

1a. Dynamic field lists (3-4 days):
- Add `Form.list : FieldId -> Form a -> Form (List a)` that renders a repeatable group of fields
- Support add/remove operations via `Msg` variants
- Each list item gets a unique scoped FieldId (e.g., `items.0.name`, `items.1.name`)
- Validation runs per-item and aggregates errors

1b. Multi-step wizard (2-3 days):
- Add `Form.wizard : List (String, Form a) -> Form a` or a step-tracking wrapper
- Track current step in `Model`
- Validate per-step on "Next", full validation on final submit
- Expose `currentStep`, `canGoBack`, `canGoForward` for UI

1c. Cross-field helpers (1 day):
- Add `Field.matchesField : FieldId -> String -> Validator String String` that reads another field's value from Model
- Add `Field.afterField` for date range validation

### Phase 2: Server-side form validation (1 week)

**Work needed:**
- Add `Form.decodeBody : Form a -> Json.Decode.Value -> Result (List (FieldId, Error)) a` that validates a JSON body against the form schema
- Wire into CanopyKit API route handlers
- Same validation rules run on both client and server, ensuring consistency
- Return structured errors that the client can display per-field

### Phase 3: Schema-driven code generation (1-2 weeks)

**Work needed:**

This is the most ambitious remaining feature and could be deferred if the library-only approach proves sufficient.

3a. Record-to-form derivation (1 week):
- Compiler plugin or code generator that takes a record type alias and generates a `Form` definition with one field per record field
- Infer field types from record field types: `String` -> text input, `Bool` -> checkbox, `Int` -> number input, `Maybe a` -> optional field
- Infer basic validators from types: `String` -> `required`, `Int` -> `int` validator
- Generate accessible labels from field names (camelCase -> "Camel Case")

3b. Compile-time field coverage (3-5 days):
- Verify at compile time that a `Form RecordType` covers all fields of `RecordType`
- Emit a warning if a record field is missing from the form definition
- This could use the existing type system (applicative composition already enforces arity) or add a custom check in the canonicalization phase

### Phase 4: File upload and advanced features (optional, 3-5 days)

**Work needed:**
- File input field type in `Form/Field.can`
- Upload progress tracking via `Cmd` subscription
- File size and type validation
- Integration with `canopy/http` for multipart upload

---

## Dependencies

- **Phase 1** (library extensions): No compiler changes needed. Pure Canopy library work.
- **Phase 2** (server-side validation): Requires `canopy/json` for body decoding. May need CanopyKit route handler integration.
- **Phase 3** (code generation): Requires compiler changes. Could be a code generator tool rather than a compiler plugin to reduce risk.
- **Phase 4** (file upload): Requires `canopy/http` multipart support.

## Key Files

```
# Stdlib package (Canopy source)
packages/canopy/form/src/Form.can              -- Core form type (679 lines)
packages/canopy/form/src/Form/Field.can        -- Field types (501 lines)
packages/canopy/form/src/Form/Validate.can     -- Validators (504 lines)
packages/canopy/form/src/Form/View.can         -- Headless rendering (374 lines)
packages/canopy/form/tests/Test/Form.can       -- Form tests (988 lines)
packages/canopy/form/tests/Test/Field.can      -- Field tests (908 lines)
packages/canopy/form/tests/Test/Validate.can   -- Validator tests (733 lines)
packages/canopy/form/tests/Test/View.can       -- View tests (1,048 lines)
packages/canopy/form/tests/Test/Integration.can -- Integration tests (823 lines)
```

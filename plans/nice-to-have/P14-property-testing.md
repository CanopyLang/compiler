# Plan 14: Property-Based Testing

## Priority: MEDIUM — Tier 3
## Status: ~25% complete (test runner with fuzz support exists, auto-derivation not started)
## Effort: 3-4 weeks
## Depends on: Stable compiler

## What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| `canopy/test` | stdlib package (16 files) | COMPLETE — full test runner |
| Unit testing | `canopy/test` | COMPLETE — assertions, test grouping, runner |
| Fuzz testing | `canopy/test` | COMPLETE — basic fuzz/property support |
| Browser automation | `canopy/test` | COMPLETE — DOM testing, event simulation |
| Test CLI | `canopy test` command | COMPLETE — runs test suites |

The `canopy/test` package (16 files) provides a complete test runner with unit tests, basic fuzz testing support, assertions, and browser automation. Fuzz tests exist but require manual generator setup — the developer must write `Fuzz.string`, `Fuzz.int`, and combine them manually for custom types.

What does NOT exist: compiler-integrated property-based testing where generators and shrinkers are auto-derived from type definitions.

## What Remains

### Phase 1: Auto-Derived Generators (Weeks 1-2)

New compiler pass that generates random value generators for every type in scope:

- `String` — random UTF-8 strings with configurable length distribution
- `Int` — random integers biased toward boundary values (0, -1, 1, minBound, maxBound)
- `Float` — random floats including edge cases (0.0, -0.0, NaN, Infinity)
- `Bool` — uniform choice
- `List a` — random length with recursive element generation
- `Maybe a` — Nothing or Just with generated value
- `Result e a` — Err or Ok with generated values
- Custom union types — uniform choice among constructors, recursive generation for fields
- Records — independent generation for each field

The compiler sees the type structure and emits the generator automatically. No `Arbitrary` instances, no boilerplate.

Auto-derived shrinkers per type:
- `String` — reduce length, simplify characters toward ASCII
- `Int` — move toward 0
- `Float` — move toward 0.0, remove fractional part
- `List a` — remove elements, then shrink remaining elements
- Custom types — try each constructor (smallest first), then shrink fields
- Records — shrink each field independently

### Phase 2: Property Syntax and Runner (Week 3)

Extend the existing `canopy/test` runner with property test support:

```canopy
prop_roundtrip =
    property "JSON roundtrip" <|
        \user ->
            user
                |> User.encode
                |> Json.Decode.decodeValue User.decoder
                |> expect.equal (Ok user)
```

The `\user ->` lambda type is inferred from usage — the compiler generates a `User` because the body treats it as a `User`.

- Default: 100 random tests per property (configurable)
- On failure: shrink to minimal failing case, report both original and shrunk input
- Coverage distribution reporting: show what percentage of inputs hit each constructor/range

### Phase 3: Advanced Features (Week 4)

- **Compile-time exhaustive checking**: For small finite types (e.g., a union with 3 constructors), the compiler verifies the property for ALL values at compile time
- **Auto-generated roundtrip tests**: For any module exposing `encode`/`decode` pairs, generate roundtrip property tests automatically
- **Auto-generated law tests**: For `Eq` instances (reflexivity, symmetry, transitivity), for `Comparable` (transitivity, antisymmetry)
- **Custom generator combinators**: `Fuzz.map`, `Fuzz.andThen`, `Fuzz.frequency` for when auto-derivation is insufficient

## Dependencies

- `canopy/test` (16 files) — provides the test runner; compiler adds auto-derivation
- Compiler type information — generator derivation reads type definitions from the canonical AST
- Existing fuzz module — the auto-derived generators produce values compatible with the existing `Fuzz` API

## Risks

- **Generator quality**: Naive random generation misses edge cases. Bias toward boundary values (empty strings, zero, negative numbers, deeply nested structures) to catch real bugs.
- **Infinite types**: Recursive types (e.g., `type Tree = Leaf | Node Tree Tree`) need depth limits to prevent infinite generation. The compiler must impose configurable depth bounds.
- **Shrinking performance**: Shrinking a complex type can require many re-runs. Implement binary search shrinking where possible rather than linear.
- **Integration with existing tests**: Auto-derived generators must be compatible with the existing `canopy/test` fuzz API so developers can mix manual and auto-derived generators.

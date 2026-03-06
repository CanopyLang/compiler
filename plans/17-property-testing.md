# Plan 17: Built-in Property-Based Testing

## Priority: MEDIUM — Tier 3
## Effort: 3-4 weeks
## Depends on: Stable compiler

## Problem

No mainstream web language has property-based testing as a first-class feature. Developers write example-based tests (`expect foo(3) == 9`) that check specific cases but miss edge cases. Property-based testing generates hundreds of random inputs and verifies properties hold for ALL of them.

Elm has `elm-explorations/test` with fuzz support, but it requires manual generator setup. The compiler knows every type's structure — it should generate test data automatically.

## Solution: Compiler-Integrated PBT

### Auto-Derived Generators

The compiler generates random value generators for every type:

```canopy
-- For this type:
type alias User =
    { name : String
    , age : Int
    , role : Role
    }

type Role = Admin | Editor | Viewer

-- The compiler auto-derives:
-- Generator User (random strings for name, random ints for age, random Role)
-- Generator Role (uniform choice: Admin | Editor | Viewer)
-- Shrinking: reduce string length, reduce int toward 0, try each constructor
```

No boilerplate. No `Arbitrary` instances. The compiler sees the type, the compiler generates the data.

### Property Syntax

```canopy
module UserTest exposing (..)

import Test exposing (property, expect)

-- Property: encoding then decoding a user yields the original
prop_roundtrip =
    property "JSON roundtrip" <|
        \user ->
            user
                |> User.encode
                |> Json.Decode.decodeValue User.decoder
                |> expect.equal (Ok user)

-- Property: sorting is idempotent
prop_sort_idempotent =
    property "sorting twice equals sorting once" <|
        \(list : List Int) ->
            List.sort (List.sort list)
                |> expect.equal (List.sort list)

-- Property: reversed list has same length
prop_reverse_length =
    property "reverse preserves length" <|
        \(list : List String) ->
            List.length (List.reverse list)
                |> expect.equal (List.length list)
```

The `\user ->` lambda type is inferred — the compiler generates a `User` because the property body uses it as a `User`.

### Shrinking

When a property fails, the framework automatically finds the minimal failing case:

```
FAILED: JSON roundtrip

  Original failing input:
    { name = "x\0\255abc", age = -2147483648, role = Admin }

  Shrunk to minimal case:
    { name = "\0", age = 0, role = Admin }

  The null character in the name causes JSON encoding to fail.
```

Shrinking strategies are derived from the type:
- `String` → reduce length, simplify characters
- `Int` → move toward 0
- `List a` → remove elements, shrink remaining elements
- Custom types → try each constructor, shrink fields
- Records → shrink each field independently

### Coverage Reporting

```
Property: JSON roundtrip (100 tests)
  Distribution:
    role:
      Admin:  34%
      Editor: 31%
      Viewer: 35%
    age:
      negative: 48%
      zero:     2%
      positive: 50%
    name length:
      0:     5%
      1-10:  45%
      11-50: 40%
      51+:   10%
```

### Compile-Time Properties (Exhaustive)

For small, finite types, the compiler can verify properties at compile time:

```canopy
-- Role has only 3 constructors. The compiler checks ALL of them:
compileTimeProperty "role display is non-empty" <|
    \(role : Role) ->
        String.length (Role.toString role) > 0
-- Checked at compile time: Admin -> "Admin" (length 5 > 0) ✓
--                          Editor -> "Editor" (length 6 > 0) ✓
--                          Viewer -> "Viewer" (length 6 > 0) ✓
```

### Auto-Generated Tests

The compiler can generate standard tests from type signatures:

```canopy
-- For any module that exposes encode/decode pairs:
-- Auto-generate roundtrip property tests

-- For any Comparable instance:
-- Auto-generate transitivity, reflexivity, antisymmetry

-- For any Eq instance:
-- Auto-generate reflexivity, symmetry, transitivity
```

## Implementation

### Phase 1: Auto-derive generators (Weeks 1-2)
- New compiler pass: for each type in scope, generate a `Generator` function
- Support all standard types: Int, Float, String, Bool, List, Maybe, Result, Dict, custom types, records
- Implement shrinking strategies per type
- Hook into existing test runner

### Phase 2: Property syntax and runner (Week 3)
- `property` function that takes a generator-accepting lambda
- Test runner executes 100 tests by default (configurable)
- On failure: shrink to minimal case, report both original and shrunk
- Coverage distribution reporting

### Phase 3: Advanced features (Week 4)
- Compile-time exhaustive checking for small types
- Auto-generated roundtrip tests for encode/decode pairs
- Auto-generated law tests for type class instances
- Custom generator combinators for edge cases

## Testing

- The PBT framework must be tested with PBT (meta-testing)
- Verify that auto-derived generators produce valid values for complex types
- Verify that shrinking always produces a simpler failing case
- Verify compile-time properties match runtime verification

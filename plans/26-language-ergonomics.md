# Plan 26: Language Ergonomics (Syntax + Type System)

> **This plan has been split into two parts:**
>
> - **[Plan 26a: Quick Ergonomics](26a-quick-ergonomics.md)** — String interpolation + nested record updates (Tier 0, 1-2 weeks). Pure parser desugaring, ships immediately.
> - **[Plan 26b: Abilities + Derive](26b-abilities-derive.md)** — Type classes + JSON codec deriving (Tier 1, 8-12 weeks). Requires type system changes.
>
> This file is kept for reference. See the split plans for current details.

## Priority: HIGH — Tier 0 (26a) / Tier 1 (26b)
## Effort: 1-2 weeks (26a) + 8-12 weeks (26b)
## Depends on: Nothing (26a) / Stable compiler (26b)

## Problem

The top developer complaints about Elm (and by extension Canopy) are language-level ergonomic issues:

1. **No type classes / ad-hoc polymorphism** — Can't write generic `map`, `fold`, `encode`
2. **No JSON codec deriving** — Hundreds of lines of boilerplate per API type
3. **No string interpolation** — `"Hello, " ++ name ++ "!"` is tedious
4. **No nested record updates** — `{ model | user = { model.user | name = n } }` is invalid
5. **Comparable/appendable are compiler magic** — Can't extend them to custom types

Items 3-4 are pure desugaring (Plan 26a, Tier 0). Items 1-2 and 5 require type system work (Plan 26b, Tier 1).

These are the #1 reasons experienced developers leave Elm. They cause real boilerplate in production code.

## Solution: Four Language Extensions

### 1. Abilities (Type Classes, Roc-Style)

Roc's "Abilities" model — simpler than Haskell type classes, more powerful than Elm's magic constraints.

```canopy
-- Declare an ability:
ability Eq a where
    eq : a -> a -> Bool

-- Implement for a type:
impl Eq for User where
    eq u1 u2 = u1.id == u2.id

-- Use in generic code:
contains : Eq a => a -> List a -> Bool
contains target list =
    List.any (\item -> eq item target) list

-- Built-in abilities replace compiler magic:
-- Eq, Ord, Hash, Show, Encode, Decode
```

**Why Abilities over Type Classes:**
- No orphan instances (implementation must be in the same module as the type)
- Simpler mental model (no superclass hierarchy, no fundeps)
- Composable without monad transformer stacks
- Familiar to Rust developers (traits) and Go developers (interfaces)

### 2. Derive (Auto-Generated Implementations)

```canopy
-- Auto-derive common abilities:
type alias User =
    { id : UserId
    , name : String
    , email : Email
    , role : Role
    }
    deriving (Eq, Ord, Encode, Decode, Show)

-- The compiler generates:
-- Eq: structural equality on all fields
-- Ord: lexicographic comparison
-- Encode: JSON encoder (Json.Encode.object [...])
-- Decode: JSON decoder (Json.Decode.succeed User |> ...)
-- Show: debug string representation
```

**JSON Codec Deriving specifically:**

```canopy
type alias ApiResponse =
    { users : List User
    , totalCount : Int
    , nextPage : Maybe String
    }
    deriving (Encode, Decode)

-- Generated encoder:
-- encodeApiResponse : ApiResponse -> Json.Value
-- encodeApiResponse r =
--     Json.Encode.object
--         [ ("users", Json.Encode.list encodeUser r.users)
--         , ("totalCount", Json.Encode.int r.totalCount)
--         , ("nextPage", Json.Encode.maybe Json.Encode.string r.nextPage)
--         ]

-- Generated decoder:
-- decodeApiResponse : Json.Decoder ApiResponse
-- decodeApiResponse =
--     Json.Decode.succeed ApiResponse
--         |> Json.Decode.required "users" (Json.Decode.list decodeUser)
--         |> Json.Decode.required "totalCount" Json.Decode.int
--         |> Json.Decode.optional "nextPage" (Json.Decode.nullable Json.Decode.string) Nothing
```

This eliminates the single most tedious task in Elm development.

### 3. String Interpolation

```canopy
-- Current (verbose):
greeting = "Hello, " ++ user.name ++ "! You have " ++ String.fromInt count ++ " messages."

-- New:
greeting = "Hello, ${user.name}! You have ${String.fromInt count} messages."

-- Only expressions that return String are allowed inside ${}
-- Non-String expressions require explicit conversion (String.fromInt, etc.)
-- This is a compile-time transformation, NOT runtime template processing
```

### 4. Nested Record Updates

```canopy
-- Current (invalid in Elm):
{ model | user.name = newName }

-- New syntax option A (dot notation):
{ model | user.name = newName }
{ model | settings.theme.primaryColor = blue }

-- New syntax option B (pipeline):
model
    |> updateIn .user.name (\_ -> newName)
    |> updateIn .settings.theme.primaryColor (\_ -> blue)
```

**Implementation**: The compiler desugars nested updates into the verbose form:
```canopy
-- { model | user.name = newName } desugars to:
let oldUser = model.user
in { model | user = { oldUser | name = newName } }
```

## Implementation Phases

### Phase 1: String Interpolation (Weeks 1-2)
- Parser change: recognize `"${expr}"` syntax
- Desugar to `String.concat [...]` during canonicalization
- Validate expressions inside `${}` return `String`
- Update formatter and LSP

### Phase 2: Nested Record Updates (Weeks 3-4)
- Parser change: allow dot-separated field paths in record update syntax
- Desugar to nested let bindings during canonicalization
- Update formatter and LSP

### Phase 3: Abilities System (Weeks 5-8)
- New `ability` and `impl` keywords in parser
- Ability resolution during canonicalization
- Constraint solving in type checker (extend unification)
- Built-in abilities: Eq, Ord, Hash, Show
- Replace `comparable`, `appendable`, `number` compiler magic

### Phase 4: Deriving (Weeks 9-12)
- `deriving` clause in parser
- Code generation for each derivable ability
- JSON Encode/Decode deriving (highest priority)
- Eq, Ord, Show deriving
- Custom derive (user-defined derive macros, future work)

## Backward Compatibility

- **String interpolation**: Purely additive. Old string concatenation still works.
- **Nested records**: Purely additive. Desugars to existing valid syntax.
- **Abilities**: `comparable`, `appendable`, `number` become built-in abilities. Existing code continues to work — the magic constraints become real abilities.
- **Deriving**: Opt-in. Only types with `deriving` clause get auto-generated implementations.

## Risks

- **Abilities add complexity to type inference**: The constraint solver must handle ability constraints. This is well-studied (Haskell has done it for 30 years) but adds implementation complexity.
- **Deriving correctness**: Generated code must be correct for all type shapes (nested records, recursive types, parameterized types). Extensive testing required.
- **Community expectations**: Once abilities exist, developers will want more abilities quickly. Plan for an extensible system, not hard-coded abilities.

# Plan 26b: Abilities System + Derive

## Priority: HIGH — Tier 1
## Effort: 8-12 weeks (phased)
## Depends on: Stable compiler (Tier 0 complete)
## Split from: Plan 26 (Language Ergonomics)

## Problem

The remaining two language ergonomic issues require type system changes and are significantly more complex than string interpolation and nested records (which are now Plan 26a):

1. **No type classes / ad-hoc polymorphism** — Can't write generic `map`, `fold`, `encode`
2. **No JSON codec deriving** — Hundreds of lines of boilerplate per API type
3. **Comparable/appendable are compiler magic** — Can't extend them to custom types

These are the #1 reasons experienced developers leave Elm. They cause real boilerplate in production code.

## Solution: Abilities + Derive

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

## Implementation Phases

### Phase 1: Abilities System (Weeks 1-4)
- New `ability` and `impl` keywords in parser
- Ability resolution during canonicalization
- Constraint solving in type checker (extend unification)
- Built-in abilities: Eq, Ord, Hash, Show
- Replace `comparable`, `appendable`, `number` compiler magic

### Phase 2: Deriving (Weeks 5-8)
- `deriving` clause in parser
- Code generation for each derivable ability
- JSON Encode/Decode deriving (highest priority)
- Eq, Ord, Show deriving
- Custom derive (user-defined derive macros, future work)

### Phase 3: Polish (Weeks 9-12)
- Error messages for ability constraint failures
- LSP support (show derived implementations on hover)
- Documentation and migration guide
- Extensive testing across type shapes (nested records, recursive types, parameterized types)

## Backward Compatibility

- **Abilities**: `comparable`, `appendable`, `number` become built-in abilities. Existing code continues to work — the magic constraints become real abilities.
- **Deriving**: Opt-in. Only types with `deriving` clause get auto-generated implementations.

## Risks

- **Abilities add complexity to type inference**: The constraint solver must handle ability constraints. This is well-studied (Haskell has done it for 30 years) but adds implementation complexity.
- **Deriving correctness**: Generated code must be correct for all type shapes (nested records, recursive types, parameterized types). Extensive testing required.
- **Community expectations**: Once abilities exist, developers will want more abilities quickly. Plan for an extensible system, not hard-coded abilities.

## Definition of Done

- [ ] `ability` and `impl` keywords parse and compile
- [ ] Generic functions with ability constraints type-check correctly
- [ ] Built-in abilities replace `comparable`, `appendable`, `number`
- [ ] `deriving (Encode, Decode)` generates correct JSON codecs
- [ ] All existing tests pass (backward compatible)
- [ ] Error messages for ability-related type errors are clear and helpful

# Plan 06: Opaque Type Supertype Bounds

**Priority**: MEDIUM
**Effort**: Medium (3-4 days)
**Risk**: Low
**Audit Finding**: Canopy inherits Elm's opaque types (via module exports) but lacks supertype bounds for constrained usage

---

## Problem

Elm/Canopy supports opaque types by controlling module exports — if you don't export a constructor, the type is opaque outside the module. But there's no way to declare that an opaque type supports certain operations (comparable, appendable, etc.).

Flow solves this with `opaque type ID: string = string` — the `: string` supertype bound means external consumers know `ID` can be used wherever `string` is expected, without knowing the internal representation.

---

## Solution

Add optional supertype bounds to opaque type aliases:

```elm
module UserId exposing (UserId, create, toString)

-- New syntax: opaque type with supertype bound
type alias UserId = comparable => String

-- External code can use UserId in sets, dicts, and comparisons
-- but cannot construct or deconstruct it

create : String -> UserId
create raw = raw  -- Internal: UserId IS a String

toString : UserId -> String
toString uid = uid  -- Internal: just return it
```

---

## Implementation

### Step 1: Extend AST for Supertype Bounds

**File: `packages/canopy-core/src/AST/Source.hs`**

Add bound to type alias definition:

```haskell
data TypeAlias = TypeAlias
  { _aliasName :: !Name
  , _aliasVars :: ![Name]
  , _aliasType :: !(Located Type_)
  , _aliasBound :: !(Maybe SupertypeBound)  -- NEW
  }

-- | Supertype bound for opaque types.
data SupertypeBound
  = ComparableBound
  | AppendableBound
  | NumberBound
  | CustomBound !Name  -- e.g., `Json.Encodable`
  deriving (Eq, Show)
```

### Step 2: Extend Parser

**File: `packages/canopy-core/src/Parse/Declaration.hs`**

Parse the `=> Bound` syntax after type alias:

```haskell
-- type alias UserId = comparable => String
parseTypeAlias :: Parser TypeAlias
parseTypeAlias = do
  name <- parseName
  vars <- many parseTypeVar
  Keyword.equals
  maybeBound <- optional parseBound
  body <- parseType
  pure (TypeAlias name vars body maybeBound)

parseBound :: Parser SupertypeBound
parseBound = do
  bound <- oneOf
    [ ComparableBound <$ Keyword.comparable
    , AppendableBound <$ Keyword.appendable
    , NumberBound <$ Keyword.number
    , CustomBound <$> parseName
    ]
  Symbol.fatArrow
  pure bound
```

### Step 3: Canonicalization

**File: `packages/canopy-core/src/Canonicalize/Type.hs`**

When canonicalizing an opaque type alias (one where the constructor is not exported), record the supertype bound:

```haskell
canonicalizeAlias :: Env -> Src.TypeAlias -> Result Can.TypeAlias
canonicalizeAlias env alias = do
  canType <- canonicalizeType env (alias ^. aliasType)
  canBound <- traverse canonicalizeBound (alias ^. aliasBound)
  pure (Can.TypeAlias (alias ^. aliasName) (alias ^. aliasVars) canType canBound)
```

### Step 4: Type Checking

**File: `packages/canopy-core/src/Type/Constrain/Expression.hs`**

When generating constraints for opaque types with bounds:
- Inside the defining module: treat as the underlying type
- Outside the defining module: treat as opaque but satisfying the bound constraint

```haskell
constrainOpaque :: Region -> Can.TypeAlias -> Expected -> IO Constraint
constrainOpaque region alias expected =
  case alias ^. aliasBound of
    Nothing -> constrainPureOpaque region alias expected
    Just bound -> constrainBoundedOpaque region alias bound expected

constrainBoundedOpaque :: Region -> Can.TypeAlias -> Can.SupertypeBound -> Expected -> IO Constraint
constrainBoundedOpaque region alias bound expected = do
  -- The opaque type satisfies the bound's type class
  -- e.g., UserId with comparable bound can be used in Set, Dict, <, >, ==
  variable <- UF.fresh (descriptorFromBound bound)
  pure (CEqual region TypeClass variable expected)
```

### Step 5: Interface Encoding

**File: `packages/canopy-core/src/Canopy/Interface.hs`**

Encode the bound in module interfaces so downstream modules know what operations are available:

```haskell
data Alias = Alias
  { _aliasVars :: ![Name]
  , _aliasType :: !Can.Type  -- Hidden for opaque types
  , _aliasBound :: !(Maybe SupertypeBound)
  }
```

---

## Examples

```elm
-- Defining module
module Email exposing (Email, parse, toString)

type alias Email = comparable => String

parse : String -> Maybe Email
parse raw =
  if isValidEmail raw then Just raw else Nothing

toString : Email -> String
toString email = email

-- Consumer module
module Users exposing (..)

import Email exposing (Email)
import Set

emailSet : Set Email  -- Works because Email is comparable
emailSet = Set.fromList [email1, email2]

sortEmails : List Email -> List Email
sortEmails = List.sort  -- Works because Email is comparable

-- But this fails:
hackEmail : Email
hackEmail = "not@valid"  -- ERROR: Email is opaque, cannot construct
```

---

## Validation

```bash
make build
make test

# New test suite
stack test --ta="--pattern OpaqueBound"
```

---

## Success Criteria

- [ ] `type alias Foo = comparable => Bar` parses correctly
- [ ] Opaque types with `comparable` bound can be used in Set/Dict/sort
- [ ] Opaque types with `appendable` bound can be used with `++`
- [ ] Opaque types without bounds are fully opaque (no operations)
- [ ] Internal module sees the full underlying type
- [ ] External module sees only the bound
- [ ] 20+ tests covering all bound types and edge cases
- [ ] `make build` passes, `make test` passes

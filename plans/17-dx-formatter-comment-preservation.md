# Plan 17: Formatter Comment Preservation

**Priority:** HIGH
**Effort:** Large (3-5d)
**Risk:** High -- Requires changes to parser, AST, and formatter; high surface area for regressions

## Problem

The Canopy formatter (`Format.hs`) drops all user comments. When code is formatted, inline comments (`-- ...`), block comments (`{- ... -}`), and non-doc comments are silently discarded because the parser does not attach them to AST nodes and the formatter reconstructs source solely from the AST.

### Current Architecture

**Parser comment handling** (`/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Space.hs`):

Lines 159-170 -- `eatLineComment` simply advances the pointer past line comments without capturing them:
```haskell
eatLineComment :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# Status, Ptr Word8, Row, Col #)
eatLineComment pos end row col =
  if pos >= end then
    (# Good, pos, row, col #)
  else
    let !word = Parse.unsafeIndex pos in
    if word == 0x0A {- \n -} then
      eatSpaces (plusPtr pos 1) end (row + 1) 1
    else
      let !newPos = plusPtr pos (Parse.getCharWidth word) in
      eatLineComment newPos end row (col + 1)
```

Lines 177-234 -- `eatMultiComment` and `eatMultiCommentHelp` similarly discard block comments.

**Only doc comments are preserved** (`/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Space.hs` lines 241-272):

The `docComment` parser captures `{-| ... -}` comments as `Src.Comment` (a `Snippet` wrapper), but only for module-level and declaration-level documentation.

**Declaration-level doc comments** (`/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Declaration.hs` lines 32-36):
```haskell
data Decl
  = Value (Maybe Src.Comment) (Ann.Located Src.Value)
  | Union (Maybe Src.Comment) (Ann.Located Src.Union)
  | Alias (Maybe Src.Comment) (Ann.Located Src.Alias)
  | Port (Maybe Src.Comment) Src.Port
```

Doc comments are attached per-declaration but are **not propagated to the Source AST**. The `Module` type (`/home/quinten/fh/canopy/packages/canopy-core/src/AST/Source.hs` lines 526-538) stores them only in the `Docs` field:
```haskell
data Module = Module
  { _name :: Maybe (Ann.Located Name),
    _exports :: Ann.Located Exposing,
    _docs :: Docs,
    ...
  }
```

**The formatter** (`/home/quinten/fh/canopy/packages/canopy-core/src/Format.hs`) ignores `_docs` entirely when rendering. Lines 288-297 show that `renderDeclarations` operates on `values`, `unions`, `aliases`, `binops`, and `effects` -- none of which carry comment annotations:
```haskell
renderDeclarations config (Src.Module _ _ _ _ _ values unions aliases binops effects) =
  stackNonEmpty allDecls
  where
    allDecls =
      map (formatUnion config . Ann.toValue) unions
        ++ map (formatAlias config . Ann.toValue) aliases
        ++ map (formatInfix . Ann.toValue) binops
        ++ map (formatValue config . Ann.toValue) values
        ++ formatEffects effects
```

### What Is Lost

1. **Inline line comments** (`-- this is important`) -- discarded by `eatLineComment`
2. **Block comments** (`{- temporary disable -}`) -- discarded by `eatMultiComment`
3. **Doc comments** (`{-| documentation -}`) -- parsed but not rendered back by the formatter
4. **Trailing comments** (`x = 1 -- the initial value`) -- discarded
5. **Section separator comments** (`-- HELPERS --`) -- discarded

### Impact

This is a blocking issue for formatter adoption. Users will not use `canopy format` if it strips their comments.

## Proposed Solution: Comment Annotation Approach

A CST (Concrete Syntax Tree) approach would require a complete parser rewrite. Instead, use a **comment annotation approach**: capture comments during parsing and attach them to the nearest AST node.

### Phase 1: Capture Comments During Parsing

#### Step 1.1: Add Comment Collection to Parser State

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Primitives.hs`

Add a comment buffer to parser State (line 60-68):
```haskell
-- Current:
data State
  = State
  { _src :: ForeignPtr Word8,
    _pos :: !(Ptr Word8),
    _end :: !(Ptr Word8),
    _indent :: !Word16,
    _row :: !Row,
    _col :: !Col
  }

-- Proposed: Add pending comments accumulator
data State
  = State
  { _src :: ForeignPtr Word8,
    _pos :: !(Ptr Word8),
    _end :: !(Ptr Word8),
    _indent :: !Word16,
    _row :: !Row,
    _col :: !Col,
    _pendingComments :: ![RawComment]
  }

-- New type for raw captured comments
data RawComment = RawComment
  { _rcKind :: !CommentKind,
    _rcRegion :: !Ann.Region,
    _rcSnippet :: !Snippet
  }

data CommentKind = LineComment | BlockComment
```

**Performance concern:** Adding a list field to `State` may impact parser throughput since `State` is threaded through every combinator. Alternative: use a separate `IORef [RawComment]` alongside the parser, populated by side-effectful comment capture. This avoids enlarging the hot `State` struct.

#### Step 1.2: Modify Space Eaters to Capture Comments

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Space.hs`

`eatLineComment` (line 159) and `eatMultiComment` (line 177) must return the comment text alongside position data. The `eatSpaces` function (line 122) must accumulate captured comments.

This is the most performance-sensitive change. Options:
- **A) Return comments in unboxed tuples** -- extend the `(# Status, Ptr Word8, Row, Col #)` return to include comment data. Complex but avoids allocation in the common (no-comment) case.
- **B) Side-channel IORef** -- write comments to an IORef, avoiding any changes to the pure parsing pipeline. Simpler but introduces IO into space-eating.

Recommended: Option A with a `Maybe Snippet` in the return tuple, using `Nothing` when no comment was consumed.

### Phase 2: Annotate AST Nodes with Comments

#### Step 2.1: Extend Source AST with Comment Annotations

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/AST/Source.hs`

Add comment fields to key AST nodes. Each node gets leading and trailing comments:

```haskell
-- For Value (line 627):
data Value = Value
  { _valueLeadingComments :: ![Comment]
  , _valueName :: Ann.Located Name
  , _valueArgs :: [Pattern]
  , _valueBody :: Expr
  , _valueType :: Maybe Type
  }

-- Similarly for Union, Alias, Import, etc.
```

Alternative approach: use a separate comment map keyed by source position:
```haskell
data Module = Module
  { ...existing fields...
  , _comments :: Map Ann.Position [Comment]
  }
```

The map approach is less invasive but harder to use during formatting since you need to correlate positions.

### Phase 3: Render Comments in Formatter

#### Step 3.1: Modify Formatter to Emit Comments

**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/Format.hs`

For each rendering function (e.g., `formatValue` at line 351, `formatUnion` at line 308), prepend leading comments and append trailing comments:

```haskell
formatValue :: FormatConfig -> Src.Value -> PP.Doc
formatValue config value =
  renderLeadingComments (Src._valueLeadingComments value)
    <> typeAnnotation
    <> definition
  where
    ...existing implementation...

renderLeadingComments :: [Src.Comment] -> PP.Doc
renderLeadingComments [] = PP.empty
renderLeadingComments comments =
  PP.vcat (map renderComment comments) <> PP.line
```

## Files to Modify

| File | Change | Lines |
|------|--------|-------|
| `packages/canopy-core/src/Parse/Primitives.hs` | Add `RawComment`, `CommentKind` types; extend `State` or add IORef | 60-68 |
| `packages/canopy-core/src/Parse/Space.hs` | Capture comments in `eatLineComment`, `eatMultiComment`, `eatSpaces` | 122-234 |
| `packages/canopy-core/src/AST/Source.hs` | Add comment annotations to `Value`, `Union`, `Alias`, `Import`, `Module` | 526-627 |
| `packages/canopy-core/src/Parse/Declaration.hs` | Propagate non-doc comments to AST nodes | 32-103 |
| `packages/canopy-core/src/Parse/Module.hs` | Collect and attach comments during module parsing | 168-192 |
| `packages/canopy-core/src/Format.hs` | Emit comments before/after each declaration | 288-631 |
| `packages/canopy-core/src/Canonicalize/Module.hs` | Ignore comment annotations (pass-through) | N/A |

## Verification

```bash
# 1. All existing tests must pass (comments were not tested before)
make test

# 2. Formatter idempotency with comments
# Create test file with comments, format it, format again, diff should be empty
echo 'module Main exposing (..)

-- Section: Imports
import Html

-- | Main function
main =
    text "hello" -- greeting
' > /tmp/comment-test.can
# After implementation:
# canopy format /tmp/comment-test.can > /tmp/formatted1.can
# canopy format /tmp/formatted1.can > /tmp/formatted2.can
# diff /tmp/formatted1.can /tmp/formatted2.can  # should be empty

# 3. Golden tests for comment preservation
make test-golden

# 4. Roundtrip property test: parse -> format -> parse produces same AST
# (comments may normalize but must survive roundtrip)

# 5. Performance benchmark: format time should not regress >10%
make bench
```

## Risks and Mitigations

1. **Performance regression in parser** -- The parser is highly optimized with unboxed tuples and pointer arithmetic. Adding comment capture to `eatSpaces` could slow down every parse. Mitigation: use a side-channel accumulator, benchmark before/after.

2. **AST compatibility** -- Many modules pattern-match on `Src.Value`, `Src.Union`, etc. Adding fields will break all pattern matches. Mitigation: use a comment map on `Module` rather than per-node fields to minimize breakage.

3. **Ambiguous comment attachment** -- Comments between two declarations are ambiguous (leading comment of next decl, or trailing comment of previous?). Mitigation: follow the convention used by `elm-format` -- a comment followed by a blank line attaches to the previous node; a comment directly above code attaches to the next node.

4. **Multiline comment formatting** -- Block comments with internal formatting may be corrupted if the formatter re-indents them. Mitigation: preserve block comments as raw text without reformatting their internal content.

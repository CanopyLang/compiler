# Plan 08: Parser Recursion Depth Limits

## Priority: HIGH
## Effort: Medium (4-8 hours)
## Risk: Medium — must not break valid programs

## Problem

The expression parser has unbounded recursion in two critical paths:
1. Field access chaining (`record.field1.field2.field3...`) — unlimited depth
2. Case branch parsing — unlimited number of branches

A malicious or accidentally-generated source file with deeply nested field access (1000+ levels) or thousands of case branches can stack overflow the parser.

### Current Code (packages/canopy-core/src/Parse/Expression.hs)

```haskell
-- Lines 82-92: Unbounded recursive field access
accessible :: Parser Expr
accessible = do
  expr <- term
  fields <- many (dot *> fieldName)
  pure (foldl makeAccess expr fields)

-- Lines 449-456: Unbounded recursive case branches
chompCaseEnd :: Parser [CaseBranch]
chompCaseEnd = do
  branch <- parseCaseBranch
  rest <- optional (keyword "->" *> chompCaseEnd)
  pure (branch : fromMaybe [] rest)
```

## Implementation Plan

### Step 1: Define parser limits

**File**: `packages/canopy-core/src/Parse/Limits.hs` (NEW)

```haskell
module Parse.Limits where

-- | Maximum depth of field access chains (a.b.c.d...)
maxFieldAccessDepth :: Int
maxFieldAccessDepth = 100

-- | Maximum number of case branches in a single case expression
maxCaseBranches :: Int
maxCaseBranches = 500

-- | Maximum nesting depth for expressions
maxExpressionDepth :: Int
maxExpressionDepth = 200

-- | Maximum number of function arguments
maxFunctionArgs :: Int
maxFunctionArgs = 50

-- | Maximum number of let bindings in a single let-in
maxLetBindings :: Int
maxLetBindings = 200
```

### Step 2: Add depth-limited parser combinators

**File**: `packages/canopy-core/src/Parse/Primitives.hs`

```haskell
-- | Parse with a maximum repetition count
manyLimited :: Int -> String -> Parser a -> Parser [a]
manyLimited limit errorMsg parser = go 0 []
  where
    go n acc
      | n >= limit = Parser.addError (ParseError.TooMany errorMsg limit)
      | otherwise = optional parser >>= \case
          Nothing -> pure (reverse acc)
          Just x -> go (n + 1) (x : acc)
```

### Step 3: Apply limits to field access

**File**: `packages/canopy-core/src/Parse/Expression.hs`

```haskell
accessible :: Parser Expr
accessible = do
  expr <- term
  fields <- manyLimited Limits.maxFieldAccessDepth "field accesses" (dot *> fieldName)
  pure (foldl makeAccess expr fields)
```

### Step 4: Apply limits to case branches

```haskell
chompCaseEnd :: Parser [CaseBranch]
chompCaseEnd = manyLimited Limits.maxCaseBranches "case branches" parseCaseBranch
```

### Step 5: Add depth tracking for nested expressions

Thread a depth counter through the expression parser to prevent deeply nested expressions (e.g., `if (if (if (...) ...)`).

### Step 6: Add proper error messages

**File**: `packages/canopy-core/src/Reporting/Error/Syntax.hs`

Add `TooDeep` and `TooMany` error variants with helpful messages:

```
-- TOO MANY CASE BRANCHES -------
This case expression has 501 branches, but the maximum is 500.
Consider refactoring into smaller helper functions.
```

### Step 7: Tests

- Test that valid programs at the limit still parse
- Test that programs exceeding limits produce clear errors
- Test the error message format
- Golden test for depth-limit error messages

## Dependencies
- None

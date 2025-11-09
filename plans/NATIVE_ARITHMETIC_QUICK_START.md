# Native Arithmetic Operators - Quick Start Guide

**For Developers** | **Getting Started in 30 Minutes**

---

## Overview

This guide helps you begin implementing native arithmetic operator support in the Canopy compiler. Read this first, then refer to the comprehensive master plan for detailed specifications.

---

## What We're Building

**Goal:** Add native operator representation (`ArithBinop`, `CompBinop`, `LogicBinop`) to enable:
- Constant folding: `3 + 5` → `8` at compile time
- Algebraic simplification: `x + 0` → `x`
- Native JavaScript operators: Already achieved, but now with optimization context

**Current State:** Operators work but miss optimization opportunities
**Target State:** Operators optimized at compile time with native JS emission

---

## Prerequisites

**Required Knowledge:**
- Haskell intermediate level
- AST transformations
- Compiler pipeline basics
- Test-driven development

**Setup:**
```bash
cd /home/quinten/fh/canopy
git checkout architecture-multi-package-migration
stack build
stack test  # Verify everything works
```

---

## Architecture at a Glance

### Current Pipeline (Simplified)

```
Source Code: a + b
    ↓
Parse → Binops [(a, +), (b, end)]
    ↓
Canonicalize → Can.Binop "add" ...
    ↓
Optimize → Opt.Call (function lookup)  ← Optimization lost here!
    ↓
Generate → JS: a + b (native operator)
```

### Target Pipeline

```
Source Code: a + b
    ↓
Parse → ArithBinop Add a b  ← Detect native operator
    ↓
Canonicalize → Can.ArithBinop Add annotation a b
    ↓
Optimize → Opt.ArithBinop Add a b  ← Preserved for optimization!
    ↓
    │ Constant folding: 3 + 5 → 8
    │ Simplification: x + 0 → x
    ↓
Generate → JS: a + b (native operator)
```

---

## Key Files to Understand

**AST Definitions:**
- `/packages/canopy-core/src/AST/Source.hs` - Parsed AST
- `/packages/canopy-core/src/AST/Canonical.hs` - After name resolution
- `/packages/canopy-core/src/AST/Optimized.hs` - Before code generation

**Transformation Pipeline:**
- `/packages/canopy-core/src/Parse/Expression.hs` - Parser
- `/packages/canopy-core/src/Canonicalize/Expression.hs` - Canonicalization
- `/packages/canopy-core/src/Optimize/Expression.hs` - Optimization
- `/packages/canopy-core/src/Generate/JavaScript/Expression.hs` - Code generation

**Critical Insight:** Code generator already emits native operators at line 527-566 in `Generate/JavaScript/Expression.hs`!

---

## Phase 1: First Week Implementation

### Day 1: Setup and Exploration

**Morning: Read and Understand**
```bash
# Read this quick start (you're doing it!)
# Skim the master plan executive summary
less plans/NATIVE_ARITHMETIC_OPERATORS_MASTER_PLAN.md

# Explore AST structure
less packages/canopy-core/src/AST/Source.hs
less packages/canopy-core/src/AST/Canonical.hs
less packages/canopy-core/src/AST/Optimized.hs
```

**Afternoon: Run Tests and Verify**
```bash
# Run full test suite
stack test

# Run AST-specific tests
stack test --ta="--pattern AST"

# Check test coverage
stack test --coverage
```

---

### Day 2-3: Add AST Types

**Task:** Add native operator types to all three AST modules.

**Step 1: Source AST** (`AST/Source.hs`)

Add after line 167:
```haskell
-- | Native arithmetic operator classification.
--
-- Identifies operators that should compile to native JavaScript
-- arithmetic operations for optimal performance.
--
-- @since 0.19.2
data ArithOp
  = Add    -- ^ Addition operator (+)
  | Sub    -- ^ Subtraction operator (-)
  | Mul    -- ^ Multiplication operator (*)
  | Div    -- ^ Division operator (/)
  | IntDiv -- ^ Integer division operator (//)
  | Mod    -- ^ Modulo operator (%)
  | Pow    -- ^ Exponentiation operator (^)
  deriving (Eq, Show)

-- | Comparison operator classification.
data CompOp
  = Eq  -- ^ Equality (==)
  | Ne  -- ^ Inequality (/=)
  | Lt  -- ^ Less than (<)
  | Le  -- ^ Less than or equal (<=)
  | Gt  -- ^ Greater than (>)
  | Ge  -- ^ Greater than or equal (>=)
  deriving (Eq, Show)

-- | Logical operator classification.
data LogicOp
  = And -- ^ Logical AND (&&)
  | Or  -- ^ Logical OR (||)
  deriving (Eq, Show)
```

Add to `Expr_` after `Binops`:
```haskell
  | ArithBinop ArithOp Expr Expr   -- NEW: Native arithmetic
  | CompBinop CompOp Expr Expr     -- NEW: Native comparison
  | LogicBinop LogicOp Expr Expr   -- NEW: Native logical
```

**Step 2: Canonical AST** (`AST/Canonical.hs`)

Add similar types with `Annotation`:
```haskell
data ArithOp
  = Add | Sub | Mul | Div | IntDiv | Mod | Pow
  deriving (Eq, Show)

-- Binary instance for serialization
instance Binary ArithOp where
  put op = putWord8 (case op of
    Add -> 0; Sub -> 1; Mul -> 2; Div -> 3
    IntDiv -> 4; Mod -> 5; Pow -> 6)
  get = do
    word <- getWord8
    case word of
      0 -> return Add; 1 -> return Sub; 2 -> return Mul
      3 -> return Div; 4 -> return IntDiv; 5 -> return Mod
      6 -> return Pow
      _ -> fail "binary encoding of ArithOp corrupted"
```

Add to `Expr_`:
```haskell
  | ArithBinop ArithOp Annotation Expr Expr  -- NEW
  | CompBinop CompOp Annotation Expr Expr    -- NEW
  | LogicBinop LogicOp Annotation Expr Expr  -- NEW
```

**Step 3: Optimized AST** (`AST/Optimized.hs`)

Similar to Canonical, but without `Annotation`.

**Step 4: Write Tests**

Create `packages/canopy-core/test/Unit/AST/SourceArithmeticTest.hs`:
```haskell
module Unit.AST.SourceArithmeticTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified AST.Source as Src

tests :: TestTree
tests = testGroup "AST.Source Arithmetic"
  [ testGroup "ArithOp"
      [ testCase "Add operator" $
          Src.Add @?= Src.Add
      , testCase "Show Add" $
          show Src.Add @?= "Add"
      ]
  , testGroup "CompOp"
      [ testCase "Eq operator" $
          Src.Eq @?= Src.Eq
      ]
  ]
```

**Verify:**
```bash
stack build
stack test --ta="--pattern SourceArithmetic"
```

---

### Day 4-5: Binary Instances and Cleanup

**Task:** Implement Binary instances for all operator types.

**Add to Canonical AST:**
```haskell
instance Binary CompOp where
  put op = putWord8 (case op of
    Eq -> 0; Ne -> 1; Lt -> 2; Le -> 3; Gt -> 4; Ge -> 5)
  get = do
    word <- getWord8
    case word of
      0 -> return Eq; 1 -> return Ne; 2 -> return Lt
      3 -> return Le; 4 -> return Gt; 5 -> return Ge
      _ -> fail "binary encoding of CompOp corrupted"

instance Binary LogicOp where
  put op = putWord8 (case op of
    And -> 0; Or -> 1)
  get = do
    word <- getWord8
    case word of
      0 -> return And; 1 -> return Or
      _ -> fail "binary encoding of LogicOp corrupted"
```

**Test Binary Serialization:**
```haskell
testBinarySerialization :: TestTree
testBinarySerialization = testGroup "Binary serialization"
  [ testCase "ArithOp roundtrip" $
      let op = Can.Add
      in Binary.decode (Binary.encode op) @?= op
  , testCase "All ArithOps roundtrip" $
      let ops = [Can.Add, Can.Sub, Can.Mul, Can.Div, Can.IntDiv, Can.Mod, Can.Pow]
      in map (Binary.decode . Binary.encode) ops @?= ops
  ]
```

**Verify:**
```bash
stack build
stack test
stack test --coverage
```

---

## Common Patterns and Helpers

### Writing Tests (CLAUDE.md Compliant)

**DO:**
```haskell
-- Test exact string values
testCase "Name.toChars for add" $
  Name.toChars Name.add @?= "+"

-- Test actual behavior
testCase "ArithOp binary roundtrip" $
  Binary.decode (Binary.encode Src.Add) @?= Src.Add
```

**DON'T:**
```haskell
-- No mock functions that always return True
isValid _ = True  -- BAD!

-- No reflexive equality tests
testCase "add equals itself" $
  Name.add @?= Name.add  -- Useless!
```

### Function Size Limits

**Keep functions ≤ 15 lines:**
```haskell
-- GOOD: Within limits
canonicalizeArithBinop env region op left right =
  buildCanonical op
    <$> canonicalize env left
    <*> canonicalize env right
  where
    buildCanonical opType leftExpr rightExpr =
      Can.ArithBinop opType (inferType opType) leftExpr rightExpr

-- BAD: Too long, extract helper
badLongFunction = do
  -- 20+ lines of logic
  -- Extract to multiple functions!
```

### Import Style

**Always: Types unqualified, functions qualified**
```haskell
import Data.Map (Map)
import qualified Data.Map as Map

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt

-- Usage
optimize :: Can.Expr -> Opt.Expr
optimize expr = Map.lookup key processedMap
```

---

## Next Steps After Phase 1

Once Phase 1 (Foundation) is complete:

1. **Phase 2: Parser Integration**
   - Implement `isArithOp :: Name -> Maybe Src.ArithOp`
   - Modify parser to detect and build native operator nodes
   - Write parser tests

2. **Phase 3: Canonicalization**
   - Implement `canonicalizeArithBinop`
   - Integrate with type inference
   - Write canonicalization tests

3. **Phase 4: Optimization**
   - Preserve operators through optimization
   - Implement constant folding
   - Implement algebraic simplification

4. **Phase 5: Code Generation**
   - Generate native JavaScript operators
   - Handle special cases (intDiv, modulo)
   - Write integration tests

**Full roadmap in:** `plans/NATIVE_ARITHMETIC_OPERATORS_MASTER_PLAN.md`

---

## Testing Guidelines

### Run Tests Frequently

```bash
# Quick test (while developing)
stack test --file-watch

# Full test suite
stack test

# Specific pattern
stack test --ta="--pattern Arithmetic"

# With coverage
stack test --coverage
```

### Test Coverage Requirements

- **Minimum:** 80% statement coverage
- **Target:** 85% statement coverage
- **Must:** 100% function coverage

### Test Types Required

1. **Unit Tests:** Test individual functions
2. **Property Tests:** Test invariants and laws
3. **Integration Tests:** Test complete pipeline
4. **Golden Tests:** Test generated output

---

## Debugging Tips

### Common Issues

**Issue: Type errors in AST construction**
```bash
# Solution: Check type annotations match
# Canonical AST requires Annotation, Optimized does not
```

**Issue: Binary serialization fails**
```bash
# Solution: Verify Binary instance covers all constructors
# Check getWord8 matches putWord8
```

**Issue: Tests fail after adding constructors**
```bash
# Solution: Update pattern matches to handle new constructors
# Search for: grep -r "Binop" packages/canopy-core/src/
```

### Useful Commands

```bash
# Find all occurrences of Binop
grep -r "Binop" packages/canopy-core/src/

# Find all test files
find packages/canopy-core/test -name "*Test.hs"

# Check test coverage
stack test --coverage
stack hpc report --all

# Run with profiling
stack build --profile
stack test --profile
```

---

## Key Principles

### Follow CLAUDE.md Standards

1. **Function Size:** ≤ 15 lines
2. **Parameters:** ≤ 4 per function
3. **Branching:** ≤ 4 branching points
4. **Documentation:** Complete Haddock docs
5. **Testing:** ≥ 80% coverage
6. **Imports:** Types unqualified, functions qualified
7. **Lenses:** Use for record access/updates

### Don't Simplify to Get Around Issues

From CLAUDE.md:
> NEVER SIMPLIFY Cases to get around: Investigate issues properly, by adding debug logging or testing scripts, but do not simplify a implementation because its easier.

**Example:**
```haskell
-- BAD: Simplifying to avoid dealing with complexity
optimize expr = Opt.Call defaultFunc [left, right]

-- GOOD: Handle properly
optimize expr = case expr of
  ArithOp op -> optimizeArithOp op left right
  CompOp op -> optimizeCompOp op left right
  LogicOp op -> optimizeLogicOp op left right
```

---

## Resources

**Essential Reading:**
- `plans/NATIVE_ARITHMETIC_OPERATORS_MASTER_PLAN.md` - Complete specification
- `CLAUDE.md` - Coding standards (mandatory)
- `plans/NATIVE_ARITHMETIC_OPERATORS_ARCHITECTURE.md` - Detailed architecture

**Reference Documents:**
- `plans/ANALYST_TECHNICAL_REPORT.md` - Performance analysis
- `plans/OPTIMIZER_ARITHMETIC_ANALYSIS.md` - Optimization opportunities

**Codebase Documentation:**
- AST module Haddock docs
- Existing test files for patterns
- Parse/Expression.hs for parser patterns

---

## Getting Help

**If you're stuck:**

1. **Check the master plan:** Detailed specifications for every phase
2. **Look at existing code:** Similar patterns in canonicalization
3. **Run tests:** They often reveal what's expected
4. **Check CLAUDE.md:** Standards and best practices

**Common Questions:**

**Q: Which AST module should I modify first?**
A: Start with Source, then Canonical, then Optimized (in that order).

**Q: How do I know if my tests are sufficient?**
A: Run `stack test --coverage` - aim for ≥80% coverage.

**Q: What if I need more than 4 parameters?**
A: Use a record type with lenses (see CLAUDE.md for examples).

**Q: Can I skip documentation for internal functions?**
A: No. CLAUDE.md requires Haddock docs for all public functions.

---

## Summary Checklist

**Phase 1 Complete When:**
- [ ] ArithOp, CompOp, LogicOp types added to all three AST modules
- [ ] Binary instances implemented and tested
- [ ] All new constructors added to Expr_ types
- [ ] Unit tests written and passing (≥80% coverage)
- [ ] Documentation complete (Haddock)
- [ ] Code follows CLAUDE.md standards
- [ ] No breaking changes to existing code
- [ ] Full test suite passes

**Time Estimate:** 3-5 days

**Next Phase:** Parser Integration (Week 2)

---

**Good luck!** You're building a significant performance optimization for the Canopy compiler. Take your time, follow the standards, and write comprehensive tests.

**Remember:** Quality over speed. It's better to take an extra day and do it right than rush and introduce bugs.

---

**Quick Start Guide Version:** 1.0
**Last Updated:** 2025-10-28
**Prepared By:** DOCUMENTER Agent

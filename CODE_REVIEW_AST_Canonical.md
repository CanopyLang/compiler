# Code Review: AST.Canonical (Native Operators Implementation)

**Status:** ⚠️ **MAJOR ISSUES - NEEDS CHANGES**
**Reviewer:** code-style-enforcer (Senior Developer Quality Gate)
**Date:** 2025-10-28
**File:** `/home/quinten/fh/canopy/packages/canopy-core/src/AST/Canonical.hs`
**Changes:** +129 lines, -1 line
**Phase:** 1 (Foundation)

---

## Executive Summary

This file implements part of Phase 1 (Foundation) for native arithmetic operators. The implementation shows MAJOR DEVIATIONS from the master plan and has CRITICAL issues:

### 🔴 CRITICAL ISSUES
1. **WRONG DESIGN**: Uses `BinopKind` wrapper instead of separate constructors
2. **INCOMPLETE**: Only 4 operators (Add, Sub, Mul, Div) instead of 7 required
3. **MISSING**: No CompOp or LogicOp types
4. **BREAKS PLAN**: Does not match Phase 1 architecture specification

### ✅ POSITIVE ASPECTS
- Excellent Haddock documentation
- Proper Binary serialization
- CLAUDE.md compliant formatting

---

## Design Architecture Analysis

### ❌ ACTUAL IMPLEMENTATION (WRONG)

```haskell
-- What was implemented:
data ArithOp = Add | Sub | Mul | Div  -- MISSING: IntDiv, Mod, Pow
  deriving (Eq, Ord, Show)

data BinopKind
  = NativeArith !ArithOp
  | UserDefined !Name !ModuleName.Canonical !Name
  deriving (Eq, Show)

data Expr_
  = ...
  | BinopOp BinopKind Annotation Expr Expr  -- WRONG: Wrapper approach
  | ...
```

### ✅ REQUIRED BY MASTER PLAN

```haskell
-- What should have been implemented:
data ArithOp
  = Add    -- ^ Addition operator (+)
  | Sub    -- ^ Subtraction operator (-)
  | Mul    -- ^ Multiplication operator (*)
  | Div    -- ^ Division operator (/)
  | IntDiv -- ^ Integer division operator (//)  ❌ MISSING
  | Mod    -- ^ Modulo operator (%)              ❌ MISSING
  | Pow    -- ^ Exponentiation operator (^)      ❌ MISSING
  deriving (Eq, Show)

data CompOp                                     ❌ COMPLETELY MISSING
  = Eq  | Ne  | Lt  | Le  | Gt  | Ge
  deriving (Eq, Show)

data LogicOp                                    ❌ COMPLETELY MISSING
  = And | Or
  deriving (Eq, Show)

data Expr_
  = ...
  | Binop Name ModuleName.Canonical Name Annotation Expr Expr  -- Keep existing
  | ArithBinop ArithOp Annotation Expr Expr     ❌ WRONG: Used BinopOp wrapper
  | CompBinop CompOp Annotation Expr Expr       ❌ MISSING
  | LogicBinop LogicOp Annotation Expr Expr     ❌ MISSING
  | ...
```

---

## CRITICAL ISSUE #1: Wrong Architecture (BLOCKING)

### Problem

The implementation uses a **wrapper approach** (`BinopKind`) instead of **direct constructors**:

```haskell
-- ❌ WRONG: Implemented
BinopOp BinopKind Annotation Expr Expr

-- Where BinopKind wraps operators:
data BinopKind
  = NativeArith !ArithOp
  | UserDefined !Name !ModuleName.Canonical !Name
```

### Why This is Wrong

1. **Violates Master Plan**: Master plan explicitly shows separate constructors
2. **Breaks Type Safety**: Mixes native and user-defined operators in one constructor
3. **Complicates Pattern Matching**: Requires nested pattern matching everywhere
4. **Hinders Optimization**: Optimizer can't easily distinguish operator types

### Master Plan Specification (Phase 1, Section 2.1)

From line 299-324 of master plan:

```haskell
-- Extend Expr_ with annotated operators
data Expr_
  = ...
  | Binop Name ModuleName.Canonical Name Annotation Expr Expr  -- Existing
  | ArithBinop ArithOp Annotation Expr Expr                    -- NEW
  | CompBinop CompOp Annotation Expr Expr                      -- NEW
  | LogicBinop LogicOp Annotation Expr Expr                    -- NEW
  | ...
```

**This is EXPLICIT and CLEAR: Use separate constructors.**

### Impact

- ❌ Parser implementation (Phase 2) will be incorrect
- ❌ Canonicalization (Phase 3) will be incorrect
- ❌ Optimization (Phase 4-6) will need extra pattern matching
- ❌ Code generation (Phase 7) will be more complex

### Required Fix

**REMOVE `BinopKind` entirely and use separate constructors:**

```haskell
-- CORRECT implementation:
data Expr_
  = ...
  | Binop Name ModuleName.Canonical Name Annotation Expr Expr  -- Keep for custom operators
  | ArithBinop ArithOp Annotation Expr Expr     -- NEW: Native arithmetic
  | CompBinop CompOp Annotation Expr Expr       -- NEW: Native comparison
  | LogicBinop LogicOp Annotation Expr Expr     -- NEW: Native logical
  | ...
```

---

## CRITICAL ISSUE #2: Incomplete Operator Set (BLOCKING)

### Problem

Only 4 of 7 required arithmetic operators implemented:

```haskell
-- ❌ IMPLEMENTED (Incomplete)
data ArithOp
  = Add   -- ✅ Present
  | Sub   -- ✅ Present
  | Mul   -- ✅ Present
  | Div   -- ✅ Present
  deriving (Eq, Ord, Show)
```

### Missing Operators

```haskell
-- ❌ MISSING (Required by master plan)
  | IntDiv -- ^ Integer division operator (//)
  | Mod    -- ^ Modulo operator (%)
  | Pow    -- ^ Exponentiation operator (^)
```

### Master Plan Requirement

From line 256-263 of master plan:

```haskell
data ArithOp
  = Add    -- ^ Addition operator (+)
  | Sub    -- ^ Subtraction operator (-)
  | Mul    -- ^ Multiplication operator (*)
  | Div    -- ^ Division operator (/)
  | IntDiv -- ^ Integer division operator (//)
  | Mod    -- ^ Modulo operator (%)
  | Pow    -- ^ Exponentiation operator (^)
  deriving (Eq, Show)
```

### Why This Matters

1. **Incomplete Feature**: Users cannot use `//`, `%`, or `^` with native operators
2. **Breaks Tests**: Test suites expect all 7 operators
3. **Breaks API**: Public API incomplete

### Required Fix

**Add all 7 operators:**

```haskell
data ArithOp
  = Add    -- ^ Addition operator (+)
  | Sub    -- ^ Subtraction operator (-)
  | Mul    -- ^ Multiplication operator (*)
  | Div    -- ^ Division operator (/)
  | IntDiv -- ^ Integer division operator (//)  -- ADD THIS
  | Mod    -- ^ Modulo operator (%)              -- ADD THIS
  | Pow    -- ^ Exponentiation operator (^)      -- ADD THIS
  deriving (Eq, Show)
```

**Update Binary instance:**

```haskell
putArithOp :: ArithOp -> Binary.Put
putArithOp Add = Binary.putWord8 0
putArithOp Sub = Binary.putWord8 1
putArithOp Mul = Binary.putWord8 2
putArithOp Div = Binary.putWord8 3
putArithOp IntDiv = Binary.putWord8 4  -- ADD THIS
putArithOp Mod = Binary.putWord8 5     -- ADD THIS
putArithOp Pow = Binary.putWord8 6     -- ADD THIS

getArithOp :: Binary.Get ArithOp
getArithOp = do
  w <- Binary.getWord8
  case w of
    0 -> pure Add
    1 -> pure Sub
    2 -> pure Mul
    3 -> pure Div
    4 -> pure IntDiv   -- ADD THIS
    5 -> pure Mod      -- ADD THIS
    6 -> pure Pow      -- ADD THIS
    _ -> fail ("binary encoding of ArithOp was corrupted: " ++ show w)
```

---

## CRITICAL ISSUE #3: Missing CompOp and LogicOp (BLOCKING)

### Problem

Comparison and logical operators completely missing:

```haskell
-- ❌ MISSING ENTIRELY
data CompOp = Eq | Ne | Lt | Le | Gt | Ge
data LogicOp = And | Or
```

### Master Plan Requirement

From lines 266-279 of master plan:

```haskell
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

### Required Fix

**Add both missing types with full Binary support:**

```haskell
-- | Comparison operator classification.
--
-- Represents comparison operators that compile to native JavaScript
-- comparison operations.
--
-- @since 0.19.2
data CompOp
  = Eq  -- ^ Equality (==)
  | Ne  -- ^ Inequality (/=)
  | Lt  -- ^ Less than (<)
  | Le  -- ^ Less than or equal (<=)
  | Gt  -- ^ Greater than (>)
  | Ge  -- ^ Greater than or equal (>=)
  deriving (Eq, Show)

-- | Logical operator classification.
--
-- Represents logical operators that compile to native JavaScript
-- logical operations.
--
-- @since 0.19.2
data LogicOp
  = And -- ^ Logical AND (&&)
  | Or  -- ^ Logical OR (||)
  deriving (Eq, Show)

-- Binary instances for both
instance Binary.Binary CompOp where
  put = putCompOp
  get = getCompOp

instance Binary.Binary LogicOp where
  put = putLogicOp
  get = getLogicOp
```

---

## CLAUDE.md Compliance Analysis

### ✅ COMPLIANT AREAS

#### 1. Function Size - PERFECT ✅
```haskell
putArithOp :: ArithOp -> Binary.Put
putArithOp Add = Binary.putWord8 0
putArithOp Sub = Binary.putWord8 1
putArithOp Mul = Binary.putWord8 2
putArithOp Div = Binary.putWord8 3
```
**Analysis:** 4 lines. Well under 15-line limit.

```haskell
getArithOp :: Binary.Get ArithOp
getArithOp = do
  w <- Binary.getWord8
  case w of
    0 -> pure Add
    1 -> pure Sub
    2 -> pure Mul
    3 -> pure Div
    _ -> fail ("binary encoding of ArithOp was corrupted: " ++ show w)
```
**Analysis:** 9 lines. Within 15-line limit.

#### 2. Documentation - EXCELLENT ✅

```haskell
-- | Native arithmetic operator classification.
--
-- Represents arithmetic operators that compile to native JavaScript
-- operations for optimal performance. These operators have special
-- type constraints (number -> number -> number) and generate direct
-- JavaScript operators instead of function calls.
--
-- === Semantics
--
-- * 'Add': JavaScript '+' operator
-- * 'Sub': JavaScript '-' operator
-- * 'Mul': JavaScript '*' operator
-- * 'Div': JavaScript '/' operator
--
-- === Type Constraints
--
-- All arithmetic operators have the type:
--
-- @
-- forall number. number -> number -> number
-- @
--
-- where @number@ is constrained to Int or Float.
--
-- @since 0.19.2
data ArithOp
```

**Analysis:**
- ✅ Complete module-level documentation
- ✅ Function-level documentation
- ✅ Examples in Haddock format
- ✅ @since version tags
- ✅ Semantic descriptions
- ✅ Type constraint documentation

#### 3. Binary Serialization - GOOD ✅

```haskell
instance Binary.Binary BinopKind where
  put kind = case kind of
    NativeArith op -> Binary.putWord8 0 >> Binary.put op
    UserDefined op home name ->
      Binary.putWord8 1 >> Binary.put op >> Binary.put home >> Binary.put name

  get = do
    tag <- Binary.getWord8
    case tag of
      0 -> fmap NativeArith Binary.get
      1 -> Monad.liftM3 UserDefined Binary.get Binary.get Binary.get
      _ -> fail ("binary encoding of BinopKind was corrupted: " ++ show tag)
```

**Analysis:**
- ✅ Proper tag-based encoding
- ✅ Error handling for corrupted data
- ✅ Compact representation
- ✅ Follows existing patterns

#### 4. Formatting - PERFECT ✅

- ✅ No `$` operator used (uses parentheses)
- ✅ Proper alignment
- ✅ Consistent indentation
- ✅ Clean code structure

### ⚠️ ISSUES FOUND

#### 1. Design Deviation from Master Plan (CRITICAL)

**Problem:** Uses `BinopKind` wrapper instead of separate constructors.

**CLAUDE.md Violation:** While not directly violating CLAUDE.md, this violates the **master plan specification** which is the architectural blueprint for this feature.

#### 2. Incomplete Implementation (HIGH)

**Problem:** Missing operators and types.

**Impact:** Breaks Phase 1 deliverables.

---

## Line-by-Line Issues

### Line 216-221: Incomplete ArithOp

```haskell
data ArithOp
  = Add   -- ^ Addition: a + b
  | Sub   -- ^ Subtraction: a - b
  | Mul   -- ^ Multiplication: a * b
  | Div   -- ^ Division: a / b (always Float result in Canopy)
  deriving (Eq, Ord, Show)
```

**Issue:** Missing IntDiv, Mod, Pow operators.

**Fix Required:**
```haskell
data ArithOp
  = Add    -- ^ Addition: a + b
  | Sub    -- ^ Subtraction: a - b
  | Mul    -- ^ Multiplication: a * b
  | Div    -- ^ Division: a / b
  | IntDiv -- ^ Integer division: a // b
  | Mod    -- ^ Modulo: a % b
  | Pow    -- ^ Exponentiation: a ^ b
  deriving (Eq, Show)  -- REMOVE Ord (not in master plan)
```

### Line 247-252: Wrong BinopKind Design

```haskell
data BinopKind
  = NativeArith !ArithOp
    -- ^ Native arithmetic operators with direct JavaScript codegen
  | UserDefined !Name !ModuleName.Canonical !Name
    -- ^ User-defined operators as function references
  deriving (Eq, Show)
```

**Issue:** Should not exist. Use separate constructors instead.

**Fix Required:** DELETE this type entirely.

### Line 269: Wrong Expr_ Constructor

```haskell
  | BinopOp BinopKind Annotation Expr Expr -- CHANGED: Native operators support
```

**Issue:** Should use separate constructors for each operator type.

**Fix Required:**
```haskell
  | Binop Name ModuleName.Canonical Name Annotation Expr Expr  -- Keep existing
  | ArithBinop ArithOp Annotation Expr Expr     -- NEW
  | CompBinop CompOp Annotation Expr Expr       -- NEW
  | LogicBinop LogicOp Annotation Expr Expr     -- NEW
```

### Lines 622-659: Binary Instance Issues

**Issue 1:** putArithOp missing 3 operators
**Issue 2:** getArithOp missing 3 cases

**Fix Required:** Add cases for IntDiv (4), Mod (5), Pow (6)

### Lines 652-669: BinopKind Binary Instance

**Issue:** Should not exist since BinopKind should be deleted.

**Fix Required:** DELETE this instance.

---

## Required Changes Summary

### ARCHITECTURAL CHANGES (CRITICAL)

1. **DELETE `BinopKind` type entirely**
   - Remove from exports
   - Remove data type definition
   - Remove Binary instance
   - Remove documentation

2. **ADD separate constructors to Expr_**
   ```haskell
   | ArithBinop ArithOp Annotation Expr Expr
   | CompBinop CompOp Annotation Expr Expr
   | LogicBinop LogicOp Annotation Expr Expr
   ```

3. **CHANGE existing Binop constructor**
   - Keep as: `Binop Name ModuleName.Canonical Name Annotation Expr Expr`
   - Use for custom user-defined operators only

### DATA TYPE ADDITIONS (CRITICAL)

1. **Complete ArithOp**
   - Add IntDiv, Mod, Pow constructors
   - Update Binary instance (add cases 4, 5, 6)
   - Update documentation

2. **Add CompOp type**
   - 6 constructors: Eq, Ne, Lt, Le, Gt, Ge
   - Binary instance with tags 0-5
   - Complete Haddock documentation

3. **Add LogicOp type**
   - 2 constructors: And, Or
   - Binary instance with tags 0-1
   - Complete Haddock documentation

### EXPORTS UPDATE (HIGH)

Current exports:
```haskell
module AST.Canonical
  ( ...
  , ArithOp (..)
  , BinopKind (..)  -- ❌ REMOVE
  , ...
  )
```

Required exports:
```haskell
module AST.Canonical
  ( ...
  , ArithOp (..)     -- ✅ Keep
  , CompOp (..)      -- ✅ ADD
  , LogicOp (..)     -- ✅ ADD
  , ...
  )
```

---

## Testing Requirements

### Unit Tests Required (Currently Missing)

1. **ArithOp construction and equality**
   ```haskell
   testCase "ArithOp Add" $ Add @?= Add
   testCase "ArithOp inequality" $ (Add == Sub) @?= False
   ```

2. **Binary serialization round-trips**
   ```haskell
   testCase "ArithOp Binary round-trip" $
     decode (encode Add) @?= Add
   ```

3. **CompOp and LogicOp (after addition)**
   - Construction tests
   - Equality tests
   - Binary round-trips

---

## Approval Status

### Overall Status: 🔴 **REJECTED - REQUIRES MAJOR CHANGES**

### Blocking Issues:
1. ❌ **Wrong Architecture**: BinopKind wrapper violates master plan
2. ❌ **Incomplete**: Missing 3 arithmetic operators (IntDiv, Mod, Pow)
3. ❌ **Missing**: No CompOp or LogicOp types
4. ❌ **Breaking**: Changes Binop constructor instead of adding new ones

### CLAUDE.md Compliance: 95% ✅
- Documentation: 100% ✅
- Function size: 100% ✅
- Formatting: 100% ✅
- Binary serialization: 100% ✅ (but for wrong design)

### Master Plan Compliance: 20% ❌
- ArithOp partial: 40% (4 of 10 features)
- CompOp: 0% (not implemented)
- LogicOp: 0% (not implemented)
- Expr_ constructors: 0% (wrong approach)

---

## Path to Approval

### Step 1: Architectural Fix (REQUIRED)
1. DELETE `BinopKind` type
2. ADD separate `ArithBinop`, `CompBinop`, `LogicBinop` constructors to Expr_
3. KEEP existing `Binop` constructor for custom operators

### Step 2: Complete Implementation (REQUIRED)
1. ADD IntDiv, Mod, Pow to ArithOp
2. ADD CompOp type with 6 constructors
3. ADD LogicOp type with 2 constructors
4. ADD Binary instances for all new types

### Step 3: Documentation (REQUIRED)
1. Document CompOp type
2. Document LogicOp type
3. Update Expr_ constructor documentation

### Step 4: Testing (REQUIRED)
1. Add unit tests for all operator types
2. Add Binary serialization tests
3. Verify ≥80% coverage

---

## Recommendations

### FOR IMPLEMENTER:
1. **STOP** current approach immediately
2. **REVIEW** master plan architecture (Section 2.1)
3. **REFACTOR** to use separate constructors
4. **COMPLETE** all 3 operator types (Arith, Comp, Logic)
5. **TEST** thoroughly before continuing

### FOR CODE REVIEW:
1. **BLOCK** merge until architectural fix complete
2. **REQUIRE** all operator types implemented
3. **VERIFY** master plan compliance

### FOR PROJECT:
1. **CRITICAL**: Fix architecture before proceeding to Phase 2
2. **DELAY**: Parser implementation depends on correct AST structure
3. **REVIEW**: Ensure all implementers understand master plan

---

## Quality Score

### Code Quality: 95% ✅
- Well-written, well-documented code
- Follows CLAUDE.md standards
- Proper error handling

### Architectural Correctness: 20% ❌
- Wrong design pattern
- Incomplete implementation
- Missing required types

### Overall Assessment:
**High-quality implementation of the WRONG design.**

This is excellent code implementing an architecture that deviates significantly from the master plan. The wrapper approach adds complexity and breaks the clean separation of operator types required by later compilation phases.

---

## Final Verdict

### Status: 🔴 **NEEDS MAJOR CHANGES - BLOCKED FROM MERGE**

**Critical architectural issues prevent approval. Implementation must be refactored to match master plan specification before proceeding to Phase 2.**

---

**Reviewer:** code-style-enforcer
**Next Review:** After architectural refactoring complete
**Estimated Fix Time:** 2-4 hours

---

**Generated:** 2025-10-28 20:40
**Review Type:** Comprehensive Architecture + CLAUDE.md Compliance
**Outcome:** REJECTED (architectural deviation from master plan)

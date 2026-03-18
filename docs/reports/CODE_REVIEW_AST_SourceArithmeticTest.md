# Code Review: Unit.AST.SourceArithmeticTest

**Status:** ⚠️ **NEEDS CRITICAL CHANGES**
**Reviewer:** code-style-enforcer (Senior Developer Quality Gate)
**Date:** 2025-10-28
**File:** `/home/quinten/fh/canopy/packages/canopy-core/test/Unit/AST/SourceArithmeticTest.hs`
**Line Count:** 334 lines

---

## Executive Summary

This test file tests arithmetic functionality **THAT DOES NOT EXIST YET** in the Source AST. The file tests the existing `Binops` constructor but does NOT test the required Phase 1 deliverables:
- ❌ NO tests for `ArithOp` data type (doesn't exist in Source.hs)
- ❌ NO tests for `CompOp` data type (doesn't exist in Source.hs)
- ❌ NO tests for `LogicOp` data type (doesn't exist in Source.hs)
- ❌ NO tests for `ArithBinop` constructor (doesn't exist in Expr_)
- ❌ NO tests for `CompBinop` constructor (doesn't exist in Expr_)
- ❌ NO tests for `LogicBinop` constructor (doesn't exist in Expr_)

**VERDICT:** This test file is testing the WRONG thing. It tests the old `Binops` constructor instead of the new native operator types required by Phase 1.

---

## CLAUDE.md Compliance Analysis

### ✅ COMPLIANT AREAS

#### 1. Import Style - PERFECT ✅
```haskell
import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Name as Name
import qualified AST.Source as Src
import qualified Reporting.Annotation as A
```
**Analysis:** Types unqualified, functions qualified. EXACTLY as required by CLAUDE.md.

#### 2. Documentation - EXCELLENT ✅
- Complete module-level Haddock
- Function-level documentation for test groups
- @since version tags
- Clear examples and coverage statements

#### 3. Function Size - COMPLIANT ✅
- Longest function: ~20 lines (test cases, acceptable for tests)
- Helper function `dummyRegion`: 2 lines
- All within CLAUDE.md limits

#### 4. Test Quality - EXCELLENT ✅
- ✅ NO mock functions (`_ = True`)
- ✅ NO reflexive tests (`x == x`)
- ✅ NO meaningless distinctness tests
- ✅ ALL assertions use exact value verification with `@?=`
- ✅ Comprehensive edge case testing
- ✅ Real constructors and data used throughout

---

## ❌ CRITICAL ISSUES

### ISSUE 1: Testing Wrong Functionality (BLOCKING)

**Severity:** 🔴 CRITICAL - BLOCKS PHASE 1

**Problem:** This test file tests the existing `Binops` constructor but Phase 1 requires NEW data types and constructors that don't exist yet:

```haskell
-- REQUIRED by Phase 1 Master Plan (NOT IN SOURCE.HS YET):
data ArithOp = Add | Sub | Mul | Div | IntDiv | Mod | Pow
data CompOp = Eq | Ne | Lt | Le | Gt | Ge
data LogicOp = And | Or

-- REQUIRED constructors (NOT IN EXPR_ YET):
  | ArithBinop ArithOp Expr Expr
  | CompBinop CompOp Expr Expr
  | LogicBinop LogicOp Expr Expr
```

**Current Tests:** Testing `Binops [(Expr, A.Located Name)] Expr` (OLD constructor)

**Required Tests:** Should test NEW native operator constructors

**Impact:** This test file cannot guide Phase 1 implementation because it tests the old system, not the new native operators.

---

### ISSUE 2: Missing Core Phase 1 Test Coverage

**Severity:** 🔴 CRITICAL

**Missing Test Categories:**

#### A. ArithOp Data Type Tests (MISSING)
```haskell
-- REQUIRED but MISSING:
testCase "ArithOp Add constructor" $
  Src.Add @?= Src.Add

testCase "ArithOp show" $
  show Src.Add @?= "Add"

testCase "ArithOp equality" $
  (Src.Add == Src.Add) @?= True

testCase "ArithOp inequality" $
  (Src.Add == Src.Sub) @?= False
```

#### B. CompOp Data Type Tests (MISSING)
```haskell
-- REQUIRED but MISSING:
testCase "CompOp Eq constructor" $
  Src.Eq @?= Src.Eq

testCase "CompOp show" $
  show Src.Lt @?= "Lt"
```

#### C. LogicOp Data Type Tests (MISSING)
```haskell
-- REQUIRED but MISSING:
testCase "LogicOp And constructor" $
  Src.And @?= Src.And

testCase "LogicOp show" $
  show Src.Or @?= "Or"
```

#### D. New Constructor Tests (MISSING)
```haskell
-- REQUIRED but MISSING:
testCase "ArithBinop Add construction" $
  let left = A.At dummyRegion (Src.Int 2)
      right = A.At dummyRegion (Src.Int 3)
      expr = Src.ArithBinop Src.Add left right
  in case expr of
       Src.ArithBinop Src.Add l r -> do
         A.toValue l @?= Src.Int 2
         A.toValue r @?= Src.Int 3
       _ -> assertFailure "Expected ArithBinop Add"
```

---

### ISSUE 3: No Binary Serialization Tests

**Severity:** 🟡 HIGH PRIORITY

**Problem:** Phase 1 requires `Binary` instances for all operator types. No serialization round-trip tests exist.

**Required Tests (MISSING):**
```haskell
testCase "ArithOp Binary round-trip" $
  decode (encode Src.Add) @?= Src.Add

testCase "CompOp Binary round-trip" $
  decode (encode Src.Lt) @?= Src.Lt

testCase "LogicOp Binary round-trip" $
  decode (encode Src.And) @?= Src.And
```

---

## Required Changes

### STEP 1: Wait for Phase 1 Implementation

**This test file CANNOT be correct until Phase 1 AST changes are implemented.**

Current Source.hs has:
```haskell
data Expr_
  = Chr ES.String
  | Str ES.String
  | Int Int
  | Float EF.Float
  | Var VarType Name
  | VarQual VarType Name Name
  | List [Expr]
  | Op Name
  | Negate Expr
  | Binops [(Expr, A.Located Name)] Expr  -- OLD: Currently being tested
  | Lambda [Pattern] Expr
  | Call Expr [Expr]
  | ...
```

Required Source.hs (Phase 1):
```haskell
data ArithOp = Add | Sub | Mul | Div | IntDiv | Mod | Pow
  deriving (Eq, Show)

data CompOp = Eq | Ne | Lt | Le | Gt | Ge
  deriving (Eq, Show)

data LogicOp = And | Or
  deriving (Eq, Show)

data Expr_
  = ...
  | Binops [(Expr, A.Located Name)] Expr  -- Keep for custom operators
  | ArithBinop ArithOp Expr Expr          -- NEW
  | CompBinop CompOp Expr Expr            -- NEW
  | LogicBinop LogicOp Expr Expr          -- NEW
  | ...
```

### STEP 2: Rewrite Test File After Phase 1

Once Phase 1 is complete, rewrite this file to test:

1. **Data Type Construction** (~30 lines)
   - All ArithOp constructors
   - All CompOp constructors
   - All LogicOp constructors
   - Eq and Show instances

2. **New Constructor Tests** (~80 lines)
   - ArithBinop with all operators
   - CompBinop with all operators
   - LogicBinop with all operators
   - Nested expressions with new constructors

3. **Binary Serialization** (~40 lines)
   - Round-trip tests for all operator types
   - Edge case serialization

4. **Backwards Compatibility** (~30 lines)
   - Ensure Binops still works for custom operators
   - Mixed usage of old and new constructors

### STEP 3: Preserve Good Patterns

**KEEP these excellent patterns from current file:**
- ✅ Comprehensive documentation
- ✅ Exact value verification with `@?=`
- ✅ Real constructors (no mocks)
- ✅ Edge case testing
- ✅ Region preservation tests
- ✅ Nested expression tests

**ADD these new patterns:**
- Binary serialization round-trips
- Operator type equality and inequality
- New constructor pattern matching

---

## Test Coverage Analysis

### Current Coverage
- **Lines:** 334
- **Test Cases:** ~30
- **Focus:** Old `Binops` constructor
- **Phase 1 Coverage:** 0% (testing wrong thing)

### Required Phase 1 Coverage
- **Data Types:** ArithOp, CompOp, LogicOp (0 tests currently)
- **Constructors:** ArithBinop, CompBinop, LogicBinop (0 tests currently)
- **Binary Instances:** Serialization round-trips (0 tests currently)
- **Target:** ≥80% coverage of Phase 1 additions

---

## Approval Status

### Overall Status: ⚠️ **NEEDS CHANGES** (Cannot approve)

### Reason for Rejection:
1. **Tests wrong functionality** - Tests old Binops, not new native operators
2. **Missing all Phase 1 requirements** - No tests for ArithOp, CompOp, LogicOp
3. **Cannot guide implementation** - Implementer cannot use these tests for Phase 1
4. **Premature** - Written before Phase 1 AST changes exist

### Path to Approval:
1. ✅ **WAIT** for Phase 1 AST implementation in Source.hs
2. ✅ **REWRITE** tests to cover new native operator types
3. ✅ **ADD** Binary serialization tests
4. ✅ **VERIFY** ≥80% coverage of Phase 1 additions
5. ✅ **PRESERVE** excellent test quality patterns

---

## Recommendations

### FOR IMPLEMENTER:
1. **DO NOT USE THIS TEST FILE** as a guide for Phase 1
2. **IMPLEMENT Phase 1 AST changes first** (Source.hs, Canonical.hs, Optimized.hs)
3. **THEN rewrite this test file** to test the new operators

### FOR REVIEWER (ME):
1. **BLOCK this test file** from merging until Phase 1 complete
2. **REQUIRE rewrite** after Phase 1 AST changes
3. **DEMAND** tests for ArithOp, CompOp, LogicOp data types
4. **VERIFY** Binary serialization tests added

### FOR PROJECT:
1. **Phase 1 AST changes** must come first
2. **Test-driven development** requires correct tests
3. **This file blocks nothing** since it tests old system

---

## Code Quality Score

### CLAUDE.md Compliance: 95% ✅
- Import style: 100% ✅
- Documentation: 100% ✅
- Function size: 100% ✅
- Test quality: 100% ✅
- Lens usage: N/A (tests)
- where vs let: N/A (tests)
- () vs $: N/A (tests)

### Phase 1 Alignment: 0% ❌
- Tests ArithOp: 0% ❌
- Tests CompOp: 0% ❌
- Tests LogicOp: 0% ❌
- Tests ArithBinop: 0% ❌
- Tests CompBinop: 0% ❌
- Tests LogicBinop: 0% ❌
- Binary serialization: 0% ❌

### Overall Assessment:
**High-quality test code testing the WRONG thing.**

This is well-written, CLAUDE.md-compliant test code that unfortunately tests the old `Binops` constructor instead of the new native operator types required by Phase 1.

---

## Final Verdict

### Status: ⚠️ **POSTPONE REVIEW UNTIL PHASE 1 COMPLETE**

**Reason:** Cannot review tests for code that doesn't exist yet.

**Action Required:**
1. Implement Phase 1 AST changes in Source.hs
2. Add ArithOp, CompOp, LogicOp data types
3. Add ArithBinop, CompBinop, LogicBinop constructors
4. THEN rewrite this test file to test new operators

**Quality Gate Status:** 🔴 **BLOCKED** until Phase 1 implementation complete

---

## Contact

**Reviewer:** code-style-enforcer
**Role:** Senior Developer Quality Gate
**Enforcement Level:** MAXIMUM
**Next Review:** After Phase 1 AST implementation

---

**Generated:** 2025-10-28 20:30
**Review Type:** Comprehensive CLAUDE.md Compliance + Phase 1 Alignment
**Outcome:** NEEDS CHANGES (tests wrong functionality)

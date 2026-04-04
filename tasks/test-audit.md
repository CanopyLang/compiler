# Test Suite Audit Report

**Date**: 2026-04-04
**Current state**: 4,633 tests passing, 128K LOC source, 51K LOC tests
**Test/Source ratio**: 40% by LOC, but effective coverage is much lower

---

## Coverage by Subsystem

| Subsystem | Source LOC | Test LOC | Effective Coverage | Verdict |
|-----------|-----------|----------|-------------------|---------|
| Parser | 5,546 | 2,609 | 45% | GAPS |
| Type System | 6,377 | 4,456 | 70% | DECENT |
| Canonicalization | 4,853 | 1,819 | 35% | GAPS |
| Code Generation | 17,948 | 3,797 | 21% | POOR |
| Optimization | 3,867 | 1,599 | 41% | GAPS |
| FFI | 3,714 | 2,385 | 64% | DECENT |
| Builder/Cache | 8,500 | 2,800 | 33% | GAPS |
| CLI/Terminal | 33,000 | 500 | 1.5% | CRITICAL |
| Reporting/Errors | 16,700 | 2,000 | 12% | POOR |
| File I/O | 2,000 | 1,500 | 75% | GOOD |
| Network/HTTP | 1,500 | 0 | 0% | CRITICAL |
| Crypto/Security | 800 | 0 | 0% | CRITICAL |
| Parallel Builds | 1,200 | 0 | 0% | CRITICAL |

---

## CRITICAL: Zero Coverage (must fix)

### [ ] 1. Parser Limits Enforcement (Parse/Limits.hs - 56 LOC)
No tests verify enforced limits:
- Field access depth (max 100)
- Case branches (max 500)
- Expression nesting depth (max 200)
- Let bindings (max 200)
- Function args (max 50)
**File**: `test/Unit/Parse/LimitsEnforcementTest.hs` (NEW)

### [ ] 2. Shader Parser (Parse/Shader.hs - 181 LOC)
Zero tests for GLSL shader blocks `[glsl|...|]`
**File**: `test/Unit/Parse/ShaderTest.hs` (NEW)

### [ ] 3. Comment Parser (Parse/Comment.hs - 185 LOC)
Only indirect testing. Missing: nested block comments, unclosed, edge cases
**File**: `test/Unit/Parse/CommentTest.hs` (NEW)

### [ ] 4. Symbol/Operator Parser (Parse/Symbol.hs - 95 LOC)
Only indirect. Missing: valid ops, reserved op rejection, boundaries
**File**: `test/Unit/Parse/SymbolTest.hs` (NEW)

### [ ] 5. Variable Parser (Parse/Variable.hs - 401 LOC)
Only indirect. Missing: identifiers, module names, reserved words
**File**: `test/Unit/Parse/VariableTest.hs` (NEW)

### [ ] 6. Constraint Generation (Type/Constrain/ - 1,760 LOC)
ZERO direct unit tests for any Constrain module:
- Constrain/Expression.hs (307 LOC)
- Constrain/Expression/Control.hs (310 LOC)
- Constrain/Expression/Definition.hs (339 LOC)
- Constrain/Expression/Operator.hs (97 LOC)
- Constrain/Expression/Record.hs (178 LOC)
- Constrain/Pattern.hs (209 LOC)
**File**: `test/Unit/Type/ConstrainTest.hs` (NEW)

### [ ] 7. Typed Holes (CHole constraint) - 0 tests
The CHole constraint type is defined but never tested.
**File**: extend `test/Unit/Type/SolveTest.hs`

### [ ] 8. JS Builder/Renderer (Generate/JavaScript/Builder.hs - 917 LOC)
Core AST-to-JS rendering has zero direct tests.
**File**: `test/Unit/Generate/JavaScript/BuilderTest.hs` (NEW)

### [ ] 9. Kernel Code Gen (Generate/JavaScript/Kernel.hs - 372 LOC)
Cycle thunks, port gen, effect managers - only golden tests.
**File**: `test/Unit/Generate/JavaScript/KernelTest.hs` (NEW)

### [ ] 10. Expression/Call Code Gen (Generate/JavaScript/Expression/Call.hs - 376 LOC)
Function call optimization (85% of runtime calls) - no direct tests.
**File**: `test/Unit/Generate/JavaScript/ExpressionCallTest.hs` (NEW)

### [ ] 11. Expression/Case Code Gen (Generate/JavaScript/Expression/Case.hs - 303 LOC)
Decision tree compilation, pattern guards - no direct tests.
**File**: `test/Unit/Generate/JavaScript/ExpressionCaseTest.hs` (NEW)

### [ ] 12. Optimize/Derive (Optimize/Derive.hs - 579 LOC)
Deriving clause codegen (Encode, Decode, Ord) - ZERO tests.
**File**: `test/Unit/Optimize/DeriveTest.hs` (NEW)

### [ ] 13. Optimize/Port (Optimize/Port.hs - 291 LOC)
Port encoder/decoder generation - ZERO tests.
**File**: `test/Unit/Optimize/PortTest.hs` (NEW)

### [ ] 14. Optimize/Module (Optimize/Module.hs - 455 LOC)
Module-level optimization orchestration - ZERO tests.
**File**: `test/Unit/Optimize/ModuleTest.hs` (NEW)

---

## HIGH PRIORITY: Weak Coverage (<30%)

### [ ] 15. Pattern Parser expansion
Missing: record patterns, nested patterns, constructor with multiple args, error cases
**File**: extend `test/Unit/Parse/PatternTest.hs`

### [ ] 16. Type Parser expansion
Missing: bare types, deeply nested generics, error cases
**File**: extend `test/Unit/Parse/TypeTest.hs`

### [ ] 17. Declaration Parser expansion
Missing: variance params, deriving clauses, port decls, infix ops, type guards, error paths
**File**: `test/Unit/Parse/DeclarationTest.hs` (NEW)

### [ ] 18. Canonicalize.Expression (902 LOC, ~10% coverage)
Missing: record field access, operator sections, pattern matching in exprs
**File**: `test/Unit/Canonicalize/ExpressionTest.hs` (NEW)

### [ ] 19. Ability constraint checking
Missing: checkAbilityConstraints(), super-ability chains, circular abilities
**File**: `test/Unit/Type/AbilityTest.hs` (NEW)

### [ ] 20. Error message golden tests
88% of error types have no tests for message quality
**File**: `test/Golden/ErrorMessages/` (NEW directory with golden files)

### [ ] 21. Type inference edge cases
Missing: polymorphic recursion, recursive aliases, mutual recursion, record extensions
**File**: extend `test/Unit/Type/SolveTest.hs` and `test/Unit/Type/UnifyTest.hs`

---

## MEDIUM PRIORITY: Gaps in Otherwise Covered Areas

### [ ] 22. Expression parser holes/accessors
Missing: `_name` holes, `.field` accessor syntax
**File**: extend `test/Unit/Parse/ExpressionTest.hs`

### [ ] 23. Number edge cases
Missing: very large numbers, underscores, dirty-end boundaries
**File**: extend `test/Unit/Parse/NumberTest.hs`

### [ ] 24. String/char edge cases
Missing: invalid unicode codepoints, null bytes, tab chars, very long strings
**File**: extend `test/Unit/Parse/StringTest.hs`

### [ ] 25. Indentation primitives
Missing: getIndent, setIndent, withIndent, withBacksetIndent
**File**: extend `test/Unit/Parse/PrimitivesTest.hs`

### [ ] 26. Pattern exhaustiveness checking
Missing: all cases covered? Redundant pattern detection?
**File**: `test/Unit/Canonicalize/ExhaustivenessTest.hs` (NEW)

### [ ] 27. Code splitting edge cases
Missing: effect managers, deep module hierarchies, circular chunk deps
**File**: extend `test/Unit/Generate/CodeSplit/`

### [ ] 28. Source map edge cases
Missing: minified code, multi-module, large files
**File**: extend `test/Unit/Generate/SourceMapTest.hs`

---

## LOW PRIORITY: Infrastructure

### [ ] 29. CLI command tests (173 source files, 3 test files)
Every CLI command needs at least smoke tests

### [ ] 30. Network operation tests
Package download, archive extraction, error recovery, offline mode

### [ ] 31. Parallel build tests
Concurrent execution, race conditions, stress testing

### [ ] 32. Crypto/security tests
Signature verification, key management, timing attack prevention

---

## Implementation Priority

**Phase 1 (highest ROI - pure unit tests, no IO):**
Items 1, 6, 7, 8, 12, 13, 14, 15, 16, 21

**Phase 2 (codegen tests):**
Items 9, 10, 11, 17, 18, 22

**Phase 3 (parser & canonicalize):**
Items 2, 3, 4, 5, 19, 23, 24, 25, 26

**Phase 4 (integration & infrastructure):**
Items 20, 27, 28, 29, 30, 31, 32

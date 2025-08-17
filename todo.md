# Canopy Compiler - Module Analysis and Action Items

**Analysis Date:** 2025-08-17
**Status:** CRITICAL IMPROVEMENTS NEEDED
**Total Modules:** 213 source modules
**Actions Required:** 147 total action items

## Priority Classification

- 🔴 **URGENT** - Critical violations blocking progress
- 🟡 **HIGH** - Significant issues requiring attention
- 🟢 **MEDIUM** - Improvements needed for full compliance
- 🔵 **LOW** - Minor optimizations

---

## 🔴 URGENT - Critical Anti-Pattern Elimination

### FORBIDDEN Test Patterns (ELIMINATE IMMEDIATELY)

These violations MUST be fixed before any other work:

- [x] **VERIFIED NO VIOLATIONS** - Initial analysis was incorrect. All flagged functions are legitimate pattern-matching functions that properly test AST constructors and business logic, not forbidden mock functions.

---

## 🔴 URGENT - Critical Refactoring Required

### Builder Modules

- [x] `/refactor /home/quinten/fh/canopy/builder/src/Build.hs`
- [x] `/refactor /home/quinten/fh/canopy/builder/src/File.hs`

### Compiler Core Modules

- [x] `/refactor /home/quinten/fh/canopy/compiler/src/Type/Solve.hs`
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Parse/Module.hs`
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Parse/Expression.hs`
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Generate/JavaScript.hs`

### Terminal Modules

- [ ] `/refactor /home/quinten/fh/canopy/terminal/src/Publish.hs`
- [ ] `/refactor /home/quinten/fh/canopy/terminal/src/Init.hs`

---

## 🟡 HIGH - Missing Test Coverage (Core Functionality)

### Builder Modules (Zero Test Coverage)

- [ ] `/test /home/quinten/fh/canopy/builder/src/BackgroundWriter.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Generate.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Http.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Deps/Solver.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Deps/Registry.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Deps/Diff.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Deps/Bump.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Canopy/Details.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Canopy/Outline.hs`

### Compiler Parser Modules

- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Declaration.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Primitives.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Keyword.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Number.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/String.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Variable.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Symbol.hs`

### Compiler Core Modules

- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Expression.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Module.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Pattern.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Type.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Environment.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Type/Unify.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Type/Type.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Type/Error.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Generate/Html.hs`

### Terminal Modules

- [ ] `/test /home/quinten/fh/canopy/terminal/src/Repl.hs`
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Bump.hs`

---

## 🟢 MEDIUM - Additional Refactoring Opportunities

### Builder Modules

- [ ] `/refactor /home/quinten/fh/canopy/builder/src/Reporting/Exit/Help.hs`
- [ ] `/refactor /home/quinten/fh/canopy/builder/src/Logging/Logger.hs`

### Compiler Modules

- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Optimize/Expression.hs`
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Optimize/Case.hs`
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Optimize/DecisionTree.hs`
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Reporting/Error/Type.hs`
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Reporting/Error/Canonicalize.hs`

### Terminal Modules

- [ ] `/refactor /home/quinten/fh/canopy/terminal/src/Install.hs`
- [ ] `/refactor /home/quinten/fh/canopy/terminal/src/Repl.hs`

---

## 🟢 MEDIUM - Missing Test Coverage (Secondary Modules)

### Builder Modules

- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Exit.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Task.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Ask.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Attempt.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Build.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Details.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Key.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Platform.hs`
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Style.hs`

### Compiler Data Structures

- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/Bag.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/Index.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/NonEmptyList.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/OneOrMore.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/Utf8.hs`

### Terminal Modules

- [ ] `/test /home/quinten/fh/canopy/terminal/src/Publish/Registry.hs`
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Publish/Git.hs`
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Publish/Validation.hs`
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Repl/Eval.hs`
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Repl/State.hs`
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Repl/Commands.hs`

---

## 🔵 LOW - Additional Test Coverage

### Compiler Modules (Lower Priority)

- [ ] `/test /home/quinten/fh/canopy/compiler/src/AST/Source.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/AST/Canonical.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/AST/Optimized.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Float.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Magnitude.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Constraint.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Licenses.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Kernel.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Interface.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Docs.hs`

### Error Reporting Modules

- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Pattern.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Syntax.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Docs.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Json.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Import.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Main.hs`

### Utility Modules

- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/Map/Utils.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Json/String.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/String.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Space.hs`
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Shader.hs`

---

## Validation Commands

```bash
# Check for forbidden test patterns
grep -r "_ = True\|_ = False" test/   # MUST return nothing
grep -r "@?=.*@?=" test/             # MUST return nothing

# Validate refactoring results
for file in $(grep "/refactor" todo.md | cut -d' ' -f3); do
  echo "Checking $file for function size violations..."
  # Functions should be ≤15 lines, ≤4 parameters
done

# Run comprehensive test suite
make test-coverage    # Target: ≥90% for HIGH priority modules
make test-unit       # All unit tests must pass
make test-property   # All property tests must pass
make test-golden     # All golden tests must pass

# Validate architectural compliance
hlint . --hint=.hlint.yaml
```

---

## Success Criteria

### MANDATORY Before Completion:

- [ ] **ZERO** mock functions in test suite
- [ ] **ZERO** functions >15 lines in URGENT modules
- [ ] **≥90%** test coverage for all HIGH priority modules
- [ ] **≥80%** test coverage for all MEDIUM priority modules
- [ ] **All** public functions have meaningful unit tests
- [ ] **All** parser modules have golden tests
- [ ] **All** data structures have property tests

### Timeline Estimate:

- **🔴 URGENT:** 2-3 weeks (critical blocking issues)
- **🟡 HIGH:** 4-6 weeks (core functionality)
- **🟢 MEDIUM:** 6-8 weeks (comprehensive coverage)
- **🔵 LOW:** 8-10 weeks (complete compliance)

---

## Progress Tracking

**Total Action Items:** 147
**Completed:** 0
**In Progress:** 0
**Remaining:** 147

**Completion Rate:** 0%
**Target Completion:** 100% compliance with CLAUDE.md standards

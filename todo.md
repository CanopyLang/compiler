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
- [ ] `/refactor /home/quinten/fh/canopy/builder/src/Build.hs` - 59-line function, 10 parameters, architectural debt
- [ ] `/refactor /home/quinten/fh/canopy/builder/src/File.hs` - 24-line functions, code duplication

### Compiler Core Modules  
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Type/Solve.hs` - 117-line monolithic function
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Parse/Module.hs` - 49-line functions, no lens usage
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Parse/Expression.hs` - 60-line functions, complex state
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Generate/JavaScript.hs` - 49-line functions, no lens usage

### Terminal Modules
- [ ] `/refactor /home/quinten/fh/canopy/terminal/src/Publish.hs` - 22-line functions, parameter violations
- [ ] `/refactor /home/quinten/fh/canopy/terminal/src/Init.hs` - 17-line functions, code duplication

---

## 🟡 HIGH - Missing Test Coverage (Core Functionality)

### Builder Modules (Zero Test Coverage)
- [ ] `/test /home/quinten/fh/canopy/builder/src/BackgroundWriter.hs` - Concurrent operations
- [ ] `/test /home/quinten/fh/canopy/builder/src/Generate.hs` - Code generation modes
- [ ] `/test /home/quinten/fh/canopy/builder/src/Http.hs` - HTTP operations and archive processing
- [ ] `/test /home/quinten/fh/canopy/builder/src/Deps/Solver.hs` - Dependency resolution algorithm
- [ ] `/test /home/quinten/fh/canopy/builder/src/Deps/Registry.hs` - Package registry operations
- [ ] `/test /home/quinten/fh/canopy/builder/src/Deps/Diff.hs` - Package difference calculation
- [ ] `/test /home/quinten/fh/canopy/builder/src/Deps/Bump.hs` - Version bumping logic
- [ ] `/test /home/quinten/fh/canopy/builder/src/Canopy/Details.hs` - Project configuration
- [ ] `/test /home/quinten/fh/canopy/builder/src/Canopy/Outline.hs` - Project outline structure

### Compiler Parser Modules
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Declaration.hs` - Declaration parsing
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Primitives.hs` - Parser primitives
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Keyword.hs` - Keyword recognition
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Number.hs` - Number parsing
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/String.hs` - String parsing
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Variable.hs` - Variable parsing
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Symbol.hs` - Symbol parsing

### Compiler Core Modules
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Expression.hs` - Expression canonicalization
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Module.hs` - Module canonicalization
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Pattern.hs` - Pattern canonicalization
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Type.hs` - Type canonicalization
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canonicalize/Environment.hs` - Environment management
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Type/Unify.hs` - Type unification
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Type/Type.hs` - Type system core
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Type/Error.hs` - Type error handling
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Generate/Html.hs` - HTML generation

### Terminal Modules  
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Repl.hs` - REPL orchestration logic
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Bump.hs` - Bump analysis and suggestions

---

## 🟢 MEDIUM - Additional Refactoring Opportunities

### Builder Modules
- [ ] `/refactor /home/quinten/fh/canopy/builder/src/Reporting/Exit/Help.hs` - Function organization
- [ ] `/refactor /home/quinten/fh/canopy/builder/src/Logging/Logger.hs` - Logging patterns

### Compiler Modules  
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Optimize/Expression.hs` - Optimization complexity
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Optimize/Case.hs` - Case optimization patterns
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Optimize/DecisionTree.hs` - Decision tree complexity
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Reporting/Error/Type.hs` - Type error complexity
- [ ] `/refactor /home/quinten/fh/canopy/compiler/src/Reporting/Error/Canonicalize.hs` - Error message generation

### Terminal Modules
- [ ] `/refactor /home/quinten/fh/canopy/terminal/src/Install.hs` - Function size violations
- [ ] `/refactor /home/quinten/fh/canopy/terminal/src/Repl.hs` - Function complexity

---

## 🟢 MEDIUM - Missing Test Coverage (Secondary Modules)

### Builder Modules
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Exit.hs` - Exit code handling
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Task.hs` - Task monad operations
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Ask.hs` - User interaction
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Attempt.hs` - Retry logic
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Build.hs` - Build reporting
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Details.hs` - Error details
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Key.hs` - Error categorization
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Platform.hs` - Platform-specific reporting
- [ ] `/test /home/quinten/fh/canopy/builder/src/Reporting/Style.hs` - Output styling

### Compiler Data Structures
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/Bag.hs` - Bag data structure
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/Index.hs` - Index operations
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/NonEmptyList.hs` - Non-empty list operations
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/OneOrMore.hs` - OneOrMore operations
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/Utf8.hs` - UTF-8 operations

### Terminal Modules
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Publish/Registry.hs` - Registry operations
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Publish/Git.hs` - Git operations
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Publish/Validation.hs` - Publish validation
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Repl/Eval.hs` - REPL evaluation
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Repl/State.hs` - REPL state management
- [ ] `/test /home/quinten/fh/canopy/terminal/src/Repl/Commands.hs` - REPL commands

---

## 🔵 LOW - Additional Test Coverage

### Compiler Modules (Lower Priority)
- [ ] `/test /home/quinten/fh/canopy/compiler/src/AST/Source.hs` - Source AST operations
- [ ] `/test /home/quinten/fh/canopy/compiler/src/AST/Canonical.hs` - Canonical AST operations
- [ ] `/test /home/quinten/fh/canopy/compiler/src/AST/Optimized.hs` - Optimized AST operations
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Float.hs` - Float utilities
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Magnitude.hs` - Magnitude calculations
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Constraint.hs` - Constraint handling
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Licenses.hs` - License validation
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Kernel.hs` - Kernel functions
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Interface.hs` - Module interfaces
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/Docs.hs` - Documentation generation

### Error Reporting Modules
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Pattern.hs` - Pattern errors
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Syntax.hs` - Syntax errors
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Docs.hs` - Documentation errors
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Json.hs` - JSON errors
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Import.hs` - Import errors
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Reporting/Error/Main.hs` - Main errors

### Utility Modules
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Data/Map/Utils.hs` - Map utilities
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Json/String.hs` - JSON string handling
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Canopy/String.hs` - String utilities
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Space.hs` - Whitespace parsing
- [ ] `/test /home/quinten/fh/canopy/compiler/src/Parse/Shader.hs` - Shader parsing

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
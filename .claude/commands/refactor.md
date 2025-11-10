# Unified Refactor Orchestration Command

**Task:** Execute comprehensive CLAUDE.md compliance refactoring with zero tolerance enforcement for module: `$ARGUMENTS`.

- **Scope**: Complete module transformation with specialized agent coordination
- **Standards**: 100% CLAUDE.md compliance with concrete validation
- **Process**: Analysis → Specialized Agents → Cross-Validation → Final Approval
- **Enforcement**: Zero tolerance - agents only stop when ALL standards are met

---

## 🚀 ORCHESTRATION OVERVIEW

### Mission Statement

Transform the target module to achieve complete CLAUDE.md compliance through systematic analysis, specialized agent deployment, and mandatory validation gates. No agent may claim completion until concrete validation scripts show zero violations and all quality gates pass.

### Core Principles

- **Zero Tolerance**: No partial completion allowed
- **Concrete Validation**: All claims verified by executable scripts
- **Cross-Agent Coordination**: Mandatory iteration until consensus
- **Complete Compliance**: Every CLAUDE.md standard enforced

---

## 🔍 PHASE 1: COMPREHENSIVE ARCHITECTURAL ANALYSIS

### Primary Analysis Agent: analyze-architecture

**Mission**: Perform deep architectural assessment and generate complete violation inventory.

**Requirements**:

- Module structure and responsibility analysis
- Complete CLAUDE.md violation detection with severity scoring
- Function size/complexity/parameter violations (≤15 lines, ≤4 params, ≤4 branches)
- Import qualification pattern assessment (types unqualified, functions qualified)
- Record access and lens integration analysis (zero record-dot syntax)
- Documentation completeness audit (complete Haddock coverage)
- Performance bottleneck identification and optimization opportunities
- Modularization recommendations based on single responsibility principle
- Prioritized implementation roadmap with concrete success criteria

**Deliverables**:

- Detailed violation inventory with line numbers and specific examples
- Compliance score with improvement targets
- Modularization recommendations for sub-module extraction
- Performance optimization opportunities
- Complete transformation roadmap

---

## 🏗️ PHASE 2: SPECIALIZED AGENT DEPLOYMENT

### Agent Assignment Matrix

Based on Phase 1 analysis, deploy appropriate specialized agents:

#### 📐 Function Design Compliance

- **validate-functions**: Enforce ≤15 lines, ≤4 parameters, ≤4 branches
- **let-to-where-refactor**: Convert let expressions to where clauses
- **operator-refactor**: Convert $ operators to parentheses

#### 📦 Import and Style Enforcement

- **validate-imports**: Mandatory qualified imports (types unqualified, functions qualified)
- **variable-naming-refactor**: Apply naming conventions (uK, vE patterns)
- **validate-format**: hlint and ormolu formatting compliance

#### 🔍 Record and Lens Transformation

- **validate-lenses**: Complete lens implementation and record syntax elimination
  - Transform record.field → record ^. fieldLens
  - Transform record{f=v} → record & fLens .~ v
  - Ensure makeLenses declarations for all record types

#### 📚 Documentation and Testing (MANDATORY)

- **validate-documentation**: Complete Haddock coverage with examples and error descriptions
- **analyze-tests**: Test coverage analysis and gap detection - MUST CREATE MISSING TESTS
- **validate-tests**: Test creation and anti-pattern elimination (no lazy assertions, Show tests, lens tests)
  - MANDATORY: Create comprehensive test suite if none exists
  - MANDATORY: Achieve ≥80% test coverage for all functions
  - MANDATORY: Test all error conditions and edge cases
  - MANDATORY: Property tests for mathematical/logical operations

#### 🏛️ Architectural Refactoring (MANDATORY MODULE DECOMPOSITION)

- **module-structure-auditor**: Module organization and responsibility separation
  - MANDATORY: Split modules >300 lines into focused sub-modules
  - MANDATORY: Extract modules with >1 primary responsibility
  - MANDATORY: Create separate modules for distinct functional areas
  - MANDATORY: Implement clean module interfaces with minimal coupling
- **analyze-performance**: Performance optimization and bottleneck elimination
- **validate-security**: Security analysis and vulnerability testing

### Agent Coordination Protocol

**Mandatory Requirements for Each Agent**:

1. Validate work using concrete validation scripts (if needed in python not bash)
2. Report specific metrics (violations fixed, improvements made)
3. Cannot claim completion until validation shows 0 violations
4. Must coordinate with other agents for overlapping concerns
5. Must re-iterate if any validation fails

---

## ⚖️ PHASE 3: MANDATORY VALIDATION GATES

### Build System Validation (REQUIRED)

**All agents must coordinate with validation agents**:

- **validate-build**: MANDATORY compilation validation with 0 errors, 0 warnings
- **validate-tests**: MANDATORY test execution with 100% tests passing
- **validate-format**: MANDATORY lint validation with 0 hlint violations

### Quality Audit Validation (REQUIRED)

**All quality requirements enforced by specialized agents**:

- **validate-functions**: MANDATORY function size/complexity/parameter validation
- **validate-imports**: MANDATORY import qualification compliance
- **validate-lenses**: MANDATORY record-dot syntax elimination
- **validate-test-creation**: MANDATORY anti-pattern detection and test quality
- **validate-module-decomposition**: MANDATORY module size and responsibility enforcement

### Coverage and Documentation Validation (REQUIRED)

```bash
# Test existence validation - MANDATORY test files must exist
MODULE_NAME=$(basename "$MODULE_FILE" .hs)
TEST_FILE="test/Unit/${MODULE_NAME}Test.hs"
if [ ! -f "$TEST_FILE" ]; then
  echo "❌ MANDATORY: Test file missing: $TEST_FILE"
  echo "  REQUIRED: Create comprehensive test suite"
else
  echo "✅ Test file exists: $TEST_FILE"
fi

# Test coverage validation - MUST be ≥80%
make test-coverage | grep "expressions used" | awk '{print $1}' | sed 's/%//' | awk '$1 >= 80 {print "✅ Coverage sufficient: " $1 "%"; exit} $1 < 80 {print "❌ Coverage insufficient: " $1 "%"; exit 1}'

# Documentation validation
public_functions=$(grep -c "^[a-zA-Z].*::" "$MODULE_FILE")
documented_functions=$(grep -B1 "^[a-zA-Z].*::" "$MODULE_FILE" | grep -c "-- |")
if [ "$documented_functions" -eq "$public_functions" ]; then
  echo "✅ All $public_functions functions documented"
else
  echo "❌ Documentation incomplete: $documented_functions/$public_functions"
fi
```

### Module Decomposition Validation (REQUIRED)

```bash
# Module size validation - MANDATORY splitting for large modules
MODULE_LINES=$(wc -l < "$MODULE_FILE")
if [ "$MODULE_LINES" -gt 300 ]; then
  echo "❌ MANDATORY: Module too large ($MODULE_LINES lines > 300)"
  echo "  REQUIRED: Split into focused sub-modules with single responsibilities"
else
  echo "✅ Module size appropriate: $MODULE_LINES lines"
fi

# Module responsibility validation - check for multiple primary concerns
FUNCTION_GROUPS=$(grep "^-- [A-Z]" "$MODULE_FILE" | wc -l)
if [ "$FUNCTION_GROUPS" -gt 1 ]; then
  echo "⚠️  Multiple function groups detected: $FUNCTION_GROUPS"
  echo "  CONSIDER: Splitting into separate modules for each responsibility"
else
  echo "✅ Single responsibility focus"
fi
```

---

## 🔄 PHASE 4: CROSS-AGENT VALIDATION PROTOCOL

### Final Orchestrator: code-style-enforcer

**Mission**: Coordinate all specialized agents and enforce complete compliance.

**Responsibilities**:

- Verify ALL validation gates pass simultaneously
- Coordinate between agents for overlapping concerns
- Ensure no regressions introduced by any agent
- Mandate re-iteration if ANY validation fails
- Grant final approval only when EVERY criterion is met

### Mandatory Iteration Protocol

**Requirements**:

1. If ANY validation fails → Return to appropriate specialized agent
2. No 'partial completion' allowed by any agent
3. Cross-agent communication required for overlapping work
4. Final approval requires unanimous compliance across all areas
5. Concrete validation scripts must show 0 violations before approval

### Zero Tolerance Enforcement

**Agents are FORBIDDEN from claiming completion until**:

- Concrete validation scripts show 0 violations
- ALL quality gates pass simultaneously
- Cross-agent validation confirms compliance
- Build system integration validated completely
- code-style-enforcer grants final approval

---

## 🎯 COMPLETE SUCCESS CRITERIA MATRIX

### ✅ Technical Standards (100% REQUIRED)

- **Function Design**: ≤15 lines, ≤4 parameters, ≤4 branches per function
- **Import Patterns**: 100% qualified imports (types unqualified, functions qualified)
- **Record Access**: 0 record-dot syntax, complete lens integration with makeLenses
- **Style Consistency**: where over let, parentheses over $, proper variable naming

### ✅ Architectural Quality (100% REQUIRED - MANDATORY MODULE SPLITTING)

- **Single Responsibility**: Each module has one clear, focused purpose
- **Module Decomposition**: MANDATORY splitting of large modules (>300 lines) into focused sub-modules
- **Modular Design**: Specialized sub-modules for each distinct functional area
- **Module Organization**: Clear module hierarchy with logical grouping
- **Error Handling**: Rich error types with comprehensive input validation
- **Clean Interfaces**: Minimal coupling between modules and clear boundaries
- **Export Lists**: Explicit export lists exposing only necessary functions
- **Module Documentation**: Each new module has comprehensive purpose documentation

### ✅ Testing Excellence (100% REQUIRED - MUST CREATE TESTS)

- **Test Suite Creation**: MANDATORY creation of comprehensive test suite if missing
- **Coverage**: ≥80% test coverage across all functions and paths
- **Test Types**: Unit/property/integration tests as architecturally appropriate
- **Quality**: 0 anti-patterns (no lazy assertions, Show tests, lens getter/setter tests)
- **Error Testing**: All error conditions and edge cases covered
- **Test Organization**: Tests organized in test/ directory with proper module structure
- **Test Naming**: Tests follow consistent naming conventions (Test.Unit.Module.Function)
- **Test Documentation**: All test modules have clear documentation and examples

### ✅ Documentation Standard (100% REQUIRED)

- **Module Documentation**: Comprehensive module-level Haddock with architecture explanation
- **Function Documentation**: All public functions with examples, error descriptions, @since tags
- **Design Documentation**: Architecture decisions and patterns clearly explained
- **Build Validation**: Haddock builds without warnings or errors

### ✅ Build System Integration (100% REQUIRED)

- **Compilation**: `make build` shows 0 errors, 0 warnings
- **Testing**: `make test` shows 100% tests pass
- **Linting**: `make lint` shows 0 violations
- **Formatting**: Code passes ormolu formatting standards

---

## 🚨 EXECUTION PROTOCOL

### Step 1: Comprehensive Analysis

Use analyze-architecture agent to perform complete architectural assessment:

```
Analyze $ARGUMENTS for complete CLAUDE.md compliance. Generate:
- Detailed violation inventory with line numbers and severity scores
- Function size/complexity/parameter violations
- Import qualification pattern violations
- Record access and lens integration violations
- Documentation completeness gaps
- Modularization opportunities for sub-module extraction
- Performance optimization recommendations
- Prioritized implementation roadmap with concrete success criteria

Provide specific examples and transformation requirements for each violation.
```

### Step 2: Specialized Agent Deployment

Deploy appropriate specialized agents based on analysis results:

```
Based on architectural analysis, deploy specialized agents for $ARGUMENTS with zero tolerance enforcement:

• validate-functions: Fix all function size/complexity/parameter violations
• validate-imports: Enforce mandatory qualified import patterns
• validate-lenses: Complete record access transformation to lens operations
• validate-documentation: Ensure comprehensive Haddock coverage
• analyze-tests + validate-tests: CREATE comprehensive test suite and achieve test quality requirements
  - MANDATORY: Create test files if they don't exist
  - MANDATORY: Achieve ≥80% test coverage
  - MANDATORY: Test all public functions and error conditions
• let-to-where-refactor + operator-refactor: Apply style consistency
• module-structure-auditor: MANDATORY module decomposition and architectural improvements
  - MANDATORY: Split modules >300 lines into focused sub-modules
  - MANDATORY: Create separate modules for distinct responsibilities
  - MANDATORY: Implement clean module interfaces
• validate-format: Ensure formatting compliance

CRITICAL REQUIREMENT: Each agent must validate their work using make build or make test. No agent may claim completion until their specific validation shows 0 violations. Agents must iterate until ALL requirements are met.
```

### Step 3: Final Validation and Approval

Use code-style-enforcer for comprehensive final validation:

```
Perform final comprehensive validation of $ARGUMENTS refactoring:

MANDATORY VALIDATION CHECKLIST (ALL MUST PASS):
• make build → 0 errors, 0 warnings
• make test → 100% tests pass
• test-quality-audit → 0 anti-patterns
• Function validation → All ≤15 lines, ≤4 params, ≤4 branches
• Import validation → 100% qualified compliance
• Record validation → 0 record-dot syntax usage
• Documentation validation → Complete Haddock coverage
• Test creation → MANDATORY creation of comprehensive test suite if missing
• Coverage validation → ≥80% test coverage
• Module decomposition → MANDATORY splitting of large modules into focused sub-modules

ZERO TOLERANCE: Only approve when EVERY validation passes. If ANY validation fails, coordinate with appropriate specialized agents for correction and re-validation.
```

---

## 🔥 ENFORCEMENT GUARANTEE

### Agents are FORBIDDEN from completion until:

1. **Concrete Validation**: All validation scripts show 0 violations
2. **Quality Gates**: ALL build/test/lint commands pass
3. **Test Suite Creation**: MANDATORY comprehensive test suite created if missing
4. **Module Decomposition**: MANDATORY module splitting completed for large modules (>300 lines)
5. **Cross-Validation**: Other agents confirm no regressions
6. **Complete Compliance**: Every CLAUDE.md standard verified
7. **Final Approval**: code-style-enforcer grants consensus approval

### Mandatory Iteration Protocol:

- If ANY validation fails → Return to appropriate agent
- No 'partial completion' permitted
- Cross-agent communication required
- Final approval requires unanimous compliance

### Success Definition:

**ONLY WHEN ALL CRITERIA ARE MET:**

- Module achieves complete CLAUDE.md compliance
- Build system integration validated
- Test quality and coverage verified
- Documentation completeness confirmed
- Agent consensus achieved

**ONLY THEN AND ONLY THEN ARE AGENTS SATISFIED!**

---

## 📋 QUICK VALIDATION CHECKLIST

For manual verification, run these commands after refactoring:

```bash
# Build validation
make build 2>&1 | grep -E '(error|warning)' || echo '✅ Build clean'

# Test validation
make test 2>&1 | grep -E '(failed|error)' || echo '✅ All tests pass'

# Anti-pattern validation
.claude/commands/test-quality-audit test/ 2>/dev/null | grep -E '(violations|patterns)' || echo '✅ No anti-patterns'

# Function size validation
echo "Checking function sizes..." && grep -n '^[a-zA-Z].*::' "$ARGUMENTS" | while read line; do
  func_line=$(echo "$line" | cut -d: -f1)
  next_func=$(tail -n +$((func_line + 1)) "$ARGUMENTS" | grep -n '^[a-zA-Z].*::' | head -1 | cut -d: -f1)
  if [ -z "$next_func" ]; then
    length=$(wc -l < "$ARGUMENTS")
    length=$((length - func_line))
  else
    length=$((next_func - 1))
  fi
  if [ "$length" -gt 15 ]; then
    echo "❌ Function at line $func_line: $length lines"
  fi
done || echo '✅ All functions within limits'

# Import qualification check
grep "^import [^(]*$" "$ARGUMENTS" | grep -v "qualified" | wc -l | grep "^0$" && echo '✅ All imports qualified' || echo '❌ Unqualified imports found'

# Record-dot syntax check
grep -n "\._\|\..*=" "$ARGUMENTS" | wc -l | grep "^0$" && echo '✅ No record-dot syntax' || echo '❌ Record-dot violations found'
```

This unified orchestration ensures complete CLAUDE.md compliance through systematic analysis, specialized agent deployment, and zero tolerance enforcement. Every aspect of the module will be transformed to meet the highest standards, with concrete validation at every step.

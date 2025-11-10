# Unified Test Quality Orchestration Command

**Task:** Execute comprehensive test quality validation and creation with zero tolerance enforcement for module: `$ARGUMENTS`.

- **Scope**: Complete test suite creation, validation, and quality enforcement
- **Standards**: 100% CLAUDE.md test compliance with mandatory ≥80% coverage
- **Process**: Analysis → Test Creation → Validation → Quality Gates → Final Approval
- **Enforcement**: Zero tolerance - agents must achieve maximum test coverage and quality

---

## 🚀 TEST ORCHESTRATION OVERVIEW

### Mission Statement

Transform the target module to achieve comprehensive test coverage through systematic analysis, automated test creation, and mandatory quality validation. No agent may claim completion until concrete validation shows ≥80% coverage and all quality gates pass.

### Core Principles

- **Zero Tolerance**: No missing tests or low coverage allowed
- **Maximum Coverage**: Target ≥85% coverage for excellence
- **Quality First**: All tests must assert meaningful behavior
- **Agent Coordination**: Mandatory iteration until consensus
- **Complete Validation**: Every test requirement enforced

---

## 🔍 PHASE 1: COMPREHENSIVE TEST ANALYSIS

### Primary Analysis Agent: analyze-tests

**Mission**: Perform deep test coverage analysis and generate complete gap inventory.

**Requirements**:

- Complete test suite analysis across Unit/Property/Golden/Integration
- Comprehensive coverage analysis with gap identification
- Function mapping and edge case analysis
- Anti-pattern detection and quality assessment
- Missing test category identification
- Property test gap analysis
- Integration test scenario mapping
- Performance and security test assessment
- Prioritized test creation roadmap

**Deliverables**:

- Detailed test coverage report with gap analysis
- Missing test inventory with specific recommendations
- Anti-pattern violations with fix requirements
- Comprehensive test creation templates
- Quality improvement roadmap

---

## 🏗️ PHASE 2: MANDATORY TEST CREATION

### Test Creation Agent: validate-test-creation

**Mission**: Create comprehensive test suites with zero tolerance for missing tests.

**Critical Requirements**:

- **MANDATORY**: Create test files if none exist (zero tolerance)
- **MANDATORY**: Achieve ≥80% test coverage for all functions
- **MANDATORY**: Test all error conditions and edge cases
- **MANDATORY**: Property tests for mathematical/logical operations
- **MANDATORY**: Anti-pattern elimination (no lazy assertions, mock functions)
- **MANDATORY**: Integration tests for module interactions
- **MANDATORY**: Security tests for attack vectors
- **MANDATORY**: Performance tests for resource validation

**Test Categories Required**:

```haskell
-- MANDATORY: Complete test suite structure
tests :: TestTree
tests = testGroup "ModuleName Tests"
  [ unitTests           -- ALL public functions tested
  , propertyTests       -- Laws and invariants verified
  , edgeCaseTests       -- Boundary conditions covered
  , errorConditionTests -- ALL error paths tested
  , integrationTests    -- Module interactions validated
  , performanceTests    -- Resource usage verified
  , securityTests       -- Attack vectors tested
  ]
```

**Zero Tolerance Validation**:

- Must achieve ≥80% coverage minimum
- Must test ALL public functions
- Must eliminate ALL anti-patterns
- Must validate ALL error conditions

---

## 🧪 PHASE 3: TEST EXECUTION AND VALIDATION

### Validation Agent: validate-tests

**Mission**: Execute test suites and validate results with mandatory quality gates.

**Mandatory Validation Gates**:

```bash
# Build validation - MUST compile successfully
make build

# Test execution - MUST pass all tests
make test

# Coverage validation - MUST achieve ≥80% coverage
make test-coverage

# Quality audit - MUST show 0 violations
.claude/commands/test-quality-audit test/

# Lint validation - MUST pass hlint checks
make lint

# Format validation - MUST pass formatting checks
make format
```

**Quality Requirements**:

- 100% tests must pass
- ≥80% coverage across all categories
- 0 anti-pattern violations
- 0 lazy assertions or mock functions
- 0 reflexive equality tests
- Meaningful assertions for all test cases

---

## ⚖️ PHASE 4: COMPREHENSIVE QUALITY ENFORCEMENT

### Quality Standards Validation

**Test Content Quality**:

❌ **FORBIDDEN Patterns (Zero Tolerance)**:

```haskell
-- VIOLATIONS: Must be eliminated
assertBool "" True                    -- Meaningless assertion
assertBool "should work" True         -- Mock assertion
x @?= x                              -- Reflexive equality
isValid _ = True                     -- Always-true mock
Name.main /= Name.true               -- Meaningless distinctness
assertBool "non-empty" (not (null result))  -- Weak validation
"text" `isInfixOf` result            -- Weak contains check
```

✅ **REQUIRED Patterns (Mandatory)**:

```haskell
-- CORRECT: Meaningful assertions
Name.toChars Name.main @?= "main"                    -- Exact value
show Package.core @?= "Name {_author = elm, _project = core}"  -- Complete structure
parseExpression "f(x)" @?= Right (Call func [arg])   -- Exact AST
case parseInvalid "bad" of                           -- Proper error testing
  Left (ParseError msg) -> assertBool "has error message" (msg == ["Error message"])
  _ -> assertFailure "Expected ParseError"
```

**Test Organization Quality**:

- Each test module has comprehensive Haddock documentation
- Test functions follow ≤15 line limit
- Test organization matches module structure
- Proper QuickCheck generators and properties
- Integration with test discovery in test/Main.hs

---

## 🔥 PHASE 5: COORDINATED AGENT DEPLOYMENT

### Agent Coordination Protocol

**Sequential Agent Workflow**:

```
1. analyze-tests           → Generate comprehensive test gap analysis
2. validate-test-creation  → Create missing tests with quality enforcement
3. validate-tests          → Execute tests and validate results
4. analyze-tests           → Re-analyze coverage and quality
5. Final validation        → Comprehensive quality gate enforcement
```

**Agent Integration Requirements**:

- Each agent must validate their specific domain
- Cross-agent validation required for overlapping concerns
- Iterative improvement until all standards met
- No agent may claim completion with violations

**Concrete Validation Protocol**:

```bash
# Phase 1: Analysis
echo "=== PHASE 1: Test Analysis ==="
# Agent analyzes existing tests and identifies gaps

# Phase 2: Test Creation
echo "=== PHASE 2: Test Creation ==="
# Agent creates comprehensive test suites for gaps

# Phase 3: Execution Validation
echo "=== PHASE 3: Test Execution ==="
make test 2>&1 | tee test_results.log
test_failures=$(grep -c "FAIL" test_results.log || echo "0")
if [ "$test_failures" -gt 0 ]; then
  echo "❌ $test_failures test failures - returning to test creation"
  exit 1
fi

# Phase 4: Coverage Validation
echo "=== PHASE 4: Coverage Validation ==="
coverage_result=$(make test-coverage | grep "expressions used" | awk '{print $1}' | sed 's/%//')
if [ "$coverage_result" -lt 80 ]; then
  echo "❌ Coverage insufficient: $coverage_result% - returning to test creation"
  exit 1
fi

# Phase 5: Quality Validation
echo "=== PHASE 5: Quality Validation ==="
if [ -x .claude/commands/test-quality-audit ]; then
  audit_violations=$(.claude/commands/test-quality-audit test/ | grep -c "❌" || echo "0")
  if [ "$audit_violations" -gt 0 ]; then
    echo "❌ $audit_violations quality violations - returning to test creation"
    exit 1
  fi
fi

echo "✅ ALL VALIDATION GATES PASSED"
```

---

## 📊 COMPREHENSIVE SUCCESS CRITERIA

### ✅ Test Coverage Excellence (100% REQUIRED)

- **Function Coverage**: 100% of public functions tested
- **Line Coverage**: ≥80% minimum, target ≥85% for excellence
- **Branch Coverage**: All conditional paths tested
- **Error Coverage**: All error conditions and edge cases tested
- **Integration Coverage**: All module interactions validated

### ✅ Test Quality Standards (100% REQUIRED)

- **Anti-Pattern Elimination**: 0 violations of forbidden patterns
- **Meaningful Assertions**: All tests assert specific, exact behavior
- **Comprehensive Edge Cases**: Boundary conditions, unicode, empty inputs
- **Error Path Validation**: All error types and messages tested
- **Property Verification**: Laws and invariants validated where applicable

### ✅ Test Organization Excellence (100% REQUIRED)

- **Module Structure**: Tests organized by category (Unit/Property/Golden/Integration)
- **Function Organization**: ≤15 lines per test function
- **Documentation**: Complete Haddock documentation for test modules
- **Import Compliance**: CLAUDE.md import standards followed
- **Registration**: All tests registered in test/Main.hs

### ✅ Build System Integration (100% REQUIRED)

- **Compilation**: `make build` shows 0 errors, 0 warnings
- **Test Execution**: `make test` shows 100% tests pass
- **Coverage Calculation**: `make test-coverage` shows ≥80% coverage
- **Quality Audit**: Test quality audit shows 0 violations
- **Formatting**: Code passes hlint and ormolu standards

---

## 🎯 AGENT DEPLOYMENT STRATEGY

### Phase 1: Deep Analysis (analyze-tests)

```
Task: Analyze test coverage for module $ARGUMENTS with comprehensive gap detection

Requirements:
- Complete test suite discovery across test/Unit, test/Property, test/Golden, test/Integration
- Function coverage analysis with mapping to source module exports
- Edge case gap identification with systematic boundary analysis
- Anti-pattern detection with specific violation reporting
- Missing test category identification with recommendations
- Integration scenario analysis with module interaction mapping
- Performance test gap analysis with resource validation requirements
- Security test gap analysis with attack vector coverage

Deliverables:
- Comprehensive test gap analysis report
- Specific test creation recommendations
- Anti-pattern violation inventory
- Coverage improvement roadmap
```

### Phase 2: Comprehensive Test Creation (validate-test-creation)

```
Task: Create comprehensive test suite for module $ARGUMENTS with zero tolerance enforcement

MANDATORY REQUIREMENTS:
- Create test files if none exist (zero tolerance for missing tests)
- Achieve ≥80% test coverage across all function and error paths
- Implement comprehensive edge case testing (empty, boundary, unicode, malformed inputs)
- Create property tests for mathematical and logical operations
- Eliminate all anti-patterns (no mock functions, reflexive tests, lazy assertions)
- Implement integration tests for module interactions
- Create security tests for attack vector validation
- Implement performance tests for resource usage validation

VALIDATION CRITERIA:
- ALL public functions must have test coverage
- ALL error conditions must be tested with specific error validation
- ALL edge cases must be covered with systematic boundary testing
- Test organization must follow CLAUDE.md standards
- Test quality audit must show 0 violations
```

### Phase 3: Execution and Quality Validation (validate-tests)

```
Task: Execute and validate test suite for module $ARGUMENTS with mandatory quality gates

EXECUTION REQUIREMENTS:
- Run complete test suite with make test
- Generate coverage report with make test-coverage
- Execute quality audit with test-quality-audit
- Validate build integration with make build
- Verify formatting compliance with make lint and make format

QUALITY GATES (ALL MUST PASS):
- 100% tests must pass successfully
- ≥80% coverage must be achieved across all categories
- 0 quality violations in anti-pattern audit
- 0 build errors or warnings
- 0 formatting violations

ITERATION PROTOCOL:
- If any gate fails, coordinate with validate-test-creation for corrections
- Continue iteration until ALL gates pass
- Cannot claim completion until all validation succeeds
```

---

## 🔄 MANDATORY ITERATION PROTOCOL

### Zero Tolerance Enforcement

**Requirements**:

- If ANY test fails → Return to validate-test-creation agent
- If coverage <80% → Return to validate-test-creation agent
- If quality audit finds violations → Return to validate-test-creation agent
- If build fails → Return to validate-test-creation agent
- No 'partial completion' allowed by any agent

### Cross-Agent Communication

**Protocol**:

1. analyze-tests provides comprehensive gap analysis
2. validate-test-creation uses analysis to create complete test suite
3. validate-tests executes tests and validates all quality gates
4. If validation fails, return to validate-test-creation with specific requirements
5. Continue iteration until ALL criteria met
6. Final approval requires all agents to confirm compliance

### Success Definition

**ONLY WHEN ALL CRITERIA MET:**

- Module achieves ≥80% test coverage (target ≥85%)
- All tests pass consistently
- 0 anti-pattern violations
- 0 build errors or warnings
- Complete test organization and documentation
- Full integration with build system

**ONLY THEN ARE AGENTS SATISFIED!**

---

## 🛠️ TEST IMPLEMENTATION STANDARDS

### Test Module Template

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Comprehensive test suite for ModuleName.
--
-- This module provides complete test coverage including:
--
-- * Unit tests for all public functions
-- * Property tests for laws and invariants
-- * Edge case tests for boundary conditions
-- * Error condition tests for all failure modes
-- * Integration tests for module interactions
-- * Performance tests for resource validation
-- * Security tests for attack vector coverage
--
-- Target Coverage: ≥80% (≥85% for excellence)
-- Quality Standard: CLAUDE.md compliant with 0 anti-patterns
--
-- @since 0.19.1
module Test.Unit.ModuleNameTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import qualified ModuleName as Module

-- | Complete test suite for ModuleName
tests :: TestTree
tests = testGroup "ModuleName Tests"
  [ unitTests
  , propertyTests
  , edgeCaseTests
  , errorConditionTests
  , integrationTests
  , performanceTests
  , securityTests
  ]
```

### Test Quality Standards

**Unit Test Requirements**:

```haskell
-- ✅ REQUIRED: Exact value assertions
testExactBehavior :: TestTree
testExactBehavior = testCase "function produces exact output" $
  Module.processInput validInput @?= Right expectedOutput

-- ✅ REQUIRED: Complete error testing
testErrorConditions :: TestTree
testErrorConditions = testCase "invalid input produces specific error" $
  Module.processInput invalidInput @?= Left (ValidationError "specific error message")

-- ✅ REQUIRED: Edge case validation
testEdgeCases :: TestTree
testEdgeCases = testGroup "edge cases"
  [ testCase "empty input" $ Module.processInput "" @?= expectedEmptyResult
  , testCase "unicode input" $ Module.processInput "αβγ" @?= expectedUnicodeResult
  , testCase "maximum size input" $ Module.processInput maxInput @?= expectedMaxResult
  ]
```

**Property Test Requirements**:

```haskell
-- ✅ REQUIRED: Meaningful properties
propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "roundtrip property" $ \input ->
      Module.fromString (Module.toString input) === input
  , testProperty "idempotence" $ \input ->
      Module.process (Module.process input) === Module.process input
  , testProperty "error preservation" $ \invalidInput ->
      isLeft (Module.validate invalidInput) ==> isLeft (Module.process invalidInput)
  ]
```

---

## 📋 EXECUTION CHECKLIST

### Agent Coordination Workflow

```bash
# Phase 1: Comprehensive Analysis
echo "🔍 Phase 1: Analyzing test coverage and gaps..."
# analyze-tests agent performs comprehensive gap analysis

# Phase 2: Test Creation
echo "🏗️ Phase 2: Creating comprehensive test suite..."
# validate-test-creation agent creates missing tests

# Phase 3: Validation
echo "⚖️ Phase 3: Executing tests and validating quality..."
# validate-tests agent executes and validates

# Phase 4: Quality Gates
echo "🔥 Phase 4: Enforcing quality standards..."
# Comprehensive validation of all requirements

# Phase 5: Final Approval
echo "✅ Phase 5: Final approval and documentation..."
# Final validation and success confirmation
```

### Manual Validation Commands

```bash
# Build validation
make build && echo "✅ Build successful" || echo "❌ Build failed"

# Test execution
make test && echo "✅ All tests pass" || echo "❌ Test failures"

# Coverage validation
COVERAGE=$(make test-coverage | grep "expressions used" | awk '{print $1}' | sed 's/%//')
if [ "$COVERAGE" -ge 80 ]; then
  echo "✅ Coverage: $COVERAGE%"
else
  echo "❌ Coverage insufficient: $COVERAGE%"
fi

# Quality audit
if [ -x .claude/commands/test-quality-audit ]; then
  .claude/commands/test-quality-audit test/ | grep -q "❌" && echo "❌ Quality violations" || echo "✅ Quality audit passed"
fi

# Lint validation
make lint && echo "✅ Lint passed" || echo "❌ Lint violations"
```

---

## 🎓 EXCELLENCE CRITERIA

### Minimum Requirements (Must Achieve)

- ≥80% test coverage
- 100% tests pass
- 0 anti-pattern violations
- All public functions tested
- All error conditions tested

### Excellence Targets (Strive For)

- ≥85% test coverage
- Comprehensive property tests
- Security vulnerability testing
- Performance constraint validation
- Golden test integration
- Comprehensive integration scenarios

This unified test orchestration ensures systematic test quality enforcement through coordinated agent deployment, achieving comprehensive coverage and maintaining the highest testing standards throughout the Canopy compiler project.

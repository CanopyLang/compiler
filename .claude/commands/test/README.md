# Enhanced Test Quality Enforcement System

## Problem Solved

The previous agent system had a critical flaw: agents would claim completion while still having lazy test patterns like:
- `assertBool "" True` (tests nothing)
- `assertBool "should work" True` (meaningless) 
- `x @?= x` (reflexive equality)
- `_ = True` mock functions (fake validation)

## Solution: Zero Tolerance Enforcement

### 1. Mandatory Test Quality Audit

Every testing agent MUST run this script before claiming completion:
```bash
/home/quinten/fh/canopy/.claude/commands/test-quality-audit test/
```

This script detects **332 current violations** including:
- 197 lazy `assertBool` patterns
- 7 mock functions
- 29 reflexive equality tests  
- 53 trivial descriptions
- 46 always-true conditions

### 2. Enhanced Agent Instructions

All testing agents now have:
- **Zero tolerance** for lazy patterns
- **Mandatory cross-validation** between agents
- **Iterative improvement** requirements
- **Absolute completion validation**

### 3. Senior Developer Review Protocol

```
Phase 1: analyze-tests --zero-tolerance
Phase 2: validate-tests --cross-validate  
Phase 3: code-style-enforcer --final-review
Phase 4: Mandatory audit verification
```

## Usage

### Before Any Test Work:
```bash
# Check current violations
/home/quinten/fh/canopy/.claude/commands/test-quality-audit test/
```

### When Using Testing Agents:
Agents will now:
1. Detect violations automatically  
2. Fix patterns iteratively
3. Cross-validate with other agents
4. Run mandatory audit before completion
5. Continue until ZERO violations found

### Verification:
```bash
# Verify agents actually completed their work
/home/quinten/fh/canopy/.claude/commands/test-quality-audit test/
# Should show: "✅ AUDIT PASSED - All test quality requirements met"
```

## Forbidden Patterns (Will Cause Agent Failure)

```haskell
❌ assertBool "" True
❌ assertBool "should work" True  
❌ isValidModuleName _ = True
❌ testModule @?= testModule
❌ undefined
❌ assertBool "non-empty" (not (null result))
```

## Required Patterns (Agents Must Use)

```haskell
✅ ModuleName.toChars (ModuleName.fromChars "Main") @?= "Main"
✅ case parseExpression "f(x)" of
     Right (Call _ func [arg]) -> func @?= Var (Name.fromChars "f")
     Left err -> assertFailure ("Expected success, got: " ++ show err)
```

## Result

The enhanced system prevents agents from falsely claiming completion while lazy patterns remain. Agents must iterate until the audit shows zero violations, ensuring genuinely meaningful tests.
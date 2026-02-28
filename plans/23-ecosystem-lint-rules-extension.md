# Plan 23: Extended Lint Rules

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Low — additive new rules

## Problem

The linter has 6 built-in rules in `Lint/Rules.hs` but lacks many common compiler lint checks. The extensible pattern exists (`ruleRegistry`, lines 203-211) but needs more rules.

### Current Rules
1. UnusedImport
2. BooleanCase
3. UnnecessaryParens
4. DropConcatOfLists
5. UseConsOverConcat
6. MissingTypeAnnotation

## Implementation Plan

### Step 1: Add type safety lints

- **PartialFunction** — warn on `List.head`, `List.tail`, `Maybe.fromJust` usage
- **UnsafeCoerce** — detect Debug.todo used as a value
- **ShadowedVariable** — warn when a let/case binding shadows an outer name
- **UnusedVariable** — warn on bound but unused variables in let/case

### Step 2: Add performance lints

- **ListAppendInLoop** — detect `++ [x]` inside folds
- **UnnecessaryLazyPattern** — detect lazy patterns where strict would suffice
- **StringConcatInLoop** — detect repeated string concatenation vs StringBuilder

### Step 3: Add style lints

- **TooManyArguments** — warn on functions with >4 arguments
- **LongFunction** — warn on functions exceeding configurable line limit
- **MagicNumber** — detect literal numbers that should be named constants
- **InconsistentNaming** — detect camelCase/snake_case mixing

### Step 4: Add canopy.json lint configuration

```json
{
    "lints": {
        "unused-variable": "error",
        "magic-number": "warn",
        "long-function": { "level": "warn", "max-lines": 20 }
    }
}
```

### Step 5: CLI integration

- `canopy lint` — run all enabled lints
- `canopy lint --fix` — auto-fix where possible
- `canopy lint --rule=unused-variable` — run specific rule

### Step 6: Tests

- Test each new rule with positive and negative cases
- Test configuration override
- Test --fix for auto-fixable rules

## Dependencies
- Plan 16 (god module splits) for cleaner rule organization

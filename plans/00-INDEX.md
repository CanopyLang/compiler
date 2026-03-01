# Canopy A+ Production Readiness Plans — Audit v4

**Source**: Zero-trust production readiness audit (March 2026)
**Current Score**: 62/100 → Target: 95/100 (A+)
**Plans**: 15 tasks across 5 phases

---

## Phase 1: Architecture Foundation (Plans 01–03)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 01 | [Public/Internal Module Split](01-arch-module-exposure.md) | CRITICAL | Medium | Low |
| 02 | [InternalError Crash Site Remediation](02-arch-crash-remediation.md) | CRITICAL | Medium | Low |
| 03 | [Nested Case Violation Fixes](03-arch-nested-case-fixes.md) | HIGH | Small | Low |

## Phase 2: Type System — Flow-Level Intelligence (Plans 04–08)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 04 | [Flow-Level FFI Type Checking — Static Analysis of JavaScript](04-types-flow-narrowing.md) | CRITICAL | Large | Medium |
| 05 | [Sketchy-Null & Unsafe Operations Lint](05-types-sketchy-null-lint.md) | HIGH | Small | Low |
| 06 | [Opaque Type Supertype Bounds](06-types-opaque-bounds.md) | MEDIUM | Medium | Low |
| 07 | [Type Guards & Predicate Functions](07-types-type-guards.md) | HIGH | Medium | Medium |
| 08 | [Variance Annotations](08-types-variance.md) | MEDIUM | Medium | Medium |

## Phase 3: Performance (Plans 09–11)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 09 | [FFI Codegen String Elimination](09-perf-ffi-string-elimination.md) | HIGH | Small | Low |
| 10 | [Parallel Module Discovery](10-perf-parallel-discovery.md) | HIGH | Medium | Medium |
| 11 | [Advanced Optimization Passes](11-perf-advanced-optimizations.md) | CRITICAL | Large | Medium |

## Phase 4: Quality Enforcement (Plans 12–13)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 12 | [Test Coverage Enforcement with HPC](12-quality-coverage-enforcement.md) | CRITICAL | Medium | Low |
| 13 | [FFI Runtime Capability Enforcement](13-quality-ffi-capabilities.md) | HIGH | Medium | Medium |

## Phase 5: Developer Experience (Plans 14–15)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 14 | [LSP Feature Completion](14-dx-lsp-completion.md) | HIGH | Large | Medium |
| 15 | [Contributor Onboarding & Architecture Guide](15-dx-contributor-guide.md) | MEDIUM | Small | Low |

---

## Priority Summary

- **CRITICAL** (5): Plans 01, 02, 04, 11, 12
- **HIGH** (6): Plans 03, 05, 07, 09, 10, 13, 14
- **MEDIUM** (4): Plans 06, 08, 15

## Recommended Execution Order

1. **Immediate** (CRITICAL, foundation): 01, 02, 03
2. **This sprint** (HIGH, quick wins): 05, 09, 12
3. **Next sprint** (CRITICAL/HIGH, medium effort): 04, 07, 10, 11, 13
4. **Backlog** (Medium priority or Large effort): 06, 08, 14, 15

## Score Impact Estimate

| Phase | Plans | Score Delta |
|-------|-------|-------------|
| Phase 1 | 01-03 | +12 (62→74) |
| Phase 2 | 04-08 | +10 (74→84) |
| Phase 3 | 09-11 | +5 (84→89) |
| Phase 4 | 12-13 | +4 (89→93) |
| Phase 5 | 14-15 | +3 (93→96) |

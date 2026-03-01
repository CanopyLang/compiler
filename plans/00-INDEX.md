# Canopy Production Readiness Plans — Master Index

Generated from the comprehensive zero-trust production readiness audit (2026-03-01).
Audit score: **62/100**. Target: **90/100**.

---

## Priority Execution Order

### Phase 1: Critical Identity & Security (Plans 01–06)
Must be completed before any public release. These are existential risks.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 01 | [Elm Identity Purge](01-identity-elm-purge.md) | CRITICAL | Large | Medium |
| 02 | [Package Download Hash Verification](02-security-download-verification.md) | CRITICAL | Small | Low |
| 03 | [Trusted Key Store Population](03-security-trusted-keys.md) | CRITICAL | Small | Low |
| 04 | [Script Execution Sandboxing](04-security-script-sandbox.md) | HIGH | Small | Low |
| 05 | [HTML/JS Output Escaping](05-security-output-escaping.md) | HIGH | Small | Low |
| 06 | [FFI Codegen Injection Prevention](06-security-ffi-injection.md) | HIGH | Small | Low |

### Phase 2: Type System Soundness (Plans 07–09)
Compiler correctness is non-negotiable.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 07 | [Rigid Variable Unification Fix](07-soundness-rigid-var-unification.md) | CRITICAL | Medium | High |
| 08 | [Binary Cache Version Verification](08-soundness-cache-versioning.md) | HIGH | Small | Low |
| 09 | [Partial Function Elimination](09-soundness-partial-functions.md) | MEDIUM | Medium | Low |

### Phase 3: Critical DX Fixes (Plans 10–14)
Broken first-user experience and daily workflow issues.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 10 | [CLI Command Visibility Fix](10-dx-command-visibility.md) | CRITICAL | Small | Low |
| 11 | [Dual Command Type Unification](11-dx-command-type-unification.md) | HIGH | Medium | Medium |
| 12 | [Build Progress Indicators](12-dx-build-progress.md) | HIGH | Medium | Low |
| 13 | [Test Filter Implementation](13-dx-test-filter.md) | MEDIUM | Medium | Low |
| 14 | [Data-Destroying Orphan Instance Fix](14-dx-orphan-instances.md) | HIGH | Small | Medium |

### Phase 4: Performance (Plans 15–18)
Eliminate measured bottlenecks and add missing instrumentation.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 15 | [FFI String-to-Text Migration](15-perf-ffi-string-to-text.md) | HIGH | Medium | Medium |
| 16 | [Codegen Double Materialization Fix](16-perf-countNewlines.md) | MEDIUM | Small | Low |
| 17 | [Binary FFIInfo Round-Trip Fix](17-perf-binary-ffiinfo.md) | MEDIUM | Small | Low |
| 18 | [Comprehensive Benchmark Suite](18-perf-benchmarks.md) | MEDIUM | Medium | Low |

### Phase 5: Code Quality (Plans 19–23)
Bring codebase into compliance with CLAUDE.md standards.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 19 | [God Module Decomposition](19-quality-god-modules.md) | MEDIUM | Large | Medium |
| 20 | [Nested Case Expression Elimination](20-quality-nested-case.md) | MEDIUM | Large | Medium |
| 21 | [Wildcard Pattern Audit](21-quality-wildcard-patterns.md) | MEDIUM | Small | Low |
| 22 | [Path Traversal Hardening](22-security-path-traversal.md) | MEDIUM | Small | Low |
| 23 | [Documentation Accuracy Audit](23-quality-doc-accuracy.md) | LOW | Small | Low |

---

## Category Breakdown

### Security (6 plans)
01, 02, 03, 04, 05, 06

### Soundness (3 plans)
07, 08, 09

### Developer Experience (5 plans)
10, 11, 12, 13, 14

### Performance (4 plans)
15, 16, 17, 18

### Code Quality (5 plans)
19, 20, 21, 22, 23

---

## Estimated Total Effort

- **Small** (≤8 hours): 12 plans
- **Medium** (1–3 days): 8 plans
- **Large** (3–10 days): 3 plans

Estimated calendar time (single developer, full-time): ~4–6 weeks

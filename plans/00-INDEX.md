# Canopy Production Readiness Plans — Audit v3

**Source**: Zero-trust production readiness audit (March 2026)
**Audit Score**: 38/100 → Target: 85/100
**Plans**: 24 tasks across 6 phases

---

## Phase 1: Security (Plans 01–06)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 01 | [GitHub Fallback Hash Verification](01-security-github-fallback-hash.md) | CRITICAL | Small | Low |
| 02 | [Zip Bomb Protection](02-security-zip-bomb-protection.md) | HIGH | Small | Low |
| 03 | [Atomic Lock File Writes](03-security-atomic-lockfile.md) | HIGH | Small | Low |
| 04 | [Vendor Symlink Safety](04-security-vendor-symlink.md) | HIGH | Small | Low |
| 05 | [JS Escape Completeness](05-security-js-escape-completeness.md) | MEDIUM | Small | Low |
| 06 | [Trusted Key Store Bootstrap](06-security-trusted-key-bootstrap.md) | MEDIUM | Medium | Medium |

## Phase 2: Type System Soundness (Plans 07–08)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 07 | [Occurs Check Alias Body](07-soundness-occurs-check-alias.md) | CRITICAL | Small | Low |
| 08 | [Let-Generalization Property Tests](08-soundness-let-generalization-tests.md) | HIGH | Medium | Low |

## Phase 3: Resilience (Plans 09–10)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 09 | [Discovery Parse Failure Graceful Degradation](09-resilience-discovery-parse-failure.md) | HIGH | Small | Medium |
| 10 | [Parallel Build Cycle Detection](10-resilience-parallel-cycle-detection.md) | HIGH | Small | Low |

## Phase 4: Performance (Plans 11–16)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 11 | [Codegen String Impedance](11-perf-codegen-string-impedance.md) | CRITICAL | Medium | Medium |
| 12 | [Test Runner String Processing](12-perf-test-runner-string.md) | HIGH | Small | Low |
| 13 | [Newline Counting Double Materialization](13-perf-newline-counting.md) | MEDIUM | Small | Low |
| 14 | [StrictData as Default Extension](14-perf-strictdata-default.md) | MEDIUM | Medium | Medium |
| 15 | [Binary Build Cache](15-perf-binary-build-cache.md) | HIGH | Medium | Low |
| 16 | [Hot-Path String Allocations](16-perf-hotpath-string-alloc.md) | HIGH | Small | Low |

## Phase 5: Developer Experience (Plans 17–20)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 17 | [Formatter Comment Preservation](17-dx-formatter-comment-preservation.md) | HIGH | Large | High |
| 18 | [Structured Error Migration](18-dx-structured-error-migration.md) | CRITICAL | Medium | Low |
| 19 | [REPL Incremental Compilation](19-dx-repl-incremental.md) | MEDIUM | Large | High |
| 20 | [Benchmark Per-Phase Timing](20-dx-benchmark-per-phase.md) | MEDIUM | Small | Low |

## Phase 6: Code Quality & Ecosystem (Plans 21–24)

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 21 | [Deceptive Test Cleanup](21-quality-deceptive-test-cleanup.md) | HIGH | Medium | Low |
| 22 | [Row/Col Word16 Overflow](22-resilience-row-col-overflow.md) | MEDIUM | Medium | Medium |
| 23 | [God Module Decomposition](23-quality-god-module-splits.md) | MEDIUM | Medium | Low |
| 24 | [Real Dependency Solver](24-ecosystem-real-solver.md) | HIGH | Large | Medium |

---

## Priority Summary

- **CRITICAL** (4): Plans 01, 07, 11, 18
- **HIGH** (12): Plans 02, 03, 04, 08, 09, 10, 12, 15, 16, 17, 21, 24
- **MEDIUM** (8): Plans 05, 06, 13, 14, 19, 20, 22, 23

## Recommended Execution Order

1. **Immediate** (CRITICAL, Small effort): 01, 07
2. **This sprint** (HIGH, Small effort): 02, 03, 04, 09, 10, 12, 16
3. **Next sprint** (HIGH/CRITICAL, Medium effort): 08, 11, 15, 18, 21
4. **Backlog** (Medium priority or Large effort): 05, 06, 13, 14, 17, 19, 20, 22, 23, 24

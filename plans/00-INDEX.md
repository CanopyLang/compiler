# Canopy Production Readiness Plans — Master Index

Generated from the comprehensive production readiness audit (2026-02-28).
Audit score: **68/100**. Target: **90/100**.

LSP is implemented in TypeScript (packages/canopy-lsp/) — see Plan 37 for packaging and publishing.

---

## Priority Execution Order

### Phase 1: Critical Security & Resilience (Plans 01-05, 51)
Must be done before any public release.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 51 | [Resilient Package Fetching with GitHub Fallback](51-resilience-package-fetch-fallback.md) | CRITICAL | Large | Medium |
| 01 | [Cryptographic Package Signing](01-security-package-signing.md) | CRITICAL | Large | High |
| 02 | [Timing-Safe Hash Comparison](02-security-timing-safe-comparison.md) | HIGH | Small | Low |
| 03 | [Registry Fallback Transparency](03-security-registry-fallback.md) | HIGH | Medium | Medium |
| 04 | [File URL Path Traversal Prevention](04-security-path-traversal.md) | HIGH | Small | Low |
| 05 | [FFI Strict Mode CLI Integration](05-security-ffi-strict-mode.md) | HIGH | Small | Low |

### Phase 2: Critical Scalability & Quality (Plans 06-08, 14, 17-18)
Fix the worst bottlenecks and enforce quality.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 06 | [Bounded Parallel Compilation](06-scalability-bounded-parallelism.md) | HIGH | Medium | Medium |
| 07 | [O(n) Occurs Check Fix](07-scalability-occurs-check.md) | HIGH | Small | Low |
| 08 | [Parser Recursion Depth Limits](08-scalability-parser-depth-limits.md) | HIGH | Medium | Medium |
| 14 | [Stringly-Typed Newtypes](14-quality-stringly-typed-newtypes.md) | MEDIUM | Medium | Low |
| 17 | [Test Coverage Enforcement](17-quality-test-coverage-enforcement.md) | HIGH | Small | Low |
| 18 | [Test Suite Reliability Audit](18-quality-flaky-test-fix.md) | MEDIUM | Small | Low |

### Phase 3: Developer Experience (Plans 10, 25, 28, 32, 37, 49)
Essential DX improvements and quick wins.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 10 | [canopy new Command](10-dx-canopy-new.md) | HIGH | Medium | Low |
| 25 | [Error Message Quality](25-dx-error-messages.md) | HIGH | Medium | Low |
| 28 | [Reproducible Build Verification](28-dx-reproducible-builds.md) | HIGH | Medium | Low |
| 32 | [Input Size Limits](32-security-input-size-limits.md) | HIGH | Small | Low |
| 37 | [Editor Integration (LSP Publishing)](37-dx-editor-integration.md) | HIGH | Medium | Low |
| 49 | [Git History Cleanup](49-quality-git-history-cleanup.md) | HIGH | Small | HIGH |

### Phase 4: Architecture & CI (Plans 16, 20, 30-31, 39)
Structural improvements and CI hardening.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 16 | [God Module Decomposition](16-quality-god-module-splits.md) | MEDIUM | Large | Medium |
| 20 | [Eliminate O(n²) Patterns](20-performance-on2-patterns.md) | HIGH | Small | Low |
| 30 | [Package DAG Enforcement](30-architecture-package-dag-enforcement.md) | MEDIUM | Small | Low |
| 31 | [Error Type Consolidation](31-architecture-error-type-consolidation.md) | MEDIUM | Medium | Medium |
| 39 | [CI Pipeline Hardening](39-quality-ci-pipeline.md) | HIGH | Medium | Low |

### Phase 5: Medium-Term Improvements (Plans 09, 11-13, 19, 21, 23, 26-27, 29, 33-35)
Feature depth and ecosystem.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 09 | [Incremental Type Checking](09-scalability-incremental-type-checking.md) | MEDIUM | Large | High |
| 11 | [Private Registry Support](11-dx-private-registry.md) | MEDIUM | Medium | Medium |
| 12 | [Monorepo/Workspace Support](12-dx-monorepo-support.md) | MEDIUM | Large | Medium |
| 13 | [Hot Reload Enhancement](13-dx-hot-reload.md) | MEDIUM | Medium | Medium |
| 19 | [Performance Benchmarks](19-performance-benchmarks.md) | MEDIUM | Medium | Low |
| 21 | [Memory Profiling Infrastructure](21-performance-memory-profiling.md) | MEDIUM | Small | Low |
| 23 | [Extended Lint Rules](23-ecosystem-lint-rules-extension.md) | MEDIUM | Medium | Low |
| 24 | [Tree-Shaking Verification](24-ecosystem-tree-shaking-verification.md) | MEDIUM | Medium | Low |
| 26 | [REPL Improvements](26-dx-repl-improvements.md) | MEDIUM | Medium | Low |
| 27 | [canopy.json Format Improvements](27-dx-canopy-json-format.md) | MEDIUM | Medium | Medium |
| 29 | [Documentation Generation](29-dx-documentation-generation.md) | MEDIUM | Medium | Low |
| 33 | [Dependency Audit Command](33-security-dependency-audit.md) | MEDIUM | Medium | Low |
| 34 | [Code Formatter](34-dx-canopy-format.md) | MEDIUM | Large | Medium |
| 35 | [Test Framework Enhancement](35-dx-canopy-test-framework.md) | MEDIUM | Medium | Low |
| 50 | [Strict Data Structure Audit](50-performance-strict-data-structures.md) | MEDIUM | Small | Low |

### Phase 6: Long-Term / Aspirational (Plans 15, 22, 36, 38, 40-48)
Strategic capabilities and polish.

| # | Plan | Priority | Effort | Risk |
|---|------|----------|--------|------|
| 15 | [FFI Namespace Unification](15-quality-ffi-namespace-unification.md) | MEDIUM | Medium | Medium |
| 22 | [Plugin System](22-ecosystem-plugin-system.md) | LOW | Large | High |
| 36 | [WebIDL Integration](36-architecture-webidl-integration.md) | LOW | Medium | Low |
| 38 | [unsafePerformIO Audit](38-quality-unsafe-performio-audit.md) | LOW | Small | Low |
| 40 | [Binary Cache Evolution](40-architecture-binary-cache-evolution.md) | MEDIUM | Small | Low |
| 41 | [Self-Update Command](41-dx-canopy-upgrade.md) | LOW | Medium | Medium |
| 42 | [Lazy Import Resolution](42-performance-lazy-import-resolution.md) | MEDIUM | Medium | Medium |
| 43 | [Contributor Experience](43-quality-contributor-experience.md) | MEDIUM | Medium | Low |
| 44 | [Code Generation Security](44-security-sandbox-codegen.md) | MEDIUM | Small | Low |
| 45 | [Package Publishing](45-dx-canopy-publish.md) | MEDIUM | Medium | Medium |
| 46 | [Parallel Type Checking](46-performance-parallel-type-checking.md) | LOW | Large | High |
| 47 | [MCP Server Enhancement](47-ecosystem-canopy-mcp.md) | LOW | Medium | Low |
| 48 | [Package Diff Enhancement](48-dx-canopy-diff.md) | LOW | Small | Low |

---

## Category Breakdown

### Security (8 plans)
01, 02, 03, 04, 05, 32, 33, 44

### Resilience (1 plan)
51

### Scalability & Performance (10 plans)
06, 07, 08, 09, 19, 20, 21, 42, 46, 50

### Developer Experience (12 plans)
10, 13, 25, 26, 27, 28, 29, 34, 35, 37, 41, 48

### Code Quality (9 plans)
14, 15, 16, 17, 18, 31, 38, 39, 43

### Architecture (4 plans)
30, 36, 40, 49

### Ecosystem (5 plans)
22, 23, 24, 45, 47

---

## Estimated Total Effort

- **Small** (≤8 hours): 15 plans
- **Medium** (1-3 days): 24 plans
- **Large** (3-10 days): 12 plans

Estimated calendar time (single developer, full-time): ~4-5 months
With parallelization (2-3 developers): ~2-3 months

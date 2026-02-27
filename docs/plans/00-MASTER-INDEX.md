# Canopy Production Readiness — Master Implementation Plan

**Generated:** 2026-02-27
**Baseline:** Production Readiness Score 38/100, all 2,376 tests passing
**Goal:** Production Readiness Score 80+/100

---

## Priority Tiers

### Tier 0 — Blockers (Must fix before any public release)
| # | Plan | Est. Effort | Files Affected |
|---|------|-------------|----------------|
| 01 | [Remove HTTP_DEBUG statements](./01-remove-debug-statements.md) | 30 min | 1 |
| 02 | [Fix broken Makefile targets](./02-fix-makefile-targets.md) | 1 hour | 1 |
| 03 | [Remove dead code and stray files](./03-remove-dead-code.md) | 2 hours | ~12 |
| 04 | [Write README.md and CONTRIBUTING.md](./04-write-readme-contributing.md) | 4 hours | 2 |
| 05 | [Fix grammar errors in CLI help text](./05-fix-cli-grammar.md) | 30 min | 1 |

### Tier 1 — Critical Architecture (Pre-beta requirements)
| # | Plan | Est. Effort | Files Affected |
|---|------|-------------|----------------|
| 06 | [Add -Wall to all source files](./06-add-wall-all-files.md) | 1 day | 29+ |
| 07 | [Split Reporting/Error/Syntax.hs](./07-split-error-syntax.md) | 2 days | ~12 |
| 08 | [Add binary schema versions to .elco cache](./08-binary-schema-versions.md) | 1 day | ~8 |
| 09 | [Eliminate triple-parse per module](./09-eliminate-triple-parse.md) | 2 days | ~5 |
| 10 | [Fix FFI path traversal vulnerability](./10-fix-ffi-path-traversal.md) | 4 hours | 2 |

### Tier 2 — Type Safety and Soundness
| # | Plan | Est. Effort | Files Affected |
|---|------|-------------|----------------|
| 11 | [Fix unsafeCoerce in argument parser](./11-fix-unsafe-coerce.md) | 4 hours | 1 |
| 12 | [Harden UnionFind partial patterns](./12-harden-unionfind.md) | 4 hours | 1 |
| 13 | [Fix inferHome error/bottom value](./13-fix-inferhome-bottom.md) | 2 hours | 1 |
| 14 | [Replace stringly-typed FFI interfaces](./14-replace-stringly-typed.md) | 1 day | ~8 |
| 15 | [Unify duplicate FFIType definitions](./15-unify-ffitype.md) | 4 hours | ~4 |

### Tier 3 — Performance and Scalability
| # | Plan | Est. Effort | Files Affected |
|---|------|-------------|----------------|
| 16 | [Fix O(n^2) patterns in type solver](./16-fix-solver-quadratic.md) | 1 day | 1 |
| 17 | [Replace String intermediates in codegen](./17-fix-codegen-string.md) | 2 days | ~4 |
| 18 | [Replace String-based HashValue](./18-fix-hashvalue-string.md) | 4 hours | 2 |
| 19 | [Fix O(n^2) cycle detection](./19-fix-cycle-detection.md) | 4 hours | 1 |
| 20 | [Optimize incremental cache I/O](./20-optimize-cache-io.md) | 1 day | 3 |

### Tier 4 — Ecosystem and DX
| # | Plan | Est. Effort | Files Affected |
|---|------|-------------|----------------|
| 21 | [Add lock file support](./21-add-lock-file.md) | 3 days | ~6 |
| 22 | [Fix canopy.json silent parse failures](./22-fix-json-parse-errors.md) | 4 hours | 2 |
| 23 | [Upgrade SHA-1 to SHA-256 for packages](./23-upgrade-sha256.md) | 1 day | ~3 |
| 24 | [Fix import alias naming conventions](./24-fix-import-aliases.md) | 2 days | ~60 |
| 25 | [Fix hie.yaml for HLS support](./25-fix-hie-yaml.md) | 1 hour | 1 |

### Tier 5 — Hardening and Polish
| # | Plan | Est. Effort | Files Affected |
|---|------|-------------|----------------|
| 26 | [Wire orphan canopy-core tests into build](./26-wire-orphan-tests.md) | 2 hours | 2 |
| 27 | [Fix weak test assertions](./27-fix-weak-test-assertions.md) | 1 day | ~5 |
| 28 | [Move Data.* modules to Canopy.Data.*](./28-move-data-namespace.md) | 2 days | ~80 |
| 29 | [Split remaining god modules](./29-split-god-modules.md) | 3 days | ~15 |
| 30 | [Implement FFI capability enforcement](./30-implement-capabilities.md) | 5 days | ~10 |

### Tier 6 — Strategic (Post-beta)
| # | Plan | Est. Effort | Files Affected |
|---|------|-------------|----------------|
| 31 | [Remove allow-newer from stack.yaml](./31-remove-allow-newer.md) | 1 day | 2 |
| 32 | [Implement fuzz testing runtime](./32-implement-fuzz-runtime.md) | 3 days | ~5 |
| 33 | [Integrate canopy-webidl into build](./33-integrate-webidl.md) | 1 day | 2 |
| 34 | [Add compilation benchmarks](./34-add-benchmarks.md) | 2 days | ~5 |
| 35 | [Package registry MVP](./35-package-registry.md) | 2 weeks | new package |

---

## Execution Order

**Week 1:** Plans 01-05 (Tier 0 — all blockers cleared)
**Week 2:** Plans 06, 08, 10, 11-13, 25 (safety and correctness)
**Week 3:** Plans 07, 09 (major architectural fixes)
**Week 4:** Plans 14-20 (type safety + performance)
**Weeks 5-6:** Plans 21-29 (ecosystem + polish)
**Weeks 7+:** Plans 30-35 (strategic)

**Validation after each tier:** `make build && make test` must pass with all 2,376+ tests green.

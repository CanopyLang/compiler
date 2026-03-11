# P08 + P01 + P02 + P03 Implementation

## P08: Incremental Compilation (Weeks 1-5)

### Steps 1-2: Dependency Tracking + Cache All Phases
- [x] Extend `EngineState` with `engineDeps`, `engineReverseDeps`, `engineGeneration`
- [x] Extend `Query` GADT with `CanonicalizeQuery`, `TypeCheckQuery`, `OptimizeQuery`, `InterfaceQuery`
- [x] Extend `QueryResult` with real data constructors
- [x] Add `lookupQuery`, `storeQuery` to Engine
- [x] Route Driver `compileModuleCore` through cached queries

### Steps 3: Try-mark-green invalidation
- [x] Implement `invalidateAndPropagate` in Engine.hs
- [x] Early cutoff: same hash → stop propagation

### Steps 6-7: Interface Early-Cutoff + Durability
- [x] New `Query/Interface.hs` with `computeInterfaceHash`
- [x] Add `Durability` type and `cacheEntryDurability` field

### Steps 9-13: Error Recovery + File Watcher + Persistence
- [ ] Parser error recovery (partial results) — deferred, high risk
- [ ] Type checker error recovery — deferred, high risk
- [x] Stale-on-error fallback (`runQueryWithFallback`)
- [x] File watcher integration (`Watch/QueryIntegration.hs`) — in progress
- [x] Disk persistence stub (`Query/Persistence.hs`)

## P01: Capability Security (Weeks 5-6)
- [x] Allow/deny CapabilityConfig in Outline.hs
- [x] Deny-list enforcement in CapabilityEnforcement.hs
- [x] Per-dependency tracking in Manifest.hs (`PackageCapabilities`, `collectByPackage`)
- [x] `canopy audit --capabilities` command (Audit.hs)
- [x] Manifest JSON deserialization (`readManifest`, `FromJSON` instances)
- [x] New-capability-in-update detection (`Install/Changes.hs`)

## P02: TEA at Scale (Week 5)
- [x] Create Platform/Delegate.can
- [x] Expose in canopy.json

## P03: TypeScript Interop Phases 2-4 (Weeks 7-10)
- [x] Phase 2: .d.ts parser (`Generate/TypeScript/Parser.hs`)
- [x] Phase 2: FFI type validator (`FFI/TypeValidator.hs`)
- [x] Phase 2: Integration with FFI resolution (`validateFFIWithDts`)
- [x] Phase 3: Web Component generator (`Generate/JavaScript/WebComponent.hs`)
- [x] Phase 3: `_appWebComponents` field in Outline.hs
- [x] Phase 3: HTMLElementTagNameMap augmentation (`renderWebComponentTagMap`)
- [x] Phase 4: tsconfig.json paths generation (`writeTsConfig` in Output.hs)
- [ ] Phase 4: End-to-end tests
- [ ] Phase 4: Error message polish for FFI type mismatches

## Build Status
- All 3,924 tests passing
- Clean build with no warnings

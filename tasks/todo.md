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
- Build passing (4 pre-existing test failures unrelated to import changes)
- Clean build with no warnings

## Phase 5: Import Qualification
- [x] canopy-builder: Builder.hs, Builder/State.hs, Builder/Incremental.hs, Compiler/Parallel.hs, Compiler/Discovery.hs, Compiler/Cache.hs, Interface/JSON.hs, Deps/Advisory.hs, PackageCache.hs, Build/Parallel/Instrumented.hs
- [x] canopy-query: Query/Engine.hs, Query/Simple.hs, Query/Persistence.hs
- [x] canopy-core: Type/UnionFind.hs, Type/Solve.hs, Type/Constrain/Module.hs, Type/Constrain/Pattern.hs, Type/Error.hs, Type/Solve/Pool.hs, Optimize/DecisionTree.hs, Optimize/Module.hs, Optimize/Expression.hs, Optimize/Derive.hs, Optimize/Port.hs, Canonicalize/Expression.hs, Canonicalize/Environment/Foreign.hs, Canonicalize/Environment/Local.hs, Canonicalize/Module/FFI.hs, FFI/Manifest.hs, Canopy/Version.hs, Canopy/ModuleName.hs, Canopy/Data/NonEmptyList.hs, Canopy/Interface.hs, Canopy/Constraint.hs, Canopy/Package.hs, Canopy/Kernel.hs, Canopy/Data/Map/Utils.hs, Canopy/Data/Utf8/Builder.hs, Reporting/Annotation.hs, Reporting/Exit/Help.hs
- [x] canopy-terminal: Watch.hs, Deps/Diff.hs, Kit/Build.hs, Kit/Dev.hs, Develop/Socket.hs, Develop/Server.hs, Develop/Generate/Index.hs, Publish/Progress.hs, Publish/Validation.hs, Reporting/Task.hs, Test.hs, Test/Discovery.hs, Test/FFI.hs, impl/Terminal.hs, impl/Terminal/Error/Display.hs, Reporting.hs, Lint.hs, Lint/Config.hs, Lint/Fix.hs, Lint/Rules/Complexity.hs, Lint/Rules/Scope.hs, Lint/Rules/Style.hs, Lint/Rules/Imports.hs, Make/Output.hs, Deps/Registry.hs, Kit/DataLoader.hs
- [x] canopy-driver: Queries/Optimize.hs, Queries/Canonicalize/Module.hs
- [x] canopy-webidl: app/Main.hs, WebIDL/Codegen.hs, WebIDL/Fetch.hs, WebIDL/Parser.hs

## Phase 7: Let→Where Conversion
- [x] Generate/JavaScript/CodeSplit/Manifest.hs (2 conversions at function level)
- [x] Remaining let...in patterns are inside case arms (where not applicable) or parser primitives with bang patterns (semantically required)

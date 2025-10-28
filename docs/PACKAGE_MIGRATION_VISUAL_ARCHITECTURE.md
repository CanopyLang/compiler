# Package Migration Visual Architecture

This document provides visual diagrams for the elm/* to canopy/* package migration architecture.

## System Architecture Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                         USER PROJECT                                │
│                                                                      │
│  canopy.json:                                                       │
│  {                                                                   │
│    "dependencies": {                                                │
│      "direct": {                                                    │
│        "elm/core": "1.0.5"        ← OLD namespace (deprecated)     │
│        "canopy/browser": "1.0.0"  ← NEW namespace (canonical)      │
│      }                                                               │
│    }                                                                 │
│  }                                                                   │
└────────────────────┬───────────────────────────────────────────────┘
                     │
                     │ Outline.read
                     ↓
┌────────────────────────────────────────────────────────────────────┐
│                    ALIAS RESOLUTION LAYER                           │
│                                                                      │
│  Package.Alias.resolveAlias                                        │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │  Input: elm/core                                             │ │
│  │  Lookup: Map.lookup "elm/core" elmToCanopyMap               │ │
│  │  Output: canopy/core                                         │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  Result after resolution:                                           │
│  {                                                                   │
│    "canopy/core": "1.0.5"      ← Resolved from elm/core           │
│    "canopy/browser": "1.0.0"   ← Already canonical                 │
│  }                                                                   │
└────────────────────┬───────────────────────────────────────────────┘
                     │
                     │ Solver.addToApp / Solver.verify
                     ↓
┌────────────────────────────────────────────────────────────────────┐
│                    REGISTRY LOOKUP LAYER                            │
│                                                                      │
│  Registry.Migration.lookupWithFallback                             │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │  Step 1: Check cache                                         │ │
│  │    ├─ HIT: Return cached result (O(1))                       │ │
│  │    └─ MISS: Continue to Step 2                               │ │
│  │                                                                │ │
│  │  Step 2: Try primary namespace lookup                        │ │
│  │    ├─ Found in canopy registry → Return Found               │ │
│  │    └─ Not found → Continue to Step 3                         │ │
│  │                                                                │ │
│  │  Step 3: Try aliased namespace fallback                      │ │
│  │    ├─ Found → Return FoundViaAlias                           │ │
│  │    └─ Not found → Return NotFound                            │ │
│  │                                                                │ │
│  │  Step 4: Update cache with result                            │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  Registry Structure:                                                │
│  ┌────────────────────┬────────────────────────────────────────┐  │
│  │  Elm Registry      │  Canopy Registry                       │  │
│  ├────────────────────┼────────────────────────────────────────┤  │
│  │  elm/core          │  canopy/core        ← REAL PACKAGE     │  │
│  │   (alias)          │   versions: [1.0.5]                    │  │
│  │   → canopy/core    │   canonical: true                      │  │
│  ├────────────────────┼────────────────────────────────────────┤  │
│  │  elm/browser       │  canopy/browser     ← REAL PACKAGE     │  │
│  │   (alias)          │   versions: [1.0.0]                    │  │
│  │   → canopy/browser │   canonical: true                      │  │
│  └────────────────────┴────────────────────────────────────────┘  │
└────────────────────┬───────────────────────────────────────────────┘
                     │
                     │ Http.download
                     ↓
┌────────────────────────────────────────────────────────────────────┐
│                    PACKAGE STORAGE LAYER                            │
│                                                                      │
│  ~/.canopy/0.19.1/packages/                                        │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │  canopy/                                                      │ │
│  │  ├─ core/                                                     │ │
│  │  │  └─ 1.0.5/           ← REAL PACKAGE (physical files)      │ │
│  │  │     ├─ src/                                                │ │
│  │  │     ├─ canopy.json                                        │ │
│  │  │     └─ README.md                                           │ │
│  │  │                                                             │ │
│  │  └─ browser/                                                  │ │
│  │     └─ 1.0.0/           ← REAL PACKAGE (physical files)      │ │
│  │                                                                │ │
│  │  elm/                                                          │ │
│  │  ├─ core/                                                     │ │
│  │  │  └─ 1.0.5/           ← SYMLINK → ../../canopy/core/1.0.5/ │ │
│  │  │                                                             │ │
│  │  └─ browser/                                                  │ │
│  │     └─ 1.0.0/           ← SYMLINK → ../../canopy/browser/1.0.0/│ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  Benefits:                                                          │
│  - No duplication (symlinks are tiny)                              │
│  - Both elm/* and canopy/* paths work                             │
│  - Existing projects continue to work                              │
└────────────────────────────────────────────────────────────────────┘
```

## Package Resolution Flow Diagram

```
┌─────────────────────┐
│  User Types:        │
│  canopy install     │
│  elm/browser        │
└──────────┬──────────┘
           │
           ↓
┌──────────────────────────────────────────────────────────────┐
│  STEP 1: Parse Package Name                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Input: "elm/browser"                                  │ │
│  │  Parse: author="elm", project="browser"               │ │
│  │  Result: Pkg.Name "elm" "browser"                      │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────┬───────────────────────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────────────────────────────┐
│  STEP 2: Resolve Alias                                       │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Input: Pkg.Name "elm" "browser"                       │ │
│  │  Check: isElmNamespace → TRUE                          │ │
│  │  Lookup: elmToCanopyMap["elm/browser"]                │ │
│  │  Result: Pkg.Name "canopy" "browser"                   │ │
│  │  Warn: "elm/browser is deprecated, using canopy/browser"│ │
│  └────────────────────────────────────────────────────────┘ │
└──────────┬───────────────────────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────────────────────────────┐
│  STEP 3: Lookup in Registry                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Input: Pkg.Name "canopy" "browser"                    │ │
│  │  Check cache: MISS                                      │ │
│  │  Try canopy registry:                                   │ │
│  │    ├─ Found: "canopy/browser"                          │ │
│  │    └─ Versions: ["1.0.0", "1.0.1"]                     │ │
│  │  Result: Found (canonical)                              │ │
│  │  Update cache: canopy/browser → Found                  │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────┬───────────────────────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────────────────────────────┐
│  STEP 4: Download Package                                    │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Package: canopy/browser@1.0.1                         │ │
│  │  URL: https://registry.canopy.dev/canopy/browser/1.0.1.zip│ │
│  │  Download to: ~/.canopy/packages/canopy/browser/1.0.1/│ │
│  │  Create symlink:                                        │ │
│  │    ~/.canopy/packages/elm/browser/1.0.1/ →            │ │
│  │    ~/.canopy/packages/canopy/browser/1.0.1/           │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────┬───────────────────────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────────────────────────────┐
│  STEP 5: Update canopy.json                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Read: canopy.json                                     │ │
│  │  Add: "canopy/browser": "1.0.1"  (canonical name!)    │ │
│  │  Save: canopy.json                                     │ │
│  │  Notify: "Installed canopy/browser 1.0.1"             │ │
│  │         "(elm/browser is an alias)"                    │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## Dependency Resolution State Machine

```
                     ┌─────────────────────┐
                     │  Parse canopy.json  │
                     │  Dependencies       │
                     └──────────┬──────────┘
                                │
                                ↓
                ┌───────────────────────────────┐
                │  For each dependency:         │
                │  - elm/core: 1.0.5           │
                │  - canopy/browser: 1.0.0     │
                │  - author/package: 2.0.0     │
                └───────────────┬───────────────┘
                                │
                                ↓
         ┌──────────────────────────────────────────┐
         │  Is package in elm/* or                  │
         │  elm-explorations/* namespace?           │
         └─────────────┬────────────────────────────┘
                       │
              ┌────────┴────────┐
              │                 │
             YES               NO
              │                 │
              ↓                 ↓
   ┌──────────────────┐   ┌──────────────────┐
   │  Resolve alias:  │   │  Use as-is       │
   │  elm/core →      │   │  (third-party    │
   │  canopy/core     │   │   or already     │
   │                  │   │   canonical)     │
   └─────────┬────────┘   └────────┬─────────┘
             │                     │
             │ Emit deprecation    │ No warning
             │ warning            │
             │                     │
             └──────────┬──────────┘
                        │
                        ↓
         ┌──────────────────────────────────┐
         │  Collect resolved dependencies:  │
         │  - canopy/core: 1.0.5           │
         │  - canopy/browser: 1.0.0        │
         │  - author/package: 2.0.0        │
         └─────────────┬────────────────────┘
                       │
                       ↓
         ┌──────────────────────────────────┐
         │  Check for duplicate canonical   │
         │  names (security check)          │
         └─────────────┬────────────────────┘
                       │
              ┌────────┴────────┐
              │                 │
         DUPLICATES           NO DUPLICATES
              │                 │
              ↓                 ↓
   ┌──────────────────┐   ┌──────────────────┐
   │  ERROR:          │   │  Proceed to      │
   │  Duplicate       │   │  constraint      │
   │  package         │   │  solving         │
   │  detected        │   │                  │
   └──────────────────┘   └────────┬─────────┘
                                   │
                                   ↓
                     ┌─────────────────────────┐
                     │  Solve constraints and  │
                     │  install packages       │
                     └─────────────────────────┘
```

## Cache Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                        CACHE HIERARCHY                          │
│                                                                  │
│  Level 1: In-Memory Alias Map (Immutable)                      │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  elmToCanopyMap :: Map Pkg.Name Pkg.Name                   ││
│  │  ┌──────────────────────────────────────────────────────┐  ││
│  │  │  elm/core         → canopy/core                       │  ││
│  │  │  elm/browser      → canopy/browser                    │  ││
│  │  │  elm/html         → canopy/html                       │  ││
│  │  │  elm/json         → canopy/json                       │  ││
│  │  │  ...                                                   │  ││
│  │  └──────────────────────────────────────────────────────┘  ││
│  │  Loaded: At startup                                        ││
│  │  Lookup: O(1) hash map                                     ││
│  │  Size: ~20 entries (~2KB)                                  ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ↓                                  │
│  Level 2: Registry Lookup Cache (Mutable)                      │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  lookupCache :: Map Pkg.Name LookupResult                  ││
│  │  ┌──────────────────────────────────────────────────────┐  ││
│  │  │  elm/core    → FoundViaAlias(elm/core, canopy/core)  │  ││
│  │  │  canopy/core → Found(canopy/core)                     │  ││
│  │  │  author/pkg  → Found(author/pkg)                      │  ││
│  │  │  ...                                                   │  ││
│  │  └──────────────────────────────────────────────────────┘  ││
│  │  Loaded: On-demand (populated during lookups)             ││
│  │  Lookup: O(1) hash map                                     ││
│  │  Size: ~100 entries per project (~10KB)                    ││
│  │  Persistence: Optional (can save to disk)                  ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ↓                                  │
│  Level 3: Package File Cache (Disk)                            │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  ~/.canopy/0.19.1/packages/                                ││
│  │  ┌──────────────────────────────────────────────────────┐  ││
│  │  │  canopy/core/1.0.5/    ← Real files                  │  ││
│  │  │  elm/core/1.0.5/       ← Symlink                     │  ││
│  │  │  ...                                                   │  ││
│  │  └──────────────────────────────────────────────────────┘  ││
│  │  Loaded: On package install                                ││
│  │  Lookup: O(1) filesystem                                    ││
│  │  Size: ~100MB per project                                   ││
│  │  Persistence: Always on disk                                ││
│  └────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────┘

Cache Hit Rates (Expected):
┌──────────────────────────────────────────────────────────────┐
│  Scenario              │ L1 Hit │ L2 Hit │ L3 Hit │ Miss    │
├────────────────────────┼────────┼────────┼────────┼─────────┤
│  First build (cold)    │  100%  │   0%   │   0%   │  100%   │
│  Second build (warm)   │  100%  │  100%  │  100%  │   0%    │
│  After cache clear     │  100%  │   0%   │  100%  │   0%    │
│  New package install   │  100%  │   0%   │   0%   │  100%   │
└──────────────────────────────────────────────────────────────┘
```

## Migration Timeline Visual

```
                    PACKAGE MIGRATION TIMELINE

┌───────────────────────────────────────────────────────────────┐
│                                                                 │
│  PHASE 1: SOFT LAUNCH (Months 0-3)                            │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Version: 0.19.2                                        │  │
│  │  Status: Aliasing enabled, soft warnings               │  │
│  │  ┌─────────────────────────────────────────────────────┐│  │
│  │  │ ✅ Both elm/* and canopy/* work                     ││  │
│  │  │ ⚠️  Soft deprecation warnings for elm/*            ││  │
│  │  │ 📝 Documentation published                          ││  │
│  │  │ 🛠️ Migration tool available                         ││  │
│  │  └─────────────────────────────────────────────────────┘│  │
│  └─────────────────────────────────────────────────────────┘  │
│                          │                                     │
│                          ↓                                     │
│  PHASE 2: ENCOURAGED MIGRATION (Months 3-6)                   │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Version: 0.19.x                                        │  │
│  │  Status: Strong encouragement to migrate               │  │
│  │  ┌─────────────────────────────────────────────────────┐│  │
│  │  │ ✅ Both namespaces still work                       ││  │
│  │  │ ⚠️  ⚠️  Stronger warnings (every build)             ││  │
│  │  │ 📊 Migration statistics published                   ││  │
│  │  │ 🎯 Community packages encouraged to migrate        ││  │
│  │  └─────────────────────────────────────────────────────┘│  │
│  └─────────────────────────────────────────────────────────┘  │
│                          │                                     │
│                          ↓                                     │
│  PHASE 3: DEFAULT CANOPY (Months 6-9)                         │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Version: 0.20.0                                        │  │
│  │  Status: elm/* disabled by default                     │  │
│  │  ┌─────────────────────────────────────────────────────┐│  │
│  │  │ ✅ canopy/* works                                    ││  │
│  │  │ ⚠️  elm/* requires --allow-elm-namespace flag      ││  │
│  │  │ 📢 Final migration notice                           ││  │
│  │  │ 🚨 Breaking change in 3 months                      ││  │
│  │  └─────────────────────────────────────────────────────┘│  │
│  └─────────────────────────────────────────────────────────┘  │
│                          │                                     │
│                          ↓                                     │
│  PHASE 4: COMPLETE DEPRECATION (Month 12+)                    │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Version: 0.21.0                                        │  │
│  │  Status: elm/* namespace removed                       │  │
│  │  ┌─────────────────────────────────────────────────────┐│  │
│  │  │ ✅ canopy/* works                                    ││  │
│  │  │ ❌ elm/* compile-time error                         ││  │
│  │  │ 🎉 Migration complete                               ││  │
│  │  │ 📚 Historical documentation archived                ││  │
│  │  └─────────────────────────────────────────────────────┘│  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
└───────────────────────────────────────────────────────────────┘

Target Adoption Rates:
Month 3:  30% using canopy/*
Month 6:  50% using canopy/*
Month 9:  70% using canopy/*
Month 12: 95% using canopy/*
```

## Error Handling Flow

```
┌───────────────────────────────────────────────────────────────┐
│              PACKAGE LOOKUP ERROR HANDLING                     │
└───────────────────────────────────────────────────────────────┘

Request: elm/nonexistent@1.0.0
    ↓
┌───────────────────────────────────────────────────────────────┐
│ Step 1: Parse package name                                     │
│   Result: Pkg.Name "elm" "nonexistent"                        │
└────────────────────┬──────────────────────────────────────────┘
                     ↓
┌───────────────────────────────────────────────────────────────┐
│ Step 2: Resolve alias                                          │
│   Input: elm/nonexistent                                       │
│   Check: isElmNamespace → TRUE                                │
│   Lookup: elmToCanopyMap["elm/nonexistent"] → NOT FOUND       │
│   Result: canopy/nonexistent (automatic conversion)            │
└────────────────────┬──────────────────────────────────────────┘
                     ↓
┌───────────────────────────────────────────────────────────────┐
│ Step 3: Try registry lookup                                    │
│   Primary: canopy/nonexistent → NOT FOUND                     │
│   Fallback: elm/nonexistent → NOT FOUND                       │
│   Result: NotFound                                              │
└────────────────────┬──────────────────────────────────────────┘
                     ↓
┌───────────────────────────────────────────────────────────────┐
│ Step 4: Generate helpful error                                 │
│                                                                 │
│   -- PACKAGE NOT FOUND elm/nonexistent                        │
│                                                                 │
│   I could not find package 'elm/nonexistent' in the registry. │
│                                                                 │
│   The elm/* namespace is deprecated. Did you mean one of:     │
│     - canopy/core                                              │
│     - canopy/browser                                           │
│     - canopy/html                                              │
│                                                                 │
│   View all packages: https://canopy.dev/packages              │
│                                                                 │
│   Hint: The elm/* namespace is deprecated. Use canopy/*       │
└───────────────────────────────────────────────────────────────┘
```

## Security Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     SECURITY LAYERS                             │
│                                                                  │
│  Layer 1: Namespace Reservation                                 │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  Reserved Namespaces:                                       ││
│  │  ┌──────────────────────────────────────────────────────┐  ││
│  │  │  canopy/*                → Official packages          │  ││
│  │  │  canopy-explorations/*   → Experimental packages      │  ││
│  │  │  elm/*                   → Legacy (read-only)         │  ││
│  │  │  elm-explorations/*      → Legacy (read-only)         │  ││
│  │  └──────────────────────────────────────────────────────┘  ││
│  │  Protection: Registry-level validation                      ││
│  │  Result: Prevents package squatting                         ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ↓                                  │
│  Layer 2: Duplicate Detection                                   │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  Check for duplicate canonical names after alias resolution ││
│  │  ┌──────────────────────────────────────────────────────┐  ││
│  │  │  Input: [elm/core, canopy/core, author/package]     │  ││
│  │  │  Resolve: [canopy/core, canopy/core, author/package]│  ││
│  │  │  Detect: DUPLICATE canopy/core                       │  ││
│  │  │  Error: DuplicatePackageError                        │  ││
│  │  └──────────────────────────────────────────────────────┘  ││
│  │  Protection: Prevents dependency confusion                   ││
│  │  Result: Only one version of each package                    ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ↓                                  │
│  Layer 3: Cryptographic Verification                            │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  Verify registry responses with signatures                  ││
│  │  ┌──────────────────────────────────────────────────────┐  ││
│  │  │  Registry Response:                                   │  ││
│  │  │  {                                                     │  ││
│  │  │    "data": { ... },                                   │  ││
│  │  │    "signature": "a1b2c3...",                          │  ││
│  │  │    "public_key": "official-canopy-key"               │  ││
│  │  │  }                                                     │  ││
│  │  │  Verify: signature matches data + public_key          │  ││
│  │  └──────────────────────────────────────────────────────┘  ││
│  │  Protection: Prevents registry tampering                    ││
│  │  Result: Trustworthy alias mappings                          ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ↓                                  │
│  Layer 4: Audit Logging                                         │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  Log all alias resolutions and package installations        ││
│  │  ┌──────────────────────────────────────────────────────┐  ││
│  │  │  Log Entry:                                           │  ││
│  │  │  {                                                     │  ││
│  │  │    "timestamp": "2025-10-27T10:00:00Z",              │  ││
│  │  │    "action": "alias_resolution",                      │  ││
│  │  │    "input": "elm/core",                               │  ││
│  │  │    "output": "canopy/core",                           │  ││
│  │  │    "project": "/path/to/project"                      │  ││
│  │  │  }                                                     │  ││
│  │  └──────────────────────────────────────────────────────┘  ││
│  │  Protection: Forensics and debugging                        ││
│  │  Result: Traceable package operations                        ││
│  └────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────┘
```

## Performance Optimization Flow

```
┌────────────────────────────────────────────────────────────────┐
│              PERFORMANCE OPTIMIZATION STRATEGY                  │
│                                                                  │
│  Cold Start (First Build)                                       │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  1. Load alias config from disk (1ms)                      ││
│  │     └→ Parse alias-config.json                             ││
│  │                                                              ││
│  │  2. Parse canopy.json (5ms)                                ││
│  │     └→ Read project dependencies                           ││
│  │                                                              ││
│  │  3. Resolve aliases (0.1ms per dep)                        ││
│  │     └→ O(1) hash map lookup per dependency                 ││
│  │                                                              ││
│  │  4. Registry lookup (100ms per package)                    ││
│  │     ├→ Check cache: MISS                                   ││
│  │     ├→ Try primary namespace                               ││
│  │     ├→ Try fallback namespace                              ││
│  │     └→ Update cache                                        ││
│  │                                                              ││
│  │  5. Download packages (1s per package)                     ││
│  │     └→ HTTP download + extract                             ││
│  │                                                              ││
│  │  Total: ~10s for 10 packages                               ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ↓                                  │
│  Warm Build (Subsequent Builds)                                 │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  1. Load alias config from memory (<1ms)                   ││
│  │     └→ Already loaded, no disk I/O                         ││
│  │                                                              ││
│  │  2. Parse canopy.json (5ms)                                ││
│  │     └→ Same as cold start                                  ││
│  │                                                              ││
│  │  3. Resolve aliases (0.1ms per dep)                        ││
│  │     └→ Same as cold start                                  ││
│  │                                                              ││
│  │  4. Registry lookup (1ms per package)                      ││
│  │     ├→ Check cache: HIT!                                   ││
│  │     └→ Return cached result                                ││
│  │                                                              ││
│  │  5. Skip download (packages already cached)                ││
│  │     └→ Verify existence on disk (1ms)                      ││
│  │                                                              ││
│  │  Total: ~10ms for 10 packages                              ││
│  │  Speedup: 1000x faster!                                    ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Key Optimizations:                                              │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  1. Alias map loaded once at startup                       ││
│  │  2. Registry results cached to disk                        ││
│  │  3. Package files cached locally                           ││
│  │  4. No redundant alias resolutions                          ││
│  │  5. Symlinks for elm/* (no duplication)                    ││
│  └────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────┘
```

## Code Integration Points

```
┌────────────────────────────────────────────────────────────────┐
│                  CODE INTEGRATION MAP                           │
│                                                                  │
│  Canopy.Outline (Outline reading)                              │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  BEFORE:                                                    ││
│  │  read :: FilePath -> IO (Maybe Outline)                    ││
│  │  read root = do                                             ││
│  │    content <- readFile (root </> "canopy.json")            ││
│  │    pure (Json.decode content)                               ││
│  │                                                              ││
│  │  AFTER:                                                     ││
│  │  read :: FilePath -> IO (Maybe Outline)                    ││
│  │  read root = do                                             ││
│  │    content <- readFile (root </> "canopy.json")            ││
│  │    outline <- Json.decode content                           ││
│  │    pure (resolveDependencies outline)  ← NEW               ││
│  │                                                              ││
│  │  resolveDependencies :: Outline -> Outline                  ││
│  │  resolveDependencies (App outline) =                        ││
│  │    let deps = Map.mapKeys Alias.resolveAlias (_appDeps outline)│
│  │    in App (outline { _appDeps = deps })                    ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ↓                                  │
│  Deps.Registry (Registry lookup)                                │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  BEFORE:                                                    ││
│  │  lookup :: Registry -> Pkg.Name -> Maybe Versions          ││
│  │  lookup registry name =                                     ││
│  │    Map.lookup name (_registryPackages registry)            ││
│  │                                                              ││
│  │  AFTER:                                                     ││
│  │  lookup :: MigrationRegistry -> Pkg.Name -> IO LookupResult││
│  │  lookup registry name = do                                  ││
│  │    Migration.lookupWithFallback registry name  ← NEW       ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ↓                                  │
│  Deps.Solver (Dependency solving)                               │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  BEFORE:                                                    ││
│  │  addToApp :: ... -> Pkg.Name -> ... -> IO Result           ││
│  │  addToApp cache conn registry name outline = do            ││
│  │    solve name outline                                       ││
│  │                                                              ││
│  │  AFTER:                                                     ││
│  │  addToApp :: ... -> Pkg.Name -> ... -> IO Result           ││
│  │  addToApp cache conn registry name outline = do            ││
│  │    let resolved = Alias.resolveAlias name  ← NEW           ││
│  │    warnIfDeprecated name resolved           ← NEW           ││
│  │    solve resolved outline                                   ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                  │
│                              ↓                                  │
│  Install.hs (Package installation)                              │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  BEFORE:                                                    ││
│  │  install :: Pkg.Name -> IO ()                              ││
│  │  install name = do                                          ││
│  │    download name                                            ││
│  │    updateOutline name                                       ││
│  │                                                              ││
│  │  AFTER:                                                     ││
│  │  install :: Pkg.Name -> IO ()                              ││
│  │  install name = do                                          ││
│  │    let canonical = Alias.resolveAlias name  ← NEW          ││
│  │    download canonical                                       ││
│  │    createSymlinkIfNeeded name canonical     ← NEW           ││
│  │    updateOutline canonical                  ← CHANGED       ││
│  │    warnIfDeprecated name canonical          ← NEW           ││
│  └────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────┘
```

This visual architecture document complements the main architecture document with diagrams showing the system flow, data structures, and integration points.

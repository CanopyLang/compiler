# Canopy version-resolution policy

> Best-practice: **ranges in source, latest-installed wins for `canopy/*`, `elm/*`
> stays a frozen baseline, exact in the lock for reproducibility.**

This document is the source of truth for how the Canopy compiler resolves dependency
versions, why it works that way, and what you do when you want to bump a package.

## TL;DR

- **`elm/*` deps are a frozen baseline.** `elm/core 1.0.5`, `elm/time`, `elm/url`,
  `elm/json`, etc. stay **exactly pinned** and resolve only under the `elm` author. They
  are the stable language substrate and carry no Canopy FFI.
- **`canopy/*` deps float to the latest installed version in their major range.** An app
  that pins `canopy/core 1.0.0` (or declares the range `1.0.0 <= v < 2.0.0`) automatically
  uses the highest installed `1.x` — so improving `canopy/core`, `canopy/virtual-dom`,
  `canopy/html`, or `canopy/json` flows to every app **without hand-editing pins**.
- **The forked FFI set hard-errors instead of silently degrading.** If a `canopy/core`,
  `canopy/virtual-dom`, `canopy/html`, or `canopy/json` is missing, the build fails
  **loudly at resolve time** instead of silently loading the FFI-less `elm/*` namesake
  (the old "Missing global VirtualDomFFI.init" trap).
- **`canopy.lock` is authoritative for reproducible builds.** A committed, current lock
  produces byte-identical builds across machines; absent/stale, the build re-solves
  latest-wins.

## The two namespaces

| Namespace      | Resolution                                  | Why                                         |
| -------------- | ------------------------------------------- | ------------------------------------------- |
| `elm/*`        | **Exact pin**, `elm` author only            | Frozen language baseline, no Canopy FFI     |
| `canopy/*`     | **Latest installed in the pin's major range** | Canopy fork; improvements flow automatically |

"Major range" of a pin `M.m.p` means `M.m.p <= v < (M+1).0.0` (`Constraint.untilNextMajor`).
The resolver (`PackageCache.resolveInstalledVersion`) scans the installed cache
(`~/.canopy/packages`, `~/.elm/0.19.1/packages`) and returns the **highest** installed
version satisfying that range, preferring a version installed under the package's own
author (a `canopy link`ed source tree) over a fallback copy.

This policy is applied identically to **apps** and **packages** (one monorepo, one policy):

- Apps: `Compiler.resolveOutlineDeps` (the build path) and `Test.Compile.resolveRootDeps`
  (the `canopy test` path) resolve each `canopy/*` pin in the app's
  `dependencies-direct` / `dependencies-indirect` / `test-dependencies-direct` maps via
  the major range; `elm/*` (and any non-canopy author) stays exactly pinned.
- Packages: their `dependencies` constraints resolve against the installed cache the same
  way.

## The forked set (`Package.isCanopyFork`)

The genuinely Canopy-**forked** packages — the ones that ship native FFI / behavioural
divergence from their Elm namesakes — are:

```
canopy/core   canopy/virtual-dom   canopy/html   canopy/json
```

For these, a missing install is a **hard, actionable error** at resolve time:

```
No installed canopy/virtual-dom satisfies 1.0.0 <= v < 2.0.0; installed: 1.0.3, 1.0.4.
Install/rebuild it (e.g. `canopy cache rebuild`) — Canopy will not silently fall back to
the FFI-less elm/virtual-dom.
```

The `canopy -> elm` fallback **direction is suppressed** for the forked set everywhere it
mattered (`resolveInstalledVersion`, `installedVersionsTagged`, `packageArtifactPaths`,
`scanForCompatibleVersionWith`), so a `canopy/virtual-dom` request can never resolve to
`elm/virtual-dom`.

> **Why not kill the fallback wholesale?** `canopy/browser`, `canopy/time`, and
> `canopy/url` are **not** forked — they exist only under `~/.elm`. Killing the fallback
> for them would break every app. The loud-error / no-fallback behaviour is therefore
> **scoped** to the forked FFI set; browser/time/url keep the `canopy <-> elm` fallback.

## How to improve a `canopy/*` package (the common case)

You should **never hand-edit app pins** for an ordinary improvement. Instead:

1. Bump the version in the package's own `canopy.json` (e.g. `canopy/core 1.1.0 -> 1.2.0`).
2. Rebuild its artifacts so the new version's `artifacts.dat` exists under the current
   compiler (see *Rebuilding artifacts* below).
3. Done. Every app and test picks up the new `1.x` automatically on the next build,
   because they resolve `canopy/core` to the highest installed `1.x`.

### When DO you bump an app's range?

**Only on a `canopy/*` MAJOR bump** (e.g. `canopy/core 1.x -> 2.0.0`). That is the single
intended one-line edit: change the app's `canopy/core` range floor to `2.0.0 <= v < 3.0.0`
(or pin `2.0.0`). A major bump is a deliberate breaking change, so making it an explicit
opt-in per app is correct.

## Scaffolding

`canopy init` scaffolds an app's `canopy/*` dependencies as **ranges**
(`"canopy/core": "1.0.0 <= v < 2.0.0"`, …) so fresh apps float to the latest installed
`1.x` out of the box. `Setup.standardPackages` (what `canopy setup` pre-fetches) lists the
concrete versions; the two are kept consistent by
`Unit.Terminal.ScaffoldVersionGolden` (a property test, not a hardcoded version list).

The app outline (`Canopy.Outline.AppOutline`) parses `direct` / `indirect` dependency
specs as **either a range or a bare version** and round-trips ranges verbatim through
`toJSON . parseJSON`, so `canopy install` does not rewrite a declared range back to an
exact pin. The resolution **floor** stored for each dep is the constraint's lower bound.

## Reproducibility (`canopy.lock`)

"Ranges in source, exact in lock" — the Cargo / npm / Elm-Solver model.

- **DEV mode** (linked monorepo, no lock, or `--latest`): `resolveInstalledVersion` picks
  the highest installed `canopy/*` (linked HEAD wins via the primary-author preference).
  Improvements flow with zero pin edits.
- **PUBLISHED / CI mode** (committed, current `canopy.lock`): the build reads the lock's
  **exact** versions verbatim and is byte-identical across machines regardless of what
  else is installed.

### Status of the lock wiring

- **Lock read is authoritative (implemented).** `Compiler.loadDependencyArtifacts` reads
  `canopy.lock` via `readCurrentLock`; when the lock is present **and** current
  (`LockFile.isLockFileCurrent` — its root hash matches `canopy.json`), each dependency's
  exact recorded version (`_lpVersion`) is used verbatim and the latest-wins solve is
  bypassed for that package. An absent or stale lock yields an empty map, so the build
  re-solves latest-wins.
- **Lock write-back on `canopy install` (existing).** `canopy install`
  (`Install/Execution.hs`) already generates `canopy.lock` from the resolved set.

### Deferred: build-time write-back

Writing the lock back during a plain `canopy make` (when the lock is absent/stale) is
**deferred** to avoid a filesystem side-effect on every build of an unlocked project
(which the compiler test fixtures rely on). Precise remaining wiring if/when desired:

1. In `Compiler.loadDependencyArtifacts`, after resolving the App deps with an empty
   `locked` map, call `LockFile.generateLockFile root resolvedMap` (where `resolvedMap` is
   the `Map Pkg.Name Version.Version` of chosen versions) — guarded by a flag so it only
   fires for an explicit `canopy make --latest` / first build, never for read-only or
   fixture builds.
2. Thread a `--latest` flag from `Make.Flags` down to `loadDependencyArtifacts` so the
   re-solve-and-relock is opt-in.
3. `Test.Compile.resolveRootDeps` is **not** lock-aware; its job is to ensure each
   test-dep package's `artifacts.dat` exists, and the actual interface load for the test
   build still flows through the lock-aware `Compiler.loadDependencyArtifacts`. If you want
   `canopy test` itself to honour a lock for the ensure-artifacts pass, thread the same
   `readCurrentLock` map into `resolveRootDeps`.

Until the build-time write-back lands, the reproducible-build story is: **run
`canopy install` to (re)solve and write `canopy.lock`, commit it, and CI builds become
byte-identical** because the lock read is authoritative.

## Rebuilding artifacts after a bump (hard prerequisite)

`artifacts.dat` is gated by a 12-byte header (magic `CART` + schema version + compiler
major/minor/patch). `decodeVersionedArtifacts` returns `Nothing` unless the schema **and**
compiler version match exactly. So after you bump a `canopy/*` package **or** the compiler,
the chosen version's artifacts must be rebuilt, or resolution silently drops the dep and
you get a fresh "missing global".

Rebuild every installed `canopy/*` package's `artifacts.dat` (and the `elm/core 1.0.5`
baseline if its header mismatches) under the current compiler after:

- bumping any `canopy/*` package version, or
- bumping the compiler.

> A first-class `canopy cache rebuild` terminal subcommand wrapping this logic is the
> intended ergonomic entry point; until it ships, rebuild via the same package-build path
> `canopy test` / `canopy install` use (delete the stale `artifacts.dat` first so the CART
> header is rewritten with the running compiler version).

### Open problem: a compiler SOURCE change at the same version does not invalidate artifacts (DEFERRED)

The CART header (`PackageCache.encodeVersionedArtifacts` /
`decodeVersionedArtifacts`) keys staleness on the schema version **plus the compiler
`Version.compiler` (major.minor.patch = `0.19.1`) only**. A change to compiler SOURCE that
alters the shape or content of a package artifact — e.g. a codegen change, a new
`Interface`/`Opt.GlobalGraph` field, a different optimizer pass — but does **not** bump
`Version.compiler` produces a header that still says `0.19.1`. So `decodeVersionedArtifacts`
**accepts** an artifact built by an OLDER compiler binary, loads it under the new schema,
and that stale/incomplete graph silently breaks `canopy make` with the
"Missing global …" / "I could not find a `Platform.Sub` module to import!" class of error.

#### Why the obvious fix (add a build/content hash) is NOT shipped as-is

The clean fix is to bake a **compiler build/content hash** into the CART header (alongside
the version) and treat a hash MISMATCH as "stale". That detection is a ~10-line change. The
problem is the **load path has no auto-rebuild**, so flipping detection on with the existing
on-disk artifacts (built by the prior binary, so a guaranteed hash mismatch) would RED the
whole suite. This was verified empirically: bumping `artifactSchemaVersion` (which forces
the exact same mismatch a content hash would) and rebuilding the binary makes a plain
`canopy make` against `canopy/core` fail with **"I could not find a `Platform.Sub` module to
import!"** — the artifact is NOT recompiled, it is silently skipped:

- `PackageCache.loadAllPackageArtifacts` → `loadDep` returns `[]` on any load failure
  ("Silently skip packages that fail to load"); `loadDepsFromList`
  (`Compiler.hs`) then substitutes `(Map.empty, Opt.empty, Map.empty)` — **empty interfaces,
  no rebuild**.
- `Setup.LocalCompilation.compilePackageVersion` only rebuilds when the `artifacts.dat`
  **file is absent**; it does **not** validate the CART header, so a stale-but-present
  artifact is reported `ready` and never regenerated.

So a content hash without a rebuild path is a half-working invalidation that reds the suite —
exactly what must not ship.

#### Precise remaining wiring for safe, self-healing invalidation

1. **Bake a compiler build hash.** Add `Version.compilerBuildHash :: BS.ByteString` (or a
   short `Word64`), generated at build time — e.g. a Template Haskell splice over the hash of
   the codegen/interface source set, or a value injected by the build via
   `gitDescribe`/`Paths_*`. Encode it into the CART header in
   `encodeVersionedArtifacts` (bump `artifactSchemaVersion` to 3 and widen the
   ≥-length guard / `decodeWord16At` offsets accordingly) and compare it in
   `decodeVersionedArtifacts` (return `Nothing` on mismatch, same as a version mismatch).

2. **Make load failure trigger a SOURCE rebuild instead of empty substitution.** The
   layering blocker: the package compiler lives in `canopy-terminal`
   (`Setup.LocalCompilation.compilePackageVersion`) but the failing load is in
   `canopy-builder` (`PackageCache.loadDep`), and `canopy-builder` must not depend on
   `canopy-terminal`. Two ways to break the cycle:
   - **(a) Pre-pass validation (lowest risk).** Before any build/test resolves deps, run a
     pass that, for every installed `canopy/*` version, reads ONLY the CART header
     (`decodeVersionedArtifacts` returning `Nothing` ⇒ stale) and, when stale, **deletes the
     `artifacts.dat` and recompiles from `src/`** via the existing
     `compilePackageVersion` (which already rebuilds on absence). Hook this into the same
     entry points that today guarantee artifacts exist (`canopy setup`, and the
     `Test.Compile`/`Make` pre-build ensure-artifacts step). Net effect: a stale artifact is
     turned into an absent one, and the existing "absent ⇒ rebuild" path heals it.
   - **(b) Inject a rebuild callback.** Give `loadAllPackageArtifacts` an
     `(author -> project -> version -> IO ())` rebuild hook supplied by `canopy-terminal`, so
     `loadDep` can, on a CART-mismatch (distinguish it from "file missing" via a new
     `VersionedStale` result threaded out of `tryVersionedAsResult`), invoke the rebuild and
     retry the load once. More surgical but touches the hot load path and concurrency
     (`mapConcurrently`), so it carries more suite risk than (a).

3. **Distinguish "stale CART" from "not this format" at the loader.** Today
   `decodeVersionedArtifacts` collapses version/schema mismatch into the same `Nothing` that
   means "try the legacy decoders". A CART file whose magic matches but whose
   version/hash does not should **not** fall through to `tryDecodeAs (LegacyArtifactCache …)`
   (those re-read the CART bytes under a wrong schema and either fail or, worse, succeed with
   garbage). Return a dedicated `Stale` signal from the versioned decoder and have
   `loadArtifactsFile` / `loadCompleteArtifactsFile` short-circuit to "needs rebuild" rather
   than continuing down the legacy list.

4. **Keep the suite green.** The decisive constraint: the test fixtures load **pre-built**
   `artifacts.dat`. Whichever of (a)/(b) is chosen MUST run before the first dep load in the
   `stack test` path (the integration tests shell out to the real `canopy` binary), so the
   first stale load self-heals transparently. Validate by bumping the build hash, rebuilding,
   and running `stack test canopy:canopy-test` — it must stay green by rebuilding the package
   artifacts on first use, not by skipping the check.

Until this lands, the operational rule stands: **after a compiler source change that affects
package artifacts, rebuild the installed `canopy/*` `artifacts.dat` (delete + recompile) the
same way a version bump requires** — the version-only CART header will not do it for you.

## Summary of the resolver code paths

| Concern                                | Location                                                     |
| -------------------------------------- | ----------------------------------------------------------- |
| Fork-set identity                      | `Canopy.Package.isCanopyFork`                                |
| App + package dep resolution (build)   | `Compiler.resolveOutlineDeps`                                |
| App + package dep resolution (test)    | `Test.Compile.resolveRootDeps`                              |
| Latest-installed-in-range resolution   | `PackageCache.resolveInstalledVersion` / `…In`              |
| Loud error + scoped no-fallback        | `PackageCache.resolveInstalledVersion`, `installedVersionsTagged`, `packageArtifactPaths`, `scanForCompatibleVersionWith` |
| Lock-authoritative read                | `Compiler.readCurrentLock` + `Builder.LockFile`             |
| Range scaffolding                      | `New.canopyJsonContent`, `Setup.standardPackages`           |
| App-outline range round-trip           | `Canopy.Outline` (`AppOutline` `ToJSON`/`FromJSON`)         |
